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
    let root = std::env::current_dir().unwrap().join("captured-init-unit");
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
fn init_roster_needs_no_ancestry_when_policy_does_not_query_it() {
    let (root, inputs) = capture("/obj/device/Initialize()\n    value = 1\n".into(), false);
    let policy = CapturedInitPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let run = policy.scan(|| Ok(())).unwrap();
    assert_eq!(
        run.run
            .sites
            .iter()
            .map(|s| (s.rule.as_str(), s.ident.as_str()))
            .collect::<Vec<_>>(),
        [("init_lines", "/obj/device::Initialize::value")]
    );
}
#[test]
fn all_six_init_rules_reuse_original_policy_and_identity_text() {
    let (root, inputs) = capture(
        include_str!("../../dmb/fixtures/native_init_policy/code/compiled.dm").into(),
        true,
    );
    let policy = CapturedInitPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let run = policy.scan(|| Ok(())).unwrap();
    assert_eq!(
        run.run
            .sites
            .iter()
            .map(|s| s.rule.as_str())
            .collect::<BTreeSet<_>>(),
        BTreeSet::from([
            "initialize",
            "late_initialize",
            "init_lines",
            "world_reads",
            "turf_on_materialize",
            "table_init_overrides"
        ])
    );
    assert!(run
        .run
        .sites
        .iter()
        .any(|s| s.ident == "/obj/nested::Initialize::nested_state"));
    assert!(run.run.sites.iter().any(|s|s.msg=="ALLOW(init) needs a reason code: ALLOW(init/CODE), CODE one of INSTANCE_STATE, CTOR_ARGS, FRAMEWORK"));
}
#[test]
fn configured_roots_skip_only_the_exact_initialize_owner() {
    let(root,inputs)=capture("/obj/core/Initialize()\n    root_state = 1\n/obj/core/child/Initialize()\n    child_state = 1\n".into(),false);
    let config=b"[lint.init.lists]\ninit_roots=['/obj/core = fixture owns the root initialization chain']\n";
    let policy =
        CapturedInitPolicy::capture(&root, &inputs, Configuration::Captured(config)).unwrap();
    let run = policy.scan(|| Ok(())).unwrap();
    assert_eq!(
        run.run
            .sites
            .iter()
            .map(|s| s.ident.as_str())
            .collect::<Vec<_>>(),
        ["/obj/core/child::Initialize::child_state"]
    );
}
#[test]
fn valid_header_keep_does_not_hide_imperative_lines_and_world_keep_is_consumed() {
    let(root,inputs)=capture("// ALLOW(init/INSTANCE_STATE): fixture retains per-instance state for this owner\n/obj/kept/Initialize()\n    state = 1\n    range(1) // ALLOW(init): fixture deliberately preserves this initialization world read\n".into(),false);
    let policy = CapturedInitPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let run = policy.scan(|| Ok(())).unwrap();
    assert_eq!(
        run.run
            .sites
            .iter()
            .map(|s| (s.rule.as_str(), s.line))
            .collect::<Vec<_>>(),
        [("init_lines", 3), ("init_lines", 4)]
    );
    assert_eq!(run.allow_used.len(), 2);
}
#[test]
fn checkpoint_error_has_no_partial_findings() {
    let (root, inputs) = capture("/obj/device/Initialize()\n    value = 1\n".into(), false);
    let policy = CapturedInitPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    assert_eq!(
        policy.scan(|| Err("cancelled".into())).err().as_deref(),
        Some("cancelled")
    );
}

#[test]
fn init_outer_annotation_state_is_isolated_on_success_failure_and_panic() {
    let previous=crate::dm::sys::take_recorded();
    let sentinel=crate::lint::AllowUse{rel:"caller.dm".into(),line:1,name:"caller".into(),code:"".into()};
    let (root,inputs)=capture("/obj/device/Initialize()\n    . = ..()\n".into(),false);
    let policy=CapturedInitPolicy::capture(&root,&inputs,Configuration::ProvenMissing).unwrap();
    let expected=policy.scan(||Ok(())).unwrap();
    for mode in 0..3 {
        crate::dm::sys::restore_recorded(vec![sentinel.clone()]);
        let actual=policy.scan(||match mode {
            1=>Err("cancelled fixture".into()),2=>panic!("fixture checkpoint panic"),_=>Ok(())
        });
        assert_eq!(crate::dm::sys::take_recorded(),vec![sentinel.clone()]);
        if mode==0 {
            let actual=actual.unwrap();assert_eq!(actual.run.sites,expected.run.sites);
            assert_eq!(actual.allow_used,expected.allow_used);assert_eq!(actual.run.notes,expected.run.notes);
        }else{assert!(actual.is_err());}
    }
    crate::dm::sys::restore_recorded(previous);
}
