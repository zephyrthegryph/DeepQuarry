use super::*;

pub(super) fn eval_condition(expr: &str, macros: &dyn MacroLookup) -> Result<bool, String> {
    eval_condition_at(expr, macros, ExpandLocation { line: 1, file_name: "" })
}

pub(super) fn eval_condition_at(expr: &str, macros: &dyn MacroLookup, location: ExpandLocation<'_>) -> Result<bool, String> {
    let original = macros.initial_environment() == crate::InitialEnvironment::OriginalChecker0290;
    if original && macros.contains_key("defined") {
        return Err("analysis context has no issued semantics for a macro named defined".into());
    }
    // Evaluate defined() before expansion: its operand is a macro name, not its value.
    let tokens = lex_spans(expr)
        .tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .collect::<Vec<_>>();
    let mut protected = String::new();
    let mut cursor = 0;
    let mut index = 0;
    while index < tokens.len() {
        if tokens[index].kind != TokenKind::Ident || tokens[index].text(expr) != "defined" {
            index += 1;
            continue;
        }
        let start = tokens[index].span.start;
        index += 1;
        let parenthesized = tokens
            .get(index)
            .is_some_and(|token| token.text(expr) == "(");
        if original && !parenthesized {
            return Err("analysis defined() requires a parenthesized identifier".into());
        }
        if parenthesized {
            index += 1;
        }
        let name = tokens
            .get(index)
            .filter(|token| token.kind == TokenKind::Ident)
            .ok_or("expected identifier after defined")?;
        let yes = condition_defined(name.text(expr), macros)?;
        let mut end = name.span.end;
        index += 1;
        if parenthesized {
            let close = tokens
                .get(index)
                .filter(|token| token.text(expr) == ")")
                .ok_or("unclosed defined() in #if")?;
            end = close.span.end;
            index += 1;
        }
        protected.push_str(&expr[cursor..start]);
        protected.push(if yes { '1' } else { '0' });
        cursor = end;
    }
    protected.push_str(&expr[cursor..]);
    let condition=ConditionLookup(macros);
    let lookup:&dyn MacroLookup=if original{&condition}else{macros};
    let expanded = expand(&protected,lookup,0,location)?;
    let expr = expanded.as_str();
    let mut parser = ConditionParser {
        tokens: lex(expr)
            .tokens
            .into_iter()
            .filter(|token| {
                !matches!(
                    token.kind,
                    TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                )
            })
            .collect(),
        index: 0,
        macros,
        expansion_depth: 0,
    };
    let value = parser.parse(0)?;
    if parser.index != parser.tokens.len() {
        return Err(format!("unsupported #if expression: {expr}"));
    }
    Ok(value.truth())
}


