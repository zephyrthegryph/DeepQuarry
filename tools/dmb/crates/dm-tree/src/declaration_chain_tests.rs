//! Structural receipts use the existing name issuer. Production content currently
//! covers headers/settings, not bodies; no body-edit optimization is implied.
use super::*;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver};

fn build_source(
    source: &str,
    retained: &owner_normalization::RetainedNormalization,
) -> SemanticTree {
    let ast = dm_syntax::parse(source);
    let adapted = adapter::from_ast(&ast, SymbolTable::default(), dm_ir::FileId(0), 0, 0).unwrap();
    let rows: Vec<_> = adapted.skeletons.iter().cloned().collect();
    let (index, _) = declaration_contributions::KeyedDeclarations::capture(None, &rows).unwrap();
    build_with_intrinsic_members_indexed(
        adapted.symbols,
        rows.as_slice().into(),
        &[],
        &[],
        false,
        Some((&index, retained)),
    )
    .unwrap()
}
fn query() -> Q {
    Q::DeclarationChain {
        owner: SymbolId::of("/datum/base/child"),
        name: SymbolId::of("read"),
        verb: false,
    }
}
#[test]
fn structural_chain_keeps_body_edits_but_rejects_metadata_and_chain_changes() {
    let retained = owner_normalization::RetainedNormalization::default();
    let original =
        "/datum/base/proc/read(x=1)\n    return x\n/datum/base/child/read(x=1)\n    return ..()\n";
    let first = build_source(original, &retained);
    let answer = Resolver::resolve(&first, query());
    let version = first.domain_version(query().domain()).unwrap();
    let M::Members(rows) = &answer else {
        panic!("source chain required")
    };
    assert_eq!(rows.len(), 2);
    assert!(
        matches!(&rows[0], M::Declaration { identity, definition: dm_ir::ProcedureDefinition::Implicit, previous: Some(_), .. } if identity.owner == SymbolId::of("/datum/base/child") && identity.occurrence == 0)
    );
    let moved = build_source(
        &format!(
            "// current provenance\n{}",
            original.replace("return x", "return x+7")
        ),
        &retained,
    );
    assert_eq!(Resolver::resolve(&moved, query()), answer);
    assert_eq!(moved.domain_version(query().domain()), Some(version));
    let executable = Q::OverrideChain {
        owner: SymbolId::of("/datum/base/child"),
        name: SymbolId::of("read"),
        verb: false,
    };
    // The adapter already excludes executable bodies from node.content.
    assert_eq!(
        Resolver::resolve(&first, executable),
        Resolver::resolve(&moved, executable)
    );
    for changed in [
        original.replace("read(x=1)", "read(x=2)"),
        format!("{original}/datum/base/child/read(x=1)\n    return 8\n"),
        original.replace(
            "/datum/base/child/read(x=1)",
            "/datum/base/child/proc/read(x=1)",
        ),
        format!(
            "{original}/datum/alternate\n/datum/base/child\n    parent_type = /datum/alternate\n"
        ),
    ] {
        let current = build_source(&changed, &retained);
        assert_ne!(
            Resolver::resolve(&current, query()).canonical_bytes(),
            answer.canonical_bytes()
        );
        assert_ne!(current.domain_version(query().domain()), Some(version));
    }
}
#[test]
fn structural_chain_missing_and_intrinsic_answers_fail_closed() {
    let retained = owner_normalization::RetainedNormalization::default();
    let tree = build_source("/datum/base/child\n", &retained);
    assert_eq!(Resolver::resolve(&tree, query()), M::Unsupported(query()));
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/datum/base/child").unwrap();
    let name = symbols.intern("read").unwrap();
    let intrinsic = IntrinsicMember {
        owner,
        name,
        kind: MemberKind::Proc,
        instance_storage_proven: false,
        shared_owner: None,
    };
    let tree = build_with_intrinsic_members(
        symbols,
        &[Skeleton::Type {
            path: owner,
            explicit_parent: None,
        }],
        &[],
        &[intrinsic],
    )
    .unwrap();
    assert_eq!(Resolver::resolve(&tree, query()), M::Unsupported(query()));
}

#[test]
fn actual_frontend_already_keeps_both_chain_answers_across_body_edits() {
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut state = frontend::RetainedSemanticTree::default();
    let mut build = |text| {
        frontend::build_with_executor_and_semantic_state(
            std::path::Path::new("chain.dme"),
            &Source(text),
            &Default::default(),
            frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            Some(&mut state),
        )
        .unwrap()
    };
    let first = build(
        "/datum/base/proc/read(x=1)\n    return x\n/datum/base/child/read(x=1)\n    return ..()\n",
    );
    let old = Q::OverrideChain {
        owner: SymbolId::of("/datum/base/child"),
        name: SymbolId::of("read"),
        verb: false,
    };
    let structural_version = first.snapshot.tree.domain_version(query().domain());
    let old_version = first.snapshot.tree.domain_version(old.domain());
    let current = build("// shifted current source\n/datum/base/proc/read(x=1)\n    return x+9\n/datum/base/child/read(x=1)\n    return ..()+2\n");
    // The admitted immutable semantic tree is shared even though body issuance changes.
    assert!(Arc::ptr_eq(&first.snapshot.tree, &current.snapshot.tree));
    for query in [query(), old] {
        assert_eq!(
            Resolver::resolve(first.snapshot.tree.as_ref(), query),
            Resolver::resolve(current.snapshot.tree.as_ref(), query)
        );
    }
    assert_eq!(
        current.snapshot.tree.domain_version(query().domain()),
        structural_version
    );
    assert_eq!(
        current.snapshot.tree.domain_version(old.domain()),
        old_version
    );
    assert_ne!(
        first.body(&first.bodies[0]).unwrap().children[0].header,
        current.body(&current.bodies[0]).unwrap().children[0].header
    );
}

#[test]
fn explicit_content_inputs_remain_visible_only_to_legacy_chain() {
    let source = "/datum/base/proc/read()\n    return 1\n/datum/base/child\n";
    let ast = dm_syntax::parse(source);
    let adapted = adapter::from_ast(&ast, SymbolTable::default(), dm_ir::FileId(0), 0, 0).unwrap();
    let first = build(adapted.symbols.clone(), &adapted.skeletons).unwrap();
    let mut rows = adapted.skeletons;
    for row in &mut rows {
        if let Skeleton::Member {
            kind: MemberKind::Proc,
            content,
            ..
        } = row
        {
            *content ^= 1;
        }
    }
    // Generic producers can explicitly supply content independently of metadata.
    let changed = build(adapted.symbols, &rows).unwrap();
    let old = Q::OverrideChain {
        owner: SymbolId::of("/datum/base/child"),
        name: SymbolId::of("read"),
        verb: false,
    };
    assert_ne!(
        Resolver::resolve(&first, old),
        Resolver::resolve(&changed, old)
    );
    assert_eq!(
        Resolver::resolve(&first, query()),
        Resolver::resolve(&changed, query())
    );
}
