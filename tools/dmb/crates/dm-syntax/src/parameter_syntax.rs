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
#[derive(Clone)]
pub struct ParameterSyntax {
    ordinal: usize,
    name: Span,
    declaration_cursor:Span,
    variadic: bool,
    type_components: Box<[Span]>,
    source_modifiers: u8,
    native_children: u8,
    array_brackets: Box<[Span]>,
    expressions: Result<Option<Box<crate::ParameterExpressions>>, &'static str>,
}
impl std::fmt::Debug for ParameterSyntax{
 fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("ParameterSyntax").field("ordinal",&self.ordinal).field("name",&self.name).field("declaration_cursor",&self.declaration_cursor).field("variadic",&self.variadic).field("type_components",&self.type_components).field("source_modifiers",&self.source_modifiers).field("array_brackets",&self.array_brackets).field("expressions",&self.expressions).finish()}
}
impl PartialEq for ParameterSyntax{
 fn eq(&self,other:&Self)->bool{self.ordinal==other.ordinal&&self.name==other.name&&self.declaration_cursor==other.declaration_cursor&&self.variadic==other.variadic&&self.type_components==other.type_components&&self.source_modifiers==other.source_modifiers&&self.array_brackets==other.array_brackets&&self.expressions==other.expressions}
}
impl Eq for ParameterSyntax{}
impl ParameterSyntax {
    /// Original syntax roots only; not a current-source/metadata admission proof.
    pub fn native_child_observation(&self)->Option<(bool,bool,bool)>{
        self.expressions.as_ref().ok()?;
        (self.native_children != 0).then_some((self.native_children & 1 != 0,self.native_children & 2 != 0,self.native_children & 4 != 0))
    }
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
#[derive(Clone,Copy,Eq,PartialEq)]enum FormalPathProfile{Compiler,Original0290,NativeObserved,OriginalNativeObserved}
impl FormalPathProfile{fn original(self)->bool{matches!(self,Self::Original0290|Self::OriginalNativeObserved)}fn observed(self)->bool{matches!(self,Self::NativeObserved|Self::OriginalNativeObserved)}}
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
        if !profile.original(){return Err("absolute parameter-header declaration is outside pinned parameter issuance");}
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
            native_children: if profile.observed() {9} else {0},
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
            native_children: if profile.observed() {9} else {0},
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
            let (_, slash)=significant.next().unwrap();
            // Pinned tree_path accepts a trailing slash without another ident;
            // proc_parameter still pops the last actual ident as the name.
            // This narrow Original receipt covers only the terminal separator.
            if profile.original() && significant.peek().is_none(){
                let span=slash.span();
                if slash.kind()!=TokenKind::Punctuation || span.end.checked_sub(span.start)!=Some(1) || t.span().end>span.start || span.end>following.start{
                    return Err("original trailing parameter slash occurrence differs");
                }
                break;
            }
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
    let mut native_no_child=false;
    let expressions = if profile==FormalPathProfile::OriginalNativeObserved{let(result,observed)=crate::parameter_expressions::issue_original_native_observed(source,tokens,&brackets,base,ordinal,defaults);native_no_child=observed;result}else if profile==FormalPathProfile::Original0290{crate::parameter_expressions::issue_original_with_default_provider(source,tokens,&brackets,base,ordinal,defaults)}else if profile==FormalPathProfile::NativeObserved{let(result,observed)=crate::parameter_expressions::issue_native_observed(source,tokens,&brackets,base,ordinal,defaults);native_no_child=observed;result}else{crate::parameter_expressions::issue_with_default_provider(source,tokens,&brackets,base,ordinal,defaults)};
    let native_children=match (&expressions,defaults.as_mut()){
        (Ok(expressions),Some(provider))=>match provider.native_child_observation(ordinal,expressions.as_deref())?{Some((complete,recovered,deferred))=>8|u8::from(complete && !recovered && !deferred)|(u8::from(recovered)<<1)|(u8::from(deferred)<<2),None=>0},
        _ if native_no_child=>9,
        _=>0,
    };
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
        native_children,
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
    if !profile.original() && tokens
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
/// SAME canonical parameter production, observed only by the private actual native recipe.
/// Child-bearing entries still require their actual producer observations.
pub(crate) fn parameter_signature_native_observed(source:&str,tokens:&[SpanToken],header:Span,base:usize,defaults:&mut Option<&mut dyn crate::ParameterDefaultSyntaxProvider>)->ParameterSignature{
 issue_tokens_with_defaults(source,tokens,header,base,defaults,FormalPathProfile::NativeObserved)
}
pub fn parameter_signature_with_default_roots(source:&str,tokens:&[SpanToken],header:Span,base:usize,defaults:&mut dyn crate::ParameterDefaultSyntaxProvider)->ParameterSignature{issue_tokens_with_defaults(source,tokens,header,base,&mut Some(defaults),FormalPathProfile::Compiler)}
/// Original syntax DATA only. The current genuine frontend/header owner must
/// independently select and authenticate its role; this issues no model grant.
pub fn parameter_signature_original_with_default_roots(source:&str,tokens:&[SpanToken],header:Span,base:usize,defaults:&mut Option<&mut dyn crate::ParameterDefaultSyntaxProvider>)->ParameterSignature{issue_tokens_with_defaults(source,tokens,header,base,defaults,FormalPathProfile::Original0290)}
/// Native completion DATA on the SAME Original grammar productions. No source/current grant.
pub fn parameter_signature_original_with_native_observation(source:&str,tokens:&[SpanToken],header:Span,base:usize,defaults:&mut Option<&mut dyn crate::ParameterDefaultSyntaxProvider>)->ParameterSignature{issue_tokens_with_defaults(source,tokens,header,base,defaults,FormalPathProfile::OriginalNativeObserved)}
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

#[cfg(test)]
mod native_parameter_observation_tests{
 use super::*;
 #[allow(dead_code)]
 struct PriorParameterSyntax{ordinal:usize,name:Span,declaration_cursor:Span,variadic:bool,type_components:Box<[Span]>,source_modifiers:u8,array_brackets:Box<[Span]>,expressions:Result<Option<Box<crate::ParameterExpressions>>,&'static str>}
 #[test]fn native_parameter_observation_uses_existing_entry_padding(){
  let prior=std::mem::size_of::<PriorParameterSyntax>();let current=std::mem::size_of::<ParameterSyntax>();
  eprintln!("NATIVE_PARAMETER_ENTRY_SIZE prior={prior} current={current}");assert_eq!(current,prior);
 }
 #[test]fn ordinary_parameter_parser_does_not_issue_native_child_observations(){
  let source="/proc/test(value=1)";let tokens=crate::lex(source).tokens.into_iter().map(|t|SpanToken{kind:t.kind,span:t.span}).collect::<Vec<_>>();
  let signature=parameter_signature_original_with_default_roots(source,&tokens,Span::new(0,source.len()),0,&mut None);
  let entry=&signature.entries().unwrap()[0];assert_eq!(entry.native_child_observation(),None);
  let mut copied=entry.clone();copied.native_children=9;assert_eq!(*entry,copied,"classification DATA must not alter semantic syntax equality");
  copied.expressions=Err("actual optional child admission failed");assert_eq!(copied.native_child_observation(),None);
 }
}

