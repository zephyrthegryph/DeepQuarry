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
    let key = b"fixture-group-exact-current-semantic-key";
    store.retain_keys(&[key.to_vec()]);
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
    store.remember(key, &code, &roots, &recorder);
    root.span = dm_syntax::Span::new(500, 511);
    let current = [AssignmentView {
        target: &target,
        lexical_owner: SymbolId::of("/"),
        value: &root,
        occurrence: dm_syntax::Span::new(0, 0),
    }];
    let replay = store.lookup(key, &current, &symbols, &first).unwrap();
    let cold = lower_assignment_views(&current, context(), &first).unwrap();
    assert_eq!(replay.procedure, cold.procedure);
    assert_eq!(replay.resources, cold.resources);
    assert!(store.lookup(key, &current, &symbols, &Host(12)).is_none());
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
        writes: vec![write(0, "a"), write(1, "b")],
        groups: vec![RuntimeGroup {
            receiver: None,
            writes: vec![0, 1],
        }],
    };
    let fragments =
        std::collections::HashMap::from([(0, b"a-fragment".to_vec()), (1, b"b-fragment".to_vec())]);
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
