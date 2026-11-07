//! ORIGINAL primary parameter path receipts. Pinned grammar: SpacemanDMM
//! 0290db5c752fa292f9824521515b603a2afd11dc parser::proc_parameter and
//! ast::VarTypeBuilder::from_iter/suffix (GPL-3.0). Uses the SAME AstFile tokens;
//! no policy lexer/parser or runtime-normalized type hint is source authority.
//! Type-path authority stays narrow. Separately fallible expression roots are
//! retained on this SAME owner; they are not current-source/metadata authority.
use crate::{Span, SpanToken, Token, TokenKind, TokenWindow};
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
    declaration_cursor:Span,
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
    /// Actual following primary token after the parameter path, before suffix/default.
    pub fn declaration_cursor(&self)->Span{self.declaration_cursor}
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
        self.type_path_using(|span|source.get(span.range()).ok_or("original parameter component outside arena"))
    }
    /// One type-path algorithm over the caller's authenticated source view.
    /// The callback projects coordinates; it does not supply a second syntax tree.
    pub fn type_path_using<'s>(&self, mut source:impl FnMut(Span)->Result<&'s str,&'static str>) -> Result<Option<String>, &'static str> {
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
                source(*span)?,
            )
        }
        Ok((!out.is_empty()).then_some(out))
    }
}
/// An absolute header entry declares a TYPE and consumes no formal slot.
/// Its written path is retained, never normalized into a parameter name/type.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HeaderTypeDeclarationSyntax {
    ordinal: usize,
    written_path: Span,
}
impl HeaderTypeDeclarationSyntax {
    pub fn ordinal(&self) -> usize {
        self.ordinal
    }
    pub fn span(&self) -> Span {
        self.written_path
    }
    pub fn written_path<'a>(&self, source: &'a str) -> Result<&'a str, &'static str> {
        source
            .get(self.written_path.range())
            .ok_or("absolute header declaration outside original source")
    }
}
#[derive(Debug, Eq, PartialEq)]
pub struct ParameterSignature {
    header: Span,
    entries: Box<[ParameterSyntax]>,
    declarations: Box<[HeaderTypeDeclarationSyntax]>,
    refusal: Option<&'static str>,
}
impl ParameterSignature {
    pub fn absolute_declarations(&self) -> Result<&[HeaderTypeDeclarationSyntax], &'static str> {
        self.refusal.map_or(Ok(&self.declarations), Err)
    }
    pub fn header(&self) -> Span {
        self.header
    }
    pub fn entries(&self) -> Result<&[ParameterSyntax], &'static str> {
        self.refusal.map_or(Ok(&self.entries), Err)
    }
    /// Owned payload census; original source and AstFile token spellings stay
    /// with their existing owner and are never copied into this receipt.
    pub fn visit_storage(&self, visit: impl FnMut(usize, usize)) {
        self.visit_signature_storage(None, visit, |_| {});
    }
    fn visit_signature_storage(
        &self,
        admission: Option<&crate::SettingAdmission<'_>>,
        mut visit: impl FnMut(usize, usize),
        mut expression: impl FnMut(&crate::Expr),
    ) {
        if !self.entries.is_empty() {
            visit(
                self.entries.as_ptr() as usize,
                std::mem::size_of_val(self.entries.as_ref()),
            );
        }
        if !self.declarations.is_empty() {
            visit(
                self.declarations.as_ptr() as usize,
                std::mem::size_of_val(self.declarations.as_ref()),
            );
        }
        for entry in &self.entries {
            if let Ok(Some(expressions)) = entry.expressions() {
                visit(
                    expressions as *const crate::ParameterExpressions as usize,
                    std::mem::size_of::<crate::ParameterExpressions>(),
                );
                expressions.visit_signature_storage(admission, &mut visit, &mut expression);
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
        std::mem::size_of::<Self>()
            .saturating_add(2 * std::mem::size_of::<usize>())
            .saturating_add(self.retained_children_bytes(None))
    }

    pub(crate) fn retained_children_bytes(
        &self,
        admission: Option<&crate::SettingAdmission<'_>>,
    ) -> usize {
        let mut storage_bytes = 0usize;
        let mut expression_bytes = 0usize;
        self.visit_signature_storage(admission, |_, n| {
            storage_bytes = storage_bytes.saturating_add(n);
        }, |expr| {
            expression_bytes = expression_bytes.saturating_add(crate::local_variable_storage::expression(expr, 0));
        });
        storage_bytes.saturating_add(expression_bytes)
    }
}

#[cfg(test)]
#[test]
fn signature_charges_only_children_without_same_domain_credit() {
    use crate::{ParameterInputCursor, SettingAdmission, SettingExpression, SharedParameterSignature};
    use crate::setting_expression::SharedSettingRetention;
    use std::sync::{atomic::{Ordering}};

    let used = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let foreign = crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a = SettingAdmission::new(&used, 1 << 20, &|| Ok(()));
    let b = SettingAdmission::new(&foreign, 1 << 20, &|| Ok(()));
    let source = "/proc/p(x = list(1, 2) as num)\n    return x\n";
    let ast = crate::parse_declaration_skeleton(source);
    let header = ast.items[0].header_span;
    let mut signature = parameter_signature_original_with_default_roots(
        source, &ast.tokens, header, 0, &mut None,
    );
    let expressions = signature.entries[0].expressions.as_mut().unwrap().as_mut().unwrap();
    let expression = expressions.default().unwrap().clone();
    let root = SettingExpression::retained_with_anchor(
        expression, SharedSettingRetention::new(a.reserve(4096).unwrap()),
    );
    expressions.default = Some(root.clone());
    let mut cursor = ParameterInputCursor::new(&a, false).unwrap();
    for token in crate::lex("num,").tokens {
        if matches!(cursor.feed(token.kind, token.span, &token.text).unwrap(),
            crate::ParameterInputFlow::Boundary)
        {
            break;
        }
    }
    let annotation = cursor.finish().unwrap();
    expressions.annotation = Some(annotation.clone());

    let gross = signature.retained_children_bytes(None);
    let own = signature.retained_children_bytes(Some(&a));
    assert!(own > 0 && own < gross);
    assert_eq!(signature.retained_children_bytes(Some(&b)), gross);
    let funded = used.load(Ordering::Acquire);
    let retained = SharedParameterSignature::retention_envelope() + own;
    let signature = SharedParameterSignature::retained_using(
        signature, a.reserve(retained).unwrap(), &a,
    ).unwrap();
    drop((root, annotation));
    assert_eq!(used.load(Ordering::Acquire), funded + retained);
    let expressions = signature.entries().unwrap()[0].expressions().unwrap().unwrap();
    assert!(expressions.default_root().unwrap().is_retained_in(&a));
    assert!(expressions.annotation().is_some());
    drop(signature);
    assert_eq!(used.load(Ordering::Acquire), crate::SettingChargeCounter::root_allocation_bytes());
}
pub(crate) fn trivia<T: ParameterToken>(t: &T) -> bool {
    matches!(
        t.kind(),
        TokenKind::Whitespace | TokenKind::Newline | TokenKind::Comment
    )
}
#[derive(Clone,Copy,Eq,PartialEq)]enum FormalPathProfile{Compiler,Original0290}
fn one<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    ordinal: usize,
    base: usize,
    following:Span,
    defaults:&mut Option<&mut dyn crate::ParameterDefaultSyntaxProvider>,
    profile:FormalPathProfile,
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
        if profile==FormalPathProfile::Compiler{return Err("absolute parameter-header declaration is outside pinned parameter issuance");}
        significant.next();
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
            declaration_cursor:shift(third.span(),base)?,
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
                declaration_cursor:shift(t.span(),base)?,
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
    let declaration_cursor=shift(significant.peek().map_or(following,|(_,token)|token.span()),base)?;
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
    let expressions = if profile==FormalPathProfile::Original0290{crate::parameter_expressions::issue_original_with_default_provider(source,tokens,&brackets,base,ordinal,defaults)}else{crate::parameter_expressions::issue_with_default_provider(source,tokens,&brackets,base,ordinal,defaults)};
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
        declaration_cursor,
        variadic: false,
        type_components: components,
        source_modifiers: flags,
        array_brackets: brackets,
        expressions,
    })
}
fn absolute<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    ordinal: usize,
    base: usize,
) -> Result<HeaderTypeDeclarationSyntax, &'static str> {
    // The native signature declaration producer accepts an unadorned absolute
    // identifier path only. Original adjacency is significant; comments/defaults,
    // arrays and declaration namespaces are not silently erased here.
    let mut tokens = tokens
        .iter()
        .filter(|t| !matches!(t.kind(), TokenKind::Whitespace | TokenKind::Newline));
    let first = tokens.next().ok_or("absolute header declaration missing")?;
    if first.text(source) != "/" {
        return Err("absolute header declaration lacks original slash");
    }
    let mut end = first.span().end;
    let mut want_identifier = true;
    for t in tokens {
        if t.span().start != end {
            return Err("absolute header declaration path is not original adjacent tokens");
        }
        if want_identifier {
            if t.kind() != TokenKind::Ident || matches!(t.text(source), "var" | "proc" | "verb") {
                return Err("unsupported absolute header declaration component");
            }
        } else if t.text(source) != "/" {
            return Err("absolute header declaration has unsupported suffix");
        }
        want_identifier = !want_identifier;
        end = t.span().end;
    }
    if want_identifier {
        return Err("absolute header declaration path is incomplete");
    }
    Ok(HeaderTypeDeclarationSyntax {
        ordinal,
        written_path: shift(Span::new(first.span().start, end), base)?,
    })
}
fn append<T: ParameterToken>(
    source: &str,
    tokens: &[T],
    base: usize,
    rows: &mut Vec<ParameterSyntax>,
    declarations: &mut Vec<HeaderTypeDeclarationSyntax>,
    following:Span,
    defaults:&mut Option<&mut dyn crate::ParameterDefaultSyntaxProvider>,
    profile:FormalPathProfile,
) -> Result<(), &'static str> {
    if rows.iter().any(ParameterSyntax::variadic) {
        return Err("original header entry follows variadic marker");
    }
    if profile==FormalPathProfile::Compiler && tokens
        .iter()
        .find(|t| !trivia(*t))
        .is_some_and(|t| t.text(source) == "/")
    {
        declarations.push(absolute(source, tokens, declarations.len(), base)?);
    } else {
        rows.push(one(source,tokens,rows.len(),base,following,defaults,profile)?);
    }
    Ok(())
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
) -> ParameterSignature {issue_tokens_with_defaults(source,tokens,header,base,&mut None,FormalPathProfile::Compiler)}
/// SAME native parameter/path/annotation producer with already-owned default
/// roots. Missing provider data is a refusal; it never calls the default parser.
pub fn parameter_signature_with_default_roots(source:&str,tokens:&[SpanToken],header:Span,base:usize,defaults:&mut dyn crate::ParameterDefaultSyntaxProvider)->ParameterSignature{issue_tokens_with_defaults(source,tokens,header,base,&mut Some(defaults),FormalPathProfile::Compiler)}
/// Original syntax DATA only. The current genuine frontend/header owner must
/// independently select and authenticate its role; this issues no model grant.
pub fn parameter_signature_original_with_default_roots(source:&str,tokens:&[SpanToken],header:Span,base:usize,defaults:&mut Option<&mut dyn crate::ParameterDefaultSyntaxProvider>)->ParameterSignature{issue_tokens_with_defaults(source,tokens,header,base,defaults,FormalPathProfile::Original0290)}
/// Checker DATA for an already-issued plain empty formal interval. This is a
/// strict subset of the Original token parser below. All trivia except plain
/// horizontal space and every ambiguous interval stay on that parser.
#[doc(hidden)]
pub fn parameter_signature_original_plain_empty(
    source: &str, tokens: TokenWindow<'_>, header: Span, argument_start: usize,
) -> Option<ParameterSignature> {
    source.get(header.range())?;
    let mut tokens = tokens.iter();
    let opening = loop {
        let token = tokens.next()?;
        if token.kind == TokenKind::Comment { return None; }
        if token.span.start >= header.start && token.span.end <= header.end
            && token.kind == TokenKind::Punctuation
            && source.get(token.span.range()) == Some("(")
        {
            break token;
        }
    };
    if opening.span.end != argument_start { return None; }
    let closing = tokens.find(|token| token.kind != TokenKind::Whitespace)?;
    if closing.kind != TokenKind::Punctuation || closing.span.end > header.end
        || source.get(closing.span.range()) != Some(")")
        || !source.get(argument_start..closing.span.start)?.bytes().all(|b| matches!(b, b' ' | b'\t'))
    {
        return None;
    }
    Some(ParameterSignature {
        header, entries: Box::default(), declarations: Box::default(), refusal: None,
    })
}

