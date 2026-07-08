;==========================================================
; PIC18F4321 Servo Motor Sweep Test  0-180 deg  @ 50Hz
; Servo signal output: RC4
; Fosc = 32MHz (8MHz INTOSC x4 PLL)  => Tcy = 125ns
;==========================================================

    LIST P=18F4321
    #INCLUDE <P18F4321.INC>

    CONFIG OSC = INTIO2    ; internal oscillator, RC4/RC5 as I/O
    CONFIG WDT = OFF
    CONFIG PBADEN = dig
    CONFIG MCLRE = ON

;-------------------- VARIABLES ---------------------------
    CBLOCK 0x20
        PULSE_US_L      ; pulse width (us) low byte
        PULSE_US_H      ; pulse width (us) high byte
        D1, D2, D3       ; generic delay counters
        FRAME_CNT        ; number of frames to hold each angle
        ANGLE_STEP       ; sweep step counter
        DIR              ; sweep direction flag
    ENDC

;==========================================================
    ORG 0x0000
    GOTO START

;==========================================================
; INIT_OSC - configure internal oscillator to 32MHz (8MHz+PLL)
;==========================================================
INIT_OSC
    MOVLW   b'01110000'
    MOVWF   OSCCON,0
    MOVLW   b'01000000'
    MOVWF   OSCTUNE,0
    RETURN

;==========================================================
; INIT_PORTS - RC4 as digital output (servo signal pin)
;==========================================================
INIT_PORTS
    BCF     TRISC, 4, 0     ; RC4 = output
    BCF     LATC, 4, 0      ; RC4 = low initially
    RETURN

;==========================================================
; MAIN PROGRAM
;==========================================================
START
    CALL    INIT_OSC
    CALL    INIT_PORTS

    ; ---- Start at 0 degrees (1000us pulse) ----
    MOVLW   LOW(1000)
    MOVWF   PULSE_US_L
    MOVLW   HIGH(1000)
    MOVWF   PULSE_US_H

SWEEP_UP
    MOVLW   .10                 ; hold each angle for 10 frames (~200ms)
    MOVWF   FRAME_CNT
HOLD_UP
    CALL    SEND_PULSE
    DECFSZ  FRAME_CNT,F
    GOTO    HOLD_UP

    ; increase pulse width by ~5.5us per step (180 steps, 1000->2000)
    MOVLW   .6
    ADDWF   PULSE_US_L,F
    MOVLW   0
    ADDWFC  PULSE_US_H,F

    ; check if we reached 2000us (180 degrees)
    MOVF    PULSE_US_H,W
    SUBLW   HIGH(2000)
    BNZ     SWEEP_UP
    MOVF    PULSE_US_L,W
    SUBLW   LOW(2000)
    BNZ     SWEEP_UP

    ; ---- reached 180 degrees, now sweep back down to 0 ----
SWEEP_DOWN
    MOVLW   .10
    MOVWF   FRAME_CNT
HOLD_DOWN
    CALL    SEND_PULSE
    DECFSZ  FRAME_CNT,F
    GOTO    HOLD_DOWN

    MOVLW   .6
    SUBWF   PULSE_US_L,F
    MOVLW   0
    SUBWFB  PULSE_US_H,F

    MOVF    PULSE_US_H,W
    SUBLW   HIGH(1000)
    BNZ     SWEEP_DOWN
    MOVF    PULSE_US_L,W
    SUBLW   LOW(1000)
    BNZ     SWEEP_DOWN

    GOTO    SWEEP_UP           ; loop forever (up, down, up, down...)

;==========================================================
; SEND_PULSE
; Generates ONE 20ms frame: HIGH for PULSE_US time, then LOW
; for the remainder of the 20ms period.
;==========================================================
SEND_PULSE
    BSF     LATC, 4, 0         ; RC4 = HIGH (start of pulse)

    MOVF    PULSE_US_L,W
    MOVWF   D1
    MOVF    PULSE_US_H,W
    MOVWF   D2
    CALL    DELAY_US           ; delay for PULSE_US microseconds

    BCF     LATC, 4, 0         ; RC4 = LOW (end of pulse)

    ; remaining time = 20000us - pulse width, approximate w/ fixed
    ; delay of ~18ms (safe margin since pulse is 1-2ms of the 20ms)
    CALL    DELAY_18MS
    RETURN

;==========================================================
; DELAY_US - delay ~(D2:D1) microseconds  (32MHz, Tcy=125ns)
; Each inner loop iteration ~ 1us (8 Tcy approx, adjust NOPs)
;==========================================================
DELAY_US
    MOVF    D1,W
    IORWF   D2,W
    BZ      DELAY_US_END
DELAY_US_LOOP
    NOP
    NOP
    NOP
    NOP                        ; padding to tune to ~1us/iteration
    DECF    D1,F
    MOVLW   0xFF
    CPFSEQ  D1
    BRA     DELAY_US_DEC_H_SKIP
    MOVF    D2,F
    BZ      DELAY_US_END
    DECF    D2,F
DELAY_US_DEC_H_SKIP
    MOVF    D1,W
    IORWF   D2,W
    BNZ     DELAY_US_LOOP
DELAY_US_END
    RETURN

;==========================================================
; DELAY_18MS - fixed ~18ms delay (fills rest of 20ms frame)
; 32MHz => 144,000 Tcy needed. Nested loop below approximates this.
;==========================================================
DELAY_18MS
    MOVLW   .60
    MOVWF   D3
DELAY_18MS_OUT
    MOVLW   .250
    MOVWF   D2
DELAY_18MS_MID
    MOVLW   .40
    MOVWF   D1
DELAY_18MS_IN
    NOP
    DECFSZ  D1,F
    GOTO    DELAY_18MS_IN
    DECFSZ  D2,F
    GOTO    DELAY_18MS_MID
    DECFSZ  D3,F
    GOTO    DELAY_18MS_OUT
    RETURN

    END