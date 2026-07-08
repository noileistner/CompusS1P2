LIST P=PIC18F4321    F=INHX32   
    #include <p18f4321.inc> 
    CONFIG  OSC=INTIO2; Internal oscillator @ 16MHz 
    CONFIG  PBADEN=DIG ; PORTB = DIGital 
    CONFIG  WDT=OFF    ; Watch Dog Timer Deactivated 
    CONFIG MCLRE = OFF ; Makes RA3 usable

    ORG 0x0000 
    GOTO    MAIN 
    ORG     0x0008  
    GOTO    HIGH_ISR
    ORG     0x0018  
    RETFIE  FAST 

; ######################### --- VARS --- ######################### 
MENU_ID         EQU 0x20    ;Menu[2..0]
    
DEBOUNCE_TIMER  EQU 0x21    ;count for debouning timer
DEBOUNCE_INNER	EQU 0x22
BTN_STATE       EQU 0x23    ; pressed or not

RNG_SEED        EQU 0x24    ; running LFSR state
RANDOM_NUM      EQU 0x25    ; latest generated 4-bit number (0-15)
RNG_COUNTER     EQU 0x26    ; garbage
GAME_ACTIVE	EQU 0x27    ; active or not
RA4_PREV	EQU 0x28    ; newNum btn state
TOKENS		EQU 0x29    ; max 5
GAME_2SEC_TIMER EQU 0x2A    ;		
		
PULSE_STATE     EQU 0x30
PULSE_START_L   EQU 0x31
PULSE_START_H   EQU 0x32
TEMP_L		EQU 0x33
TEMP_H		EQU 0x34
		    
		
QTICK_CNT       EQU 0x40    ; counts 0-3 (quarter-ms subticks)
MS_TICKS_L      EQU 0x41    ; free-running quarter-ms counter, low byte
MS_TICKS_H      EQU 0x42    ; free-running quarter-ms counter, high byte
MS_TICK_FLAG	EQU 0x43    ; flag 

    
; ######################### --- INITS --- #########################   
INIT_OSC   ; Configure the microcontroller 
   MOVLW   b'01110000'      ;32MHz fosc
   MOVWF   OSCCON,0  
    
   MOVLW   b'01000000'	;PLLEN on 8x4
   MOVWF   OSCTUNE,0
   RETURN 
   
INIT_PORTS
   BCF	    TRISC,3,0	;RC3 output
   
   ;RGB
   BCF	    TRISC,5,0	;RC5 output
   BCF	    TRISC,6,0	;RC6 output
   BCF	    TRISC,7,0	;RC7 output 
   CLRF	    TRISC, 0	;All off
   
   ;PB
   BSF	    TRISB,0,0	;RB1 in
   BSF	    TRISB,1,0	;RB1 in
   BSF	    TRISB,2,0	;RB2 in
   BSF	    TRISB,3,0	;RB3 in
   BCF      INTCON2, RBPU,0   ; enable PORTB pull-ups
   
   ;7seg
   CLRF     TRISD,0    ; PORTD configured completely as outputs for 7-Segment Displ
   CLRF     LATD,0     ; Clear 7-Segment outputs on boot
   
   ;game 
   BCF	    TRISA,6,0	;ra6 OUT = RanGen
   BCF	    TRISA,0,0	;ran num bin OUT
   BCF	    TRISA,1,0	;
   BCF	    TRISA,2,0	;
   BCF	    TRISA,3,0	;ran num bin OUT
   SETF     ADCON1,0   ; Make all pins digital
   BSF	    TRISA,4,0	;ra4 in newnum
   BSF	    TRISA,5,0	;ra5 in playing (stop gen)
   BSF	    TRISB,4,0	;rB4 in resPulse (idk)	NEG LOGIC
  
   RETURN
   
INIT_MENU
  
   MOVLW    0x01    ;init state
   MOVWF    MENU_ID, 0
   
   CLRF	    BTN_STATE, 0
   
   RETURN

INIT_TIMER0
    MOVLW   b'10000010'     ; TMR0ON, 16-bit, internal clk, 1:8 prescaler
    MOVWF   T0CON, 0
    MOVLW   HIGH(.65286)
    MOVWF   TMR0H, 0
    MOVLW   LOW(.65286)
    MOVWF   TMR0L, 0
    BCF     INTCON, T0IF, 0
    BSF     INTCON, T0IE, 0   ; enable Timer0 interrupt
    BSF     INTCON, GIE, 0    ; enable global interrupts
    RETURN
    
; ######################### --- Functions --- #########################  


; ###### TIMER
    
