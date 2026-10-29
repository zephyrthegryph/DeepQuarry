use super::*;
use dm_analysis::policy_inputs::{HostCapture, PolicyRole};
use dm_tree::frontend::{build_with_config, EngineSeed, FrontendConfig};
use std::{collections::BTreeSet, path::PathBuf, sync::Arc};
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
fn hierarchy() -> EngineSeed {
    let mut seed = EngineSeed {
        identity: 0xdec1,
        symbols: Default::default(),
        hierarchy: dm_tree::EngineHierarchy {
            schema: 0xdec1,
            parents: Vec::new(),
        },
        fields: Arc::from([]),
        intrinsics: Arc::from([]),
    };
    for (child, parent) in [
        ("/", None),
        ("/datum", Some("/")),
        ("/atom", Some("/datum")),
        ("/atom/movable", Some("/atom")),
        ("/obj", Some("/atom/movable")),
        ("/mob", Some("/atom/movable")),
        ("/turf", Some("/atom")),
        ("/area", Some("/atom")),
    ] {
        let child = seed.symbols.intern(child).unwrap();
        let parent = parent.map(|path| seed.symbols.intern(path).unwrap());
        seed.hierarchy.parents.push((child, parent));
    }
    seed
}
fn capture(source: String, certified: bool) -> (PathBuf, PolicyInputs) {
    let root = std::env::current_dir().unwrap().join("captured-decl-unit");
    let path = root.join("code/probe.dm");
    let provider = Source(source);
    let seed = hierarchy();
    let frontend = build_with_config(
        &path,
        &provider,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: certified.then_some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let extra = frontend
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
    (root, PolicyInputs::capture(&frontend, extra).unwrap())
}
#[test]
fn declared_ancestry_preserves_manual_datum_exclusion_and_atom_alias() {
    let(root,inputs)=capture("/datum/manual/proc/Initialize()\n    after(src, 1, null)\n/obj/device/Initialize()\n    after(src, 1, null)\n/datum/alias\n    parent_type = /obj\n    Initialize()\n        after(src, 1, null)\n".into(),true);
    let policy = CapturedDeclPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let run = policy.scan(|| Ok(())).unwrap();
    assert_eq!(
        run.run
            .sites
            .iter()
            .map(|site| (site.rule.as_str(), site.line))
            .collect::<Vec<_>>(),
        [("init_scheduling", 4), ("init_scheduling", 8)]
    );
}
#[test]
fn missing_intrinsic_ancestry_is_unsupported_not_a_false_clean_result() {
    let (root, inputs) = capture(
        "/obj/device/Initialize()\n    after(src, 1, null)\n".into(),
        false,
    );
    let policy = CapturedDeclPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    assert!(policy.scan(|| Ok(())).err().unwrap().contains("certified"));
}
#[test]
fn borrowed_decl_reuses_current_source_owner_and_preserves_all_observations() {
    let source = include_str!("../../dmb/fixtures/native_decl_policy/code/compiled.dm");
    let (root, inputs) = capture(source.into(), true);
    let raw = CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let borrowed = BorrowedDeclPolicy::capture(&raw, &inputs).unwrap();
    let actual = borrowed.scan(|| Ok(())).unwrap();
    let repeated = borrowed.scan(|| Ok(())).unwrap();
    let expected = CapturedDeclPolicy::capture(&root, &inputs, Configuration::ProvenMissing)
        .unwrap()
        .scan(|| Ok(()))
        .unwrap();
    assert!(!actual.run.sites.is_empty());
    assert_eq!(actual.run.sites, expected.run.sites);
    assert_eq!(actual.run.notes, expected.run.notes);
    assert_eq!(actual.allow_used, expected.allow_used);
    assert_eq!(repeated.run.sites, actual.run.sites);
    assert_eq!(repeated.allow_used, actual.allow_used);
}
#[test]
fn borrowed_decl_refuses_equal_bytes_from_another_current_raw_owner() {
    let source = "/obj/device/Initialize()\n    after(src, 1, null)\n";
    let (root, inputs) = capture(source.into(), true);
    let raw = CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let (_, foreign) = capture(source.into(), true);
    assert!(BorrowedDeclPolicy::capture(&raw, &foreign).is_err());
}
#[test]
fn every_decl_rule_reuses_existing_findings_and_allow_consumption() {
    let source = format!(
        "{}\n// own_set(src, \"dead_owned\", null)\n",
        include_str!("../../dmb/fixtures/native_decl_policy/code/compiled.dm")
    );
    let (root, inputs) = capture(source, true);
    let policy = CapturedDeclPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let run = policy.scan(|| Ok(())).unwrap();
    let rules = run
        .run
        .sites
        .iter()
        .map(|site| site.rule.as_str())
        .collect::<BTreeSet<_>>();
    assert_eq!(
        rules,
        BTreeSet::from([
            "init_reagents",
            "init_gas",
            "init_registry",
            "init_service",
            "init_bind",
            "init_scheduling",
            "init_visuals",
            "init_new_child",
            "destroy_qdel_owned",
            "destroy_drop",
            "destroy_registry",
            "destroy_scheduling",
            "destroy_unbind",
            "destroy_effects"
        ])
    );
    assert_eq!(run.allow_used.len(), 1);
    assert_eq!(run.allow_used[0].name, "decl");
    assert!(run.run.notes.is_empty());
}
#[test]
fn checkpoint_error_discards_the_complete_run() {
    let (root, inputs) = capture(
        "/obj/device/Initialize()\n    after(src, 1, null)\n".into(),
        true,
    );
    let policy = CapturedDeclPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    assert_eq!(
        policy.scan(|| Err("cancelled".into())).err().as_deref(),
        Some("cancelled")
    );
}
