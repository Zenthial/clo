%{
  open Ast
%}

%token <float> FLOAT
%token <int> INT
%token <string> IDENT
%token <string> STRING
%token FN
%token LET
%token PRINT
%token PLUS
%token MINUS
%token MUL
%token EOF
%token TRUE
%token FALSE
%token RETURN
%token LPAREN
%token RPAREN
%token LBRACE
%token RBRACE
%token LBRACKET
%token RBRACKET
%token COMMA
%token ARROW
%token COLON
%token SEMICOLON
%token EQUAL
%token EQUALEQUAL
%token DOT
%token MATCH
%token WITH
%token PIPE
%token UNDERSCORE
%token MUT
%token IF
%token ELSE
%token FOR
%token IN
%token BREAK
%token DOTDOT

%token STRUCT
%token ENUM

%token TYPE_INT 
%token TYPE_BOOL
%token TYPE_VOID

%left PLUS
%left MINUS
%left MUL

%start <Ast.expr list> prog

%%

prog:
    | es = list(expr);  EOF { es }
    ;

type_expr:
    | TYPE_INT { TInt }
    | TYPE_BOOL { TBool }
    | TYPE_VOID { TVoid }
    | custom=IDENT; { TCustom custom }
    ;

type_annotation:
    | COLON; annot=type_expr { annot }
    ;

param:
    | param_name=IDENT; param_type=type_annotation { param_name, param_type, ($startpos, $endpos) }
    ;

params:
    | LPAREN; params=separated_list(COMMA,param); RPAREN { params }
    ;

args:
    | LPAREN; args=separated_list(COMMA, expr); RPAREN { args }
    ;

semi_terminated:
    | e=expr; SEMICOLON { e }
    ;

block_expr:
    | LBRACE; exprs=list(semi_terminated); RBRACE { exprs }
    ;

return_type_expr:
    | ARROW; ret_type=type_expr { ret_type }
    ;

function_defn:
    | FN; name=IDENT; function_params=params; ret_type = option(return_type_expr); body=block_expr { Function ((name, function_params, ret_type, body), ($startpos, $endpos)) }
    ;

struct_field:
    | name=IDENT; COLON; ty=type_expr; SEMICOLON { Field (name, ty, ($startpos, $endpos)) }
    ;

struct_expr:
    | LBRACE; fields=list(struct_field); RBRACE { fields }
    ;

struct_defn:
    | STRUCT; name=IDENT; body=struct_expr { Struct (name, body, ($startpos, $endpos)) }
    ;

enum_type_tag:
    | LPAREN; ty=type_expr; RPAREN { ty }
    ;

enum_variant:
    | name=IDENT; ty=option(enum_type_tag) { EnumVar (name, ty, ($startpos, $endpos)) }
    | name=IDENT; fields=struct_expr { StructVar (name, fields, ($startpos, $endpos)) }
    ;

enum_expr:
    | LBRACE; variants=separated_list(COMMA, enum_variant); RBRACE { variants }
    ;

enum_defn:
    | ENUM; name=IDENT; body=enum_expr { Enum (name, body, ($startpos, $endpos))}
    ;

struct_construct_field:
    | name=IDENT; COLON; e=expr; SEMICOLON { (name, e, ($startpos, $endpos)) }
    ;

struct_construct:
    | name=IDENT; LBRACE; fields=list(struct_construct_field); RBRACE { StructConstruct (name, fields, ($startpos, $endpos))}
    ;

enum_data:
    | LPAREN; e=separated_list(COMMA, expr); RPAREN { UnionVariant e }
    | LBRACE; fields=list(struct_construct_field); RBRACE  { StructVariant fields }
    ;

enum_construct:
    | name=IDENT; COLON; variant_name=IDENT; data=option(enum_data) { EnumConstruct (name, variant_name, data, ($startpos, $endpos)) }
    ;

match_case_kind:
    | LPAREN; is=separated_list(COMMA, IDENT); RPAREN { UnionMatch (is, ($startpos, $endpos)) }
    | struct_name=IDENT; { StructMatch (struct_name, ($startpos, $endpos)) }
    ;

match_type:
    | name=IDENT; COLON; variant_name=IDENT; kind=option(match_case_kind); { EnumMatch (name, variant_name, kind) }
    | UNDERSCORE; { DefaultMatch }
    ;

(* these are basically enum data with identifiers *)
match_case:
    | PIPE; ty=match_type; ARROW; e=expr { ty, e, ($startpos, $endpos)}
    ;

match_cases:
    | cases=separated_list(COMMA, match_case) { cases }
    ;

match_statement:
    | MATCH; e=expr; WITH; cases=match_cases { Match (e, cases, ($startpos, $endpos)) }
    ;

if_expr:
    | conditions=cond_block; else_block=option(else_statement) { (conditions, else_block, ($startpos, $endpos)) }
    ;

cond_block:
    | IF; cond=expr; then_block=block_expr { (cond, then_block) }

else_statement:
    | ELSE; else_block=block_expr { else_block }
    ;

range_expr:
    | start=INT; DOTDOT; finish=INT { Range (start, finish) }
    ;

for_expr:
    | FOR; id=IDENT; IN; range=range_expr; { ForInRange (id, range) }
    ;

array_expr:
    | LBRACKET; size=INT; RBRACKET; LBRACE; items=separated_list(COMMA, expr); RBRACE { Array (size, items, ($startpos, $endpos)) }
    ;

index:
    | id=IDENT; LBRACKET; idx=expr; RBRACKET { Index (id, idx, ($startpos, $endpos)) }
    ;

expr:
    | LPAREN; e=expr RPAREN {e}
    | lhs=expr; op=bin_op; rhs=expr { Binop (op, lhs, rhs, ($startpos, $endpos)) }
    | LET; mut=option(MUT); id=IDENT; annot=option(type_annotation); EQUAL; e=expr { Let (id, mut, annot, e, ($startpos, $endpos)) }
    | fn=IDENT; fn_args=args { Call (fn, fn_args, ($startpos, $endpos)) }
    | PRINT; LPAREN; str=STRING; option(COMMA); args=separated_list(COMMA, expr); RPAREN; {  Print (str, args, ($startpos, $endpos)) }
    | fn_def=function_defn { fn_def }
    | struct_def=struct_defn { struct_def }
    | enum_def=enum_defn { enum_def }
    | sc=struct_construct { sc }
    | ec=enum_construct { ec }
    | arr=array_expr { arr }
    | idx=index { idx }
    | fore=for_expr; exprs=block_expr { For (fore, exprs, ($startpos, $endpos)) }
    | m = match_statement { m }
    | id=IDENT { Variable (id, ($startpos, $endpos)) }
    | id=IDENT; EQUAL; e=expr { Assignment (id, e, ($startpos, $endpos)) }
    | i=INT { Int i }
    | f=FLOAT { Float f }
    | iff=if_expr; { If iff }
    | TRUE { Bool true }
    | FALSE { Bool false }
    | RETURN; e=expr { Return (e, ($startpos, $endpos)) }
    | struct_name=IDENT; DOT; field_name=IDENT { FieldAccess (struct_name, field_name, ($startpos, $endpos)) }
    | BREAK; { Break (($startpos, $endpos)) }
    ;


%inline bin_op:
| PLUS { Plus }
| MUL { Mul }
| MINUS { Minus }
| EQUALEQUAL { Eq }
