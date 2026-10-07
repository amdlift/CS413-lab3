@=============================================================================
@ File:        davis.s
@ Class:       CS 413-02
@ Term:        Fall 2026
@ Author:      Aaron Davis
@ Email:       amd0047@uah.edu
@ Date:        October 7, 2026
@
@-----------------------------------------------------------------------------
@ PURPOSE OF SOFTWARE
@-----------------------------------------------------------------------------
@ This program simulates a single serve coffee machine of the kind sold under
@ the Keurig name.  The machine starts with a full 48 ounce water reservoir.
@
@ The user is shown a welcome message and presses B to begin brewing or T to
@ turn the machine off.  After pressing B the user picks a cup size:
@
@       Small    6 ounces
@       Medium   8 ounces
@       Large   10 ounces
@
@ The machine then checks the reservoir.  If there is not enough water left
@ for the size that was picked, an error is shown and the user is asked for a
@ smaller size.  If there is enough water the machine reports that it is ready
@ to brew, asks for a cup to be placed in the tray and waits for B to be
@ pressed again before dispensing.
@
@ After every cup the reservoir is checked.  Once it falls below 6 ounces, the
@ smallest cup the machine can make, a refill message is shown and the machine
@ turns itself off.
@
@ A hidden code may be typed at ANY prompt.  It reports how much water is left
@ and how many cups of each size have been made since the machine was started.
@ The code is the word COFFEE and is not mentioned in any of the menus, which
@ is what makes it hidden.
@
@-----------------------------------------------------------------------------
@ BUILD / RUN / DEBUG COMMANDS
@-----------------------------------------------------------------------------
@   Assemble:  as -g -o davis.o davis.s
@   Link:      gcc -o davis davis.o
@   Run:       ./davis
@   Debug:     gdb ./davis
@
@=============================================================================

@-----------------------------------------------------------------------------
@ MACHINE CONSTANTS
@ These are gathered here so the capacity of the machine and the cup sizes can
@ be changed in one place instead of being scattered through the code.
@-----------------------------------------------------------------------------
        .equ    RESERVOIR_OZ, 48        @ a full reservoir
        .equ    SMALL_OZ,      6        @ also the shut off level, because the
        .equ    MEDIUM_OZ,     8        @ machine cannot make anything smaller
        .equ    LARGE_OZ,     10        @ than a small cup
        .equ    BUFSZ,        64        @ room for one typed line

        .global main
        .text

@=============================================================================
@ main
@
@ The machine state is kept in the callee saved registers so that it survives
@ every call to printf and fgets without having to be written back to memory:
@
@       r4 = ounces of water left in the reservoir
@       r5 = number of small cups dispensed
@       r6 = number of medium cups dispensed
@       r7 = number of large cups dispensed
@       r8 = size in ounces of the cup the user is currently ordering
@=============================================================================
main:
        push    {r4-r12, lr}            @ save registers for the C library;
                                        @ 10 registers keeps sp 8-byte aligned

        mov     r4, #RESERVOIR_OZ       @ the reservoir is filled at startup
        mov     r5, #0                  @ no cups have been made yet
        mov     r6, #0
        mov     r7, #0

@-----------------------------------------------------------------------------
@ welcomeLoop - the machine sits here between cups waiting to be started.
@ One pass per key the user presses.  The loop repeats rather than falls
@ through when the hidden code is typed or the key is not one we recognize,
@ so the welcome message is always on screen when input is expected.
@-----------------------------------------------------------------------------
welcomeLoop:
        ldr     r0, =welcomeMsg
        bl      printf

        bl      getCommand              @ r0 = status, r1 = key pressed
        cmn     r0, #1                  @ input ended, treat it as power off
        beq     machineOff
        cmp     r0, #1                  @ hidden code was handled for us, so
        beq     welcomeLoop             @ just show the welcome again

        cmp     r1, #'B'                @ B begins a cup of coffee
        beq     sizeLoop
        cmp     r1, #'T'                @ T turns the machine off
        beq     machineOff

        ldr     r0, =errWelcomeMsg      @ error check: any other key is not a
        bl      printf                  @ machine control, so say so and wait
        b       welcomeLoop

