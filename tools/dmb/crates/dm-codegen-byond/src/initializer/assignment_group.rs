//! Current target admission, separated from reusable assignment continuations.
use super::*;
#[derive(Clone, Copy)]
pub struct ValueContinuation<'a> {
    pub dimensions: &'a [u16],
    pub before_assignment: bool,
    pub emit_assignment: bool,
    /// Allocate into the admitted target instead of emitting an authored RHS.
    pub assignment_is_allocation: bool,
}
pub struct PreparedAssignmentGroup<'a> {
    assignments: &'a [AssignmentView<'a>],
    context: InitializerContext<'a>,
    targets: Vec<dm_syntax::Expr>,
    inputs: Vec<ProcedureInputs>,
    slots: Vec<(usize, SymRef, ResolvedSlot)>,
    instance: bool,
    continuations: Vec<Option<ValueContinuation<'a>>>,
}
impl<'a> PreparedAssignmentGroup<'a> {
    pub fn expression(&self, index: usize) -> Option<&dm_syntax::Expr> {
        self.assignments
            .get(index)
            .map(|assignment| assignment.value)
    }
    pub fn symbols(&self) -> &SymbolTable {
        self.context.symbols
    }
    pub(super) fn new(
        assignments: &'a [AssignmentView<'a>],
        context: InitializerContext<'a>,
        targets: Vec<dm_syntax::Expr>,
        inputs: Vec<ProcedureInputs>,
        slots: Vec<(usize, SymRef, ResolvedSlot)>,
        instance: bool,
    ) -> Self {
        Self {
            assignments,
            context,
            targets,
            inputs,
            slots,
            instance,
            continuations: Vec::new(),
        }
    }
    pub fn with_value_continuations(
        mut self,
        values: Vec<Option<ValueContinuation<'a>>>,
    ) -> Result<Self, InitializerError> {
        if values.len() != self.assignments.len() {
            return Err(InitializerError::Invalid(
                "initializer continuation roster differs".into(),
            ));
        }
        if values
            .iter()
            .flatten()
            .any(|value| value.dimensions.is_empty())
        {
            return Err(InitializerError::Invalid(
                "initializer array continuation has no dimensions".into(),
            ));
        }
        if values.iter().flatten().any(|value| {
            value.assignment_is_allocation && (!value.emit_assignment || value.before_assignment)
        }) {
            return Err(InitializerError::Invalid(
                "assigned array continuation has incompatible operation order".into(),
            ));
        }
        for (assignment, continuation) in self.assignments.iter().zip(&values) {
            if continuation.is_some_and(|value| !value.emit_assignment)
                && !matches!(&assignment.value.kind, dm_syntax::ExprKind::Ident(value) | dm_syntax::ExprKind::Literal(value) if value == "null")
            {
                return Err(InitializerError::Invalid(
                    "value-only array continuation requires authored null".into(),
                ));
            }
        }
        self.continuations = values;
        Ok(self)
    }
    pub(super) fn lower_whole<R: Resolver>(
        self,
        host: &R,
    ) -> Result<ResolverProc, InitializerError> {
        let scopes = self
            .targets
            .iter()
            .zip(&self.inputs)
            .zip(self.assignments)
            .enumerate()
            .map(
                |(index, ((target, inputs), assignment))| crate::typed_scopes::AssignmentScope {
                    inputs,
                    continuation: self.continuations.get(index).copied().flatten(),
                    target,
                    value: assignment.value,
                    occurrence: assignment.occurrence,
                    double_receiver: self.instance
                        && assignment.source_site == dm_ir::InitializerSite::Declaration,
                },
            )
            .collect::<Vec<_>>();
        let code = crate::simple::compile_assignment_scopes_with_resolver(
            &scopes,
            self.context.symbols,
            host,
            self.context.debug,
        )
        .map_err(InitializerError::Lowering)?;
        self.finish(code)
    }
    pub fn lower_fragment<R: Resolver>(
        &self,
        index: usize,
        host: &R,
    ) -> Result<AssignmentFragment, InitializerError> {
        self.try_lower_fragment(index, host)?.ok_or_else(|| {
            InitializerError::Invalid(
                "initializer continuation cannot certify independent composition".into(),
            )
        })
    }
    /// A supported whole initializer need not have independently composable
    /// continuations. That case declines reuse without changing compilation.
    pub fn try_lower_fragment<R: Resolver>(
        &self,
        index: usize,
        host: &R,
    ) -> Result<Option<AssignmentFragment>, InitializerError> {
        let assignment = self.assignments.get(index).ok_or_else(|| {
            InitializerError::Invalid("initializer assignment fragment index missing".into())
        })?;
        let debug = LocalDebug;
        let code = crate::simple::compile_assignment_fragment_with_resolver(
            crate::typed_scopes::AssignmentScope {
                inputs: &self.inputs[index],
                continuation: self.continuations.get(index).copied().flatten(),
                target: &self.targets[index],
                value: assignment.value,
                occurrence: dm_syntax::Span::new(0, 0),
                double_receiver: self.instance
                    && assignment.source_site == dm_ir::InitializerSite::Declaration,
            },
            self.context.symbols,
            host,
            self.context
                .debug
                .map(|_| &debug as &dyn crate::DebugSourceProvider),
        )
        .map_err(InitializerError::Lowering)?;
        Ok(AssignmentFragment::certify(code).ok())
    }
    pub fn assemble(
        self,
        fragments: Vec<AssignmentFragment>,
    ) -> Result<ResolverProc, InitializerError> {
        if fragments.len() != self.assignments.len() {
            return Err(InitializerError::Invalid(
                "initializer fragment roster differs from admitted writes".into(),
            ));
        }
        let code = fragments::assemble_continuations(fragments, self.context.debug.is_some())?;
        self.finish(code)
    }
    fn finish(self, mut code: ResolverProc) -> Result<ResolverProc, InitializerError> {
        finish_initializer(&mut code, false)?;
        // Storage is always admitted above; only actual setters require emitted
        // slot references. Authored null arrays deliberately emit allocation only.
        let slots = self
            .slots
            .into_iter()
            .filter_map(|(index, symbol, slot)| {
                self.continuations
                    .get(index)
                    .copied()
                    .flatten()
                    .is_none_or(|extra| extra.emit_assignment)
                    .then_some((symbol, slot))
            })
            .collect();
        attach_target_slots(&mut code, slots)?;
        Ok(code)
    }
}
struct LocalDebug;
impl crate::DebugSourceProvider for LocalDebug {
    fn entry_ordinal(&self) -> Result<u32, String> {
        Ok(0)
    }
    fn ordinal(&self, offset: usize) -> Result<u32, String> {
        if offset == 0 {
            Ok(0)
        } else {
            Err("initializer fragment debug must be assignment-local".into())
        }
    }
}
#[cfg(test)]
#[path = "fragment_parity_tests.rs"]
mod tests;

/// Same prepared assignment producer, with explicitly issued value-only continuations.
pub fn lower_with_value_continuations<'a, R: Resolver>(
    assignments: &'a [super::AssignmentView<'a>],
    context: super::InitializerContext<'a>,
    host: &R,
    continuations: Vec<Option<ValueContinuation<'a>>>,
) -> Result<ResolverProc, InitializerError> {
    super::prepare_assignment_group(assignments, context, host)?
        .with_value_continuations(continuations)?
        .lower_whole(host)
}
