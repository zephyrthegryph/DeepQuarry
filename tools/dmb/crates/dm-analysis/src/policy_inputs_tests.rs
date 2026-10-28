use super::*;
use dm_tree::frontend::build;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend() -> ColdFrontend {
    build(
        Path::new("code/compiled.dm"),
        &Source("/datum/compiled\n    var/value = 1\n"),
        &Default::default(),
        1,
    )
    .unwrap()
}
fn text(value: &str) -> SourceText {
    value.to_owned().into()
}
fn raw(path: &str, role: PolicyRole, value: &str) -> HostCapture {
    HostCapture::analyze_raw(Arc::new(path.into()), role, text(value))
}

#[test]
fn compiler_capture_borrows_exact_source_payload_and_requires_raw_view_explicitly() {
    let frontend = frontend();
    let inputs = PolicyInputs::capture(&frontend, []).unwrap();
    let source = &frontend.files[0];
    let file = inputs.file(&source.path).unwrap();
    assert!(file.is_compiled());
    assert!(file
        .view(TextView::CompilerDecoded)
        .unwrap()
        .same_view(&source.text));
    assert!(matches!(
        file.view(TextView::AnalyzeRaw),
        Err(CaptureError::MissingView {
            view: TextView::AnalyzeRaw,
            ..
        })
    ));
    assert!(inputs.matches_frontend(&frontend));
    assert!(inputs.matches_archive(inputs.archive()));
    assert_eq!(inputs.coverage(), Coverage::CapturedFilesOnly);
}

#[test]
fn policy_only_dm_never_becomes_compiled_or_changes_compiler_revision() {
    let frontend = frontend();
    let before = frontend.source_export_revision();
    let first = PolicyInputs::capture(
        &frontend,
        [raw(
            "code/noncompiled.dm",
            PolicyRole::DmSource,
            "/datum/policy_only\n",
        )],
    )
    .unwrap();
    let second = PolicyInputs::capture(
        &frontend,
        [raw(
            "code/noncompiled.dm",
            PolicyRole::DmSource,
            "/datum/policy_only\n    var/extra\n",
        )],
    )
    .unwrap();
    assert_eq!(first.revision().compiler_source, before);
    assert_eq!(
        first.revision().compiler_source,
        second.revision().compiler_source
    );
    assert_ne!(
        first.revision().policy_inputs,
        second.revision().policy_inputs
    );
    assert!(!first
        .file(Path::new("code/noncompiled.dm"))
        .unwrap()
        .is_compiled());
    assert!(first
        .archive()
        .tree()
        .lookup_type(dm_ir::SymbolId::of("/datum/policy_only"))
        .is_none());
    assert_eq!(first.semantic_revision(), second.semantic_revision());
}

#[test]
fn configuration_edits_change_only_policy_input_revision() {
    let frontend = frontend();
    let first = PolicyInputs::capture(
        &frontend,
        [raw(
            "tools/ci/lint_scopes.toml",
            PolicyRole::Configuration,
            "[lint.x]\n",
        )],
    )
    .unwrap();
    let second = PolicyInputs::capture(
        &frontend,
        [raw(
            "tools/ci/lint_scopes.toml",
            PolicyRole::Configuration,
            "[lint.y]\n",
        )],
    )
    .unwrap();
    assert_eq!(
        first.revision().compiler_source,
        second.revision().compiler_source
    );
    assert_ne!(
        first.revision().policy_inputs,
        second.revision().policy_inputs
    );
    assert_eq!(
        first
            .file(Path::new("tools/ci/lint_scopes.toml"))
            .unwrap()
            .role(),
        PolicyRole::Configuration
    );
}

#[test]
fn host_capture_order_does_not_change_the_bound_revision() {
    let frontend = frontend();
    let a = raw(
        "code/a.dm",
        PolicyRole::DmSource,
        "SCHEMA(/datum/x, value, num())\n",
    );
    let b = raw("lint.toml", PolicyRole::Configuration, "enabled = true\n");
    let first = PolicyInputs::capture(&frontend, [a.clone(), b.clone()]).unwrap();
    let second = PolicyInputs::capture(&frontend, [b, a]).unwrap();
    assert_eq!(first.revision(), second.revision());
}

#[test]
fn canonical_aliases_reject_contradictory_duplicates_and_coalesce_equal_views() {
    let frontend = frontend();
    let result = PolicyInputs::capture(
        &frontend,
        [
            raw("code/a/../extra.dm", PolicyRole::DmSource, "first"),
            raw("code/extra.dm", PolicyRole::DmSource, "second"),
        ],
    );
    assert!(matches!(
        result,
        Err(CaptureError::ContradictoryText {
            view: TextView::AnalyzeRaw,
            ..
        })
    ));
    let one = PolicyInputs::capture(
        &frontend,
        [raw("code/extra.dm", PolicyRole::DmSource, "same")],
    )
    .unwrap();
    let two = PolicyInputs::capture(
        &frontend,
        [
            raw("code/a/../extra.dm", PolicyRole::DmSource, "same"),
            raw("code/extra.dm", PolicyRole::DmSource, "same"),
        ],
    )
    .unwrap();
    assert_eq!(one.revision(), two.revision());
    assert_eq!(one.files().count(), two.files().count());
}

