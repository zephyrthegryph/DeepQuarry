use super::*;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M};

struct Host {
    inner_exists: bool,
}
impl Resolver for Host {
    fn resolve(&self, query: Q) -> M {
        match query {
            Q::RuntimeType(path) if path != SymbolId::of("/obj/inner") || self.inner_exists => {
                M::Symbol(path)
            }
            Q::HasMemberVar { .. } => M::Presence(true),
            _ => M::Unsupported(query),
        }
    }
}

fn seed(padding: usize, amount: u32) -> (SymRef, CapturedModifiedInstance, DebugOrigins) {
    let text = format!(
        "{}/obj/outer{{child=/obj/inner{{amount={amount}}};zz_unused=9}}",
        " ".repeat(padding)
    );
    let parsed = dm_syntax::parse_expression(&text);
    assert!(parsed.diagnostics.is_empty(), "{:#?}", parsed.diagnostics);
    let expression = parsed.expr.unwrap();
    let dm_syntax::ExprKind::ObjectInitializer { fields, .. } = &expression.kind else {
        panic!("object")
    };
    let descriptor = dm_ir::ModifiedInstance::capture_with_policy(
        SymbolId::of("/obj/outer"),
        SymbolId::of("/"),
        None,
        fields,
        |_| None,
        None,
    )
    .unwrap();
    assert_eq!(descriptor.fields().len(), 2);
    let reference = SymRef::Instance(SymbolId::of(&descriptor.alias()));
    (
        reference,
        CapturedModifiedInstance {
            descriptor,
            field_origins: vec![Some(0); 2],
            origin: Some(0),
            source_span: Some(expression.span),
        },
        DebugOrigins {
            entries: vec![DebugOrigin {
                semantic_path: format!("include-{padding}.dm").into(),
                line: 7 + padding as u32,
            }],
        },
    )
}

fn code_bytes(artifact: &InitializationArtifact) -> Vec<u8> {
    dm_codegen_byond::encoder::freeze_proc(&artifact.code.procedure.code)
        .unwrap()
        .code()
        .canonical_bytes()
        .to_vec()
}

