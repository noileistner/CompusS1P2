LIST P=PIC18F4321    F=INHX32     
    #include <p18f4321.inc> 
    CONFIG  OSC=INTIO2; Internal oscillator @ 16MHz 
    CONFIG  PBADEN=DIG ; PORTB = DIGital 
    CONFIG  WDT=OFF    ; Watch Dog Timer Deactivated 
    CONFIG MCLRE = OFF ; Makes RA3 the reset
   
    ORG 0x0000 
    GOTO    MAIN 
    ORG     0x0008  
    RETFIE  FAST  
    ORG     0x0018  
    RETFIE  FAST 
    

; ######################### Vars #########################
MENU_ID         EQU 0x20    ;Menu[2..0]
DEBOUNCE_TIMER  EQU 0x21    ;count for debouning timer
DEBOUNCE_INNER  EQU 0x22    ;used as a max counter every loop
    
; LED MATRIX VARIABLES
BYTE_BUFF       EQU 0x23    ;frame byte
BIT_COUNT       EQU 0x24    ;8 - 0
FRAME_PTR_L     EQU 0x25    ;RAM pointers
FRAME_PTR_H     EQU 0x26
RESET_COUNT     EQU 0x27    ;For counting reset time
LED_COUNT       EQU 0x28    ;64 - 0

; TAMAGOTCHI CORE STAT ENGINE VARIABLES
SEC_COUNTER     EQU 0x2A    ; Ticks up to 60 seconds
AGE_COUNTER     EQU 0x2B    ; Ticks 0, 10, 20 ... up to 100 years
SHAPE_STATE     EQU 0x2C    ; 0 = Baby [0-29], 1 = Adult [30-59], 2 = Old [60-100]
HEALTH_STATE    EQU 0x2D    ; 0 = Green, 1 = Yellow, 2 = Red
    
FRAME_BUFF      EQU 0x060   ;will hold a frame in ram 
    
GRID_PIN        EQU 0       ; RE0 will be our LED Matrix Grid signal output
SERVO_PIN       EQU 4       ; RC4 will be our Servo signal output pin

; --- Servo pulse-width target, latched once a minute, consumed every loop ---
SERVO_TARGET_L  EQU 0x2E    ; low byte of target HIGH-time count
SERVO_TARGET_H  EQU 0x2F    ; high byte of target HIGH-time count

; --- Scratch counters used DURING pulse generation (every loop pass) ---
SERVO_ON_TIME   EQU 0x30    ; working low counter
SERVO_ON_TIME_H EQU 0x31    ; working high counter

