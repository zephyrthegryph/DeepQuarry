//! Current issued signature expressions use the same helper syntax container.
use super::*;
use dm_syntax::{Expr, ExprKind, Span, StatementKind};
pub(crate) fn current_header_modifier(
    frontend: &ColdFrontend,
    parsed: &dm_tree::frontend::ParsedBody<'_>,
    argument: u32,
    span: Span,
    symbols: &SymbolTable,
) -> Option<(Expr, DebugOrigins)> {
    frontend
        .validate_parsed_body(parsed, parsed.occurrence())
        .ok()?;
    let member = frontend.snapshot.tree.member(parsed.occurrence().member)?;
    let metadata = member.metadata.procedure.as_ref()?;
    let header = ProcedureHeader::from(parsed.item());
    if frontend.expanded.text.get(header.header_span.range()) != Some(header.header) {
        return None;
    }
    let absolute = source_offset(header, metadata, argument as usize).ok()?;
    let origin = frontend.location(absolute)?;
    let expression = metadata
        .signature
        .parameters
        .get(argument as usize)?
        .source_expression
        .as_ref()?
        .source_text(symbols)?;
    let container = syntax_container(&expression).ok()?;
    let statements = dm_syntax::parse_body_items(&container.children);
    if !statements.diagnostics.is_empty() || statements.statements.len() != 1 {
        return None;
    }
    let StatementKind::Return(Some(root)) = &statements.statements[0].kind else {
        return None;
    };
    fn find<'a>(expr: &'a Expr, span: Span, found: &mut Option<&'a Expr>, duplicate: &mut bool) {
        if expr.span == span && matches!(expr.kind, ExprKind::ObjectInitializer { .. }) {
            if found.replace(expr).is_some() {
                *duplicate = true;
            }
        }
        dm_syntax::for_each_expression_child(expr, |_, child| find(child, span, found, duplicate));
    }
    let mut found = None;
    let mut duplicate = false;
    find(root, span, &mut found, &mut duplicate);
    if duplicate {
        return None;
    }
    Some((
        found?.clone(),
        DebugOrigins {
            entries: vec![DebugOrigin {
                semantic_path: origin.semantic_path.clone(),
                line: u32::try_from(origin.line).ok()?,
            }],
        },
    ))
}

