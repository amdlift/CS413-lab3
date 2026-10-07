@ ============================================================================
@ File:    davis.s
@ Program: CS413 Lab 3 - ARM Recursive Function: Factorial
@ Class:   CS413-02
@ Term:    Fall 2026
@ Author:  Aaron Davis (amd0047@uah.edu)
@ Date:    October 7, 2026
@
@ Purpose:
@   Calculates n! using a function that calls itself.  The user is asked for
@   an integer.  The entry is read as a whole line and checked one character
@   at a time so letters, special characters and negative numbers are all
@   rejected.  The largest factorial that still fits in an unsigned 32-bit
@   integer is 12! = 479,001,600, so entries above 12 are rejected as well.
@   Bad entries print an error and the program asks again.  Once the entry is
@   good the recursive function is called, the answer is printed and the
@   program ends.
@
@ Build and run:
@   as  -o davis.o davis.s
@   gcc -o davis davis.o
@   ./davis
@ ============================================================================

@ MAX_N is the only place the limit is written down.  The prompt and the
@ range error both print it, so changing this one line is all it takes to
@ change the limit the program enforces.
@ Unsigned 32-bit holds up to 4,294,967,295.
@ 12! =   479,001,600  fits
@ 13! = 6,227,020,800  does not fit
        .equ    MAX_N, 12
        .equ    BUFSZ, 64

        .global main
        .text

@ ----------------------------------------------------------------------------
@ main
@   r4 = the number the user entered
@   r5 = the factorial returned by the recursive function
@ ----------------------------------------------------------------------------
main:
        push    {r4-r12, lr}            @ save registers for the C library;
                                        @ 10 registers keeps sp 8-byte aligned

        ldr     r0, =welcomeMsg
        mov     r1, #MAX_N
        bl      printf

@ ----------------------------------------------------------------------------
@ getInput - ask for n until readValidN says the entry is good.
@ ----------------------------------------------------------------------------
getInput:
        ldr     r0, =nPrompt
        mov     r1, #MAX_N
        bl      printf
        bl      readValidN              @ r0 = n, r1 = status
        cmn     r1, #1                  @ end of input, so quit
        beq     exitProgram
        cmp     r1, #0                  @ bad entry, so ask again
        bne     getInput
        mov     r4, r0                  @ r4 = n

@ ----------------------------------------------------------------------------
@ compute - hand n to the recursive function and keep the answer.
@ ----------------------------------------------------------------------------
        mov     r0, r4
        bl      factorial
        mov     r5, r0                  @ r5 = n!

        ldr     r0, =resultMsg          @ %u because the answer is unsigned
        mov     r1, r4
        mov     r2, r5
        bl      printf

        mov     r0, #0
        pop     {r4-r12, pc}

@ exitProgram - reached when the input stream ends before a good entry.
exitProgram:
        ldr     r0, =byeMsg
        bl      printf
        mov     r0, #0
        pop     {r4-r12, pc}


@ ============================================================================
@ factorial - the recursive function.
@   r0 on the way in  = n
@   r0 on the way out = n!
@
@ Every call pushes the caller's r4 and the return address onto the stack and
@ pops them back off on the way out.  That is what lets the function call
@ itself: each level gets its own copy of n in r4 and its own place to come
@ back to.  The deepest the stack can go here is 12 levels.
@   0! = 1 and 1! = 1 are the base cases that stop the recursion.
@   n! = n * (n-1)! is the recursive case.
@ ============================================================================
factorial:
        push    {r4, lr}                @ two registers keeps sp 8-byte aligned
        cmp     r0, #2
        blo     factBase                @ n is 0 or 1, so stop here

        mov     r4, r0                  @ r4 = n, kept safe across the call
        sub     r0, r0, #1
        bl      factorial               @ r0 = (n-1)!
        mul     r0, r4, r0              @ n * (n-1)!
        pop     {r4, pc}

factBase:
        mov     r0, #1
        pop     {r4, pc}


@ ============================================================================
@ Input subroutines
@ ============================================================================

