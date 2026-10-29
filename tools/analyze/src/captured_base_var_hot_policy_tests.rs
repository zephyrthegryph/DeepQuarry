use super::*;
use dm_analysis::policy_inputs::HostCapture;
use std::{path::PathBuf, sync::Arc};
struct Source(
    &'static str,
    std::cell::RefCell<std::collections::BTreeMap<PathBuf, dm_preprocess::AcquiredSource>>,
);
impl Source {
    fn new(text: &'static str) -> Self {
        Self(text, Default::default())
    }
}
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("actual primary bytes required".into())
    }
    fn acquired_source(
        &self,
        path: &Path,
    ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        if !self.1.borrow().contains_key(path) {
            self.1.borrow_mut().insert(
                path.into(),
                dm_preprocess::AcquiredSource::from_original_bytes(self.0.as_bytes().to_vec(), ()),
            );
        }
        Ok(self.1.borrow().get(path).cloned())
    }
    fn source_acquisition(
        &self,
        path: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.1
            .borrow()
            .get(path)
            .filter(|source| source.lease().source_text().same_view(text))
            .cloned()
    }
}
fn inputs(source: &'static str) -> (PathBuf, PolicyInputs) {
    let root = std::env::current_dir().unwrap().join("base-var-hot-unit");
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("code/probe.dm"),
        &Source::new(source),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        None,
        true,
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
fn borrowed_facts_keep_authored_initializer_and_native_declaration_metadata() {
    let (root, inputs) =
        inputs("/atom\n    var/list/items = null\n    items = list()\n    var/static/shared\n");
    let raw = CapturedRawPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    let facts = NativeBaseVarFacts::capture(&raw, &inputs).unwrap();
    let rows = facts.declarations(BASE_TYPES).unwrap();
    assert_eq!(rows.len(), 1);
    let row = &rows[0];
    assert_eq!(
        (row.owner, row.name, row.relative.as_ref(), row.line),
        ("/atom", "items", "code/probe.dm", 2)
    );
    assert!(row.native.list_init);
    assert_ne!(row.native.declaration, row.native.source_value);
    assert!(std::ptr::eq(
        row.native.metadata,
        inputs
            .archive()
            .tree()
            .member(row.native.declaration)
            .unwrap()
            .metadata
            .as_ref()
    ));
}
#[test]
fn foreign_empty_roster_cannot_certify_another_raw_capture() {
    let (root, a) = inputs("/datum/a\n");
    let (_, b) = inputs("/datum/b\n");
    let raw = CapturedRawPolicy::capture(&root, &a, Configuration::ProvenMissing).unwrap();
    assert!(NativeBaseVarFacts::capture(&raw, &b).is_err());
}
#[test]
fn hot_rule_shares_existing_classifier_and_ignores_instance_free_fields() {
    let(root,inputs)=inputs("#define TRACKED(T,V)\n/atom\n    var/existing\n    var/homed\n    var/static/shared\nTRACKED(/atom,homed)\n");
    let config=b"[lint.base_vars.lists]\nbase_var_home_macros=['TRACKED']\n[lint.base_vars.tables.base_var_home_hot]\n'/atom/existing'='code/reader.dm /atom/proc/tick reads this field on every active tick'\n'/atom/homed'='code/reader.dm /atom/proc/tick reads this field on every active tick'\n'/atom/shared'='code/reader.dm /atom/proc/tick reads this field on every active tick'\n";
    let policy =
        CapturedBaseVarHotPolicy::capture(&root, &inputs, Configuration::Captured(config)).unwrap();
    let run = policy.scan(|| Ok(())).unwrap();
    assert_eq!(run.run.sites.len(), 2);
    assert!(run
        .run
        .sites
        .iter()
        .any(|site| site.ident == "hot::/atom/homed" && site.msg.contains("already homed")));
    assert!(run
        .run
        .sites
        .iter()
        .any(|site| site.ident == "hot::/atom/shared" && site.msg.contains("stale")));
    assert!(run.allow_used.is_empty());
    assert_eq!(
        run.run.notes,
        ["base_vars: 3 hot base vars homed by base_var_home_hot"]
    );
}
#[test]
fn cancellation_does_not_return_partial_findings() {
    let (root, inputs) = inputs("/atom\n    var/existing\n");
    let policy =
        CapturedBaseVarHotPolicy::capture(&root, &inputs, Configuration::ProvenMissing).unwrap();
    assert_eq!(
        policy.scan(|| Err("cancelled".into())).err().as_deref(),
        Some("cancelled")
    );
}
