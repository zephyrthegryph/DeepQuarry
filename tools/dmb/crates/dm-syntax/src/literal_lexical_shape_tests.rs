use super::*;

fn shape(raw: &str) -> LiteralLexicalShape {
    let parsed = crate::parse_expression(raw);
    assert!(parsed.diagnostics.is_empty(), "{:?}", parsed.diagnostics);
    let crate::ExprKind::Literal(text) = parsed.expr.unwrap().kind else {
        panic!("expected issued literal");
    };
    text.parts().unwrap().unwrap().lexical.unwrap()
}

#[test]
fn interpolation_is_a_lexical_fact_even_without_expression_nodes() {
    for raw in [r#""[]""#, r#""[ ]""#, r#""[a]""#] {
        assert_eq!(
            shape(raw),
            LiteralLexicalShape {
                interpolated: true,
                pinned_segment_nonempty: false
            },
            "{raw}"
        );
    }
    let empty = LiteralText::at(r#""[]""#.into(), 0);
    assert!(empty.parts().unwrap().unwrap().expressions.is_empty());
    for raw in [r#""prefix [a]""#, r#""[a] suffix""#, r#""\ []""#] {
        assert_eq!(
            shape(raw),
            LiteralLexicalShape {
                interpolated: true,
                pinned_segment_nonempty: true
            },
            "{raw}"
        );
    }
}

#[test]
fn pinned_escape_presence_is_retained_before_runtime_decoding() {
    let text = LiteralText::at(r#""\ ""#.into(), 0);
    let parts = text.parts().unwrap().unwrap();
    assert!(parts.template.is_empty());
    assert_eq!(
        parts.lexical.unwrap(),
        LiteralLexicalShape {
            interpolated: false,
            pinned_segment_nonempty: true
        }
    );
    assert_eq!(
        shape(r#""\[a]""#),
        LiteralLexicalShape {
            interpolated: false,
            pinned_segment_nonempty: true
        }
    );
    assert_eq!(
        shape(r#""\n""#),
        LiteralLexicalShape {
            interpolated: false,
            pinned_segment_nonempty: true
        }
    );
    assert_eq!(
        shape(r#""""#),
        LiteralLexicalShape {
            interpolated: false,
            pinned_segment_nonempty: false
        }
    );
}

#[test]
fn raw_literals_do_not_interpolate_or_consume_continuations() {
    assert_eq!(
        shape(r#"@"[a]""#),
        LiteralLexicalShape {
            interpolated: false,
            pinned_segment_nonempty: true
        }
    );
    assert_eq!(
        shape(r#"@"""#),
        LiteralLexicalShape {
            interpolated: false,
            pinned_segment_nonempty: false
        }
    );
    // Use the compiler-admitted multiline raw form. Single-line raw LF
    // acceptance needs a real DreamMaker oracle, not checker permissiveness.
    assert!(shape("@{\"\\\n\"}").pinned_segment_nonempty);
}

#[test]
fn pinned_lf_continuation_limit_is_not_replaced_with_runtime_whitespace_erasure() {
    assert!(!shape("\"\\\n\"").pinned_segment_nonempty);
    assert!(!shape("\"\\\n \t\n\"").pinned_segment_nonempty);
    let raw = "\"\\\n \t\n \t\n\"";
    let text = LiteralText::at(raw.into(), 0);
    let parts = text.parts().unwrap().unwrap();
    assert!(parts.template.is_empty());
    assert!(parts.lexical.unwrap().pinned_segment_nonempty);
}

#[test]
fn original_cr_segments_preserve_pinned_presence_and_runtime_outputs() {
    for (raw, interpolated, nonempty) in [
        ("\"\r\"", false, true),
        ("\"a\rb\"", false, true),
        ("\"\\\r\n\"", false, false),
        ("\"\\\r\n\n\"", false, true),
        ("\"\\\n\n\"", false, false),
        ("\"[a\r]\"", true, false),
        ("\"[\r]\"", true, false),
        ("\"\r[a]\"", true, true),
        ("\"[a]\r\"", true, true),
        ("@\"\r\"", false, true),
        ("@\"\\\r\n[a]\"", false, true),
    ] {
        let text = LiteralText::at(raw.into(), 0);
        let parts = text.parts().unwrap().unwrap();
        assert_eq!(
            parts.lexical,
            Ok(LiteralLexicalShape {
                interpolated,
                pinned_segment_nonempty: nonempty
            }),
            "{raw:?}"
        );
        let tuple = string_literal_parts(raw).unwrap().unwrap();
        assert_eq!(parts.template, tuple.0);
        assert_eq!(parts.expressions, tuple.1);
    }
    assert!(LiteralText::from("\"\r\"")
        .parts()
        .unwrap()
        .unwrap()
        .template
        .is_empty());
    assert!(LiteralText::from("@\"\r\"")
        .parts()
        .unwrap()
        .unwrap()
        .template
        .is_empty());
}

#[test]
fn cr_changed_interpolation_boundaries_remain_explicitly_unsupported() {
    // Pinned escaped CR is a continuation followed by interpolation; the
    // existing runtime CR removal instead leaves an escaped literal '['.
    let raw = "\"\\\r[a]\"";
    let text = LiteralText::at(raw.into(), 0);
    let parts = text.parts().unwrap().unwrap();
    assert!(parts.expressions.is_empty());
    assert_eq!(parts.template, b"[a]");
    assert_eq!(
        parts.lexical,
        Err(LiteralLexicalError::InterpolationBoundaryNormalization)
    );
}

#[test]
fn lexical_facts_live_in_the_existing_shared_once_owner() {
    let text = LiteralText::at(r#""x[a]""#.into(), 0);
    let cloned = text.clone();
    assert!(std::ptr::eq(
        text.parts().unwrap().unwrap(),
        cloned.parts().unwrap().unwrap()
    ));
    assert_eq!(
        text.parts().unwrap().unwrap().lexical,
        cloned.parts().unwrap().unwrap().lexical
    );
}
