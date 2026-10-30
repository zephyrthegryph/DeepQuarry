#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;

fn build<P: dm_preprocess::SourceProvider>(
    project: &std::path::Path,
    provider: &P,
    defines: &std::collections::BTreeMap<String, String>,
    workers: usize,
) -> Result<dm_tree::frontend::ColdFrontend, Vec<dm_tree::frontend::Diagnostic>> {
    dm_tree::frontend::build_with_config(
        project,
        provider,
        defines,
        dm_tree::frontend::FrontendConfig {
            workers,
            engine: Some(&reference_hierarchy::seed()),
            observer: None,
        },
    )
}
use super::*;
use crate::value_program::Key;
use dm_ir::SymbolId;
use std::{
    path::Path,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Mutex,
    },
};

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn archive() -> Arc<BodyArchive> {
    let frontend = build(
        Path::new("p.dme"),
        &Source("/datum/item\n/datum/holder\n    var/saved = 1\n/proc/scalar(x)\n    return x + 1\n/proc/object()\n    return new /datum/item\n"),
        &Default::default(), 1,
    ).unwrap();
    frontend.body_archive().unwrap()
}

#[derive(Debug, Default)]
struct OneProofHost {
    proof: Mutex<Option<Arc<ArchiveValueProof>>>,
    computes: AtomicUsize,
}
impl ArchiveValueQueries for OneProofHost {
    fn value_proof(
        &self,
        input: &Arc<ArchiveValueInput>,
    ) -> Result<Arc<ArchiveValueProof>, Unsupported> {
        let mut slot = self.proof.lock().unwrap();
        if let Some(proof) = &*slot {
            return Ok(Arc::clone(proof));
        }
        self.computes.fetch_add(1, Ordering::Relaxed);
        let proof = input.compute()?;
        *slot = Some(Arc::clone(&proof));
        Ok(proof)
    }
}

#[test]
fn archived_value_proof_reuses_one_solution_across_policy_views() {
    let archive = archive();
    let input = ArchiveValueInput::new(Arc::clone(&archive), &[]);
    let host = OneProofHost::default();
    let first = input.obtain(&host).unwrap();
    let second = input.obtain(&host).unwrap();
    assert!(Arc::ptr_eq(&first, &second));
    let one = Values::from_archive_input(&input, first).unwrap();
    let two = Values::from_archive_input(&input, second).unwrap();
    assert!(
        std::ptr::eq(&*one, &*two),
        "policy views share equations and SCC solution"
    );
    assert_eq!(host.computes.load(Ordering::Relaxed), 1);
    let direct = Values::build_archive(&archive, archive.tree(), &[]).unwrap();
    assert_eq!(one.equations, direct.equations);
    assert_eq!(one.solution, direct.solution);
    let roster = archive.callables();
    for (ordinal, member) in roster.members().iter().enumerate() {
        let id = roster.identity(ordinal).unwrap();
        assert_eq!(
            one.is_value(&Key::Return(id)),
            id.name == SymbolId::of("scalar")
        );
        assert!(archive.tree().member(*member).is_some());
    }
    assert!(input.compute().unwrap().budget_charge() >= 4096);
}

#[test]
fn archived_value_proof_rejects_foreign_archive_and_config_even_for_equal_source() {
    let source = archive();
    let input = ArchiveValueInput::new(Arc::clone(&source), &[]);
    let host = OneProofHost::default();
    let proof = input.obtain(&host).unwrap();
    let foreign = ArchiveValueInput::new(archive(), &[]);
    assert_ne!(input.key(), foreign.key());
    assert!(proof.validate_for(&foreign).is_err());
    assert!(
        foreign.obtain(&host).is_err(),
        "host cannot rebind a cached proof"
    );
    assert!(Values::from_archive_input(&foreign, Arc::clone(&proof)).is_err());
    let config = ArchiveValueInput::new(source, &["/datum/item".into()]);
    assert!(proof.validate_for(&config).is_err());
    assert!(Values::from_archive_input(&config, proof).is_err());
}

#[test]
fn archive_value_input_normalizes_policy_without_retaining_archive_in_result() {
    let archive = archive();
    let weak = Arc::downgrade(&archive);
    let input = ArchiveValueInput::new(archive, &["/z".into(), "/a".into(), "/z".into()]);
    assert_eq!(
        input.exempt_types(),
        &[String::from("/a"), String::from("/z")]
    );
    let proof = input.compute().unwrap();
    let values = Values::from_archive_input(&input, Arc::clone(&proof)).unwrap();
    assert!(values
        .validate_exempt_types(&["/z".into(), "/a".into()])
        .is_ok());
    assert!(values.validate_exempt_types(&[]).is_err());
    drop(values);
    drop(input);
    assert!(
        weak.upgrade().is_none(),
        "owned summaries do not retain source/model owners"
    );
    assert!(proof.input.upgrade().is_none());
}

#[derive(Debug)]
struct CheckedOriginalSyntaxHost {
    failures: AtomicUsize,
}
impl dm_tree::frontend::BodySyntaxQueries for CheckedOriginalSyntaxHost {
    fn syntax(
        &self,
        input: &Arc<dm_tree::frontend::BodySyntaxInput>,
    ) -> Result<Arc<dm_tree::frontend::BodySyntax>, dm_tree::frontend::Diagnostic> {
        input.parse().map(Arc::new)
    }
    fn syntax_checked(
        &self,
        input: &Arc<dm_tree::frontend::BodySyntaxInput>,
    ) -> Result<Arc<dm_tree::frontend::BodySyntax>, dm_tree::frontend::BodySyntaxFailure> {
        if self.failures.swap(0, Ordering::Relaxed) > 0 {
            return Err(dm_tree::frontend::BodySyntaxFailure::Operational(
                std::io::Error::from_raw_os_error(1450),
            ));
        }
        input
            .parse()
            .map(Arc::new)
            .map_err(dm_tree::frontend::BodySyntaxFailure::Syntax)
    }
}
#[test]
fn checked_value_inference_preserves_actual_body_io_and_shares_original_algorithm() {
    let host = Arc::new(CheckedOriginalSyntaxHost {
        failures: AtomicUsize::new(1),
    });
    let frontend = build(
        Path::new("checked-value.dme"),
        &Source("/proc/scalar(x)\n    return x+1\n"),
        &Default::default(),
        1,
    )
    .unwrap()
    .with_body_queries(host);
    let archive = frontend.body_archive().unwrap();
    let input = ArchiveValueInput::new(Arc::clone(&archive), &[]);
    match input
        .compute_checked()
        .err()
        .expect("actual original-body demand failure")
    {
        ValueQueryFailure::Operational(error) => assert_eq!(error.raw_os_error(), Some(1450)),
        other => panic!("actual IO downgraded: {other:?}"),
    }
    let checked = input.compute_checked().unwrap();
    let independent = input.compute().unwrap();
    let first = Values::from_archive_input(&input, checked).unwrap();
    let second = Values::from_archive_input(&input, independent).unwrap();
    assert_eq!(first.equations, second.equations);
    assert_eq!(first.solution, second.solution);
    assert_eq!(
        dm_ir::Resolver::source_owner(first.resolver()),
        dm_ir::Resolver::source_owner(archive.tree())
    );
}
#[test]
fn checked_value_compatibility_host_still_checks_exact_proof_issuance() {
    let input = ArchiveValueInput::new(archive(), &[]);
    let host = OneProofHost::default();
    let original = input.obtain_checked(&host).unwrap();
    assert!(Arc::ptr_eq(&original, &input.obtain(&host).unwrap()));
    let foreign = ArchiveValueInput::new(archive(), &[]);
    assert!(matches!(
        foreign.obtain_checked(&host),
        Err(ValueQueryFailure::Unsupported(_))
    ));
}