HIGH_ISR
    BTFSS   INTCON, T0IF, 0
    RETFIE  FAST

    ;BTG	    LATC, 3, 0    ;Bit toggle RC3
    ; reload for next
    MOVLW   HIGH(.65286)    ;CONFIRMED
    MOVWF   TMR0H, 0
    MOVLW   LOW(.65286)
    MOVWF   TMR0L, 0
    BCF     INTCON, T0IF, 0

    ; free-running quarter-ms counter, for pulse timing
    INFSNZ  MS_TICKS_L, 1, 0
    INCF    MS_TICKS_H, 1, 0

    ; roll 4 subticks into one "1ms" event for SEC_COUNTER logic
    INCF    QTICK_CNT, 1, 0
    MOVLW   .4
    SUBWF   QTICK_CNT, W, 0
    BTFSS   STATUS, Z, 0
    RETFIE  FAST

    CLRF    QTICK_CNT, 0
    BSF     MS_TICK_FLAG, 0, 0   ; tell main loop "1ms elapsed"

    RETFIE  FAST
    
    
; ###### DEBOUNCE
WAIT_DEBOUNCE            
    MOVLW   0x34        
    MOVWF   DEBOUNCE_TIMER,0    
DB_LOOP                 
    MOVLW   0xFF        
    MOVWF   DEBOUNCE_INNER,0    
DB_WAIT                
    DECFSZ  DEBOUNCE_INNER,1,0    
    GOTO    DB_WAIT        
    
    DECFSZ  DEBOUNCE_TIMER,1,0  
    GOTO DB_LOOP        
    RETURN     
    
; ###### RGB
    
UPDATE_RGB
   MOVLW    0x01
   SUBWF    MENU_ID,W,0     
   BTFSS    STATUS,C,0     
   GOTO     RGB_0
   BTFSC    STATUS,Z,0     
   GOTO     RGB_1
   GOTO     RGB_2
RGB_1
   BSF  LATC,5,0
   BSF  LATC,6,0
   BCF  LATC,7,0    ;c
   RETURN
RGB_2
   BSF  LATC,5,0
   BCF  LATC,6,0    ;c
   BSF  LATC,7,0
   RETURN
RGB_0
   BSF  LATC,5,0
   BSF  LATC,6,0
   BSF  LATC,7,0
   RETURN
    
; ###### MENU
    
MENU_BUTTON_CHECK
   ; ---- LEFT
   BTFSS    PORTB, 0, 0        ;pin high (released)? skip if so
   BRA      LEFT_PRESSED       ;pin is low -> button currently pressed
   BCF      BTN_STATE, 0, 0    ;released -> clear latch
   BRA      RIGHT_CHECK
LEFT_PRESSED
   BTFSC    BTN_STATE, 0, 0    ; already latched (handled this press)?
   BRA      RIGHT_CHECK        ; yes -> nothing to do
   CALL     CH_LEFT_EDGE

RIGHT_CHECK
   ; ---- RIGHT
   BTFSS    PORTB, 1, 0
   BRA      RIGHT_PRESSED
   BCF      BTN_STATE, 1, 0
   BRA      SELECT_CHECK
RIGHT_PRESSED
   BTFSC    BTN_STATE, 1, 0
   BRA      SELECT_CHECK
   CALL     CH_RIGHT_EDGE

SELECT_CHECK
   ; ---- SELECT
   BTFSS    PORTB, 2, 0
   BRA      SELECT_PRESSED
   BCF      BTN_STATE, 2, 0
   RETURN
SELECT_PRESSED
   BTFSC    BTN_STATE, 2, 0
   RETURN
   CALL     CH_SELECT_EDGE
   RETURN

CH_LEFT_EDGE
   CALL     WAIT_DEBOUNCE
   BTFSC    PORTB, 0, 0        ; still low after debounce?
   RETURN                      ; no - was noise
   BSF      BTN_STATE, 0, 0    ; latch left as handled
   GOTO     MENU_LEFT

CH_RIGHT_EDGE
   CALL     WAIT_DEBOUNCE
   BTFSC    PORTB, 1, 0
   RETURN
   BSF      BTN_STATE, 1, 0
   GOTO     MENU_RIGHT

CH_SELECT_EDGE
   CALL     WAIT_DEBOUNCE
   BTFSC    PORTB, 2, 0
   RETURN
   BSF      BTN_STATE, 2, 0
   GOTO     SELECT_PRESS