#[cfg(test)]
#[test]fn native_observed_parameter_settlement_does_not_invent_child_completion(){
 for (source,expected) in [("/proc/test(value)",Some((true,false,false))),("/proc/test(value=1)",None)]{
  let tokens=crate::lex(source).tokens.into_iter().map(|t|SpanToken{kind:t.kind,span:t.span}).collect::<Vec<_>>();
  let observed=parameter_signature_native_observed(source,&tokens,Span::new(0,source.len()),0,&mut None);
  assert_eq!(observed.entries().unwrap()[0].native_child_observation(),expected);
  let ordinary=issue_spans(source,&tokens,Span::new(0,source.len()),0);
  assert_eq!(ordinary.entries().unwrap()[0].native_child_observation(),None);
 }
}

#[cfg(test)]
#[test]fn accepted_variadic_production_never_borrows_nonexistent_named_clause_rows(){
 struct NamedRows;
 impl crate::ParameterDefaultSyntaxProvider for NamedRows{
  fn native_child_observation(&mut self,_:usize,_:Option<&crate::ParameterExpressions>)->Result<Option<(bool,bool,bool)>,&'static str>{panic!("ellipsis has no named child row")}
  fn default_root(&mut self,_:usize,_:Span,_:Span)->Result<crate::SettingExpression,&'static str>{Err("no named default row")}
 }
 let source="/proc/test(...)";let tokens=crate::lex(source).tokens.into_iter().map(|t|SpanToken{kind:t.kind,span:t.span}).collect::<Vec<_>>();
 let mut rows=NamedRows;let mut provider:Option<&mut dyn crate::ParameterDefaultSyntaxProvider>=Some(&mut rows);
 let original=parameter_signature_original_with_default_roots(source,&tokens,Span::new(0,source.len()),0,&mut provider);
 let entry=&original.entries().unwrap()[0];assert!(entry.variadic());assert_eq!(entry.native_child_observation(),None);
 let native=parameter_signature_native_observed(source,&tokens,Span::new(0,source.len()),0,&mut provider);
 assert!(native.entries().unwrap()[0].variadic());assert_eq!(native.entries().unwrap()[0].native_child_observation(),Some((true,false,false)));
 for bad in ["/proc/test(. . .)","/proc/test(...value)"]{
  let tokens=crate::lex(bad).tokens.into_iter().map(|t|SpanToken{kind:t.kind,span:t.span}).collect::<Vec<_>>();
  assert!(parameter_signature_original_with_default_roots(bad,&tokens,Span::new(0,bad.len()),0,&mut provider).entries().is_err());
 }
 let named="/proc/test(value=1)";let tokens=crate::lex(named).tokens.into_iter().map(|t|SpanToken{kind:t.kind,span:t.span}).collect::<Vec<_>>();
 let named_signature=parameter_signature_original_with_default_roots(named,&tokens,Span::new(0,named.len()),0,&mut provider);assert!(named_signature.entries().unwrap()[0].expressions().is_err(),"missing actual named/default clauses remain refused");
}

