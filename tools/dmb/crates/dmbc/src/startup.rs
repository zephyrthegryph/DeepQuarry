//! Captured procedure-static declarations interleaved with authored field writes.
//! Executable body capture is current-source authority, separate from tree identity.
use dm_ir::ProcedureIdentity;
use dm_tree::{
    frontend::ColdFrontend, initializers::InitializerPlan, procedure_statics::StaticPlan,
    OccurrenceId,
};
#[path = "startup_artifacts.rs"]
mod artifacts;
pub(crate) use artifacts::Artifact as StartupArtifact;
pub use artifacts::StartupArtifacts;
#[cfg(test)]
#[path = "startup_artifacts_tests.rs"]
mod artifact_tests;

pub struct CapturedStartup<'a> {
    frontend: &'a ColdFrontend,
    revision: Option<&'a dm_tree::frontend::FrontendRevision>,
    facts: std::sync::Arc<StartupFacts>,
}
/// Owned startup declarations and static plans, issued by one immutable frontend
/// revision. No resolver or reference into a movable frontend is retained.
pub struct StartupFacts {
    issuance: Option<dm_tree::frontend::FrontendIssuance>,
    plan: InitializerPlan,
    procedures: Vec<(OccurrenceId, ProcedureCapture)>,
    procedure_index: std::collections::HashMap<OccurrenceId, usize>,
    static_inventory: std::sync::Arc<dm_tree::procedure_statics::StaticInventory>,
    unit_members: std::sync::Arc<
        std::collections::BTreeMap<crate::lowering::UnitIdentity, dm_tree::MemberId>,
    >,
}
pub(crate) enum ProcedureCapture {
    Empty(StaticPlan),
    Issued(std::sync::Arc<dm_tree::frontend::IssuedStaticPlan>),
}
impl std::ops::Deref for ProcedureCapture {
    type Target = StaticPlan;
    fn deref(&self) -> &StaticPlan {
        match self {
            Self::Empty(plan) => plan,
            Self::Issued(receipt) => receipt.plan(),
        }
    }
}
impl std::ops::Deref for CapturedStartup<'_> {
    type Target = StartupFacts;
    fn deref(&self) -> &Self::Target {
        &self.facts
    }
}
impl StartupFacts {
    pub(crate) fn unit_members(
        &self,
    ) -> &std::sync::Arc<std::collections::BTreeMap<crate::lowering::UnitIdentity, dm_tree::MemberId>>
    {
        &self.unit_members
    }

