use super::*;
use crate::check_policy::DiagnosticSeverity;

fn parse(source: &str) -> Result<Loaded, LoadError> {
    let selection = select(Path::new("project.dme"), Some(Path::new("fixture.toml")));
    load(
        &selection,
        Capture {
            path: Path::new("fixture.toml"),
            read: CapturedRead::Bytes(source.as_bytes()),
        },
    )
}

#[test]
fn complete_schema_fields_are_retained_and_policy_composes_existing_normalizer() {
    let loaded = parse(include_str!(
        "../../../fixtures/check_configuration/full.toml"
    ))
    .unwrap();
    assert!(loaded.present);
    assert_eq!(loaded.config.environment, Some("kept-only.dme".into()));
    assert!(loaded.config.langserver.dreamchecker);
    assert!(
        loaded
            .config
            .code_standards
            .disallow_relative_proc_definitions
    );
    assert!(
        !loaded
            .config
            .code_standards
            .disallow_relative_type_definitions
    );
    assert!(loaded.config.dmdoc.use_typepath_names);
    assert_eq!(loaded.config.dmdoc.index_file.as_deref(), Some("index.md"));
    assert_eq!(
        loaded.config.dmdoc.module_directories,
        ["code/library", "code/engine"]
    );
    assert_eq!(loaded.config.debugger.engine, DebugEngine::Auxtools);
    assert_eq!(
        loaded.config.map_renderer.render_passes.get("objects"),
        Some(&true)
    );
    assert_eq!(
        loaded.config.map_renderer.fancy_layers.get("/obj"),
        Some(&2.5)
    );
    assert_eq!(loaded.config.map_renderer.hide_invisible, ["/obj/hidden"]);
    assert_eq!(
        loaded
            .policy
            .register(Some("ambiguous_not_bitwise"), DiagnosticSeverity::Warning),
        Some(DiagnosticSeverity::Error)
    );
}

#[test]
fn nested_defaults_match_pinned_schema_including_nondefaulted_langserver_field() {
    let loaded = parse("").unwrap();
    assert_eq!(loaded.config, Config::default());
    assert_eq!(loaded.config.debugger.engine, DebugEngine::Extools);
    assert!(parse("[display]\n[debugger]\n[code_standards]\n[dmdoc]\n[map_renderer]\n").is_ok());
    let error = parse("[langserver]\n").unwrap_err();
    let LoadError::Configuration {
        line,
        column,
        cause,
        ..
    } = error
    else {
        panic!("configuration error expected")
    };
    assert_eq!((line, column), (1, 1));
    assert!(cause.contains("missing field `dreamchecker`"), "{cause}");
}

#[test]
fn malformed_nonpolicy_sections_cannot_be_ignored_by_policy_loader() {
    for source in [
        "environment=1\n",
        "[code_standards]\ndisallow_relative_proc_definitions=\"yes\"\n",
        "[langserver]\ndreamchecker=1\n",
        "[dmdoc]\nmodule_directories=\"code\"\n",
        "[debugger]\nengine=\"EXTOOLS\"\n",
        "[map_renderer.render_passes]\nobjects=1\n",
        "[map_renderer.fancy_layers]\n\"/obj\"=true\n",
        "[map_renderer]\nhide_invisible=[1]\n",
    ] {
        assert!(
            matches!(parse(source), Err(LoadError::Configuration { .. })),
            "{source}"
        );
    }
}

#[test]
fn exact_enum_aliases_and_unknown_field_behavior_are_preserved() {
    for engine in ["Extools", "extools", "Auxtools", "auxtools"] {
        assert!(
            parse(&format!("[debugger]\nengine=\"{engine}\"\n")).is_ok(),
            "{engine}"
        );
    }
    for level in [
        "error", "errors", "warning", "warnings", "info", "infos", "hint", "hints", "disabled",
        "false", "off", "unset",
    ] {
        assert!(
            parse(&format!("[diagnostics]\nunknown_future=\"{level}\"\n")).is_ok(),
            "{level}"
        );
    }
    assert!(parse("[diagnostics]\nx=false\n").is_err());
    assert!(parse("[diagnostics]\nx=\"Warning\"\n").is_err());
    assert!(parse("unknown={arbitrary=[1,2]}\n[debugger]\nunknown=true\n[langserver]\ndreamchecker=false\nunknown={a=[true]}\n").is_ok());
}

