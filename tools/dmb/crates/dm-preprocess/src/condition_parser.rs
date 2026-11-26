use super::*;

pub(super) fn eval_condition(expr: &str, macros: &dyn MacroLookup) -> Result<bool, String> {
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
        if parenthesized {
            index += 1;
        }
        let name = tokens
            .get(index)
            .filter(|token| token.kind == TokenKind::Ident)
            .ok_or("expected identifier after defined")?;
        let yes = macro_defined(name.text(expr), macros);
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
    let expanded = expand(
        &protected,
        macros,
        0,
        ExpandLocation {
            line: 1,
            file_name: "",
        },
    )?;
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
    Ok(value != 0)
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
    pub(super) fn parse(&mut self, min_bp: u8) -> Result<i64, String> {
        let mut lhs = if self.take("!") {
            (self.parse(21)? == 0) as i64
        } else if self.take("~") {
            !self.parse(21)?
        } else if self.take("-") {
            self.parse(21)?.wrapping_neg()
        } else if self.take("+") {
            self.parse(21)?
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
            macro_defined(&name, self.macros) as i64
        } else {
            let token = self
                .tokens
                .get(self.index)
                .ok_or("missing #if operand")?
                .clone();
            self.index += 1;
            if token.kind == TokenKind::Number {
                parse_int(&token.text)?
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
            lhs = match op {
                "||" => ((lhs != 0) || (rhs != 0)) as i64,
                "&&" => ((lhs != 0) && (rhs != 0)) as i64,
                "|" => lhs | rhs,
                "^" => lhs ^ rhs,
                "&" => lhs & rhs,
                "==" => (lhs == rhs) as i64,
                "!=" => (lhs != rhs) as i64,
                "<" => (lhs < rhs) as i64,
                "<=" => (lhs <= rhs) as i64,
                ">" => (lhs > rhs) as i64,
                ">=" => (lhs >= rhs) as i64,
                "<<" => lhs.wrapping_shl(rhs as u32),
                ">>" => lhs.wrapping_shr(rhs as u32),
                "+" => lhs.wrapping_add(rhs),
                "-" => lhs.wrapping_sub(rhs),
                "*" => lhs.wrapping_mul(rhs),
                "/" if rhs != 0 => lhs.wrapping_div(rhs),
                "%" if rhs != 0 => lhs.wrapping_rem(rhs),
                "/" | "%" => return Err("division by zero in #if".into()),
                _ => unreachable!(),
            };
        }
        Ok(lhs)
    }

    fn macro_value(&self, name: &str) -> Result<i64, String> {
        let Some(definition) = self.macros.get(name) else {
            return Ok(0);
        };
        if definition.parameters.is_some() {
            return Ok(0);
        }
        if definition.replacement.trim().is_empty() {
            return Ok(0);
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
