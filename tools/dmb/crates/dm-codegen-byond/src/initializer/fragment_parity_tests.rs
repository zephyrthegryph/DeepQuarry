//! Independent whole-scope oracle for the continuation producer.
use super::*;
use crate::{DebugSourceProvider, SymbolId};
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::VarStorage { owner, name }
                if owner == SymbolId::of("/")
                    && [SymbolId::of("first"), SymbolId::of("second")].contains(&name) =>
            {
                ResolvedMeaning::Slot {
                    symbol: name,
                    owner,
                    name,
                }
            }
            ResolveQuery::GlobalVar(name)
                if [SymbolId::of("first"), SymbolId::of("second")].contains(&name) =>
            {
                ResolvedMeaning::Member {
                    owner: SymbolId::of("/"),
                    name,
                    fingerprint: name.bits() as u128,
                    data: std::sync::Arc::new(dm_ir::DeclarationMeaning::default()),
                }
            }
            ResolveQuery::DeclaredVarType { .. } => ResolvedMeaning::DeclaredType(None),
            ResolveQuery::RuntimeType(path) => ResolvedMeaning::Symbol(path),
            ResolveQuery::GlobalVar(_) => ResolvedMeaning::Missing,
            _ => ResolvedMeaning::Unsupported(query),
        }
    }
}
#[test]
fn resolver_failure_uses_issued_assignment_coordinate() {
    let mut symbols = SymbolTable::default();
    for text in ["/", "first", "unknown_call"] {
        symbols.intern(text).unwrap();
    }
    let target = InitializerTarget::Shared {
        slot: SymbolId::of("first"), owner: SymbolId::of("/"), name: SymbolId::of("first"),
    };
    let value = dm_syntax::parse_expression("unknown_call()").expr.unwrap();
    let assignments = [AssignmentView {
        source_site: dm_ir::InitializerSite::Declaration,
        target: &target, lexical_owner: SymbolId::of("/"), value: &value,
        occurrence: dm_syntax::Span::new(7, 7),
    }];
    let error = lower_assignment_views(&assignments, InitializerContext {
        symbols: &symbols, resource_search_context: None, debug: None,
    }, &Host).err().unwrap();
    let InitializerError::Lowering(errors) = error else { panic!("expected a typed lowering error") };
    assert_eq!(errors.len(), 1);
    assert_eq!(errors[0].span, Some(crate::LowerSpan { start: 7, end: 7 }));
    assert_eq!(errors[0].kind, crate::LowerErrorKind::UnsupportedModel);
}

