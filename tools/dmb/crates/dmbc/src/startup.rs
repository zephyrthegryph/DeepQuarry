//! Captured procedure-static declarations interleaved with authored field writes.
//! Executable body capture is current-source authority, separate from tree identity.
use dm_ir::ProcedureIdentity;
use dm_tree::{
    frontend::ColdFrontend, initializers::InitializerPlan, procedure_statics::StaticPlan,
    OccurrenceId,
};

pub struct CapturedStartup {
    pub plan: InitializerPlan,
    pub procedures: Vec<(OccurrenceId, StaticPlan)>,
}
pub fn capture(frontend: &ColdFrontend) -> Result<CapturedStartup, String> {
    let units = crate::driver_facts::unit_members(frontend).map_err(|e| e.to_string())?;
    let identities = units
        .into_iter()
        .map(|(unit, member)| {
            (
                member,
                ProcedureIdentity {
                    owner: unit.owner,
                    name: unit.name,
                    verb: unit.namespace == crate::lowering::Namespace::Verb,
                    occurrence: unit.occurrence,
                },
            )
        })
        .collect::<std::collections::HashMap<_, _>>();
    let mut procedures = Vec::with_capacity(frontend.bodies.len());
    for body in frontend.bodies.iter() {
        let identity = *identities
            .get(&body.member)
            .ok_or("startup procedure identity missing")?;
        let parsed = frontend
            .body(body)
            .map_err(|e| format!("startup body: {e:?}"))?;
        let mut plan = dm_tree::procedure_statics::capture(identity, &parsed.children)?;
        // Retain declaration facts only; procedure workers re-capture their own
        // bounded executable bodies instead of duplicating the whole corpus.
        plan.executable_body = Vec::new();
        procedures.push((body.declaration, plan));
    }
    let base = dm_tree::initializers::plan(&frontend.snapshot, &frontend.emission_order)
        .map_err(|e| format!("startup declarations: {e:?}"))?;
    let plan = dm_tree::initializers::with_procedure_statics(
        &base,
        &frontend.emission_order,
        &procedures,
    )?;
    Ok(CapturedStartup { plan, procedures })
}
/// Re-capture all current body facts before accepting an escaping generic plan.
/// This rejects stale same-tree plans after an executable static declaration edit.
pub fn validate(frontend: &ColdFrontend, plan: &InitializerPlan) -> Result<(), String> {
    let current = capture(frontend)?;
    if current.plan.identity != plan.identity
        || current.plan.writes.as_ref() != plan.writes.as_ref()
        || current.plan.origins.as_ref() != plan.origins.as_ref()
    {
        return Err("startup plan differs from current captured declarations or bodies".into());
    }
    Ok(())
}

/// Ordinary field evaluation keeps the caller's captured policy. Static lexical
/// names use the same immutable resolver plus the captured body's symbol delta.
pub struct StartupEvaluator<'a> {
    pub ordinary: &'a dyn crate::initializer_policy::CapturedInitializerEvaluator,
    pub resolver: &'a dyn dm_ir::Resolver,
    pub symbols: &'a dm_ir::SymbolTable,
}
impl crate::initializer_policy::CapturedInitializerEvaluator for StartupEvaluator<'_> {
    fn evaluate(
        &self,
        owner: dm_ir::SymbolId,
        value: &dm_ir::SymbolicExpression,
    ) -> Result<crate::initializer_policy::Evaluation, String> {
        self.ordinary.evaluate(owner, value)
    }
    fn evaluate_write(
        &self,
        write: &dm_ir::InitializerWrite,
        value: &dm_ir::SymbolicExpression,
    ) -> Result<crate::initializer_policy::Evaluation, String> {
        if write.lexical_procedure.is_some() {
            crate::initializer_policy::CapturedInitializerEvaluator::evaluate_write(
                &crate::driver_facts::DriverEvaluator {
                    resolver: self.resolver,
                    symbols: self.symbols,
                },
                write,
                value,
            )
        } else {
            self.ordinary.evaluate_write(write, value)
        }
    }
    fn declaration_modifiers(
        &self,
        write: &dm_ir::InitializerWrite,
    ) -> Result<Option<u32>, String> {
        self.ordinary.declaration_modifiers(write)
    }
}
impl CapturedStartup {
    pub fn resolver<'a, R: dm_ir::Resolver>(
        &'a self,
        frontend: &ColdFrontend,
        host: &'a R,
    ) -> Result<dm_tree::procedure_statics::StaticResolver<'a, R>, String> {
        if self.plan.source.tree.identity() != frontend.snapshot.tree.identity()
            || self.plan.source.occurrences.tree_identity()
                != frontend.snapshot.occurrences.tree_identity()
        {
            return Err("static resolver belongs to another frontend".into());
        }
        dm_tree::procedure_statics::StaticResolver::from_plans(
            host,
            self.procedures
                .iter()
                .map(|(_, plan)| (plan.procedure, plan)),
        )
    }
}
