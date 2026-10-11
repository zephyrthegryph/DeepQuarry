use super::*;

/// Parse the expression subset used by declaration defaults and simple procedure bodies.
/// Invalid or unsupported syntax returns a diagnostic instead of a guessed expression.
pub fn parse_expression(source: &str) -> ParsedExpr {
    let lexical = lex(source);
    let mut parser = ExprParser {
        tokens: lexical
            .tokens
            .into_iter()
            .filter(|t| {
                !matches!(
                    t.kind,
                    TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
                )
            })
            .collect(),
        index: 0,
        ternary_then_depth: 0,
        diagnostics: lexical.diagnostics,
    };
    let expr = parser.expression(0);
    if let Some(token) = parser.peek() {
        parser.diagnostics.push(Diagnostic {
            span: token.span,
            kind: DiagnosticKind::Expression,
            message: format!("unexpected token in expression: {}", token.text),
        });
    }
    ParsedExpr {
        expr,
        diagnostics: parser.diagnostics,
    }
}

struct ExprParser {
    tokens: Vec<Token>,
    index: usize,
    ternary_then_depth: usize,
    diagnostics: Vec<Diagnostic>,
}

impl ExprParser {
    pub(super) fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.index)
    }
    pub(super) fn take(&mut self) -> Option<Token> {
        let token = self.peek()?.clone();
        self.index += 1;
        Some(token)
    }
    fn take_text(&mut self, text: &str) -> Option<Token> {
        if self.peek().is_some_and(|t| t.text == text) {
            self.take()
        } else {
            None
        }
    }
    pub(super) fn error(&mut self, span: Span, message: impl Into<String>) {
        self.diagnostics.push(Diagnostic {
            span,
            kind: DiagnosticKind::Expression,
            message: message.into(),
        });
    }

    pub(super) fn expression(&mut self, min_bp: u8) -> Option<Expr> {
        let mut lhs = self.prefix()?;
        loop {
            if self.ternary_then_depth > 0
                && self.peek().is_some_and(|token| token.text == ":")
                && self
                    .tokens
                    .get(self.index + 1)
                    .is_none_or(|token| token.text != ":")
                && !self.colon_member_before_ternary_separator(&lhs)
            {
                break;
            }
            if min_bp <= 26 {
                if let Some(open) = self.take_text("{") {
                    let mut fields = Vec::new();
                    while self.peek().is_some_and(|next| next.text != "}") {
                        let Some(name) = self.take() else {
                            break;
                        };
                        if name.kind != TokenKind::Ident {
                            self.error(name.span, "expected object initializer field name");
                            break;
                        }
                        if self.take_text("=").is_none() {
                            self.error(name.span, "expected = after object initializer field");
                            break;
                        }
                        let Some(value) = self.expression_nested(0) else {
                            self.error(name.span, "expected object initializer field value");
                            break;
                        };
                        fields.push((name.text, value));
                        if self.take_text(",").is_none() && self.take_text(";").is_none() {
                            break;
                        }
                    }
                    let end = self.take_text("}").map_or_else(
                        || {
                            self.error(open.span, "unclosed object initializer");
                            lhs.span.end
                        },
                        |close| close.span.end,
                    );
                    lhs = Expr {
                        span: Span::new(lhs.span.start, end),
                        kind: ExprKind::ObjectInitializer {
                            object: Box::new(lhs),
                            fields,
                        },
                    };
                    continue;
                }
                if let (Some(first), Some(second)) =
                    (self.tokens.get(self.index), self.tokens.get(self.index + 1))
                {
                    if first.text == second.text
                        && matches!(first.text.as_str(), "+" | "-")
                        && first.span.end == second.span.start
                    {
                        let op = if first.text == "+" {
                            "post++"
                        } else {
                            "post--"
                        };
                        let end = second.span.end;
                        self.index += 2;
                        lhs = Expr {
                            span: Span::new(lhs.span.start, end),
                            kind: ExprKind::Unary {
                                op: op.into(),
                                value: Box::new(lhs),
                            },
                        };
                        continue;
                    }
                }
                if self.peek().is_some_and(|token| token.text == "?")
                    && self.tokens.get(self.index + 1).is_some_and(|token| {
                        (token.text == "." || token.text == "[")
                            && self.tokens[self.index].span.end == token.span.start
                    })
                {
                    self.take();
                    let separator = self.take().unwrap();
                    if separator.text == "." {
                        let Some(selector) = self.take() else {
                            self.error(separator.span, "expected safe member name");
                            break;
                        };
                        if selector.kind != TokenKind::Ident {
                            self.error(selector.span, "expected safe member name");
                            break;
                        }
                        lhs = Expr {
                            span: Span::new(lhs.span.start, selector.span.end),
                            kind: ExprKind::SafeMember {
                                object: Box::new(lhs),
                                selector: selector.text,
                            },
                        };
                    } else {
                        let index = self.expression_nested(0);
                        let end = self.take_text("]").map_or_else(
                            || {
                                self.error(separator.span, "unclosed safe index");
                                lhs.span.end
                            },
                            |token| token.span.end,
                        );
                        if let Some(index) = index {
                            lhs = Expr {
                                span: Span::new(lhs.span.start, end),
                                kind: ExprKind::SafeIndex {
                                    object: Box::new(lhs),
                                    index: Box::new(index),
                                },
                            };
                        }
                    }
                    continue;
                }
                if let Some(open) = self.take_text("(") {
                    let mut args = Vec::new();
                    if self.peek().is_some_and(|t| t.text != ")") {
                        loop {
                            if self.peek().is_some_and(|next| next.text == ",") {
                                let at = self.peek().unwrap().span.start;
                                args.push(Expr {
                                    span: Span::new(at, at),
                                    kind: ExprKind::Literal("null".into()),
                                });
                                self.take();
                                continue;
                            }
                            let Some(mut arg) = self.expression_nested(0) else {
                                self.error(open.span, "missing call argument");
                                break;
                            };
                            if self.take_text(";").is_some() {
                                let Some(value) = self.expression_nested(0) else {
                                    self.error(arg.span, "missing weighted pick value");
                                    break;
                                };
                                arg = Expr {
                                    span: Span::new(arg.span.start, value.span.end),
                                    kind: ExprKind::Binary {
                                        op: ";".into(),
                                        lhs: Box::new(arg),
                                        rhs: Box::new(value),
                                    },
                                };
                            }
                            args.push(arg);
                            if self.take_text(",").is_none() {
                                break;
                            }
                            if self.peek().is_some_and(|next| next.text == ")") {
                                break;
                            }
                        }
                    }
                    let end = self.take_text(")").map_or_else(
                        || {
                            self.error(open.span, "unclosed call");
                            lhs.span.end
                        },
                        |t| t.span.end,
                    );
                    lhs = Expr {
                        span: Span::new(lhs.span.start, end),
                        kind: ExprKind::Call {
                            callee: Box::new(lhs),
                            args,
                        },
                    };
                    // `in` is an optional locate clause, so it belongs inside
                    // an enclosing prefix operator (`!locate(T) in L`).
                    if matches!(&lhs.kind, ExprKind::Call { callee, args }
                        if matches!(&callee.kind, ExprKind::Ident(name) if name == "locate")
                            && args.len() <= 1)
                        && self.take_text("in").is_some()
                    {
                        let container = self.expression(8)?;
                        lhs = Expr {
                            span: Span::new(lhs.span.start, container.span.end),
                            kind: ExprKind::Binary {
                                op: "in".into(),
                                lhs: Box::new(lhs),
                                rhs: Box::new(container),
                            },
                        };
                    }
                    continue;
                }
                if let Some(open) = self.take_text("[") {
                    let index = self.expression_nested(0);
                    let end = self.take_text("]").map_or_else(
                        || {
                            self.error(open.span, "unclosed index");
                            lhs.span.end
                        },
                        |t| t.span.end,
                    );
                    if let Some(index) = index {
                        lhs = Expr {
                            span: Span::new(lhs.span.start, end),
                            kind: ExprKind::Index {
                                object: Box::new(lhs),
                                index: Box::new(index),
                            },
                        };
                    }
                    continue;
                }
                if self.peek().is_some_and(|t| t.text == "." || t.text == ":") {
                    let separator = self.take().unwrap();
                    let is_static = separator.text == ":" && self.take_text(":").is_some();
                    let Some(selector) = self.take() else {
                        self.error(separator.span, "expected member after selector");
                        break;
                    };
                    if selector.kind != TokenKind::Ident {
                        self.error(selector.span, "expected member name");
                        break;
                    }
                    lhs = Expr {
                        span: Span::new(lhs.span.start, selector.span.end),
                        kind: if is_static {
                            ExprKind::StaticMember {
                                object: Box::new(lhs),
                                selector: selector.text,
                            }
                        } else {
                            ExprKind::Member {
                                object: Box::new(lhs),
                                selector: selector.text,
                                via_colon: separator.text == ":",
                            }
                        },
                    };
                    continue;
                }
            }
            if min_bp <= 8 && self.take_text("as").is_some() {
                let mut types = Vec::new();
                let mut end = lhs.span.end;
                loop {
                    let Some(kind) = self.take() else {
                        self.error(lhs.span, "missing input type after as");
                        break;
                    };
                    if kind.kind != TokenKind::Ident {
                        self.error(kind.span, "expected input type after as");
                        break;
                    }
                    end = kind.span.end;
                    types.push(kind.text);
                    if self.take_text("|").is_none() {
                        break;
                    }
                }
                lhs = Expr {
                    span: Span::new(lhs.span.start, end),
                    kind: ExprKind::TypeFilter {
                        value: Box::new(lhs),
                        types,
                    },
                };
                continue;
            }
            if min_bp <= 2 && self.take_text("?").is_some() {
                self.ternary_then_depth += 1;
                let then_value = self.expression(0);
                self.ternary_then_depth -= 1;
                let then_value = then_value?;
                if self.take_text(":").is_none() {
                    self.error(lhs.span, "ternary expression requires :");
                    return Some(lhs);
                }
                let else_value = self.expression(2)?;
                lhs = Expr {
                    span: Span::new(lhs.span.start, else_value.span.end),
                    kind: ExprKind::Conditional {
                        condition: Box::new(lhs),
                        then_value: Box::new(then_value),
                        else_value: Box::new(else_value),
                    },
                };
                continue;
            }
            let Some((op, width, left_bp, right_bp)) = self.operator() else {
                break;
            };
            if left_bp < min_bp {
                break;
            }
            self.index += width;
            if self.peek().is_none() && self.diagnostics.is_empty() {
                self.diagnostics.push(Diagnostic {
                    span: Span::new(lhs.span.end, lhs.span.end),
                    kind: DiagnosticKind::IncompleteExpression,
                    // The recognized binary operator exhausted its expression
                    // input. Use the compiler's general missing-expression
                    // wording; retain operator detail for uncertified recovery.
                    message: "missing expression".into(),
                });
                break;
            }
            let Some(rhs) = self.expression(right_bp) else {
                self.error(lhs.span, format!("missing right operand for {op}"));
                break;
            };
            lhs = Expr {
                span: Span::new(lhs.span.start, rhs.span.end),
                kind: ExprKind::Binary {
                    op,
                    lhs: Box::new(lhs),
                    rhs: Box::new(rhs),
                },
            };
        }
        Some(lhs)
    }

    fn colon_member_before_ternary_separator(&self, lhs: &Expr) -> bool {
        let Some(colon) = self.tokens.get(self.index) else {
            return false;
        };
        let Some(member) = self.tokens.get(self.index + 1) else {
            return false;
        };
        if lhs.span.end != colon.span.start
            || colon.span.end != member.span.start
            || member.kind != TokenKind::Ident
        {
            return false;
        }
        let mut nesting = 0usize;
        for token in self.tokens.iter().skip(self.index + 2) {
            match token.text.as_str() {
                "(" | "[" | "{" => nesting += 1,
                ")" | "]" | "}" if nesting == 0 => break,
                ")" | "]" | "}" => nesting -= 1,
                "," | ";" if nesting == 0 => break,
                ":" if nesting == 0 => return true,
                _ => {}
            }
        }
        false
    }

    fn expression_nested(&mut self, min_bp: u8) -> Option<Expr> {
        let previous = self.ternary_then_depth;
        self.ternary_then_depth = 0;
        let result = self.expression(min_bp);
        self.ternary_then_depth = previous;
        result
    }

    pub(super) fn prefix(&mut self) -> Option<Expr> {
        let token = self.take()?;
        let span = token.span;
        match token.kind {
            TokenKind::Ident if token.text == "new" => {
                if self.peek().is_none() {
                    return Some(Expr {
                        span,
                        kind: ExprKind::Call {
                            callee: Box::new(Expr {
                                span,
                                kind: ExprKind::Ident("new".into()),
                            }),
                            args: Vec::new(),
                        },
                    });
                }
                if let Some(open) = self.take_text("(") {
                    let mut args = Vec::new();
                    if self.peek().is_some_and(|next| next.text != ")") {
                        loop {
                            if self.peek().is_some_and(|next| next.text == ",") {
                                let at = self.peek().unwrap().span.start;
                                args.push(Expr {
                                    span: Span::new(at, at),
                                    kind: ExprKind::Literal("null".into()),
                                });
                                self.take();
                                continue;
                            }
                            let Some(arg) = self.expression_nested(0) else {
                                self.error(open.span, "missing constructor argument");
                                break;
                            };
                            args.push(arg);
                            if self.take_text(",").is_none() {
                                break;
                            }
                            if self.peek().is_some_and(|next| next.text == ")") {
                                break;
                            }
                        }
                    }
                    let end = self.take_text(")").map_or_else(
                        || {
                            self.error(open.span, "unclosed constructor");
                            open.span.end
                        },
                        |close| close.span.end,
                    );
                    return Some(Expr {
                        span: Span::new(span.start, end),
                        kind: ExprKind::Call {
                            callee: Box::new(Expr {
                                span,
                                kind: ExprKind::Ident("new".into()),
                            }),
                            args,
                        },
                    });
                }
                let value = self.expression(24)?;
                Some(Expr {
                    span: Span::new(span.start, value.span.end),
                    kind: ExprKind::Unary {
                        op: token.text,
                        value: Box::new(value),
                    },
                })
            }
            TokenKind::Ident if token.text == "null" => Some(Expr {
                span,
                kind: ExprKind::Literal(token.text),
            }),
            TokenKind::Ident => Some(Expr {
                span,
                kind: ExprKind::Ident(token.text),
            }),
            TokenKind::Number | TokenKind::String | TokenKind::Resource => Some(Expr {
                span,
                kind: ExprKind::Literal(token.text),
            }),
            TokenKind::Operator if matches!(token.text.as_str(), "-" | "+" | "!" | "~") => {
                if matches!(token.text.as_str(), "-" | "+")
                    && self.peek().is_some_and(|next| {
                        next.text == token.text && next.span.start == token.span.end
                    })
                {
                    self.take();
                    if self.peek().is_none() && self.diagnostics.is_empty() {
                        self.diagnostics.push(Diagnostic {
                            span,
                            kind: DiagnosticKind::IncompleteExpression,
                            message: format!(
                                "missing operand for prefix {}{}",
                                token.text, token.text
                            ),
                        });
                        return None;
                    }
                    let value = self.expression(26)?;
                    return Some(Expr {
                        span: Span::new(span.start, value.span.end),
                        kind: ExprKind::Unary {
                            op: if token.text == "+" {
                                "pre++".into()
                            } else {
                                "pre--".into()
                            },
                            value: Box::new(value),
                        },
                    });
                }
                if self.peek().is_none() && self.diagnostics.is_empty() {
                    self.diagnostics.push(Diagnostic {
                        span,
                        kind: DiagnosticKind::IncompleteExpression,
                        message: format!("missing operand for unary {}", token.text),
                    });
                    return None;
                }
                let value = self.expression(26)?;
                Some(Expr {
                    span: Span::new(span.start, value.span.end),
                    kind: ExprKind::Unary {
                        op: token.text,
                        value: Box::new(value),
                    },
                })
            }
            TokenKind::Punctuation if token.text == "(" => {
                let value = self.expression_nested(0)?;
                let end = self.take_text(")").map_or_else(
                    || {
                        if self.peek().is_none() && self.diagnostics.is_empty() {
                            self.diagnostics.push(Diagnostic {
                                span,
                                kind: DiagnosticKind::IncompleteExpression,
                                message: "unclosed group".into(),
                            });
                        } else {
                            self.error(span, "unclosed group");
                        }
                        value.span.end
                    },
                    |t| t.span.end,
                );
                Some(Expr {
                    span: Span::new(span.start, end),
                    kind: ExprKind::Group(Box::new(value)),
                })
            }
            TokenKind::Punctuation if token.text == "/" => {
                let mut path = String::from("/");
                let mut end = span.end;
                while let Some(next) = self.peek() {
                    if next.span.start != end {
                        break;
                    }
                    if next.kind == TokenKind::Ident || next.text == "/" {
                        path.push_str(&next.text);
                        end = next.span.end;
                        self.index += 1;
                    } else if next.text == "."
                        && self.tokens.get(self.index + 1).is_some_and(|kind| {
                            matches!(kind.text.as_str(), "proc" | "verb" | "var")
                        })
                        && self
                            .tokens
                            .get(self.index + 2)
                            .is_some_and(|slash| slash.text == "/")
                    {
                        path.push('.');
                        path.push_str(&self.tokens[self.index + 1].text);
                        end = self.tokens[self.index + 1].span.end;
                        self.index += 2;
                    } else {
                        break;
                    }
                }
                if path == "/" {
                    self.error(span, "expected type path after /");
                    None
                } else {
                    path.truncate(path.trim_end_matches('/').len());
                    Some(Expr {
                        span: Span::new(span.start, end),
                        kind: ExprKind::TypePath(path),
                    })
                }
            }
            TokenKind::Punctuation if token.text == "." => {
                if let Some(second) = self.take_text(".") {
                    Some(Expr {
                        span: Span::new(span.start, second.span.end),
                        kind: ExprKind::Ident("..".into()),
                    })
                } else if self
                    .peek()
                    .is_some_and(|next| matches!(next.text.as_str(), "proc" | "verb" | "var"))
                    && self
                        .tokens
                        .get(self.index + 1)
                        .is_some_and(|next| next.text == "/")
                {
                    let mut path = String::from(".");
                    let mut end = span.end;
                    while let Some(next) = self.peek() {
                        if next.span.start != end {
                            break;
                        }
                        if next.kind == TokenKind::Ident || next.text == "/" {
                            path.push_str(&next.text);
                            end = next.span.end;
                            self.index += 1;
                        } else {
                            break;
                        }
                    }
                    path.truncate(path.trim_end_matches('/').len());
                    Some(Expr {
                        span: Span::new(span.start, end),
                        kind: ExprKind::TypePath(path),
                    })
                } else {
                    Some(Expr {
                        span,
                        kind: ExprKind::Ident(".".into()),
                    })
                }
            }
            _ => {
                self.error(span, format!("unexpected expression token: {}", token.text));
                None
            }
        }
    }

    fn operator(&self) -> Option<(String, usize, u8, u8)> {
        const OPS: &[(&str, u8, u8)] = &[
            ("=", 1, 1),
            ("+=", 1, 1),
            ("-=", 1, 1),
            ("*=", 1, 1),
            ("/=", 1, 1),
            ("%=", 1, 1),
            ("|=", 1, 1),
            ("&=", 1, 1),
            ("^=", 1, 1),
            ("<<=", 1, 1),
            (">>=", 1, 1),
            ("||=", 1, 1),
            ("&&=", 1, 1),
            ("||", 3, 4),
            ("&&", 5, 6),
            ("in", 7, 8),
            ("to", 8, 9),
            ("==", 7, 8),
            ("!=", 7, 8),
            ("~=", 7, 8),
            ("~!", 7, 8),
            ("<=", 9, 10),
            (">=", 9, 10),
            ("<", 9, 10),
            (">", 9, 10),
            ("|", 11, 12),
            ("^", 13, 14),
            ("&", 15, 16),
            ("<<", 17, 18),
            (">>", 17, 18),
            ("+", 19, 20),
            ("-", 19, 20),
            ("*", 21, 22),
            ("/", 21, 22),
            ("%", 21, 22),
            ("**", 25, 26),
        ];
        let first = self.peek()?;
        if !matches!(
            first.kind,
            TokenKind::Operator | TokenKind::Punctuation | TokenKind::Ident
        ) {
            return None;
        }
        let mut best: Option<(String, usize, u8, u8)> = None;
        for (op, l, r) in OPS {
            let mut width = 0;
            let mut assembled = String::new();
            for token in self.tokens.iter().skip(self.index) {
                if assembled.len() >= op.len()
                    || token.span.start != first.span.start + assembled.len()
                {
                    break;
                }
                assembled.push_str(&token.text);
                width += 1;
                if assembled == *op && best.as_ref().is_none_or(|b| op.len() > b.0.len()) {
                    best = Some(((*op).into(), width, *l, *r));
                }
            }
        }
        best
    }
}

