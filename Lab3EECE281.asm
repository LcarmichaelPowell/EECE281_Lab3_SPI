$MODDE2
org 0000H
   ljmp MyProgram

FREQ   EQU 33333333
BAUD   EQU 115200
T2LOAD EQU 65536-(FREQ/(32*BAUD))
CE_ADC EQU p0.3
SCLK   EQU p0.2
MOSI   EQU P0.1
MISO   EQU p0.0


DSEG at 30H
x:   		ds 4
y:   		ds 4
bcd: 		ds 5
DEG:	    ds 1
Turn_Hex_6: ds 1
HOT:		ds 1

BSEG
mf: dbit 1

$include(math32.asm)

CSEG

T_7seg: ;Lookup table for Hex keys
    DB 0C0H, 0F9H, 0A4H, 0B0H, 099H
    DB 092H, 082H, 0F8H, 080H, 090H
    DB 088H, 083H





; Configure the serial port and baud rate using timer 2
InitSerialPort:
	clr TR2 ; Disable timer 2
	mov T2CON, #30H ; RCLK=1, TCLK=1 
	mov RCAP2H, #high(T2LOAD)  
	mov RCAP2L, #low(T2LOAD)
	setb TR2 ; Enable timer 2
	mov SCON, #52H
	ret

; Send a character through the serial port
putchar:
    JNB TI, putchar
    CLR TI
    MOV SBUF, a
    RET

; Send a constant-zero-terminated string through the serial port
SendString:
    CLR A
    MOVC A, @A+DPTR
    JZ SSDone
    LCALL putchar
    INC DPTR
    SJMP SendString
Sendtemp: ;Sends the current temp through the Serial Port
	mov a, bcd+2
	anl a,#0FH
	orl a, #30H
	lcall putchar
	
	mov a, bcd+1
	swap a
	anl a,#0FH
	orl a, #30H
	lcall putchar
	
	mov a, bcd+1
	anl a,#0FH
	orl a,#30H
	lcall putchar
	
	mov a,#'.'
	lcall putchar
	
	mov a, bcd+0
	swap a
	anl a,#0FH
	orl a, #30H
	lcall putchar
	
	mov a, bcd+0
	anl a,#0FH
	orl a,#30H
	lcall putchar
	
	mov a, #'\r'
	lcall putchar
	
	mov a, #'\n'
	lcall putchar
	
	ret
	
SSDone:
    ret

Display_BCD:  ;Display_BCD numbers on the Hex keys
	mov dptr, #T_7seg

	mov r0,bcd+2
	cjne r0,#0,Turn_on
	sjmp not_100
Turn_on:
	mov a, bcd+2
	anl a, #0FH
	movc a, @a+dptr
	mov HEX6, a
	sjmp Continue_Dude
	
Not_100:
	mov Hex6,#1111111B
	
Continue_dude:	
	mov a, bcd+1
	swap a
	anl a, #0FH
	movc a, @a+dptr
	mov HEX5, a
	
	mov a, bcd+1
	anl a, #0FH
	movc a, @a+dptr
	mov HEX4, a

	mov a, bcd+0
	swap a
	anl a, #0FH
	movc a, @a+dptr
	mov HEX3, a
	
	mov a, bcd+0
	anl a, #0FH
	movc a, @a+dptr
	mov HEX2, a
	
	ret
Correct_Voltage:  ;Turns the LM355 voltage output into the current temperature 100*(Vout-2.73) Vout=(ADC/1023)*5
	Load_y(500)
	lcall mul32
	
	Load_y(100)
	lcall mul32
	
	Load_y(1023)
	lcall div32
	
	Load_y(27300)
	lcall sub32 
	
	ret
	
MyProgram: ;Clears Inputs, sets out input/output pins (Only runs once)
    MOV SP, #7FH
    mov LEDRA, #0
    mov DEG,#0
    mov LEDRB, #0
   ; mov DEG,#0
    mov r0,#0
    mov a,#0
    mov HOT,#0
    mov r1,#0
    mov LEDRC, #0
    mov Turn_Hex_6,#0
    clr p3.7
    mov LEDG, #0
    lcall InitSerialPort
    orl P0MOD, #00111000b ; make all CEs outputs  
    orl P3MOD, #11111111b ; make all CEs outputs  
	setb CE_ADC
	lcall Degrees_in_K
	orl p0mod,#00001000b
	lcall INI_SPI
		setb LCD_ON
  	setb LCD_blON
    clr LCD_EN  ; Default state of enable must be zero
    lcall Wait40us
    
    mov LCD_MOD, #0xff ; Use LCD_DATA as output port
    clr LCD_RW ;  Only writing to the LCD in this code.
	
	mov a, #0ch ; Display on command
	lcall LCD_command
	mov a, #38H ; 8-bits interface, 2 lines, 5x7 characters
	lcall LCD_command
	mov a, #01H ; Clear screen (Warning, very slow command!)
	lcall LCD_command
    
    ; Delay loop needed for 'clear screen' command above (1.6ms at least!)
    mov R1, #40
    lcall Delay
   

 

    
