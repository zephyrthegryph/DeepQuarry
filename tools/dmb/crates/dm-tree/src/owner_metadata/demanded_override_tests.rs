//! Exact named chain certificates share the existing demand store/lifecycle.
use super::*;
use dm_ir::{ResolveQuery as Q, Resolver};

fn build(
    rows: &[Skeleton],
    retained: &crate::owner_normalization::RetainedNormalization,
) -> SemanticTree {
    let mut symbols = SymbolTable::default();
    for spelling in [
        "/datum/base",
        "/datum/child",
        "/datum/alternate",
        "read",
        "unrelated",
        "missing",
    ] {
        symbols.intern(spelling).unwrap();
    }
    let (index, _) =
        crate::declaration_contributions::KeyedDeclarations::capture(None, rows).unwrap();
    crate::build_with_intrinsic_members_indexed(
        symbols,
        rows.into(),
        &[],
        &[],
        false,
        Some((&index, retained)),
    )
    .unwrap()
}
fn callable(owner: &str, name: &str, content: u128, mode: DefinitionMode) -> Skeleton {
    Skeleton::Member {
        owner: SymbolId::of(owner),
        name: SymbolId::of(name),
        kind: MemberKind::Proc,
        mode,
        metadata: Arc::new(MemberMetadata::default()),
        content,
    }
}
fn query(name: &str) -> Q {
    Q::OverrideChain {
        owner: SymbolId::of("/datum/child"),
        name: SymbolId::of(name),
        verb: false,
    }
}
#[test]
fn named_chain_reuses_siblings_but_tracks_content_override_and_inheritance() {
    let retained = crate::owner_normalization::RetainedNormalization::default();
    let rows = vec![
        Skeleton::Type {
            path: SymbolId::of("/datum/base"),
            explicit_parent: None,
        },
        Skeleton::Type {
            path: SymbolId::of("/datum/child"),
            explicit_parent: Some(SymbolId::of("/datum/base")),
        },
        callable("/datum/base", "read", 1, DefinitionMode::Declare),
    ];
    let first = build(&rows, &retained);
    let answer = Resolver::resolve(&first, query("read"));
    let token = first.domain_version(query("read").domain()).unwrap();
    let absent_token = first.domain_version(query("missing").domain()).unwrap();
    let mut sibling = rows.clone();
    sibling.push(callable(
        "/datum/base",
        "unrelated",
        3,
        DefinitionMode::Declare,
    ));
    let added = build(&sibling, &retained);
    assert_eq!(Resolver::resolve(&added, query("read")), answer);
    assert_eq!(added.domain_version(query("read").domain()), Some(token));
    assert_eq!(
        added.domain_version(query("missing").domain()),
        Some(absent_token)
    );
    let removed = build(&rows, &retained);
    assert_eq!(removed.domain_version(query("read").domain()), Some(token));
    for changed in [
        {
            let mut changed = rows.clone();
            if let Skeleton::Member { content, .. } = &mut changed[2] {
                *content = 9;
            }
            changed
        },
        {
            let mut changed = rows.clone();
            changed.push(callable(
                "/datum/child",
                "read",
                4,
                DefinitionMode::Override,
            ));
            changed
        },
        {
            let mut changed = rows.clone();
            changed.push(Skeleton::Type {
                path: SymbolId::of("/datum/alternate"),
                explicit_parent: None,
            });
            if let Skeleton::Type {
                explicit_parent, ..
            } = &mut changed[1]
            {
                *explicit_parent = Some(SymbolId::of("/datum/alternate"));
            }
            changed
        },
    ] {
        let current = build(&changed, &retained);
        assert_ne!(Resolver::resolve(&current, query("read")), answer);
        assert_ne!(current.domain_version(query("read").domain()), Some(token));
    }
    let mut present = rows.clone();
    present.push(callable(
        "/datum/base",
        "missing",
        5,
        DefinitionMode::Declare,
    ));
    let current = build(&present, &retained);
    assert_ne!(
        current.domain_version(query("missing").domain()),
        Some(absent_token)
    );
    // Old snapshots retain their issued proof, never publish a new current one.
    assert_eq!(first.domain_version(query("read").domain()), Some(token));
}

#[test]
fn frontend_body_text_is_separate_from_override_chain_meaning() {
    let retained = crate::owner_normalization::RetainedNormalization::default();
    let source =
        "/datum/base/proc/read()\n    return 1\n/datum/child\n    parent_type = /datum/base\n";
    let from_source = |source: &str| {
        let ast = dm_syntax::parse(source);
        let adapted =
            crate::adapter::from_ast(&ast, SymbolTable::default(), dm_ir::FileId(0), 0, 0).unwrap();
        let rows: Vec<_> = adapted.skeletons.iter().cloned().collect();
        let (index, _) =
            crate::declaration_contributions::KeyedDeclarations::capture(None, &rows).unwrap();
        crate::build_with_intrinsic_members_indexed(
            adapted.symbols,
            rows.as_slice().into(),
            &[],
            &[],
            false,
            Some((&index, &retained)),
        )
        .unwrap()
    };
    let first = from_source(source);
    let answer = Resolver::resolve(&first, query("read"));
    let token = first.domain_version(query("read").domain()).unwrap();
    let current = from_source(&source.replace("return 1", "return 2"));
    assert_eq!(Resolver::resolve(&current, query("read")), answer);
    assert_eq!(current.domain_version(query("read").domain()), Some(token));
    // Current body/source receipts, outside this query, remain mandatory for
    // executable lowering. The adapter's content means headers/settings today.
}