pub(crate) fn current_original_header_modifier<'a>(
    frontend: &ColdFrontend,
    parsed: &'a dm_tree::frontend::ParsedBody<'_>,
    argument: u32,
    relative: Span,
) -> Option<(&'a Expr, DebugOrigins)> {
    frontend
        .validate_parsed_body(parsed, parsed.occurrence())
        .ok()?;
    let view = parsed.source_header_expressions().ok()?;
    let root = view.in_source(argument as usize).ok()??;
    let span = Span::new(
        root.span.start.checked_add(relative.start)?,
        root.span.start.checked_add(relative.end)?,
    );
    if relative.start > relative.end || span.end > root.span.end {
        return None;
    }
    struct Find<'a> {
        span: Span,
        found: Option<&'a Expr>,
        duplicate: bool,
    }
    fn find<'a>(expression: &'a Expr, state: &mut Find<'a>) {
        if expression.span == state.span
            && matches!(expression.kind, ExprKind::ObjectInitializer { .. })
        {
            if state.found.replace(expression).is_some() {
                state.duplicate = true;
            }
        }
        dm_syntax::for_each_expression_child(expression, |_, child| find(child, state));
    }
    let mut state = Find {
        span,
        found: None,
        duplicate: false,
    };
    find(root, &mut state);
    if state.duplicate {
        return None;
    }
    let origin = frontend.location(root.span.start)?;
    Some((
        state.found?,
        DebugOrigins {
            entries: vec![DebugOrigin {
                semantic_path: origin.semantic_path,
                line: u32::try_from(origin.line).ok()?,
            }],
        },
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M};
    struct Source(&'static str);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok(self.0.into())
        }
    }
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, query: Q) -> M {
            match query {
                Q::RuntimeType(path) => M::Symbol(path),
                _ => M::Unsupported(query),
            }
        }
    }
    fn frontend(source: &'static str) -> ColdFrontend {
        dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Source(source),
            &Default::default(),
            1,
        )
        .unwrap()
    }
    #[test]
    fn header_modifier_recipe_rebinds_current_origin_and_rejects_changed_expression() {
        let old = frontend("/obj/base\n/proc/p(x in (/obj/base{amount=1}))\n    return x\n");
        let moved = frontend("\n\n/obj/base\n/proc/p(x in (/obj/base{amount=1}))\n    return x\n");
        let changed =
            frontend("\n\n/obj/base\n/proc/p(x in (/obj/base{amount=2}))\n    return x\n");
        let container = syntax_container("(/obj/base{amount=1})").unwrap();
        let statements = dm_syntax::parse_body_items(&container.children);
        let StatementKind::Return(Some(root)) = &statements.statements[0].kind else {
            panic!("return");
        };
        let ExprKind::Group(inner) = &root.kind else {
            panic!("group");
        };
        let span = inner.span;
        fn arena(front: &ColdFrontend) -> dm_tree::frontend::BodyArena<'_> {
            dm_tree::frontend::BodyArena::new_typed(
                front,
                dm_codegen_byond::typed_statements_supported_for_capture,
            )
        }
        let recipe = arena(&old)
            .with_parsed(&old.bodies[0], |parsed| {
                let (expr, debug) =
                    current_header_modifier(&old, parsed, 0, span, old.snapshot.tree.symbols())
                        .unwrap();
                let ExprKind::ObjectInitializer { object, fields } = &expr.kind else {
                    panic!("modifier");
                };
                let ExprKind::TypePath(path) = &object.kind else {
                    panic!("path");
                };
                let captured = dm_codegen_byond::lower_resolver::ModifiedCaptureContext {
                    resolver: &Host,
                    symbols: old.snapshot.tree.symbols(),
                    resource_search_context: None,
                }
                .capture(path, "/", fields, Some(0), expr.span)
                .unwrap();
                crate::modified_initializers::prepare_seed(
                    dm_ir::SymRef::Instance(dm_ir::SymbolId::of(&captured.descriptor.alias())),
                    &captured,
                    &debug,
                )
                .unwrap()
                .helper_source_recipe(0)
                .unwrap()
            })
            .unwrap();
        let debug = DebugOrigins::default();
        arena(&moved)
            .with_parsed(&moved.bodies[0], |parsed| {
                let _current = recipe
                    .reissue(parsed, &moved, &Host, moved.snapshot.tree.symbols(), &debug)
                    .unwrap();
                // Empty ordinary-procedure origins cannot substitute for helper provenance.
                let (_, origins) =
                    current_header_modifier(&moved, parsed, 0, span, moved.snapshot.tree.symbols())
                        .unwrap();
                assert_eq!(origins.entries[0].line, 4);
                let bytes = dm_wire::encode(91, &recipe.disk_evidence()).unwrap();
                let wire: crate::modified_initializers::RecipeWire<'_> =
                    dm_wire::decode_borrowed(91, &bytes, bytes.len()).unwrap();
                assert!(wire
                    .reissue(
                        parsed,
                        &moved,
                        &Host,
                        moved.snapshot.tree.symbols(),
                        &debug,
                        None,
                        dm_ir::SymbolId::of("/")
                    )
                    .is_some());
            })
            .unwrap();
        arena(&changed)
            .with_parsed(&changed.bodies[0], |parsed| {
                assert!(recipe
                    .reissue(
                        parsed,
                        &changed,
                        &Host,
                        changed.snapshot.tree.symbols(),
                        &debug
                    )
                    .is_none());
                assert!(current_header_modifier(
                    &changed,
                    parsed,
                    1,
                    span,
                    changed.snapshot.tree.symbols()
                )
                .is_none());
                assert!(current_header_modifier(
                    &old,
                    parsed,
                    0,
                    span,
                    old.snapshot.tree.symbols()
                )
                .is_none());
            })
            .unwrap();
    }
}

