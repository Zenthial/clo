type loc = Ast.loc
type type_expr = Ast.type_expr

type type_error_kind =
  | TETypeDefAsValue
  | TETypeRedefine
  | TEFieldLengthMismatch
  | TEFieldNonExistant
  | TETypeConstructWithoutDefine
  | TEVariableNotBound
  | TETypeMismatch
  | TEReturnTypeMismatch
  | TEFunctionNonExistant
  | TEInvalidFieldAccess
(* this needs to hold a 'loc list' that points to every return type location *)

exception
  TypeError of
    { kind : type_error_kind
    ; loc : loc
    ; msg : string option
    }

type expr =
  | Int of int
  | Float of float
  | Str of string (* a constant string that cannot change *)
  | Bool of bool
  | Variable of string * type_expr * loc
  | Call of call * loc
  | Binop of bop * loc (* we validate the *)
  | Let of let_expr * loc
  | Return of expr * type_expr * loc
  | FnDef of fn_def * loc
  | TypeDef of type_def * loc
  | TypeConstruct of
      type_construct * loc (* something like thing = StructName { field_one: string} *)
  | FieldAccess of field_access * loc

and call =
  { cname : string
  ; ctype : type_expr
  ; cargs : expr list
  }

and bop =
  { lhs : expr
  ; rhs : expr
  ; bop : Ast.bop
  ; btype : type_expr
  }

and let_expr =
  { lname : string
  ; ltype : type_expr
  ; lbinding : expr
  }

and fnparam = string * type_expr

and fn_def =
  { fnname : string
  ; fnparams : fnparam list
  ; fnret : type_expr (* we resolve and type check this *)
  ; fnexprs : expr list
  }

and type_def =
  | EnumDef
  | StructDef of struct_def

and field = type_expr * loc

and struct_def =
  { sname : string
  ; sfields : field array
  }

and construct_field = expr * loc

and struct_construct =
  { scname : string
  ; scfields : construct_field array
  }

and type_construct =
  | EnumConst
  | StructConst of struct_construct

and field_access =
  { fvarname : string
  ; ffieldidx : int
  ; ffieldtype : type_expr
  ; ftypename : string
  }

let defined_structs : (string, struct_def) Hashtbl.t =
  Hashtbl.create 10 (* struct_name -> struct_def *)
;;

let defined_struct_fields =
  Hashtbl.create 10 (* struct_name -> HashTbl<field_name, idx> *)
;;

let bound_variables : (string, type_expr) Hashtbl.t = Hashtbl.create 10
let string_of_type = Ast.string_of_type
let defined_functions = Hashtbl.create 10 (* fn_name -> type_expr *)

let type_of = function
  | Int _ -> Ast.TInt
  | Float _ -> Ast.TFloat
  | Bool _ -> Ast.TBool
  | Str _ -> Ast.TStr
  | Return (_, ty, _) -> ty
  | TypeConstruct (c, _) ->
    (match c with
     | EnumConst -> Ast.TCustom "Enum"
     | StructConst s -> TCustom s.scname)
  | TypeDef (_, loc) -> raise (TypeError { kind = TETypeDefAsValue; loc; msg = None })
  | Variable (_, ty, _) -> ty
  | Let (l, _) -> l.ltype
  | Call (c, _) -> c.ctype
  | Binop (b, _) -> b.btype
  | FnDef (fndef, _) -> fndef.fnret
  | FieldAccess (faccess, _) -> faccess.ffieldtype
;;

let typecheck_field field_name struct_name fieldty loc =
  let sdef =
    try Hashtbl.find defined_structs struct_name with
    | Not_found -> raise (TypeError { kind = TEVariableNotBound; msg = None; loc })
  in
  let struct_fields =
    try Hashtbl.find defined_struct_fields struct_name with
    | Not_found -> raise (TypeError { kind = TEVariableNotBound; msg = None; loc })
  in
  let idx =
    try Hashtbl.find struct_fields field_name with
    | Not_found -> raise (TypeError { kind = TEFieldNonExistant; msg = None; loc })
  in
  let field_type, _ = Array.get sdef.sfields idx in
  if field_type = fieldty
  then ()
  else
    raise
      (TypeError
         { kind = TETypeMismatch
         ; msg =
             Some
               (Format.sprintf
                  "Field %s expected type %s, got %s"
                  field_name
                  (string_of_type field_type)
                  (string_of_type fieldty))
         ; loc
         })
;;