#[cfg(test)]mod original_observed_parameter_production_controls{
 use super::*;
 #[test]fn original_native_observation_records_only_actual_no_child_productions(){
  for source in["/proc/p(value)","/proc/p(...)"]{let tokens=crate::lex(source).tokens.into_iter().map(|token|SpanToken{kind:token.kind,span:token.span}).collect::<Vec<_>>();let legacy=parameter_signature_original_with_default_roots(source,&tokens,Span::new(0,source.len()),0,&mut None);let observed=parameter_signature_original_with_native_observation(source,&tokens,Span::new(0,source.len()),0,&mut None);let old=&legacy.entries().unwrap()[0];let new=&observed.entries().unwrap()[0];assert_eq!(old,new,"native metadata does not change parameter semantics");assert_eq!(old.native_child_observation(),None);assert_eq!(new.native_child_observation(),Some((true,false,false)));}
 }
 #[test]fn original_observed_constructor_cannot_lend_completion_to_compatibility_or_failed_children(){
  for source in["/proc/p(value=1)","/proc/p(value=(1+))"]{let tokens=crate::lex(source).tokens.into_iter().map(|token|SpanToken{kind:token.kind,span:token.span}).collect::<Vec<_>>();let observed=parameter_signature_original_with_native_observation(source,&tokens,Span::new(0,source.len()),0,&mut None);let entry=&observed.entries().unwrap()[0];assert_eq!(entry.native_child_observation(),None,"a real produced child loan remains required");if source.contains("1+"){assert!(entry.expressions().is_err())}}
 }
}

