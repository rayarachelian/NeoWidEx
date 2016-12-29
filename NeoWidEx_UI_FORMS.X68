*-----------------------------------------------------------
* Title      : NeoWidEx_UI
* Written by : Tom Stepleton
* Date       : XX November 2016
* Description:
*   Formatting and diagnostic tool for Widget drives,
*   inspired by the WidEx utility internal to Apple, and by
*   Patrick Schäfer's UsbWidEx hardware tool.
*   -- This file: Form subroutines, data, and scratch areas.
*      Equates from NeoWidEx_DEFS must be defined.
*      Macros from NeoWidEx_MACROS must be defined.
*-----------------------------------------------------------


* NeoWidEx UI FORMS code ===================================

    ; FORM -- Present a form with up to four numerical fields to the user
    ; Args:
    ;   A0: Address of form template
    ;   A1: Address of an array of prompt strings for the four fields
    ;   A2: If nonzero, address of an array of initial field values
    ;   A3: If nonzero, address of an array of upper bounds (inclusive)
    ; Notes:
    ;   Trashes D0-D3/A0-A4
    ;   TODO: add notes
FORM:
    ; First, prepare all "temporaries" used by this subroutine.
    mMemCpy A1,#z_FPromptAddrs,#(4*4)  ; Copy field prompt addresses

    MOVE.L  A2,D0                    ; Just to test: init. field vals supplied?
    BNE.S   .c0                      ; Yes, skip ahead to copy them
    mMemSet #0,#zFieldValues,#(4*4)  ; No, fill it with zeros
    mMemSet #0,#z_FFieldResets,#(4*4)  ; Same for the default/reset values
    BRA.S   .cb                      ; Skip ahead to copy upper bounds
.c0 mMemCpy A2,#zFieldValues,#(4*4)  ; Copy initial field values
    mMemCpy A2,#z_FFieldResets,#(4*4)  ; Also to the default/reset values

.cb MOVE.L  A3,D0                    ; Just to test: upper bounds specified?
    BNE.S   .c1                      ; Yes, skip ahead to copy them
    mMemSet #$FF,#z_FFieldBounds,#(4*4)  ; No, fill it with maxuints
    BRA.S   .c2                      ; Skip ahead to scan the form template
.c1 mMemCpy A3,#z_FFieldBounds,#(4*4)  ; Copy upper bounds

.c2 CLR.L   z_FFieldSizes            ; All zeros into field sizes

    ; Next, scan the form template to find the locations and sizes of the
    ; fields. We also count the number of rows the template has as one plus
    ; the number of $0D characters inside.
    ; TODO: save registers
    MOVE.L  A0,-(A7)                 ; Save form template address to stack
    CLR.B   D0                       ; Row count accumulates in D0
    CLR.B   D1                       ; Current column accumulates in D1
    CLR.W   D2                       ; Prepare D2 for use as a table index

.sl CMPI.B  #$0D,(A0)                ;   Top of loop; is this a carriage return?
    BNE.S   .s0                      ;   No, skip ahead to next check
    ADDQ.B  #1,D0                    ;   Yes, increment row count...
    CLR.B   D1                       ;   ...zero out current column...
    BRA.S   .s3                      ;   ...and go to bottom of loop (for incr.)

.s0 CMPI.B  #'a',(A0)                ;   Is this byte less than ASCII 'a'?
    BLO.S   .s2                      ;   Yes, skip ahead to the next character
    CMPI.B  #'d',(A0)                ;   Is this byte greater than ASCII 'd'?
    BHI.S   .s2                      ;   Yes, skip ahead to the next character

    MOVE.B  (A0)+,D2                 ;   Copy field ID to D2, move to next char
    SUBI.B  #'a',D2                  ;   Turn D2 into a 0-based index
    LEA     z_FFieldRows,A1          ;   Rows table base into A1
    MOVE.B  D0,0(A1,D2.W)            ;   Save row into row table
    LEA     z_FFieldCols,A1          ;   Columns table base into A1
    MOVE.B  D1,0(A1,D2.W)            ;   Save column into columns table
    ADDQ.B  #1,D1                    ;   Increment column (since we bumped A0)

    MOVE.B  (A0),D3                  ;   Copy field size to D3
    SUBI.B  #'0',D3                  ;   Turn ASCII into a number
    LEA     z_FFieldSizes,A1         ;   Field sizes base into A1
    MOVE.B  D3,0(A1,D2.W)            ;   Save field size into field sizes table

    LSL.B   #1,D3                    ;   D3 *= 2 for field size in chars
    SUBQ.B  #2,D3                    ;   D3 -= 2 for chars already used