#[test]
fn absent_autodetect_and_explicit_read_failures_are_distinct_captured_facts() {
    let auto = select(Path::new("a/b/project.dme"), None);
    assert_eq!(auto.path, Path::new("a/b/SpacemanDMM.toml"));
    let empty = load(
        &auto,
        Capture {
            path: &auto.path,
            read: CapturedRead::AutodetectAbsent,
        },
    )
    .unwrap();
    assert!(!empty.present);
    let explicit = select(Path::new("a/b/project.dme"), Some(Path::new("custom.toml")));
    assert_eq!(explicit.path, Path::new("custom.toml"));
    assert!(matches!(
        load(
            &explicit,
            Capture {
                path: &explicit.path,
                read: CapturedRead::AutodetectAbsent
            }
        ),
        Err(LoadError::ExplicitWithoutReadResult(_))
    ));
    let error = load(
        &explicit,
        Capture {
            path: &explicit.path,
            read: CapturedRead::ReadFailure {
                cause: "actual captured open error",
            },
        },
    )
    .unwrap_err();
    assert!(
        matches!(error,LoadError::Configuration {line:1,column:1,cause,..} if cause=="actual captured open error")
    );
    assert!(matches!(
        load(
            &explicit,
            Capture {
                path: Path::new("different.toml"),
                read: CapturedRead::Bytes(b"")
            }
        ),
        Err(LoadError::ForeignCapture { .. })
    ));
}

#[test]
fn invalid_utf8_is_a_read_error_not_lossy_toml_input() {
    let selected = select(Path::new("project.dme"), Some(Path::new("fixture.toml")));
    let error = load(
        &selected,
        Capture {
            path: &selected.path,
            read: CapturedRead::Bytes(b"# \xff\n"),
        },
    )
    .unwrap_err();
    assert!(
        matches!(error,LoadError::Configuration {line:1,column:1,cause,..} if cause=="stream did not contain valid UTF-8")
    );
}

#[test]
fn map_renderer_uses_pinned_f32_deserialization_including_special_floats() {
    let loaded =
        parse("[map_renderer.fancy_layers]\nfinite=2\nnot_a_number=nan\ninfinite=inf\n").unwrap();
    assert_eq!(loaded.config.map_renderer.fancy_layers["finite"], 2.0);
    assert!(loaded.config.map_renderer.fancy_layers["not_a_number"].is_nan());
    assert!(loaded.config.map_renderer.fancy_layers["infinite"].is_infinite());
}

#[test]
fn malformed_fixture_causes_and_locations_match_independent_pinned_checker_capture() {
    for (source, expected_line, expected_column, expected_cause) in [
        (include_str!("../../../fixtures/check_configuration/missing_langserver.toml"),1,1,
            "missing field `dreamchecker` for key `langserver` at line 1 column 1"),
        (include_str!("../../../fixtures/check_configuration/invalid_standards.toml"),2,38,
            "invalid type: string \"yes\", expected a boolean for key `code_standards.disallow_relative_proc_definitions` at line 2 column 38"),
        (include_str!("../../../fixtures/check_configuration/invalid_dmdoc.toml"),2,22,
            "invalid type: string \"code\", expected a sequence for key `dmdoc.module_directories` at line 2 column 22"),
        (include_str!("../../../fixtures/check_configuration/invalid_debugger.toml"),1,1,
            "unknown variant `EXTOOLS`, expected one of `Extools`, `extools`, `Auxtools`, `auxtools` for key `debugger.engine` at line 1 column 1"),
    ] {
        let LoadError::Configuration {line,column,cause,..}=parse(source).unwrap_err() else {panic!("configuration error expected")};
        assert_eq!((line,column,cause.as_str()),(expected_line,expected_column,expected_cause));
    }
    assert_eq!(
        CONFIGURATION_ERROR_MESSAGE,
        "Error reading configuration file"
    );
}