    /// Raw compatibility models require full current declaration/body recapture.
    pub fn view<'a>(
        self: &std::sync::Arc<Self>,
        frontend: &'a ColdFrontend,
    ) -> Result<CapturedStartup<'a>, String> {
        validate(frontend, &self.plan)?;
        Ok(CapturedStartup {
            frontend,
            revision: None,
            facts: std::sync::Arc::clone(self),
        })
    }
    pub fn view_revision<'a>(
        self: &std::sync::Arc<Self>,
        revision: &'a dm_tree::frontend::FrontendRevision,
    ) -> Result<CapturedStartup<'a>, String> {
        match &self.issuance {
            Some(issuance) if !issuance.matches(revision) => {
                return Err("startup capture belongs to a different frontend".into())
            }
            Some(_) => (),
            None => validate(revision, &self.plan)?,
        }
        Ok(CapturedStartup {
            frontend: revision,
            revision: Some(revision),
            facts: std::sync::Arc::clone(self),
        })
    }
}
pub fn capture(frontend: &ColdFrontend) -> Result<CapturedStartup<'_>, String> {
    capture_with_workers(frontend, 1)
}
pub fn capture_with_workers(
    frontend: &ColdFrontend,
    workers: usize,
) -> Result<CapturedStartup<'_>, String> {
    Ok(CapturedStartup {
        frontend,
        revision: None,
        facts: std::sync::Arc::new(capture_impl(frontend, workers, true)?),
    })
}
fn capture_impl(
    frontend: &ColdFrontend,
    workers: usize,
    prefilter: bool,
) -> Result<StartupFacts, String> {
    let executor = dm_exec::BuildExecutor::new(workers).map_err(|error| error.to_string())?;
    capture_impl_with_executor(frontend, &executor, prefilter)
}
fn capture_impl_with_executor(
    frontend: &ColdFrontend,
    executor: &dm_exec::BuildExecutor,
    prefilter: bool,
) -> Result<StartupFacts, String> {
    let bodies = dm_tree::frontend::BodyArena::new(frontend);
    capture_impl_with_bodies(frontend, executor, &bodies, prefilter)
}
fn capture_impl_with_bodies(
    frontend: &ColdFrontend,
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    prefilter: bool,
) -> Result<StartupFacts, String> {
    capture_impl_with_bodies_and_artifacts(frontend, executor, bodies, prefilter, None)
}
fn capture_impl_with_bodies_and_artifacts(
    frontend: &ColdFrontend,
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    prefilter: bool,
    artifacts: Option<&StartupArtifacts>,
) -> Result<StartupFacts, String> {
    let units = std::sync::Arc::new(
        crate::driver_facts::unit_members(frontend).map_err(|e| e.to_string())?,
    );
    let identities = units
        .iter()
        .map(|(unit, member)| {
            (
                *member,
                ProcedureIdentity {
                    owner: unit.owner,
                    name: unit.name,
                    verb: unit.namespace == crate::lowering::Namespace::Verb,
                    occurrence: unit.occurrence,
                },
            )
        })
        .collect::<std::collections::HashMap<_, _>>();
    let mut keys = std::collections::HashMap::new();
    if let Some(artifacts) = artifacts {
        for body in frontend.bodies.iter() {
            let key = (|| {
                let input = frontend
                    .body_input(body)
                    .map_err(|e| format!("startup body: {e:?}"))?;
                let source = input.source();
                if !prefilter || input.may_contain_stored_declarations() {
                    let identity = *identities
                        .get(&body.member)
                        .ok_or("startup procedure identity missing")?;
                    Ok(Some(artifacts::key(identity, source)))
                } else {
                    Ok::<_, String>(None)
                }
            })();
            keys.insert(body.member, key);
        }
        artifacts.retain_keys(
            keys.values()
                .filter_map(|result| result.as_ref().ok()?.as_deref()),
            identities.values().copied(),
        );
    }
    let capture_body = |body: &dm_tree::frontend::BodyOccurrence| {
        let identity = *identities
            .get(&body.member)
            .ok_or("startup procedure identity missing")?;
        let input = frontend
            .body_input(body)
            .map_err(|e| format!("startup body: {e:?}"))?;
        let candidate_key = keys
            .get(&body.member)
            .map(|result| result.as_ref().map(Option::as_deref).map_err(Clone::clone))
            .transpose()?
            .flatten();
        let empty = if artifacts.is_some() {
            candidate_key.is_none()
        } else {
            prefilter && !input.may_contain_stored_declarations()
        };
        if empty {
            return Ok((
                body.declaration,
                ProcedureCapture::Empty(dm_tree::procedure_statics::capture_declarations(
                    identity,
                    &[],
                )?),
            ));
        }
        if let (Some(artifacts), Some(key)) = (artifacts, candidate_key) {
            if let Some(payload) = artifacts.lookup(key) {
                let plan = payload.bind(frontend, body)?;
                return Ok((body.declaration, ProcedureCapture::Issued(plan)));
            }
        }
        let plan = bodies
            .with_parsed(body, |parsed| parsed.capture_stored_declarations(identity))
            .map_err(|e| format!("startup body: {e:?}"))??;
        if let (Some(artifacts), Some(key)) = (artifacts, candidate_key) {
            artifacts.remember(key.to_vec(), &plan);
        }
        Ok::<_, String>((body.declaration, ProcedureCapture::Issued(plan)))
    };
    let workers = executor.workers().min(frontend.bodies.len().max(1));
    let chunk = frontend.bodies.len().div_ceil(workers).max(1);
    let chunks: Vec<_> = frontend.bodies.chunks(chunk).collect();
    let results: Vec<_> = (0..chunks.len())
        .map(|_| std::sync::Mutex::new(None))
        .collect();
    let scheduling = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        executor.scope(|scope| {
            for (index, bodies) in chunks.iter().enumerate() {
                let capture_body = &capture_body;
                let slot = &results[index];
                scope.spawn(move |_| {
                    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        let _profile = dm_profile::stage("cold.startup_capture");
                        bodies
                            .iter()
                            .map(capture_body)
                            .collect::<Result<Vec<_>, String>>()
                    }))
                    .unwrap_or_else(|_| Err("startup capture worker panicked".into()));
                    *slot.lock().unwrap_or_else(|error| error.into_inner()) = Some(result);
                });
            }
        });
    }));
    scheduling.map_err(|_| "startup capture scheduler panicked".to_string())?;
    let chunks = results.into_iter().map(|slot| {
        slot.into_inner()
            .unwrap_or_else(|error| error.into_inner())
            .unwrap_or_else(|| Err("startup capture job did not complete".into()))
    });
    let mut procedures = Vec::with_capacity(frontend.bodies.len());
    // Chunk order is source order, including deterministic first-error selection.
    for result in chunks {
        procedures.extend(result?);
    }
    let base = dm_tree::initializers::capture_declaration_draft(
        &frontend.snapshot,
        &frontend.emission_order,
    )
    .map_err(|e| format!("startup declarations: {e:?}"))?;
    let plan = dm_tree::initializers::finish_declaration_draft(
        base,
        procedures
            .iter()
            .map(|(occurrence, plan)| (*occurrence, &**plan)),
    )?;
    let procedure_index = procedures
        .iter()
        .enumerate()
        .map(|(index, (occurrence, _))| (*occurrence, index))
        .collect();
    let mut static_inventory = dm_tree::procedure_statics::StaticInventory::from_plans(
        procedures.iter().map(|(_, plan)| (plan.procedure, &**plan)),
    )?;
    if let Some(artifacts) = artifacts {
        static_inventory
            .certify(|procedure, declarations| artifacts.admit_layout(procedure, declarations));
    }
    let static_inventory = std::sync::Arc::new(static_inventory);

    Ok(StartupFacts {
        issuance: None,
        plan,
        procedures,
        procedure_index,
        static_inventory,
        unit_members: units,
    })
}
/// Extend only the compilation spelling dictionary. Captured declarations,
/// source provenance and semantic identity remain the original source model.
pub fn capture_with_spellings<'a>(
    frontend: &'a ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
) -> Result<CapturedStartup<'a>, String> {
    capture_with_spellings_and_workers(frontend, spellings, 1)
}
pub fn capture_with_spellings_and_workers<'a>(
    frontend: &'a ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    workers: usize,
) -> Result<CapturedStartup<'a>, String> {
    Ok(CapturedStartup {
        frontend,
        revision: None,
        facts: capture_facts_with_spellings_and_workers(frontend, spellings, workers)?,
    })
}
/// Production path borrows the one executor owned by this build.
pub fn capture_with_executor<'a>(
    frontend: &'a ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
) -> Result<CapturedStartup<'a>, String> {
    Ok(CapturedStartup {
        frontend,
        revision: None,
        facts: capture_facts_with_executor(frontend, spellings, executor)?,
    })
}
pub fn capture_with_executor_and_bodies<'a>(
    frontend: &'a ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
) -> Result<CapturedStartup<'a>, String> {
    Ok(CapturedStartup {
        frontend,
        revision: None,
        facts: capture_facts_with_executor_and_bodies(frontend, spellings, executor, bodies)?,
    })
}
pub fn capture_revision_facts_with_executor_and_bodies(
    revision: &dm_tree::frontend::FrontendRevision,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
) -> Result<std::sync::Arc<StartupFacts>, String> {
    capture_revision_facts_with_executor_and_bodies_and_artifacts(
        revision, spellings, executor, bodies, None,
    )
}
pub fn capture_revision_facts_with_executor_and_bodies_and_artifacts(
    revision: &dm_tree::frontend::FrontendRevision,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    artifacts: Option<&StartupArtifacts>,
) -> Result<std::sync::Arc<StartupFacts>, String> {
    let mut facts = capture_facts_with_executor_and_bodies_and_artifacts(
        revision, spellings, executor, bodies, artifacts,
    )?;
    std::sync::Arc::get_mut(&mut facts)
        .expect("new startup facts are exclusively owned")
        .issuance = Some(revision.issuance());
    Ok(facts)
}
pub fn capture_revision_facts_with_executor(
    revision: &dm_tree::frontend::FrontendRevision,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
) -> Result<std::sync::Arc<StartupFacts>, String> {
    let mut facts = capture_facts_with_executor(revision, spellings, executor)?;
    std::sync::Arc::get_mut(&mut facts)
        .expect("new startup facts are exclusively owned")
        .issuance = Some(revision.issuance());
    Ok(facts)
}
pub fn capture_revision_facts_with_spellings_and_workers(
    revision: &dm_tree::frontend::FrontendRevision,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    workers: usize,
) -> Result<std::sync::Arc<StartupFacts>, String> {
    let mut facts = capture_facts_with_spellings_and_workers(revision, spellings, workers)?;
    std::sync::Arc::get_mut(&mut facts)
        .expect("new startup facts are exclusively owned")
        .issuance = Some(revision.issuance());
    Ok(facts)
}
pub fn capture_facts_with_spellings_and_workers(
    frontend: &ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    workers: usize,
) -> Result<std::sync::Arc<StartupFacts>, String> {
    let executor = dm_exec::BuildExecutor::new(workers).map_err(|error| error.to_string())?;
    capture_facts_with_executor(frontend, spellings, &executor)
}
fn capture_facts_with_executor(
    frontend: &ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
) -> Result<std::sync::Arc<StartupFacts>, String> {
    let bodies = dm_tree::frontend::BodyArena::new(frontend);
    capture_facts_with_executor_and_bodies(frontend, spellings, executor, &bodies)
}
fn capture_facts_with_executor_and_bodies(
    frontend: &ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
) -> Result<std::sync::Arc<StartupFacts>, String> {
    capture_facts_with_executor_and_bodies_and_artifacts(
        frontend, spellings, executor, bodies, None,
    )
}
fn capture_facts_with_executor_and_bodies_and_artifacts(
    frontend: &ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    artifacts: Option<&StartupArtifacts>,
) -> Result<std::sync::Arc<StartupFacts>, String> {
    let mut startup =
        capture_impl_with_bodies_and_artifacts(frontend, executor, bodies, true, artifacts)?;
    let mut symbols = dm_ir::SymbolTable::overlay(startup.plan.symbols.clone());
    for (expected, bytes) in spellings {
        let text =
            std::str::from_utf8(bytes).map_err(|_| "captured symbol spelling is not UTF-8")?;
        let actual = symbols
            .intern(text)
            .map_err(|error| format!("captured symbol collision: {error:?}"))?;
        if actual != *expected {
            return Err("captured spelling does not match symbolic identity".into());
        }
    }
    startup.plan.symbols = std::sync::Arc::new(symbols);
    Ok(std::sync::Arc::new(startup))
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
    pub resource_search_context: Option<u128>,
    pub ordinary: &'a dyn crate::initializer_policy::CapturedInitializerEvaluator,
    pub resolver: &'a dyn dm_ir::Resolver,
    pub symbols: &'a dm_ir::SymbolTable,
}
impl crate::initializer_policy::CapturedInitializerEvaluator for StartupEvaluator<'_> {
    fn evaluate_prepared_write(
        &self,
        write: &dm_ir::InitializerWrite,
        value: &dm_ir::SymbolicExpression,
    ) -> Result<
        (
            crate::initializer_policy::Evaluation,
            Option<crate::initializer_policy::PreparedInitializerExpression>,
        ),
        String,
    > {
        if write.lexical_procedure.is_some() {
            crate::initializer_policy::CapturedInitializerEvaluator::evaluate_prepared_write(
                &crate::driver_facts::DriverEvaluator {
                    pure_calls: self.ordinary.pure_calls(),
                    resource_search_context: self.resource_search_context,
                    resolver: self.resolver,
                    symbols: self.symbols,
                },
                write,
                value,
            )
        } else {
            self.ordinary.evaluate_prepared_write(write, value)
        }
    }

    fn evaluate_ast_write(
        &self,
        write: &dm_ir::InitializerWrite,
        ast: &dm_syntax::Expr,
        source: &str,
        symbols: &dm_ir::SymbolTable,
    ) -> Result<crate::initializer_policy::Evaluation, String> {
        if write.lexical_procedure.is_some() {
            crate::initializer_policy::CapturedInitializerEvaluator::evaluate_ast_write(
                &crate::driver_facts::DriverEvaluator {
                    pure_calls: self.ordinary.pure_calls(),
                    resource_search_context: self.resource_search_context,
                    resolver: self.resolver,
                    symbols: self.symbols,
                },
                write,
                ast,
                source,
                symbols,
            )
        } else {
            self.ordinary
                .evaluate_ast_write(write, ast, source, symbols)
        }
    }
    fn initializer_token_scalar(&self, value: &dm_ir::SemanticValue) -> Result<Vec<u8>, String> {
        self.ordinary.initializer_token_scalar(value)
    }
    fn initializer_intrinsic_constructor(
        &self,
        write: &dm_ir::InitializerWrite,
        name: &str,
    ) -> bool {
        self.ordinary.initializer_intrinsic_constructor(write, name)
    }
    fn initializer_constructor_type(
        &self,
        write: &dm_ir::InitializerWrite,
    ) -> Result<Option<dm_ir::SymbolId>, String> {
        crate::initializer_policy::CapturedInitializerEvaluator::initializer_constructor_type(
            &crate::driver_facts::DriverEvaluator {
                pure_calls: self.ordinary.pure_calls(),
                resource_search_context: self.resource_search_context,
                resolver: self.resolver,
                symbols: self.symbols,
            },
            write,
        )
    }
    fn pure_calls(&self) -> Option<&dyn dm_tree::constants::PureCalls> {
        self.ordinary.pure_calls()
    }
    fn instance_storage(
        &self,
        write: &dm_ir::InitializerWrite,
    ) -> Result<Option<(dm_ir::SymbolId, dm_ir::SymbolId)>, String> {
        crate::initializer_policy::CapturedInitializerEvaluator::instance_storage(
            &crate::driver_facts::DriverEvaluator {
                pure_calls: self.ordinary.pure_calls(),
                resource_search_context: self.resource_search_context,
                resolver: self.resolver,
                symbols: self.symbols,
            },
            write,
        )
    }
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
                    pure_calls: self.ordinary.pure_calls(),
                    resource_search_context: self.resource_search_context,
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
impl CapturedStartup<'_> {
    pub fn facts(&self) -> std::sync::Arc<StartupFacts> {
        std::sync::Arc::clone(&self.facts)
    }
    pub fn plan(&self) -> &InitializerPlan {
        &self.plan
    }
    pub(crate) fn static_inventory(
        &self,
    ) -> &std::sync::Arc<dm_tree::procedure_statics::StaticInventory> {
        &self.static_inventory
    }
    pub fn procedures(&self) -> impl ExactSizeIterator<Item = (&OccurrenceId, &StaticPlan)> {
        self.procedures
            .iter()
            .map(|(occurrence, capture)| (occurrence, &**capture))
    }
    pub(crate) fn procedure_captures(&self) -> &[(OccurrenceId, ProcedureCapture)] {
        &self.procedures
    }
    pub fn procedure(&self, occurrence: OccurrenceId) -> Option<&StaticPlan> {
        self.procedure_index
            .get(&occurrence)
            .map(|index| &*self.procedures[*index].1)
    }
    /// Issued facts are immutable and borrow the exact frontend throughout use.
    /// Independently supplied generic plans still use the strict recapture API.
    pub fn validate_for(&self, frontend: &ColdFrontend) -> Result<(), String> {
        if !std::ptr::eq(self.frontend, frontend)
            || self
                .facts
                .issuance
                .as_ref()
                .zip(self.revision)
                .is_some_and(|(issuance, revision)| !issuance.matches(revision))
        {
            return Err("startup capture belongs to a different frontend".into());
        }
        Ok(())
    }
    pub fn resolver<'a, R: dm_ir::Resolver>(
        &'a self,
        frontend: &ColdFrontend,
        host: &'a R,
    ) -> Result<dm_tree::procedure_statics::StaticResolver<'a, R>, String> {
        self.validate_for(frontend)?;
        if self.plan.source.tree.identity() != frontend.snapshot.tree.identity()
            || self.plan.source.occurrences.tree_identity()
                != frontend.snapshot.occurrences.tree_identity()
        {
            return Err("static resolver belongs to another frontend".into());
        }
        dm_tree::procedure_statics::StaticResolver::from_inventory(
            host,
            std::sync::Arc::clone(&self.static_inventory),
        )
    }
}

