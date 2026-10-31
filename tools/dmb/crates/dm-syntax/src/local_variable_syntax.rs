//! Native primary local-declaration fact. Invoked by the EXISTING body grammar
//! on its already tokenized path fragment; never a checker parser or source scan.
//! Pinned grammar provenance: SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc,
//! parser.rs simple_statement; ast.rs VarTypeBuilder::from_iter (GPL-3.0).
use crate::{Expr, Span, SpanToken, TokenKind};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LocalSourceKind {
    Statement,
    CommaContinuation,
    ForInitializer,
    ForBinding,
    CatchBinding,
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct LocalVariableLedger {
    entries: Vec<LocalVariableSyntax>,
    refusal: Option<&'static str>,
    source_ordered: bool,
}
impl LocalVariableLedger {
    pub(crate) fn drop_dimension_expressions(self,mut drop:impl FnMut(Expr)){
        for mut entry in self.entries{if let Some(array)=entry.array_syntax.take(){for expression in array.root.dimensions.into_vec(){drop(expression);}}}
    }

    pub fn entries(&self) -> Result<&[LocalVariableSyntax], &'static str> {
        if let Some(reason) = self.refusal {
            Err(reason)
        } else {
            Ok(&self.entries)
        }
    }
    /// Grammar-issued rows are monotonically ordered by original name point.
    /// Borrow a header subrange without building a second lookup table.
    pub fn in_span(&self, span: Span) -> Result<&[LocalVariableSyntax], &'static str> {
        if !self.source_ordered {
            return Err("native local ledger source order was not finalized");
        }
        let entries = self.entries()?;
        let start = entries.partition_point(|f| f.name.start < span.start);
        let end = start + entries[start..].partition_point(|f| f.name.start < span.end);
        Ok(&entries[start..end])
    }
    pub(crate) fn finish_source_order(&mut self) {
        // Catch facts are issued before their preceding try body is parsed.
        // Finalize the SAME owner once, before any body receipt is published.
        self.entries.sort_unstable_by_key(|f| f.name.start);
        if self
            .entries
            .windows(2)
            .any(|pair| pair[0].name.start == pair[1].name.start)
        {
            self.decline("native local declarations have duplicate original points");
        }
        self.source_ordered = true;
    }
    pub fn storage(&self) -> &Vec<LocalVariableSyntax> {
        &self.entries
    }
    pub(crate) fn decline(&mut self, reason: &'static str) {
        self.refusal.get_or_insert(reason);
    }
    pub(crate) fn issue(
        &mut self,
        source: &str,
        tokens: &[SpanToken],
        first: bool,
        base: usize,
        kind: LocalSourceKind,
        preceding_comma: Option<Span>,
    ) {
        let result = issue_local_variable(source, tokens, first).and_then(|mut fact| {
            if kind == LocalSourceKind::CommaContinuation {
                fact.anchor =
                    preceding_comma.ok_or("native preceding comma token was not issued")?;
            } else if preceding_comma.is_some() {
                return Err("unexpected comma origin for first declaration");
            }
            fn shift(span: &mut Span, base: usize) -> Result<(), &'static str> {
                span.start = span
                    .start
                    .checked_add(base)
                    .ok_or("local primary point overflow")?;
                span.end = span
                    .end
                    .checked_add(base)
                    .ok_or("local primary point overflow")?;
                Ok(())
            }
            shift(&mut fact.anchor, base)?;
            shift(&mut fact.name, base)?;
            for span in fact.type_components.iter_mut() {
                shift(span, base)?;
            }
            if let Some(array) = &mut fact.array_syntax {
                let initializer = &mut array.root;
                for dimension in initializer.dimensions.iter_mut() {
                    crate::shift_expression(dimension, base);
                }
                for bracket in initializer.brackets.iter_mut() {
                    shift(bracket, base)?;
                }
            }
            if kind == LocalSourceKind::CatchBinding && fact.array_suffix {
                return Err("catch parameter tree-path grammar does not admit array suffix");
            }
            if kind == LocalSourceKind::ForBinding && fact.implicit_list_initializer().is_some() {
                return Err("nonempty array initializer is not an old for-in/all binding");
            }
            fact.source_kind = kind;
            Ok(fact)
        });
        match result {
            Ok(fact) => self.entries.push(fact),
            Err(reason) => self.decline(reason),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalVariableSyntax {
    pub source_kind: LocalSourceKind,
    /// Exact token used by the pinned simple_statement error producer. For the
    /// first item this is `var`, for comma continuations it is the actual preceding comma token.
    pub anchor: Span,
    pub name: Span,
    /// Original primary component spans AFTER leading source modifiers. No
    /// strings/model are copied; downstream symbolic projection borrows source.
    pub type_components: Box<[Span]>,
    /// Source grammar bits, NOT runtime DeclarationMeaning.flags encoding.
    pub source_modifiers: u8,
    pub array_suffix: bool,
    pub array_syntax: Option<LocalArraySyntax>,
}
/// The pinned primary grammar synthesizes a constructor, not a written `new`
/// expression. Only this suffix producer issues this origin; an unissued source
/// cursor never falls back to an unknown position.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ImplicitListOrigin {
    ParserSynthetic,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct LocalArraySyntax {
    /// Runtime compilation may still need original dimension effects even
    /// when the old checker skips its synthetic initializer under explicit '='.
    pub root: ImplicitListInitializer,
    pub explicit_initializer: bool,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ImplicitListInitializer {
    pub origin: ImplicitListOrigin,
    pub brackets: Box<[Span]>,
    /// None is an actual empty suffix; Some indexes the single owned Expr root.
    pub dimension_slots: Box<[Option<usize>]>,
    pub dimensions: Box<[Expr]>,
}
impl LocalVariableSyntax {
    pub fn implicit_list_initializer(&self) -> Option<&ImplicitListInitializer> {
        self.array_syntax
            .as_ref()
            .filter(|array| !array.explicit_initializer && !array.root.dimensions.is_empty())
            .map(|array| &array.root)
    }
    /// Project already-issued component spans; no lexing/splitting or inference.
    pub fn type_path(&self, source: &str) -> Result<Option<String>, &'static str> {
        let mut path = if self.array_suffix {
            String::from("/list")
        } else {
            String::new()
        };
        for component in &self.type_components {
            path.push('/');
            path.push_str(
                source
                    .get(component.range())
                    .ok_or("native local component source unavailable")?,
            );
        }
        Ok((!path.is_empty()).then_some(path))
    }
}
pub(crate) fn source_modifier(name: &str) -> Option<u8> {
    Some(match name {
        "static" | "global" => 1,
        "const" => 4,
        "tmp" => 8,
        "final" | "SpacemanDMM_final" => 16,
        "SpacemanDMM_private" => 32,
        "SpacemanDMM_protected" => 64,
        _ => return None,
    })
}
/// `first` is issued by native simple-statement grammar, not inferred by policy.
/// The passed token slice contains ONE already parsed declaration path plus
/// optional suffix/initializer. Its spans refer to `source`, before normalization.
pub(crate) fn issue_local_variable(
    source: &str,
    tokens: &[SpanToken],
    first: bool,
) -> Result<LocalVariableSyntax, &'static str> {
    let original_tokens = tokens;
    let significant = tokens.iter().filter(|token| {
        !matches!(
            token.kind,
            TokenKind::Whitespace | TokenKind::Comment | TokenKind::Newline
        )
    });
    let mut tokens = significant.peekable();
    let anchor = tokens.peek().ok_or("native local path is empty")?.span;
    if first {
        let keyword = tokens.next().unwrap();
        if keyword.kind != TokenKind::Ident || keyword.text(source) != "var" {
            return Err("native local keyword was not issued");
        }
    }
    let mut path = Vec::new();
    let mut need_ident = true;
    let mut initial = true;
    let mut array_suffix = false;
    while let Some(token) = tokens.next() {
        let text = source
            .get(token.span.range())
            .ok_or("native local token span unavailable")?;
        if text == "/" && (initial || !need_ident) {
            need_ident = true;
            initial = false;
            continue;
        }
        if token.kind == TokenKind::Ident && need_ident {
            path.push(token.span);
            need_ident = false;
            initial = false;
            continue;
        }
        if !need_ident && matches!(text, "=" | "[" | ";" | "," | ")") {
            array_suffix = text == "[";
            break;
        }
        if !need_ident && token.kind == TokenKind::Ident && matches!(text, "as" | "in") {
            break;
        }
        return Err("native local path/suffix grammar was not issued");
    }
    if need_ident {
        return Err("native local path is incomplete");
    }
    let name = path.pop().ok_or("native local name unavailable")?;
    let mut modifiers = 0;
    let mut prefix = 0;
    while let Some(component) = path.get(prefix) {
        let name = source
            .get(component.range())
            .ok_or("native local modifier span unavailable")?;
        let Some(flag) = source_modifier(name) else {
            break;
        };
        modifiers |= flag;
        prefix += 1;
    }
    Ok(LocalVariableSyntax {
        source_kind: LocalSourceKind::Statement,
        anchor,
        name,
        type_components: path[prefix..].into(),
        source_modifiers: modifiers,
        array_suffix,
        array_syntax: issue_array_initializer(source, original_tokens, name)?,
    })
}

