//! Independent pre-view statement construction checks the borrowed adapter.
use super::*;
use dm_ir::{ProcedureIdentity, ProcedureStaticDeclaration, ProcedureStaticIdentity, SymbolId};
use dm_syntax::{Expr, ExprKind, Span, Statement, StatementKind};
struct StaticHost;
impl Resolver for StaticHost {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::ProcedureStatic { procedure, name } => {
                ResolvedMeaning::ProcedureStatic(std::sync::Arc::new(ProcedureStaticDeclaration {
                    identity: ProcedureStaticIdentity { procedure, name },
                    declared_type: None,
                    modifiers: 1,
                    declared_array: None,
                    initializer: InitializerValue::NoAuthoredValue,
                }))
            }
            other => ResolvedMeaning::Unsupported(other),
        }
    }
}
struct Debug;
impl crate::DebugSourceProvider for Debug {
    fn entry_ordinal(&self) -> Result<u32, String> {
        Ok(0)
    }
    fn ordinal(&self, offset: usize) -> Result<u32, String> {
        u32::try_from(offset).map_err(|error| error.to_string())
    }
}
fn fixture() -> (SymbolTable, InitializerTarget, ProcedureIdentity) {
    let mut symbols = SymbolTable::default();
    for text in ["/", "work", "counter"] {
        symbols.intern(text).unwrap();
    }
    let procedure = ProcedureIdentity {
        owner: SymbolId::of("/"),
        name: SymbolId::of("work"),
        verb: false,
        occurrence: 3,
    };
    (
        symbols,
        InitializerTarget::ProcedureStatic(ProcedureStaticIdentity {
            procedure,
            name: SymbolId::of("counter"),
        }),
        procedure,
    )
}
// This deliberately constructs the old owned statement, rather than calling
// the compatibility wrapper now adapted through AssignmentView.
fn legacy(
    value: &Expr,
    occurrence: Span,
    symbols: &SymbolTable,
    procedure: ProcedureIdentity,
) -> Result<ResolverProc, Vec<crate::LowerError>> {
    let mut owned = value.clone();
    owned.span = occurrence;
    let statement = Statement {
        span: occurrence,
        header_span: occurrence,
        raw_header: "initializer assignment".into(),
        kind: StatementKind::Assign {
            target: Expr {
                span: occurrence,
                kind: ExprKind::Ident("counter".into()),
            },
            op: "=".into(),
            value: owned,
        },
    };
    let inputs = ProcedureInputs {
        procedure_identity: Some(procedure),
        ..Default::default()
    };
    let scopes = [crate::typed_scopes::TypedScope {
        inputs: &inputs,
        statements: std::slice::from_ref(&statement),
    }];
    let mut code =
        crate::compile_typed_scopes_with_resolver(&scopes, symbols, &StaticHost, Some(&Debug))?;
    finish_initializer(&mut code, false).unwrap();
    Ok(code)
}
#[test]
fn authored_ast_is_borrowed_with_independent_occurrence_and_exact_old_code() {
    let (symbols, target, procedure) = fixture();
    let mut value = dm_syntax::parse_expression("(1 + 2) * 3").expr.unwrap();
    value.span = Span::new(500, 700);
    let before = value.clone();
    let occurrence = Span::new(7, 7);
    let view = AssignmentView {
        source_site: dm_ir::InitializerSite::Declaration,
                target: &target,
        lexical_owner: procedure.owner,
        value: &value,
        occurrence,
    };
    assert!(std::ptr::eq(view.value, &value));
    let code = lower_assignment_views(
        &[view],
        InitializerContext {
            symbols: &symbols,
            resource_search_context: None,
            debug: Some(&Debug),
        },
        &StaticHost,
    )
    .unwrap();
    let old = legacy(&value, occurrence, &symbols, procedure).unwrap();
    assert_eq!(code.procedure, old.procedure);
    assert_eq!(code.procedure_statics, old.procedure_statics);
    assert_eq!(
        crate::freeze_proc(&code.procedure.code)
            .unwrap()
            .code()
            .canonical_bytes(),
        crate::freeze_proc(&old.procedure.code)
            .unwrap()
            .code()
            .canonical_bytes()
    );
    assert_eq!(value, before);
}
#[test]
fn failed_expression_uses_exact_old_initializer_occurrence() {
    let (symbols, target, procedure) = fixture();
    let value = dm_syntax::parse_expression("world << \"message\"")
        .expr
        .unwrap();
    let occurrence = Span::new(11, 11);
    let old = match legacy(&value, occurrence, &symbols, procedure) {
        Ok(_) => panic!("expected old lowering failure"),
        Err(errors) => errors,
    };
    let error = lower_assignment_views(
        &[AssignmentView {
            source_site: dm_ir::InitializerSite::Declaration,
                target: &target,
            lexical_owner: procedure.owner,
            value: &value,
            occurrence,
        }],
        InitializerContext {
            symbols: &symbols,
            resource_search_context: None,
            debug: Some(&Debug),
        },
        &StaticHost,
    )
    .err()
    .expect("expected borrowed lowering failure");
    match error {
        InitializerError::Lowering(errors) => assert_eq!(errors, old),
        other => panic!("unexpected error: {other:?}"),
    }
    assert_eq!(old[0].reason, "output operator requires statement context");
    assert_eq!(old[0].span.unwrap().start, 11);
}
