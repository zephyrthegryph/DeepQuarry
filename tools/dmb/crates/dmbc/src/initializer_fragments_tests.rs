use super::*;
use dm_codegen_byond::initializer::{prepare_assignment_group, AssignmentView, InitializerContext};
use dm_ir::{
    InitializerTarget, InitializerValue, InitializerWrite, ResolveQuery, ResolvedMeaning, SymbolId,
    SymbolTable,
};
struct Host {
    resource: u128,
}
impl Resolver for Host {
    fn resolve(&self, q: ResolveQuery) -> ResolvedMeaning {
        match q {
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
                content: self.resource,
            },
            _ => ResolvedMeaning::Unsupported(q),
        }
    }
}
fn write(source: &str, symbols: &mut SymbolTable) -> InitializerWrite {
    let expression = dm_ir::SymbolicExpression {
        tokens: dm_syntax::lex(source)
            .tokens
            .into_iter()
            .filter(|token| {
                !matches!(
                    token.kind,
                    dm_syntax::TokenKind::Whitespace
                        | dm_syntax::TokenKind::Newline
                        | dm_syntax::TokenKind::Comment
                )
            })
            .map(|token| dm_ir::ExpressionToken {
                kind: token.kind,
                text: symbols.intern(&token.text).unwrap(),
                relative_span: token.span,
            })
            .collect::<Vec<_>>()
            .into(),
    };
    InitializerWrite {
        source_site: dm_ir::InitializerSite::Declaration,
            target: InitializerTarget::Shared {
            slot: SymbolId::of("value"),
            owner: SymbolId::of("/"),
            name: SymbolId::of("value"),
        },
        lexical_owner: SymbolId::of("/"),
        lexical_procedure: None,
        value: InitializerValue::Expression(expression),
        declared_array: None,
        declaration_flags: Some(1),
    }
}
#[test]
fn resource_read_change_invalidates_only_its_retained_continuation_and_matches_cold() {
    let store = InitializerFragments::default();
    let mut symbols = SymbolTable::default();
    for text in ["/", "value"] {
        symbols.intern(text).unwrap();
    }
    let write = write("'asset.dat'", &mut symbols);
    let value = dm_syntax::parse_expression("'asset.dat'").expr.unwrap();
    let runtime = RuntimeValue::Expression(std::sync::Arc::new(value.clone()));
    let key = semantic_key(&write, &runtime, 7, None, false);
    store.retain_keys(&HashMap::from([(0, key.clone())]));
    let views = [AssignmentView {
        source_site: dm_ir::InitializerSite::Declaration,
                target: &write.target,
        lexical_owner: write.lexical_owner,
        value: &value,
        occurrence: dm_syntax::Span::new(0, 0),
    }];
    for resource in [11, 11, 12] {
        let host = Host { resource };
        let context = || InitializerContext {
            symbols: &symbols,
            resource_search_context: None,
            debug: None,
        };
        let prepared = prepare_assignment_group(&views, context(), &host).unwrap();
        let fragment = store
            .fragment(&key, &prepared, 0, &write, &host)
            .unwrap()
            .unwrap();
        let actual = prepared.assemble(vec![fragment]).unwrap();
        let cold = dm_codegen_byond::initializer::lower_assignment_views(&views, context(), &host)
            .unwrap();
        assert_eq!(actual.procedure, cold.procedure);
        assert_eq!(actual.resources, cold.resources);
    }
    assert_eq!(store.hits.load(Ordering::Relaxed), 1);
    assert_eq!(store.recomputed.load(Ordering::Relaxed), 2);
    let mut retained = 0;
    store.values.visit_storage(|view| {
        if matches!(view, dm_session::ObservedArtifactStorageView::Entry { .. }) {
            retained += 1;
        }
    });
    assert_eq!(
        retained, 1,
        "changed read replaces current variant rather than retaining history"
    );
    store.retain_keys(&HashMap::new());
    assert!(store
        .values
        .lookup(
            &key.key,
            &receipts::Host {
                binding: &key,
                resolver: &Host { resource: 12 }
            }
        )
        .is_none());
}
#[test]
fn sized_dimensions_and_resource_search_context_are_semantic_inputs() {
    let mut symbols = SymbolTable::default();
    let write = write("1", &mut symbols);
    let first = RuntimeValue::SizedArray(vec![2u16, 3].into());
    let second = RuntimeValue::SizedArray(vec![2u16, 4].into());
    assert_ne!(
        semantic_key(&write, &first, 7, None, false),
        semantic_key(&write, &second, 7, None, false)
    );
    assert_ne!(
        semantic_key(&write, &first, 7, None, false),
        semantic_key(&write, &first, 7, Some(1), false)
    );
    assert_ne!(
        semantic_key(&write, &first, 7, None, false),
        semantic_key(&write, &first, 8, None, false)
    );
    assert_ne!(
        semantic_key(&write, &first, 7, None, false),
        semantic_key(&write, &first, 7, None, true)
    );
}