; --- 20ms frame-spacing counter (so we don't re-pulse faster than ~50Hz) ---
SERVO_FRAME_CNT EQU 0x32

; --- PLAY GAME / RANDOM NUMBER VARIABLES ---
PLAY_MENU_ID    EQU 0x02    ; ASSUMPTION: MENU_ID value that represents "Play"
RNG_SEED        EQU 0x35    ; running LFSR state
RANDOM_NUM      EQU 0x36    ; latest generated 4-bit number (0-15)
BTN_STATE       EQU 0x37    ; Latch tracking register: 0=None pressed, 1=Handled

GAME_ACTIVE     EQU 0x38    ; 1 = game loop running, 0 = idle
GAME_WAIT_CNT   EQU 0x39    ; ~1s wait counter between numbers (stand-in for NewNumber pulse)

; --- Game I/O pin assignments (all on PORTB) ---
PIN_NEWNUM      EQU 5       ; RB5 - NewNumber, input, pulsed by external circuit (stubbed for now)
PIN_PLAYING     EQU 6       ; RB6 - Playing, input, external circuit signals game stop
PIN_RANDGEN     EQU 4       ; RB4 - RandomGenerated, output, PIC holds high while waiting on a number
PIN_RESULT      EQU 7       ; RB7 - ResultPulse, output, stubbed for now

;######################### BASE_CODE #########################

INIT_OSC   ; Configure the microcontroller @ 32MHz w/ internal oscillator 
   MOVLW   b'01110000'      ;8MHz fosc
   MOVWF   OSCCON,0  
    
   MOVLW   b'01000000'
   MOVWF   OSCTUNE,0
   RETURN 
   
    
; Debounce 20ms @ 32MHz
WAIT_DEBOUNCE            
    MOVLW   0xD0        
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
    
; ######################### RGB_MENU #########################
     
INIT_RGB
   SETF     ADCON1,0   ; Make all pins digital
   CLRF     TRISD,0    ; PORTD configured completely as outputs for 7-Segment Display
   CLRF     LATD,0     ; Clear 7-Segment outputs on boot
   
   ; Configure RC7:RC5 as outputs for the RGB menu system, RC4 remains handled by Servo Setup
   MOVF     TRISC, W, 0
   ANDLW    b'00011111' ; Clear bits 7, 6, 5 (0 = Output)
   MOVWF    TRISC, 0
   
   MOVF     LATC, W, 0
   ANDLW    b'00011111' ; Clear RGB indicators on boot
   MOVWF    LATC, 0

   SETF     TRISB,0    ; PORTB input
   BCF      INTCON2, RBPU,0   ; enable PORTB pull-ups
   MOVLW    0x02
   MOVWF    MENU_ID, 0
   CLRF     BTN_STATE, 0      ; Start unlatched
   RETURN

INIT_PLAY_GAME
    MOVLW   b'11101111'     
    MOVWF   TRISA, 0
    BCF     LATA, 4, 0

    ; --- Configure PORTC cleanly without overwriting RC4 ---
    BCF     TRISC, 0, 0     ; Set RC0 as output (RandomNumber bit 0)
    BCF     TRISC, 1, 0     ; Set RC1 as output (RandomNumber bit 1)
    BCF     TRISC, 2, 0     ; Set RC2 as output (RandomNumber bit 2)
    BCF     TRISC, 3, 0     ; Set RC3 as output (RandomNumber bit 3)

    ; Clear only the lower 4 bits of LATC, preserve the servo pin state
    MOVF    LATC, W, 0
    ANDLW   b'11110000'     ; Clears lower 4 bits, leaves RC4 state exactly as it was
    MOVWF   LATC, 0

    ; --- Configure game handshake pins on PORTB ---
    ; RB5 (NewNumber) and RB6 (Playing) stay inputs (PORTB defaults to input from INIT_RGB)
    ; RB4 (RandomGenerated) and RB7 (ResultPulse) are outputs
    BCF     TRISB, PIN_RANDGEN, 0
    BCF     TRISB, PIN_RESULT, 0
    BCF     LATB, PIN_RANDGEN, 0
    BCF     LATB, PIN_RESULT, 0

    MOVLW   0xA5            
    MOVWF   RNG_SEED, 0
    CLRF    GAME_ACTIVE, 0
    RETURN
   

; --- NEW NON-BLOCKING EDGE TRIGGER MECHANISM ---
MENU_BUTTON_CHECK
   ; STEP 1: Verify if all buttons are back in their IDLE released states
   ; RB0=1 (High), RB1=1 (High), RB2=0 (Low). Idle pattern = b'011' (RB2:RB1:RB0)
   MOVF     PORTB, W, 0
   ANDLW    b'00000111'       ; Check bits 0,1,2 (Left, Right, Select)
   XORLW    b'00000011'       ; Idle pattern: RB0=1,RB1=1,RB2=0 -> 011
   BTFSC    STATUS, Z, 0
   CLRF     BTN_STATE, 0      ; Clears memory lock register once ALL buttons are released

   ; STEP 2: If an operation is currently locked, skip reading inputs entirely
   MOVF     BTN_STATE, W, 0
   BTFSS    STATUS, Z, 0
   RETURN                     

   ; STEP 3: Detect initial down-press thresholds
   BTFSS    PORTB, 0, 0       ; Left Key (Active Low: looking for a 0)
   GOTO     CH_LEFT_EDGE
   BTFSS    PORTB, 1, 0       ; Right Key (Active Low: looking for a 0)
   GOTO     CH_RIGHT_EDGE
   BTFSC    PORTB, 2, 0       ; Select Key (Active High: looking for a 1)
   GOTO     CH_SELECT_EDGE
   RETURN

CH_LEFT_EDGE
   CALL     WAIT_DEBOUNCE
   BTFSC    PORTB, 0, 0       ; Verify button is still physically low
   RETURN                     ; Was noise, drop out
   MOVLW    0x01
   MOVWF    BTN_STATE, 0      ; Lock button processing latch
   GOTO     MENU_LEFT

CH_RIGHT_EDGE
   CALL     WAIT_DEBOUNCE
   BTFSC    PORTB, 1, 0       ; Verify button is still physically low
   RETURN
   MOVLW    0x01
   MOVWF    BTN_STATE, 0      ; Lock button processing latch
   GOTO     MENU_RIGHT

CH_SELECT_EDGE
   CALL     WAIT_DEBOUNCE
   BTFSS    PORTB, 2, 0       ; Verify button is still physically high
   RETURN
   MOVLW    0x01
   MOVWF    BTN_STATE, 0      ; Lock button processing latch
   GOTO     SELECT_PRESS


MENU_LEFT
    ; 1. Clear RA4 on PORTA
    BCF     LATA, 4, 0      

    ; 2. Clear 7-Segment display on PORTD
    CLRF    LATD, 0

    ; If the game was active, fully stop it so leaving the menu can't leave it running
    CALL    STOP_PLAY_GAME

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
    ; 1. Clear RA4 on PORTA
    BCF     LATA, 4, 0      

    ; 2. Clear 7-Segment display on PORTD
    CLRF    LATD, 0

    ; If the game was active, fully stop it so leaving the menu can't leave it running
    CALL    STOP_PLAY_GAME

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
   MOVLW    PLAY_MENU_ID
   SUBWF    MENU_ID, W, 0
   BTFSS    STATUS, Z, 0
   RETURN

   CALL     START_PLAY_GAME
   RETURN

UPDATE_RGB
   MOVLW    0x01
   SUBWF    MENU_ID,W,0     
   BTFSS    STATUS,C,0     
   GOTO     RGB_0
   BTFSC    STATUS,Z,0     
   GOTO     RGB_1
   GOTO     RGB_2
RGB_2
   BSF  LATC,5,0
   BSF  LATC,6,0
   BCF  LATC,7,0
   RETURN
RGB_1
   BSF  LATC,5,0
   BCF  LATC,6,0
   BSF  LATC,7,0
   RETURN
RGB_0
   BSF  LATC,5,0
   BSF  LATC,6,0
   BSF  LATC,7,0
   RETURN

; ######################### PLAY GAME (Memory Game / External IC) #########################
;
; Pin map (all on PORTB):
;   RB4 PIN_RANDGEN  - output. Held HIGH while a number is on display, waiting to be
;                       acknowledged/consumed. Dropped LOW right before the next number
;                       is generated.
;   RB5 PIN_NEWNUM   - input. External circuit pulses this to request the next number.
;                       STUBBED: not yet polled. A fixed ~1s wait is used instead, so the
;                       cycle can be tested standalone. Swap-in point is marked below.
;   RB6 PIN_PLAYING  - input. External circuit drives this HIGH once it has taken over /
;                       finished, which stops the generate loop entirely.
;   RB7 PIN_RESULT   - output. STUBBED: reserved for pulsing the result once scoring is
;                       added. Left LOW for now, never written elsewhere.
;
; RandomNumber nibble -> RC0-3 (already configured as outputs in INIT_PLAY_GAME)
; 7-segment equivalent -> RD0-6 via DISPLAY_7SEG (unchanged)
;
; NOTE: numbers generated for THIS game are NOT clamped to 0-9 like the old flash code did -
; the spec calls for a 4-bit number (0-15) since it's being driven out on 4 raw bits, not
; just decoded to a single 7-seg digit. SEGMENT_TABLE already has entries up to 0xF.

START_PLAY_GAME
    MOVLW   0x01
    MOVWF   GAME_ACTIVE, 0
    BCF     LATB, PIN_RANDGEN, 0   ; ensure RandomGenerated starts low
    CALL    PLAY_GAME_NEXT_NUMBER
    RETURN

; Stops the game cleanly: clears state, drops RandomGenerated, blanks the 7-seg and RC0-3.
; Safe to call even if the game isn't active.
STOP_PLAY_GAME
    CLRF    GAME_ACTIVE, 0
    BCF     LATB, PIN_RANDGEN, 0

    CLRF    LATD, 0                ; blank 7-segment

    MOVF    LATC, W, 0             ; blank RC0-3 only, preserve RC4-7 (servo + RGB)
    ANDLW   b'11110000'
    MOVWF   LATC, 0
    RETURN

; Generates one number, drives it out on RC0-3 and the 7-segment, then raises
; PIN_RANDGEN to signal "number ready, waiting for acknowledgement".
PLAY_GAME_NEXT_NUMBER
    CALL    UPDATE_RNG
    MOVF    RNG_SEED, W, 0
    ANDLW   0x0F
    MOVWF   RANDOM_NUM, 0          ; full 4-bit range (0-15), no clamping

    ; --- Output raw binary on RC0-3 ---
    MOVF    LATC, W, 0
    ANDLW   b'11110000'            ; preserve RC4-7 (servo + RGB), clear RC0-3
    IORWF   RANDOM_NUM, W, 0       ; RANDOM_NUM is already masked to 4 bits, safe to OR in directly
    MOVWF   LATC, 0

    ; --- Output 7-segment equivalent on RD0-6 ---
    CALL    DISPLAY_7SEG

    ; --- Signal RandomGenerated: number is ready, waiting on acknowledgement ---
    BSF     LATB, PIN_RANDGEN, 0

    ; --- Reset the stand-in wait counter (swap point for real NewNumber pulse later) ---
    MOVLW   0x02
    MOVWF   GAME_WAIT_CNT, 0
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
    ADDWFC  TBLPTRH, F, 0       ; Carry tracking

    TBLRD* 
    MOVF    TABLAT, W, 0
    MOVWF   LATD, 0            ; Push exact illumination array directly out of PORTD
    RETURN

UPDATE_RNG
    MOVF    SEC_COUNTER, W, 0   ; use SEC_COUNTER instead - changes every second
    XORWF   RNG_SEED, W, 0      ; XOR with running seed for extra mixing
    MULLW   .7
    RRNCF   PRODL, F, 0
    RRNCF   PRODL, W, 0
    MOVWF   RNG_SEED, 0
    RETURN

; Called once per ~0.5s TMR0 tick from the main loop while GAME_ACTIVE=1.
; Checks PIN_PLAYING first (stop condition always wins), then counts down the
; stand-in wait before moving to the next number.
GAME_TICK
    MOVF    GAME_ACTIVE, W, 0
    BZ      GAME_TICK_DONE

    ; Playing going HIGH stops the game outright, regardless of wait state
    BTFSC   PORTB, PIN_PLAYING, 0
    GOTO    GAME_TICK_STOP

    ; --- STUB: waiting for NewNumber (RB5) goes here instead of the timed wait. ---
    ; To switch over later, replace the DECFSZ/GOTO pair below with:
    ;   BTFSS   PORTB, PIN_NEWNUM, 0
    ;   RETURN
    ;   BCF     LATB, PIN_RANDGEN, 0
    ;   CALL    PLAY_GAME_NEXT_NUMBER
    DECFSZ  GAME_WAIT_CNT, 1, 0
    GOTO    GAME_TICK_DONE

    BCF     LATB, PIN_RANDGEN, 0
    CALL    PLAY_GAME_NEXT_NUMBER
    GOTO    GAME_TICK_DONE

GAME_TICK_STOP
    CALL    STOP_PLAY_GAME
    ; Result pulse (RB7) intentionally not driven yet - add scoring/result logic here later.

GAME_TICK_DONE
    RETURN
   
; ######################### LED_MATRIX #########################

INIT_LM
    ; Initialize PORTE for driving the grid
    BCF     TRISE, GRID_PIN, 0   ; Set RE0 as Output
    BCF     LATE, GRID_PIN, 0    ; Clear grid output line
    CALL    INIT_TAMAGOTCHI
    CALL    REFRESH_GAME_FRAME
    RETURN

INIT_TAMAGOTCHI
    CLRF    SEC_COUNTER, 0
    CLRF    AGE_COUNTER, 0
    CLRF    SHAPE_STATE, 0
    CLRF    HEALTH_STATE, 0
    CLRF    GAME_ACTIVE, 0
    RETURN

INIT_SERVO
    ; Configure RC4 as output for driving the Servomotor
    BCF     TRISC, SERVO_PIN, 0  
    BCF     LATC, SERVO_PIN, 0   
    CLRF    SERVO_FRAME_CNT, 0
    RETURN

REFRESH_GAME_FRAME
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
   MOVLW    HIGH(FRAME_BUFF)
   MOVWF    FSR0H, 0
   MOVLW    LOW(FRAME_BUFF)
   MOVWF    FSR0L, 0
   
   MOVLW    .192
   MOVWF    LED_COUNT, 0 
SEND_LOOP
   MOVFF    POSTINC0, BYTE_BUFF
   CALL     SEND_BYTE
   DECFSZ   LED_COUNT, 1, 0
   GOTO     SEND_LOOP
   
   CALL     SEND_RESET
   RETURN
   
SEND_BIT
    BTFSS   BYTE_BUFF, 7, 0   
    GOTO    BIT_IS_ZERO       

    BSF     LATE, GRID_PIN, 0       ; Send Data via RE0
    NOP                       
    NOP                       
    NOP                       
    NOP                       
    NOP                       
    BCF     LATE, GRID_PIN, 0        
    GOTO    SEND_DONE

BIT_IS_ZERO
    BSF     LATE, GRID_PIN, 0        
    NOP                       
    NOP                       
    BCF     LATE, GRID_PIN, 0        
    GOTO    SEND_DONE       

SEND_DONE
    NOP
    NOP
    NOP
    RLNCF   BYTE_BUFF, 1, 0   
    RETURN
   
SEND_BYTE
   MOVLW    0x08
   MOVWF    BIT_COUNT, 0
BYTE_LOOP
   CALL     SEND_BIT
   DECFSZ   BIT_COUNT, 1, 0
   GOTO     BYTE_LOOP
   RETURN
   
SEND_RESET
    BCF     LATE, GRID_PIN, 0
    MOVLW   .200
    MOVWF   RESET_COUNT, 0
RESET_LOOP  
    NOP
    NOP
    NOP
    DECFSZ  RESET_COUNT,1,0
    GOTO RESET_LOOP
    RETURN
    

; ######################### TIMER ENGINE SETUP #########################

INIT_TIMER0
    MOVLW   b'10000111'     ; Enable TMR0, 16-bit, Internal Clock, 1:256 Prescaler
    MOVWF   T0CON, 0
    MOVLW   high(.34286)    
    MOVWF   TMR0H, 0
    MOVLW   low(.34286)
    MOVWF   TMR0L, 0
    BCF     INTCON, T0IF, 0 
    RETURN


; ######################### SERVO ENGINE #########################

RECALC_SERVO_TARGET
    MOVF    AGE_COUNTER, W, 0
    MULLW   .23             

    ; Securely clear Carry flag before running addition math
    BCF     STATUS, C, 0

    ; Base count offset updated to .1200 (~1.5ms Center Position at 32MHz)
    MOVLW   LOW(.1200)
    ADDWF   PRODL, W, 0         
    MOVWF   SERVO_TARGET_L, 0    
    
    MOVLW   HIGH(.1200)
    ADDWFC  PRODH, W, 0         
    MOVWF   SERVO_TARGET_H, 0      
    RETURN

REFRESH_SERVO_PULSE
    MOVFF   SERVO_TARGET_L, SERVO_ON_TIME
    MOVFF   SERVO_TARGET_H, SERVO_ON_TIME_H

    BSF     LATC, SERVO_PIN, 0  

SERVO_PULSE_LOOP                      
    NOP                          
    NOP                          
    NOP                          
    NOP                          
    DECFSZ  SERVO_ON_TIME, 1, 0 
    GOTO    SERVO_PULSE_LOOP          
    
    DECFSZ  SERVO_ON_TIME_H, 1, 0   
    GOTO    SERVO_PULSE_LOOP          

    BCF     LATC, SERVO_PIN, 0  

    MOVLW   .120
    MOVWF   SERVO_FRAME_CNT, 0
SERVO_FRAME_WAIT
    NOP
    NOP
    DECFSZ  SERVO_FRAME_CNT, 1, 0
    GOTO    SERVO_FRAME_WAIT

    RETURN

; ######################### MAIN #########################   
MAIN
    CALL INIT_OSC
    CALL INIT_RGB
    CALL UPDATE_RGB
    CALL INIT_LM
    CALL INIT_TIMER0
    CALL INIT_SERVO
    CALL INIT_PLAY_GAME
    CALL RECALC_SERVO_TARGET    

LOOP
    ; --- INTERRUPT POLLING ENGINE ---
    BTFSS   INTCON, T0IF, 0
    GOTO    SKIP_CLOCK_TICK
    
    MOVLW   high(.34286)
    MOVWF   TMR0H, 0
    MOVLW   low(.34286)
    MOVWF   TMR0L, 0
    BCF     INTCON, T0IF, 0     
    
    INCF    SEC_COUNTER, 1, 0

    ; --- GAME ENGINE (runs every ~0.5s tick) ---
    CALL    GAME_TICK

    MOVLW   .60
    SUBWF   SEC_COUNTER, W, 0
    BTFSS   STATUS, Z, 0
    GOTO    REFRESH_SYSTEM_VIEW 

    CLRF    SEC_COUNTER, 0      
    MOVLW   .10
    ADDWF   AGE_COUNTER, 1, 0   
    
    CALL    RECALC_SERVO_TARGET

    MOVLW   .100
    SUBWF   AGE_COUNTER, W, 0
    BTFSC   STATUS, Z, 0        
    GOTO    DEATH_STATE         

    MOVLW   .30
    SUBWF   AGE_COUNTER, W, 0
    BTFSC   STATUS, C, 0        
    GOTO    CHECK_OLD_BRACKET   
    
    MOVLW   .0
    MOVWF   SHAPE_STATE, 0
    GOTO    REFRESH_SYSTEM_VIEW 

CHECK_OLD_BRACKET
    MOVLW   .60
    SUBWF   AGE_COUNTER, W, 0
    BTFSC   STATUS, C, 0        
    GOTO    SET_OLD_STATE       
    
    MOVLW   .1
    MOVWF   SHAPE_STATE, 0
    GOTO    REFRESH_SYSTEM_VIEW

SET_OLD_STATE
    MOVLW   .2
    MOVWF   SHAPE_STATE, 0

REFRESH_SYSTEM_VIEW
    CALL    REFRESH_GAME_FRAME  

SKIP_CLOCK_TICK
    CALL    REFRESH_SERVO_PULSE

    BCF     INTCON, GIE, 0  
    CALL    SEND_FRAME_FROM_RAM
    BSF     INTCON, GIE, 0  
    
    CALL    MENU_BUTTON_CHECK
    
    GOTO LOOP

; ######################### PERMANENT DEATH TRAP #########################
DEATH_STATE
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
    ;      8     9     A     b     C     d     E     F
    DB  0x7F, 0x7B, 0x77, 0x1F, 0x4D, 0x3E, 0x4F, 0x47
      
    END