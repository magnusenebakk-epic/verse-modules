# Parser combinators over []char. Verse failure IS parse failure: Parse is
# <decides>, alternation is `or`, and a failed branch rolls back cleanly.
#
# Combinators are classes, not closures (nested functions are VVM-only):
# each combinator captures its configuration as fields. Composition builds
# an object tree, the classic OOP encoding of a closure.
#
#     Digits := some_of(DigitChar)
#     Num := parse_int{}
#     Pair := seq{A := Num, Sep := lit(","), B := Num}
#
# parse_result(t) carries the value and the rest of the input; a parser
# succeeds iff it can produce one.

parse_result<public>(t:type) := class:
    Value<public>:t
    Rest<public>:[]char


char_parser<public> := class<abstract>:
    Parse<public>(In:[]char)<transacts><decides>:parse_result(char)


string_parser<public> := class<abstract>:
    Parse<public>(In:[]char)<transacts><decides>:parse_result([]char)


int_parser<public> := class<abstract>:
    Parse<public>(In:[]char)<transacts><decides>:parse_result(int)


# --- Character level ---------------------------------------------------------

# One char satisfying Pred.
char_satisfying<public> := class(char_parser):
    Pred<public>:type{_(:char)<transacts><decides>:void}

    Parse<override>(In:[]char)<transacts><decides>:parse_result(char) =
        C := In[0]
        Pred[C]
        parse_result(char){Value := C, Rest := In.Slice[1]}

# char has no ordering (only int/float do), so membership in a set string
# instead of range checks.
DigitChar<public>(C:char)<transacts><decides>:void =
    first (X : "0123456789", X = C) { X }

LowerChar<public>(C:char)<transacts><decides>:void =
    first (X : "abcdefghijklmnopqrstuvwxyz", X = C) { X }

UpperChar<public>(C:char)<transacts><decides>:void =
    first (X : "ABCDEFGHIJKLMNOPQRSTUVWXYZ", X = C) { X }

SpaceChar<public>(C:char)<transacts><decides>:void =
    C = ' '


# --- String level ------------------------------------------------------------

# Exact literal.
literal<public> := class(string_parser):
    Expected<public>:[]char

    Parse<override>(In:[]char)<transacts><decides>:parse_result([]char) =
        Prefix := In.Slice[0, Expected.Length]
        Prefix = Expected
        parse_result([]char){Value := Prefix, Rest := In.Slice[Expected.Length]}

lit<public>(S:[]char)<transacts>:literal =
    literal{Expected := S}

# Zero or more chars satisfying Pred. Total by nature but kept <decides>
# to compose; never fails.
many_of<public> := class(string_parser):
    Pred<public>:type{_(:char)<transacts><decides>:void}

    Parse<override>(In:[]char)<transacts><decides>:parse_result([]char) =
        var N:int = 0
        loop:
            if (C := In[N], Pred[C]):
                set N += 1
            else:
                break
        Taken := In.Slice[0, N] or array{}
        Remaining := In.Slice[N] or array{}
        parse_result([]char){Value := Taken, Rest := Remaining}

# One or more.
some_of<public> := class(string_parser):
    Pred<public>:type{_(:char)<transacts><decides>:void}

    Parse<override>(In:[]char)<transacts><decides>:parse_result([]char) =
        R := many_of{Pred := Pred}.Parse[In]
        R.Value.Length > 0
        R

# First of two string parsers to succeed. Alternation is just `or`.
either<public> := class(string_parser):
    A<public>:string_parser
    B<public>:string_parser

    Parse<override>(In:[]char)<transacts><decides>:parse_result([]char) =
        A.Parse[In] or B.Parse[In]

# A then B, values concatenated.
both<public> := class(string_parser):
    A<public>:string_parser
    B<public>:string_parser

    Parse<override>(In:[]char)<transacts><decides>:parse_result([]char) =
        RA := A.Parse[In]
        RB := B.Parse[RA.Rest]
        parse_result([]char){Value := RA.Value + RB.Value, Rest := RB.Rest}

# Leading spaces dropped, then P.
token<public> := class(string_parser):
    P<public>:string_parser

    Parse<override>(In:[]char)<transacts><decides>:parse_result([]char) =
        WS := many_of{Pred := SpaceChar}.Parse[In]
        P.Parse[WS.Rest]


# --- Values ------------------------------------------------------------------

# Optional minus, one or more digits.
parse_int<public> := class(int_parser):

    Parse<override>(In:[]char)<transacts><decides>:parse_result(int) =
        Negative := if (In[0] = '-') then true else false
        Body := if (Negative?) then In.Slice[1] else In
        Digits := some_of{Pred := DigitChar}.Parse[Body]
        var N:int = 0
        for (C : Digits.Value):
            set N = N * 10 + DigitValue(C)
        Signed := if (Negative?) then -N else N
        parse_result(int){Value := Signed, Rest := Digits.Rest}

    DigitValue<internal>(C:char)<transacts>:int =
        # char arithmetic is unavailable, table it.
        if (C = '0') then 0
        else if (C = '1') then 1
        else if (C = '2') then 2
        else if (C = '3') then 3
        else if (C = '4') then 4
        else if (C = '5') then 5
        else if (C = '6') then 6
        else if (C = '7') then 7
        else if (C = '8') then 8
        else if (C = '9') then 9
        else 0


# Comma-separated ints with optional spaces: "3, -14,15" -> array{3,-14,15}
ParseIntList<public>(In:[]char)<transacts><decides>:[]int =
    First := parse_int{}.Parse[In]
    var Values:[]int = array{First.Value}
    var Rest:[]char = First.Rest
    loop:
        if:
            Sep := token{P := lit(",")}.Parse[Rest]
            WS := many_of{Pred := SpaceChar}.Parse[Sep.Rest]
            Next := parse_int{}.Parse[WS.Rest]
        then:
            set Values += array{Next.Value}
            set Rest = Next.Rest
        else:
            break
    Rest.Length = 0   # demand full consumption
    Values
