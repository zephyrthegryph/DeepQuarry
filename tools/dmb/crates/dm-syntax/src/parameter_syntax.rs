//! ORIGINAL primary parameter path receipts. Pinned grammar: SpacemanDMM
//! 0290db5c752fa292f9824521515b603a2afd11dc parser::proc_parameter and
//! ast::VarTypeBuilder::from_iter/suffix (GPL-3.0). Uses the SAME AstFile tokens;
//! no policy lexer/parser or runtime-normalized type hint is source authority.
//! Type-path authority stays narrow. Separately fallible expression roots are
//! retained on this SAME owner; they are not current-source/metadata authority.
use crate::{Span, SpanToken, Token, TokenKind};
pub(crate) trait ParameterToken {
    fn span(&self) -> Span;
    fn kind(&self) -> TokenKind;
    fn text<'a>(&'a self, source: &'a str) -> &'a str;
    fn expression(source: &str, tokens: &[Self]) -> crate::ParsedExpr
    where
        Self: Sized;
}
impl ParameterToken for Token {
    fn expression(_: &str, tokens: &[Self]) -> crate::ParsedExpr {
        crate::expression_parser::parse_expression_tokens(tokens)
    }
    fn span(&self) -> Span {
        self.span
    }
    fn kind(&self) -> TokenKind {
        self.kind
    }
    fn text<'a>(&'a self, _: &'a str) -> &'a str {
        &self.text
    }
}
impl ParameterToken for SpanToken {
    fn expression(source: &str, tokens: &[Self]) -> crate::ParsedExpr {
        crate::expression_parser::parse_expression_span_tokens(source, tokens)
    }
    fn span(&self) -> Span {
        self.span
    }
    fn kind(&self) -> TokenKind {
        self.kind
    }
    fn text<'a>(&'a self, source: &'a str) -> &'a str {
        SpanToken::text(*self, source)
    }
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ParameterSyntax {
    ordinal: usize,
    name: Span,
    variadic: bool,
    type_components: Box<[Span]>,
    source_modifiers: u8,
    array_brackets: Box<[Span]>,
    expressions: Result<Option<Box<crate::ParameterExpressions>>, &'static str>,
}
impl ParameterSyntax {
    /// Original syntax roots only; not a current-source/metadata admission proof.
    pub fn expressions(&self) -> Result<Option<&crate::ParameterExpressions>, &'static str> {
        self.expressions
            .as_ref()
            .map(|value| value.as_deref())
            .map_err(|reason| *reason)
    }
    pub fn ordinal(&self) -> usize {
        self.ordinal
    }
    pub fn name(&self) -> Span {
        self.name
    }
    pub fn variadic(&self) -> bool {
        self.variadic
    }
    pub fn type_components(&self) -> &[Span] {
        &self.type_components
    }
    pub fn source_modifiers(&self) -> u8 {
        self.source_modifiers
    }
    pub fn array_brackets(&self) -> &[Span] {
        &self.array_brackets
    }
    pub fn type_path(&self, source: &str) -> Result<Option<String>, &'static str> {
        if self.variadic {
            return Ok(None);
        }
        let mut out = String::new();
        // The old suffix prepends list ONCE, regardless dimension count.
        if !self.array_brackets.is_empty() {
            out.push_str("/list")
        }
        for span in &self.type_components {
            out.push('/');
            out.push_str(
                source
                    .get(span.range())
                    .ok_or("original parameter component outside arena")?,
            )
        }
        Ok((!out.is_empty()).then_some(out))
    }
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ParameterSignature {
    header: Span,
    entries: Box<[ParameterSyntax]>,
    refusal: Option<&'static str>,
}
impl ParameterSignature {
    pub fn header(&self) -> Span {
        self.header
    }
    pub fn entries(&self) -> Result<&[ParameterSyntax], &'static str> {
        self.refusal.map_or(Ok(&self.entries), Err)
    }
    /// Owned payload census; original source and AstFile token spellings stay
    /// with their existing owner and are never copied into this receipt.
    pub fn visit_storage(&self, mut visit: impl FnMut(usize, usize)) {
        if !self.entries.is_empty() {
            visit(
                self.entries.as_ptr() as usize,
                std::mem::size_of_val(self.entries.as_ref()),
            );
        }
        for entry in &self.entries {
            if let Ok(Some(expressions)) = entry.expressions() {
                visit(
                    expressions as *const crate::ParameterExpressions as usize,
                    std::mem::size_of::<crate::ParameterExpressions>(),
                );
                expressions.visit_storage(&mut visit);
            }
            for spans in [&entry.type_components, &entry.array_brackets] {
                if !spans.is_empty() {
                    visit(
                        spans.as_ptr() as usize,
                        std::mem::size_of_val(spans.as_ref()),
                    );
                }
            }
        }
    }
    pub fn visit_expression_roots<'a>(&'a self, mut visit: impl FnMut(&'a crate::Expr)) {
        for entry in &self.entries {
            if let Ok(Some(expressions)) = entry.expressions() {
                expressions.visit_roots(&mut visit);
            }
        }
    }
    /// Optional expression payloads must fit inside the ORIGINAL header receipt
    /// allowance. Refusing these roots never refuses the independent type-path
    /// receipt. The caller retains its existing metadata-only admission gate.
    pub fn admit_optional_expressions(&mut self, total_allowance: usize) {
        if self.retained_bytes() <= total_allowance {
            return;
        }
        // Drop the whole optional cohort deterministically rather than choosing
        // a parameter-order dependent subset. Ok(None) still proves no clauses.
        for entry in &mut self.entries {
            if matches!(&entry.expressions, Ok(Some(_))) {
                entry.expressions = Err("formal optional roots exceed original header admission");
            }
        }
    }
    pub fn retained_bytes(&self) -> usize {
        let mut bytes =
            std::mem::size_of::<Self>().saturating_add(2 * std::mem::size_of::<usize>());
        self.visit_storage(|_, n| bytes = bytes.saturating_add(n));
        self.visit_expression_roots(|expr| {
            bytes = bytes.saturating_add(crate::local_variable_storage::expression(expr, 0))
        });
        bytes
    }
}
pub(crate) fn trivia<T: ParameterToken>(t: &T) -> bool {
    matches!(
        t.kind(),
        TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
    )
}
fn one<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    ordinal: usize,
    base: usize,
) -> Result<ParameterSyntax, &'static str> {
    let mut significant = tokens
        .iter()
        .enumerate()
        .filter(|(_, t)| !trivia(*t))
        .map(|(i, t)| (i, t))
        .peekable();
    let mut path = Vec::new();
    if significant
        .peek()
        .is_some_and(|(_, t)| t.text(source) == "/")
    {
        return Err("absolute parameter-header declaration is outside pinned parameter issuance");
    }
    // Primary lexing retains punctuation one byte at a time. The pinned
    // ellipsis requires the three ORIGINAL dots to be byte-adjacent.
    if significant
        .peek()
        .is_some_and(|(_, t)| t.text(source) == ".")
    {
        let (_, first) = significant.next().unwrap();
        let (_, second) = significant
            .next()
            .ok_or("incomplete original variadic token")?;
        let (_, third) = significant
            .next()
            .ok_or("incomplete original variadic token")?;
        if second.text(source) != "."
            || third.text(source) != "."
            || first.span().end != second.span().start
            || second.span().end != third.span().start
            || significant.next().is_some()
        {
            return Err("variadic marker was not one original adjacent token");
        }
        return Ok(ParameterSyntax {
            ordinal,
            name: shift(Span::new(first.span().start, third.span().end), base)?,
            variadic: true,
            type_components: Box::default(),
            source_modifiers: 0,
            array_brackets: Box::default(),
            expressions: Ok(None),
        });
    }
    if let Some((_, t)) = significant.peek() {
        if t.text(source) == "..." {
            let t = *t;
            significant.next();
            if significant.next().is_some() {
                return Err("variadic parameter has unexpected trailing tokens");
            }
            return Ok(ParameterSyntax {
                ordinal,
                name: shift(t.span(), base)?,
                variadic: true,
                type_components: Box::default(),
                source_modifiers: 0,
                array_brackets: Box::default(),
                expressions: Ok(None),
            });
        }
    }
    loop {
        let (_, t) = significant
            .next()
            .ok_or("parameter path is empty or incomplete")?;
        if t.kind() != TokenKind::Ident {
            return Err("parameter path lacks original identifier token");
        }
        path.push(t.span());
        if significant
            .peek()
            .is_some_and(|(_, t)| t.text(source) == "/")
        {
            significant.next();
            continue;
        }
        break;
    }
    let name = path.pop().ok_or("parameter original name missing")?;
    if path
        .first()
        .is_some_and(|s| source.get(s.range()) == Some("var"))
    {
        path.remove(0);
    }
    let mut flags = 0;
    let mut prefix = 0;
    while let Some(s) = path.get(prefix) {
        let name = source
            .get(s.range())
            .ok_or("parameter modifier source missing")?;
        let Some(f) = crate::local_variable_syntax::source_modifier(name) else {
            break;
        };
        flags |= f;
        prefix += 1;
    }
    let mut brackets = Vec::new();
    while significant
        .peek()
        .is_some_and(|(_, t)| t.text(source) == "[")
    {
        let (_, opening) = significant.next().unwrap();
        let mut stack = vec!["]"];
        let mut last = None;
        while let Some((i, t)) = significant.next() {
            match t.text(source) {
                "[" => stack.push("]"),
                "(" => stack.push(")"),
                "{" => stack.push("}"),
                "]" | ")" | "}" => {
                    if stack.pop() != Some(t.text(source)) {
                        return Err("parameter suffix delimiters differ from original grammar");
                    }
                    if stack.is_empty() {
                        last = Some((i, t));
                        break;
                    }
                }
                _ => (),
            }
        }
        let (_, close) = last.ok_or("parameter suffix close missing")?;
        brackets.push(Span::new(opening.span().start, close.span().end));
    }
    // The path receipt does not certify default/as/in semantics. Their original
    // roots are issued separately below and RETAINED on this same owner;
    // unsupported roots are an explicit error, never an empty valid clause.
    if let Some((_, next)) = significant.peek() {
        if !matches!(next.text(source), "=" | "as" | "in" | ";") {
            return Err("parameter type path has an unissued following cursor");
        }
    }
    let expressions = crate::parameter_expressions::issue(source, tokens, &brackets, base);
    let components = path[prefix..]
        .iter()
        .map(|s| shift(*s, base))
        .collect::<Result<Box<[_]>, _>>()?;
    let brackets = brackets
        .into_iter()
        .map(|s| shift(s, base))
        .collect::<Result<Box<[_]>, _>>()?;
    Ok(ParameterSyntax {
        ordinal,
        name: shift(name, base)?,
        variadic: false,
        type_components: components,
        source_modifiers: flags,
        array_brackets: brackets,
        expressions,
    })
}
fn shift(span: Span, base: usize) -> Result<Span, &'static str> {
    Ok(Span::new(
        span.start
            .checked_add(base)
            .ok_or("parameter origin overflow")?,
        span.end
            .checked_add(base)
            .ok_or("parameter origin overflow")?,
    ))
}
pub(crate) fn issue(
    source: &str,
    tokens: &[Token],
    header: Span,
    base: usize,
) -> ParameterSignature {
    issue_tokens(source, tokens, header, base)
}
pub(crate) fn issue_spans(
    source: &str,
    tokens: &[SpanToken],
    header: Span,
    base: usize,
) -> ParameterSignature {
    issue_tokens(source, tokens, header, base)
}
fn issue_tokens<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    header: Span,
    base: usize,
) -> ParameterSignature {
    let result = (|| -> Result<Box<[ParameterSyntax]>, &'static str> {
        let first = tokens
            .iter()
            .position(|t| {
                t.span().start >= header.start
                    && t.span().end <= header.end
                    && t.kind() == TokenKind::Punctuation
                    && t.text(source) == "("
            })
            .ok_or("original parameter opening token missing")?;
        let mut stack = vec![")"];
        let mut begin = first + 1;
        let mut rows = Vec::new();
        for (i, t) in tokens.iter().enumerate().skip(first + 1) {
            if t.span().end > header.end {
                return Err("original parameter close outside header");
            }
            if trivia(t) {
                continue;
            }
            match t.text(source) {
                "(" => stack.push(")"),
                "[" => stack.push("]"),
                "{" => stack.push("}"),
                ")" | "]" | "}" => {
                    if stack.pop() != Some(t.text(source)) {
                        return Err("parameter header delimiters differ from original grammar");
                    }
                    if stack.is_empty() {
                        if tokens[begin..i].iter().any(|t| !trivia(t)) {
                            rows.push(one(source, &tokens[begin..i], rows.len(), base)?)
                        }
                        return Ok(rows.into_boxed_slice());
                    }
                }
                "," if stack.len() == 1 => {
                    if tokens[begin..i].iter().all(trivia) {
                        return Err("empty original parameter between separators");
                    }
                    rows.push(one(source, &tokens[begin..i], rows.len(), base)?);
                    begin = i + 1;
                }
                _ => (),
            }
        }
        Err("original parameter header close missing")
    })();
    let header = match shift(header, base) {
        Ok(h) => h,
        Err(refusal) => {
            return ParameterSignature {
                header,
                entries: Box::default(),
                refusal: Some(refusal),
            }
        }
    };
    match result {
        Ok(entries) => ParameterSignature {
            header,
            entries,
            refusal: None,
        },
        Err(refusal) => ParameterSignature {
            header,
            entries: Box::default(),
            refusal: Some(refusal),
        },
    }
}
#[cfg(test)]
#[path = "parameter_syntax_tests.rs"]
mod tests;