@-----------------------------------------------------------------------------
@ sizeLoop - ask which cup size the user wants.
@ This is also where we come back to after telling the user there is not
@ enough water left, which is how the handout asks for a smaller size to be
@ offered rather than cancelling the order outright.
@-----------------------------------------------------------------------------
sizeLoop:
        ldr     r0, =sizeMsg
        bl      printf

        bl      getCommand
        cmn     r0, #1
        beq     machineOff
        cmp     r0, #1
        beq     sizeLoop

        cmp     r1, #'S'                @ translate the key into the number of
        moveq   r8, #SMALL_OZ           @ ounces that size will cost us, which
        beq     checkWater              @ is all the rest of the code needs
        cmp     r1, #'M'
        moveq   r8, #MEDIUM_OZ
        beq     checkWater
        cmp     r1, #'L'
        moveq   r8, #LARGE_OZ
        beq     checkWater
        cmp     r1, #'T'                @ let the user quit from here too so
        beq     machineOff              @ they are never trapped at a prompt

        ldr     r0, =errSizeMsg         @ error check: not one of the three
        bl      printf                  @ sizes the machine can pour
        b       sizeLoop

@-----------------------------------------------------------------------------
@ checkWater - make sure the reservoir can cover the size that was ordered.
@ Both values are small positive counts, so an unsigned compare is safe.
@-----------------------------------------------------------------------------
checkWater:
        cmp     r4, r8
        blo     notEnough               @ less water than this cup needs

        ldr     r0, =readyMsg           @ enough water, so walk the user
        bl      printf                  @ through placing a cup and starting

@-----------------------------------------------------------------------------
@ brewLoop - wait for B to actually start the brew.
@ The order is already accepted at this point, so nothing here changes the
@ water level; we only loop until a valid key arrives.
@-----------------------------------------------------------------------------
brewLoop:
        bl      getCommand
        cmn     r0, #1
        beq     machineOff
        cmp     r0, #1
        beq     brewPrompt              @ hidden code: reprint what we want

        cmp     r1, #'B'                @ B starts the brew
        beq     dispense
        cmp     r1, #'T'
        beq     machineOff

        ldr     r0, =errBrewMsg         @ error check: the machine is loaded
        bl      printf                  @ and waiting, it only accepts B here
        b       brewLoop

@ brewPrompt - repeat the start instruction after the status report scrolled
@ it off the screen, so the user still knows what the machine is waiting for.
brewPrompt:
        ldr     r0, =pressBrewMsg
        bl      printf
        b       brewLoop

@-----------------------------------------------------------------------------
@ notEnough - the reservoir cannot cover the size that was ordered.
@ The handout asks that the user be allowed to pick a smaller cup instead of
@ the machine giving up, so this returns to the size prompt.
@-----------------------------------------------------------------------------
notEnough:
        ldr     r0, =errWaterMsg
        mov     r1, r4                  @ show what is actually left so the
        bl      printf                  @ user can pick a size that will fit
        b       sizeLoop

@-----------------------------------------------------------------------------
@ dispense - pour the cup and update the machine state.
@ The size in r8 tells us both how much water to take and which counter to
@ add to, so the conditional adds below need no branches.
@-----------------------------------------------------------------------------
dispense:
        sub     r4, r4, r8              @ take the water out of the reservoir

        cmp     r8, #SMALL_OZ
        addeq   r5, r5, #1
        cmp     r8, #MEDIUM_OZ
        addeq   r6, r6, #1
        cmp     r8, #LARGE_OZ
        addeq   r7, r7, #1

        ldr     r0, =dispensedMsg
        bl      printf

        cmp     r4, #SMALL_OZ           @ the handout asks for this check after
        blo     needRefill              @ EVERY cup, not just when empty
        b       welcomeLoop

@-----------------------------------------------------------------------------
@ needRefill - too little water left for even the smallest cup, so the machine
@ cannot serve anyone else until a person refills it.
@-----------------------------------------------------------------------------
needRefill:
        ldr     r0, =refillMsg
        mov     r1, r4
        bl      printf
        b       exitProgram

