use super::*;

fn identity() -> ProcedureIdentity {
    ProcedureIdentity {
        owner: dm_ir::SymbolId::of("/"),
        name: dm_ir::SymbolId::of("work"),
        verb: false,
        occurrence: 0,
    }
}

#[test]
fn rejects_lexical_false_positives_without_rejecting_real_qualifiers() {
    let negatives = [
        "return static_count + constant + globalized",
        "// var/static/value = 1\nreturn 1",
        "/* var/const/value = 1 /* global */ */\nreturn 1",
        "return \"static const global\"",
        "return 'icons/static-global.dmi'",
        "return \"escaped \\\" static\"",
        "return {\"multiline\nvar/static/value = 1\n\"}",
        "return @\"static const global\"",
    ];
    for source in negatives {
        assert!(source.contains("static") || source.contains("const") || source.contains("global"));
        assert!(!may_contain_stored_declarations(source), "{source:?}");
    }
    for qualifier in ["static", "const", "global"] {
        assert!(may_contain_stored_declarations(&format!(
            "var/{qualifier}/value = 1"
        )));
    }
}

#[test]
fn malformed_or_unknown_lexical_candidates_keep_capture_admission() {
    for source in [
        "return \"static",
        "/* const",
        "return 'global",
        "return $constant",
    ] {
        assert!(may_contain_stored_declarations(source), "{source:?}");
    }
}

#[test]
fn filtered_capture_matches_full_capture_of_expanded_valid_bodies() {
    // Input is already expanded: the final declaration models a macro whose
    // replacement emitted an ordinary stored declaration.
    for body in [
        "    var/static/value = 1\n    return value\n",
        "    var/const/value = 1\n    return value\n",
        "    var/global/value = 1\n    return value\n",
        "    var/static/list/value = list(\"escaped \\\" const\")\n    return value\n",
        "    var/static/value = {\"first\nsecond\"}\n    return value\n",
        "    /* static distraction */\n    var/const/expanded_name = 3\n    return expanded_name\n",
        "    return \"static\"\n",
        "    // var/static/value = 1\n    return constant_name\n",
    ] {
        let source = format!("/proc/work()\n{body}");
        let parsed = dm_syntax::parse(&source);
        assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
        let full = capture_declarations(identity(), &parsed.items[0].children).unwrap();
        let filtered = if may_contain_stored_declarations(body) {
            capture_declarations(identity(), &parsed.items[0].children).unwrap()
        } else {
            capture_declarations(identity(), &[]).unwrap()
        };
        assert_eq!(filtered.declarations, full.declarations, "{source}");
        assert_eq!(filtered.origins, full.origins, "{source}");
        assert_eq!(
            filtered.symbols.ordered(),
            full.symbols.ordered(),
            "{source}"
        );
    }
}
