//! Borrowed evaluated-root hooks for the one pinned control-policy traversal.
//! This is an event contract, not another CFG, syntax tree or DM parser.
use dm_syntax::{Expr, ForInitializer, Span, Statement};
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ScopeKind {
    IfArm,
    ElseArm,
    While,
    DoWhile,
    For,
    SwitchCase,
    SwitchDefault,
    Spawn,
    Label,
    Try,
    Catch,
}
/// The pinned expression's enclosing source or switch-branch anchor.
#[derive(Clone, Copy)]
pub enum ExpressionOrigin {
    Source(Span),
    Case(dm_syntax::OriginalCaseSite),
}

/// The observer stages findings privately and publishes only after traversal
/// succeeds. Scope exit is delivered even when a nested hook returns Err.
/// Binding strings are already issued by primary syntax, never reparsed bodies.
pub trait EvaluatedObserver<'a,E=String> {
    fn expression_at(&mut self, expression: &'a Expr, _at: Option<ExpressionOrigin>) -> Result<(), E> {
        self.expression(expression)
    }
    fn statement_expression_at(&mut self, expression: &'a Expr, _at: Span) -> Result<(), E> {
        self.statement_expression(expression)
    }
    /// True means the actual event was consumed synchronously by the union.
    fn control_event(&mut self,_event:crate::checker_reachable::Event<'a>)->Result<bool,E>{Ok(false)}
    fn do_while_unreachable(&mut self,_at:Span,_condition:Span)->Result<(),E>{Ok(())}
    /// Original numeric switch checks run before condition/selector evaluation.
    fn switch_started(&mut self,_selector:&'a Expr,_cases:&'a [dm_syntax::SwitchCase],_default_present:bool,_at:Span)->Result<(),E>{Ok(())}
    fn switch_case(&mut self,_case:&'a dm_syntax::SwitchCase)->Result<(),E>{Ok(())}
    /// Optional operation-scoped storage admission. Existing observers keep
    /// their original allocation behavior; only an explicitly bounded observer
    /// returns true. A zero-byte call also checks a sticky void-hook refusal.
    fn admit_storage(&mut self, _bytes: usize) -> Result<bool, E> {
        Ok(false)
    }
    /// Relay a failed allocator reservation through an opted-in denial channel.
    fn storage_allocation_failed(&mut self) {}

    fn enter_scope(&mut self, kind: ScopeKind);
    fn leave_scope(&mut self, kind: ScopeKind);
    fn leaf(&mut self, statement: &'a Statement) -> Result<(), E>;
    fn expression(&mut self, expression: &'a Expr) -> Result<(), E>;
    fn statement_expression(&mut self, expression: &'a Expr) -> Result<(), E>;
    fn initializer(&mut self, initializer: &'a ForInitializer, at: Span) -> Result<(), E>;
    /// `always_untyped` is the pinned key/value loop value-binding rule.
    /// Otherwise a pre-existing binding is not re-declared and its range start
    /// is deliberately not visited by the legacy checker.
    fn binding(
        &mut self,
        binding: &'a str,
        value: Option<&'a Expr>,
        always_untyped: bool,
        at: Span,
    ) -> Result<(), E>;
    /// One iterable evaluation; observers may consume its actual static result.
    fn iterable(&mut self,expression:&'a Expr,_at:Span)->Result<(),E>{self.expression(expression)}
    fn invalid_range(&mut self,_at:Span)->Result<(),E>{Ok(())}
    fn catch_parameters(&mut self,_count:usize,_try_header:Span,_catch_header:Span)->Result<(),E>{Ok(())}
    fn catch_binding(&mut self, binding: Option<&'a str>, at: Span, try_at: Span) -> Result<(), E>;
}
