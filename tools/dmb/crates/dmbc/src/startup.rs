//! Captured procedure-static declarations interleaved with authored field writes.
//! Executable body capture is current-source authority, separate from tree identity.
use dm_tree::{
    frontend::ColdFrontend, initializers::InitializerPlan, procedure_statics::StaticPlan,
    OccurrenceId,
};
#[path = "startup_artifacts.rs"]
mod artifacts;
pub(crate) use artifacts::Answer as StartupAnswer;
pub(crate) use artifacts::Artifact as StartupArtifact;
pub use artifacts::StartupArtifacts;
#[cfg(test)]
#[path = "startup_artifacts_tests.rs"]
mod artifact_tests;

/// Stack-only failure status, never a startup artifact or cached semantic key.
#[derive(Debug)]
pub enum StartupFailure {
    Semantic(String),
    Operational(std::io::Error),
}
impl From<String> for StartupFailure {fn from(value:String)->Self{Self::Semantic(value)}}
impl From<&str> for StartupFailure {fn from(value:&str)->Self{Self::Semantic(value.into())}}
impl From<std::io::Error> for StartupFailure{fn from(error:std::io::Error)->Self{Self::Operational(error)}}
trait StartupDemand {
    type Failure:From<String>+From<&'static str>+Send;
    fn source<'f>(_front:&'f ColdFrontend)->Result<Option<dm_tree::frontend::OriginalDeclarationExpressionContext<'f>>,Self::Failure>{Ok(None)}
    fn cached(frontend:&ColdFrontend,body:&dm_tree::frontend::BodyOccurrence,artifacts:&StartupArtifacts,key:&[u8],_source:Option<&dm_tree::frontend::OriginalDeclarationExpressionContext<'_>>)->Result<Option<std::sync::Arc<dm_tree::frontend::IssuedStaticPlan>>,Self::Failure>{
        artifacts.lookup(key).map(|payload|payload.bind(frontend,body).map_err(Into::into)).transpose()
    }
    fn remember(artifacts:&StartupArtifacts,key:Vec<u8>,plan:&std::sync::Arc<dm_tree::frontend::IssuedStaticPlan>){artifacts.remember(key,plan)}
    fn admit_static(_plan:&std::sync::Arc<dm_tree::frontend::IssuedStaticPlan>,_source:Option<&dm_tree::frontend::OriginalDeclarationExpressionContext<'_>>)->Result<(),Self::Failure>{Ok(())}
    fn semantic(error:Self::Failure)->Result<String,Self::Failure>;
    fn inventory(procedures:&[(OccurrenceId,ProcedureCapture)],artifacts:Option<&StartupArtifacts>)->Result<std::sync::Arc<dm_tree::procedure_statics::StaticInventory>,Self::Failure>;
    fn finish(draft:dm_tree::initializers::DeclarationDraft<'_>,frontend:&ColdFrontend,procedures:&[(OccurrenceId,ProcedureCapture)])->Result<StartupPlan,Self::Failure>;
    fn body<'f,T>(arena:&dm_tree::frontend::BodyArena<'f>,body:&dm_tree::frontend::BodyOccurrence,
        produce:impl FnOnce(&dm_tree::frontend::ParsedBody<'f>)->T)->Result<T,Self::Failure>;
}
struct CompatibilityStartup;
struct CheckedStartup;
impl StartupDemand for CompatibilityStartup {
    type Failure=String;
    fn inventory(procedures:&[(OccurrenceId,ProcedureCapture)],artifacts:Option<&StartupArtifacts>)->Result<std::sync::Arc<dm_tree::procedure_statics::StaticInventory>,String>{
        match artifacts{
            Some(artifacts)=>artifacts.inventory_with_rosters(&procedures.iter().map(|(_,plan)|&**plan).collect::<Vec<_>>(),&procedures.iter().map(|(_,plan)|match plan{ProcedureCapture::Issued(receipt)=>receipt.canonical_declarations().map(Some),ProcedureCapture::Empty(_)=>Ok(None)}).collect::<Result<Vec<_>,String>>()?),
            None=>Ok(std::sync::Arc::new(dm_tree::procedure_statics::StaticInventory::from_plans(procedures.iter().map(|(_,plan)|(plan.procedure,&**plan)))?)),
        }
    }
    fn semantic(error:String)->Result<String,String>{Ok(error)}
    fn finish(draft:dm_tree::initializers::DeclarationDraft<'_>,_frontend:&ColdFrontend,procedures:&[(OccurrenceId,ProcedureCapture)])->Result<StartupPlan,String>{
        dm_tree::initializers::finish_declaration_draft(draft,procedures.iter().map(|(occurrence,plan)|(*occurrence,&**plan))).map(StartupPlan::Compatibility)
    }
    fn body<'f,T>(arena:&dm_tree::frontend::BodyArena<'f>,body:&dm_tree::frontend::BodyOccurrence,
        produce:impl FnOnce(&dm_tree::frontend::ParsedBody<'f>)->T)->Result<T,String>{
        arena.with_parsed(body,produce).map_err(|error|format!("startup body: {error:?}"))
    }
}
impl StartupDemand for CheckedStartup {
    type Failure=StartupFailure;
    fn inventory(procedures:&[(OccurrenceId,ProcedureCapture)],artifacts:Option<&StartupArtifacts>)->Result<std::sync::Arc<dm_tree::procedure_statics::StaticInventory>,StartupFailure>{
        match artifacts{
            Some(artifacts)=>artifacts.inventory_with_original_rosters(&procedures.iter().map(|(_,plan)|&**plan).collect::<Vec<_>>(),&procedures.iter().map(|(_,plan)|match plan{ProcedureCapture::Issued(receipt)=>receipt.canonical_declarations().map(Some),ProcedureCapture::Empty(_)=>Ok(None)}).collect::<Result<Vec<_>,String>>()?).map_err(Into::into),
            None=>Ok(std::sync::Arc::new(dm_tree::procedure_statics::StaticInventory::from_issued_plans(procedures.iter().map(|(_,plan)|(plan.procedure,&**plan,match plan{ProcedureCapture::Issued(receipt)=>Some(receipt),ProcedureCapture::Empty(_)=>None})))?)),
        }
    }
    fn finish(draft:dm_tree::initializers::DeclarationDraft<'_>,frontend:&ColdFrontend,procedures:&[(OccurrenceId,ProcedureCapture)])->Result<StartupPlan,StartupFailure>{
        for (_,capture) in procedures { if let ProcedureCapture::Empty(plan)=capture { if !plan.declarations.is_empty() || !plan.origins.is_empty() { return Err("unissued startup static capture contains rows".into()); } } }
        dm_tree::initializers::finish_declaration_draft_issued(draft,frontend,procedures.iter().filter_map(|(occurrence,capture)|match capture{ProcedureCapture::Issued(receipt)=>Some((*occurrence,receipt)),ProcedureCapture::Empty(_)=>None})).map(StartupPlan::Issued).map_err(Into::into)
    }
    fn semantic(error:StartupFailure)->Result<String,StartupFailure>{
        match error { StartupFailure::Semantic(reason)=>Ok(reason), operation=>Err(operation) }
    }
    fn body<'f,T>(arena:&dm_tree::frontend::BodyArena<'f>,body:&dm_tree::frontend::BodyOccurrence,
        produce:impl FnOnce(&dm_tree::frontend::ParsedBody<'f>)->T)->Result<T,StartupFailure>{
        match arena.with_parsed_checked(body,produce){
            Ok(value)=>Ok(value),
            Err(dm_tree::frontend::BodySyntaxFailure::Syntax(error))=>Err(StartupFailure::Semantic(format!("startup body: {error:?}"))),
            Err(dm_tree::frontend::BodySyntaxFailure::Operational(error))=>Err(StartupFailure::Operational(error)),
        }
    }
}

fn source_failure(error:dm_tree::frontend::BodySyntaxFailure)->StartupFailure{match error{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>StartupFailure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(source)=>StartupFailure::Semantic(format!("startup original source: {source:?}"))}}
/// Source-required capture is a distinct produced role, not a caller-provided
/// readiness boolean. It owns the SAME startup facts and retains no new model.
struct OriginalStartupDemand;
impl StartupDemand for OriginalStartupDemand{
    type Failure=StartupFailure;
    fn source<'f>(front:&'f ColdFrontend)->Result<Option<dm_tree::frontend::OriginalDeclarationExpressionContext<'f>>,Self::Failure>{
        let context=front.original_declaration_expression_context().map_err(source_failure)?;
        context.with_admission(&mut|_|Ok(())).map_err(source_failure)?;Ok(Some(context))
    }
    fn cached(front:&ColdFrontend,body:&dm_tree::frontend::BodyOccurrence,artifacts:&StartupArtifacts,key:&[u8],source:Option<&dm_tree::frontend::OriginalDeclarationExpressionContext<'_>>)->Result<Option<std::sync::Arc<dm_tree::frontend::IssuedStaticPlan>>,Self::Failure>{
        let source=source.ok_or_else(||StartupFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"original startup admission unavailable")))?;
        artifacts.lookup_original(key,&mut|payload|{
            let Ok(plan)=payload.bind(front,body)else{return Ok(None)};
            let mut admitted=false;
            source.with_admission(&mut|a|{admitted=plan.admitted_by(a)?;Ok(())}).map_err(source_failure)?;
            Ok(admitted.then_some(plan))
        })
    }
    fn remember(artifacts:&StartupArtifacts,key:Vec<u8>,plan:&std::sync::Arc<dm_tree::frontend::IssuedStaticPlan>){artifacts.remember_original(key,plan)}
    fn admit_static(plan:&std::sync::Arc<dm_tree::frontend::IssuedStaticPlan>,source:Option<&dm_tree::frontend::OriginalDeclarationExpressionContext<'_>>)->Result<(),Self::Failure>{
        let source=source.ok_or_else(||StartupFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"original startup admission unavailable")))?;
        let mut admitted=false;source.with_admission(&mut|a|{admitted=plan.admitted_by(a)?;Ok(())}).map_err(source_failure)?;
        if !admitted{return Err(StartupFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"original startup requires actual current admitted body producer")));}Ok(())
    }
    fn finish(draft:dm_tree::initializers::DeclarationDraft<'_>,front:&ColdFrontend,procedures:&[(OccurrenceId,ProcedureCapture)])->Result<StartupPlan,Self::Failure>{CheckedStartup::finish(draft,front,procedures)}
    fn inventory(procedures:&[(OccurrenceId,ProcedureCapture)],artifacts:Option<&StartupArtifacts>)->Result<std::sync::Arc<dm_tree::procedure_statics::StaticInventory>,Self::Failure>{CheckedStartup::inventory(procedures,artifacts)}
    fn semantic(error:Self::Failure)->Result<String,Self::Failure>{CheckedStartup::semantic(error)}
    fn body<'f,T>(arena:&dm_tree::frontend::BodyArena<'f>,body:&dm_tree::frontend::BodyOccurrence,produce:impl FnOnce(&dm_tree::frontend::ParsedBody<'f>)->T)->Result<T,Self::Failure>{
        arena.with_parsed_checked(body,|parsed|{
            if !parsed.statement_body().is_some_and(|owner|owner.has_native_literal_syntax()){
                return Err(StartupFailure::Operational(std::io::Error::new(std::io::ErrorKind::NotConnected,"original startup requires admitted canonical statement syntax")));
            }
            Ok(produce(parsed))
        }).map_err(source_failure)?
    }
}
/// Current source-required view. Only actual capture can construct this role;
/// detached/compatibility facts cannot certify body resource admission.
pub struct OriginalStartup<'a>{captured:CapturedStartup<'a>}
impl<'a> std::ops::Deref for OriginalStartup<'a>{type Target=CapturedStartup<'a>;fn deref(&self)->&Self::Target{&self.captured}}
impl OriginalStartup<'_>{
 pub(crate) fn source_static_receipt(&self,occurrence:OccurrenceId)->Option<&std::sync::Arc<dm_tree::frontend::IssuedStaticPlan>>{let index=*self.captured.facts.procedure_index.get(&occurrence)?;match &self.captured.facts.procedures.get(index)?.1{ProcedureCapture::Issued(receipt)=>Some(receipt),ProcedureCapture::Empty(_)=>None}}
pub fn issued_initializer_plan(&self)->&dm_tree::initializers::IssuedInitializerPlan{self.captured.issued_initializer_plan().expect("source-required producer finishes an issued plan")}}

