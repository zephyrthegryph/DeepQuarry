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
        "{}/obj/outer{{child=/obj/inner{{amount={amount}}}}}",
        " ".repeat(padding)
    );
    let expression = dm_syntax::parse_expression(&text).expr.unwrap();
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
    let reference = SymRef::Instance(SymbolId::of(&descriptor.alias()));
    (
        reference,
        CapturedModifiedInstance {
            descriptor,
            field_origins: vec![Some(0)],
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
    for text in ["/", "/obj/outer", "/obj/inner", "child", "amount"] {
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