#[cfg(test)]
#[test]
fn original_plain_empty_matches_checker_and_defers_ambiguous_token_shapes() {
    for (source, plain) in [
        ("/proc/p()", true), ("/proc/p( \t )", true),
        ("/proc/p(/* retained trivia */)", false),
        ("/proc/p(\n)", false), ("/proc/p(...)", false),
        ("/proc/p(,)", false), ("/proc/p(]", false), ("/proc/p(", false),
    ] {
        let tokens = crate::lex_spans(source).tokens;
        let header = Span::new(0, source.len());
        let start = "/proc/p(".len();
        let check = |argument| parameter_signature_original_plain_empty(
            source, TokenWindow::from_slice(&tokens), header, argument,
        );
        let candidate = check(start);
        assert_eq!(candidate.is_some(), plain, "{source:?}");
        if let Some(candidate) = candidate {
            assert_eq!(candidate, parameter_signature_original_with_default_roots(
                source, &tokens, header, 0, &mut None,
            ));
        }
        assert!(check(start + 1).is_none());
    }
}
#[cfg(test)]thread_local!{pub(crate) static PARAMETER_SIGNATURE_ISSUANCES:std::cell::Cell<usize>=const{std::cell::Cell::new(0)};}
fn issue_tokens_with_defaults<T:ParameterToken>(source:&str,tokens:&[T],header:Span,base:usize,defaults:&mut Option<&mut dyn crate::ParameterDefaultSyntaxProvider>,profile:FormalPathProfile)->ParameterSignature{
    #[cfg(test)]PARAMETER_SIGNATURE_ISSUANCES.with(|counter|counter.set(counter.get()+1));
    let result = (|| -> Result<(Box<[ParameterSyntax]>,Box<[HeaderTypeDeclarationSyntax]>), &'static str> {
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
        let mut declarations=Vec::new();
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
                            append(source,&tokens[begin..i],base,&mut rows,&mut declarations,t.span(),defaults,profile)?
                        }
                        return Ok((rows.into_boxed_slice(),declarations.into_boxed_slice()));
                    }
                }
                "," if stack.len() == 1 => {
                    if tokens[begin..i].iter().all(trivia) {
                        return Err("empty original parameter between separators");
                    }
                    append(source,&tokens[begin..i],base,&mut rows,&mut declarations,t.span(),defaults,profile)?;
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
                declarations: Box::default(),
                refusal: Some(refusal),
            }
        }
    };
    match result {
        Ok((entries, declarations)) => ParameterSignature {
            header,
            entries,
            declarations,
            refusal: None,
        },
        Err(refusal) => ParameterSignature {
            header,
            entries: Box::default(),
            declarations: Box::default(),
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

#[cfg(test)]mod original_absolute_parameter_profile_tests{
 use super::*;
 #[test]fn same_actual_span_tokens_issue_original_absolute_parameters_without_compiler_declaration_rows(){
  let source="/proc/p(/datum/a/value, /foo)\n    return\n";let primary=crate::parse_declaration_skeleton(source);assert!(primary.diagnostics.is_empty());let header=primary.items[0].header_span;
  let original=parameter_signature_original_with_default_roots(source,&primary.tokens,header,0,&mut None);let entries=original.entries().unwrap();assert_eq!(entries.len(),2);assert_eq!(&source[entries[0].name().range()],"value");assert_eq!(&source[entries[1].name().range()],"foo");assert!(original.absolute_declarations().unwrap().is_empty());
  let compiler=issue_spans(source,&primary.tokens,header,0);assert!(compiler.entries().unwrap().is_empty());assert_eq!(compiler.absolute_declarations().unwrap().len(),2);
 }
}