pub struct CapturedStartup<'a> {
    frontend: &'a ColdFrontend,
    revision: Option<&'a dm_tree::frontend::FrontendRevision>,
    facts: std::sync::Arc<StartupFacts>,
}
/// Owned startup declarations and static plans, issued by one immutable frontend
/// revision. No resolver or reference into a movable frontend is retained.
pub struct StartupFacts {
    issuance: Option<dm_tree::frontend::FrontendIssuance>,
    plan: StartupPlan,
    procedures: Vec<(OccurrenceId, ProcedureCapture)>,
    procedure_index: std::collections::HashMap<OccurrenceId, usize>,
    static_inventory: std::sync::Arc<dm_tree::procedure_statics::StaticInventory>,
    unit_members: std::sync::Arc<
        std::collections::BTreeMap<crate::lowering::UnitIdentity, dm_tree::MemberId>,
    >,
}
/// Exactly one plan allocation/row family is owned in either mode.
/// The issued branch cannot be manufactured from a detached public plan.
enum StartupPlan {
    Compatibility(InitializerPlan),
    Issued(dm_tree::initializers::IssuedInitializerPlan),
}
impl std::ops::Deref for StartupPlan {
    type Target=InitializerPlan;
    fn deref(&self)->&InitializerPlan {match self{Self::Compatibility(plan)=>plan,Self::Issued(plan)=>plan.plan()}}
}
impl StartupPlan {
    fn replace_symbol_overlay(&mut self,symbols:std::sync::Arc<dm_ir::SymbolTable>)->Result<(),String>{
        match self{Self::Compatibility(plan)=>{plan.symbols=symbols;Ok(())},Self::Issued(plan)=>plan.with_symbol_overlay(symbols)}
    }
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
    /// Only the checked original draft/static producer can issue this owner.
    /// Current source/mapping validation remains the borrowing factory's duty.
    pub fn issued_initializer_plan(&self)->Option<&dm_tree::initializers::IssuedInitializerPlan>{
        match &self.plan{StartupPlan::Issued(plan)=>Some(plan),StartupPlan::Compatibility(_)=>None}
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

    pub fn plan(&self) -> &InitializerPlan {
        &self.plan
    }
    pub fn procedure(&self, occurrence: OccurrenceId) -> Option<&StaticPlan> {
        self.procedure_index
            .get(&occurrence)
            .map(|index| &*self.procedures[*index].1)
    }

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
    capture_impl_with_bodies_and_artifacts(frontend, executor, bodies, prefilter, None, None)
}
fn capture_impl_with_bodies_and_artifacts(
    frontend: &ColdFrontend,
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    prefilter: bool,
    artifacts: Option<&StartupArtifacts>,
    prepared: Option<&crate::lowering::PreparedBodyRoster<'_>>,
) -> Result<StartupFacts, String> {
    capture_impl_with_bodies_and_artifacts_using::<CompatibilityStartup>(frontend,executor,bodies,prefilter,artifacts,prepared)
}
fn capture_impl_with_bodies_and_artifacts_using<D:StartupDemand>(
    frontend: &ColdFrontend,
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    prefilter: bool,
    artifacts: Option<&StartupArtifacts>,
    prepared: Option<&crate::lowering::PreparedBodyRoster<'_>>,
) -> Result<StartupFacts,D::Failure> {
    let source = D::source(frontend)?;
    let prepared = prepared.filter(|roster| roster.authenticates(frontend));
    let units = match artifacts {
        Some(artifacts) => artifacts.unit_members(frontend)?,
        None => std::sync::Arc::new(
            crate::driver_facts::unit_members(frontend).map_err(|error| error.to_string())?,
        ),
    };
    let roster = frontend.callable_roster()?;
    let mut keys = std::collections::HashMap::new();
    if let Some(artifacts) = artifacts {
        // One independent key per body (a hash of its source): computed on the workers, then
        // gathered in body order.
        let key_of = |body: &dm_tree::frontend::BodyOccurrence| -> Result<Option<Vec<u8>>, String> {
            let shared = prepared.and_then(|roster| roster.current(body));
            let owned = if shared.is_none() {
                Some(
                    frontend
                        .body_input(body)
                        .map_err(|e| format!("startup body: {e:?}"))?,
                )
            } else {
                None
            };
            let input = shared
                .map(|row| row.input())
                .or(owned.as_ref())
                .expect("current or ordinary input");
            let source = input.source();
            if !prefilter || input.may_contain_stored_declarations() {
                let identity = roster
                    .identity_for_member(body.member)
                    .ok_or("startup procedure identity missing")?;
                Ok(Some(artifacts::key(identity, source)))
            } else {
                Ok(None)
            }
        };
        let computed: Vec<_> = executor.install(|| {
            use rayon::prelude::*;
            frontend
                .bodies
                .par_iter()
                .with_min_len(256)
                .map(|body| (body.member, key_of(body)))
                .collect()
        });
        keys.extend(computed);
        artifacts.retain_keys(
            keys.values()
                .filter_map(|result| result.as_ref().ok()?.as_deref()),
            roster
                .members()
                .iter()
                .filter_map(|member| roster.identity_for_member(*member)),
        );
    }
    dm_profile::request_mark("startup.keys_done");
    let capture_body = |body: &dm_tree::frontend::BodyOccurrence| {
        let identity = roster
            .identity_for_member(body.member)
            .ok_or("startup procedure identity missing")?;
        let shared = prepared.and_then(|roster| roster.current(body));
        let owned = if shared.is_none() {
            Some(
                frontend
                    .body_input(body)
                    .map_err(|e| format!("startup body: {e:?}"))?,
            )
        } else {
            None
        };
        let input = shared
            .map(|row| row.input())
            .or(owned.as_ref())
            .expect("current or ordinary input");
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
            if let Some(plan)=D::cached(frontend,body,artifacts,key,source.as_ref())?{
                return Ok((body.declaration,ProcedureCapture::Issued(plan)));
            }
        }
        let plan=D::body(bodies,body,|parsed|parsed.capture_stored_declarations(identity))??;
        D::admit_static(&plan,source.as_ref())?;
        if let (Some(artifacts), Some(key)) = (artifacts, candidate_key) {
            D::remember(artifacts,key.to_vec(),&plan);
        }
        Ok::<_,D::Failure>((body.declaration,ProcedureCapture::Issued(plan)))
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
                            .collect::<Result<Vec<_>,D::Failure>>()
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
    // All workers have joined. Preserve actual operational failure from any
    // completed chunk before selecting the first source-ordered semantic error.
    let mut first_semantic=None;
    for result in chunks {
        match result {
            Ok(rows)=>procedures.extend(rows),
            Err(error)=>match D::semantic(error) {
                Err(operation)=>return Err(operation),
                Ok(reason)=>if first_semantic.is_none(){first_semantic=Some(reason)},
            },
        }
    }
    if let Some(reason)=first_semantic{return Err(reason.into());}
    dm_profile::request_mark("startup.procs_collected");
    let draft_timer = dm_profile::detail_timer("startup.declaration_draft");
    let base = dm_tree::initializers::capture_declaration_draft(
        &frontend.snapshot,
        &frontend.emission_order,
    )
    .map_err(|e| format!("startup declarations: {e:?}"))?;
    drop(draft_timer);
    let finish_timer = dm_profile::detail_timer("startup.finish_draft");
    let plan = D::finish(base,frontend,&procedures)?;
    drop(finish_timer);
    dm_profile::request_mark("startup.plan_done");
    let procedure_index = procedures
        .iter()
        .enumerate()
        .map(|(index, (occurrence, _))| (*occurrence, index))
        .collect();
    let static_inventory = D::inventory(&procedures,artifacts)?;

    dm_profile::request_mark("startup.inventory_done");
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
pub fn capture_with_executor_and_bodies_checked<'a>(
    frontend: &'a ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
) -> Result<CapturedStartup<'a>,StartupFailure> {
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    let captured=CapturedStartup {
        frontend,
        revision: None,
        facts: capture_facts_with_executor_and_bodies_and_artifacts_using::<CheckedStartup>(frontend,spellings,executor,bodies,None,None)?,
    };
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    Ok(captured)
}
/// Explicit source-required capture. Current-code/counter cache acceptance
/// precedes claims; a rejected parent uses the SAME checked BodyArena producer.
pub fn capture_original_with_executor_and_bodies_checked<'a>(frontend:&'a ColdFrontend,spellings:&[(dm_ir::SymbolId,std::sync::Arc<[u8]>)],executor:&dm_exec::BuildExecutor,bodies:&dm_tree::frontend::BodyArena<'_>)->Result<OriginalStartup<'a>,StartupFailure>{
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    let facts=capture_facts_with_executor_and_bodies_and_artifacts_using::<OriginalStartupDemand>(frontend,spellings,executor,bodies,None,None)?;
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    Ok(OriginalStartup{captured:CapturedStartup{frontend,revision:None,facts}})
}
/// Same original capture with existing artifact acceleration; no second store.
pub fn capture_original_with_artifacts_checked<'a>(frontend:&'a ColdFrontend,spellings:&[(dm_ir::SymbolId,std::sync::Arc<[u8]>)],executor:&dm_exec::BuildExecutor,bodies:&dm_tree::frontend::BodyArena<'_>,artifacts:&StartupArtifacts)->Result<OriginalStartup<'a>,StartupFailure>{
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    let facts=capture_facts_with_executor_and_bodies_and_artifacts_using::<OriginalStartupDemand>(frontend,spellings,executor,bodies,Some(artifacts),None)?;
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    Ok(OriginalStartup{captured:CapturedStartup{frontend,revision:None,facts}})
}
/// Production capture borrows the same current body admissions as lowering.
pub(crate) fn capture_with_prepared_bodies<'a>(
    frontend: &'a ColdFrontend,
    revision: Option<&'a dm_tree::frontend::FrontendRevision>,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    artifacts: Option<&StartupArtifacts>,
    prepared: &crate::lowering::PreparedBodyRoster<'_>,
) -> Result<CapturedStartup<'a>, String> {
    if revision.is_some_and(|revision| !std::ptr::eq::<ColdFrontend>(&**revision, frontend)) {
        return Err("startup revision belongs to another current frontend".into());
    }
    let mut facts = capture_facts_with_executor_and_bodies_and_artifacts(
        frontend,
        spellings,
        executor,
        bodies,
        artifacts,
        Some(prepared),
    )?;
    if let Some(revision) = revision {
        std::sync::Arc::get_mut(&mut facts)
            .expect("new startup facts are exclusively owned")
            .issuance = Some(revision.issuance());
    }
    Ok(CapturedStartup {
        frontend,
        revision,
        facts,
    })
}
pub(crate) fn capture_with_prepared_bodies_checked<'a>(
    frontend: &'a ColdFrontend,
    revision: Option<&'a dm_tree::frontend::FrontendRevision>,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    artifacts: Option<&StartupArtifacts>,
    prepared: &crate::lowering::PreparedBodyRoster<'_>,
) -> Result<CapturedStartup<'a>,StartupFailure> {
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    if revision.is_some_and(|revision| !std::ptr::eq::<ColdFrontend>(&**revision, frontend)) {
        return Err("startup revision belongs to another current frontend".into());
    }
    let mut facts = capture_facts_with_executor_and_bodies_and_artifacts_using::<CheckedStartup>(
        frontend,
        spellings,
        executor,
        bodies,
        artifacts,
        Some(prepared),
    )?;
    if let Some(revision) = revision {
        std::sync::Arc::get_mut(&mut facts)
            .expect("new startup facts are exclusively owned")
            .issuance = Some(revision.issuance());
    }
    let captured=CapturedStartup {
        frontend,
        revision,
        facts,
    };
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    Ok(captured)
}
/// Source-required prepared-body capture uses the SAME original producer and revision guards.
pub(crate) fn capture_original_with_prepared_bodies_checked<'a>(
    frontend: &'a ColdFrontend,
    revision: Option<&'a dm_tree::frontend::FrontendRevision>,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    artifacts: Option<&StartupArtifacts>,
    prepared: &crate::lowering::PreparedBodyRoster<'_>,
) -> Result<OriginalStartup<'a>,StartupFailure> {
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    if revision.is_some_and(|revision| !std::ptr::eq::<ColdFrontend>(&**revision, frontend)) {
        return Err("startup revision belongs to another current frontend".into());
    }
    let mut facts = capture_facts_with_executor_and_bodies_and_artifacts_using::<OriginalStartupDemand>(
        frontend,
        spellings,
        executor,
        bodies,
        artifacts,
        Some(prepared),
    )?;
    if let Some(revision) = revision {
        std::sync::Arc::get_mut(&mut facts)
            .expect("new startup facts are exclusively owned")
            .issuance = Some(revision.issuance());
    }
    let captured=CapturedStartup {
        frontend,
        revision,
        facts,
    };
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    Ok(OriginalStartup{captured})
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
        revision, spellings, executor, bodies, artifacts, None,
    )?;
    std::sync::Arc::get_mut(&mut facts)
        .expect("new startup facts are exclusively owned")
        .issuance = Some(revision.issuance());
    Ok(facts)
}
pub fn capture_revision_facts_with_executor_and_bodies_and_artifacts_checked(
    revision: &dm_tree::frontend::FrontendRevision,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    artifacts: Option<&StartupArtifacts>,
) -> Result<std::sync::Arc<StartupFacts>,StartupFailure> {
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
    let mut facts=capture_facts_with_executor_and_bodies_and_artifacts_using::<CheckedStartup>(
        revision, spellings, executor, bodies, artifacts, None,
    )?;
    std::sync::Arc::get_mut(&mut facts)
        .expect("new startup facts are exclusively owned")
        .issuance = Some(revision.issuance());
    crate::daemon::control::checkpoint().map_err(StartupFailure::Operational)?;
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
        frontend, spellings, executor, bodies, None, None,
    )
}
fn capture_facts_with_executor_and_bodies_and_artifacts(
    frontend: &ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    artifacts: Option<&StartupArtifacts>,
    prepared: Option<&crate::lowering::PreparedBodyRoster<'_>>,
) -> Result<std::sync::Arc<StartupFacts>, String> {
    capture_facts_with_executor_and_bodies_and_artifacts_using::<CompatibilityStartup>(frontend,spellings,executor,bodies,artifacts,prepared)
}
fn capture_facts_with_executor_and_bodies_and_artifacts_using<D:StartupDemand>(
    frontend: &ColdFrontend,
    spellings: &[(dm_ir::SymbolId, std::sync::Arc<[u8]>)],
    executor: &dm_exec::BuildExecutor,
    bodies: &dm_tree::frontend::BodyArena<'_>,
    artifacts: Option<&StartupArtifacts>,
    prepared: Option<&crate::lowering::PreparedBodyRoster<'_>>,
) -> Result<std::sync::Arc<StartupFacts>,D::Failure> {
    let mut startup = capture_impl_with_bodies_and_artifacts_using::<D>(
        frontend, executor, bodies, true, artifacts, prepared,
    )?;
    dm_profile::request_mark("startup.impl_done");
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
    startup.plan.replace_symbol_overlay(std::sync::Arc::new(symbols))?;
    dm_profile::request_mark("startup.spellings_done");
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
    fn evaluate_original_write_checked<'source>(&self,input:&dm_tree::frontend::OriginalInitializerExpressionInput<'source>,write:&dm_ir::InitializerWrite)->Result<(crate::initializer_policy::Evaluation,Option<crate::initializer_policy::ScopedPreparedInitializerExpression<'source>>),crate::initializer_policy::InitializerFailure>{
        if write.lexical_procedure.is_some(){crate::initializer_policy::CapturedInitializerEvaluator::evaluate_original_write_checked(&crate::driver_facts::DriverEvaluator{pure_calls:self.ordinary.pure_calls(),resource_search_context:self.resource_search_context,resolver:self.resolver,symbols:self.symbols},input,write)}else{self.ordinary.evaluate_original_write_checked(input,write)}
    }
    fn evaluate_original_dimension_checked(&self,input:&dm_tree::frontend::OriginalInitializerDimensionInput<'_>,write:&dm_ir::InitializerWrite)->Result<crate::initializer_policy::Evaluation,crate::initializer_policy::InitializerFailure>{
        if write.lexical_procedure.is_some(){crate::initializer_policy::CapturedInitializerEvaluator::evaluate_original_dimension_checked(&crate::driver_facts::DriverEvaluator{pure_calls:self.ordinary.pure_calls(),resource_search_context:self.resource_search_context,resolver:self.resolver,symbols:self.symbols},input,write)}else{self.ordinary.evaluate_original_dimension_checked(input,write)}
    }
    fn evaluate_original_ast_write_checked<'source>(&self,input:&dm_tree::frontend::OriginalInitializerExpressionInput<'source>,write:&dm_ir::InitializerWrite,root:&dm_tree::frontend::OriginalInitializerExpression<'source>,ast:&dm_syntax::Expr,symbols:&dm_ir::SymbolTable)->Result<crate::initializer_policy::Evaluation,crate::initializer_policy::InitializerFailure>{
        if write.lexical_procedure.is_some(){crate::initializer_policy::CapturedInitializerEvaluator::evaluate_original_ast_write_checked(&crate::driver_facts::DriverEvaluator{pure_calls:self.ordinary.pure_calls(),resource_search_context:self.resource_search_context,resolver:self.resolver,symbols:self.symbols},input,write,root,ast,symbols)}else{self.ordinary.evaluate_original_ast_write_checked(input,write,root,ast,symbols)}
    }

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

