use super::*;
#[test]
fn original_parameter_qualifiers_and_typed_array_suffix_preserve_all_old_rows() {
    macro_rules! case {
        ($name:literal) => {
            (
                include_str!(concat!(
                    "../../../fixtures/unified_checks/parameter_source/",
                    $name,
                    "/probe.dme"
                )),
                include_str!(concat!(
                    "../../../fixtures/unified_checks/parameter_source/",
                    $name,
                    "/reference.stderr"
                )),
                $name,
            )
        };
    }
    for (source, expected, name) in [case!("qualified-leading"), case!("typed-array")] {
        assert!(
            !expected.is_empty(),
            "fixture must expose a real old effect diagnostic"
        );
        let (snapshot, _) = fixture(source, None);
        let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
        let rows = snapshot
            .native_purity_report(&input, &env(), None, &snapshot.tree)
            .unwrap_or_else(|e| panic!("{name}: {e}"));
        assert_eq!(
            render(&rows),
            decode_oracle_transport(expected).as_ref(),
            "{name}: complete old oracle"
        );
    }
}
#[test]
fn internal_parameter_qualifier_does_not_borrow_runtime_normalized_receiver_type() {
    let source = include_str!(
        "../../../fixtures/unified_checks/parameter_source/qualified-internal/probe.dme"
    );
    let expected = include_str!(
        "../../../fixtures/unified_checks/parameter_source/qualified-internal/reference.stderr"
    );
    assert!(expected.contains("undefined type: /datum/tmp/box"));
    let (snapshot, _) = fixture(source, None);
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let error = snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .unwrap_err();
    assert!(
        error
            .to_string()
            .contains("undefined-type diagnostic projection"),
        "{error}"
    );
}
