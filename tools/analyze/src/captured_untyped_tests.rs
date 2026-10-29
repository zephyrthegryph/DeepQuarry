use super::*;
#[path = "../../dmb/crates/dm-analysis/examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
struct Source {
    source: &'static str,
    acquired: std::cell::RefCell<
        std::collections::BTreeMap<std::path::PathBuf, dm_preprocess::AcquiredSource>,
    >,
}
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, path: &Path) -> Result<String, String> {
        Ok(if path.extension().is_some_and(|e| e == "dme") {
            "#include \"code/probe.dm\"\n".into()
        } else {
            self.source.into()
        })
    }
    fn acquired_source(
        &self,
        path: &Path,
    ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        if !self.acquired.borrow().contains_key(path) {
            let text = self.read(path)?;
            self.acquired.borrow_mut().insert(
                path.into(),
                dm_preprocess::AcquiredSource::from_original_slice(text.as_bytes(), ()),
            );
        }
        Ok(self.acquired.borrow().get(path).cloned())
    }
    fn source_acquisition(
        &self,
        path: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.acquired
            .borrow()
            .get(path)
            .filter(|a| a.lease().source_text().same_view(text))
            .cloned()
    }
}
fn build_inputs(source: &'static str) -> (std::path::PathBuf, PolicyInputs) {
    build_inputs_mode(source, true)
}
fn build_inputs_mode(source: &'static str, active: bool) -> (std::path::PathBuf, PolicyInputs) {
    use dm_analysis::policy_inputs::{HostCapture, PolicyRole};
    let root = std::env::current_dir()
        .unwrap()
        .join("captured-untyped-fixture");
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("deepquarry.dme"),
        &Source {
            source,
            acquired: Default::default(),
        },
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
        None,
        &executor,
        None,
        active,
    )
    .unwrap();
    let raw = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, f.text.clone())
        })
        .collect::<Vec<_>>();
    (root, PolicyInputs::capture(&frontend, raw).unwrap())
}
#[test]
fn full_untyped_keeps_typed_message_identity_order_and_no_allow() {
    let (root, inputs) = build_inputs(
        "/datum/probe\n    var/item\n    proc/set_item(datum/probe/P)\n        item = P\n",
    );
    let input = ArchiveValueInput::new(Arc::clone(inputs.archive()), &[]);
    let proof = input.compute().unwrap();
    let result = CapturedUntyped::capture(&root, &inputs, Configuration::ProvenMissing)
        .unwrap()
        .scan(&input, proof, ManifestRead::Compiled, || Ok(()))
        .unwrap();
    assert_eq!(result.run.sites.len(), 1);
    let site = &result.run.sites[0];
    assert_eq!(
        (
            site.rule.as_str(),
            site.rel.as_str(),
            site.line,
            site.ident.as_str()
        ),
        ("typed", "code/probe.dm", 2, "/datum/probe::item")
    );
    assert_eq!(
        site.msg,
        "/datum/probe/var/item has no type and is assigned an atom or datum at code/probe.dm:4"
    );
    assert!(result.allow_used.is_empty());
    assert!(result.run.notes.is_empty());
}
#[test]
fn whole_program_value_receipt_cannot_cross_archive_or_exemption_policy() {
    let (root, inputs) = build_inputs("/datum/probe\n    var/item\n");
    let (_, other) = build_inputs("/datum/probe\n    var/item\n");
    let foreign = ArchiveValueInput::new(Arc::clone(other.archive()), &[]);
    let proof = foreign.compute().unwrap();
    let policy = CapturedUntyped::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    assert!(policy
        .scan(&foreign, proof, ManifestRead::Compiled, || Ok(()))
        .is_err());
    let wrong = ArchiveValueInput::new(Arc::clone(inputs.archive()), &["/datum/probe".into()]);
    let proof = wrong.compute().unwrap();
    assert!(policy
        .scan(&wrong, proof, ManifestRead::Compiled, || Ok(()))
        .is_err());
}

#[test]
fn captured_manifest_projection_retains_bom_cr_and_inactive_include_policy() {
    use crate::raw_marker_policy::{dme_include_order, dme_include_order_view};
    let text = "#include \"z.dm\"\n#include \"a.dm\"\n";
    assert_eq!(
        dme_include_order_view(text, true),
        dme_include_order(&format!("\u{feff}{text}"))
    );
    assert_eq!(
        dme_include_order_view(text, true)
            .keys()
            .collect::<Vec<_>>(),
        ["a.dm"]
    );
    let cr = "#include \"z.dm\"\r#include \"a.dm\"\n";
    let rows = dme_include_order(cr);
    assert_eq!(rows.len(), 1);
    assert_eq!(rows["z.dm"], 0);
    let inactive = "#if 0\n#include \"z.dm\"\n#endif\n#include \"a.dm\"\n#include \"z.dm\"\n";
    let rows = dme_include_order(inactive);
    assert_eq!((rows["z.dm"], rows["a.dm"]), (0, 1));
}
#[test]
fn unavailable_manifest_cannot_override_a_positive_captured_root_manifest() {
    let (root, inputs) = build_inputs("/datum/probe\n    var/item\n");
    let policy = CapturedUntyped::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let input = ArchiveValueInput::new(Arc::clone(inputs.archive()), &[]);
    assert!(policy
        .scan(
            &input,
            input.compute().unwrap(),
            ManifestRead::ProvenUnavailable,
            || Ok(())
        )
        .is_err());
    assert!(policy
        .scan(
            &input,
            input.compute().unwrap(),
            ManifestRead::OriginalBytes(b""),
            || Ok(())
        )
        .is_err());
}

