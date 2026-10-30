//! ORIGINAL primary parameter path receipts. Pinned grammar: SpacemanDMM
//! 0290db5c752fa292f9824521515b603a2afd11dc parser::proc_parameter and
//! ast::VarTypeBuilder::from_iter/suffix (GPL-3.0). Uses the SAME AstFile tokens;
//! no policy lexer/parser or runtime-normalized type hint is source authority.
//! This is TYPE-PATH authority only, not full default/header syntax admission.
use crate::{Span, Token, TokenKind};
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ParameterSyntax {
    ordinal: usize,
    name: Span,
    variadic: bool,
    type_components: Box<[Span]>,
    source_modifiers: u8,
    array_brackets: Box<[Span]>,
}
impl ParameterSyntax {
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
    pub fn retained_bytes(&self) -> usize {
        let mut bytes =
            std::mem::size_of::<Self>().saturating_add(2 * std::mem::size_of::<usize>());
        self.visit_storage(|_, n| bytes = bytes.saturating_add(n));
        bytes
    }
}
fn trivia(t: &Token) -> bool {
    matches!(
        t.kind,
        TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
    )
}
fn one(
    source: &str,
    tokens: &[Token],
    ordinal: usize,
    base: usize,
) -> Result<ParameterSyntax, &'static str> {
    let mut significant = tokens
        .iter()
        .enumerate()
        .filter(|(_, t)| !trivia(t))
        .map(|(i, t)| (i, t))
        .peekable();
    let mut path = Vec::new();
    if significant.peek().is_some_and(|(_, t)| t.text == "/") {
        return Err("absolute parameter-header declaration is outside pinned parameter issuance");
    }
    // Primary lexing retains punctuation one byte at a time. The pinned
    // ellipsis requires the three ORIGINAL dots to be byte-adjacent.
    if significant.peek().is_some_and(|(_, t)| t.text == ".") {
        let (_, first) = significant.next().unwrap();
        let (_, second) = significant
            .next()
            .ok_or("incomplete original variadic token")?;
        let (_, third) = significant
            .next()
            .ok_or("incomplete original variadic token")?;
        if second.text != "."
            || third.text != "."
            || first.span.end != second.span.start
            || second.span.end != third.span.start
            || significant.next().is_some()
        {
            return Err("variadic marker was not one original adjacent token");
        }
        return Ok(ParameterSyntax {
            ordinal,
            name: shift(Span::new(first.span.start, third.span.end), base)?,
            variadic: true,
            type_components: Box::default(),
            source_modifiers: 0,
            array_brackets: Box::default(),
        });
    }
    if let Some((_, t)) = significant.peek() {
        if t.text == "..." {
            let t = *t;
            significant.next();
            if significant.next().is_some() {
                return Err("variadic parameter has unexpected trailing tokens");
            }
            return Ok(ParameterSyntax {
                ordinal,
                name: shift(t.span, base)?,
                variadic: true,
                type_components: Box::default(),
                source_modifiers: 0,
                array_brackets: Box::default(),
            });
        }
    }
    loop {
        let (_, t) = significant
            .next()
            .ok_or("parameter path is empty or incomplete")?;
        if t.kind != TokenKind::Ident {
            return Err("parameter path lacks original identifier token");
        }
        path.push(t.span);
        if significant.peek().is_some_and(|(_, t)| t.text == "/") {
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
    while significant.peek().is_some_and(|(_, t)| t.text == "[") {
        let (_, opening) = significant.next().unwrap();
        let mut stack = vec!["]"];
        let mut last = None;
        while let Some((i, t)) = significant.next() {
            match t.text.as_str() {
                "[" => stack.push("]"),
                "(" => stack.push(")"),
                "{" => stack.push("}"),
                "]" | ")" | "}" => {
                    if stack.pop() != Some(t.text.as_str()) {
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
        brackets.push(Span::new(opening.span.start, close.span.end));
    }
    // This receipt proves only the parameter type path, modifiers and suffix
    // arity. The containing ORIGINAL token stream already balances the whole
    // header. Default/as/in expression interpretation remains with the existing
    // compiler grammar; do not parse/drop a second expression tree here.
    if let Some((_, next)) = significant.peek() {
        if !matches!(next.text.as_str(), "=" | "as" | "in" | ";") {
            return Err("parameter type path has an unissued following cursor");
        }
    }
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
    let result = (|| -> Result<Box<[ParameterSyntax]>, &'static str> {
        let first = tokens
            .iter()
            .position(|t| {
                t.span.start >= header.start
                    && t.span.end <= header.end
                    && t.kind == TokenKind::Punctuation
                    && t.text == "("
            })
            .ok_or("original parameter opening token missing")?;
        let mut stack = vec![")"];
        let mut begin = first + 1;
        let mut rows = Vec::new();
        for (i, t) in tokens.iter().enumerate().skip(first + 1) {
            if t.span.end > header.end {
                return Err("original parameter close outside header");
            }
            if trivia(t) {
                continue;
            }
            match t.text.as_str() {
                "(" => stack.push(")"),
                "[" => stack.push("]"),
                "{" => stack.push("}"),
                ")" | "]" | "}" => {
                    if stack.pop() != Some(t.text.as_str()) {
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
