LIST P=PIC18F4321	F=INHX32     
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
    
 
; ######################### Vars #########################
MENU_ID		EQU 0x20	;Menu[2..0]
DEBOUNCE_TIMER	EQU 0x21	;count for debouning timer
DEBOUNCE_INNER	EQU 0x22	;used as a max counter every loop
	
; LED MATRIX VARIABLES
BYTE_BUFF	EQU 0x23	;frame byte
BIT_COUNT	EQU 0x24	;8 - 0
FRAME_PTR_L	EQU 0x25	;RAM pointers
FRAME_PTR_H	EQU 0x26
RESET_COUNT	EQU 0x27	;For counting reset time
LED_COUNT	EQU 0x28	;64 - 0

; TAMAGOTCHI CORE STAT ENGINE VARIABLES
AGE          EQU 0x29    ; Tracks current age (0 to 100)
HEALTH_STATE EQU 0x2A    ; 0 = Healthy (Green), 1 = Warning (Yellow), 2 = Critical (Red)
SEC_COUNTER  EQU 0x2B    ; Increments every second to time status transitions
	
FRAME_BUFF	EQU 0x060	;will hold a frame in ram 
	
;######################### BASE_CODE #########################

INIT_OSC   ; Configure the microcontroller @ 32MHz w/ internal oscillator 
   
    MOVLW   b'01110000'		;8MHz fosc
    MOVWF   OSCCON,0  
    
	
    MOVLW   b'01000000'
    MOVWF   OSCTUNE,0
    
    RETURN 
   
    
; Debounce 20ms @ 32MHz
; 1 cycle = 4/32Mhz = 125ns
; 20ms : 20000us/ 0.125us = 160000 cycles
WAIT_DEBOUNCE			;2c when called
    MOVLW   0xD0		;1c   XX = 208
    MOVWF   DEBOUNCE_TIMER,0	;1c
DB_LOOP				    ; XX*(764 + 5) + 4 = 160000
    MOVLW   0xFF		;1c
    MOVWF   DEBOUNCE_INNER,0	;1c
DB_WAIT				    ;3c*254 + 2 = 764
    DECFSZ  DEBOUNCE_INNER,1,0	;1c, 2c if skip
    GOTO    DB_WAIT		;2c
    
    DECFSZ  DEBOUNCE_TIMER,1,0  ;1c, 2c if skip
    GOTO DB_LOOP		;2c
    
    
    RETURN			;2c
    
; ######################### RGB_MENU #########################
     
INIT_RGB
   SETF	    ADCON1,0   ; Make all pins digital
   
   CLRF	    TRISD,0	;PORTD output
   CLRF	    LATD,0	;CLEAR D
   
   SETF	    TRISB,0	;PORTB intro
   BCF     INTCON2, RBPU,0   ; enable PORTB pull-ups
   
   CLRF MENU_ID, 0
   
   RETURN 
   
 
MENU_BUTTON_CHECK
   BTFSS PORTB, 0, 0	;skip if set (buttons 0 when pressed)
   CALL	MENU_LEFT
   BTFSS PORTB, 1, 0
   CALL	MENU_RIGHT
   BTFSS PORTB, 2, 0
   NOP

   RETURN
   
   
MENU_LEFT
   CALL WAIT_DEBOUNCE
   MOVF	    MENU_ID,W,0
   BTFSS    STATUS, Z ,0
   GOTO	DECREMENT
   MOVLW    0x02
   MOVWF    MENU_ID, 0
   GOTO	    SKIP_DECREMENT
DECREMENT
   DECF	MENU_ID,1,0
SKIP_DECREMENT
   CALL	UPDATE_RGB
LOOP_L
   BTFSS    PORTB,0,0	
   GOTO LOOP_L
   CALL WAIT_DEBOUNCE
   RETURN
  
   
MENU_RIGHT 
   CALL WAIT_DEBOUNCE
   MOVLW    0x02
   SUBWF    MENU_ID,W,0
   BTFSC    STATUS,Z,0	;skip if clear (menu=2, answer = 0)
   GOTO	    WRAP_RIGHT
   INCF	    MENU_ID,1,0
   GOTO	RSKIP_RESET 
WRAP_RIGHT
   CLRF	MENU_ID, 0
RSKIP_RESET
   CALL	UPDATE_RGB
