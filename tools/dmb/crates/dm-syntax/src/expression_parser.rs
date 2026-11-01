use super::*;

/// Parse the expression subset used by declaration defaults and simple procedure bodies.
/// Invalid or unsupported syntax returns a diagnostic instead of a guessed expression.
pub fn parse_expression(source: &str) -> ParsedExpr {
    let lexical = lex(source);
    finish_expression(lexical.tokens, lexical.diagnostics)
}
/// SAME primary parser for an original literal interpolation child. The
/// literal producer already identified/spliced this genuine child; no consumer
/// reconstructs a declaration expression. Caller reserves its scratch first.
pub(crate) fn parse_expression_with_admission(
    source: &str,
    admission: &crate::SettingAdmission<'_>,
) -> ParsedExpr {
    if admission.checkpoint().is_err() {
        return ParsedExpr {
            expr: None,
            diagnostics: Vec::new(),
        };
    }
    let lexical = lex(source);
    finish_expression_with_admission(lexical.tokens, lexical.diagnostics, Some(admission))
}

/// Existing primary expression parser over already-issued primary body tokens.
/// No lexer/source scan and no second expression tree is involved.
pub(crate) fn parse_expression_span_tokens(source: &str, tokens: &[SpanToken]) -> ParsedExpr {
    let owned = tokens
        .iter()
        .map(|token| Token {
            kind: token.kind,
            span: token.span,
            text: token.text(source).to_owned(),
        })
        .collect();
    finish_expression(owned, Vec::new())
}
/// Existing primary parser over the original owned-token producer. Tokens are
/// temporary parser input, not another semantic/AST owner or a source reparse.
pub(crate) fn parse_expression_tokens(tokens: &[Token]) -> ParsedExpr {
    finish_expression(tokens.to_vec(), Vec::new())
}
/// Same primary grammar, admitted native setting entry. The original owner
/// reserves parser/scratch storage BEFORE calling; this does not grant source
/// authority or establish a new grammar/stack-coverage claim.
pub(crate) fn parse_expression_span_tokens_with_admission(
    source: &str,
    tokens: &[SpanToken],
    current_offset: usize,
    admission: &crate::SettingAdmission<'_>,
) -> ParsedExpr {
    let mut owned = Vec::new();
    for token in tokens {
        if admission.checkpoint().is_err() {
            return ParsedExpr {
                expr: None,
                diagnostics: Vec::new(),
            };
        }
        let Some(text) = source.get(token.span.range()) else {
            admission.record_operational_error(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "original setting token range unavailable",
            ));
            return ParsedExpr {
                expr: None,
                diagnostics: Vec::new(),
            };
        };
        let Some(start) = token.span.start.checked_add(current_offset) else {
            admission.record_operational_error(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "current setting token offset overflow",
            ));
            return ParsedExpr {
                expr: None,
                diagnostics: Vec::new(),
            };
        };
        let Some(end) = token.span.end.checked_add(current_offset) else {
            admission.record_operational_error(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "current setting token end overflow",
            ));
            return ParsedExpr {
                expr: None,
                diagnostics: Vec::new(),
            };
        };
        owned.push(Token {
            kind: token.kind,
            span: Span::new(start, end),
            text: text.to_owned(),
        });
    }
    finish_expression_with_admission(owned, Vec::new(), Some(admission))
}
fn finish_expression(tokens: Vec<Token>, diagnostics: Vec<Diagnostic>) -> ParsedExpr {
    finish_expression_with_admission(tokens, diagnostics, None)
}
fn finish_expression_with_admission(
    tokens: Vec<Token>,
    diagnostics: Vec<Diagnostic>,
    admission: Option<&crate::SettingAdmission<'_>>,
) -> ParsedExpr {
    let mut parser = ExprParser {
        tokens: expression_tokens(tokens),
        index: 0,
        ternary_then_depth: 0,
        diagnostics,
        admission,
    };
    let expr = parser.expression(0);
    if parser.admission.is_some_and(|a| a.is_stopped()) {
        // A recoverable syntax diagnostic is not the actual operation error.
        // Discard any partial grammar recovery; the enclosing checked producer
        // must extract the SAME admission's original IO before publication.
        if let Some(expression) = expr {
            crate::setting_drop::drop_expression(expression, None);
        }
        return ParsedExpr {
            expr: None,
            diagnostics: Vec::new(),
        };
    }
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

/// Project the existing lossless tokens to primary expression punctuation.
/// Scope is maximal-munch BEFORE conditional/member parsing consumes colons.
/// Trivia is discarded but original byte adjacency is still authoritative.
fn expression_tokens(tokens: Vec<Token>) -> Vec<Token> {
    let mut input = tokens
        .into_iter()
        .filter(|token| {
            !matches!(
                token.kind,
                TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
            )
        })
        .peekable();
    let mut output = Vec::new();
    while let Some(mut token) = input.next() {
        if token.text == ":"
            && input
                .peek()
                .is_some_and(|next| next.text == ":" && token.span.end == next.span.start)
        {
            let next = input.next().unwrap();
            token.text.push(':');
            token.span.end = next.span.end;
        }
        output.push(token);
    }
    output
}

// Pratt's left fold can create a deep AST WITHOUT deep parser recursion.
// Bound its possible error-unwind destructor work against the host's explicit
// operation stack allowance before another fold. This is never syntax meaning.
fn admitted_drop_shape(root: &Expr, admission: &crate::SettingAdmission<'_>) -> bool {
    let mut pending = vec![(root, 1usize)];
    while let Some((value, depth)) = pending.pop() {
        if admission.admit_drop_depth(depth).is_err() {
            return false;
        }
        let next = depth.saturating_add(1);
        match &value.kind {
            ExprKind::Unary { value, .. }
            | ExprKind::Group(value)
            | ExprKind::TypeFilter { value, .. } => pending.push((value, next)),
            ExprKind::Binary { lhs, rhs, .. } => {
                pending.push((lhs, next));
                pending.push((rhs, next));
            }
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                pending.push((condition, next));
                pending.push((then_value, next));
                pending.push((else_value, next));
            }
            ExprKind::Call { callee, args } => {
                pending.push((callee, next));
                pending.extend(args.iter().map(|a| (a, next)));
            }
            ExprKind::Member { object, .. }
            | ExprKind::StaticMember { object, .. }
            | ExprKind::SafeMember { object, .. } => pending.push((object, next)),
            ExprKind::ObjectInitializer { object, fields } => {
                pending.push((object, next));
                pending.extend(fields.iter().map(|(_, a)| (a, next)));
            }
            ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
                pending.push((object, next));
                pending.push((index, next));
            }
            ExprKind::Ident(_) | ExprKind::TypePath(_) | ExprKind::Literal(_) => (),
        }
    }
    true
}
#[derive(Clone, Copy, Eq, PartialEq)]
enum PostfixMode {
    Expression,
    ConstructorPrefab,
    ConstructorMini,
}

