use super::*;
use dm_codegen_byond::initializer::{lower_assignment_views, AssignmentView, InitializerContext};
use dm_ir::{InitializerTarget, ResolveQuery, ResolvedMeaning, SymbolId};
struct Host(u128);
impl Resolver for Host {
    fn domain_version(&self, _: dm_ir::ReadDomain) -> Option<u128> {
        Some(self.0)
    }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::Ancestry(owner) => ResolvedMeaning::Symbols(vec![owner]),
            ResolveQuery::VarStorage { owner, name } => ResolvedMeaning::Slot {
                symbol: name,
                owner,
                name,
            },
            ResolveQuery::GlobalVar(name) => ResolvedMeaning::Member {
                owner: SymbolId::of("/"),
                name,
                fingerprint: 1,
                data: std::sync::Arc::new(dm_ir::DeclarationMeaning::default()),
            },
            ResolveQuery::DeclaredVarType { .. } => ResolvedMeaning::DeclaredType(None),
            ResolveQuery::RuntimeType(path) => ResolvedMeaning::Symbol(path),
            ResolveQuery::Resource(path) => ResolvedMeaning::Resource {
                path,
                content: self.0,
            },
            _ => ResolvedMeaning::Unsupported(query),
        }
    }
}
#[test]
fn assembled_resource_reads_invalidate_and_shifted_current_roots_match_fresh() {
    let store = InitializerAssemblies::default();
    let key = receipts::Binding::fixture(b"fixture-group-exact-current-semantic-key");
    store.retain_keys(&[key.clone()]);
    let mut symbols = SymbolTable::default();
    for name in ["/", "value", "asset.dat"] {
        symbols.intern(name).unwrap();
    }
    let target = InitializerTarget::Shared {
        slot: SymbolId::of("value"),
        owner: SymbolId::of("/"),
        name: SymbolId::of("value"),
    };
    let mut root = dm_syntax::parse_expression("'asset.dat'").expr.unwrap();
    let first = Host(11);
    let roots = [AssignmentView {
        source_site: dm_ir::InitializerSite::Declaration,
                target: &target,
        lexical_owner: SymbolId::of("/"),
        value: &root,
        occurrence: dm_syntax::Span::new(0, 0),
    }];
    let recorder = crate::lowering_memo::RecordingResolver::new(&first);
    let context = || InitializerContext {
        symbols: &symbols,
        resource_search_context: None,
        debug: None,
    };
    let code = lower_assignment_views(&roots, context(), &recorder).unwrap();
    store.remember(&key, &code, &roots, &recorder);
    assert!(store
        .lookup_with_current_roots(
            &key,
            1,
            |_| panic!("plain admitted assembly must not prepare AST roots"),
            &symbols,
            &first
        )
        .is_some());
    assert!(store
        .lookup_with_current_roots(
            &key,
            2,
            |_| panic!("root count must decline before AST binding"),
            &symbols,
            &first
        )
        .is_none());
    root.span = dm_syntax::Span::new(500, 511);
    let current = [AssignmentView {
        source_site: dm_ir::InitializerSite::Declaration,
                target: &target,
        lexical_owner: SymbolId::of("/"),
        value: &root,
        occurrence: dm_syntax::Span::new(0, 0),
    }];
    let replay = store.lookup(&key, &current, &symbols, &first).unwrap();
    let cold = lower_assignment_views(&current, context(), &first).unwrap();
    assert_eq!(replay.procedure, cold.procedure);
    assert_eq!(replay.resources, cold.resources);
    assert!(store.lookup(&key, &current, &symbols, &Host(12)).is_none());
}

#[test]
fn nested_certified_admission_records_transitive_reads_in_assembly_ledger() {
    let host = Host(7);
    let query = ResolveQuery::Resource(SymbolId::of("asset.dat"));
    let nested = dm_session::ArtifactStore::current_revision();
    nested.insert_with(
        std::sync::Arc::from(b"fragment".as_slice()),
        vec![crate::lowering_memo::ResolverRead {
            domain: query.domain(),
            query,
            answer: host.resolve(query),
        }],
        vec![(query.domain(), 7)],
        1,
        || (),
    );
    let recorder = crate::lowering_memo::RecordingResolver::new(&host);
    let wrapped = AssemblyHost {
        original: &host,
        recorder: Some(&recorder),
    };
    assert!(nested.lookup(b"fragment", &wrapped).is_some());
    assert!(recorder.reads().iter().any(|read| read.query == query));
}

