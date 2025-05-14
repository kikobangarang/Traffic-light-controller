; Definicao dos valores dos simbolos utilizados no programa
;
	.equ	CPSR_BIT_I, 0b010000          ; Mascara para o bit I do registo CPSR

	.equ	STACK_SIZE, 64                ; Dimensao do stack - 64 B

	; Definicoes do porto de entrada
	.equ	INPORT_ADDRESS, 0xFF80        ; Endereco do porto de entrada

	; Definicoes do porto de saida
	.equ	OUTPORT_ADDRESS, 0xFFC0       ; Endereco do porto de saida

	.equ	OUTPORT_INIT_VAL, 0           ; Valor inicial do porto de saida

	; Definicoes do circuito pTC

	.equ	PTC_ADDRESS,  0xFF40          ; Endereco do circuito pTC


	.equ	PTC_TCR, 0                    ; Deslocamento do registo TCR do pTC
	.equ	PTC_TMR, 2                    ; Deslocamento do registo TMR do pTC
	.equ	PTC_TC,  4                    ; Deslocamento do registo TC do pTC
	.equ	PTC_TIR, 6                    ; Deslocamento do registo TIR do pTC

	.equ	PTC_CMD_START, 0              ; Comando para iniciar a contagem no pTC
	.equ	PTC_CMD_STOP, 1               ; Comando para parar a contagem no pTC

	.equ	SYSCLK_FREQ, 0x63             ; Intervalo de contagem do circuito pTC que suporta a implementação do sysclk

	.EQU pedestrian_mask, 0b1
	.EQU config_mask, 0b10000
	.EQU BLINK_TIME, 5
	.EQU Crossing_time, 100         
	.EQU SET_TIME_MASK, 0b11100000

; Seccao:    startup
; Descricao: Guarda o código de arranque do sistema
.section startup
	b	_start
	ldr pc, isr_addr


_start:
	ldr	sp, stack_top_addr ; inicializar a stack
    mov r0, pc
    add lr, r0, #4
	ldr	pc, init_addr
    b   .

	stack_top_addr:
		.word	stack_top
	init_addr:
		.word	init
	isr_addr:
		.word	isr

; Seccao:    text
; Descricao: Guarda o código do programa

.text


init:
	mov	r0, #OUTPORT_INIT_VAL
	bl	outport_init ; Inicialização do outport
	mov	r0, #SYSCLK_FREQ 
	bl	sysclk_ptc_init ; Inicialização do sysclock e do ptc
	

	mrs	r0, cpsr
	mov	r1, #CPSR_BIT_I
	orr	r0, r0, r1
	MSR cpsr,r0

    bl inport_read          ; ler porto
	MOV R4, #pedestrian_mask 
    AND R3, R0, R4          ; criar valor inicial para pedestrian

	mov r8, #Crossing_time

    b main
main:
    bl inport_read 			; ler porto
	MOV R2, #config_mask 	
    AND R1, R0, R2 			; obter valor de config
    cmp R1, R2 				; comparar valor de config com a mascara
    BEQ maintenance_flashing_init   ; se for igual entrar em state maintenance

	MOV R4, #pedestrian_mask
    AND R1, R0, R4          ; obter valor de pedestrian
    cmp R3, R1              ; comparar valor de pedestrian com valor anterior
    blo crossing            ; se a transição for ascendente entra

	MOV R3, R1              ; Atualizar o pedestrian pressed prev para R1
	bl flash_init ; entrar na rotina que pisca os leds para circulação de carros

    b main


flash_init:
    MOV R0, #0b00100111     ; Máscara para ligar as leds necessárias (LED1=amarelo, LED2=vermelho, LED3=verde)
    bl outport_write        ; escrever no porto
    bl sysclk_get_ticks     ; obter tempo inicial
    MOV R4, R1 
    bl flashing_on


flashing_on:
    bl sysclk_get_ticks     ; obter tempo atual
    SUB R0, R1, R4          ; tempo inicial - tempo atual
	MOV R6, #BLINK_TIME 
    cmp R0, R6              ; se tempo inicial - tempo atual >= BLINK_TIME
    bhs flashing_off_init 
    b flashing_on           ; repetir loop até a condição ser verdadeira