// One precedence/token walk serves both admitted contexts. Only its numeric
// value domain changes: the pinned original constant evaluator uses f32 and
// masks integer operations to 24 bits; native retains its existing i64 rules.
#[derive(Clone,Copy)]
enum ConditionNumber{Native(i64),Original(f32),Null}
impl ConditionNumber{
 fn truth(self)->bool{match self{Self::Native(n)=>n!=0,Self::Original(n)=>n!=0.0,Self::Null=>false}}
 fn flag(value:bool,original:bool)->Self{if original{Self::Original(u8::from(value) as f32)}else{Self::Native(i64::from(value))}}
 fn unary(self,op:&str)->Result<Self,String>{Ok(match self{
  Self::Native(n)=>Self::Native(match op{"!"=>i64::from(n==0),"~"=>!n,"-"=>n.wrapping_neg(),"+"=>n,_=>unreachable!()}),
  Self::Original(n)=>match op{"!"=>Self::Original(u8::from(n==0.0) as f32),"~"=>Self::Original((!(n as u32)&0xffffff) as f32),"-"=>Self::Original(-n),_=>return Err("original conditional unary operator has not been issued".into())},
  Self::Null if op=="!"=>Self::Original(1.0),Self::Null=>return Err("non-constant original conditional unary operation on null".into()),
 })}
 fn binary(self,rhs:Self,op:&str)->Result<Self,String>{
  if let(Self::Native(lhs),Self::Native(rhs))=(self,rhs){return Ok(Self::Native(match op{
   "||"=>i64::from(lhs!=0||rhs!=0),"&&"=>i64::from(lhs!=0&&rhs!=0),"|"=>lhs|rhs,"^"=>lhs^rhs,"&"=>lhs&rhs,"=="=>i64::from(lhs==rhs),"!="=>i64::from(lhs!=rhs),"<"=>i64::from(lhs<rhs),"<="=>i64::from(lhs<=rhs),">"=>i64::from(lhs>rhs),">="=>i64::from(lhs>=rhs),"<<"=>lhs.wrapping_shl(rhs as u32),">>"=>lhs.wrapping_shr(rhs as u32),"+"=>lhs.wrapping_add(rhs),"-"=>lhs.wrapping_sub(rhs),"*"=>lhs.wrapping_mul(rhs),"/" if rhs!=0=>lhs.wrapping_div(rhs),"%" if rhs!=0=>lhs.wrapping_rem(rhs),"/"|"%"=>return Err("division by zero in #if".into()),_=>unreachable!(),
  }))}
  if op=="||"{return Ok(if self.truth(){self}else{rhs})}if op=="&&"{return Ok(if self.truth(){rhs}else{self})}
  if matches!(op,"=="|"!="){let equal=match(self,rhs){(Self::Null,Self::Null)=>true,(Self::Original(a),Self::Original(b))=>a==b||(a.is_nan()&&b.is_nan()),_=>false};return Ok(Self::flag(if op=="=="{equal}else{!equal},true))}
  let(Self::Original(a),Self::Original(b))=(self,rhs)else{return Err("non-constant original conditional operation on null".into())};
  Ok(Self::Original(match op{
   "+"=>a+b,"-"=>a-b,"*"=>a*b,"/"=>a/b,"%"=>a%b,"<"=>u8::from(a<b) as f32,"<="=>u8::from(a<=b) as f32,">"=>u8::from(a>b) as f32,">="=>u8::from(a>=b) as f32,
   "|"=>((a as u32|b as u32)&0xffffff)as f32,"&"=>((a as u32&b as u32)&0xffffff)as f32,"^"=>((a as u32^b as u32)&0xffffff)as f32,
   "<<"|">>"=>{let shift=b as u32;if shift>=32{return Err("original conditional shift is outside issued u32 width".into())}let n=if op=="<<"{(a as u32)<<shift}else{(a as u32)>>shift};(n&0xffffff)as f32},
   _=>unreachable!(),
  }))
 }
}

struct ConditionParser<'a> {
    tokens: Vec<dm_syntax::Token>,
    index: usize,
    macros: &'a dyn MacroLookup,
    expansion_depth: usize,
}