#[test]
fn modified_instance_fragments_are_fresh_only_and_keep_current_first_origin() {
    let mut symbols = SymbolTable::default();
    for text in ["/", "first", "second", "/obj/item", "amount"] {
        symbols.intern(text).unwrap();
    }
    let span = dm_syntax::Span::new(0, 10);
    let value = dm_syntax::Expr {
        span,
        kind: dm_syntax::ExprKind::ObjectInitializer {
            object: Box::new(dm_syntax::Expr {
                span,
                kind: dm_syntax::ExprKind::TypePath("/obj/item".into()),
            }),
            fields: vec![(
                "amount".into(),
                dm_syntax::parse_expression("1").expr.unwrap(),
            )],
        },
    };
    let targets = ["first", "second"].map(|name| InitializerTarget::Shared {
        slot: SymbolId::of(name),
        owner: SymbolId::of("/"),
        name: SymbolId::of(name),
    });
    let views = targets
        .iter()
        .enumerate()
        .map(|(index, target)| AssignmentView {
            source_site: dm_ir::InitializerSite::Declaration,
                target,
            lexical_owner: SymbolId::of("/"),
            value: &value,
            occurrence: dm_syntax::Span::new(index, index),
        })
        .collect::<Vec<_>>();
    let context = || InitializerContext {
        symbols: &symbols,
        resource_search_context: None,
        debug: Some(&Debug),
    };
    let oracle = lower_assignment_views(&views, context(), &Host).unwrap();
    let prepared = prepare_assignment_group(&views, context(), &Host).unwrap();
    let fragments = (0..2)
        .map(|index| prepared.lower_fragment(index, &Host).unwrap())
        .collect::<Vec<_>>();
    assert!(fragments.iter().all(|fragment| !fragment.can_retain()));
    let actual = prepared.assemble(fragments).unwrap();
    assert_eq!(actual.procedure, oracle.procedure);
    assert_eq!(actual.modified_instances.len(), 1);
    for (key, captured) in &actual.modified_instances {
        let expected = &oracle.modified_instances[key];
        assert_eq!(
            captured.descriptor.canonical_bytes(),
            expected.descriptor.canonical_bytes()
        );
        assert_eq!(captured.origin, expected.origin);
        assert_eq!(captured.field_origins, expected.field_origins);
        assert_eq!(captured.source_span, expected.source_span);
    }
}
struct Debug;
impl DebugSourceProvider for Debug {
    fn entry_ordinal(&self) -> Result<u32, String> {
        Ok(0)
    }
    fn ordinal(&self, offset: usize) -> Result<u32, String> {
        if offset < 2 {
            Ok(offset as u32)
        } else {
            Err("outside current assignments".into())
        }
    }
}
#[test]
fn shared_fragments_match_whole_scope_code_rosters_sidecars_and_debug() {
    for sources in [
        ["1 ? \"first\" : \"second\"", "0 ? \"second\" : \"last\""],
        ["list(\"same\", 2)", "list(\"same\", 3)"],
        ["1 || 2", "3 && 4"],
    ] {
        let mut symbols = SymbolTable::default();
        for text in ["/", "first", "second"] {
            symbols.intern(text).unwrap();
        }
        let targets = ["first", "second"].map(|name| InitializerTarget::Shared {
            slot: SymbolId::of(name),
            owner: SymbolId::of("/"),
            name: SymbolId::of(name),
        });
        let expressions = sources.map(|source| dm_syntax::parse_expression(source).expr.unwrap());
        let views = targets
            .iter()
            .zip(&expressions)
            .enumerate()
            .map(|(index, (target, value))| AssignmentView {
                source_site: dm_ir::InitializerSite::Declaration,
                target,
                lexical_owner: SymbolId::of("/"),
                value,
                occurrence: dm_syntax::Span::new(index, index),
            })
            .collect::<Vec<_>>();
        for debug in [None, Some(&Debug as &dyn DebugSourceProvider)] {
            let context = || InitializerContext {
                symbols: &symbols,
                resource_search_context: None,
                debug,
            };
            let oracle = lower_assignment_views(&views, context(), &Host).unwrap();
            let prepared = prepare_assignment_group(&views, context(), &Host).unwrap();
            let fragments = (0..views.len())
                .map(|index| prepared.lower_fragment(index, &Host).unwrap())
                .collect::<Vec<_>>();
            let actual = prepared.assemble(fragments).unwrap();
            assert_eq!(actual.procedure, oracle.procedure);
            assert_eq!(actual.slots, oracle.slots);
            assert_eq!(actual.resources, oracle.resources);
            assert_eq!(actual.instances, oracle.instances);
            assert_eq!(actual.procedure_values, oracle.procedure_values);
            assert_eq!(actual.procedure_statics, oracle.procedure_statics);
            assert!(actual.modified_instances.is_empty());
        }
    }
}
#[test]
fn every_target_is_admitted_before_any_fragment_expression() {
    let mut symbols = SymbolTable::default();
    for text in ["/", "first", "absent"] {
        symbols.intern(text).unwrap();
    }
    let targets = ["first", "absent"].map(|name| InitializerTarget::Shared {
        slot: SymbolId::of(name),
        owner: SymbolId::of("/"),
        name: SymbolId::of(name),
    });
    let expressions =
        ["unknown_call()", "1"].map(|source| dm_syntax::parse_expression(source).expr.unwrap());
    let views = targets
        .iter()
        .zip(&expressions)
        .enumerate()
        .map(|(index, (target, value))| AssignmentView {
            source_site: dm_ir::InitializerSite::Declaration,
                target,
            lexical_owner: SymbolId::of("/"),
            value,
            occurrence: dm_syntax::Span::new(index, index),
        })
        .collect::<Vec<_>>();
    let context = || InitializerContext {
        symbols: &symbols,
        resource_search_context: None,
        debug: None,
    };
    let oracle = lower_assignment_views(&views, context(), &Host)
        .err()
        .unwrap();
    let actual = prepare_assignment_group(&views, context(), &Host)
        .err()
        .unwrap();
    assert_eq!(format!("{actual:?}"), format!("{oracle:?}"));
    assert!(!matches!(actual, InitializerError::Lowering(_)));
}