#[cfg(test)]
#[path = "startup_prepared_roster_tests.rs"]
mod prepared_roster_tests;

#[cfg(test)]
mod checked_capture_tests {
    use super::*;
    use std::{path::Path,sync::Arc};
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self,_:&Path)->Result<String,String>{
            Ok("/proc/probe()\n    var/static/value = 1\n    return value\n".into())
        }
    }
    #[test]
    fn checked_startup_actual_body_operation_is_not_artifact_or_semantic_failure() {
        let db=Arc::new(crate::query_db::QueryDb::default());
        let frontend=dm_tree::frontend::build(Path::new("startup-operation.dme"),&Source,&Default::default(),1)
            .unwrap().with_body_queries(db.clone());
        let executor=dm_exec::BuildExecutor::new(1).unwrap();
        let arena=dm_tree::frontend::BodyArena::new(&frontend);
        let error=executor.install(||{
            let _scheduled=db.fail_body_syntax_after_for_test(0,std::io::Error::from_raw_os_error(1450));
            capture_with_executor_and_bodies_checked(&frontend,&[],&executor,&arena)
                .err().expect("real current body failure")
        });
        assert!(matches!(error,StartupFailure::Operational(ref error) if error.raw_os_error()==Some(1450)));
        let actual=capture_with_executor_and_bodies_checked(&frontend,&[],&executor,&arena).unwrap();
        let old=capture_with_executor_and_bodies(&frontend,&[],&executor,&arena).unwrap();
        assert_eq!(actual.plan.writes,old.plan.writes);
        assert_eq!(actual.plan.origins,old.plan.origins);
        assert_eq!(actual.procedures.len(),old.procedures.len());
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed,1);
    }
    #[test]
    fn checked_startup_completed_sibling_operation_precedes_first_source_rejection() {
        use std::sync::atomic::{AtomicBool,AtomicUsize,AtomicU64,Ordering};
        struct Two;
        impl dm_preprocess::SourceProvider for Two {
            fn read(&self,_:&Path)->Result<String,String>{Ok(
                "/proc/first()\n    var/static/value = 1\n    var/static/value = 2\n/proc/second()\n    var/static/other = 3\n".into())}
        }
        struct FailSecond {db:Arc<crate::query_db::QueryDb>,target:AtomicU64,once:AtomicBool,calls:AtomicUsize}
        impl std::fmt::Debug for FailSecond {
            fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("FailSecond")}
        }
        impl dm_tree::frontend::BodySyntaxQueries for FailSecond {
            fn syntax(&self,input:&Arc<dm_tree::frontend::BodySyntaxInput>)
                ->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::Diagnostic>{
                dm_tree::frontend::BodySyntaxQueries::syntax(self.db.as_ref(),input)
            }
            fn syntax_checked(&self,input:&Arc<dm_tree::frontend::BodySyntaxInput>)
                ->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>{
                self.calls.fetch_add(1,Ordering::SeqCst);
                let _schedule=(input.key()==self.target.load(Ordering::SeqCst) && self.once.swap(false,Ordering::SeqCst))
                    .then(||self.db.fail_body_syntax_after_for_test(0,std::io::Error::from_raw_os_error(1450)));
                dm_tree::frontend::BodySyntaxQueries::syntax_checked(self.db.as_ref(),input)
            }
        }
        let db=Arc::new(crate::query_db::QueryDb::default());
        let frontend=dm_tree::frontend::build(Path::new("startup-joined-operation.dme"),&Two,&Default::default(),1).unwrap();
        assert_eq!(frontend.bodies.len(),2);
        let provider=Arc::new(FailSecond{db:db.clone(),target:AtomicU64::new(0),once:AtomicBool::new(true),calls:AtomicUsize::new(0)});
        let frontend=frontend.with_body_queries(provider.clone());
        provider.target.store(frontend.body_archive().unwrap().syntax_inputs().unwrap()[1].key(),Ordering::SeqCst);
        let executor=dm_exec::BuildExecutor::new(2).unwrap();
        let arena=dm_tree::frontend::BodyArena::new(&frontend);
        let error=capture_with_executor_and_bodies_checked(&frontend,&[],&executor,&arena).err().expect("joined sibling IO");
        assert!(matches!(error,StartupFailure::Operational(ref error) if error.raw_os_error()==Some(1450)));
        assert_eq!(provider.calls.load(Ordering::SeqCst),2,"both original chunks completed");
        let retry=capture_with_executor_and_bodies_checked(&frontend,&[],&executor,&arena).err().expect("original duplicate remains");
        assert!(matches!(retry,StartupFailure::Semantic(ref reason) if reason=="same-name scoped procedure statics require a certified lexical slot policy"),"{retry:?}");
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed,2);
    }
    #[test]
    fn checked_startup_cancelled_empty_capture_returns_no_facts_then_recovers() {
        struct Empty;
        impl dm_preprocess::SourceProvider for Empty {
            fn read(&self,_:&Path)->Result<String,String>{Ok(String::new())}
        }
        let frontend=dm_tree::frontend::build(Path::new("startup-empty.dme"),&Empty,&Default::default(),1).unwrap();
        let executor=dm_exec::BuildExecutor::new(1).unwrap();
        let arena=dm_tree::frontend::BodyArena::new(&frontend);
        let token=crate::daemon::control::Cancellation::default();
        let binding=crate::daemon::control::bind_with_deadline(token.clone(),
            std::time::Instant::now()+std::time::Duration::from_secs(300));
        token.cancel();
        let error=capture_with_executor_and_bodies_checked(&frontend,&[],&executor,&arena)
            .err().expect("empty checked capture still observes current cancellation");
        assert!(matches!(error,StartupFailure::Operational(ref error) if error.kind()==std::io::ErrorKind::Interrupted));
        drop(binding);
        assert!(capture_with_executor_and_bodies_checked(&frontend,&[],&executor,&arena).is_ok());
    }
    #[test]
    fn checked_startup_last_original_body_read_cancel_precedes_returning_facts() {
        struct CancelAfterDb {db:Arc<crate::query_db::QueryDb>,token:crate::daemon::control::Cancellation}
        impl std::fmt::Debug for CancelAfterDb {
            fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{
                f.debug_struct("CancelAfterDb").finish_non_exhaustive()
            }
        }
        impl dm_tree::frontend::BodySyntaxQueries for CancelAfterDb {
            fn syntax(&self,input:&Arc<dm_tree::frontend::BodySyntaxInput>)
                ->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::Diagnostic>{
                dm_tree::frontend::BodySyntaxQueries::syntax(self.db.as_ref(),input)
            }
            fn syntax_checked(&self,input:&Arc<dm_tree::frontend::BodySyntaxInput>)
                ->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>{
                let result=dm_tree::frontend::BodySyntaxQueries::syntax_checked(self.db.as_ref(),input);
                self.token.cancel();result
            }
        }
        let token=crate::daemon::control::Cancellation::default();
        let db=Arc::new(crate::query_db::QueryDb::default());
        let frontend=dm_tree::frontend::build(Path::new("startup-late-cancel.dme"),&Source,&Default::default(),1)
            .unwrap().with_body_queries(Arc::new(CancelAfterDb{db:db.clone(),token:token.clone()}));
        let executor=dm_exec::BuildExecutor::new(1).unwrap();
        let arena=dm_tree::frontend::BodyArena::new(&frontend);
        let binding=crate::daemon::control::bind_with_deadline(token.clone(),
            std::time::Instant::now()+std::time::Duration::from_secs(300));
        let error=capture_with_executor_and_bodies_checked(&frontend,&[],&executor,&arena)
            .err().expect("last actual native read cancelled request");
        assert!(matches!(error,StartupFailure::Operational(ref error) if error.kind()==std::io::ErrorKind::Interrupted));
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed,1);
        drop(binding);
        let retry_token=crate::daemon::control::Cancellation::default();
        let retry_binding=crate::daemon::control::bind_with_deadline(retry_token,
            std::time::Instant::now()+std::time::Duration::from_secs(300));
        assert!(capture_with_executor_and_bodies_checked(&frontend,&[],&executor,&arena).is_ok());
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed,1);
        drop(retry_binding);
    }
}