@ ----------------------------------------------------------------------------
@ readValidN - read one line and turn it into a number.
@ Returns r0 = n and r1 = 0 when the entry is good, r1 = 1 when it is not.
@ Returns r1 = -1 when the input stream ends so main can quit.
@
@   r4 = pointer walking through the line
@   r5 = the number built up so far
@   r6 = count of digits seen
@ Error checks: an empty line, a leading minus sign, anything that is not a
@ digit, and a value larger than MAX_N are all rejected with a message.
@ ----------------------------------------------------------------------------
readValidN:
        push    {r4-r6, lr}

        ldr     r0, =inBuf              @ fgets(inBuf, BUFSZ, stdin)
        mov     r1, #BUFSZ
        ldr     r2, =stdin
        ldr     r2, [r2]
        bl      fgets
        cmp     r0, #0                  @ NULL means end of input
        beq     readEOF

        ldr     r4, =inBuf
        mov     r5, #0                  @ value so far
        mov     r6, #0                  @ digits seen so far

@ skipSpace - step past any blanks typed before the number.
skipSpace:
        ldrb    r1, [r4]
        cmp     r1, #' '
        cmpne   r1, #9                  @ tab
        addeq   r4, r4, #1
        beq     skipSpace

        cmp     r1, #'-'                @ negative numbers are not allowed
        beq     badNeg

@ digitLoop - one character per pass until the end of the line.
digitLoop:
        ldrb    r1, [r4]
        cmp     r1, #10                 @ newline ends the line
        beq     endOfLine
        cmp     r1, #13                 @ carriage return ends the line
        beq     endOfLine
        cmp     r1, #0                  @ no newline, line filled the buffer
        beq     endOfLine

        cmp     r1, #'0'                @ anything that is not a digit is
        blo     badChar                 @ a letter or a special character
        cmp     r1, #'9'
        bhi     badChar

        sub     r1, r1, #'0'            @ character to its numeric value
        mov     r2, #10
        mla     r5, r2, r5, r1          @ value = value * 10 + digit
        add     r6, r6, #1
        add     r4, r4, #1

        cmp     r5, #MAX_N              @ stop as soon as the value is too
        bhi     badRange                @ big so a long entry can not wrap

        b       digitLoop

@ endOfLine - the line is done, so make sure it actually held a number.
endOfLine:
        cmp     r6, #0                  @ no digits means the line was empty
        beq     badChar
        cmp     r5, #MAX_N
        bhi     badRange

        mov     r0, r5                  @ good entry
        mov     r1, #0
        pop     {r4-r6, pc}

@ readEOF - the input stream ended, so tell main to quit.
readEOF:
        mov     r0, #0
        mvn     r1, #0                  @ r1 = -1, the input stream ended
        pop     {r4-r6, pc}


badChar:
        ldr     r0, =errNumMsg
        bl      printf
        b       readBad

badNeg:
        ldr     r0, =errNegMsg
        bl      printf
        b       readBad

badRange:
        ldr     r0, =errRangeMsg
        mov     r1, #MAX_N
        bl      printf

readBad:
        mov     r0, #0
        mov     r1, #1                  @ tell main to ask again
        pop     {r4-r6, pc}


@ ============================================================================
@ Data
@ ============================================================================
        .data

welcomeMsg:
        .ascii  "\nFactorial Calculator\n"
        .ascii  "This program calculates n! using a recursive function.\n"
        .asciz  "The answer must fit in a 32-bit unsigned integer, so n can be at most %d.\n"

nPrompt:        .asciz  "\nEnter an integer from 0 to %d: "
resultMsg:      .asciz  "\n%d! = %u\n"

errNumMsg:      .asciz  "Error: that is not a valid integer. Digits only.\n"
errNegMsg:      .asciz  "Error: negative numbers are not allowed.\n"
errRangeMsg:    .asciz  "Error: that value is too large. %d! is the biggest factorial that fits in 32 bits.\n"
byeMsg:         .asciz  "\nNo more input. Goodbye!\n"

        .balign 4
inBuf:          .space  BUFSZ
