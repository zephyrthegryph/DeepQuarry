use super::*;
use dm_ir::{ResolveQuery, ResolvedMeaning};
struct Host {
    resource: u128,
}
impl Resolver for Host {
    fn resolve(&self, q: ResolveQuery) -> ResolvedMeaning {
        match q {
            ResolveQuery::RuntimeType(path) => ResolvedMeaning::Symbol(path),
            ResolveQuery::Resource(path) => ResolvedMeaning::Resource {
                path,
                content: self.resource,
            },
            _ => ResolvedMeaning::Unsupported(q),
        }
    }
}
fn object(start: usize, value: &str) -> Expr {
    let mut field = dm_syntax::parse_expression(value).expr.unwrap();
    field.span = dm_syntax::Span::new(start + 10, start + 10 + value.len());
    Expr {
        span: dm_syntax::Span::new(start, start + 40),
        kind: ExprKind::ObjectInitializer {
            object: Box::new(Expr {
                span: dm_syntax::Span::new(start, start + 9),
                kind: ExprKind::TypePath("/obj/item".into()),
            }),
            fields: vec![("amount".into(), field)],
        },
    }
}
fn root(start: usize, value: &str) -> Expr {
    Expr {
        span: dm_syntax::Span::new(start, start + 100),
        kind: ExprKind::Call {
            callee: Box::new(Expr {
                span: dm_syntax::Span::new(start, start + 4),
                kind: ExprKind::Ident("list".into()),
            }),
            args: vec![
                dm_syntax::parse_expression("3").expr.unwrap(),
                object(start + 20, value),
            ],
        },
    }
}
fn capture(
    expression: &Expr,
    host: &Host,
    symbols: &SymbolTable,
) -> (SymRef, CapturedModifiedInstance) {
    let ExprKind::ObjectInitializer { object, fields } = &expression.kind else {
        panic!("object required")
    };
    let ExprKind::TypePath(path) = &object.kind else {
        panic!("type path required")
    };
    let captured = dm_codegen_byond::lower_resolver::ModifiedCaptureContext {
        resolver: host,
        symbols,
        resource_search_context: None,
    }
    .capture(path, "/", fields, Some(0), expression.span)
    .unwrap();
    (
        SymRef::Instance(SymbolId::of(&captured.descriptor.alias())),
        captured,
    )
}
fn nested(root: &Expr) -> &Expr {
    let ExprKind::Call { args, .. } = &root.kind else {
        panic!("call required")
    };
    &args[1]
}
#[test]
fn nested_recipe_uses_current_typed_child_and_current_field_spans() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/").unwrap();
    let host = Host { resource: 1 };
    let old = root(0, "1");
    let (reference, captured) = capture(nested(&old), &host, &symbols);
    let recipe = ExpressionRecipe::from_capture(reference, &captured, &old).unwrap();
    drop(captured);
    drop(old);
    let current = root(500, "1");
    let (_, reissued) = recipe.reissue(&current, &host, &symbols).unwrap();
    assert_eq!(reissued.source_span, Some(nested(&current).span));
    assert_eq!(
        reissued.descriptor.fields()[0].1.span,
        dm_syntax::Span::new(530, 531)
    );
    assert_eq!(recipe.path, vec![2]);
    let changed = root(500, "2");
    assert!(recipe.reissue(&changed, &host, &symbols).is_none());
    assert!(recipe
        .reissue(
            &dm_syntax::parse_expression("1").expr.unwrap(),
            &host,
            &symbols
        )
        .is_none());
}
#[test]
fn canonical_resource_proof_and_unambiguous_current_node_are_required() {
    let mut symbols = SymbolTable::default();
    symbols.intern("/").unwrap();
    let host = Host { resource: 11 };
    let old = root(0, "'asset.dat'");
    let (reference, captured) = capture(nested(&old), &host, &symbols);
    let recipe = ExpressionRecipe::from_capture(reference, &captured, &old).unwrap();
    assert!(recipe
        .reissue(&root(200, "'asset.dat'"), &Host { resource: 12 }, &symbols)
        .is_none());
    let mut ambiguous = old.clone();
    let ExprKind::Call { args, .. } = &mut ambiguous.kind else {
        panic!("call required")
    };
    args.push(nested(&old).clone());
    assert!(ExpressionRecipe::from_capture(reference, &captured, &ambiguous).is_none());
}