#[test]
fn ordered_group_and_current_token_roster_answers_are_exact_key_inputs() {
    use crate::initializer_policy::{
        ClassifiedInitializers, ClassifiedWrite, DefaultValue, Phase, RuntimeGroup,
    };
    let owner = SymbolId::of("/");
    let write = |ordinal, name: &str| ClassifiedWrite {
        source_ordinal: ordinal,
        write: dm_ir::InitializerWrite {
            source_site: dm_ir::InitializerSite::Declaration,
            target: InitializerTarget::Shared {
                slot: SymbolId::of(name),
                owner,
                name: SymbolId::of(name),
            },
            lexical_owner: owner,
            lexical_procedure: None,
            value: dm_ir::InitializerValue::Expression(dm_ir::SymbolicExpression {
                tokens: Vec::new().into(),
            }),
            declared_array: None,
            declaration_flags: Some(1),
        },
        default: DefaultValue::InitializerExpression {
            token: 12,
            canonical: std::sync::Arc::from(b"exact-token".as_slice()),
        },
        phase: Some(Phase::Runtime),
        runtime_value: None,
    };
    let mut classified = ClassifiedInitializers {
        accepted: Vec::new(),
        writes: vec![write(0, "a"), write(1, "b")],
        groups: vec![RuntimeGroup {
            declaration_presence: None,
            receiver: None,
            writes: vec![0, 1],
        }],
    };
    let fragments = classified
        .writes
        .iter()
        .map(|write| {
            (
                write.source_ordinal,
                receipts::Binding::fragment(
                    write.source_ordinal,
                    receipts::FragmentInputs {
                        write: write.write.clone(),
                        shape: receipts::Shape::Expression,
                        policy: 7,
                        resource_context: None,
                        debug_enabled: true,
                        accepted: None,
                    },
                ),
            )
        })
        .collect();
    let original = current_keys(&classified, &fragments).unwrap();
    classified.groups[0].writes.reverse();
    assert_ne!(current_keys(&classified, &fragments).unwrap(), original);
    classified.groups[0].writes.reverse();
    if let DefaultValue::InitializerExpression { token, .. } = &mut classified.writes[0].default {
        *token = 13;
    }
    assert_ne!(current_keys(&classified, &fragments).unwrap(), original);
    if let DefaultValue::InitializerExpression { token, .. } = &mut classified.writes[0].default {
        *token = 12;
    }
    classified.groups[0].receiver = Some(SymbolId::of("/datum/receiver"));
    assert_ne!(current_keys(&classified, &fragments).unwrap(), original);
}

#[test]
fn earlier_unrelated_receiver_preserves_assembly_locator_and_admission() {
    use crate::initializer_policy::{ClassifiedInitializers, RuntimeGroup};
    let mut classified = ClassifiedInitializers {
        accepted: Vec::new(),
        writes: Vec::new(),
        groups: vec![RuntimeGroup {
            declaration_presence: None,
            receiver: Some(SymbolId::of("/datum/current")),
            writes: Vec::new(),
        }],
    };
    let fragments = std::collections::HashMap::new();
    let old = current_keys(&classified, &fragments).unwrap().remove(0);
    let store = receipts::Store::<()>::current_revision();
    store.insert_with(
        std::sync::Arc::clone(&old.key),
        receipts::reads(&old, Vec::new()),
        Vec::new(),
        1,
        || (),
    );
    classified.groups.insert(
        0,
        RuntimeGroup {
            declaration_presence: None,
            receiver: Some(SymbolId::of("/datum/earlier")),
            writes: Vec::new(),
        },
    );
    let keys = current_keys(&classified, &fragments).unwrap();
    store.retain_current_keys(keys.iter().map(|binding| binding.key.as_ref()));
    let current = &keys[1];
    assert_eq!(old.key, current.key);
    assert!(store
        .lookup(
            &current.key,
            &receipts::Host {
                binding: current,
                resolver: &Host(7)
            }
        )
        .is_some());
    classified.groups.push(classified.groups[1].clone());
    let duplicate_keys = current_keys(&classified, &fragments).unwrap();
    assert_ne!(current.key, duplicate_keys[2].key);
}
