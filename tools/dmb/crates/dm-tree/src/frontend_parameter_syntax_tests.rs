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
fn original_parameter_receipt_issues_absolute_type_and_only_real_formals() {
    let source="/datum/other\n/proc/check(datum/D,/datum/marker,actual_power=1)\n    return actual_power\n";
    let archive = archive(source);
    let profile = archive.tree().checker_builtin_profile().unwrap();
    let body = archive.parse(0).unwrap();
    let view = body.checker_parameters(profile).unwrap();
    assert_eq!(
        view.entries()
            .unwrap()
            .iter()
            .map(|p| view.name(p).unwrap())
            .collect::<Vec<_>>(),
        ["D", "actual_power"]
    );
    assert_eq!(
        view.absolute_declarations().unwrap()[0]
            .written_path(archive.expanded_source())
            .unwrap(),
        "/datum/marker"
    );
    assert!(archive
        .tree()
        .lookup_type(dm_ir::SymbolId::of("/datum/marker"))
        .is_some());
    let metadata = archive
        .tree()
        .member(body.occurrence().member)
        .unwrap()
        .metadata
        .procedure
        .as_deref()
        .unwrap();
    assert_eq!(metadata.signature.parameters.len(), 2);
    assert!(body
        .source_header_expressions()
        .unwrap()
        .default(1)
        .unwrap()
        .is_some());
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

#[test]
fn header_roots_borrow_exact_original_owner_and_selected_metadata() {
    let current = archive("/proc/p(x=(1+2), y=3 in list(4), z)\n    return x\n");
    let body = current.parse(0).unwrap();
    let view = body.source_header_expressions().unwrap();
    let entry = &body.parameter_storage().entries().unwrap()[0];
    let canonical = entry.expressions().unwrap().unwrap().default().unwrap();
    assert!(std::ptr::eq(view.default(0).unwrap().unwrap(), canonical));
    assert!(view.in_source(1).unwrap().is_some());
    assert!(view.default(2).unwrap().is_none());
    assert!(view.default(3).is_err());
    view.require_for(current.tree(), body.occurrence(), view.selected_metadata())
        .unwrap();
    let copied = view.selected_metadata().clone();
    assert!(view
        .require_for(current.tree(), body.occurrence(), &copied)
        .unwrap_err()
        .contains("metadata owner"));
    let occurrence = body.occurrence().clone();
    assert!(view
        .require_for(current.tree(), &occurrence, view.selected_metadata())
        .is_err());
    let foreign = archive("/proc/p(x=(1+2), y=3 in list(4), z)\n    return x\n");
    assert!(view
        .require_for(foreign.tree(), body.occurrence(), view.selected_metadata())
        .is_err());
}
#[test]
fn optional_header_refusal_never_becomes_an_empty_root_view() {
    let archive = archive(&format!(
        "/proc/p(x={})\n    return 1\n",
        "!".repeat(300) + "1"
    ));
    let body = archive.parse(0).unwrap();
    assert!(body.source_parameters().is_ok());
    assert!(body.source_header_expressions().is_err());
}

#[test]
fn header_expression_tokens_preserve_original_leading_comments_and_unicode() {
    let current =
        archive("/proc/p(x=/*first*/(1+2), y=\"é漢\" in /*source*/list(4))\n    return x\n");
    let body = current.parse(0).unwrap();
    let view = body.source_header_expressions().unwrap();
    assert!(view.default(0).unwrap().is_some());
    assert!(view.default(1).unwrap().is_some());
    assert!(view.in_source(1).unwrap().is_some());
}

#[test]
fn original_header_handle_survives_consumed_parsed_wrapper_without_copy_or_query() {
    let provider = Source(dm_preprocess::AcquiredSource::from_original_bytes(
        b"/proc/p(x=1+2)\n    return x\n".to_vec(),
        (),
    ));
    #[derive(Debug)]
    struct Observe(Arc<std::sync::atomic::AtomicUsize>);
    impl BodySyntaxQueries for Observe {
        fn syntax(&self, input: &Arc<BodySyntaxInput>) -> Result<Arc<BodySyntax>, Diagnostic> {
            self.0.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            input.parse().map(Arc::new)
        }
    }
    let parses = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let frontend = build(
        Path::new("header-handle.dm"),
        &provider,
        &Default::default(),
        1,
    )
    .unwrap()
    .with_body_queries(Arc::new(Observe(Arc::clone(&parses))));
    let parsed = frontend.parse_body(&frontend.bodies[0]).unwrap();
    let storage = parsed.parameter_storage().clone();
    let root = storage.entries().unwrap()[0]
        .expressions()
        .unwrap()
        .unwrap()
        .default()
        .unwrap() as *const dm_syntax::Expr;
    let handle = parsed.share_header_expressions().unwrap();
    assert!(storage.same_owner(handle.storage()));
    let (item, statements) = parsed.into_parts();
    drop(item);
    drop(statements);
    assert_eq!(parses.load(std::sync::atomic::Ordering::Relaxed), 1);
    let view = handle.view().unwrap();
    assert_eq!(
        view.default(0).unwrap().unwrap() as *const dm_syntax::Expr,
        root
    );
    assert_eq!(parses.load(std::sync::atomic::Ordering::Relaxed), 1);
    view.require_for(
        &frontend.snapshot.tree,
        &frontend.bodies[0],
        view.selected_metadata(),
    )
    .unwrap();
    let copied = frontend.bodies[0].clone();
    assert!(view
        .require_for(&frontend.snapshot.tree, &copied, view.selected_metadata())
        .is_err());
}
