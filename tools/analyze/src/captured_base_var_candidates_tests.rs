use super::*;
use dm_analysis::policy_inputs::{HostCapture, PolicyRole};
use std::{path::PathBuf, sync::Arc};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn inputs(source: &'static str, raw: Option<&'static str>) -> (PathBuf, PolicyInputs) {
    let root = std::env::current_dir()
        .unwrap()
        .join("base-var-candidate-unit");
    let frontend = dm_tree::frontend::build(
        &root.join("code/probe.dm"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let mut extra = frontend
        .files
        .iter()
        .filter(|file| file.captured)
        .map(|file| {
            HostCapture::analyze_raw(
                Arc::clone(&file.path),
                PolicyRole::DmSource,
                file.text.clone(),
            )
        })
        .collect::<Vec<_>>();
    if let Some(raw) = raw {
        extra.push(HostCapture::analyze_raw(
            Arc::new(root.join("code/raw.dm")),
            PolicyRole::DmSource,
            raw.into(),
        ));
    }
    (root, PolicyInputs::capture(&frontend, extra).unwrap())
}
#[test]
fn raw_uncompiled_and_typed_only_allow_questions_are_preserved() {
    let source="#define NATIVE /atom/var/typed = 0 // ALLOW(base_vars): fixture deliberately keeps this native only field declaration\n/atom\n    var/plain\nNATIVE // ALLOW(base_vars): fixture deliberately keeps this native only field declaration\n";
    let raw="/datum/first\n    var/a // ALLOW(base_vars): fixture keeps the first raw instance declaration\n/datum/second\n    var/b // ALLOW(base_vars): fixture keeps the second raw instance declaration\n/datum/first\n    var/c // ALLOW(base_vars): fixture keeps the later declaration of the first owner\n";
    let (root, inputs) = inputs(source, Some(raw));
    let policy =
        CapturedBaseVarCandidates::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let native =
        crate::captured_base_var_hot_policy::NativeBaseVarFacts::capture(&policy.raw, &inputs)
            .unwrap()
            .declarations(BASE_TYPES)
            .unwrap();
    assert!(native.iter().any(|row| row.name == "typed"));
    let run = policy.scan(|| Ok(())).unwrap();
    assert_eq!(
        run.allow_used
            .iter()
            .filter(|u| u.rel == "code/raw.dm")
            .map(|u| u.line)
            .collect::<Vec<_>>(),
        [2, 6, 4]
    );
    assert!(run
        .run
        .sites
        .iter()
        .any(|site| site.ident == "/atom::plain"));
    assert!(run
        .allow_used
        .iter()
        .any(|usage| usage.rel == "code/probe.dm" && usage.name == "base_vars"));
}
#[test]
fn schema_hint_presence_reads_raw_markers_without_a_decls_model() {
    let source = "/atom\n    var/one\n    var/two\n";
    let raw="SCHEMA(/atom, one, map_of(schema_text(), schema_path(/obj), nullable = 1))\nSCHEMA(/atom, one, schema_ref(/obj))\nSCHEMA(/atom, two, schema_ref(/obj))\n";
    let (root, inputs) = inputs(source, Some(raw));
    let policy =
        CapturedBaseVarCandidates::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let run = policy.scan(|| Ok(())).unwrap();
    assert!(run.run.sites.iter().any(|site| site.ident == "/atom::one"
        && site.msg == crate::value_schema_policy::hint_message("/atom::one")));
    assert!(run
        .run
        .sites
        .iter()
        .any(|site| site.ident == "/atom::two" && site.msg.is_empty()));
    let file = policy.raw.tree.get("code/raw.dm").unwrap();
    assert!(file.marker().same_view(file.marker()));
}
#[test]
fn list_keep_is_consumed_only_after_the_original_exemption_filters() {
    let source="/datum/ordinary\n    var/list/cache = list() // ALLOW(instance_list): fixture keeps this instance list allocation deliberately\n";
    let (root, inputs) = inputs(source, None);
    let config = b"[lint.base_vars.lists]\nlist_init_exempt_prefixes=['code/']\n";
    let policy =
        CapturedBaseVarCandidates::capture(&root, &inputs, Configuration::Captured(config))
            .unwrap();
    let run = policy.scan(|| Ok(())).unwrap();
    assert!(run.run.sites.is_empty());
    assert!(run.allow_used.is_empty());
}
#[test]
fn raw_callback_skips_instance_free_declarations_before_allow_questions() {
    let text="/datum/probe\n    var/a // ALLOW(base_vars): fixture keeps this raw variable declaration deliberately\n    var/static/b // ALLOW(base_vars): static fields must not consume this annotation\n";
    let file = crate::tree::SourceFile::from_text("code/raw.dm", text);
    assert_eq!(
        crate::base_var_candidate_policy::raw_allow_lines(&file),
        [2]
    );
}
#[test]
fn cancellation_discards_all_policy_results() {
    let (root, inputs) = inputs("/atom\n    var/one\n", None);
    let policy =
        CapturedBaseVarCandidates::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    assert_eq!(
        policy.scan(|| Err("cancelled".into())).err().as_deref(),
        Some("cancelled")
    );
}
#[test]
fn panic_discards_partial_annotation_records_and_restores_caller_state() {
    let (root, inputs) = inputs("/atom\n    var/one\n", None);
    let policy =
        CapturedBaseVarCandidates::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let prior = crate::lint::AllowUse {
        rel: "caller.dm".into(),
        line: 7,
        name: "base_vars".into(),
        code: String::new(),
    };
    let saved = crate::dm::sys::take_recorded();
    crate::dm::sys::restore_recorded(vec![prior.clone()]);
    let result = policy.scan(|| {
        crate::dm::sys::replay_recorded(vec![crate::lint::AllowUse {
            rel: "partial.dm".into(),
            line: 1,
            name: "base_vars".into(),
            code: String::new(),
        }]);
        panic!("intentional policy boundary failure")
    });
    assert!(result.is_err());
    assert_eq!(crate::dm::sys::take_recorded(), vec![prior]);
    crate::dm::sys::restore_recorded(saved);
}