flashing_off_init:
    MOV R0, #0b00100100     ; Máscara para desligar as leds necessárias (LED1=apagado, LED2=vermelho, LED3=verde)
    bl outport_write        ; escrever no porto
    bl sysclk_get_ticks     ; obter tempo inicial
    MOV R4, R1
    bl flashing_off

flashing_off:
    bl sysclk_get_ticks     ; obter tempo atual
	SUB R0, R1, R4          ; tempo inicial - tempo atual
	MOV R6, #BLINK_TIME 
    cmp R0, R6              ; se tempo inicial - tempo atual >= BLINK_TIME
    bhs main
    b flashing_off         ; repetir loop até a condição ser verdadeira






maintenance_flashing_init:
	MOV R0, #0b00111011     ; Máscara para ligar as leds necessárias (LED1=amarelo, LED2=verde, LED3=amarelo)
    bl outport_write 

	bl set_time             ; Mudar o tempo de acordo com o input

    bl sysclk_get_ticks     ; obter tempo inicial
    MOV R4, R1 

	bl inport_read
	mov R7, #config_mask
	AND R0, R0, R7 			; Verificar se botão maintenance foi desligado
	cmp R0, R7
	BEQ maintenance_flashing      ; Se não tiver sido
    b main

maintenance_flashing:
    bl sysclk_get_ticks
    SUB R0, R1, R4          ; tempo init - tempo atual
	MOV R6, #BLINK_TIME
    cmp R0, R6 
    bhs maintenance_flashing_off_init ; tempo init - tempo atual >= BLINK_TIME
    b maintenance_flashing  ; repetir loop até a condição ser verdadeira

maintenance_flashing_off_init:
    MOV R0, #0b00110000     ; Máscara para ligar as leds necessárias (LED1=apagado, LED2=apagado, LED3=amarelo)
    bl outport_write
    bl sysclk_get_ticks     ; obter tempo inicial
    MOV R4, R1
    bl maintenance_flashing_off

maintenance_flashing_off:
    bl sysclk_get_ticks     ; obter tempo atual
    SUB R0, R1, R4          ; tempo inicial - tempo atual
	mov R6, #BLINK_TIME
    cmp R0, R6
    bhs maintenance_flashing_init ; tempo init - tempo atual >= BLINK_TIME
    b maintenance_flashing_off ; repetir loop até a condição ser verdadeira

