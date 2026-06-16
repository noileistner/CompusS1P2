; hello wassup
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
	
	;LED MATRIX

BYTE_BUFF	EQU 0x23	;frame byte
BIT_COUNT	EQU 0x24	;8 - 0
LED_COUNT	EQU 0x24	;64 - 0
FRAME_PTR_L	EQU 0x25	;RAM pointers
FRAME_PTR_H	EQU 0x26
RESET_COUNT	EQU 0x27	;For counting reset time
	
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
   ;BCF	TRISD,1,0	;already done in init_rgb
   BCF	LATD,0,0
   
   ; Point TBLPTR at IMAGE0 in flash
   MOVLW   UPPER(IMAGE_0)
   MOVWF   TBLPTRU, 0
   MOVLW   HIGH(IMAGE_0)
   MOVWF   TBLPTRH, 0
   MOVLW   LOW(IMAGE_0)
   MOVWF   TBLPTRL, 0
   
   CALL    LOAD_IMAGE_TO_RAM
   
   RETURN
   
LOAD_IMAGE_TO_RAM
   MOVLW   HIGH(FRAME_BUFF)
   MOVWF   FSR0H, 0
   MOVLW   LOW(FRAME_BUFF)
   MOVWF   FSR0L, 0
   
   ;64 pixels * 3 bytes
   MOVLW   .192
   MOVWF   LED_COUNT, 0 
LOAD_LOOP
   TBLRD*+		    ;read and increment
   MOVFF   TABLAT, POSTINC0
   DECFSZ  LED_COUNT, 1, 0	;decrement, skip if zero
   GOTO	   LOAD_LOOP
   
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
   
;BIT FUNC -----------------------------   
SEND_BIT
   BSF	   LATD, 0, 0	    ;begin high	 1
   BTFSS   BYTE_BUFF, 7, 0 ;check MSB   1
   GOTO SEND_ZERO			;1
   
   ;1c = 125
   ;total = 650-1850ns
   ;bit = 1, high 800ns = 6.4, low 450ns = 3.6
   ; 6 + 4 = 10
   ;so far 3
   NOP
   NOP
   NOP
   NOP
   BCF	   LATD,0,0
   NOP
   NOP
   GOTO SEND_DONE
   
SEND_ZERO
   ;bit = 0, high 400ns = 3.2, low 850ns = 6.8
   ; 3 + 7 = 10
   ;so far 2 (goto)
   NOP
   BCF	    LATD,0,0
   NOP
   NOP
   NOP
   NOP
   NOP
   GOTO SEND_DONE
   
SEND_DONE
   RLNCF    BYTE_BUFF,1,0   ;rotate bit left (nc = no carry)
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
    

  
; ######################### MAIN #########################
   
MAIN
    CALL INIT_OSC
    CALL INIT_RGB
    CALL UPDATE_RGB
    ;CALL INIT_LM
LOOP
    ;auto stuff
    
    ;LED routine
    ;BCF	    INTCON, GIE, 0  ;disable interrupt during transmission
    ;CALL    SEND_FRAME_FROM_RAM
    ;BSF	    INTCON, GIE, 0
    
    ;check for action
    CALL MENU_BUTTON_CHECK
    
    GOTO LOOP
    
    
;TABLES    
    
    ORG 0x0200  ;hardcoded adress for flash
IMAGE_0
    DB  0x40,0x40,0x40,  0x40,0x40,0x40,  0x40,0x40,0x40,  0x40,0x40,0x40,  0x40,0x40,0x40
    DB  0x40,0x40,0x40,  0x00,0x00,0x00,  0x00,0x00,0x00,  0x00,0x00,0x00,  0x40,0x40,0x40
    DB  0x40,0x40,0x40,  0x00,0x00,0x00,  0x00,0x00,0x00,  0x00,0x00,0x00,  0x40,0x40,0x40
    DB  0x40,0x40,0x40,  0x00,0x00,0x00,  0x00,0x00,0x00,  0x00,0x00,0x00,  0x40,0x40,0x40
    DB  0x40,0x40,0x40,  0x40,0x40,0x40,  0x40,0x40,0x40,  0x40,0x40,0x40,  0x40,0x40,0x40
IMAGE_0_END
      
    
    
    END