.s1 TST.B   D3                       ;   Any chars left in field to skip?
    BEQ.S   .s2                      ;   No, skip ahead
    ADDQ.L  #1,A0                    ;   Yes, increment current char
    ADDQ.B  #1,D1                    ;   And increment current column as well
    SUBQ.B  #1,D3                    ;   Decrement characters left in field
    BRA.S   .s1                      ;   Keep skipping chars in field if needed

.s2 ADDQ.B  #1,D1                    ;   Next char; increment column
.s3 TST.B   (A0)+                    ;   But was last char the end? (Note incr.)
    BNE.S   .sl                      ;   No, back to top of loop

    MOVE.L  (A7)+,A0                 ; Recover form address from top of stack

    ; If no fields were discovered, exit now to avoid an infinite loop.
    TST.L   z_FFieldSizes            ; Are there any fields?
    BNE.S   .o0                      ; Yes, continue
    RTS                              ; No, return to caller

    ; Collected field rows are all offset from the first row of the template.
    ; We want offsets from the template's last row: numbers <= 0.
.o0 SUB.B   D0,z_FFieldRows
    SUB.B   D0,(z_FFieldRows+1)
    SUB.B   D0,(z_FFieldRows+2)
    SUB.B   D0,(z_FFieldRows+3)

    ; Display form template in the console window
    mPrtMem kCrtRow,kCrtCol,#kFirstCol,export,A0

    ; Initialise UI
    CLR.W   D0                       ; Start off editing the first field
    LEA     zFieldValues,A0          ; Field values array into A0
    LEA     z_FFieldRows,A1          ; Field rows array into A1
    LEA     z_FFieldCols,A2          ; Field columns array into A2
    LEA     z_FFieldSizes,A3         ; Field sizes array into A3
    BSR     _REFRESHFORM             ; Fill in current field values

    ; At last, the main UI loop!
.ui TST.B   0(A3,D0.W)               ;   Does this field exist in the form?
    BEQ     .u9                      ;   No, so on to the next field

    JSR     kMakeDbox                ;   Show dialogue box
    BSR     _FIELDPOS                ;   Position of current field into D1,D2
    BSR     _BLANKFIELD              ;   Overlay ?-blocks onto current field

    MOVE.W  #kDboxRow,D1             ;   Dialog box pixel row to D1
    MOVE.W  #kDboxColumn,D2          ;   Dialog box character column to D2
    LEA     z_FPromptAddrs,A4        ;   Field prompt pointer array into A4
    LSL.W   #2,D0                    ;   D0 *= 4 for indirect addressing
    MOVE.L  0(A4,D0.W),-(A7)         ;   Prompt string pointer onto stack
    mPrint  D1,D2,#kFirstCol,s,<'? '>    ; Print prompt into dialog box
    LSR.W   #2,D0                    ;   Restore D0: D0 /= 4
    ; TODO: Print cursor-like marker in appropriate spot
    BSR     _FILLFIELD               ;   Print field contents into dialog box

   MOVE.L D0,-(A7)
._ JSR    kWait4Input
   TST.B  D0
   BPL.S  ._
   MOVE.L (A7)+,D0

    BSR     _FIELDPOS                ;   Position of current field into D1,D2
    BSR     _FILLFIELD               ;   Fill in current field value

.u9 ADDQ.W  #1,D0                    ;   Advance to next field
    CMPI.W  #4,D0                    ;   Or do we need to rewind to field 0?
    BLO     .ui                      ;   No, so back to top of UI loop
    CLR.W   D0                       ;   Yes, so rewind to field 0
    BRA     .ui                      ;   And back to top of UI loop

    ; Finally, cleanup