#[cfg(test)]
#[path = "startup_owned_tests.rs"]
mod owned_tests;
#[cfg(test)]
mod spelling_tests {
    use super::*;
    use std::{path::Path, sync::Arc};
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/proc/p()\n    return 1\n".into())
        }
    }
    #[test]
    fn issued_startup_is_bound_to_immutable_input_and_indexes_procedures() {
        let first =
            dm_tree::frontend::build(Path::new("probe.dme"), &Source, &Default::default(), 1)
                .unwrap();
        let identical =
            dm_tree::frontend::build(Path::new("probe.dme"), &Source, &Default::default(), 1)
                .unwrap();
        let issued = capture(&first).unwrap();
        issued.validate_for(&first).unwrap();
        assert!(issued.validate_for(&identical).is_err());
        for (occurrence, plan) in issued.procedures() {
            assert!(std::ptr::eq(issued.procedure(*occurrence).unwrap(), plan));
        }
        // A detached generic plan retains exact content validation, including
        // rejection of modifications; the production token exposes no mutation.
        let mut escaped = issued.plan().clone();
        escaped.identity ^= 1;
        assert!(validate(&first, &escaped).is_err());
    }
    #[test]
    fn bounded_parallel_startup_preserves_source_order_and_facts() {
        struct Multiple;
        impl dm_preprocess::SourceProvider for Multiple {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok("/datum/demo\n    var/static/class_tick = 0\n    proc/first()\n        var/static/value = 1\n        return value\n    proc/second()\n        var/static/value = 2\n        return value\n".into())
            }
        }
        let frontend =
            dm_tree::frontend::build(Path::new("probe.dme"), &Multiple, &Default::default(), 1)
                .unwrap();
        let serial = capture_with_workers(&frontend, 1).unwrap();
        let parallel = capture_with_workers(&frontend, 2).unwrap();
        assert_eq!(serial.plan.identity, parallel.plan.identity);
        assert_eq!(serial.plan.writes.as_ref(), parallel.plan.writes.as_ref());
        assert_eq!(serial.plan.origins.as_ref(), parallel.plan.origins.as_ref());
        assert_eq!(serial.procedures.len(), 2);
        for ((left_id, left), (right_id, right)) in
            serial.procedures.iter().zip(&parallel.procedures)
        {
            assert_eq!(left_id, right_id);
            assert_eq!(left.procedure, right.procedure);
            assert_eq!(left.declarations, right.declarations);
            assert_eq!(left.origins, right.origins);
            assert!(left.executable_body.is_empty() && right.executable_body.is_empty());
        }
    }
    #[test]
    fn borrowed_executor_reuses_revision_capture_without_changing_facts() {
        let revision = dm_tree::frontend::FrontendRevision::new(
            dm_tree::frontend::build(Path::new("probe.dme"), &Source, &Default::default(), 1)
                .unwrap(),
        );
        let executor = dm_exec::BuildExecutor::new(3).unwrap();
        assert_eq!(executor.workers(), 3);
        let first = capture_revision_facts_with_executor(&revision, &[], &executor).unwrap();
        let second = capture_revision_facts_with_executor(&revision, &[], &executor).unwrap();
        let serial = capture(&revision).unwrap();
        assert_eq!(first.plan.identity, serial.plan.identity);
        assert_eq!(
            first.unit_members().as_ref(),
            &crate::driver_facts::unit_members(&revision).unwrap()
        );
        let view = first.view_revision(&revision).unwrap();
        assert!(std::sync::Arc::ptr_eq(
            first.unit_members(),
            view.unit_members()
        ));
        assert_eq!(first.plan.writes.as_ref(), second.plan.writes.as_ref());
        assert_eq!(first.plan.origins.as_ref(), second.plan.origins.as_ref());
        first
            .view_revision(&revision)
            .unwrap()
            .validate_for(&revision)
            .unwrap();
        second
            .view_revision(&revision)
            .unwrap()
            .validate_for(&revision)
            .unwrap();
    }
    #[test]
    fn captured_alias_overlay_preserves_source_and_ledger_identity() {
        let frontend =
            dm_tree::frontend::build(Path::new("probe.dme"), &Source, &Default::default(), 1)
                .unwrap();
        let original = capture(&frontend).unwrap();
        let alias = dm_ir::SymbolId::of("asset.txt");
        assert!(frontend.snapshot.tree.symbols().text(alias).is_none());
        let issued =
            capture_with_spellings(&frontend, &[(alias, Arc::from(b"asset.txt".as_slice()))])
                .unwrap();
        assert_eq!(issued.plan.symbols.text(alias), Some("asset.txt"));
        assert!(frontend.snapshot.tree.symbols().text(alias).is_none());
        assert_eq!(issued.plan.identity, original.plan.identity);
        assert_eq!(issued.plan.writes.as_ref(), original.plan.writes.as_ref());
        validate(&frontend, &issued.plan).unwrap();
        assert!(
            capture_with_spellings(&frontend, &[(alias, Arc::from(b"other.txt".as_slice()))])
                .is_err()
        );
    }
    #[test]
    fn stored_local_prefilter_matches_full_capture_for_expanded_and_nested_declarations() {
        struct Mixed;
        impl dm_preprocess::SourceProvider for Mixed {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok("#define CACHE var/static/list/cache = list(1)\n/proc/plain()\n    var/local = 1\n    return local\n/proc/substrings()\n    var/globalish = \"static const global\"\n    return globalish\n/proc/expanded()\n    CACHE\n    if(1)\n        var/const/alias = 3\n        var/static/next = alias\n    return cache\n/proc/global_local()\n    var/global/count = 2\n    return count\n".into())
            }
        }
        let frontend =
            dm_tree::frontend::build(Path::new("probe.dme"), &Mixed, &Default::default(), 2)
                .unwrap();
        let full = capture_impl(&frontend, 1, false).unwrap();
        for workers in [1, 2] {
            let filtered = capture_impl(&frontend, workers, true).unwrap();
            assert_eq!(filtered.plan.identity, full.plan.identity);
            assert_eq!(filtered.plan.writes.as_ref(), full.plan.writes.as_ref());
            assert_eq!(filtered.plan.origins.as_ref(), full.plan.origins.as_ref());
            for ((left_id, left), (right_id, right)) in
                filtered.procedures.iter().zip(&full.procedures)
            {
                assert_eq!(left_id, right_id);
                assert_eq!(left.procedure, right.procedure);
                assert_eq!(left.declarations, right.declarations);
                assert_eq!(left.origins, right.origins);
                assert!(left.executable_body.is_empty());
                for declaration in &right.declarations {
                    assert_eq!(
                        left.symbols.text(declaration.identity.name),
                        right.symbols.text(declaration.identity.name)
                    );
                }
            }
        }
        assert!(
            !dm_tree::procedure_statics::may_contain_stored_declarations(
                "/proc/plain()\n    var/local = 1\n    return local\n"
            )
        );
        assert!(!dm_tree::procedure_statics::may_contain_stored_declarations("return \"static\""));
        assert!(!dm_tree::procedure_statics::may_contain_stored_declarations("// global comment"));
    }
}

#[cfg(test)]
#[path = "startup_evaluator_forwarding_tests.rs"]
mod evaluator_forwarding_tests;

#[cfg(test)]
#[path = "startup_static_certificate_tests.rs"]
mod static_certificate_tests;