#[test]
fn retained_modifier_reissues_current_ast_after_old_source_is_dropped() {
    let store = InitializerFragments::default();
    let mut symbols = SymbolTable::default();
    for text in ["/", "value", "/obj/item", "amount"] {
        symbols.intern(text).unwrap();
    }
    let write = write("(/obj/item{amount=1})", &mut symbols);
    let host = Host { resource: 1 };
    for start in [0, 500] {
        let mut field = dm_syntax::parse_expression("1").expr.unwrap();
        field.span = dm_syntax::Span::new(start + 20, start + 21);
        let value = dm_syntax::Expr {
            span: dm_syntax::Span::new(start, start + 30),
            kind: dm_syntax::ExprKind::ObjectInitializer {
                object: Box::new(dm_syntax::Expr {
                    span: dm_syntax::Span::new(start, start + 9),
                    kind: dm_syntax::ExprKind::TypePath("/obj/item".into()),
                }),
                fields: vec![("amount".into(), field)],
            },
        };
        let key = semantic_key(
            &write,
            &RuntimeValue::Expression(std::sync::Arc::new(value.clone())),
            7,
            None,
            false,
        );
        store.retain_keys(&HashMap::from([(0, key.clone())]));
        let views = [AssignmentView {
            source_site: dm_ir::InitializerSite::Declaration,
                target: &write.target,
            lexical_owner: write.lexical_owner,
            value: &value,
            occurrence: dm_syntax::Span::new(start, start + 30),
        }];
        let context = || InitializerContext {
            symbols: &symbols,
            resource_search_context: None,
            debug: None,
        };
        let prepared = prepare_assignment_group(&views, context(), &host).unwrap();
        let fragment = store
            .fragment(&key, &prepared, 0, &write, &host)
            .unwrap()
            .unwrap();
        let current = prepared.assemble(vec![fragment]).unwrap();
        let fresh = dm_codegen_byond::initializer::lower_assignment_views(&views, context(), &host)
            .unwrap();
        assert_eq!(current.procedure, fresh.procedure);
        let captured = current.modified_instances.values().next().unwrap();
        assert_eq!(captured.source_span, Some(value.span));
        assert_eq!(
            captured.descriptor.fields()[0].1.span,
            dm_syntax::Span::new(start + 20, start + 21)
        );
        store.values.visit_storage(|view| {
            if let dm_session::ObservedArtifactStorageView::Entry { value, .. } = view {
                assert!(value.code.code().modified_instances.is_empty());
                assert_eq!(value.recipes.len(), 1);
            }
        });
    }
    assert_eq!(store.hits.load(Ordering::Relaxed), 1);
    assert_eq!(store.recomputed.load(Ordering::Relaxed), 1);
}