LOOP_R
   BTFSS    PORTB,1,0
   GOTO LOOP_R
   CALL WAIT_DEBOUNCE
   RETURN
 
   
UPDATE_RGB
   
   MOVLW    0x01
   SUBWF    MENU_ID,W,0	    ;0 is negative, 1 is 0, 2 is neither
   BTFSS    STATUS,C,0	    ;skip if set (carry)
   GOTO	RGB_0
   BTFSC    STATUS,Z,0	    ;skip if clear (negative)
   GOTO	RGB_1
   GOTO	RGB_2
RGB_2
   BSF	LATD,4,0
   BSF	LATD,5,0
   BCF	LATD,6,0
   RETURN
RGB_1
   BSF	LATD,4,0
   BCF	LATD,5,0
   BSF	LATD,6,0
   RETURN
RGB_0
   BSF	LATD,4,0
   BSF	LATD,5,0
   BSF	LATD,6,0
   RETURN
   
; ######################### LED_MATRIX #########################

INIT_LM
   BCF	LATD,0,0
   CLRF AGE, 0
   CLRF HEALTH_STATE, 0
   CLRF SEC_COUNTER, 0
   CALL REFRESH_GAME_FRAME
   RETURN

; DYNAMIC DATA GENERATOR: Combines Age shape layout + Health colors into RAM
REFRESH_GAME_FRAME
   ; Step 1: Assign Flash lookups according to current simulation milestones
   MOVLW    .30
   SUBWF    AGE, W, 0
   BTFSS    STATUS, C, 0
   GOTO     LOAD_BABY_PTR    ; Age 0-29
   
   MOVLW    .60
   SUBWF    AGE, W, 0
   BTFSS    STATUS, C, 0
   GOTO     LOAD_ADULT_PTR   ; Age 30-59
   GOTO     LOAD_OLD_PTR     ; Age 60-100

LOAD_BABY_PTR
   MOVLW    UPPER(IMAGE_BABY)
   MOVWF    TBLPTRU, 0
   MOVLW    HIGH(IMAGE_BABY)
   MOVWF    TBLPTRH, 0
   MOVLW    LOW(IMAGE_BABY)
   MOVWF    TBLPTRL, 0
   GOTO     START_RAM_RENDER

LOAD_ADULT_PTR
   MOVLW    UPPER(IMAGE_ADULT)
   MOVWF    TBLPTRU, 0
   MOVLW    HIGH(IMAGE_ADULT)
   MOVWF    TBLPTRH, 0
   MOVLW    LOW(IMAGE_ADULT)
   MOVWF    TBLPTRL, 0
   GOTO     START_RAM_RENDER

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
   
   MOVLW    .64             ; 64 total individual frame blocks to evaluate
   MOVWF    LED_COUNT, 0

RENDER_LOOP
   TBLRD*+                  ; Get structural shape instruction from table
   MOVF     TABLAT, W, 0
   BZ       WRITE_BLANK     ; If flash value is zero, skip mapping a color
   
   ; Flash position is active! Map current status health color structure
   ; Color byte payload sorting: GRB sequence
   MOVF     HEALTH_STATE, W, 0
   BZ       SET_COLOR_GREEN
   DECFSZ   WREG, 1, 0
   GOTO     SET_COLOR_RED

SET_COLOR_YELLOW            ; State 1: Yellow (G=0x20, R=0x20, B=0x00)
   MOVLW    0x20
   MOVWF    POSTINC0, 0
   MOVLW    0x20
   MOVWF    POSTINC0, 0
   CLRF     POSTINC0, 0
   GOTO     NEXT_PIXEL

SET_COLOR_GREEN             ; State 0: Green (G=0x30, R=0x00, B=0x00)
   MOVLW    0x30
   MOVWF    POSTINC0, 0
   CLRF     POSTINC0, 0
   CLRF     POSTINC0, 0
   GOTO     NEXT_PIXEL

SET_COLOR_RED               ; State 2: Red (G=0x00, R=0x30, B=0x00)
   CLRF     POSTINC0, 0
   MOVLW    0x30
   MOVWF    POSTINC0, 0
   CLRF     POSTINC0, 0
   GOTO     NEXT_PIXEL

WRITE_BLANK
   CLRF     POSTINC0, 0    ; Fill blank space with clear GRB zeroes
   CLRF     POSTINC0, 0
   CLRF     POSTINC0, 0