.rt JSR     kClearDbox               ; Delete dialogue box
    RTS                              ; Return to caller

    ; Test code now: just show the template and cover the fields with ?-blocks.
 ;mResetP
 ;LEA zFieldValues,A1
 ;mPrint  kCrtRow,kCrtCol,#kFirstCol,qpendl,<'FIELD VALUES'>
 ;mDump.L kCrtRow,kCrtCol,#kFirstCol,A1,#4,qpendl

 ;LEA z_FFieldBounds,A1
 ;mPrint  kCrtRow,kCrtCol,#kFirstCol,qpendl,<'FIELD BOUNDS'>
 ;mDump.L kCrtRow,kCrtCol,#kFirstCol,A1,#4,qpendl

 ;LEA z_FPromptAddrs,A1
 ;mPrint  kCrtRow,kCrtCol,#kFirstCol,qpendl,<'PROMPT ADDRESSES'>
 ;mDump.L kCrtRow,kCrtCol,#kFirstCol,A1,#4,qpendl

 ;LEA z_FFieldRows,A1
 ;mPrint  kCrtRow,kCrtCol,#kFirstCol,qpendl,<'FIELD ROWS'>
 ;mDump.B kCrtRow,kCrtCol,#kFirstCol,A1,#4,qpendl

 ;LEA z_FFieldCols,A1
 ;mPrint  kCrtRow,kCrtCol,#kFirstCol,qpendl,<'FIELD COLS'>
 ;mDump.B kCrtRow,kCrtCol,#kFirstCol,A1,#4,qpendl

 ;LEA z_FFieldSizes,A1
 ;mPrint  kCrtRow,kCrtCol,#kFirstCol,qpendl,<'FIELD SIZES'>
 ;mDump.B kCrtRow,kCrtCol,#kFirstCol,A1,#4,qpendl
 ;mPrtCr  kCrtRow,kCrtCol,#kFirstCol


    ; _REFRESHFORM -- FORM helper: fill form with current values
    ; Args:
    ;   A0: Address of the field values array
    ;   A1: Address of the field rows array
    ;   A2: Address of the field columns array
    ;   A3: Address of the field sizes array
    ; Notes:
    ;   Will loop forever if a form has no fields.
_REFRESHFORM:
    MOVEM.W D0-D2,-(A7)              ; Save used data registers to stack
    CLR.W   D0                       ; DO: field index

.t0 TST.B   0(A3,D0.W)               ;   Does this field exist in the form?
    BEQ.S   .t1                      ;   No, so on to the next field
    BSR     _FIELDPOS                ;   Position of this field into D1,D2
    BSR     _FILLFIELD               ;   Show this field's value
.t1 ADDQ.B  #1,D0                    ;   Set index to the next field
    CMPI.B  #4,D0                    ;   Or have we finished them all?
    BLO.S   .t0                      ;   If not, on to the next field

    MOVEM.W (A7)+,D0-D2              ; Recover used data registers from stack
    RTS                              ; Back to caller


    ; _FIELDPOS -- FORM helper: screen position of a field into D1, D2
    ; Args:
    ;   D0: field index, as a word in 0..3
    ;   A1: Address of the field rows array
    ;   A2: Address of the field columns array
    ; Notes:
    ;   D1 is set to the field screen row for field (D0.W) in pixels; D1 is set
    ;       to the field screen column for field (D0.W) in character positions.
_FIELDPOS:
    MOVE.B  0(A1,D0.W),D1            ; Field's relative row into D1
    MOVE.B  0(A2,D0.W),D2            ; Field's column into D2
    EXT.W   D1                       ; Extend D1 from byte to word
    EXT.W   D2                       ; Extend D2 from byte to word
    MULS.W  #kCharHeight,D1          ; Convert rows from text to pixels
    ADD.W   kCrtRow,D1               ; Add current row (pixels) to D1
    ADD.W   #kFirstCol,D2            ; Add leftmost column to D2
    RTS                              ; Back to caller
 

    ; _FILLFIELD -- FORM helper: print field contents to a screen location
    ; Args:
    ;   D0: field index, as a word in 0..3
    ;   D1: field screen row, in pixels
    ;   D2: field screen column, in character positions
    ;   A0: Address of the field values array
    ;   A3: Address of the field sizes array
    ; Notes:
    ;   Does not alter contents of D1-D2.
_FILLFIELD:
    CMPI.B  #1,0(A3,D0.W)            ; Is this field a byte?
    BNE.S   .f0                      ; No, skip ahead
    LSL.W   #2,D0                    ; Yes, D0 *= 4 for indirect addressing...
    MOVE.B  3(A0,D0.W),-(A7)         ; ...and move byte onto stack
    mPrtHxB D1,D2,#kFirstCol,noexport  ; Print byte
    BRA     .f3                      ; Skip to end of loop

.f0 CMPI.B  #2,0(A3,D0.W)            ; Is this field a word?
    BNE.S   .f1                      ; No, skip ahead
    LSL.W   #2,D0                    ; Yes, D0 *= 4 for indirect addressing...
    MOVE.W  2(A0,D0.W),-(A7)         ; ...and move word onto stack
    mPrtHxW D1,D2,#kFirstCol,noexport  ; Print word
    BRA.S   .f3                      ; Skip to end of loop

.f1 CMPI.B  #3,0(A3,D0.W)            ; Is this field a three-byter?
    BNE.S   .f2                      ; No, skip ahead
    LSL.W   #2,D0                    ; Yes, D0 *= 4 for indirect addressing...
    MOVE.L  0(A0,D0.W),-(A7)         ; ...and move long holding it onto stack
    mPrtHx3 D1,D2,#kFirstCol,noexport  ; Print the three-byter
    BRA.S   .f3                      ; Skip to end of loop