@ machineOff - normal power off, reached from T at any prompt or from the end
@ of the input stream.
machineOff:
        ldr     r0, =offMsg
        bl      printf

@ exitProgram - hand control back to the operating system.
exitProgram:
        mov     r0, #0
        pop     {r4-r12, pc}


@=============================================================================
@ SUBROUTINES
@=============================================================================

@-----------------------------------------------------------------------------
@ getCommand - read one typed line and turn it into a single command key.
@
@ Every prompt in the program reads input through this one subroutine.  That
@ is deliberate: it is the reason the hidden code works at any prompt without
@ each prompt having to test for it.
@
@ Returns:
@       r0 = -1  the input stream ended; the caller should power the machine
@                off instead of looping forever on an empty read
@       r0 =  1  the line was the hidden code and the report has already been
@                printed; the caller should prompt again
@       r0 =  0  a command was entered and r1 holds it:
@                  r1 = the key, as an uppercase character
@                  r1 = 0 when the line was not exactly one character, which
@                       the caller reports with its own error message
@
@ Only r0-r3 are used for working values so the machine state in r4-r8 is
@ untouched.
@-----------------------------------------------------------------------------
getCommand:
        push    {r4, lr}                @ two registers keeps sp 8-byte aligned

        ldr     r0, =inBuf              @ fgets(inBuf, BUFSZ, stdin)
        mov     r1, #BUFSZ
        ldr     r2, =stdin
        ldr     r2, [r2]
        bl      fgets
        cmp     r0, #0                  @ error check: NULL means there is no
        beq     cmdEndOfInput           @ more input coming, ever

        bl      trimAndUpper            @ tidy the line before looking at it

        ldr     r0, =inBuf              @ is this the hidden code?
        ldr     r1, =hiddenCode
        bl      strEquals
        cmp     r0, #0
        bne     cmdHidden

        ldr     r0, =inBuf              @ a command is one character and then
        ldrb    r1, [r0]                @ the end of the line.  Anything longer
        ldrb    r2, [r0, #1]            @ is a typing mistake, so r1 is cleared
        cmp     r2, #0                  @ and the caller reports it.
        movne   r1, #0

        mov     r0, #0
        pop     {r4, pc}

@ cmdHidden - the hidden code was entered, so report and tell the caller to
@ prompt again rather than treating the code as a command.
cmdHidden:
        bl      showStatus
        mov     r0, #1
        mov     r1, #0
        pop     {r4, pc}

@ cmdEndOfInput - report the end of input through r0.  This must NOT jump
@ straight to the exit in main, because this subroutine's own frame is still
@ on the stack and main's POP would restore the wrong registers.
cmdEndOfInput:
        mvn     r0, #0                  @ r0 = -1
        mov     r1, #0
        pop     {r4, pc}

@-----------------------------------------------------------------------------
@ trimAndUpper - clean up the line sitting in inBuf, in place.
@ The newline that fgets keeps is cut off, and lowercase letters are folded to
@ uppercase so a user who types b or coffee is treated the same as one who
@ types B or COFFEE.
@
@ r0 walks the buffer, r1 holds the character being looked at.
@-----------------------------------------------------------------------------
trimAndUpper:
        ldr     r0, =inBuf

@ trimLoop - one character per pass until the line ends.
trimLoop:
        ldrb    r1, [r0]
        cmp     r1, #0                  @ end of the string
        beq     trimDone
        cmp     r1, #10                 @ newline ends the line
        beq     trimCut
        cmp     r1, #13                 @ carriage return ends the line too,
        beq     trimCut                 @ so files with CRLF still work

        cmp     r1, #'a'                @ fold lowercase to uppercase by
        blo     trimNext                @ clearing the 0x20 bit
        cmp     r1, #'z'
        bhi     trimNext
        sub     r1, r1, #32
        strb    r1, [r0]

trimNext:
        add     r0, r0, #1
        b       trimLoop

@ trimCut - replace the line ending with a terminator so the rest of the
@ program sees a plain string.
trimCut:
        mov     r1, #0
        strb    r1, [r0]

trimDone:
        bx      lr

@-----------------------------------------------------------------------------
@ strEquals - compare two zero terminated strings.
@       r0 = address of the first string
@       r1 = address of the second string
@ Returns r0 = 1 when they match and r0 = 0 when they do not.
@
@ r2 and r3 hold the pair of characters being compared.
@-----------------------------------------------------------------------------
strEquals:

@ eqLoop - one character from each string per pass.
eqLoop:
        ldrb    r2, [r0], #1
        ldrb    r3, [r1], #1
        cmp     r2, r3
        bne     eqNo                    @ a difference means no match
        cmp     r2, #0                  @ both ended at the same place, so
        bne     eqLoop                  @ the strings are equal

        mov     r0, #1
        bx      lr

eqNo:
        mov     r0, #0
        bx      lr

@-----------------------------------------------------------------------------
@ showStatus - print the hidden code report.
@
@ printf only takes three values in r1-r3, and these four lines each carry
@ their own label anyway, so the report is printed one line per call.
@ The counters live in r4-r7, which printf is required to preserve, so they
@ are still correct between the calls.
@-----------------------------------------------------------------------------
showStatus:
        push    {r8, lr}                @ two registers keeps sp 8-byte aligned

        ldr     r0, =waterMsg
        mov     r1, r4
        bl      printf
        ldr     r0, =smallMsg
        mov     r1, r5
        bl      printf
        ldr     r0, =mediumMsg
        mov     r1, r6
        bl      printf
        ldr     r0, =largeMsg
        mov     r1, r7
        bl      printf

        pop     {r8, pc}


@=============================================================================
@ DATA
@ Every string the program can print is defined here rather than being built
@ in the code, so the wording can be changed without touching the logic.
@=============================================================================
        .data

@ The hidden code.  It is only ever compared against, never printed, so the
@ user has no way to discover it from the menus.
hiddenCode:     .asciz  "COFFEE"

welcomeMsg:
        .ascii  "\nWelcome to the Coffee Maker\n\n"
        .ascii  "Insert K-cup and press B to begin making coffee.\n\n"
        .asciz  "Press T to turn off the machine.\n\n> "

sizeMsg:
        .ascii  "\nSelect your cup size:\n"
        .ascii  "  S  Small  (6 oz)\n"
        .ascii  "  M  Medium (8 oz)\n"
        .asciz  "  L  Large  (10 oz)\n\n> "

readyMsg:
        .ascii  "\nReady to Brew\n"
        .ascii  "Place cup in tray\n"
        .asciz  "Press B (and enter) to start brewing.\n\n> "

@ Printed on its own when the status report has pushed the ready message out
@ of sight, so the user is not left guessing.
pressBrewMsg:   .asciz  "\nPress B (and enter) to start brewing.\n\n> "

dispensedMsg:   .asciz  "\nCoffee has been dispensed\n"

@ The hidden code report.
waterMsg:       .asciz  "\nWater level: %d\n"
smallMsg:       .asciz  "Small: %d\n"
mediumMsg:      .asciz  "Medium: %d\n"
largeMsg:       .asciz  "Large: %d\n"

@ Error messages.  Each prompt has its own so the user is told what is valid
@ where they actually are, instead of getting one vague complaint.
errWelcomeMsg:  .asciz  "\nThat is not a valid choice. Press B to begin or T to turn the machine off.\n"
errSizeMsg:     .asciz  "\nThat is not a valid cup size. Enter S, M or L.\n"
errBrewMsg:     .asciz  "\nThe machine is waiting to brew. Press B to start.\n"
errWaterMsg:    .asciz  "\nThere is not enough water for that size. Only %d oz remain.\nPlease select a smaller cup size.\n"

refillMsg:      .asciz  "\nOnly %d oz of water remain, which is not enough for a small cup.\nPlease refill the reservoir. Turning off the machine.\n\n"
offMsg:         .asciz  "\nTurning off the machine. Goodbye!\n\n"

        .balign 4
inBuf:          .space  BUFSZ