struct ExprParser<'op> {
    admission: Option<&'op crate::SettingAdmission<'op>>,
    tokens: Vec<Token>,
    index: usize,
    ternary_then_depth: usize,
    diagnostics: Vec<Diagnostic>,
}

impl ExprParser<'_> {
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
        let admission = self.admission;
        let _frame = match admission {
            Some(admission) => Some(admission.parser_frame().ok()?),
            None => None,
        };
        let lhs = self.prefix()?;
        self.expression_from(min_bp, lhs, PostfixMode::Expression)
    }

    // Reuse the primary postfix grammar, but terminate a constructor target
    // after its FIRST argument list. Later follows bind to the new object.
    fn expression_from(&mut self, min_bp: u8, mut lhs: Expr, mode: PostfixMode) -> Option<Expr> {
        loop {
            if let Some(admission) = self.admission {
                if !admitted_drop_shape(&lhs, admission) {
                    crate::setting_drop::drop_expression(lhs, None);
                    return None;
                }
            }
            if self.ternary_then_depth > 0
                && self.peek().is_some_and(|token| token.text == ":")
                && !self.colon_member_before_ternary_separator(&lhs)
            {
                break;
            }
            if min_bp <= 26 {
                if mode != PostfixMode::ConstructorMini
                    && self.peek().is_some_and(|t| t.text == "{")
                {
                    let open = self.take().unwrap();
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
                    if mode == PostfixMode::Expression
                        && first.text == second.text
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
                        matches!(token.text.as_str(), "." | ":" | "[")
                            && mode != PostfixMode::ConstructorPrefab
                            && (mode == PostfixMode::Expression || token.text != "[")
                            && self.tokens[self.index].span.end == token.span.start
                    })
                {
                    self.take();
                    let separator = self.take().unwrap();
                    if matches!(separator.text.as_str(), "." | ":") {
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
                                via_colon: separator.text == ":",
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
                    if mode != PostfixMode::Expression {
                        break;
                    }
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
                if mode == PostfixMode::Expression && self.peek().is_some_and(|t| t.text == "[") {
                    let open = self.take().unwrap();
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
                if mode != PostfixMode::ConstructorPrefab
                    && self
                        .peek()
                        .is_some_and(|t| matches!(t.text.as_str(), "." | ":" | "::"))
                {
                    let separator = self.take().unwrap();
                    let is_static = separator.text == "::";
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
            if mode != PostfixMode::Expression {
                break;
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
            if min_bp <= 3 && self.take_text("?").is_some() {
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

    fn original_prefab_tail(&mut self,start:&str,span:Span,namespace_dot:bool)->Option<Expr>{
        let mut path=String::from(start);let mut end=span.end;
        while let Some(next)=self.peek(){if next.span.start!=end{break}if next.kind==TokenKind::Ident||next.text=="/"{path.push_str(&next.text);end=next.span.end;self.index+=1;}else if namespace_dot&&next.text=="."&&self.tokens.get(self.index+1).is_some_and(|kind|matches!(kind.text.as_str(),"proc"|"verb"|"var"))&&self.tokens.get(self.index+2).is_some_and(|slash|slash.text=="/"){path.push('.');path.push_str(&self.tokens[self.index+1].text);end=self.tokens[self.index+1].span.end;self.index+=2;}else{break}}
        if path==start{self.error(span,format!("expected type path after {start}"));None}else{path.truncate(path.trim_end_matches('/').len());Some(Expr{span:Span::new(span.start,end),kind:ExprKind::TypePath(path)})}
    }

    pub(super) fn prefix(&mut self) -> Option<Expr> {
        let token = self.take()?;
        let span = token.span;
        match token.kind {
            TokenKind::Punctuation | TokenKind::Operator if token.text == "::" => {
                let Some(name) = self.take() else {
                    self.error(span, "expected global procedure name after ::");
                    return None;
                };
                if name.kind != TokenKind::Ident {
                    self.error(name.span, "expected global procedure name after ::");
                    return None;
                }
                // The scope operator is retained by PRIMARY syntax. It is not
                // a member receiver, unscoped identifier or text-side analysis.
                // The primary scope marker also represents the original bare
                // GlobalIdent term. Call dispatch remains decided by postfix ().
                Some(Expr {
                    span: Span::new(span.start, name.span.end),
                    kind: ExprKind::Unary {
                        op: "::".into(),
                        value: Box::new(Expr {
                            span: name.span,
                            kind: ExprKind::Ident(name.text),
                        }),
                    },
                })
            }
            // Pinned input_type accepts the exact empty type tuple in
            // as(()) as well as an absent type in as(). Keep this ONLY in
            // the contextual as primitive; ordinary empty groups stay invalid.
            TokenKind::Ident if token.text == "as"
                && self.tokens.get(self.index).is_some_and(|t|t.text=="(")
                && self.tokens.get(self.index+1).is_some_and(|t|t.text=="(")
                && self.tokens.get(self.index+2).is_some_and(|t|t.text==")")
                && self.tokens.get(self.index+3).is_some_and(|t|t.text==")") =>
            {
                let end=self.tokens[self.index+3].span.end;
                self.index+=4;
                Some(Expr{span:Span::new(span.start,end),kind:ExprKind::Call{
                    callee:Box::new(Expr{span,kind:ExprKind::Ident(token.text)}),args:Vec::new(),
                }})
            }
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
                let target = match self.peek() {
                    Some(next) if next.kind == TokenKind::Ident => {
                        let target = self.take().unwrap();
                        Some((
                            Expr {
                                span: target.span,
                                kind: ExprKind::Ident(target.text),
                            },
                            PostfixMode::ConstructorMini,
                        ))
                    }
                    Some(next) if matches!(next.text.as_str(), "/" | ".") => {
                        let target = self.prefix()?;
                        let mode = if matches!(target.kind, ExprKind::TypePath(_)) {
                            PostfixMode::ConstructorPrefab
                        } else {
                            PostfixMode::ConstructorMini
                        };
                        Some((target, mode))
                    }
                    _ => None,
                };
                let Some((target, mode)) = target else {
                    // A bare contextual new can precede a delimiter/operator,
                    // not only end-of-input (for example list(new, new)).
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
                };
                let value = self.expression_from(24, target, mode)?;
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
                kind: ExprKind::Literal(crate::LiteralText::at(token.text, span.start)),
            }),
            TokenKind::Ident => Some(Expr {
                span,
                kind: ExprKind::Ident(token.text),
            }),
            TokenKind::Number | TokenKind::String | TokenKind::Resource => Some(Expr {
                span,
                kind: ExprKind::Literal(crate::LiteralText::at(token.text, span.start)),
            }),
            TokenKind::Operator if matches!(token.text.as_str(), "-" | "+" | "!" | "~" | "*" | "&") => {
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
            TokenKind::Punctuation if token.text == "/" => self.original_prefab_tail("/",span,true),
            TokenKind::Punctuation if token.text == ":" => self.original_prefab_tail(":",span,false),
            TokenKind::Punctuation if token.text == "." => {
                if let Some(second) = self.take_text(".") {
                    Some(Expr {
                        span: Span::new(span.start, second.span.end),
                        kind: ExprKind::Ident("..".into()),
                    })
                } else if self.peek().is_some_and(|next| next.kind==TokenKind::Ident)
                {
                    self.original_prefab_tail(".",span,false)
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
            // DreamMaker binds the bit operators looser than comparison and shifts looser than relational operators
            // (`a == b | c` is `(a == b) | c`, `a << b < c` is `a << (b < c)`), measured against dm.exe.
            ("|", 7, 8),
            ("^", 9, 10),
            ("&", 11, 12),
            // `in` is the loosest operator of all, below `?:`: `a in b ? c : d` is `a in (b ? c : d)` and
            // `a || b in c` is `(a || b) in c` (dm.exe 516.1687).
            ("in", 0, 1),
            ("==", 13, 14),
            ("!=", 13, 14),
            ("<>", 13, 14),
            ("~=", 13, 14),
            ("~!", 13, 14),
            ("to", 14, 15),
            ("<<", 15, 16),
            (">>", 15, 16),
            ("<=>", 17, 18),
            ("<=", 17, 18),
            (">=", 17, 18),
            ("<", 17, 18),
            (">", 17, 18),
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
        // `<>` is DreamMaker's spelling of `!=`.
        if let Some(found) = best.as_mut() {
            if found.0 == "<>" {
                found.0 = "!=".into();
            }
        }
        best
    }
}

#[cfg(test)]
mod incomplete_tests {
    use super::*;
    #[test]
    fn membership_is_below_assignment_and_both_sides_of_ternary() {
        for source in ["a = b in c", "a ? b : c in d"] {
            let parsed = parse_expression(source);
            assert!(
                parsed.diagnostics.is_empty(),
                "{source}: {:?}",
                parsed.diagnostics
            );
            let ExprKind::Binary { op, lhs, .. } = parsed.expr.unwrap().kind else {
                panic!("{source}")
            };
            assert_eq!(op, "in");
            assert!(
                matches!(lhs.kind, ExprKind::Binary { ref op, .. } if op == "=")
                    || matches!(lhs.kind, ExprKind::Conditional { .. }),
                "{source}"
            );
        }
        let parsed = parse_expression("a in b ? c : d");
        let ExprKind::Binary { op, rhs, .. } = parsed.expr.unwrap().kind else {
            panic!()
        };
        assert_eq!(op, "in");
        assert!(matches!(rhs.kind, ExprKind::Conditional { .. }));
        let parsed = parse_expression("a in b = c");
        let ExprKind::Binary { op, rhs, .. } = parsed.expr.unwrap().kind else {
            panic!()
        };
        assert_eq!(op, "in");
        assert!(matches!(rhs.kind, ExprKind::Binary { ref op, .. } if op == "="));
    }
    #[test]
    fn prefix_pointer_dereference_parses_after_a_binary_operator() {
        // DreamMaker 516.1681 accepts `a +* 2` and `a * * 2` (fixtures/diagnostics/cases/bad_operator).
        for source in ["a +* 2", "a * * 2", "*a", "a -* 2"] {
            let parsed = parse_expression(source);
            assert!(
                parsed.diagnostics.is_empty(),
                "{source}: {:?}",
                parsed.diagnostics
            );
        }
    }
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

#[cfg(test)]
mod setting_admission_parser_tests {
    use super::*;
    #[test]
    fn admitted_primary_grammar_keeps_compatibility_tree_and_stops_during_real_parse() {
        let source = "call(1+2,3+4)";
        let lexical = crate::lex_spans(source);
        assert!(lexical.diagnostics.is_empty());
        let counter = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let polls = std::cell::Cell::new(0);
        let stop_at = lexical.tokens.len() + 3;
        let stopped = || {
            polls.set(polls.get() + 1);
            if polls.get() == stop_at {
                Err(std::io::Error::new(
                    std::io::ErrorKind::Interrupted,
                    "actual primary parser checkpoint",
                ))
            } else {
                Ok(())
            }
        };
        let admission = crate::SettingAdmission::new(&counter, 1024 * 1024, &stopped);
        let interrupted =
            parse_expression_span_tokens_with_admission(source, &lexical.tokens, 0, &admission);
        assert!(interrupted.expr.is_none());
        assert!(admission.is_stopped());
        assert_eq!(
            polls.get(),
            stop_at,
            "stop follows token conversion and original grammar entry"
        );
        let actual = admission.take_operational_error().unwrap();
        assert_eq!(actual.kind(), std::io::ErrorKind::Interrupted);
        assert_eq!(actual.to_string(), "actual primary parser checkpoint");
        let healthy = || Ok(());
        let retry = crate::SettingAdmission::new(&counter, 1024 * 1024, &healthy);
        let retried =
            parse_expression_span_tokens_with_admission(source, &lexical.tokens, 0, &retry);
        assert!(retried.diagnostics.is_empty());
        assert_eq!(retried.expr, crate::parse_expression(source).expr);
        assert!(!retry.is_stopped());
    }
}

#[cfg(test)]mod pinned_debug_grammar_gap_tests{
 use super::*;
 fn expression(text:&str)->Expr{let parsed=parse_expression(text);assert!(parsed.diagnostics.is_empty(),"{text}: {:?}",parsed.diagnostics);parsed.expr.unwrap()}
 #[test]fn primary_spaceship_uses_original_relational_precedence_and_exact_adjacent_tokens(){
  for(text,outer)in[("a <=> b","<=>"),("a <=> b << c","<<"),("a <=> b == c","=="),("a <=> b < c","<")]{let expr=expression(text);let ExprKind::Binary{op,lhs,..}=&expr.kind else{panic!("binary")};assert_eq!(op,outer);if outer!="<=>"{assert!(matches!(&lhs.kind,ExprKind::Binary{op,..}if op=="<=>"))}}
  for text in["a < = > b","a <= > b","a < => b"]{assert!(!parse_expression(text).diagnostics.is_empty(),"nonadjacent spelling accepted: {text}")}
 }
 #[test]fn primary_empty_input_type_tuple_is_contextual_and_preserves_complete_original_span(){
  for text in["as(())","as( ( ) )","as(/*a*/ ( /*b*/ ) /*c*/) "]{let expr=expression(text);let ExprKind::Call{callee,args}=&expr.kind else{panic!("as primitive")};assert!(matches!(&callee.kind,ExprKind::Ident(name)if name=="as"));assert!(args.is_empty());assert_eq!(expr.span.start,0);assert_eq!(expr.span.end,text.trim_end().len());}
  for text in["()","f(())","as((()))"]{assert!(!parse_expression(text).diagnostics.is_empty(),"general empty/parenthesized type was admitted: {text}")}
 }
}

#[cfg(test)]mod original_reference_and_prefab_term_tests{
 use super::*;
 #[test]fn primary_original_relative_prefab_reference_and_bare_global_are_distinct_nodes(){
  for text in[".child/type",".proc/run"]{let parsed=parse_expression(text);assert!(parsed.diagnostics.is_empty(),"{text}: {:?}",parsed.diagnostics);assert!(matches!(parsed.expr.unwrap().kind,ExprKind::TypePath(ref path)if path==text));}
  let reference=parse_expression("&value");assert!(reference.diagnostics.is_empty());assert!(matches!(reference.expr.unwrap().kind,ExprKind::Unary{op,value}if op=="&"&&matches!(value.kind,ExprKind::Ident(ref name)if name=="value")));
  let global=parse_expression("::value");assert!(global.diagnostics.is_empty());assert!(matches!(global.expr.unwrap().kind,ExprKind::Unary{op,value}if op=="::"&&matches!(value.kind,ExprKind::Ident(ref name)if name=="value")));
  assert!(matches!(parse_expression("::value()").expr.unwrap().kind,ExprKind::Call{callee,..}if matches!(callee.kind,ExprKind::Unary{ref op,..}if op=="::")));
  assert!(matches!(parse_expression(".()").expr.unwrap().kind,ExprKind::Call{callee,..}if matches!(callee.kind,ExprKind::Ident(ref name)if name==".")));
  assert!(!parse_expression("::").diagnostics.is_empty());assert!(!parse_expression("&").diagnostics.is_empty());
 }
}

/// SAME primary child lexer/parser, retaining ONLY its span/kind geometry for
/// later source diagnostics. No child reparse or owned token spelling survives.
pub(crate) fn parse_expression_with_primary_tokens(source:&str,admission:Option<&crate::SettingAdmission<'_>>)->Result<(ParsedExpr,Vec<SpanToken>),String>{
 if let Some(a)=admission{a.checkpoint().map_err(|_|"interpolation operation stopped".to_owned())?;}
 let lexical=lex(source);let mut spans=Vec::new();let count=lexical.tokens.len();
 spans.try_reserve_exact(count).map_err(|_|{if let Some(a)=admission{a.record_operational_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"primary interpolation token geometry allocation refused"));}"primary interpolation token geometry allocation refused".to_owned()})?;
 if spans.capacity()>count.saturating_mul(4){if let Some(a)=admission{a.record_operational_error(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"primary interpolation token geometry exposed excess"));}return Err("primary interpolation token geometry exposed excess".into())}
 for token in &lexical.tokens{if let Some(a)=admission{a.checkpoint().map_err(|_|"interpolation operation stopped".to_owned())?;}spans.push(SpanToken{kind:token.kind,span:token.span});}
 Ok((finish_expression_with_admission(lexical.tokens,lexical.diagnostics,admission),spans))
}

#[cfg(test)]mod original_colon_prefab_primary{
 use super::*;
 #[test]fn primary_colon_prefab_preserves_original_node_and_call_arguments_without_changing_ternary(){for text in[":child",":child/type",":proc/run"]{let parsed=parse_expression(text);assert!(parsed.diagnostics.is_empty(),"{text}: {:?}",parsed.diagnostics);let value=parsed.expr.unwrap();assert_eq!(value.span,Span::new(0,text.len()));assert!(matches!(value.kind,ExprKind::TypePath(ref path)if path==text));}let call=parse_expression("filter(type=:child)");assert!(call.diagnostics.is_empty(),"{:?}",call.diagnostics);let ternary=parse_expression("a ? b : c");assert!(ternary.diagnostics.is_empty());assert!(matches!(ternary.expr.unwrap().kind,ExprKind::Conditional{..}));for text in[":",":(child)"]{assert!(!parse_expression(text).diagnostics.is_empty(),"invalid colon prefab {text}");}}
}