#[cfg(test)]
mod original_recipe_tests {
    use super::*;
    use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M};
    struct Source(dm_preprocess::AcquiredSource);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Err("original acquisition required".into())
        }
        fn acquired_source(
            &self,
            _: &std::path::Path,
        ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
            Ok(Some(self.0.clone()))
        }
        fn source_acquisition(
            &self,
            _: &std::path::Path,
            text: &dm_preprocess::SourceText,
        ) -> Option<dm_preprocess::AcquiredSource> {
            self.0
                .lease()
                .source_text()
                .same_view(text)
                .then(|| self.0.clone())
        }
    }
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, q: Q) -> M {
            match q {
                Q::RuntimeType(path) => M::Symbol(path),
                _ => M::Unsupported(q),
            }
        }
    }
    fn frontend(source: &str) -> ColdFrontend {
        let provider = Source(dm_preprocess::AcquiredSource::from_original_bytes(
            source.as_bytes().to_vec(),
            (),
        ));
        dm_tree::frontend::build(
            std::path::Path::new("original-root-recipe.dm"),
            &provider,
            &Default::default(),
            1,
        )
        .unwrap()
        .with_body_queries(std::sync::Arc::new(crate::query_db::QueryDb::default()))
    }
    #[test]
    fn original_root_recipes_borrow_current_nodes_and_reissue_resident_and_wire_after_shift() {
        let old = frontend("/obj/base\n/proc/p(x in (/obj/base{amount=1}))\n    return x\n");
        let moved = frontend("\n\n/obj/base\n/proc/p(x in (/obj/base{amount=1}))\n    return x\n");
        let changed =
            frontend("\n\n/obj/base\n/proc/p(x in (/obj/base{amount=2}))\n    return x\n");
        let parsed = old.parse_body(&old.bodies[0]).unwrap();
        let view = parsed.source_header_expressions().unwrap();
        let root = view.in_source(0).unwrap().unwrap();
        let ExprKind::Group(inner) = &root.kind else {
            panic!("original group")
        };
        let relative = Span::new(
            inner.span.start - root.span.start,
            inner.span.end - root.span.start,
        );
        let (borrowed, origins) =
            current_original_header_modifier(&old, &parsed, 0, relative).unwrap();
        assert!(std::ptr::eq(borrowed, inner.as_ref()));
        let ExprKind::ObjectInitializer { object, fields } = &borrowed.kind else {
            panic!("modifier")
        };
        let ExprKind::TypePath(path) = &object.kind else {
            panic!("path")
        };
        let captured = dm_codegen_byond::lower_resolver::ModifiedCaptureContext {
            resolver: &Host,
            symbols: old.snapshot.tree.symbols(),
            resource_search_context: None,
        }
        .capture(path, "/", fields, Some(0), borrowed.span)
        .unwrap();
        let seed = crate::modified_initializers::prepare_seed(
            dm_ir::SymRef::Instance(dm_ir::SymbolId::of(&captured.descriptor.alias())),
            &captured,
            &origins,
        )
        .unwrap();
        let recipe = seed.helper_source_recipe_in(0, Some(root.span)).unwrap();
        let moved_parsed = moved.parse_body(&moved.bodies[0]).unwrap();
        let moved_view = moved_parsed.source_header_expressions().unwrap();
        let moved_root = moved_view.in_source(0).unwrap().unwrap();
        let ExprKind::Group(moved_inner) = &moved_root.kind else {
            panic!("current original group")
        };
        let (current, current_origins) =
            current_original_header_modifier(&moved, &moved_parsed, 0, relative).unwrap();
        assert!(std::ptr::eq(current, moved_inner.as_ref()));
        assert_eq!(current_origins.entries[0].line, 4);

        assert!(recipe
            .reissue(
                &moved_parsed,
                &moved,
                &Host,
                moved.snapshot.tree.symbols(),
                &DebugOrigins::default()
            )
            .is_some());
        let bytes = dm_wire::encode(91, &recipe.disk_evidence()).unwrap();
        let wire: crate::modified_initializers::RecipeWire<'_> =
            dm_wire::decode_borrowed(91, &bytes, bytes.len()).unwrap();
        assert!(wire
            .reissue(
                &moved_parsed,
                &moved,
                &Host,
                moved.snapshot.tree.symbols(),
                &DebugOrigins::default(),
                None,
                dm_ir::SymbolId::of("/")
            )
            .is_some());
        let changed_parsed = changed.parse_body(&changed.bodies[0]).unwrap();
        assert!(recipe
            .reissue(
                &changed_parsed,
                &changed,
                &Host,
                changed.snapshot.tree.symbols(),
                &DebugOrigins::default()
            )
            .is_none());
        assert!(recipe
            .reissue(
                &moved_parsed,
                &old,
                &Host,
                old.snapshot.tree.symbols(),
                &DebugOrigins::default()
            )
            .is_none());
        let synthetic = syntax_container("(/obj/base{amount=1})").unwrap();
        let synthetic = dm_syntax::parse_body_items(&synthetic.children);
        let StatementKind::Return(Some(synthetic)) = &synthetic.statements[0].kind else {
            panic!("compatibility return")
        };
        let ExprKind::Group(synthetic) = &synthetic.kind else {
            panic!("compatibility group")
        };
        assert!(
            current_original_header_modifier(&old, &parsed, 0, synthetic.span).is_none(),
            "synthetic coordinates cannot become original-root-relative coordinates"
        );
    }
}