MENU_LEFT    
    CLRF    GAME_ACTIVE, 0
    MOVF    MENU_ID,W,0
    BTFSS   STATUS, Z ,0
    GOTO    DECREMENT
    MOVLW   0x02
    MOVWF   MENU_ID, 0
    GOTO    SKIP_DECREMENT
DECREMENT
    DECF    MENU_ID,1,0
SKIP_DECREMENT
    CALL    UPDATE_RGB
    RETURN
  
   
MENU_RIGHT  
    CLRF    GAME_ACTIVE, 0
    MOVLW   0x02
    SUBWF   MENU_ID,W,0
    BTFSC   STATUS,Z,0   
    GOTO    WRAP_RIGHT
    INCF    MENU_ID,1,0
    GOTO    RSKIP_RESET 
WRAP_RIGHT
    CLRF    MENU_ID, 0
RSKIP_RESET
    CALL    UPDATE_RGB
    RETURN
    

SELECT_PRESS
    MOVF    MENU_ID, W, 0   
    
    ; Check for 0
    XORLW   0x00            
    BTFSC   STATUS, Z, 0
    GOTO    CMD_ZERO
    
    ; Check for 1
    MOVF    MENU_ID, W, 0   ; Reload ID 
    XORLW   0x01            
    BTFSC   STATUS, Z, 0
    GOTO    CMD_ONE
    
    ; Check for 2
    MOVF    MENU_ID, W, 0
    XORLW   0x02           ; If W is 2, Z flag sets
    BTFSC   STATUS, Z, 0
    GOTO    CMD_TWO
    
    RETURN                  ; If MENU_ID is not 0, 1, or 2, exit (error)

; Commands
CMD_ZERO
    ;TEST: add token
    ;MOVLW   .5
    ;SUBWF   TOKENS, W, 0   ; W = TOKEN - 5
    ;BTFSC   STATUS, Z, 0        ; TOKEN == 5?
    ;RETURN                     
    ;INCF    TOKENS, 1, 0   ;Safe to add 1 token
    ;CALL    DISPLAY_TOKEN
    
WAIT_FOR_RELEASE
    BTFSS   PORTB, 2, 0    ; Is RB2 High (released)? Skip if yes.
    BRA     WAIT_FOR_RELEASE ;
    RESET
    
    RETURN

CMD_ONE
    CALL    START_PLAY_GAME
    RETURN

CMD_TWO
    ;check if health already max
    MOVF    HEALTH_STATE, F, 0  ; Move HEALTH_STATE to itself to update STATUS flags
    BTFSC   STATUS, Z, 0        
    RETURN                      
    
    ;Check if we have tokens ---
    MOVF    TOKENS, F, 0   ; Moving a register to itself updates the STATUS flags
    BTFSC   STATUS, Z, 0        ; Is TOKEN_COUNT == 0?
    RETURN                      ;No tokens available, reject the feed command.

    ;Pay 1 token ---
    DECF    TOKENS, 1, 0   ; Subtract 1 token from inventory
    
    CALL    DISPLAY_TOKEN
    
    CLRF    HEALTH_STATE, 0     ; 1. Force state back to 0 (Default Green)
    CLRF    HUNGER_COUNTER, 0  ; 2. Wipe the 90-second window back to zero
    CALL    REFRESH_GAME_FRAME  ; 3. Regenerate the frame colors instantly
    RETURN
    
; ####### GAME
    
INIT_GAME
 
    MOVLW   0xA5
    MOVWF   RNG_SEED, 0
    
    CLRF    GAME_ACTIVE, 0
    CLRF    RA4_PREV, 0
    CLRF    TOKENS, 0
 
    RETURN
  

START_PLAY_GAME
    CLRF    GAME_2SEC_TIMER, 0  ;
    CALL    GENERATE_NEW_NUMBER
 
    MOVLW   0x01
    MOVWF   GAME_ACTIVE, 0
 
    CLRF    RA4_PREV, 0
    BTFSC   PORTA, 4, 0
    BSF     RA4_PREV, 0, 0
    RETURN
 

GENERATE_NEW_NUMBER
    CALL    UPDATE_RNG
    MOVF    RNG_SEED, W, 0
    ANDLW   0x0F
    MOVWF   RANDOM_NUM, 0
 
    MOVLW   .10
    SUBWF   RANDOM_NUM, W, 0
    BTFSS   STATUS, C, 0
    BRA     GNN_VALID
    MOVLW   .10
    SUBWF   RANDOM_NUM, F, 0
GNN_VALID
    CALL    DISPLAY_7SEG
    CALL    DISPLAY_BINARY
    RETURN
    
    