Forever:  ;Loop to constantly check the temperature and update Hex/LCD
	clr p3.7
	lcall clear_hot
	clr CE_ADC
	mov R0,#00000001B ; Start bit:1
	lcall DO_SPI_G
	mov R0,#10000000B ; Single ended, read channel 0
	
	lcall DO_SPI_G
	mov a, R1 ; R1 contains bits 8 and 9
	anl a, #03H ; Make sure other bits are zero
	mov x+1,a
	mov LEDRB, a ; Display the bits
	
	mov R0, #55H ; It doesn't matter what we transmit...
	lcall DO_SPI_G
	mov LEDRA, R1 ; R1 contains bits 0 to 7
	mov x+0,r1
	setb CE_ADC

	lcall correct_voltage	
	mov a, bcd+1
	swap a
	anl a, #0FH
	cjne a,#3,Dont_do_yo
	lcall is_it_hot
dont_do_yo:     
	jb Key.1,Skip4 	 ;Checks if user is attemptint to change to Celcus/Fah/Kelvin
Let_go:
	jnb Key.1,Let_go	
	lcall rotate_value
Skip4:
	lcall show_the_value		;Converts to the required temp scale	
	lcall hex2bcd				; Turns the HEX into BCD
	lcall Display_BCD			; Calls subroutine to display on Hex
	lcall sendtemp				; Sends temp to Serial Port
	lcall Current_temp			; Sends Temp to LCD
	lcall Delay					; Small Delay
	
		
	sjmp Forever				;Loops Forever

Delay:
	mov R2, #90
L3: mov R1, #250
L2: mov R0, #250
L1: djnz R0, L1
	djnz R1, L2
	djnz R2, L3
	ret
	
INI_SPI:
	orl P0MOD,#00000110b ; Set SCLK, MOSI as outputs
	anl P0MOD,#11111110b ; Set MISO as input
	clr SCLK ; Mode 0,0 default
	ret

DO_SPI_G:
	mov R1,#0 ; Received byte stored in R1
	mov R2,#8 ; Loop counter (8-bits)

DO_SPI_G_LOOP:
	mov a, R0 ; Byte to write is in R0
	rlc a ; Carry flag has bit to write
	mov R0, a
	mov MOSI, c
	setb SCLK ; Transmit
	mov c, MISO ; Read received bit
	mov a, R1 ; Save received bit in R1
	rlc a
	mov R1, a
	clr SCLK
	djnz R2, DO_SPI_G_LOOP
	ret

Degrees_in_C:		;Adds C to diplay Units
	mov HEX0, #1000110B
	lcall Setting_C
	ret
Degrees_in_F:		;Adds F to diplay Units
	mov HEX0, #0001110B
	lcall Setting_F
	ret
Degrees_in_K:		;Adds K to diplay Units
	mov HEX0, #1111111B
	lcall Setting_K
	ret
	
Rotate_Value:		;Sets DEG variable depending on current State when button is pressed
	mov r0,DEG
	cjne r0,#0,Not_C0
	lcall Degrees_in_C
	mov Deg,#1
	sjmp skip9
Not_C0:
	cjne r0,#1,Not_F0
	lcall Degrees_in_F
	mov Deg,#2
	sjmp skip9
Not_F0:
	cjne r0,#2,skip9
	lcall Degrees_in_K
	mov Deg,#0
	sjmp skip9
	
skip9:
	ret

show_the_value:		;Changes all the different values depending on the state of the DEG variable that was set above
	mov r0,DEG
	cjne r0,#2,Not_in_F

	Load_y(18)
	lcall mul32
	
	Load_Y(10)
	lcall div32
	
	Load_Y(3200)
	lcall add32

	sjmp skip0
Not_in_F:
	mov r0,DEG
	cjne r0,#0,Skip0
	
	Load_y(27315)
	lcall add32
Skip0:
	ret
	
	
	Wait40us:
	mov R0, #149
	
X1: 						;All this stuff is for the LCD display
	nop
	nop
	nop
	nop
	nop
	nop
	djnz R0, X1 ; 9 machine cycles-> 9*30ns*149=40us
    ret

LCD_command:
	mov	LCD_DATA, A
	clr	LCD_RS
	nop
	nop
	setb LCD_EN ; Enable pulse should be at least 230 ns
	nop
	nop
	nop
	nop
	nop
	nop
	clr	LCD_EN
	ljmp Wait40us

LCD_put:
	mov	LCD_DATA, A
	setb LCD_RS
	nop
	nop
	setb LCD_EN ; Enable pulse should be at least 230 ns
	nop
	nop
	nop
	nop
	nop
	nop
	clr	LCD_EN
	ljmp Wait40us
	
