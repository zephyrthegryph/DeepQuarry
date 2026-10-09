//! Independent captured VM values through the current shared preprocess pipeline.
use std::{collections::BTreeMap, path::Path};
#[test]
fn literal_continuations_match_captured_byond_globals() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../fixtures/native_compiler/line_continuation_strings");
    let plan = dm_preprocess::regions::plan_regions(
        &root.join("probe.dme"),
        &dm_preprocess::FileSystem,
        &BTreeMap::new(),
    );
    assert!(plan.diagnostics.is_empty(), "{:?}", plan.diagnostics);
    let expanded = dm_preprocess::regions::expand_regions(&plan, 1);
    assert!(
        expanded.diagnostics.is_empty(),
        "{:?}",
        expanded.diagnostics
    );
    let reference = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../fixtures/native_compiler/line_continuation_strings/probe.native.bin"
    ))
    .unwrap();
    let mut actual = BTreeMap::new();
    let text = expanded.text.as_str();
    let mut end = 0;
    for token in dm_syntax::lex_spans(text).tokens {
        if token.kind != dm_syntax::TokenKind::String {
            continue;
        }
        let prefix = &text[end..token.span.start];
        let name = prefix
            .split("var/")
            .last()
            .unwrap()
            .split('=')
            .next()
            .unwrap()
            .trim();
        let value = dm_codegen_byond::decode_constant_string_literal(token.text(text))
            .unwrap()
            .unwrap();
        actual.insert(name.to_owned(), value);
        end = token.span.end;
    }
    for name in ["quoted", "adjacent", "macro", "block"] {
        let variable = reference
            .variables
            .iter()
            .find(|v| reference.string(v.name) == Some(name.as_bytes()))
            .unwrap();
        assert_eq!(variable.kind, 6);
        assert_eq!(
            actual[name],
            reference.string(variable.value).unwrap(),
            "{name}"
        );
    }
}

#[test]
fn captured_raw_quoted_newline_is_a_source_error() {
    let source =
        include_str!("../../../fixtures/native_compiler/line_continuation_strings/raw_newline.dm");
    assert!(!dm_syntax::lex_spans(source).diagnostics.is_empty());
    // The restriction belongs to quoted text, not raw block strings.
    assert!(dm_syntax::lex_spans("@{\"left\nright\"}")
        .diagnostics
        .is_empty());
}
