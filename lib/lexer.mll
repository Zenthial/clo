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
let frac = '.' digit+
(* let exp = ['e' 'E'] ['-' '+']? digit+ *)
let float = digit* frac (* exp? *)
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
  | "//"     { read_single_line_comment lexbuf (* use our comment rule for rest of line *) }
  | "/*"     { read_multi_line_comment lexbuf }
  | "fn"     { FN }
  | "let"    { LET }
  | "print"  { PRINT }
  | "true"   { TRUE }
  | "false"  { FALSE }
  | "return" { RETURN }
  | "struct" { STRUCT }
  | "enum"   { ENUM }
  | "void"   { TYPE_VOID }
  | "match"  { MATCH }
  | "with"   { WITH }
  | "int"    { TYPE_INT }
  | "bool"   { TYPE_BOOL }
  | "mut"    { MUT }
  | "if"     { IF }
  | "else"   { ELSE }
  | "for"    { FOR }
  | "in"     { IN }
  | "break"  { BREAK }
  | ".."     { DOTDOT }
  | "->"     { ARROW }
  | "=="     { EQUALEQUAL }
  | '+'      { PLUS }
  | '-'      { MINUS }
  | '*'      { MUL }
  | '('      { LPAREN }
  | ')'      { RPAREN }
  | '{'      { LBRACE }
  | '}'      { RBRACE }
  | '['      { LBRACKET }
  | ']'      { RBRACKET }
  | '|'      { PIPE }
  | '_'      { UNDERSCORE }
  | ','      { COMMA }
  | ':'      { COLON }
  | ';'      { SEMICOLON }
  | '='      { EQUAL }
  | '.'      { DOT }
  | '"'      { read_string (Buffer.create 17) lexbuf }
  | id       { IDENT (Lexing.lexeme lexbuf) }
  | _        { raise ( SyntaxError ("Unexpected char: " ^ Lexing.lexeme lexbuf)) }
  | eof      { EOF }
and read_single_line_comment = parse
  | newline { next_line lexbuf; read lexbuf }
  | eof { EOF }
  | _ { read_single_line_comment lexbuf }

and read_multi_line_comment = parse
  | "*/" { read lexbuf }
  | newline { next_line lexbuf; read_multi_line_comment lexbuf }
  | eof { raise (SyntaxError ("Lexer - Unexpected EOF - please terminate your comment.")) }
  | _ { read_multi_line_comment lexbuf }

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