NEXT_PIXEL
   DECFSZ   LED_COUNT, 1, 0
   GOTO     RENDER_LOOP
   RETURN
   
;SEND FRAME FUNC ----------------------------
SEND_FRAME_FROM_RAM
   MOVLW    HIGH(FRAME_BUFF)
   MOVWF    FSR0H, 0
   MOVLW    LOW(FRAME_BUFF)
   MOVWF    FSR0L, 0
   
   MOVLW    .192
   MOVWF    LED_COUNT, 0 
SEND_LOOP
   MOVFF    POSTINC0, BYTE_BUFF
   CALL	    SEND_BYTE
   DECFSZ   LED_COUNT, 1, 0
   GOTO	    SEND_LOOP
   
   CALL	    SEND_RESET
   RETURN
   
; ######################### BIT FUNC #########################  
SEND_BIT
    ; Step 1: Pre-check the bit BEFORE turning the pin high
    BTFSS   BYTE_BUFF, 7, 0   ; Check if MSB is 1 (Skip if 1)
    GOTO    BIT_IS_ZERO       ; If 0, jump to the zero-handler

    ; --- BIT 1 PATH --- (Target: 6-7 cycles high)
    BSF     LATD, 0, 0        ; [Pin goes HIGH]
    NOP                       
    NOP                       
    NOP                       
    NOP                       
    NOP                       
    BCF     LATD, 0, 0        ; [Pin goes LOW]
    GOTO    SEND_DONE

BIT_IS_ZERO
    ; --- BIT 0 PATH --- (Target: 3 cycles high)
    BSF     LATD, 0, 0        ; [Pin goes HIGH]
    NOP                       
    NOP                       
    BCF     LATD, 0, 0        ; [Pin goes LOW]
    GOTO    SEND_DONE         

SEND_DONE
    NOP
    NOP
    NOP
    RLNCF   BYTE_BUFF, 1, 0   ; Rotate bit left
    RETURN
   
   
;BYTE FUNC -----------------------------   
SEND_BYTE
   MOVLW    0x08
   MOVWF    BIT_COUNT, 0
BYTE_LOOP
   CALL	    SEND_BIT
   DECFSZ   BIT_COUNT, 1, 0
   GOTO	    BYTE_LOOP
   RETURN
   
;RESET FUNC ----------------------------
SEND_RESET
    BCF	    LATD,0,0
    MOVLW   .200
    MOVWF   RESET_COUNT, 0
RESET_LOOP	;TODO check timing here and fix the rest of ts
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
    ; Preload sequence: Write high byte first, then low byte
    MOVLW   high(.34286)    
    MOVWF   TMR0H, 0
    MOVLW   low(.34286)
    MOVWF   TMR0L, 0
    BCF     INTCON, T0IF, 0 ; Clear overflow flag
    RETURN

  
; ######################### MAIN #########################
   
MAIN
    CALL INIT_OSC
    CALL INIT_RGB
    CALL UPDATE_RGB
    CALL INIT_LM
    CALL INIT_TIMER0

LOOP
    ; --- INTERRUPT POLLING ENGINE (Ticks once per second) ---
    BTFSS   INTCON, T0IF, 0
    GOTO    SKIP_CLOCK_TICK
    
    ; Corrected Preload Sequence
    MOVLW   high(.34286)
    MOVWF   TMR0H, 0
    MOVLW   low(.34286)
    MOVWF   TMR0L, 0
    BCF     INTCON, T0IF, 0 ; Clear interrupt flag
    
    ; Process time-based events
    INCF    SEC_COUNTER, 1, 0
    
    ; --- LINEAR SIMULATION ENGINE ---

    ; --- Second 5 Milestone ---
    MOVLW   .5
    SUBWF   SEC_COUNTER, W, 0
    BTFSC   STATUS, Z, 0
    CALL    SET_WARNING_STATE   ; Baby turns Yellow

    ; --- Second 10 Milestone ---
    MOVLW   .10
    SUBWF   SEC_COUNTER, W, 0
    BTFSS   STATUS, Z, 0
    GOTO    SKIP_M10
    CALL    EVOLVE_TO_ADULT     ; Baby evolves to Adult shape
    CALL    SET_HEALTHY_STATE   ; Color goes back to Green
