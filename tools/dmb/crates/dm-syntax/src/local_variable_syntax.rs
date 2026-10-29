//! Native primary local-declaration fact. Invoked by the EXISTING body grammar
//! on its already tokenized path fragment; never a checker parser or source scan.
//! Pinned grammar provenance: SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc,
//! parser.rs simple_statement; ast.rs VarTypeBuilder::from_iter (GPL-3.0).
use crate::{Span, SpanToken, TokenKind};

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
}
impl LocalVariableLedger {
    pub fn entries(&self) -> Result<&[LocalVariableSyntax], &'static str> {
        if let Some(reason) = self.refusal {
            Err(reason)
        } else {
            Ok(&self.entries)
        }
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
}
impl LocalVariableSyntax {
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
fn source_modifier(name: &str) -> Option<u8> {
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
    })
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
