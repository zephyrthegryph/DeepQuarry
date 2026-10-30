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
/// The observer stages findings privately and publishes only after traversal
/// succeeds. Scope exit is delivered even when a nested hook returns Err.
/// Binding strings are already issued by primary syntax, never reparsed bodies.
pub trait EvaluatedObserver<'a> {
    /// Optional operation-scoped storage admission. Existing observers keep
    /// their original allocation behavior; only an explicitly bounded observer
    /// returns true. A zero-byte call also checks a sticky void-hook refusal.
    fn admit_storage(&mut self, _bytes: usize) -> Result<bool, String> {
        Ok(false)
    }
    /// Relay a failed allocator reservation through an opted-in denial channel.
    fn storage_allocation_failed(&mut self) {}

    fn enter_scope(&mut self, kind: ScopeKind);
    fn leave_scope(&mut self, kind: ScopeKind);
    fn leaf(&mut self, statement: &'a Statement) -> Result<(), String>;
    fn expression(&mut self, expression: &'a Expr) -> Result<(), String>;
    fn statement_expression(&mut self, expression: &'a Expr) -> Result<(), String>;
    fn initializer(&mut self, initializer: &'a ForInitializer, at: Span) -> Result<(), String>;
    /// `always_untyped` is the pinned key/value loop value-binding rule.
    /// Otherwise a pre-existing binding is not re-declared and its range start
    /// is deliberately not visited by the legacy checker.
    fn binding(
        &mut self,
        binding: &'a str,
        value: Option<&'a Expr>,
        always_untyped: bool,
        at: Span,
    ) -> Result<(), String>;
    fn catch_binding(&mut self, binding: Option<&'a str>, at: Span) -> Result<(), String>;
}