#[test]
fn nested_modified_replay_reissues_current_fields_and_preserves_fifo_and_fresh_code() {
    let mut symbols = SymbolTable::default();
    for text in [
        "/",
        "/obj/outer",
        "/obj/inner",
        "child",
        "amount",
        "zz_unused",
    ] {
        symbols.intern(text).unwrap();
    }
    let host = Host { inner_exists: true };
    let store = crate::initializer_lowering::InitializerFragments::default();
    let old = [seed(0, 1)];
    let first = collect_owned_prepared_retained(
        std::iter::empty(),
        std::iter::empty(),
        &old,
        &symbols,
        &host,
        None,
        Some(&store),
    )
    .unwrap();
    assert_eq!(first.artifacts.len(), 2);
    assert_eq!(
        store.recomputed.load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    let current = [seed(100, 1)];
    let reused = collect_owned_prepared_retained(
        std::iter::empty(),
        std::iter::empty(),
        &current,
        &symbols,
        &host,
        None,
        Some(&store),
    )
    .unwrap();
    assert_eq!(store.hits.load(std::sync::atomic::Ordering::Relaxed), 2);
    let binding = crate::initializer_lowering::receipts::Binding::modified(
        current[0].0,
        &current[0].1.descriptor,
        None,
    );
    let mut roots = retained::CurrentFields::new(current[0].1.descriptor.fields(), None);
    assert_eq!(roots.prepared_indexes().count(), 0);
    let mut requested = Vec::new();
    assert!(store
        .modified(&binding, &symbols, &host, |index| {
            requested.push(index);
            roots.root(index)
        })
        .is_some());
    assert_eq!(requested, [0]);
    assert_eq!(roots.prepared_indexes().collect::<Vec<_>>(), [0]);
    let first_root = roots.root(0).unwrap();
    let repeated_root = roots.root(0).unwrap();
    assert!(Arc::ptr_eq(&first_root, &repeated_root));
    assert_eq!(roots.prepared_indexes().collect::<Vec<_>>(), [0]);
    let fresh = collect_with_defaults(std::iter::empty(), &current, &symbols, &host, None).unwrap();
    for (actual, expected) in reused.artifacts.iter().zip(&fresh.artifacts) {
        assert_eq!(actual.identity, expected.identity);
        assert_eq!(actual.debug_origins, expected.debug_origins);
        assert_eq!(code_bytes(actual), code_bytes(expected));
    }
    let inner = &reused.descriptors[1].1;
    assert_eq!(inner.descriptor.runtime_type(), SymbolId::of("/obj/inner"));
    assert!(inner.source_span.unwrap().start >= 100);
    assert!(inner.descriptor.fields()[0].1.span.start >= 100);
    // The leaf has no current descriptors and shares its immutable code owner.
    assert!(Arc::ptr_eq(
        first.artifacts[1].code.code_owner(),
        reused.artifacts[1].code.code_owner()
    ));
    // Every nested runtime type is revalidated, not only the outer input bytes.
    assert!(collect_owned_prepared_retained(
        std::iter::empty(),
        std::iter::empty(),
        &current,
        &symbols,
        &Host {
            inner_exists: false
        },
        None,
        Some(&store)
    )
    .is_err());
    let changed = [seed(100, 2)];
    let changed_reused = collect_owned_prepared_retained(
        std::iter::empty(),
        std::iter::empty(),
        &changed,
        &symbols,
        &host,
        None,
        Some(&store),
    )
    .unwrap();
    let changed_fresh =
        collect_with_defaults(std::iter::empty(), &changed, &symbols, &host, None).unwrap();
    assert_ne!(
        code_bytes(&reused.artifacts[1]),
        code_bytes(&changed_reused.artifacts[1])
    );
    assert_eq!(
        changed_reused
            .artifacts
            .iter()
            .map(code_bytes)
            .collect::<Vec<_>>(),
        changed_fresh
            .artifacts
            .iter()
            .map(code_bytes)
            .collect::<Vec<_>>()
    );
    // Removed nested programs are pruned from the same current owner.
    collect_owned_prepared_retained(
        std::iter::empty(),
        std::iter::empty(),
        &[],
        &symbols,
        &host,
        None,
        Some(&store),
    )
    .unwrap();
    let mut entries = 0;
    store.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Store { entries: count, .. } = view {
            entries = count;
        }
    });
    assert_eq!(entries, 0);
}

#[test]
fn modified_fragment_hit_verifies_same_fresh_producer_after_origin_shift() {
    let mut symbols = SymbolTable::default();
    for text in [
        "/",
        "/obj/outer",
        "/obj/inner",
        "child",
        "amount",
        "zz_unused",
    ] {
        symbols.intern(text).unwrap();
    }
    let host = Host { inner_exists: true };
    let store = crate::initializer_lowering::InitializerFragments::default();
    let policy = crate::lowering_memo::VerifyPolicy::all();
    let old = [seed(0, 7)];
    collect_owned_prepared_retained_verified(
        std::iter::empty(),
        std::iter::empty(),
        &old,
        &symbols,
        &host,
        None,
        Some(&store),
        Some(&policy),
    )
    .unwrap();
    let current = [seed(100, 7)];
    let reused = collect_owned_prepared_retained_verified(
        std::iter::empty(),
        std::iter::empty(),
        &current,
        &symbols,
        &host,
        None,
        Some(&store),
        Some(&policy),
    )
    .unwrap();
    let fresh = collect_with_defaults(std::iter::empty(), &current, &symbols, &host, None).unwrap();
    assert_eq!(store.modified_fragment_verification_counts(), (2, 0));
    assert_eq!(reused.artifacts.len(), fresh.artifacts.len());
    for (actual, fresh) in reused.artifacts.iter().zip(&fresh.artifacts) {
        assert_eq!(code_bytes(actual), code_bytes(fresh));
        assert_eq!(actual.debug_origins, fresh.debug_origins);
    }
}