; Rotina:    isr
; Descricao: Incrementa o valor da variável global sysclk.
isr:
	push r0
	push r1 ; 6clks

	ldr r0, sysclk_ADDR1 ; 6clks
	ldr r1, [r0, #0]
	add r1, r1, #1 ;3 clks
	str r1, [r0, #0] ; 6clks
	; Reiniciar o TIR
	mov r0, #PTC_ADDRESS & 0xFF
	movt r0, #PTC_ADDRESS >> 8 & 0xFF
	;==
	mov R1, #0
	;==
	strb r1, [r0, #PTC_TIR]

	pop r1
	pop r0
	movs pc, lr

sysclk_ADDR1:
	.word sysclk

; Rotina:    sysclk_ptc_init
; Descricao: Inicia uma nova contagem no periferico pTC com o intervalo de
;            contagem recebido em R0, em ticks, limpando eventuais pedidos de
;            interrupcao pendentes e iniciando com o valor zero a variavel
;            global sysclk.
; Entradas:  R0 - Valor do novo intervalo de contagem, em ticks.
sysclk_ptc_init:
	push lr
	; colocar sysclock a 0
    ldr     r1, sysclk_ADDR
    mov     r2, #0
    strb    r2, [r1]

	; Faz a iniciacao do periférico pTC, habilitando o seu funcionamento em modo continuo e com o intervalo de contagem SYSCLK_FREQ em ticks.

	; tirar pedidos de interrupção
    bl ptc_clr_irq             
	
	;Definir novo intervalo do PTC	
	mov r0, #PTC_ADDRESS & 0xFF
	movt r0, #PTC_ADDRESS >> 8 & 0xFF

	; Para a contagem no periferico pTC.
	mov     r2, #PTC_CMD_STOP
	mov 	r1, #SYSCLK_FREQ
	strb    r2, [r0, #PTC_TCR]      
    strb    r1, [r0, #PTC_TMR]

	; Habilita a contagem no periferico pTC.
    mov     r2, #PTC_CMD_START
    strb    r2, [r0, #PTC_TCR]

	pop pc


; Rotina: sysclk_get_ticks
; Devolve o valor corrente da variável global sysclk. 
; Saidas:    - R1 - É o valor do sysclk 
sysclk_get_ticks:
	ldr     r0, sysclk_ADDR             
	ldr     r1, [r0]                
    mov     pc, lr  
	sysclk_ADDR:
		.word sysclk



; Pedestre a passar, os leds precisam de estar: (LED1=vermelho, LED2=verde, LED3=verde)
crossing: 
	MOV R3, R1   ; Atualizar o pedestrian pressed prev para R1
    MOV R0, #0b00101001 ; Máscara para ligar as leds necessárias (LED1=vermelho, LED2=verde, LED3=verde)
    bl outport_write
    bl sysclk_get_ticks ; obter tempo inicial
    MOV R2, R1
    bl crossing_check

crossing_check:
	bl inport_read
	MOV R4, #pedestrian_mask
    AND R1, R0, R4          ; obter valor de pedestrian
    cmp R3, R1              ; comparar valor de pedestrian com valor anterior
	blo crossing
	mov R3, R1

	bl sysclk_get_ticks ; obter tempo atual
    SUB R0, R1, R2 ; tempo inicial - tempo atual
    cmp R0, R8 ; se tempo inicial - tempo atual >= Crossing_time
    bhs main
    b crossing_check ; repetir loop até a condição ser verdadeira

; Gestor de periférico para o porto de entrada

; Rotina:    inport_read
; Descricao: Adquire e devolve o valor corrente do porto de entrada.
; Saidas:    R0 - valor adquirido do porto de entrada
inport_read:
	ldr	r1, inport_addr
	ldrb	r0, [r1, #0]
	mov	pc, lr

inport_addr:
	.word	INPORT_ADDRESS

; Gestor de periférico para o porto de saída

; Rotina:    outport_init
; Descricao: Faz a iniciacao do porto de saida, nele estabelecendo o valor recebido em R0.
; Entradas:  R0 - Valor a atribuir ao porto de saida.
outport_init:
	push	lr
	ldr	r1, outport_img_addr
	strb	r0, [r1]
	bl	outport_write
	pop	pc


outport_img_addr:
	.word	outport_img

; Rotina:    outport_write
; Descricao: Escreve no porto de saida o valor recebido em R0.
; Entradas:  R0 - valor a atribuir ao porto de saida.
outport_write:
	ldr	r1, outport_addr
	strb r0, [r1, #0]
	mov	pc, lr

outport_addr:
	.word	OUTPORT_ADDRESS

; Gestor de periférico para o Pico Timer/Counter (pTC)

; Rotina:    ptc_clr_irq
; Descricao: Sinaliza o periferico pTC que foi atendido um pedido de interrupção.
ptc_clr_irq:
	ldr	r3, PTC_ADDR
	mov r5, #0
	strb	r5, [r3, #PTC_TIR]
	mov	pc, lr

PTC_ADDR:
	.word	PTC_ADDRESS

; Rotina:    set_time
; Descricao: Modifica o crossing time, de acordo com o input recebido
set_time:
	push lr	
	bl inport_read ; ler porto de entrada
	mov r1,#SET_TIME_MASK
	and r1, r0, r1 ; obter os 3 bits mais significativos
	lsr r1, r1, #4 ; realizar 4 shifts right para ter os 3 bits na posição mais a direita
	ldr r5, array_of_time_addr 
	ldr r8, [r5,r1]  ; obter da lista de tempos o tempo com offset r1

	pop pc

	array_of_time_addr:
	.word array_of_time
; Seccao:    data
; Descricao: Guarda as variáveis globais
.data


	sysclk:
		.space	2
	outport_img:
		.space	1

		.align
	array_of_time:
		.word 100,150,200,250,300,450,500,600


; Seccao:    stack
; Descricao: Implementa a pilha com o tamanho definido pelo simbolo STACK_SIZE
	.stack
	.space	STACK_SIZE
stack_top:
