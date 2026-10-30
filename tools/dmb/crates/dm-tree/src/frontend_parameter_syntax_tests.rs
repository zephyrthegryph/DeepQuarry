//! Exact ORIGINAL archive/profile signature authority, without a copied model.
use super::*;
use std::{path::Path, sync::Arc};
mod reference_hierarchy {
    use crate as dm_tree;
    include!("../../dm-analysis/examples/support/reference_hierarchy.rs");
}
struct Source(dm_preprocess::AcquiredSource);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("original acquisition required".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(
        &self,
        _: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
fn archive(source: &str) -> Arc<BodyArchive> {
    archive_with_state(source, None)
}
fn archive_with_state(source: &str, state: Option<&mut RetainedSemanticTree>) -> Arc<BodyArchive> {
    let source = Source(dm_preprocess::AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let front = build_with_executor_and_semantic_state_for_policy(
        Path::new("parameter-source.dm"),
        &source,
        &Default::default(),
        FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
        None,
        &executor,
        state,
        true,
    )
    .unwrap();
    front.body_archive().unwrap()
}
#[test]
fn original_parameter_receipt_is_profile_bound_and_does_not_mutate_runtime_signature() {
    let archive=archive("/proc/check(static/datum/D, datum/static/embedded, SpacemanDMM_private/datum/private)\n    return\n");
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let body = archive.parse(0).unwrap();
    let before = Arc::clone(
        &archive
            .tree()
            .member(body.occurrence().member)
            .unwrap()
            .metadata,
    );
    let receipt = body.checker_parameters(profile).unwrap();
    let hints = receipt
        .entries()
        .unwrap()
        .iter()
        .map(|p| p.type_path(archive.expanded_source()).unwrap())
        .collect::<Vec<_>>();
    assert_eq!(
        hints,
        [
            Some("/datum".into()),
            Some("/datum/static".into()),
            Some("/datum".into())
        ]
    );
    assert!(Arc::ptr_eq(
        &before,
        &archive
            .tree()
            .member(body.occurrence().member)
            .unwrap()
            .metadata
    ));
    assert!(body
        .checker_parameters(dm_ir::PackedU128::new(profile.get() ^ 1))
        .is_err());
}
#[test]
fn original_parameter_receipt_rejects_absolute_runtime_header_declaration() {
    let archive = archive("/datum/other\n/proc/check(/datum/marker)\n    return\n");
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let body = archive.parse(0).unwrap();
    assert!(body
        .checker_parameters(profile)
        .unwrap_err()
        .contains("absolute parameter-header"));
}
#[test]
fn parameter_source_view_rejects_foreign_callable_tree_and_copied_entry() {
    let source = "/proc/first(datum/D)\n    return\n/proc/second(datum/D)\n    return\n";
    let current = archive(source);
    let profile = current.tree().checker_builtin_profile().unwrap();
    let first = current.parse(0).unwrap();
    let second = current.parse(1).unwrap();
    let view = first.checker_parameters(profile).unwrap();
    assert!(view
        .require_for(current.tree(), second.occurrence())
        .is_err());
    let copied_occurrence = first.occurrence().clone();
    assert!(view
        .require_for(current.tree(), &copied_occurrence)
        .is_err());
    let another = archive(source);
    assert!(view
        .require_for(another.tree(), first.occurrence())
        .is_err());
    let copied = dm_syntax::parse_proc_with_origins_at_span(source, first.header().span).unwrap();
    assert!(view
        .type_path(&copied.parameters.entries().unwrap()[0])
        .is_err());
}

#[test]
fn same_semantic_tree_and_member_do_not_authorize_another_real_source_occurrence() {
    // Native retained semantic reuse is proved for body-only edits. Header
    // spelling changes legitimately rebuild declaration ownership even when
    // runtime hints normalize equal; they cannot establish this test premise.
    let source = "/proc/check(datum/D)\n    return 1\n";
    let changed = "/proc/check(datum/D)\n    return 12345\n";
    let mut state = RetainedSemanticTree::default();
    let first = archive_with_state(source, Some(&mut state));
    let second = archive_with_state(changed, Some(&mut state));
    assert!(
        std::ptr::eq(first.tree(), second.tree()),
        "fixture requires actual semantic reuse, not merely equal trees"
    );
    let a = first.parse(0).unwrap();
    let b = second.parse(0).unwrap();
    assert_eq!(a.occurrence().member, b.occurrence().member);
    assert_eq!(a.header().header, b.header().header);
    assert_ne!(first.expanded_source(), second.expanded_source());
    assert!(
        !std::ptr::eq(a.occurrence(), b.occurrence()),
        "real fresh source issuance must have a distinct occurrence owner"
    );
    let profile = first.tree().checker_builtin_profile().unwrap();
    let view = a.checker_parameters(profile).unwrap();
    assert!(view.require_for(second.tree(), b.occurrence()).is_err());
    assert!(view.require_for(first.tree(), a.occurrence()).is_ok());
}
