    LIST P=PIC18F4321    F=INHX32   
    #include <p18f4321.inc> 
    CONFIG  OSC=INTIO2; Internal oscillator @ 16MHz 
    CONFIG  PBADEN=DIG ; PORTB = DIGital 
    CONFIG  WDT=OFF    ; Watch Dog Timer Deactivated 
    CONFIG MCLRE = OFF ; Makes RA3 usable

    ORG 0x0000 
    GOTO    MAIN 
    ORG     0x0008  
    RETFIE  FAST  
    ORG     0x0018  
    RETFIE  FAST 

; ######################### --- VARS --- ######################### 
MENU_ID         EQU 0x20    ;Menu[2..0]
    
DEBOUNCE_TIMER  EQU 0x21    ;count for debouning timer
DEBOUNCE_INNER	EQU 0x22
BTN_STATE       EQU 0x23    ; pressed or not

RNG_SEED        EQU 0x24    ; running LFSR state
RANDOM_NUM      EQU 0x25    ; latest generated 4-bit number (0-15)
SEC_COUNTER     EQU 0x26    ; garbage
GAME_ACTIVE	EQU 0x27    ; active or not
RA4_PREV	EQU 0x28    ; newNum btn state
    
    
; ######################### --- INITS --- #########################   
INIT_OSC   ; Configure the microcontroller @ 8MHz w/ internal oscillator 
   MOVLW   b'01110000'      ;8MHz fosc
   MOVWF   OSCCON,0  
    
   MOVLW   b'00000000'	;PLLEN off
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
   BSF	    TRISB,1,0	;RB2 in
   BSF	    TRISB,3,0	;RB3 in
   BCF      INTCON2, RBPU,0   ; enable PORTB pull-ups
   
   ;7seg
   CLRF     TRISD,0    ; PORTD configured completely as outputs for 7-Segment Displ
   CLRF     LATD,0     ; Clear 7-Segment outputs on boot
   
   ;game 
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


; ######################### --- Functions --- #########################  

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
    RETURN

CMD_ONE
    CALL    START_PLAY_GAME
    RETURN

CMD_TWO
    RETURN
    
; ####### GAME
    
INIT_GAME
 
    MOVLW   0xA5
    MOVWF   RNG_SEED, 0
    
    CLRF    GAME_ACTIVE, 0
    CLRF    RA4_PREV, 0
 
    RETURN
  

START_PLAY_GAME
    CALL    GENERATE_NEW_NUMBER
 
    MOVLW   0x01
    MOVWF   GAME_ACTIVE, 0
 
    CLRF    RA4_PREV, 0
    ;BTFSC   PORTA, 4, 0
    ;BSF     RA4_PREV, 0, 0
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
    ;CALL    DISPLAY_BINARY
    RETURN
    
    
; Game "MAIN"
POLL_NEW_NUMBER_BUTTON
    ;Check if the game is active
    MOVF    GAME_ACTIVE, W, 0
    BZ      PNB_DONE        ; If 0, don't play
    
    ; Check if RA5 is high
    BTFSC   PORTA, 5, 0     ;
    BRA     PNB_EXIT        
    
    ; Now check RA4
    BTFSS   PORTA, 4, 0    
    BRA     PNB_LOW        
    
    ; RA4 is high
    BTFSC   RA4_PREV, 0, 0  ; Already handled this press?
    BRA     PNB_DONE
    
    CALL    GENERATE_NEW_NUMBER
    BSF     RA4_PREV, 0, 0
    BRA     PNB_DONE

PNB_LOW
    BCF     RA4_PREV, 0, 0
    BRA     PNB_DONE

PNB_EXIT
    CLRF    GAME_ACTIVE, 0
PNB_DONE
    RETURN
 
; ------------------------------------------------------------------
; Puts RANDOM_NUM (0-9, fits in 4 bits) onto RA0-3
; ------------------------------------------------------------------
DISPLAY_BINARY
    MOVF    RANDOM_NUM, W, 0
    ANDLW   0x0F
    MOVWF   LATA, 0         ; RA4-7 are inputs, so upper bits here are irrelevant
    RETURN
 
; ------------------------------------------------------------------
; Unchanged - table lookup for 7-segment pattern
; ------------------------------------------------------------------
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
 
; ------------------------------------------------------------------
; Unchanged - RNG core
; ------------------------------------------------------------------
UPDATE_RNG
    MOVF    SEC_COUNTER, W, 0
    XORWF   RNG_SEED, W, 0
    MULLW   .7
    RRNCF   PRODL, F, 0
    RRNCF   PRODL, W, 0
    MOVWF   RNG_SEED, 0
    RETURN 
    
; ######################### --- MAIN --- #########################    
MAIN
    CALL INIT_OSC
    CALL INIT_PORTS
    CALl INIT_MENU
    CALL INIT_GAME
    
    CALL UPDATE_RGB
   
LOOP
    BTG	    LATC, 3, 0    ;Bit toggle RC3
    
    INCF    SEC_COUNTER, 1, 0
    
    CALL    MENU_BUTTON_CHECK
    CALL    POLL_NEW_NUMBER_BUTTON
    
    GOTO    LOOP
 
; ######################### PERMANENT DEATH TRAP #########################
DEATH_STATE
    GOTO    DEATH_STATE
 
    
    
    
; ######################### 7-SEGMENT TRANSLATION TABLE #########################
    ORG 0x0700          
SEGMENT_TABLE
    ;      0     1     2     3     4     5     6     7
    DB  0x7D, 0x30, 0x6E, 0x7A, 0x33, 0x5B, 0x5F, 0x70
    ;      8     9
    DB  0x7F, 0x7B
      
    END
      