/// Resource DATA for the existing Original0290 producer with an authenticated
/// count of already-produced formal clauses. Every optional child must be a
/// SAME-admission root/input alias; other callers keep their old envelope.
/// This path allocates no source strings or child ASTs.
pub fn original_parameter_metadata_envelope(source:&str,tokens:TokenWindow<'_>,parameters:usize,a:&crate::SettingAdmission<'_>)->std::io::Result<usize>{
 use std::{io,mem::size_of};
 let overflow=||io::Error::new(io::ErrorKind::OutOfMemory,"parameter metadata geometry overflow");
 let poll=||a.checkpoint().map_err(|proxy|a.take_operational_error().unwrap_or(proxy));poll()?;
 let(mut identifiers,mut brackets,mut openings)=(0usize,0usize,0usize);
 for(index,token)in tokens.iter().enumerate(){
  if index%64==0{poll()?;}
  let spelling=source.get(token.span.range()).ok_or(io::ErrorKind::InvalidInput)?;
  if token.kind==TokenKind::Ident{identifiers=identifiers.checked_add(1).ok_or_else(overflow)?;}
  // SAME parameter producer spelling checks; conservative allocation DATA,
  // not a second delimiter grammar or a source/parameter receipt.
  if spelling=="["{brackets=brackets.checked_add(1).ok_or_else(overflow)?;}
  if matches!(spelling,"("|"["|"{"){openings=openings.checked_add(1).ok_or_else(overflow)?;}
 }
 let mul=|x:usize,y:usize|x.checked_mul(y).ok_or_else(overflow);
 let add=|x:usize,y:usize|x.checked_add(y).ok_or_else(overflow);
 // Native produced clauses omit the optional variadic marker, while this
 // syntax receipt retains it as one row. Reserve that one possible extra row.
 let parameters=parameters.checked_add(1).ok_or_else(overflow)?;
 // Four-slot envelopes cover the established Vec allocator/growth and old/new
 // Vec-to-box overlap. Per-row minimum capacities are named, not source bytes.
 let rows=mul(mul(parameters.max(4),4)?,size_of::<ParameterSyntax>())?;
 let minimum_spans=mul(parameters,4)?;
 let paths=mul(mul(add(identifiers,minimum_spans)?,4)?,size_of::<Span>())?;
 let suffixes=mul(mul(add(brackets,minimum_spans)?,4)?,size_of::<Span>())?;
 let dimensions=mul(mul(brackets,4)?,size_of::<Option<crate::SettingExpression>>())?;
 let expression_boxes=mul(parameters,size_of::<crate::ParameterExpressions>())?;
 // Outer header stack and one current suffix stack can coexist. Other suffix
 // scratch dies before the next formal is constructed. Original declares no
 // separate absolute-declaration Vec (those entries use the same formal rows).
 let delimiter_scratch=mul(mul(add(openings,4)?,8)?,size_of::<&str>())?;
 let mut bytes=crate::SharedParameterSignature::retention_envelope();
 for next in[rows,paths,suffixes,dimensions,expression_boxes,delimiter_scratch]{bytes=add(bytes,next)?;}
 poll()?;Ok(bytes)
}

#[cfg(test)]mod metadata_geometry_controls{
 use super::*;use std::sync::atomic::Ordering;
 #[test]fn parameter_geometry_counts_named_storage_not_opaque_source_bytes(){
  let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));
  let short="/proc/p(x=\"text\")";let long=format!("/proc/p(x=\"{}\")","x".repeat(128*1024));
  let bound=|s:&str,r|{let tokens=crate::lex_spans(s).tokens;original_parameter_metadata_envelope(s,TokenWindow::from_slice(&tokens),r,&a).unwrap()};
  assert_eq!(bound(short,1),bound(&long,1));assert!(bound(&long,1)<16384);
  assert!(bound("/proc/p(datum/a/x[1][2],datum/b/y,...)",3)>bound(short,1));
  assert_eq!(counter.load(Ordering::Acquire),fixed);
 }
 #[test]fn parameter_geometry_overflow_first_io_and_cancel_preserve_exact_failure(){
  let tokens=crate::lex_spans("/proc/p(x)").tokens;let fixed=crate::SettingChargeCounter::root_allocation_bytes();let counter=crate::SettingChargeCounter::try_new(fixed).unwrap();
  let a=crate::SettingAdmission::new(&counter,1<<20,&||Ok(()));assert_eq!(original_parameter_metadata_envelope("/proc/p(x)",TokenWindow::from_slice(&tokens),usize::MAX,&a).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);
  let fail=||Err(std::io::Error::from_raw_os_error(1450));let a=crate::SettingAdmission::new(&counter,1<<20,&fail);assert_eq!(original_parameter_metadata_envelope("/proc/p(x)",TokenWindow::from_slice(&tokens),1,&a).unwrap_err().raw_os_error(),Some(1450));
  let cancel=||Err(std::io::Error::new(std::io::ErrorKind::Interrupted,"actual metadata cancellation"));let a=crate::SettingAdmission::new(&counter,1<<20,&cancel);let error=original_parameter_metadata_envelope("/proc/p(x)",TokenWindow::from_slice(&tokens),1,&a).unwrap_err();assert_eq!(error.kind(),std::io::ErrorKind::Interrupted);assert_eq!(error.to_string(),"actual metadata cancellation");assert_eq!(counter.load(Ordering::Acquire),fixed);
 }
}