#[cfg(test)]
mod aggregate_optional_admission_tests {
    #[test]
    fn tiny_optional_headroom_drops_roots_without_losing_type_paths() {
        let source = "/proc/p(datum/A/x=!!!!1, y=1+2, z)\n    return 1\n";
        let cold = crate::parse_declaration_skeleton(source);
        assert!(cold.diagnostics.is_empty());
        let original = || {
            crate::parse_proc_with_origins_from_spans(source, cold.items[0].span, &cold.tokens, 0)
                .unwrap()
                .parameters
        };
        let mut signature = original();
        assert!(signature.entries().unwrap()[0]
            .expressions()
            .unwrap()
            .is_some());
        let full = signature.retained_bytes();
        signature.admit_optional_expressions(0);
        let metadata = signature.retained_bytes();
        assert!(metadata < full);
        assert_eq!(
            signature.entries().unwrap()[0]
                .type_path(source)
                .unwrap()
                .as_deref(),
            Some("/datum/A")
        );
        assert!(signature.entries().unwrap()[0].expressions().is_err());
        assert!(signature.entries().unwrap()[1].expressions().is_err());
        assert_eq!(signature.entries().unwrap()[2].expressions(), Ok(None));
        // Metadata admission remains the caller's decision, even at zero room.
        assert!(metadata > 0);
        let mut exact = original();
        exact.admit_optional_expressions(metadata);
        assert_eq!(exact.retained_bytes(), metadata);
        assert!(exact.entries().unwrap()[0].expressions().is_err());
    }
}