struct CurrentDebug;
impl dm_codegen_byond::DebugSourceProvider for CurrentDebug {
    fn entry_ordinal(&self) -> Result<u32, String> {
        Ok(0)
    }
    fn ordinal(&self, index: usize) -> Result<u32, String> {
        if index < 2 {
            Ok(index as u32)
        } else {
            Err("current assignment origin missing".into())
        }
    }
}
#[test]
fn retained_modifier_binds_current_group_debug_ordinal_after_an_inserted_write() {
    let store = InitializerFragments::default();
    let mut symbols = SymbolTable::default();
    for text in ["/", "value", "other", "/obj/item", "amount"] {
        symbols.intern(text).unwrap();
    }
    let write = write("(/obj/item{amount=1})", &mut symbols);
    let host = Host { resource: 1 };
    for moved in [false, true] {
        let start = if moved { 500 } else { 0 };
        let value = dm_syntax::Expr {
            span: dm_syntax::Span::new(start, start + 30),
            kind: dm_syntax::ExprKind::ObjectInitializer {
                object: Box::new(dm_syntax::Expr {
                    span: dm_syntax::Span::new(start, start + 9),
                    kind: dm_syntax::ExprKind::TypePath("/obj/item".into()),
                }),
                fields: vec![(
                    "amount".into(),
                    dm_syntax::Expr {
                        span: dm_syntax::Span::new(start + 20, start + 21),
                        kind: dm_syntax::ExprKind::Literal("1".into()),
                    },
                )],
            },
        };
        let other = InitializerTarget::Shared {
            slot: SymbolId::of("other"),
            owner: SymbolId::of("/"),
            name: SymbolId::of("other"),
        };
        let literal = dm_syntax::parse_expression("3").expr.unwrap();
        let mut views = Vec::new();
        if moved {
            views.push(AssignmentView {
                source_site: dm_ir::InitializerSite::Declaration,
                target: &other,
                lexical_owner: write.lexical_owner,
                value: &literal,
                occurrence: dm_syntax::Span::new(0, 0),
            });
        }
        let index = views.len();
        views.push(AssignmentView {
            source_site: dm_ir::InitializerSite::Declaration,
                target: &write.target,
            lexical_owner: write.lexical_owner,
            value: &value,
            occurrence: dm_syntax::Span::new(index, index),
        });
        let key = semantic_key(
            &write,
            &RuntimeValue::Expression(std::sync::Arc::new(value.clone())),
            7,
            None,
            true,
        );
        store.retain_keys(&HashMap::from([(index, key.clone())]));
        let context = || InitializerContext {
            symbols: &symbols,
            resource_search_context: None,
            debug: Some(&CurrentDebug),
        };
        let prepared = prepare_assignment_group(&views, context(), &host).unwrap();
        let mut fragments = Vec::new();
        if moved {
            fragments.push(prepared.lower_fragment(0, &host).unwrap());
        }
        let issued = store
            .fragment_with_recipes(&key, &prepared, index, &write, &host)
            .unwrap()
            .unwrap();
        let admitted = issued
            .recipes
            .unwrap()
            .into_iter()
            .map(|recipe| (index, recipe.with_assignment_origin(index as u32)))
            .collect();
        fragments.push(issued.code);
        let current = prepared.assemble(fragments).unwrap();
        let fresh = dm_codegen_byond::initializer::lower_assignment_views(&views, context(), &host)
            .unwrap();
        assert_eq!(current.procedure, fresh.procedure);
        let captured = current.modified_instances.values().next().unwrap();
        let expected = fresh.modified_instances.values().next().unwrap();
        assert_eq!(captured.origin, Some(index as u32));
        assert_eq!(captured.origin, expected.origin);
        assert_eq!(captured.field_origins, expected.field_origins);
        assert_eq!(captured.source_span, Some(value.span));
        let assemblies = super::super::assemblies::InitializerAssemblies::default();
        let group_key = receipts::Binding::fixture(b"actual-fragment-recipe-handoff");
        assemblies.retain_keys(&[group_key.clone()]);
        let recorder = crate::lowering_memo::RecordingResolver::new(&host);
        assert!(assemblies
            .remember_with_recipes(&group_key, &current, &views, &recorder, Some(admitted))
            .is_some());
        let replay = assemblies
            .lookup(&group_key, &views, &symbols, &host)
            .unwrap();
        assert_eq!(replay.procedure, fresh.procedure);
        let replay_capture = replay.modified_instances.values().next().unwrap();
        assert_eq!(replay_capture.origin, expected.origin);
        assert_eq!(replay_capture.field_origins, expected.field_origins);
        assert_eq!(replay_capture.source_span, Some(value.span));
    }
    assert_eq!(store.hits.load(Ordering::Relaxed), 1);
    assert_eq!(store.recomputed.load(Ordering::Relaxed), 1);
}