impl ConditionParser<'_> {
    pub(super) fn peek(&self) -> Option<&str> {
        self.tokens.get(self.index).map(|token| token.text.as_str())
    }

    pub(super) fn take(&mut self, expected: &str) -> bool {
        if self.peek() == Some(expected) {
            self.index += 1;
            true
        } else {
            false
        }
    }

    // Preserve frozen precedence parser control flow and binding-power exit.
    #[allow(clippy::while_let_loop)]
    pub(super) fn parse(&mut self, min_bp: u8) -> Result<ConditionNumber, String> {
        let mut lhs = if self.take("!") {
            self.parse(21)?.unary("!")?
        } else if self.take("~") {
            self.parse(21)?.unary("~")?
        } else if self.take("-") {
            self.parse(21)?.unary("-")?
        } else if self.take("+") {
            self.parse(21)?.unary("+")?
        } else if self.take("(") {
            let value = self.parse(0)?;
            if !self.take(")") {
                return Err("unclosed parenthesis in #if".into());
            }
            value
        } else if self.take("defined") {
            let parenthesized = self.take("(");
            let name = self
                .tokens
                .get(self.index)
                .ok_or("missing identifier after defined")?;
            if name.kind != TokenKind::Ident {
                return Err("expected identifier after defined".into());
            }
            let name = name.text.clone();
            self.index += 1;
            if parenthesized && !self.take(")") {
                return Err("unclosed defined() in #if".into());
            }
            ConditionNumber::flag(condition_defined(&name, self.macros)?,self.original())
        } else {
            let token = self
                .tokens
                .get(self.index)
                .ok_or("missing #if operand")?
                .clone();
            self.index += 1;
            if token.kind == TokenKind::Number {
                self.number(&token.text)?
            } else if token.kind == TokenKind::Ident {
                self.macro_value(&token.text)?
            } else {
                return Err(format!("unsupported #if token: {}", token.text));
            }
        };
        loop {
            let Some((op, width, left_bp, right_bp)) = self.binary_operator() else {
                break;
            };
            if left_bp < min_bp {
                break;
            }
            self.index += width;
            let rhs = self.parse(right_bp)?;
            lhs = lhs.binary(rhs,op)?;
        }
        Ok(lhs)
    }

    fn original(&self)->bool{self.macros.initial_environment()==crate::InitialEnvironment::OriginalChecker0290}
    fn number(&self,text:&str)->Result<ConditionNumber,String>{
        if !self.original(){return parse_int(text).map(ConditionNumber::Native)}
        use dm_syntax::numeric_form::{numeric_form,NumericForm};
        let n=match numeric_form(text)?{NumericForm::Integer(n)=>n as f32,NumericForm::Float=>{let text=text.replace('_',"");if text.ends_with("#INF"){f32::INFINITY}else if text.ends_with("#IND"){f32::NAN}else{text.parse::<f32>().map_err(|_|format!("invalid original #if number: {text}"))?}}};
        Ok(ConditionNumber::Original(n))
    }

    fn macro_value(&self, name: &str) -> Result<ConditionNumber, String> {
        if self.macros.initial_environment() == crate::InitialEnvironment::OriginalChecker0290 {
            // The pinned constant evaluator has no object tree in #if. An
            // unexpanded identifier is an error, except the primary null term.
            return if name == "null" { Ok(ConditionNumber::Null) } else { Err(format!("cannot reference variable {name:?} in this context")) };
        }
        let Some(definition) = self.macros.get(name) else {
            return Ok(ConditionNumber::Native(0));
        };
        if definition.parameters.is_some() {
            return Ok(ConditionNumber::Native(0));
        }
        if definition.replacement.trim().is_empty() {
            return Ok(ConditionNumber::Native(0));
        }
        if self.expansion_depth >= 32 {
            return Err("#if macro expansion exceeded depth 32".into());
        }
        let mut nested = ConditionParser {
            tokens: lex(&definition.replacement)
                .tokens
                .into_iter()
                .filter(|token| {
                    !matches!(
                        token.kind,
                        TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                    )
                })
                .collect(),
            index: 0,
            macros: self.macros,
            expansion_depth: self.expansion_depth + 1,
        };
        let value = nested.parse(0)?;
        if nested.index != nested.tokens.len() {
            return Err(format!("unsupported #if macro value: {name}"));
        }
        Ok(value)
    }

    fn binary_operator(&self) -> Option<(&'static str, usize, u8, u8)> {
        const OPS: &[(&str, u8)] = &[
            ("||", 1),
            ("&&", 3),
            ("|", 5),
            ("^", 7),
            ("&", 9),
            ("==", 11),
            ("!=", 11),
            ("<=", 13),
            (">=", 13),
            ("<", 13),
            (">", 13),
            ("<<", 15),
            (">>", 15),
            ("+", 17),
            ("-", 17),
            ("*", 19),
            ("/", 19),
            ("%", 19),
        ];
        let first = self.tokens.get(self.index)?;
        OPS.iter()
            .filter_map(|(op, bp)| {
                let mut width = 0;
                let mut spelling = String::new();
                for token in self.tokens.iter().skip(self.index) {
                    if token.span.start != first.span.start + spelling.len()
                        || spelling.len() >= op.len()
                    {
                        break;
                    }
                    spelling.push_str(&token.text);
                    width += 1;
                }
                (spelling == *op).then_some((*op, width, *bp, bp + 1))
            })
            .max_by_key(|(op, _, _, _)| op.len())
    }
}

fn parse_int(value: &str) -> Result<i64, String> {
    let value = value.replace('_', "");
    if let Some(hex) = value
        .strip_prefix("0x")
        .or_else(|| value.strip_prefix("0X"))
    {
        i64::from_str_radix(hex, 16).map_err(|_| format!("invalid #if number: {value}"))
    } else {
        value
            .parse::<i64>()
            .map_err(|_| format!("invalid #if number: {value}"))
    }
}

fn condition_defined(name: &str, macros: &dyn MacroLookup) -> Result<bool, String> {
    if macros.initial_environment() == crate::InitialEnvironment::OriginalChecker0290 {
        // The original preprocessor expands these dynamic tokens before its
        // defined() operand protection; the constant evaluator rejects them.
        if matches!(name, "__FILE__" | "__LINE__") {
            return Err("malformed defined() call, argument given isn't an Ident".into());
        }
        Ok(macros.contains_key(name))
    } else { Ok(macro_defined(name, macros)) }
}

/// Borrow the same definitions/dependency recorder for the real conditional site.
struct ConditionLookup<'a>(&'a dyn MacroLookup);
impl MacroLookup for ConditionLookup<'_>{fn initial_environment(&self)->crate::InitialEnvironment{self.0.initial_environment()}fn condition_expansion(&self)->bool{true}fn get_key_value(&self,name:&str)->Option<(&str,&Macro)>{self.0.get_key_value(name)}fn location_read(&self,file:bool){self.0.location_read(file)}}