Setting_C:			
	lcall Wait40us
	djnz R1, Setting_C

	; Move to first column of first row	
	mov a, #0xc0
	lcall LCD_command
		
	; Display letter A
	mov a, #'C'
	lcall LCD_put
	
	mov a, #'e'
	lcall LCD_put
	
	mov a, #'l'
	lcall LCD_put
	
	mov a, #'s'
	lcall LCD_put
	
	mov a, #'i'
	lcall LCD_put
	
	mov a, #'u'
	lcall LCD_put
	
	mov a, #'s'
	lcall LCD_put
	
	mov a, #' '
	lcall LCD_put
	
	mov a, #' '
	lcall LCD_put
	
	mov a, #' '
	lcall LCD_put
	
    ret
    
Setting_F:
	lcall Wait40us
	djnz R1, Setting_F

	; Move to first column of first row	
	mov a, #0xc0
	lcall LCD_command
		
	; Display letter A
	mov a, #'F'
	lcall LCD_put
	
	mov a, #'a'
	lcall LCD_put
	
	mov a, #'h'
	lcall LCD_put
	
	mov a, #'r'
	lcall LCD_put
	
	mov a, #'e'
	lcall LCD_put
	
	mov a, #'n'
	lcall LCD_put
	
	mov a, #'h'
	lcall LCD_put
	
	mov a, #'e'
	lcall LCD_put
	
	mov a, #'i'
	lcall LCD_put
	
	mov a, #'t'
	lcall LCD_put
	
    ret

Setting_K:
	lcall Wait40us
	djnz R1, Setting_K

	; Move to first column of first row	
	mov a, #0xc0
	lcall LCD_command
		
	; Display letter A
	mov a, #'K'
	lcall LCD_put
	
	mov a, #'e'
	lcall LCD_put
	
	mov a, #'l'
	lcall LCD_put
	
	mov a, #'v'
	lcall LCD_put
	
	mov a, #'i'
	lcall LCD_put
	
	mov a, #'n'
	lcall LCD_put
	
	mov a, #' '
	lcall LCD_put
	
	mov a, #' '
	lcall LCD_put
	
	mov a, #' '
	lcall LCD_put
	
	mov a, #' '
	lcall LCD_put
	
    ret
    
Current_Temp:
	lcall Wait40us
	djnz R1, Current_Temp

	; Move to first column of first row	
	mov a, #80H
	lcall LCD_command
	mov dptr, #T_7seg
	
	mov r0,bcd+2
	cjne r0,#0,Turn_ona
	sjmp not_100a
Turn_ona:
	mov a, bcd+2
	anl a,#0FH
	orl a,#30H
	lcall LCD_PUT
	
	sjmp Continue_Dudea
	
Not_100a:
	mov a,#' '
	
Continue_dudea:			
	mov a, bcd+1
	swap a
	anl a,#0FH
	orl a, #30H
	lcall LCD_Put
	
	mov a, bcd+1
	anl a,#0FH
	orl a,#30H
	lcall LCD_PUt
	
	mov a,#'.'
	lcall LCD_PUT
	
	mov a, bcd+0
	swap a
	anl a,#0FH
	orl a, #30H
	lcall LCD_PUt
	
	mov a, bcd+0
	anl a,#0FH
	orl a,#30H
	lcall LCD_put
	
    ret	    
Not_too_hot:				;Checks if it is above the threshold number set in the code
	mov HOT,#0
	sjmp light
	
Careful_too_hot:
	mov HOT,#1
	sjmp light
is_it_hot:
	mov r0,#2 ;set this number to choose threshold
	mov a, bcd+1
	swap a
	anl a, #0FH
	mov r1,a
Intermed:

	mov a,r1
	jz not_too_hot
	
	mov a, r0 
	jz Careful_too_hot
	
	
	dec r1
	dec r0
	

	
	sjmp intermed
Light:
	mov r0, hot
	cjne r0,#1,Skip_this_step1
	lcall COOL_DOWN
	setb p3.7
	
Skip_this_step1:	
	ret

Cool_down:
	lcall Wait40us
	djnz R1, Cool_down

	; Move to first column of first row	
	mov a, #0x8D
	lcall LCD_command
		
	; Display letter A
	mov a, #'H'
	lcall LCD_put
	
	mov a, #'O'
	lcall LCD_put
	
	mov a, #'T'
	lcall LCD_put
	
    ret
    
    Clear_hot:
	lcall Wait40us
	djnz R1, Clear_hot

	; Move to first column of first row	
	mov a, #0x8D
	lcall LCD_command
		
	; Display letter A
	mov a, #' '
	lcall LCD_put
	
	mov a, #' '
	lcall LCD_put
	
	mov a, #' '
	lcall LCD_put
	
	ret
	
END
