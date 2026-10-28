use super::*;
use serde_json::json;

#[test]
fn default_keeps_producer_severity_and_untagged_findings() {
    let policy = CheckerPolicy::default();
    for severity in [
        DiagnosticSeverity::Error,
        DiagnosticSeverity::Warning,
        DiagnosticSeverity::Info,
        DiagnosticSeverity::Hint,
    ] {
        assert_eq!(policy.register(Some("anything"), severity), Some(severity));
        assert_eq!(policy.register(None, severity), Some(severity));
    }
    assert_eq!(DiagnosticSeverity::default(), DiagnosticSeverity::Error);
}

#[test]
fn exact_aliases_are_case_sensitive_strings_not_booleans() {
    for (names, expected) in [
        (vec!["error", "errors"], WarningLevel::Error),
        (vec!["warning", "warnings"], WarningLevel::Warning),
        (vec!["info", "infos"], WarningLevel::Info),
        (vec!["hint", "hints"], WarningLevel::Hint),
        (vec!["disabled", "false", "off"], WarningLevel::Disabled),
        (vec!["unset"], WarningLevel::Unset),
    ] {
        for name in names {
            assert_eq!(WarningLevel::parse(name), Ok(expected));
        }
    }
    for invalid in ["Warning", "true", "on", "none", ""] {
        assert!(WarningLevel::parse(invalid).is_err());
    }
    for invalid in [json!(false), json!(0), json!(null), json!([])] {
        assert!(CheckerPolicy::from_sections(None, Some(&json!({"x": invalid}))).is_err());
    }
}

#[test]
fn overrides_run_before_registration_threshold() {
    let policy = CheckerPolicy::from_sections(
        Some(&json!({"error_level": "warning"})),
        Some(
            &json!({"promote": "error", "demote": "hint", "disabled": "off", "unchanged": "unset"}),
        ),
    )
    .unwrap();
    assert_eq!(
        policy.register(Some("promote"), DiagnosticSeverity::Hint),
        Some(DiagnosticSeverity::Error)
    );
    assert_eq!(
        policy.register(Some("demote"), DiagnosticSeverity::Error),
        None
    );
    assert_eq!(
        policy.register(Some("disabled"), DiagnosticSeverity::Error),
        None
    );
    assert_eq!(
        policy.register(Some("unchanged"), DiagnosticSeverity::Warning),
        Some(DiagnosticSeverity::Warning)
    );
    assert_eq!(policy.register(None, DiagnosticSeverity::Hint), None);
}

#[test]
fn family_keys_are_exact_and_unknown_keys_are_not_global_defaults() {
    let policy = CheckerPolicy::from_sections(
        None,
        Some(&json!({"x": "off", "unknown_future": "error", "": "off"})),
    )
    .unwrap();
    assert_eq!(policy.register(Some("x"), DiagnosticSeverity::Error), None);
    assert_eq!(
        policy.register(Some("X"), DiagnosticSeverity::Error),
        Some(DiagnosticSeverity::Error)
    );
    assert_eq!(
        policy.register(None, DiagnosticSeverity::Warning),
        Some(DiagnosticSeverity::Warning)
    );
    assert_eq!(
        policy.register(Some("unknown_future"), DiagnosticSeverity::Warning),
        Some(DiagnosticSeverity::Error)
    );
}

#[test]
fn every_display_cutoff_includes_the_boundary() {
    let severities = [
        DiagnosticSeverity::Error,
        DiagnosticSeverity::Warning,
        DiagnosticSeverity::Info,
        DiagnosticSeverity::Hint,
    ];
    for (level, count) in [
        (WarningLevel::Error, 1),
        (WarningLevel::Warning, 2),
        (WarningLevel::Info, 3),
        (WarningLevel::Hint, 4),
        (WarningLevel::Unset, 4),
        (WarningLevel::Disabled, 0),
    ] {
        assert_eq!(
            severities.iter().filter(|s| level.applies_to(**s)).count(),
            count
        );
    }
}

#[test]
fn malformed_sections_fail_but_unknown_display_fields_are_ignored() {
    assert_eq!(
        CheckerPolicy::from_sections(Some(&json!({"future": false})), None).unwrap(),
        CheckerPolicy::default()
    );
    for value in [json!(null), json!("off"), json!([]), json!(false)] {
        assert!(CheckerPolicy::from_sections(Some(&value), None).is_err());
        assert!(CheckerPolicy::from_sections(None, Some(&value)).is_err());
    }
}

#[test]
fn config_selection_has_no_ancestor_search_or_explicit_path_rebase() {
    assert_eq!(
        configuration_path(Path::new("a/b/p.dme"), None),
        Path::new("a/b/SpacemanDMM.toml")
    );
    assert_eq!(
        configuration_path(Path::new("p.dme"), None),
        Path::new("SpacemanDMM.toml")
    );
    assert_eq!(
        configuration_path(Path::new("a/b/p.dme"), Some(Path::new("custom.toml"))),
        Path::new("custom.toml")
    );
}

#[test]
fn hints_stay_registered_but_do_not_print_or_fail_pinned_cli() {
    assert!(!cli_printed(DiagnosticSeverity::Hint));
    assert!(!cli_counts_as_failure(DiagnosticSeverity::Hint));
    assert!(cli_printed(DiagnosticSeverity::Info));
    assert!(cli_counts_as_failure(DiagnosticSeverity::Info));
}