let rec typed_expr (e : Ast.expr) =
  match e with
  | Ast.FieldAccess (var_name, field_name, loc) ->
    let var_type =
      try Hashtbl.find bound_variables var_name with
      | Not_found -> raise (TypeError { kind = TEVariableNotBound; msg = None; loc })
    in
    let var_type =
      match var_type with
      | Ast.TCustom s -> s
      | _ -> raise (TypeError { kind = TEInvalidFieldAccess; msg = None; loc })
    in
    let sdef =
      try Hashtbl.find defined_structs var_type with
      | Not_found -> raise (TypeError { kind = TEVariableNotBound; msg = None; loc })
    in
    let struct_fields =
      try Hashtbl.find defined_struct_fields var_type with
      | Not_found -> raise (TypeError { kind = TEVariableNotBound; msg = None; loc })
    in
    let idx =
      try Hashtbl.find struct_fields field_name with
      | Not_found -> raise (TypeError { kind = TEFieldNonExistant; msg = None; loc })
    in
    let field_type, _ = Array.get sdef.sfields idx in
    FieldAccess
      ( { fvarname = var_name
        ; ffieldidx = idx
        ; ffieldtype = field_type
        ; ftypename = var_type
        }
      , loc )
  | Ast.Struct (name, fields, loc) ->
    let struct_field_tbl =
      match Hashtbl.find_opt defined_struct_fields name with
      | Some _ -> raise (TypeError { kind = TETypeRedefine; loc; msg = None })
      | None -> Hashtbl.create 10
    in
    let fields = Array.of_list fields in
    let field_types = Array.make (Array.length fields) (Ast.TVoid, Ast.dummy_loc) in
    Array.iteri
      (fun i f ->
        let field_name, field_type, loc =
          match f with
          | Ast.Field (field_name, field_type, l) -> field_name, field_type, l
        in
        Hashtbl.add struct_field_tbl field_name i;
        Array.set field_types i (field_type, loc))
      fields;
    Hashtbl.add defined_struct_fields name struct_field_tbl;
    let def = { sname = name; sfields = field_types } in
    Hashtbl.add defined_structs name def;
    TypeDef (StructDef def, loc)
  | Ast.StructConstruct (name, fields, loc) ->
    let struct_field_tbl =
      try Hashtbl.find defined_struct_fields name with
      | Not_found ->
        raise (TypeError { kind = TETypeConstructWithoutDefine; loc; msg = None })
    in
    let fields = Array.of_list fields in
    if Array.length fields != Hashtbl.length struct_field_tbl
    then raise (TypeError { kind = TEFieldLengthMismatch; loc; msg = None })
    else ();
    let mapped_fields = Array.make (Array.length fields) (Int 0, Ast.dummy_loc) in
    Array.iter
      (fun (field_name, field_expr, field_loc) ->
        let idx =
          try Hashtbl.find struct_field_tbl field_name with
          | Not_found ->
            raise (TypeError { kind = TEFieldNonExistant; loc = field_loc; msg = None })
        in
        let expr = typed_expr field_expr in
        let fieldty = type_of expr in
        typecheck_field field_name name fieldty field_loc;
        Array.set mapped_fields idx (expr, field_loc))
      fields;
    TypeConstruct (StructConst { scname = name; scfields = mapped_fields }, loc)
  | Ast.Int i -> Int i
  | Ast.Float f -> Float f
  | Ast.Bool b -> Bool b
  | Ast.Variable (var_name, loc) ->
    let bound_var =
      try Hashtbl.find bound_variables var_name with
      | Not_found ->
        raise (TypeError { kind = TEVariableNotBound; msg = Some var_name; loc })
    in
    Variable (var_name, bound_var, loc)
  | Ast.Let (name, ty, expr, loc) ->
    let lbinding = typed_expr expr in
    let lbinding_type = type_of lbinding in
    if ty <> lbinding_type
    then
      raise
        (TypeError
           { kind = TETypeMismatch
           ; msg =
               Some
                 (Format.sprintf
                    "Left side type %s does not match right side type %s"
                    (string_of_type ty)
                    (string_of_type lbinding_type))
           ; loc
           })
    else ();
    Hashtbl.add bound_variables name lbinding_type;
    (* be able to look up bindings to find and validate field accesses *)
    Let ({ lname = name; ltype = ty; lbinding }, loc)
  | Ast.Binop (bop, lhs, rhs, loc) ->
    let lhs = typed_expr lhs in
    let rhs = typed_expr rhs in
    let lhs_type = type_of lhs in
    let rhs_type = type_of rhs in
    if lhs_type != rhs_type
    then
      raise
        (TypeError
           { kind = TETypeMismatch
           ; loc
           ; msg =
               Some
                 (Format.sprintf
                    "Left side type %s does not match right side type %s"
                    (string_of_type lhs_type)
                    (string_of_type rhs_type))
           })
    else ();
    Binop ({ bop; lhs; rhs; btype = lhs_type }, loc)
  | Function ((fnname, fnparams, fntype_opt, fnexprs), loc) ->
    Hashtbl.clear bound_variables;
    (* bound variables do not persist across functions *)
    List.iter (fun (pname, ptype) -> Hashtbl.add bound_variables pname ptype) fnparams;
    let fnexprs = List.map typed_expr fnexprs in
    (* list of types of all the returns in the function *)
    (* need to extract the locations as well for better error reporting *)
    let returns =
      List.filter_map
        (fun e ->
          match e with
          | Return (_, ty, _) -> Some ty
          | _ -> None)
        fnexprs
    in
    let return_types_match =
      match fntype_opt with
      | Some ty -> List.for_all (fun ty' -> ty = ty') returns
      (* assert that there are no returns if the return type is void *)
      | _ -> List.length returns = 0 (* Util.all_same returns *)
    in
    let fnret =
      if not return_types_match
      then raise (TypeError { kind = TEReturnTypeMismatch; loc; msg = None })
      else (
        match fntype_opt with
        | Some ty -> ty
        | None -> TVoid)
    in
    Hashtbl.add defined_functions fnname fnret;
    FnDef ({ fnname; fnparams; fnret; fnexprs }, loc)
  | Call (fnname, args, loc) ->
    let cargs = List.map (fun e -> typed_expr e) args in
    let ctype =
      try Hashtbl.find defined_functions fnname with
      | Not_found -> raise (TypeError { kind = TEFunctionNonExistant; msg = None; loc })
    in
    Call ({ cname = fnname; cargs; ctype }, loc)
  | Print (str, args, loc) ->
    let cargs = List.map (fun e -> typed_expr e) args in
    let cargs = Str str :: cargs in
    Call ({ cname = "printf"; cargs; ctype = TVoid }, loc)
  | Return (expr, loc) ->
    let texpr = typed_expr expr in
    let ty = type_of texpr in
    Return (texpr, ty, loc)
;;