SKIP_M10

    ; --- Second 15 Milestone ---
    MOVLW   .15
    SUBWF   SEC_COUNTER, W, 0
    BTFSC   STATUS, Z, 0
    CALL    SET_WARNING_STATE   ; Adult turns Yellow

    ; --- Second 20 Milestone ---
    MOVLW   .20
    SUBWF   SEC_COUNTER, W, 0
    BTFSS   STATUS, Z, 0
    GOTO    SKIP_M20
    CALL    EVOLVE_TO_OLD       ; Adult evolves to Old shape
    CALL    SET_HEALTHY_STATE   ; Color goes back to Green
SKIP_M20

    ; --- Second 25 Milestone ---
    MOVLW   .25
    SUBWF   SEC_COUNTER, W, 0
    BTFSC   STATUS, Z, 0
    CALL    SET_WARNING_STATE   ; Old pet turns Yellow

    ; --- Second 28 Milestone ---
    MOVLW   .28
    SUBWF   SEC_COUNTER, W, 0
    BTFSC   STATUS, Z, 0
    CALL    SET_CRITICAL_STATE  ; Old pet turns Red

    ; --- Second 30 Milestone: Global Cycle Reset ---
    MOVLW   .30
    SUBWF   SEC_COUNTER, W, 0
    BTFSS   STATUS, Z, 0
    GOTO    REFRESH_SYSTEM_VIEW ; If not 30, go render normally
    
    CLRF    SEC_COUNTER, 0  
    CLRF    AGE, 0          ; Forces system back to Baby shape
    CLRF    HEALTH_STATE, 0 ; Forces system back to Green color

REFRESH_SYSTEM_VIEW
    CALL    REFRESH_GAME_FRAME ; Rebuild RAM matrix structure

SKIP_CLOCK_TICK
    ; Update display panel hardware
    BCF     INTCON, GIE, 0  
    CALL    SEND_FRAME_FROM_RAM
    BSF     INTCON, GIE, 0  
    
    ; Service background asynchronous menu requests
    CALL    MENU_BUTTON_CHECK
    
    GOTO LOOP

; --- SIMULATION SUBROUTINES ---
EVOLVE_TO_ADULT
    MOVLW   .35             ; Fits Adult bracket (30-59)
    MOVWF   AGE, 0
    RETURN

EVOLVE_TO_OLD
    MOVLW   .70             ; Fits Old bracket (60-100)
    MOVWF   AGE, 0
    RETURN

SET_HEALTHY_STATE
    CLRF    HEALTH_STATE, 0 ; State 0 = Healthy (Green)
    RETURN

SET_WARNING_STATE
    MOVLW   .1              ; State 1 = Warning (Yellow)
    MOVWF   HEALTH_STATE, 0
    RETURN

SET_CRITICAL_STATE
    MOVLW   .2              ; State 2 = Critical (Red)
    MOVWF   HEALTH_STATE, 0
    RETURN
    
    
; ######################### GRAPHIC TEMPLATES DATABASE #########################
    ORG 0x0600  
IMAGE_BABY
    ; Simple cross-hair layout shape template marker
    DB  0,0,0,0,0,0,0,0
    DB  0,0,0,0,0,0,0,0
    DB  0,0,0,1,1,0,0,0
    DB  0,0,1,0,0,1,0,0
    DB  0,0,1,0,0,1,0,0
    DB  0,0,0,1,1,0,0,0
    DB  0,0,0,0,0,0,0,0
    DB  0,0,0,0,0,0,0,0

IMAGE_ADULT
    ; Square boundary shape template marker
    DB  0,0,0,0,0,0,0,0
    DB  0,0,1,1,1,1,0,0
    DB  0,1,0,0,0,0,1,0
    DB  0,1,0,0,0,0,1,0
    DB  0,1,0,1,1,0,1,0
    DB  0,1,0,0,0,0,1,0
    DB  0,0,1,1,1,1,0,0
    DB  0,0,0,0,0,0,0,0

IMAGE_OLD
    ; Diamond style block template marker
    DB  0,1,1,1,1,1,1,0
    DB  1,0,0,0,0,0,0,1
    DB  1,0,1,1,1,1,0,1
    DB  1,0,0,0,0,0,0,1
    DB  1,0,1,0,0,1,0,1
    DB  1,0,1,0,0,1,0,1
    DB  1,0,0,0,0,0,0,1
    DB  0,1,1,1,1,1,1,0
      
    
    END


