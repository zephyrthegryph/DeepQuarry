use super::*;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M};
use dm_syntax::ExprKind;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
struct Host(u128);
impl Resolver for Host {
    fn resolve(&self, query: Q) -> M {
        match query {
            Q::RuntimeType(path) => M::Symbol(path),
            Q::Resource(path) => M::Resource {
                path,
                content: self.0,
            },
            _ => M::Unsupported(query),
        }
    }
}
fn frontend(text: &'static str) -> dm_tree::frontend::ColdFrontend {
    dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source(text),
        &Default::default(),
        1,
    )
    .unwrap()
}
fn seed(frontend: &dm_tree::frontend::ColdFrontend, host: &Host) -> PreparedSeed {
    let arena = dm_tree::frontend::BodyArena::new_typed(
        frontend,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    arena
        .with_parsed(&frontend.bodies[0], |parsed| {
            let dm_syntax::StatementKind::Return(Some(expr)) =
                &parsed.statement_body().unwrap().parsed().statements[0].kind
            else {
                panic!("expected return");
            };
            let expr = match &expr.kind {
                ExprKind::Group(inner) => inner.as_ref(),
                _ => expr,
            };
            let ExprKind::ObjectInitializer { object, fields } = &expr.kind else {
                panic!("expected modifier");
            };
            let ExprKind::TypePath(path) = &object.kind else {
                panic!("expected type");
            };
            let captured = dm_codegen_byond::lower_resolver::ModifiedCaptureContext {
                resolver: host,
                symbols: frontend.snapshot.tree.symbols(),
                resource_search_context: None,
            }
            .capture(path, "/", fields, Some(0), expr.span)
            .unwrap();
            prepare_seed(
                SymRef::Instance(SymbolId::of(&captured.descriptor.alias())),
                &captured,
                &DebugOrigins {
                    entries: vec![DebugOrigin {
                        semantic_path: "old.dm".into(),
                        line: 2,
                    }],
                },
            )
            .unwrap()
        })
        .unwrap()
}
#[test]
fn modifier_recipe_reissues_current_ast_and_resources_after_source_shift() {
    let old = frontend("/obj/base\n/proc/p()\n    return (/obj/base{amount=1;icon='x.dmi'})\n");
    let moved =
        frontend("\n\n/obj/base\n/proc/p()\n    return (/obj/base{amount=1;icon='x.dmi'})\n");
    let previous = seed(&old, &Host(7));
    let recipe = previous.source_recipe(old.bodies[0].expanded_span).unwrap();
    let mut wire_only = previous.clone();
    wire_only.captured.source_span = None;
    assert!(wire_only
        .source_recipe(old.bodies[0].expanded_span)
        .is_none());
    let mut foreign_site = previous.clone();
    foreign_site.captured.source_span = Some(Span::new(0, 1));
    assert!(foreign_site
        .source_recipe(old.bodies[0].expanded_span)
        .is_none());
    let mut different_field_origin = previous.clone();
    different_field_origin.captured.field_origins[0] = Some(1);
    assert!(different_field_origin
        .source_recipe(old.bodies[0].expanded_span)
        .is_none());

    let current_debug = DebugOrigins {
        entries: vec![DebugOrigin {
            semantic_path: "current.dm".into(),
            line: 5,
        }],
    };
    let arena = dm_tree::frontend::BodyArena::new_typed(
        &moved,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    arena
        .with_parsed(&moved.bodies[0], |parsed| {
            let wire_bytes = dm_wire::encode(91, &recipe.disk_evidence()).unwrap();
            let wire: RecipeWire<'_> =
                dm_wire::decode_borrowed(91, &wire_bytes, wire_bytes.len()).unwrap();
            let from_wire = wire
                .reissue(
                    parsed,
                    &moved,
                    &Host(7),
                    moved.snapshot.tree.symbols(),
                    &current_debug,
                    None,
                    SymbolId::of("/"),
                )
                .unwrap();
            assert_eq!(
                from_wire.captured.descriptor.canonical_bytes(),
                previous.captured.descriptor.canonical_bytes()
            );
            assert_eq!(
                from_wire.captured.source_span.unwrap().start,
                previous.captured.source_span.unwrap().start + moved.bodies[0].expanded_span.start
                    - old.bodies[0].expanded_span.start
            );
            assert!(wire
                .reissue(
                    parsed,
                    &moved,
                    &Host(8),
                    moved.snapshot.tree.symbols(),
                    &current_debug,
                    None,
                    SymbolId::of("/")
                )
                .is_none());
            assert!(wire
                .reissue(
                    parsed,
                    &moved,
                    &Host(7),
                    moved.snapshot.tree.symbols(),
                    &current_debug,
                    Some(17),
                    SymbolId::of("/")
                )
                .is_none());
            let current = recipe
                .reissue(
                    parsed,
                    &moved,
                    &Host(7),
                    moved.snapshot.tree.symbols(),
                    &current_debug,
                )
                .unwrap();
            assert_eq!(
                current.captured.descriptor.canonical_bytes(),
                previous.captured.descriptor.canonical_bytes()
            );
            let shift = moved.bodies[0].expanded_span.start - old.bodies[0].expanded_span.start;
            for ((_, old), (_, new)) in previous
                .captured
                .descriptor
                .fields()
                .iter()
                .zip(current.captured.descriptor.fields())
            {
                assert_eq!(new.span.start, old.span.start + shift);
                assert_eq!(new.span.end, old.span.end + shift);
            }
            assert_eq!(current.origins.entries.len(), 3);
            assert!(current
                .origins
                .entries
                .iter()
                .all(|origin| origin == &current_debug.entries[0]));
            assert!(recipe
                .reissue(
                    parsed,
                    &moved,
                    &Host(8),
                    moved.snapshot.tree.symbols(),
                    &current_debug
                )
                .is_none());
            let mut wrong_site = recipe.clone();
            wrong_site.relative_span.start += 1;
            assert!(wrong_site
                .reissue(
                    parsed,
                    &moved,
                    &Host(7),
                    moved.snapshot.tree.symbols(),
                    &current_debug
                )
                .is_none());
        })
        .unwrap();
    let raw = dm_tree::frontend::BodyArena::new(&moved);
    raw.with_parsed(&moved.bodies[0], |parsed| {
        assert!(recipe
            .reissue(
                parsed,
                &moved,
                &Host(7),
                moved.snapshot.tree.symbols(),
                &current_debug
            )
            .is_none());
    })
    .unwrap();
}

#[test]
fn unparenthesized_return_modifier_remains_an_unsupported_frontend_form() {
    let result = dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source("/obj/base\n/proc/p()\n    return /obj/base{amount=1}\n"),
        &Default::default(),
        1,
    );
    let errors = match result {
        Ok(_) => panic!("unsupported block must not issue a frontend"),
        Err(errors) => errors,
    };
    assert!(errors.iter().any(|error| error
        .message
        .contains("a block following a return expression has unsupported semantics")));
}

#[test]
fn resource_free_disk_recipe_allows_current_project_context_but_resource_proof_is_exact() {
    let current = frontend("/obj/base\n/proc/p()\n    return (/obj/base{amount=1})\n");
    let previous = seed(&current, &Host(7));
    let recipe = previous
        .source_recipe(current.bodies[0].expanded_span)
        .unwrap();
    let debug = DebugOrigins {
        entries: vec![DebugOrigin {
            semantic_path: "project.dme".into(),
            line: 3,
        }],
    };
    let arena = dm_tree::frontend::BodyArena::new_typed(
        &current,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    arena
        .with_parsed(&current.bodies[0], |parsed| {
            let mut wire = recipe.disk_evidence();
            assert_eq!(wire.resource_context, None);
            let reissue = |wire: &RecipeWire<'_>, context| {
                wire.reissue(
                    parsed,
                    &current,
                    &Host(7),
                    current.snapshot.tree.symbols(),
                    &debug,
                    context,
                    SymbolId::of("/"),
                )
            };
            assert!(reissue(&wire, Some(41)).is_some());
            // A transported positive resource authority is never substituted by
            // another current project context (even before canonical recapture).
            wire.resource_context = Some(41);
            assert!(reissue(&wire, Some(42)).is_none());
            assert!(reissue(&wire, None).is_none());
        })
        .unwrap();
}
