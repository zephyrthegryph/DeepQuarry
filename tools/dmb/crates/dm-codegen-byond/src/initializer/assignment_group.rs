//! Current target admission, separated from reusable assignment continuations.
use super::*;
pub struct PreparedAssignmentGroup<'a> {
    assignments: &'a [AssignmentView<'a>],
    context: InitializerContext<'a>,
    targets: Vec<dm_syntax::Expr>,
    inputs: Vec<ProcedureInputs>,
    slots: Vec<(SymRef, ResolvedSlot)>,
    instance: bool,
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
        slots: Vec<(SymRef, ResolvedSlot)>,
        instance: bool,
    ) -> Self {
        Self {
            assignments,
            context,
            targets,
            inputs,
            slots,
            instance,
        }
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
            .map(
                |((target, inputs), assignment)| crate::typed_scopes::AssignmentScope {
                    inputs,
                    target,
                    value: assignment.value,
                    occurrence: assignment.occurrence,
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
                target: &self.targets[index],
                value: assignment.value,
                occurrence: dm_syntax::Span::new(0, 0),
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
        finish_initializer(&mut code, self.instance)?;
        attach_target_slots(&mut code, self.slots)?;
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