; Game "MAIN"
POLL_NEW_NUMBER_BUTTON
    ; Check if the game is active
    MOVF    GAME_ACTIVE, W, 0
    BZ      PNB_DONE            ; If game mode is 0, exit out safely
    
    ; Check if RA5 is high (Stop command given)
    BTFSC   PORTA, 5, 0         ; Read pin state
    BRA     PNB_EXIT            ; High -> Turn off game mode
    RETURN                      ; Low -> Do nothing, keep rolling

PNB_EXIT
    CLRF    GAME_ACTIVE, 0      ; Shut down the minigame engine
PNB_DONE
    RETURN

    
DISPLAY_BINARY
    MOVF    RANDOM_NUM, W, 0
    ANDLW   0x0F
    MOVWF   LATA, 0         ; RA4-7 are inputs, so upper bits here are irrelevant
    RETURN
 
DISPLAY_7SEG
    MOVLW   UPPER(SEGMENT_TABLE)
    MOVWF   TBLPTRU, 0
    MOVLW   HIGH(SEGMENT_TABLE)
    MOVWF   TBLPTRH, 0
    MOVLW   LOW(SEGMENT_TABLE)
    MOVWF   TBLPTRL, 0
 
    MOVF    RANDOM_NUM, W, 0
    ADDWF   TBLPTRL, F, 0
    MOVLW   0
    ADDWFC  TBLPTRH, F, 0
 
    TBLRD*
    MOVF    TABLAT, W, 0
    MOVWF   LATD, 0
    RETURN
 

UPDATE_RNG
    MOVF    RNG_COUNTER, W, 0
    XORWF   RNG_SEED, W, 0
    MULLW   .7
    RRNCF   PRODL, F, 0
    RRNCF   PRODL, W, 0
    MOVWF   RNG_SEED, 0
    RETURN 
    
POLL_RESULT_PULSE

    BTFSS   PORTB, 4, 0
    BRA     PULSE_LOW
    ; pin HIGH
    MOVF    PULSE_STATE, W, 0
    BZ      PRP_DONE
    CLRF    PULSE_STATE, 0

    ; diff = MS_TICKS - PULSE_START  (snapshot both, interrupts can be left on -
    ; a single-byte race is negligible here, but disable briefly to be safe)
    BCF     INTCON, GIE, 0
    MOVF    MS_TICKS_L, W, 0
    MOVWF   TEMP_L, 0
    MOVF    MS_TICKS_H, W, 0
    MOVWF   TEMP_H, 0
    BSF     INTCON, GIE, 0

    MOVF    PULSE_START_L, W, 0
    SUBWF   TEMP_L, F, 0
    MOVF    PULSE_START_H, W, 0
    SUBWFB  TEMP_H, F, 0

    MOVLW   .6
    SUBWF   TEMP_L, W, 0
    MOVF    TEMP_H, W, 0
    BTFSS   STATUS, Z, 0
    BRA     PRP_LONG_CHECK
    ; TEMP_H==0 case handled below anyway; simplest: just check TEMP_H!=0 OR TEMP_L>=6
PRP_LONG_CHECK
    MOVF    TEMP_H, W, 0
    BNZ     PRP_ADD_TOKEN         ; overflowed a byte -> definitely long
    MOVLW   .6
    SUBWF   TEMP_L, W, 0
    BTFSS   STATUS, C, 0
    BRA     PRP_DONE              ; < 6 ticks -> short pulse, ignore
PRP_ADD_TOKEN
    MOVLW   .5
    SUBWF   TOKENS, W, 0   ; W = TOKEN - 5
    BTFSC   STATUS, Z, 0        ; TOKEN == 5?
    BRA	    PRP_DONE                    
    INCF    TOKENS, 1, 0   ;Safe to add 1 token
    CALL    DISPLAY_TOKEN
    BRA     PRP_DONE

PULSE_LOW
    MOVF    PULSE_STATE, W, 0
    BNZ     PRP_DONE
    MOVLW   0x01
    MOVWF   PULSE_STATE, 0
    BCF     INTCON, GIE, 0
    MOVF    MS_TICKS_L, W, 0
    MOVWF   PULSE_START_L, 0
    MOVF    MS_TICKS_H, W, 0
    MOVWF   PULSE_START_H, 0
    BSF     INTCON, GIE, 0
PRP_DONE
    RETURN  
    