/// Assignment delimiter in the existing primary declaration grammar. Nested
/// assignments inside a dimension are expressions, never the local initializer.
pub(crate) fn top_level_local_assignment(source: &str) -> Option<usize> {
    let mut nesting = 0usize;
    for token in crate::lex_spans(source).tokens {
        match token.text(source) {
            "[" | "(" | "{" => nesting += 1,
            "]" | ")" | "}" => nesting = nesting.saturating_sub(1),
            "=" if nesting == 0 => return Some(token.span.start),
            _ => (),
        }
    }
    None
}

fn issue_array_initializer(
    source: &str,
    tokens: &[SpanToken],
    name: Span,
) -> Result<Option<LocalArraySyntax>, &'static str> {
    let sig: Vec<usize> = tokens
        .iter()
        .enumerate()
        .filter_map(|(i, t)| {
            (!matches!(
                t.kind,
                TokenKind::Whitespace | TokenKind::Comment | TokenKind::Newline
            ) && t.span.start >= name.end)
                .then_some(i)
        })
        .collect();
    let mut i = 0;
    let mut brackets = Vec::new();
    let mut dimensions = Vec::new();
    let mut dimension_slots = Vec::new();
    while i < sig.len() && tokens[sig[i]].text(source) == "[" {
        let open = tokens[sig[i]].span;
        let begin = sig[i] + 1;
        let mut stack = vec!["]"];
        i += 1;
        while i < sig.len() && !stack.is_empty() {
            match tokens[sig[i]].text(source) {
                "[" => stack.push("]"),
                "(" => stack.push(")"),
                "{" => stack.push("}"),
                close @ ("]" | ")" | "}") => {
                    if stack.pop() != Some(close) {
                        return Err("array dimension delimiter mismatch");
                    }
                }
                _ => (),
            }
            if !stack.is_empty() {
                i += 1;
            }
        }
        if i >= sig.len() || !stack.is_empty() {
            return Err("array dimension closing token unavailable");
        }
        let end = sig[i];
        brackets.push(Span::new(open.start, tokens[end].span.end));
        if tokens[begin..end].iter().any(|t| {
            !matches!(
                t.kind,
                TokenKind::Whitespace | TokenKind::Comment | TokenKind::Newline
            )
        }) {
            let parsed =
                crate::expression_parser::parse_expression_span_tokens(source, &tokens[begin..end]);
            if !parsed.diagnostics.is_empty() {
                return Err("array dimension primary expression unsupported");
            }
            dimension_slots.push(Some(dimensions.len()));
            dimensions.push(
                parsed
                    .expr
                    .ok_or("array dimension primary expression missing")?,
            );
        } else {
            dimension_slots.push(None);
        }
        i += 1;
    }
    // Preserve original roots for native runtime lowering. The checker borrows
    // them only when no explicitly written initializer replaces its constructor.
    if brackets.is_empty() {
        return Ok(None);
    }
    if sig
        .get(i)
        .is_some_and(|&n| !matches!(tokens[n].text(source), "=" | "as" | "in" | ";" | ")" | ","))
    {
        return Err("array suffix has an unsupported trailing primary token");
    }
    Ok(Some(LocalArraySyntax {
        explicit_initializer: sig.get(i).is_some_and(|&n| tokens[n].text(source) == "="),
        root: ImplicitListInitializer {
            origin: ImplicitListOrigin::ParserSynthetic,
            brackets: brackets.into(),
            dimension_slots: dimension_slots.into(),
            dimensions: dimensions.into(),
        },
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn issue(source: &str, first: bool) -> LocalVariableSyntax {
        let lexed = crate::lex_spans(source);
        assert!(lexed.diagnostics.is_empty());
        issue_local_variable(source, &lexed.tokens, first).unwrap()
    }
    #[test]
    fn leading_modifiers_only_and_variable_name_is_not_a_modifier() {
        let source = "var/SpacemanDMM_private/datum/SpacemanDMM_protected/value";
        let fact = issue(source, true);
        assert_eq!(fact.source_modifiers, 32);
        assert_eq!(
            fact.type_components
                .iter()
                .map(|span| &source[span.range()])
                .collect::<Vec<_>>(),
            ["datum", "SpacemanDMM_protected"]
        );
        assert_eq!(issue("var/SpacemanDMM_private", true).source_modifiers, 0);
    }
    #[test]
    fn comma_parts_have_fresh_prefix_and_authentic_anchor() {
        assert_eq!(
            issue("var/SpacemanDMM_private/a", true).source_modifiers,
            32
        );
        assert_eq!(issue("b", false).source_modifiers, 0);
        let source = " /SpacemanDMM_private/y";
        let fact = issue(source, false);
        assert_eq!(fact.source_modifiers, 32);
        assert_eq!(fact.anchor, Span::new(1, 2));
        assert_eq!(fact.type_components.len(), 0);
    }
    #[test]
    fn arrays_and_initializer_text_do_not_change_source_modifiers() {
        let source =
            "var/SpacemanDMM_private/SpacemanDMM_protected/list/value[2] = list(\"final\")";
        let fact = issue(source, true);
        assert_eq!(fact.source_modifiers, 96);
        assert!(fact.array_suffix);
        assert_eq!(fact.anchor, Span::new(0, 3));
        assert_eq!(
            fact.type_components
                .iter()
                .map(|span| &source[span.range()])
                .collect::<Vec<_>>(),
            ["list"]
        );
    }
    #[test]
    fn unknown_tokens_decline_instead_of_inventing_a_clean_modifier_fact() {
        for source in ["var//x", "var/\\/x", "var/x.y", "var/"] {
            let lexed = crate::lex_spans(source);
            assert!(
                issue_local_variable(source, &lexed.tokens, true).is_err(),
                "{source:?}"
            );
        }
    }
    fn body(source: &str) -> crate::ParsedBody {
        let parsed = crate::parse(source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        crate::parse_proc_body(&parsed.items[0])
    }
    #[test]
    fn actual_primary_grammar_records_unreachable_and_for_locals_but_not_catch_warning() {
        let source="/proc/probe()\n    var/SpacemanDMM_private/a=1\n    if(0)\n        var/SpacemanDMM_protected/b\n    for(var/SpacemanDMM_private/x=1; x<2; x++)\n        continue\n    for(var/SpacemanDMM_protected/y in list(1))\n        continue\n    try\n        throw 1\n    catch(var/SpacemanDMM_private/e)\n        return\n";
        let parsed = body(source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let facts = parsed.local_variables.entries().unwrap();
        assert_eq!(
            facts
                .iter()
                .map(|fact| fact.source_modifiers)
                .collect::<Vec<_>>(),
            [32, 64, 32, 64, 32]
        );
        let lines = facts
            .iter()
            .map(|fact| {
                source.as_bytes()[..fact.anchor.start]
                    .iter()
                    .filter(|&&byte| byte == b'\n')
                    .count()
                    + 1
            })
            .collect::<Vec<_>>();
        assert_eq!(lines, [2, 4, 5, 7, 11]);
        assert_eq!(
            facts
                .iter()
                .map(|fact| fact.source_kind)
                .collect::<Vec<_>>(),
            [
                LocalSourceKind::Statement,
                LocalSourceKind::Statement,
                LocalSourceKind::ForInitializer,
                LocalSourceKind::ForBinding,
                LocalSourceKind::CatchBinding
            ]
        );
    }
    #[test]
    fn actual_comma_declarations_preserve_written_path_and_flags_zero_proof() {
        let source="/proc/probe()\n    var/SpacemanDMM_private/a, b\n    var/SpacemanDMM_private/SpacemanDMM_protected/both\n";
        let parsed = body(source);
        assert!(parsed.diagnostics.is_empty());
        let facts = parsed.local_variables.entries().unwrap();
        assert_eq!(
            facts
                .iter()
                .map(|fact| fact.source_modifiers)
                .collect::<Vec<_>>(),
            [32, 0, 96]
        );
        assert_eq!(
            facts
                .iter()
                .map(|fact| &source[fact.name.range()])
                .collect::<Vec<_>>(),
            ["a", "b", "both"]
        );
        assert_eq!(facts[1].source_kind, LocalSourceKind::CommaContinuation);
        assert!(facts[1].type_components.is_empty());
    }
    #[test]
    fn native_only_local_block_is_explicitly_outside_pinned_checker_domain() {
        let parsed = body("/proc/probe()\n    var/SpacemanDMM_private\n        a\n        b\n");
        assert!(
            parsed.diagnostics.is_empty(),
            "do not change runtime compiler admission"
        );
        assert!(
            parsed.local_variables.entries().is_err(),
            "the reference parser rejects this source instead of emitting two warnings"
        );
    }
    #[test]
    fn no_local_body_retains_no_local_fact_allocation() {
        let parsed = body("/proc/probe()\n    return 1\n");
        assert_eq!(parsed.local_variables.storage().capacity(), 0);
        assert!(parsed.local_variables.entries().unwrap().is_empty());
    }
    #[test]
    fn actual_comma_warning_anchors_are_the_consumed_separator_not_next_slash() {
        let source="/proc/probe()\n    var/plain, /SpacemanDMM_private/second, /SpacemanDMM_protected/third\n";
        let parsed = body(source);
        assert!(parsed.diagnostics.is_empty());
        let facts = parsed.local_variables.entries().unwrap();
        assert_eq!(
            facts.iter().map(|f| f.source_modifiers).collect::<Vec<_>>(),
            [0, 32, 64]
        );
        assert_eq!(&source[facts[1].anchor.range()], ",");
        assert_eq!(&source[facts[2].anchor.range()], ",");
        let line = source.find('\n').unwrap() + 1;
        assert_eq!(
            (
                facts[1].anchor.start - line + 1,
                facts[2].anchor.start - line + 1
            ),
            (14, 43)
        );
    }

    #[test]
    fn reconstructed_item_must_reissue_local_facts_from_current_header_not_flags() {
        let source = "/proc/probe()\n    var/plain\n    var/SpacemanDMM_private/datum/second\n";
        let original = crate::parse(source);
        let expected = crate::parse_proc_body(&original.items[0]);
        let mut reconstructed = original.items[0].clone();
        for child in &mut reconstructed.children {
            child.checker_qualifiers = 255;
            child.declaration_cursor = None;
        }
        let actual = crate::parse_proc_body(&reconstructed);
        assert_eq!(
            actual.local_variables.entries().unwrap(),
            expected.local_variables.entries().unwrap()
        );
        assert_eq!(
            actual
                .local_variables
                .entries()
                .unwrap()
                .iter()
                .map(|f| f.source_modifiers)
                .collect::<Vec<_>>(),
            [0, 32]
        );
        reconstructed.children[0].header = "var/SpacemanDMM_protected/plain".into();
        let changed = crate::parse_proc_body(&reconstructed);
        assert_eq!(
            changed.local_variables.entries().unwrap()[0].source_modifiers,
            64,
            "current primary grammar reissues metadata; no decoded/cached flags certify it"
        );
    }
}

#[cfg(test)]
mod array_tests {
    use super::*;
    fn body(source: &str) -> crate::ParsedBody {
        let parsed = crate::parse(source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let body = crate::parse_proc_body(&parsed.items[0]);
        assert!(body.diagnostics.is_empty(), "{:?}", body.diagnostics);
        body
    }
    #[test]
    fn native_suffix_owns_real_dimension_roots_once_and_keeps_synthetic_constructor_origin() {
        let source = "/proc/probe()\n    var/datum/value[first()][][second(1)]\n";
        let parsed = body(source);
        let fact = &parsed.local_variables.entries().unwrap()[0];
        assert_eq!(
            fact.type_path(source).unwrap().as_deref(),
            Some("/list/datum")
        );
        let init = fact.implicit_list_initializer().unwrap();
        assert_eq!(init.origin, ImplicitListOrigin::ParserSynthetic);
        assert_eq!(init.brackets.len(), 3);
        assert_eq!(init.dimensions.len(), 2);
        assert_eq!(&source[init.dimensions[0].span.range()], "first()");
        assert_eq!(&source[init.dimensions[1].span.range()], "second(1)");
        assert!(
            matches!(
                &parsed.statements[0].kind,
                crate::StatementKind::Var { value: None, .. }
            ),
            "implicit constructor is a dedicated root, never a fabricated written-new Expr"
        );
    }
    #[test]
    fn explicit_initializer_drops_dimensions_while_empty_suffix_has_no_constructor() {
        for source in [
            "/proc/p()\n    var/x[ignored()] = kept()\n",
            "/proc/p()\n    var/x[][]\n",
        ] {
            let parsed = body(source);
            let fact = &parsed.local_variables.entries().unwrap()[0];
            assert!(fact.array_suffix);
            assert!(fact.implicit_list_initializer().is_none());
        }
    }
    #[test]
    fn named_assignment_inside_dimension_is_not_a_written_local_initializer() {
        let source = "/proc/p()\n    var/x[n=missing()]\n";
        let parsed = body(source);
        let fact = &parsed.local_variables.entries().unwrap()[0];
        assert!(fact.implicit_list_initializer().is_some());
        assert!(matches!(
            &parsed.statements[0].kind,
            crate::StatementKind::Var { value: None, .. }
        ));
        assert_eq!(
            top_level_local_assignment("var/x[n=missing()] = kept()"),
            Some(19)
        );
    }
    #[test]
    fn initializer_dimensions_reissue_current_points_after_prefix_shift() {
        let old = "/proc/p()\n    var/x[first()][][second()]\n";
        let prefix = "// shifted original input\n";
        let shifted = format!("{prefix}{old}");
        let one = body(old);
        let two = body(&shifted);
        let a = one.local_variables.entries().unwrap()[0]
            .implicit_list_initializer()
            .unwrap();
        let b = two.local_variables.entries().unwrap()[0]
            .implicit_list_initializer()
            .unwrap();
        for (left, right) in a.dimensions.iter().zip(b.dimensions.iter()) {
            assert_eq!(right.span.start, left.span.start + prefix.len());
            assert_eq!(&old[left.span.range()], &shifted[right.span.range()]);
        }
        for (left, right) in a.brackets.iter().zip(b.brackets.iter()) {
            assert_eq!(right.start, left.start + prefix.len());
        }
    }
    #[test]
    fn nonempty_for_binding_refuses_old_parse_shape_but_empty_suffix_is_a_real_binding() {
        let nonempty = body("/proc/p()\n    for(var/x[missing()] in list())\n        return\n");
        assert_eq!(
            nonempty.local_variables.entries().unwrap_err(),
            "nonempty array initializer is not an old for-in/all binding"
        );
        let empty = body("/proc/p()\n    for(var/x[] in list())\n        return\n");
        assert!(empty.local_variables.entries().unwrap()[0].array_suffix);
    }
}
