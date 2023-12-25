type loc = Lexing.position * Lexing.position (* start, end *)

let dummy_loc = Lexing.dummy_pos, Lexing.dummy_pos

type bop =
  | Plus
  | Mul

(* proto - This type represents the "prototype" for a function, which captures
 * its name, and its argument names (thus implicitly the number of arguments the
 * function takes). *)
type type_expr =
  | TInt
  | TFloat
  | TStr
  | TVoid
  | TBool
  | TCustom of string

let string_of_type = function
  | TInt -> "int"
  | TFloat -> "float"
  | TStr -> "str"
  | TVoid -> "void"
  | TBool -> "bool"
  | TCustom s -> s
;;

type param = string * type_expr
type field = Field of string * type_expr * loc

type expr =
  (* variant for numeric literals like "1.0". *)
  | Int of int
  | Float of float
  | Bool of bool
  (* variant for referencing a variable, like "a". *)
  | Variable of string * loc
  (* variant for a binary operator. *)
  | Binop of bop * expr * expr * loc
  (* variant for function calls. *)
  | Call of string * expr list * loc
  | Print of string * expr list * loc
  | Let of string * type_expr * expr * loc
  | Function of fndef * loc
  | Return of expr * loc
  | Struct of string * field list * loc
  | StructConstruct of string * construct_field list * loc

and fndef = string * param list * type_expr option * expr list
and construct_field = string * expr * loc
