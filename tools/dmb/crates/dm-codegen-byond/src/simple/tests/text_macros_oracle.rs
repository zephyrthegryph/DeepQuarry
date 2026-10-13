//! Text macros and escapes against DreamMaker 516.1687 output. Each source
//! string in `fixtures/native_compiler/text_macros/probe.dm` ends with `|Q<n>`;
//! the compiled template of that string in `probe.native.bin` is the oracle.
use super::*;

fn oracle() -> Vec<(String, Vec<u8>)> {
    let source = include_str!("../../../../../fixtures/native_compiler/text_macros/probe.dm");
    let dmb = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
        "../../../../../fixtures/native_compiler/text_macros/probe.native.bin"
    ))
    .unwrap();
    let mut pairs = Vec::new();
    for line in source.lines() {
        let Some(literal) = line.trim().strip_prefix("s = \"") else {
            continue;
        };
        let literal = literal.strip_suffix('"').unwrap();
        let tag = literal[literal.rfind("|Q").unwrap()..].as_bytes().to_vec();
        let matches: Vec<_> = dmb
            .strings
            .iter()
            .filter(|string| string.data.ends_with(&tag))
            .collect();
        assert_eq!(matches.len(), 1, "one compiled string for {literal}");
        pairs.push((literal.to_owned(), matches[0].data.clone()));
    }
    assert!(pairs.len() > 250);
    pairs
}

#[test]
fn text_macros_and_escapes_match_dreammaker_templates() {
    let mut failures = Vec::new();
    for (literal, expected) in oracle() {
        match parse_interpolated_string(&literal) {
            Ok((actual, _)) if actual == expected => {}
            Ok((actual, _)) => failures.push(format!(
                "{literal:?}: expected {expected:02x?} got {actual:02x?}"
            )),
            Err(error) => failures.push(format!("{literal:?}: rejected: {error}")),
        }
    }
    assert!(failures.is_empty(), "{} mismatches:\n{}", failures.len(), failures.join("\n"));
}

#[test]
fn text_macros_rejected_by_dreammaker_are_rejected() {
    // Each is a DreamMaker 516.1687 compile error in this position.
    for literal in [
        r"\r",
        r"a\redb",
        r"\h",
        r"\e",
        r"\N",
        r"\T",
        r"\S",
        r"\Him",
        r"\Himself",
        r"\Herself",
        r"\it",
        r"\its",
        r"\itself",
        r"\strike",
        r"\big",
        r"\center",
        r"\.",
        r"[1]\The",
        r"[1]\a",
        r"[1]\an",
        r"[1]\A",
        r"[1]\An",
        r"\he",
        r"\s",
        r"x\proper",
    ] {
        assert!(
            parse_interpolated_string(literal).is_err(),
            "{literal:?} must be rejected like DreamMaker"
        );
    }
}
