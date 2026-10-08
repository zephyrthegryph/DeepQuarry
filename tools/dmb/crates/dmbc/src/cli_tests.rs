use super::*;

fn parse_args(arguments: &[&str]) -> Result<Command, Box<dyn std::error::Error>> {
    parse(
        &arguments
            .iter()
            .map(|s| (*s).to_owned())
            .collect::<Vec<_>>(),
    )
}
fn build(arguments: &[&str]) -> BuildRequest {
    let Command::Build(request) = parse_args(arguments).unwrap() else {
        panic!("expected build request");
    };
    *request
}

#[test]
fn build_defaults_and_supplied_workers_preserve_existing_admission() {
    let request = build(&["compile", "relative.dme"]);
    assert_eq!(request.command, BuildCommand::Compile);
    assert_eq!(request.project, PathBuf::from("relative.dme"));
    assert_eq!(request.workers, 2);
    assert!(request.engine_template.is_none());
    assert!(!request.bootstrap_catalog);
    assert!(!request.exact_inputs);
    assert!(!request.no_cache);
    // Stage worker clamps remain in their existing implementations. Parsing
    // must not impose a new limit or silently change a supplied request.
    assert_eq!(build(&["analyze", "a.dme", "--workers", "99"]).workers, 99);
    assert_eq!(
        parse_args(&["compile", "a.dme", "--workers", "0"])
            .unwrap_err()
            .to_string(),
        "--workers must be positive"
    );
}

#[test]
fn all_build_options_and_define_precedence_cross_typed_boundary() {
    let request = build(&[
        "compile",
        "a.dme",
        "--no-daemon",
        "--no-cache",
        "--exact-inputs",
        "--trace",
        "first.trace",
        "--trace",
        "last.trace",
        "--progress",
        "--engine-template",
        "engine.bin",
        "--bootstrap-catalog",
        "--output-store",
        "store",
        "--record-inputs",
        "record",
        "--replay-inputs",
        "replay",
        "--artifact-directory",
        "out",
        "-D",
        "FOO",
        "-DFOO=2",
        "-DBAR=",
    ]);
    assert!(request.no_daemon && request.no_cache && request.exact_inputs);
    assert!(request.progress_enabled && request.bootstrap_catalog);
    assert_eq!(request.trace_path, Some(PathBuf::from("first.trace")));
    assert_eq!(request.engine_template, Some(PathBuf::from("engine.bin")));
    assert_eq!(request.output_store, Some(PathBuf::from("store")));
    assert_eq!(request.record_inputs, Some(PathBuf::from("record")));
    assert_eq!(request.replay_inputs, Some(PathBuf::from("replay")));
    assert_eq!(request.artifact_directory, Some(PathBuf::from("out")));
    assert_eq!(request.defines["FOO"], "2");
    assert_eq!(request.defines["BAR"], "");
}

#[test]
fn maintenance_help_and_verification_keep_original_dispatch() {
    assert_eq!(parse_args(&[]).unwrap(), Command::Help);
    assert_eq!(parse_args(&["-h", "ignored"]).unwrap(), Command::Help);
    assert_eq!(
        parse_args(&["gc"]).unwrap(),
        Command::Gc {
            project: "deepquarry.dme".into()
        }
    );
    assert_eq!(
        parse_args(&["stats", "p.dme", "ignored"]).unwrap(),
        Command::Stats {
            project: "p.dme".into()
        }
    );
    assert_eq!(
        parse_args(&["explain", "/obj/proc/p"]).unwrap(),
        Command::Explain {
            project: "deepquarry.dme".into(),
            target: "/obj/proc/p".into()
        }
    );
    assert_eq!(
        parse_args(&["explain"]).unwrap_err().to_string(),
        "explain requires an absolute procedure path"
    );
    let arguments = ["invalid", "--verify", "p.dme"];
    assert_eq!(
        parse_args(&arguments).unwrap(),
        Command::Verify(arguments.map(str::to_owned).into())
    );
}

#[test]
fn first_argument_error_and_existing_messages_are_preserved() {
    for (arguments, expected) in [
        (
            vec!["compile", "--unknown", "--workers", "0"],
            "unknown option --unknown",
        ),
        (
            vec!["compile", "a.dme", "b.dme"],
            "analyze accepts one project manifest",
        ),
        (
            vec!["compile", "a.dme", "--trace"],
            "--trace requires a file",
        ),
        (
            vec![
                "compile",
                "a.dme",
                "--output-store",
                "one",
                "--output-store",
                "two",
            ],
            "--output-store accepts one directory",
        ),
        (
            vec![
                "compile",
                "a.dme",
                "--engine-template",
                "one",
                "--engine-template",
                "two",
            ],
            "--engine-template accepts one template",
        ),
        (
            vec!["compile", "-D9INVALID"],
            "invalid define name \"9INVALID\"",
        ),
        (vec!["compile"], "a project manifest is required"),
        (vec!["unknown"], "expected analyze or compile"),
    ] {
        assert_eq!(parse_args(&arguments).unwrap_err().to_string(), expected);
    }
}

#[test]
fn runner_keeps_canonicalization_before_conflicting_record_replay_error() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
    let mut request = build(&[
        "compile",
        "placeholder.dme",
        "--record-inputs",
        "a",
        "--replay-inputs",
        "b",
    ]);
    request.project = manifest.clone();
    assert_eq!(
        crate::request_runner::run_build(request.clone())
            .unwrap_err()
            .to_string(),
        "record and replay inputs are mutually exclusive"
    );
    request.project = manifest.join("guaranteed-missing");
    let expected = std::fs::canonicalize(&request.project)
        .unwrap_err()
        .to_string();
    assert_eq!(
        crate::request_runner::run_build(request)
            .unwrap_err()
            .to_string(),
        expected
    );
}
