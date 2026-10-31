use super::*;
use std::{
    cell::RefCell,
    collections::BTreeMap,
    path::{Path, PathBuf},
};
struct Source {
    bytes: Vec<u8>,
    owners: RefCell<BTreeMap<PathBuf, dm_preprocess::AcquiredSource>>,
}
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("must acquire original bytes".into())
    }
    fn acquired_source(
        &self,
        path: &Path,
    ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        if !self.owners.borrow().contains_key(path) {
            self.owners.borrow_mut().insert(
                path.into(),
                dm_preprocess::AcquiredSource::from_original_bytes(self.bytes.clone(), ()),
            );
        }
        Ok(self.owners.borrow().get(path).cloned())
    }
    fn source_acquisition(
        &self,
        path: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.owners
            .borrow()
            .get(path)
            .filter(|owner| owner.lease().source_text().same_view(text))
            .cloned()
    }
}
fn prepare(text: &str) -> Result<DiagnosticFrontend, Vec<Diagnostic>> {
    let source = Source {
        bytes: text.as_bytes().to_vec(),
        owners: Default::default(),
    };
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let result = super::super::build_for_checker_diagnostics(
        Path::new("diagnostic_native.dme"),
        &source,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
    );
    assert_eq!(
        source.owners.borrow().len(),
        1,
        "one acquired original source owner; no second parse/provider model"
    );
    result
}
#[test]
fn diagnostic_frontend_retains_the_original_error_graph_and_refuses_compile_transition() {
    let source =
        "/datum/base\n    var/SpacemanDMM_private/p = null\n/datum/base/child\n    var/p = null\n";
    let prepared = prepare(source).unwrap();
    let view = prepared.source_view().unwrap();
    assert_eq!(view.receipt().errors().len(), 1);
    assert!(view.receipt().authenticates(view.tree()));
    assert!(view.archive().matches_tree(view.tree()));
    assert!(Arc::ptr_eq(view.mapping(), view.archive().source_mapping()));
    let child = view
        .tree()
        .lookup_type(dm_ir::SymbolId::of("/datum/base/child"))
        .unwrap();
    let own = view
        .tree()
        .resolve(child, dm_ir::SymbolId::of("p"), crate::MemberKind::Var)
        .unwrap();
    assert_eq!(
        view.tree().member(own).unwrap().definition,
        crate::DefinitionMode::Declare
    );
    let occurrences = view.occurrences().for_target(crate::Target::Member(own));
    assert_eq!(occurrences.len(), 1);
    let occurrence = occurrences[0];
    assert_eq!(
        view.mapping()
            .declaration_checker_qualifiers(occurrence)
            .unwrap(),
        0
    );
    assert!(
        prepared.try_into_compilable().is_err(),
        "error graph cannot be laundered into runtime ABI/lowering"
    );
}
#[test]
fn diagnostic_frontend_without_errors_transfers_same_owner_to_ordinary_compiler() {
    let prepared =
        prepare("/datum/base\n    var/p = null\n/datum/base/child\n    p = null\n").unwrap();
    let owner = Arc::clone(prepared.source_view().unwrap().tree());
    let compiled = match prepared.try_into_compilable() {
        Ok(frontend) => frontend,
        Err(_) => panic!("valid original declaration graph should compile without rebuild"),
    };
    assert!(Arc::ptr_eq(&owner, &compiled.snapshot.tree));
}
#[test]
fn diagnostic_frontend_does_not_collect_unproved_error_domains() {
    for source in [
        "/datum/base\n    var/p=1\n    var/p=2\n",
        "/datum/base/proc/p()\n/datum/base/child/proc/p()\n",
    ] {
        assert!(prepare(source).is_err());
    }
}

#[test]
fn diagnostic_unknown_settings_preserve_raw_prefix_but_never_admit_compilation() {
    let text="/proc/unknown_setting_probe()\n    set ordinary_unknown = 1\n    set spacemanDMM_typo in list(1)\n    return 0\n";
    let source=Source{bytes:text.as_bytes().to_vec(),owners:Default::default()};
    let executor=dm_exec::BuildExecutor::new(1).unwrap();
    assert!(super::super::build(Path::new("diagnostic_native.dme"),&source,&Default::default(),1).is_err(),"strict compilation still rejects raw unknown settings");
    let prepared=prepare(text).unwrap();
    let view=prepared.source_view().unwrap();
    assert!(view.receipt().errors().is_empty());
    assert!(!view.receipt().settings_compilable());
    let body=view.archive().parse(0).unwrap();
    assert!(body.statement_body().parsed().statements.len()>=2,"original Set statements survive for diagnostic checking");
    drop(body);
    assert!(prepared.try_into_compilable().is_err());
    let mut state=RetainedSemanticTree::one_shot();
    let prepared=super::super::build_for_checker_diagnostics_with_state(Path::new("diagnostic_native.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(&mut state)).unwrap();
    assert!(prepared.try_into_compilable_retained(&mut state).is_err(),"checker-only header facts cannot be adopted by ordinary compilation");
    assert!(super::super::build_with_executor_and_semantic_state(Path::new("diagnostic_native.dme"),&source,&Default::default(),FrontendConfig{workers:1,engine:None,observer:None},None,&executor,Some(&mut state)).is_err(),"diagnostic retained header facts never satisfy strict compiler cache lookup");
}