DISPLAY_TOKEN
    MOVLW   UPPER(SEGMENT_TABLE)
    MOVWF   TBLPTRU, 0
    MOVLW   HIGH(SEGMENT_TABLE)
    MOVWF   TBLPTRH, 0
    MOVLW   LOW(SEGMENT_TABLE)
    MOVWF   TBLPTRL, 0
 
    MOVF    TOKENS, W, 0
    ADDWF   TBLPTRL, F, 0
    MOVLW   0
    ADDWFC  TBLPTRH, F, 0
 
    TBLRD*
    MOVF    TABLAT, W, 0
    MOVWF   LATD, 0
    RETURN
; ######################### --- old modules (age, led, motor) --- #########################
    
; ####### age
  ; ---- extra vars (put with your other EQUs) ----
SEC_COUNTER     EQU 0x50    ; ticks 0-59
AGE_COUNTER     EQU 0x51    ; 0,10,20...100
SHAPE_STATE     EQU 0x52    ; 0 baby / 1 adult / 2 old
HEALTH_STATE    EQU 0x53    ; 0 green / 1 yellow / 2 red
MS_ACC          EQU 0x54    ; counts MS_TICK_FLAG events up to 1000 (needs 2 bytes if you want exact 1000; see note)
MS_ACC_H        EQU 0x55
	
HUNGER_COUNTER  EQU 0x56    ; 0-90 seconds

INIT_TAMAGOTCHI
    CLRF    SEC_COUNTER, 0
    CLRF    AGE_COUNTER, 0
    CLRF    SHAPE_STATE, 0
    CLRF    HEALTH_STATE, 0
    CLRF    HUNGER_COUNTER, 0 ;
    CLRF    TOKENS, 0
    
    CLRF    MS_ACC, 0
    CLRF    MS_ACC_H, 0
    RETURN

