{
  open Parser

  exception SyntaxError of string

  let next_line (lexbuf : Lexing.lexbuf) =
    let pos = lexbuf.lex_curr_p in
    lexbuf.lex_curr_p <-
      { pos with pos_bol = lexbuf.lex_curr_pos;
                 pos_lnum = pos.pos_lnum + 1
      }
}

let digit = ['0'-'9']
let frac = '.' digit*
let exp = ['e' 'E'] ['-' '+']? digit+
let float = digit* frac exp?
let int = '-'? digit+

let white = [' ' '\t']+
let newline = '\r' | '\n' | "\r\n"
let id = ['a'-'z' 'A'-'Z' '_'] ['a'-'z' 'A'-'Z' '0'-'9' '_']*

rule read =
  parse
  | white    { read lexbuf }
  | newline  { next_line lexbuf; read lexbuf }
  | float    { FLOAT (float_of_string (Lexing.lexeme lexbuf)) }
  | int      { INT (int_of_string (Lexing.lexeme lexbuf)) }
  | "fn"     { FN }
  | "let"    { LET }
  | "print"  { PRINT }
  | "true"   { TRUE }
  | "false"  { FALSE }
  | "return" { RETURN }
  | "type"   { TYPE }
  | "void"   { TYPE_VOID }
  | "int"    { TYPE_INT }
  | "bool"   { TYPE_BOOL }
  | "+"      { PLUS }
  | "*"      { MUL }
  | "("      { LPAREN }
  | ")"      { RPAREN }
  | "{"      { LBRACE }
  | "}"      { RBRACE }
  | "->"     { ARROW }
  | ","      { COMMA }
  | ":"      { COLON }
  | ";"      { SEMICOLON }
  | "="      { EQUAL }
  | '"'      { read_string (Buffer.create 17) lexbuf }
  | id       { IDENT (Lexing.lexeme lexbuf) }
  | _        { raise ( SyntaxError ("Unexpected char: " ^ Lexing.lexeme lexbuf)) }
  | eof      { EOF }
and read_string buf = parse
  | '"'       { STRING (Buffer.contents buf) }
  | '\\' '/'  { Buffer.add_char buf '/'; read_string buf lexbuf }
  | '\\' '\\' { Buffer.add_char buf '\\'; read_string buf lexbuf }
  | '\\' 'b'  { Buffer.add_char buf '\b'; read_string buf lexbuf }
  | '\\' 'f'  { Buffer.add_char buf '\012'; read_string buf lexbuf }
  | '\\' 'n'  { Buffer.add_char buf '\n'; read_string buf lexbuf }
  | '\\' 'r'  { Buffer.add_char buf '\r'; read_string buf lexbuf }
  | '\\' 't'  { Buffer.add_char buf '\t'; read_string buf lexbuf }
  | [^ '"' '\\']+
    { Buffer.add_string buf (Lexing.lexeme lexbuf);
      read_string buf lexbuf
    }
  | _ { raise (SyntaxError ("Illegal string character: " ^ Lexing.lexeme lexbuf)) }
  | eof { raise (SyntaxError ("String is not terminated")) }