.f2 LSL.W   #2,D0                    ; Must be a long, D0 *= 4 for addressing...
    MOVE.L  0(A0,D0.W),-(A7)         ; ...and move long onto stack
    mPrtHxL D1,D2,#kFirstCol,noexport  ; Print the long

.f3 LSR.W   #2,D0                    ; Restore D0: D0 /= 4
    RTS                              ; Back to caller


    ; _BLANKFIELD -- FORM helper: fill location of field contents with ?-blocks
    ; Args:
    ;   D0: field index, as a word in 0..3
    ;   D1: field screen row, in pixels
    ;   D2: field screen column, in character positions
    ;   A3: Address of the field sizes array
    ; Notes:
    ;   Does not alter contents of D1-D2.
    ;   Not fast at all, but simple...
_BLANKFIELD:
    MOVE.W  D3,-(A7)                 ; Save D3 to stack
    CLR.W   D3                       ; Clear D3 in preparation for...
    MOVE.B  0(A3,D0.W),D3            ; ...copying in the field size...
    LSL.B   #1,D3                    ; ...multiplying that by two...
    ADD.W   D2,D3                    ; ...adding the field's first column...
.b0 SUBQ.W  #1,D3                    ; ...and -1 to get last column/decrement
    mPrtLit D1,D3,#kFirstCol,noexport,<'!'>  ; Print ?-block
    CMP.W   D2,D3                    ; Have we reached the start of the field?
    BNE.S   .b0                      ; No, keep going
    MOVE.W  (A7)+,D3                 ; Yes, recover D3 from stack
    RTS                              ; Back to caller


    PAGE
* NeoWidEx UI FORMS numerical data =========================
    SECTION kSecData

; TODO: do we need it?


    PAGE
* NeoWidEx UI FORMS scratch data allocation ================
    SECTION kSecScratch

    DS.W    0                        ; Just to make sure we're even-aligned

zFieldValues:                        ; Will hold longs entered into fields
    DC.B    'Fiel'
    DC.B    'dVal'
    DC.B    'sGoH'
    DC.B    'ere;'

z_FFieldResets:                      ; Will hold the initial values of fields
    DC.B    'Defa'
    DC.B    'ults'
    DC.B    'GoHe'
    DC.B    're; '

z_FFieldBounds:                      ; Will hold upper-bounds for field values
    DC.B    'Boun'
    DC.B    'dsGo'
    DC.B    'Here'
    DC.B    ';and'

z_FPromptAddrs:                      ; Will hold pointers to prompt strings
    DC.B    'Prom'
    DC.B    'ptPt'
    DC.B    'rsGo'
    DC.B    'Here'

z_FFieldRows:                        ; Field rows relative to last row...
    DC.B    'Rows'                   ; ...that is, signed chars, all 0 or less
z_FFieldCols:                        ; Field columns, absolute
    DC.B    'Cols'
z_FFieldSizes:                       ; Field sizes, in bytes
    DC.B    'Lens'                   ; 0 means: this field is absent

    DS.W    0                        ; Force even alignment for following data


    PAGE
* NeoWidEx UI FORMS strings =================================
    SECTION kSecStrings

sFormHelp:
    DC.B    'TAB/RETURN-NEXT FIELD.  CLEAR-RESET FIELD.  ENTER-SUBMIT.',0

sFormTest:
    DC.B    $0D
    DC.B    '  --- SOME FORM ---',$0D
    DC.B    'THIS IS A FORM. HERE IS THE THIRD FIELD. c3____. COOL.',$0D
    DC.B    'LET US NOW HAVE FIELD TWO-b4______. HOW ABOUT THAT.',$0D
    DC.B    'FIELD FOUR IS ONE BYTE... d1... AND AT LAST...',$0D
    DC.B    'FIELD ONE IS a2__ ... TWO BYTES.',0

    DS.W    0
sFormTestPrompts:
    DC.L    .p1,.p2,.p3,.p4
.p1 DC.B    'FIELD 1',0
.p2 DC.B    'FIELD TWO',0
.p3 DC.B    'FIELD THREE',0
.p4 DC.B    'FIELD IV',0

    DS.W    0
sFormTestInitialVals:
    DC.L    $11121314,$21222324,$31323334,$41424344


** (Back to the code section) **
    SECTION kSecCode


*~Font name~Courier New~
*~Font size~10~
*~Tab type~1~
*~Tab size~4~