; Call this once per LOOP pass. Only does work when MS_TICK_FLAG is set,
; so it costs ~nothing on passes where no ms has elapsed.
SERVICE_AGE_ENGINE
    BTFSS   MS_TICK_FLAG, 0, 0
    RETURN
    BCF     MS_TICK_FLAG, 0, 0

    INFSNZ  MS_ACC, 1, 0
    INCF    MS_ACC_H, 1, 0

    ; check MS_ACC:MS_ACC_H == 1000
    MOVLW   LOW(.1000)
    XORWF   MS_ACC, W, 0
    BTFSS   STATUS, Z, 0
    RETURN
    MOVLW   HIGH(.1000)
    XORWF   MS_ACC_H, W, 0
    BTFSS   STATUS, Z, 0
    RETURN

    ; one second elapsed
    CLRF    MS_ACC, 0
    CLRF    MS_ACC_H, 0
    INCF    SEC_COUNTER, 1, 0
    
    ;#### RANGEN TICKS
    MOVF    GAME_ACTIVE, W, 0
    BZ      GAME_OFF_BYPASS         ; If game isn't active, bypass and turn off pin
    
    INCF    GAME_2SEC_TIMER, 1, 0   ; Add 1 second to the game timer
    MOVLW   .2
    SUBWF   GAME_2SEC_TIMER, W, 0   ; Check if 2 seconds have passed
    BTFSS   STATUS, Z, 0
    BRA     TURN_PIN_ON             ; Not at 2 seconds yet (it's at 1 second), turn pin ON
    
    ; --- 2 SECONDS REACHED: Generate & Drop Pin LOW ---
    CLRF    GAME_2SEC_TIMER, 0      ; Reset 2-second counter
    CALL    GENERATE_NEW_NUMBER     ; Automatically roll and display a new number
    BCF     LATA, 6, 0              ; Turn ranGen (RA6) LOW immediately when number changes
    BRA     SKIP_GAME_TIMER
    
TURN_PIN_ON
    BSF     LATA, 6, 0              ; 1 second has passed since generation, turn ranGen HIGH
    BRA     SKIP_GAME_TIMER

GAME_OFF_BYPASS
    BCF     LATA, 6, 0              ; Safety: Ensure pin is completely off if game is inactive

SKIP_GAME_TIMER
    
    
    ;##### HUNGER
    INCF    HUNGER_COUNTER, 1, 0
    MOVLW   .90                         ;TODO: make 90
    SUBWF   HUNGER_COUNTER, W, 0
    BTFSS   STATUS, Z, 0
    GOTO    SKIP_NEGLECT_TICK           ; Not 90 seconds yet, proceed with regular age checks

    ; 90 seconds hit! Advance health state
    CLRF    HUNGER_COUNTER, 0
    INCF    HEALTH_STATE, 1, 0          ; Move Green (0) -> Yellow (1) -> Red (2)

    ; Check if health has degraded past Red (Value 3 = Death)
    MOVLW   .3
    SUBWF   HEALTH_STATE, W, 0
    BTFSC   STATUS, Z, 0
    GOTO    DEATH_STATE                 ; Failed to clean/feed in time! Permanent trap.

    ; Update matrix buffers instantly so user sees the color shift
    CALL    REFRESH_GAME_FRAME

SKIP_NEGLECT_TICK
    
    ;how many seconds to age
    MOVLW   .60		;TODO; 60 (1min)
    SUBWF   SEC_COUNTER, W, 0
    BTFSS   STATUS, Z, 0
    RETURN

    ;age
    CLRF    SEC_COUNTER, 0
    MOVLW   .10	
    ADDWF   AGE_COUNTER, 1, 0

    CALL    RECALC_SERVO_TARGET   ; module 3

    MOVLW   .100
    SUBWF   AGE_COUNTER, W, 0
    BTFSC   STATUS, Z, 0
    GOTO    DEATH_STATE

    MOVLW   .30		    
    SUBWF   AGE_COUNTER, W, 0
    BTFSC   STATUS, C, 0
    GOTO    AGE_CHECK_OLD
    CLRF    SHAPE_STATE, 0
    GOTO    AGE_REFRESH

AGE_CHECK_OLD
    MOVLW   .60
    SUBWF   AGE_COUNTER, W, 0
    BTFSC   STATUS, C, 0
    GOTO    AGE_SET_OLD
    MOVLW   .1
    MOVWF   SHAPE_STATE, 0
    GOTO    AGE_REFRESH

AGE_SET_OLD
    MOVLW   .2
    MOVWF   SHAPE_STATE, 0

AGE_REFRESH
    CALL    REFRESH_GAME_FRAME
    
    RETURN  
    
; ######## LED Matrix
    
; ---- vars ----
BYTE_BUFF       EQU 0x60
BIT_COUNT       EQU 0x61
LED_COUNT       EQU 0x62
RESET_COUNT     EQU 0x63
FRAME_BUFF      EQU 0x100   ; 64 px * 3 bytes = 192 bytes, pick a free bank
GRID_PIN        EQU 0       ; RE0
	
SYS_FLAGS      EQU 0x64 
#DEFINE LED_DIRTY_FLAG  SYS_FLAGS, 0

INIT_LM
    BCF     TRISE, GRID_PIN, 0
    BCF     LATE, GRID_PIN, 0
    
    CALL    REFRESH_GAME_FRAME
    RETURN

; --- unchanged logic from your original REFRESH_GAME_FRAME / RENDER_LOOP ---
; (copy verbatim: TBLPTR setup by SHAPE_STATE, RENDER_LOOP, SET_COLOR_*, WRITE_BLANK)
; This part does no timing-sensitive work, only table reads + RAM writes.
REFRESH_GAME_FRAME
    BSF LED_DIRTY_FLAG
    
    MOVLW    .0
    CPFSEQ   SHAPE_STATE, 0
    BRA      TRY_ADULT_PTR

    MOVLW    UPPER(IMAGE_BABY)
    MOVWF    TBLPTRU, 0
    MOVLW    HIGH(IMAGE_BABY)
    MOVWF    TBLPTRH, 0
    MOVLW    LOW(IMAGE_BABY)
    MOVWF    TBLPTRL, 0
    BRA      START_RAM_RENDER

TRY_ADULT_PTR
    MOVLW    .1
    CPFSEQ   SHAPE_STATE, 0
    BRA      LOAD_OLD_PTR

    MOVLW    UPPER(IMAGE_ADULT)
    MOVWF    TBLPTRU, 0
    MOVLW    HIGH(IMAGE_ADULT)
    MOVWF    TBLPTRH, 0
    MOVLW    LOW(IMAGE_ADULT)
    MOVWF    TBLPTRL, 0
    BRA      START_RAM_RENDER

LOAD_OLD_PTR
    MOVLW    UPPER(IMAGE_OLD)
    MOVWF    TBLPTRU, 0
    MOVLW    HIGH(IMAGE_OLD)
    MOVWF    TBLPTRH, 0
    MOVLW    LOW(IMAGE_OLD)
    MOVWF    TBLPTRL, 0

START_RAM_RENDER
   MOVLW    HIGH(FRAME_BUFF)
   MOVWF    FSR0H, 0
   MOVLW    LOW(FRAME_BUFF)
   MOVWF    FSR0L, 0

   MOVLW    .64
   MOVWF    LED_COUNT, 0

RENDER_LOOP
   TBLRD*+
   MOVF     TABLAT, W, 0
   BZ       WRITE_BLANK

   MOVF     HEALTH_STATE, W, 0
   BZ       SET_COLOR_GREEN
   DECFSZ   WREG, 1, 0
   GOTO     SET_COLOR_RED

SET_COLOR_YELLOW
   MOVLW    0x20
   MOVWF    POSTINC0, 0
   MOVLW    0x20
   MOVWF    POSTINC0, 0
   CLRF     POSTINC0, 0
   GOTO     NEXT_PIXEL

SET_COLOR_GREEN
   MOVLW    0x30
   MOVWF    POSTINC0, 0
   CLRF     POSTINC0, 0
   CLRF     POSTINC0, 0
   GOTO     NEXT_PIXEL

SET_COLOR_RED
   CLRF     POSTINC0, 0
   MOVLW    0x30
   MOVWF    POSTINC0, 0
   CLRF     POSTINC0, 0
   GOTO     NEXT_PIXEL

WRITE_BLANK
   CLRF     POSTINC0, 0
   CLRF     POSTINC0, 0
   CLRF     POSTINC0, 0

NEXT_PIXEL
   DECFSZ   LED_COUNT, 1, 0
   GOTO     RENDER_LOOP
   RETURN

SEND_FRAME_FROM_RAM
    MOVLW   HIGH(FRAME_BUFF)
    MOVWF   FSR0H, 0
    MOVLW   LOW(FRAME_BUFF)
    MOVWF   FSR0L, 0
    MOVLW   .192
    MOVWF   LED_COUNT, 0
SEND_LOOP
    MOVFF   POSTINC0, BYTE_BUFF
    CALL    SEND_BYTE
    DECFSZ  LED_COUNT, 1, 0
    GOTO    SEND_LOOP
    CALL    SEND_RESET
    RETURN

SEND_BYTE
    MOVLW   0x08
    MOVWF   BIT_COUNT, 0
BYTE_LOOP
    CALL    SEND_BIT
    DECFSZ  BIT_COUNT, 1, 0
    GOTO    BYTE_LOOP
    RETURN


SEND_BIT
    BTFSS   BYTE_BUFF, 7, 0
    GOTO    BIT_IS_ZERO
    BSF     LATE, GRID_PIN, 0   ; "1": ~2 cycles high (~1.0us)
    NOP
    NOP
    NOP
    NOP
    NOP
    BCF     LATE, GRID_PIN, 0
    GOTO    SEND_DONE
BIT_IS_ZERO
    BSF     LATE, GRID_PIN, 0   ; "0": ~1 cycle high (~0.5us)
    NOP
    NOP
    BCF     LATE, GRID_PIN, 0
SEND_DONE
    NOP
    NOP
    NOP
    RLNCF   BYTE_BUFF, 1, 0
    RETURN

SEND_RESET
    BCF     LATE, GRID_PIN, 0
    MOVLW   .300                ; scaled down from .200 (~4x fewer loop passes needed)
    MOVWF   RESET_COUNT, 0
RESET_LOOP
    DECFSZ  RESET_COUNT, 1, 0
    GOTO    RESET_LOOP
    RETURN
    
; ###### Servo motor
    
; ---- vars ----
SERVO_TARGET_L  EQU 0x70
SERVO_TARGET_H  EQU 0x71
SERVO_ON_TIME   EQU 0x72
SERVO_ON_TIME_H EQU 0x73
SERVO_NEXT_L    EQU 0x74   ; MS_TICKS snapshot for next allowed pulse
SERVO_NEXT_H    EQU 0x75
SERVO_PIN       EQU 4      ; RC4

INIT_SERVO
    BCF     TRISC, SERVO_PIN, 0
    BCF     LATC, SERVO_PIN, 0
    MOVFF   MS_TICKS_L, SERVO_NEXT_L
    MOVFF   MS_TICKS_H, SERVO_NEXT_H
    RETURN

RECALC_SERVO_TARGET
    MOVF    AGE_COUNTER, W, 0
    MULLW   .30		;TODO: ADJUST (was 23)
    BCF     STATUS, C, 0
    MOVLW   LOW(.1500)	;TODO: ADJUST (was 1200/ 2000)
    ADDWF   PRODL, W, 0
    MOVWF   SERVO_TARGET_L, 0
    MOVLW   HIGH(.1500)
    ADDWFC  PRODH, W, 0
    MOVWF   SERVO_TARGET_H, 0
    RETURN

; Call once per LOOP pass. Non-blocking except during the ~1-2ms
; active pulse itself (unavoidable for bit-banged servo signaling).
SERVICE_SERVO
    ; has 20ms (80 quarter-ms ticks) elapsed since last pulse?
    MOVF    MS_TICKS_L, W, 0
    SUBWF   SERVO_NEXT_L, W, 0
    MOVF    MS_TICKS_H, W, 0
    SUBWFB  SERVO_NEXT_H, W, 0
    BTFSC   STATUS, C, 0
    RETURN                      ; next-time still in the future -> not due

    ; schedule next pulse 80 ticks (20ms) from now
    MOVLW   .80
    ADDWF   SERVO_NEXT_L, 1, 0
    MOVLW   0
    ADDWFC  SERVO_NEXT_H, 1, 0

    MOVFF   SERVO_TARGET_L, SERVO_ON_TIME
    MOVFF   SERVO_TARGET_H, SERVO_ON_TIME_H

    BSF     LATC, SERVO_PIN, 0
SERVO_PULSE_LOOP
    BCF INTCON, GIE, 0    
    NOP
    DECFSZ  SERVO_ON_TIME, 1, 0
    GOTO    SERVO_PULSE_LOOP
    DECFSZ  SERVO_ON_TIME_H, 1, 0
    GOTO    SERVO_PULSE_LOOP
    BCF     LATC, SERVO_PIN, 0
    BSF INTCON, GIE, 0    
    RETURN
    
; ######################### --- MAIN --- #########################    
MAIN
    CALL    INIT_OSC
    CALL    INIT_PORTS
    CALl    INIT_MENU
    CALL    INIT_GAME
    CALL    INIT_TAMAGOTCHI
    CALL    INIT_LM
    CALL    INIT_SERVO
    CALL    INIT_TIMER0
    CALL    UPDATE_RGB
    CALL    RECALC_SERVO_TARGET
    
    CALL    REFRESH_GAME_FRAME
   
LOOP
    
    INCF    RNG_COUNTER, 1, 0
    
    CALL    SERVICE_AGE_ENGINE
    CALL    MENU_BUTTON_CHECK
    CALL    POLL_NEW_NUMBER_BUTTON
    CALL    POLL_RESULT_PULSE
    CALL    SERVICE_SERVO
    
    BTG	    LATC, 3, 0
    
    ; --- LED UPDATE CHECK ---
    BTFSS LED_DIRTY_FLAG         
    BRA SKIP_LED_UPDATE           

    ; --- LED UPDATE EXECUTION  ---
    BCF INTCON, GIE, 0            
    CALL SEND_FRAME_FROM_RAM      
    BSF INTCON, GIE, 0          
    BCF LED_DIRTY_FLAG            

SKIP_LED_UPDATE
    
    
    GOTO    LOOP
 
; ######################### PERMANENT DEATH TRAP #########################
DEATH_STATE
    BCF  LATC,5,0
    BCF  LATC,6,0
    BSF  LATC,7,0
    GOTO    DEATH_STATE
 
; ######################### GRAPHIC TEMPLATES DATABASE #########################
    ORG 0x0600  
IMAGE_BABY
    DB  0,0,0,0,0,0,0,0
    DB  0,0,0,0,0,0,0,0
    DB  0,0,0,1,1,0,0,0
    DB  0,0,1,0,0,1,0,0
    DB  0,0,1,0,0,1,0,0
    DB  0,0,0,1,1,0,0,0
    DB  0,0,0,0,0,0,0,0
    DB  0,0,0,0,0,0,0,0

IMAGE_ADULT
    DB  0,0,0,0,0,0,0,0
    DB  0,0,1,1,1,1,0,0
    DB  0,1,0,0,0,0,1,0
    DB  0,1,0,0,0,0,1,0
    DB  0,1,0,1,1,0,1,0
    DB  0,1,0,0,0,0,1,0
    DB  0,0,1,1,1,1,0,0
    DB  0,0,0,0,0,0,0,0

IMAGE_OLD
    DB  0,1,1,1,1,1,1,0
    DB  1,0,0,0,0,0,0,1
    DB  1,0,1,1,1,1,0,1
    DB  1,0,0,0,0,0,0,1
    DB  1,0,1,0,0,1,0,1
    DB  1,0,1,0,0,1,0,1
    DB  1,0,0,0,0,0,0,1
    DB  0,1,1,1,1,1,1,0    
    
    
; ######################### 7-SEGMENT TRANSLATION TABLE #########################
    ORG 0x0700          
SEGMENT_TABLE
    ;      0     1     2     3     4     5     6     7
    DB  0x7D, 0x30, 0x6E, 0x7A, 0x33, 0x5B, 0x5F, 0x70
    ;      8     9
    DB  0x7F, 0x7B
      
    END
        
    