#[cfg(test)]
mod issued_plan_tests {
 use super::*;use std::path::Path;
 struct Source(&'static str);
 impl dm_preprocess::SourceProvider for Source{fn read(&self,_:&Path)->Result<String,String>{Ok(self.0.into())}}
 #[test]
 fn checked_startup_retains_one_issued_complete_plan_with_real_static_receipts_and_compatibility_stays_plain(){
  let front=dm_tree::frontend::build(Path::new("checked-issued-startup.dme"),&Source("var/a=1\n/proc/p()\n    var/static/local=2\n    return local\nvar/b=3\n/proc/empty()\n    return 1\n"),&Default::default(),1).unwrap();
  let executor=dm_exec::BuildExecutor::new(1).unwrap();let bodies=dm_tree::frontend::BodyArena::new(&front);
  let old=capture_with_executor_and_bodies(&front,&[],&executor,&bodies).unwrap();
  assert!(old.issued_initializer_plan().is_none());
  let checked=capture_with_executor_and_bodies_checked(&front,&[],&executor,&bodies).unwrap();
  let issued=checked.issued_initializer_plan().expect("checked private draft/static merge issues the plan");
  assert!(std::ptr::eq(issued.plan(),checked.plan()),"one underlying plan, not a copied semantic model");assert!(issued.matches_snapshot(&front.snapshot));assert!(issued.matches_frontend(&front));
  assert_eq!(old.plan().writes,checked.plan().writes);assert_eq!(old.plan().origins,checked.plan().origins);assert_eq!(old.plan().identity,checked.plan().identity);
  assert!(checked.procedure_captures().iter().any(|(_,capture)|matches!(capture,ProcedureCapture::Issued(_))));
  assert!(checked.procedure_captures().iter().any(|(_,capture)|matches!(capture,ProcedureCapture::Empty(_))));
  let added=dm_ir::SymbolId::of("asset.png");
  let spelled=capture_with_executor_and_bodies_checked(&front,&[(added,std::sync::Arc::from(b"asset.png".as_slice()))],&executor,&bodies).unwrap();
  let issued=spelled.issued_initializer_plan().unwrap();assert_eq!(issued.plan().symbols.text(added),Some("asset.png"));assert!(issued.matches_snapshot(&front.snapshot));
  assert_eq!(spelled.plan().writes,checked.plan().writes);assert_eq!(spelled.plan().origins,checked.plan().origins);
 }
}

#[cfg(test)]
#[path="startup_original_tests.rs"]
mod original_tests;
