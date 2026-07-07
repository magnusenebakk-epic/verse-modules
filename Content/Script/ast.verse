# minilang AST. Castable class hierarchies; the parser builds these, the
# interpreter dispatches by downcast chains (Verse's object pattern match).

expr<public> := class<abstract><castable>:

int_literal<public> := class(expr):
    Value<public>:int

str_literal<public> := class(expr):
    Value<public>:string

bool_literal<public> := class(expr):
    Value<public>:logic

name_expr<public> := class(expr):
    Name<public>:string

unary_expr<public> := class(expr):
    Op<public>:token_kind
    Operand<public>:expr

binary_expr<public> := class(expr):
    Op<public>:token_kind
    Lhs<public>:expr
    Rhs<public>:expr

call_expr<public> := class(expr):
    Callee<public>:expr
    Args<public>:[]expr

# Function literal. Captures its defining environment at eval time, which
# is what makes minilang closures work.
fn_expr<public> := class(expr):
    Params<public>:[]string
    Body<public>:[]stmt


stmt<public> := class<abstract><castable>:

let_stmt<public> := class(stmt):
    Name<public>:string
    Init<public>:expr

assign_stmt<public> := class(stmt):
    Name<public>:string
    ValueExpr<public>:expr

expr_stmt<public> := class(stmt):
    E<public>:expr

if_stmt<public> := class(stmt):
    Cond<public>:expr
    ThenBody<public>:[]stmt
    ElseBody<public>:[]stmt

while_stmt<public> := class(stmt):
    Cond<public>:expr
    Body<public>:[]stmt

return_stmt<public> := class(stmt):
    ValueExpr<public>:?expr