#[cfg(test)]
mod incomplete_tests {
    use super::*;
    #[test]
    fn unary_eof_certificates_survive_statement_parsing_at_exact_operand_spans() {
        for (operator, message) in [
            ("!", "missing operand for unary !"),
            ("~", "missing operand for unary ~"),
            ("++", "missing operand for prefix ++"),
        ] {
            let source = format!("// shifted\n/proc/probe()\n    return {operator}\n");
            let ast = crate::parse(&source);
            assert!(ast.diagnostics.is_empty(), "{:?}", ast.diagnostics);
            let parsed = crate::parse_body_items(&ast.items[0].children);
            let diagnostic = parsed
                .diagnostics
                .iter()
                .find(|diagnostic| diagnostic.kind == DiagnosticKind::IncompleteExpression)
                .expect("statement parser must preserve typed EOF certificate");
            assert_eq!(diagnostic.message, message);
            assert_eq!(diagnostic.span.start, source.rfind(operator).unwrap());
        }
        for value in ["!1", "~1", "++value", "!@"] {
            let ast = crate::parse(&format!("/proc/probe()\n    return {value}\n"));
            let parsed = crate::parse_body_items(&ast.items[0].children);
            assert!(!parsed
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.kind == DiagnosticKind::IncompleteExpression));
        }
    }
    #[test]
    fn certified_binary_eof_uses_common_missing_expression_wording() {
        for source in ["1 +", "(1 +", "1 *", "1 &&", "1 =="] {
            let parsed = parse_expression(source);
            let diagnostic = parsed
                .diagnostics
                .iter()
                .find(|d| d.kind == DiagnosticKind::IncompleteExpression)
                .unwrap();
            assert_eq!(diagnostic.message, "missing expression", "{source}");
        }
        let parsed = parse_expression("1 + @");
        assert!(!parsed
            .diagnostics
            .iter()
            .any(|d| d.kind == DiagnosticKind::IncompleteExpression));
    }

    #[test]
    fn only_recognized_eof_failures_are_certified() {
        for source in ["1 +", "(1 +", "(1", "!", "~", "+", "-", "++", "--"] {
            assert!(
                parse_expression(source)
                    .diagnostics
                    .iter()
                    .any(|d| d.kind == DiagnosticKind::IncompleteExpression),
                "{source}"
            );
        }
        for source in [
            "/datum/example",
            "new /datum/example",
            "1 + @",
            "(1 @",
            "list(1,)",
            "!1",
            "~1",
            "+1",
            "-1",
            "++value",
            "--value",
            "!@",
        ] {
            assert!(
                !parse_expression(source)
                    .diagnostics
                    .iter()
                    .any(|d| d.kind == DiagnosticKind::IncompleteExpression),
                "{source}"
            );
        }
    }
}