#[test]
fn extra_capture_cannot_replace_compiler_payload_or_relabel_its_role() {
    let frontend = frontend();
    let path = Arc::clone(&frontend.files[0].path);
    let original = &frontend.files[0].text;
    let equal = PolicyInputs::capture(
        &frontend,
        [HostCapture::compiler_decoded(
            Arc::clone(&path),
            text(original.as_str()),
        )],
    )
    .unwrap();
    assert!(equal
        .file(&path)
        .unwrap()
        .view(TextView::CompilerDecoded)
        .unwrap()
        .same_view(original));
    assert!(matches!(
        PolicyInputs::capture(
            &frontend,
            [HostCapture::compiler_decoded(
                Arc::clone(&path),
                text("other")
            )]
        ),
        Err(CaptureError::ContradictoryText { .. })
    ));
    assert!(matches!(
        PolicyInputs::capture(
            &frontend,
            [HostCapture::analyze_raw(
                path,
                PolicyRole::Configuration,
                text("same")
            )]
        ),
        Err(CaptureError::DuplicateRole(_))
    ));
}

#[test]
fn compiler_and_analyze_decoding_are_distinct_needed_views_not_silent_fallbacks() {
    let frontend = frontend();
    let source = &frontend.files[0];
    let bom_text = format!("\u{feff}{}", source.text.as_str());
    let inputs = PolicyInputs::capture(
        &frontend,
        [HostCapture::analyze_raw(
            Arc::clone(&source.path),
            PolicyRole::DmSource,
            text(&bom_text),
        )],
    )
    .unwrap();
    let file = inputs.file(&source.path).unwrap();
    assert_eq!(file.view(TextView::AnalyzeRaw).unwrap().as_str(), bom_text);
    assert_eq!(
        file.view(TextView::CompilerDecoded).unwrap().as_str(),
        source.text.as_str()
    );
    assert_ne!(
        PolicyInputs::capture(&frontend, [])
            .unwrap()
            .revision()
            .policy_inputs,
        inputs.revision().policy_inputs
    );
}

#[test]
fn equivalent_views_can_share_the_preexisting_source_owner() {
    let frontend = frontend();
    let source = &frontend.files[0];
    let inputs = PolicyInputs::capture(
        &frontend,
        [HostCapture::analyze_raw(
            Arc::clone(&source.path),
            PolicyRole::DmSource,
            source.text.clone(),
        )],
    )
    .unwrap();
    let file = inputs.file(&source.path).unwrap();
    assert!(file
        .view(TextView::AnalyzeRaw)
        .unwrap()
        .same_view(file.view(TextView::CompilerDecoded).unwrap()));
}

#[test]
fn changed_public_file_roster_is_rejected_even_with_equal_bytes() {
    let mut frontend = frontend();
    frontend.files = frontend.files.iter().cloned().collect::<Vec<_>>().into();
    assert!(frontend.source_export_mapping().is_none());
    assert!(matches!(
        PolicyInputs::capture(&frontend, []),
        Err(CaptureError::ForeignCompilerInputs)
    ));
}

#[test]
fn retained_capture_survives_frontend_release_and_checks_both_revision_pins() {
    let inputs = {
        let frontend = frontend();
        PolicyInputs::capture(
            &frontend,
            [raw("code/extra.dm", PolicyRole::DmSource, "captured once")],
        )
        .unwrap()
    };
    assert_eq!(
        inputs
            .file(Path::new("code/extra.dm"))
            .unwrap()
            .view(TextView::AnalyzeRaw)
            .unwrap()
            .as_str(),
        "captured once"
    );
    let revision = inputs.revision();
    assert!(inputs.matches_revisions(revision.compiler_source, revision.policy_inputs));
    assert!(!inputs.matches_revisions(revision.compiler_source ^ 1, revision.policy_inputs));
    assert!(!inputs.matches_revisions(revision.compiler_source, revision.policy_inputs ^ 1));
    let foreign = PolicyInputs::capture(&frontend(), []).unwrap();
    assert!(!inputs.matches_archive(foreign.archive()));
    assert!(!inputs.matches_frontend(&frontend()));
}

#[test]
fn prepared_policy_file_reuses_the_existing_lexical_owner_without_compiling_it() {
    let frontend = frontend();
    let prepared =
        dm_preprocess::regions::prepared_source::shared_prepared(text("/datum/uncompiled\n"));
    let inputs = PolicyInputs::capture(
        &frontend,
        [HostCapture::prepared_dm(
            Arc::new("code/uncompiled.dm".into()),
            &prepared,
        )],
    )
    .unwrap();
    let file = inputs.file(Path::new("code/uncompiled.dm")).unwrap();
    assert!(file
        .view(TextView::CompilerDecoded)
        .unwrap()
        .same_view(prepared.original()));
    assert!(!file.is_compiled());
    assert!(inputs
        .archive()
        .tree()
        .lookup_type(dm_ir::SymbolId::of("/datum/uncompiled"))
        .is_none());
}