#[cfg(test)]mod original_trailing_parameter_path_controls{
 use super::*;
 #[test]fn actual_original_terminal_parameter_slash_keeps_last_identifier_type_and_following_cursor(){
  for source in["/proc/p(obj/instance/)","/proc/p(obj/instance/ /* actual trivia */)","/proc/p(/obj/instance/,datum/other/)"]{
   let tokens=crate::lex_spans(source).tokens;let header=Span::new(0,source.len());
   let ordinary=parameter_signature_original_with_default_roots(source,&tokens,header,0,&mut None);
   let observed=parameter_signature_original_with_native_observation(source,&tokens,header,0,&mut None);
   let rows=ordinary.entries().unwrap();let native=observed.entries().unwrap();assert_eq!(rows,native,"observed metadata never changes parameter semantics");
   assert_eq!(&source[rows[0].name().range()],"instance");assert_eq!(rows[0].type_path(source).unwrap().as_deref(),Some("/obj"));assert!(!rows[0].variadic());assert!(rows[0].array_brackets().is_empty());assert_eq!(rows[0].expressions(),Ok(None));
   let following=source.find(',').unwrap_or_else(||source.rfind(')').unwrap());assert_eq!(rows[0].declaration_cursor(),Span::new(following,following+1));
   if rows.len()==2{assert_eq!(&source[rows[1].name().range()],"other");assert_eq!(rows[1].type_path(source).unwrap().as_deref(),Some("/datum"));}
  }
 }
 #[test]fn actual_original_terminal_parameter_slash_refuses_forged_occurrences_and_keeps_native_scope(){
  let source="/proc/p(obj/instance/)";let tokens=crate::lex_spans(source).tokens;let header=Span::new(0,source.len());let slash=source.rfind('/').unwrap();let index=tokens.iter().position(|t|t.span==Span::new(slash,slash+1)).unwrap();
  assert_eq!(tokens[index].kind,TokenKind::Punctuation);
  for mutation in 0..3{let mut changed=tokens.clone();match mutation{0=>changed[index].kind=TokenKind::Operator,1=>changed[index].span.end+=1,_=>{changed[index].span.start+=1000;changed[index].span.end+=1000;}}assert!(parameter_signature_original_with_default_roots(source,&changed,header,0,&mut None).entries().is_err(),"forged terminal slash {mutation}");}
  assert!(issue_spans(source,&tokens,header,0).entries().is_err(),"this actual Original-only receipt does not grant Native compatibility grammar");
  assert!(parameter_signature_original_with_default_roots(source,&tokens,header,usize::MAX,&mut None).entries().is_err(),"original coordinate overflow remains refused");
  for source in["/proc/p(/)","/proc/p(obj/instance/+)"]{let tokens=crate::lex_spans(source).tokens;assert!(parameter_signature_original_with_default_roots(source,&tokens,Span::new(0,source.len()),0,&mut None).entries().is_err(),"no identifier/unfinished nonterminal path cannot borrow this receipt");}
 }
}