#[test]
fn original_member_headers_and_assignment_points_survive_multiphysical_defaults() {
    let(root,inputs)=build_inputs("/datum/probe\n    var/item = list(\n        1)\n    proc/set_item(datum/probe/P)\n        if(1)\n            item = P\n");
    let input = ArchiveValueInput::new(Arc::clone(inputs.archive()), &[]);
    let proof = input.compute().unwrap();
    let run = CapturedUntyped::capture(&root, &inputs, Configuration::ProvenMissing)
        .unwrap()
        .scan(&input, proof, ManifestRead::Compiled, || Ok(()))
        .unwrap();
    assert_eq!(run.run.sites.len(), 1);
    let site = &run.run.sites[0];
    assert_eq!((site.rule.as_str(), site.line), ("typed", 2));
    assert_eq!(
        site.msg,
        "/datum/probe/var/item has no type and is assigned an atom or datum at code/probe.dm:6"
    );
}
#[test]
fn generated_member_header_uses_certified_macro_invocation_line() {
    let(root,inputs)=build_inputs("#define DECL_ITEM var/item\n/datum/probe\n    DECL_ITEM\n    proc/set_item(datum/probe/P)\n        item = P\n");
    let input = ArchiveValueInput::new(Arc::clone(inputs.archive()), &[]);
    let proof = input.compute().unwrap();
    let run = CapturedUntyped::capture(&root, &inputs, Configuration::ProvenMissing)
        .unwrap()
        .scan(&input, proof, ManifestRead::Compiled, || Ok(()))
        .unwrap();
    assert_eq!(run.run.sites.len(), 1);
    assert_eq!(run.run.sites[0].line, 3);
}

#[cfg(windows)]
#[test]
fn dos_verbatim_manifest_candidate_needs_receipt_even_for_negative_selection() {
    let root = Path::new("E:/fixture");
    let exact = root.join("deepquarry.dme");
    assert!(reject_unproven_manifest_alias(root, [exact.as_path()]).is_ok());
    assert!(
        reject_unproven_manifest_alias(root, [Path::new(r"\\?\E:\fixture\deepquarry.dme")])
            .is_err()
    );
}

#[test]
fn lone_cr_display_correction_applies_to_declaration_site_and_assignment_message() {
    let(root,inputs)=build_inputs("/datum/prelude\n    var/dummy\r \n/datum/probe\n    var/item\n    proc/set_item(datum/probe/P)\n        item = P\n");
    let input = ArchiveValueInput::new(Arc::clone(inputs.archive()), &[]);
    let proof = input.compute().unwrap();
    let run = CapturedUntyped::capture(&root, &inputs, Configuration::ProvenMissing)
        .unwrap()
        .scan(&input, proof, ManifestRead::Compiled, || Ok(()))
        .unwrap();
    assert_eq!(run.run.sites.len(), 1);
    assert_eq!(run.run.sites[0].line, 5);
    assert_eq!(
        run.run.sites[0].msg,
        "/datum/probe/var/item has no type and is assigned an atom or datum at code/probe.dm:7"
    );
}

#[test]
fn ordinary_untyped_capture_cannot_silently_substitute_unissued_compatibility_origins() {
    let (root, inputs) = build_inputs_mode(
        "/datum/probe\n    var/item\n    proc/set_item(datum/probe/P)\n        item = P\n",
        false,
    );
    let input = ArchiveValueInput::new(Arc::clone(inputs.archive()), &[]);
    let proof = input.compute().unwrap();
    let result = CapturedUntyped::capture(&root, &inputs, Configuration::ProvenMissing)
        .unwrap()
        .scan(&input, proof, ManifestRead::Compiled, || Ok(()));
    assert!(result.err().unwrap().contains("producer was not requested"));
}

#[test]
fn host_original_compiled_manifest_preserves_facade_rows_and_rejects_substitution() {
    let (root, inputs) = build_inputs(
        "/datum/probe\n    var/item\n    proc/save(datum/probe/P)\n        item = P\n",
    );
    let input = ArchiveValueInput::new(Arc::clone(inputs.archive()), &[]);
    let policy = CapturedUntyped::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let original = b"#include \"code/probe.dm\"\n";
    let old = policy
        .scan(
            &input,
            input.compute().unwrap(),
            ManifestRead::Compiled,
            || Ok(()),
        )
        .unwrap();
    let host = policy
        .scan(
            &input,
            input.compute().unwrap(),
            ManifestRead::CompiledOriginalBytes(original),
            || Ok(()),
        )
        .unwrap();
    assert_eq!(host.run.sites, old.run.sites);
    assert_eq!(host.run.notes, old.run.notes);
    assert!(policy
        .scan(
            &input,
            input.compute().unwrap(),
            ManifestRead::CompiledOriginalBytes(b"#include \"other.dm\"\n"),
            || Ok(())
        )
        .is_err());
}