#[test]
fn same_locator_declines_changed_current_flags_before_reusing_code() {
    let store = receipts::Store::<()>::current_revision();
    let mut symbols = SymbolTable::default();
    let first = write("1", &mut symbols);
    let runtime =
        RuntimeValue::Expression(Arc::new(dm_syntax::parse_expression("1").expr.unwrap()));
    let original = semantic_key(&first, &runtime, 7, None, false);
    let host = Host { resource: 11 };
    store.insert_with(
        Arc::clone(&original.key),
        receipts::reads(&original, Vec::new()),
        Vec::new(),
        1,
        || (),
    );
    assert!(store
        .lookup(
            &original.key,
            &receipts::Host {
                binding: &original,
                resolver: &host
            }
        )
        .is_some());
    let mut changed = first.clone();
    changed.declaration_flags = Some(3);
    let current = semantic_key(&changed, &runtime, 7, None, false);
    assert_eq!(original.key, current.key);
    assert!(store
        .lookup(
            &current.key,
            &receipts::Host {
                binding: &current,
                resolver: &host
            }
        )
        .is_none());
}

#[test]
fn earlier_unrelated_write_preserves_fragment_locator_and_real_hit() {
    use crate::initializer_policy::{
        ClassifiedInitializers, ClassifiedWrite, DefaultValue, Phase, RuntimeGroup,
    };
    let store = InitializerFragments::default();
    let mut symbols = SymbolTable::default();
    symbols.intern("/").unwrap();
    symbols.intern("value").unwrap();
    let target = write("'asset.dat'", &mut symbols);
    let expression = dm_syntax::parse_expression("'asset.dat'").expr.unwrap();
    let runtime = RuntimeValue::Expression(Arc::new(expression.clone()));
    let mut classified = ClassifiedInitializers {
        accepted: Vec::new(),
        writes: vec![ClassifiedWrite {
            source_ordinal: 0,
            write: target.clone(),
            default: DefaultValue::Scalar(dm_ir::SemanticValue::Null),
            phase: Some(Phase::Runtime),
            runtime_value: Some(runtime.clone()),
        }],
        groups: vec![RuntimeGroup {
            declaration_presence: None,
            receiver: None,
            writes: vec![0],
        }],
    };
    let original = current_keys(&classified, 7, None).unwrap();
    store.retain_keys(&original);
    let host = Host { resource: 11 };
    let roots = [AssignmentView {
        source_site: dm_ir::InitializerSite::Declaration,
                target: &target.target,
        lexical_owner: target.lexical_owner,
        value: &expression,
        occurrence: dm_syntax::Span::new(0, 0),
    }];
    let context = || InitializerContext {
        symbols: &symbols,
        resource_search_context: None,
        debug: None,
    };
    let prepared = prepare_assignment_group(&roots, context(), &host).unwrap();
    store
        .fragment(&original[&0], &prepared, 0, &target, &host)
        .unwrap()
        .unwrap();
    let mut unrelated = classified.writes[0].clone();
    unrelated.write.target = InitializerTarget::Shared {
        slot: SymbolId::of("unrelated"),
        owner: SymbolId::of("/"),
        name: SymbolId::of("unrelated"),
    };
    classified.writes[0].source_ordinal = 1;
    classified.writes.insert(0, unrelated);
    classified.groups[0].writes = vec![0, 1];
    let current = current_keys(&classified, 7, None).unwrap();
    assert_eq!(original[&0].key, current[&1].key);
    store.retain_keys(&current);
    let reused = store
        .fragment(&current[&1], &prepared, 0, &target, &host)
        .unwrap()
        .unwrap();
    let actual = prepared.assemble(vec![reused]).unwrap();
    let fresh =
        dm_codegen_byond::initializer::lower_assignment_views(&roots, context(), &host).unwrap();
    assert_eq!(actual.procedure, fresh.procedure);
    assert_eq!(actual.resources, fresh.resources);
    assert_eq!(store.hits.load(Ordering::Relaxed), 1);
    assert_eq!(store.recomputed.load(Ordering::Relaxed), 1);
}
