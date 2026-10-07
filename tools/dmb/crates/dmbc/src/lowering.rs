//! Bounded cold procedure driver. ABI interpretation remains an explicit policy.
use crate::debug_sources::{DebugOrigins, FrontendDebugProvider};
use crate::procedure_policy::{AbiContext, PreparedAbi, PreparedReplay, PreparedUnit};
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_codegen_byond::{compile_simple_proc_with_resolver_and_debug, ProcedureInputs};
use dm_ir::{ProcedureMetadata, Resolver, SymbolId, SymbolTable};
use dm_tree::{
    frontend::{BodyOccurrence, ColdFrontend, DiagnosticKind, SourceLocation},
    MemberKind,
};
use std::cell::RefCell;
use std::{collections::BTreeMap, sync::Arc, thread};
#[derive(Default)]
struct MemoCapture {
    debug: Vec<usize>,
    errors: Option<Vec<dm_codegen_byond::LowerError>>,
}
fn replay_errors(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    identity: dm_ir::ProcedureIdentity,
    errors: Vec<dm_codegen_byond::LowerError>,
) -> Option<Vec<LoweringDiagnostic>> {
    errors
        .into_iter()
        .map(|error| {
            let origin = match error.span {
                None => body.source.clone(),
                Some(span) => {
                    if span.end
                        > body
                            .expanded_span
                            .end
                            .checked_sub(body.expanded_span.start)?
                        || span.start > span.end
                    {
                        return None;
                    }
                    frontend.location(body.expanded_span.start.checked_add(span.start)?)?
                }
            };
            Some(LoweringDiagnostic {
                kind: match error.kind {
                    dm_codegen_byond::LowerErrorKind::SourceError => DiagnosticKind::SourceError,
                    dm_codegen_byond::LowerErrorKind::UnsupportedModel => {
                        DiagnosticKind::UnsupportedModel
                    }
                    dm_codegen_byond::LowerErrorKind::Internal => return None,
                },
                identity: Some(UnitIdentity {
                    owner: identity.owner,
                    name: identity.name,
                    namespace: if identity.verb {
                        Namespace::Verb
                    } else {
                        Namespace::Proc
                    },
                    occurrence: identity.occurrence,
                }),
                origin,
                message: if error.statement.is_empty() {
                    error.reason
                } else {
                    format!("{}: {}", error.statement, error.reason)
                },
            })
        })
        .collect()
}
struct MemoDebugProvider<'a> {
    original: FrontendDebugProvider<'a>,
    base: usize,
    entry: usize,
    capture: Option<&'a RefCell<MemoCapture>>,
}
impl dm_codegen_byond::DebugSourceProvider for MemoDebugProvider<'_> {
    fn entry_ordinal(&self) -> Result<u32, String> {
        let ordinal = self.original.entry_ordinal()?;
        if let Some(capture) = self.capture {
            let mut capture = capture.borrow_mut();
            if capture.debug.len() <= ordinal as usize {
                capture.debug.resize(ordinal as usize + 1, usize::MAX);
            }
            capture.debug[ordinal as usize] =
                self.entry.checked_sub(self.base).unwrap_or(usize::MAX);
        }
        Ok(ordinal)
    }
    fn ordinal(&self, offset: usize) -> Result<u32, String> {
        let ordinal = self.original.ordinal(offset)?;
        if let Some(capture) = self.capture {
            // An unrebased legacy/default expression is uncacheable; recording
            // it must never introduce a new compiler failure.
            let relative = offset.checked_sub(self.base).unwrap_or(usize::MAX);
            let mut capture = capture.borrow_mut();
            if capture.debug.len() <= ordinal as usize {
                capture.debug.resize(ordinal as usize + 1, usize::MAX);
            }
            capture.debug[ordinal as usize] = relative;
        }
        Ok(ordinal)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Namespace {
    Proc,
    Verb,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct UnitIdentity {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub namespace: Namespace,
    pub occurrence: u32,
}
/// Converts signature/default/annotation semantics using one pinned compiler ABI.
/// Reject unsupported flags/value-source/default decoding rather than guessing.
pub trait AbiPolicy: Sync {
    /// Custom policies retain full parsing. Only an authoritative captured policy
    /// can issue a fixed-transform replay preparation for the current body.
    fn prepare_issued(
        &self,
        _metadata: &ProcedureMetadata,
        _input: &dm_tree::frontend::IssuedBodyInput<'_>,
        _context: &AbiContext<'_>,
    ) -> Result<Option<PreparedReplay>, String> {
        Ok(None)
    }
    /// Issued production parses retain the existing behavior for custom policies.
    fn prepare_captured(
        &self,
        metadata: &ProcedureMetadata,
        parsed: &dm_tree::frontend::ParsedBody<'_>,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, String> {
        self.prepare(metadata, parsed.item(), context)
    }
    fn inputs(
        &self,
        identity: UnitIdentity,
        metadata: &ProcedureMetadata,
        symbols: &SymbolTable,
        origin: &SourceLocation,
    ) -> Result<ProcedureInputs, String>;
    /// Existing local-only policies are deliberately unauthoritative for DMB output.
    fn prepare(
        &self,
        metadata: &ProcedureMetadata,
        parsed: &dm_syntax::Item,
        context: &AbiContext<'_>,
    ) -> Result<PreparedUnit, String> {
        self.inputs(context.identity, metadata, context.symbols, context.origin)
            .map(|inputs| PreparedUnit::local_only(inputs, parsed))
    }
}
#[derive(Clone, Copy, Debug)]
pub struct LoweringConfig {
    pub workers: usize,
    pub max_chunk: usize,
}
impl Default for LoweringConfig {
    fn default() -> Self {
        Self {
            workers: 1,
            max_chunk: 32,
        }
    }
}
#[derive(Clone)]
pub struct LoweredUnit {
    pub identity: UnitIdentity,
    /// Exact immutable tree selection, independent of encounter order.
    pub effective: bool,
    pub origin: BodyOccurrence,
    pub code: ResolverProc,
    pub metadata: Arc<ProcedureMetadata>,
    pub abi: Option<Arc<PreparedAbi>>,
    pub debug_origins: DebugOrigins,
    pub source_helpers: Vec<crate::argument_sources::LoweredHelper>,
}
#[derive(Clone, Debug)]
pub struct LoweringDiagnostic {
    pub kind: DiagnosticKind,
    pub identity: Option<UnitIdentity>,
    pub origin: SourceLocation,
    pub message: String,
}
#[derive(Default)]
pub struct LoweringBatch {
    pub units: Vec<LoweredUnit>,
    pub diagnostics: Vec<LoweringDiagnostic>,
}
pub fn lower_frontend<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
) -> LoweringBatch {
    lower_frontend_impl(frontend, host, policy, config, None, None)
}
/// Startup admission is an exact captured body inventory, never a bypass flag.
pub fn lower_frontend_with_statics<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
) -> LoweringBatch {
    lower_frontend_impl(frontend, host, policy, config, Some(startup), None)
}
/// Memo admission retains the cold startup/ABI guards. The caller supplies a
/// compiler policy identity; it must not substitute a whole-program tree hash.
pub fn lower_frontend_with_memo<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: &crate::startup::CapturedStartup,
    memo: &crate::lowering_memo::ProcedureMemo,
) -> LoweringBatch {
    lower_frontend_impl(frontend, host, policy, config, Some(startup), Some(memo))
}
fn lower_frontend_impl<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    host: &R,
    policy: &P,
    config: LoweringConfig,
    startup: Option<&crate::startup::CapturedStartup>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
) -> LoweringBatch {
    // At most eight workers and bounded chunks, independent of machine core count.
    let workers = config.workers.clamp(1, 8);
    let chunk = config.max_chunk.clamp(1, 256);
    let mut bodies: Vec<_> = frontend.bodies.iter().collect();
    bodies.sort_by_key(|body| {
        (
            body.source.encounter_ordinal,
            body.expanded_span.start,
            body.declaration.0,
        )
    });
    // Only final outputs occupy indexed slots. Each worker holds at most one
    // bounded chunk; publication remains inside the existing memo producer.
    let slices: Vec<_> = bodies.chunks(chunk).collect();
    let results: Vec<_> = (0..slices.len())
        .map(|_| std::sync::Mutex::new(None))
        .collect();
    let next = std::sync::atomic::AtomicUsize::new(0);
    thread::scope(|scope| {
        let mut handles = Vec::new();
        for _ in 0..workers.min(slices.len()) {
            let slices = &slices;
            let results = &results;
            let next = &next;
            handles.push(scope.spawn(move || loop {
                let index = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                let Some(slice) = slices.get(index) else {
                    break;
                };
                let outcomes = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    slice
                        .iter()
                        .map(|body| lower_one_memo(frontend, body, host, policy, startup, memo))
                        .collect::<Vec<_>>()
                }))
                .unwrap_or_else(|_| {
                    slice
                        .iter()
                        .map(|body| {
                            Err(vec![LoweringDiagnostic {
                                kind: DiagnosticKind::Internal,
                                identity: None,
                                origin: body.source.clone(),
                                message: "procedure lowering worker panicked".into(),
                            }])
                        })
                        .collect()
                });
                *results[index]
                    .lock()
                    .unwrap_or_else(|error| error.into_inner()) = Some(outcomes);
            }));
        }
        for handle in handles {
            // A lowering panic is caught at the claimed chunk boundary above.
            handle.join().expect("procedure scheduling worker panicked");
        }
    });
    let mut batch = LoweringBatch::default();
    for slot in results {
        for outcome in slot
            .into_inner()
            .unwrap_or_else(|error| error.into_inner())
            .expect("every procedure chunk completed")
        {
            match outcome {
                Ok(unit) => batch.units.push(unit),
                Err(errors) => batch.diagnostics.extend(errors),
            }
        }
    }
    batch
}
fn lower_one_memo<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    host: &R,
    policy: &P,
    startup: Option<&crate::startup::CapturedStartup>,
    memo: Option<&crate::lowering_memo::ProcedureMemo>,
) -> Result<LoweredUnit, Vec<LoweringDiagnostic>> {
    let Some(memo) = memo else {
        return lower_one(frontend, body, host, policy, startup);
    };
    let key_start = std::time::Instant::now();
    if startup.is_some_and(|capture| capture.validate_for(frontend).is_err()) {
        return lower_one(frontend, body, host, policy, startup);
    }
    let Some(mut key) = crate::lowering_memo::key(frontend, body, memo.policy) else {
        return lower_one(frontend, body, host, policy, startup);
    };
    // Frozen ABI policies are prepared before this stage. Their actual folded
    // outputs must enter the key because no resolver call happens on replay.
    let tree = &frontend.snapshot.tree;
    let recording = crate::lowering_memo::RecordingResolver::new(host);
    let ready = (|| {
        let node = tree.member(body.member)?;
        let owner = tree.type_node(node.owner)?.path;
        let occurrence = tree
            .override_chain(body.member)
            .iter()
            .filter(|id| {
                tree.member(**id).is_some_and(|entry| {
                    entry.owner == node.owner && entry.kind == node.kind && entry.name == node.name
                })
            })
            .count()
            .checked_sub(1)?;
        let identity = UnitIdentity {
            owner,
            name: node.name,
            namespace: if node.kind == MemberKind::Verb {
                Namespace::Verb
            } else {
                Namespace::Proc
            },
            occurrence: u32::try_from(occurrence).ok()?,
        };
        let issued = frontend.body_input(body).ok()?;
        let context = AbiContext {
            identity,
            origin: &body.source,
            resolver: &recording,
            symbols: startup.map_or(tree.symbols(), |startup| startup.plan().symbols.as_ref()),
        };
        let metadata = node.metadata.procedure.as_ref()?;
        let (parsed, prepared) = match policy.prepare_issued(metadata, &issued, &context).ok()? {
            Some(replay) => {
                memo.counts
                    .issued_preparations
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                let prepared = replay.into_view();
                crate::lowering_memo::prepared_replay_key(&mut key, &prepared)?;
                (None, prepared)
            }
            None => {
                memo.counts
                    .parsed_preparations
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                let parsed = frontend.parse_body(body).ok()?;
                let prepared = policy.prepare_captured(metadata, &parsed, &context).ok()?;
                crate::lowering_memo::prepared_key(&mut key, &prepared, body.expanded_span.start)?;
                (Some(parsed), prepared)
            }
        };
        Some((
            parsed,
            prepared,
            dm_ir::ProcedureIdentity {
                owner: identity.owner,
                name: identity.name,
                verb: identity.namespace == Namespace::Verb,
                occurrence: identity.occurrence,
            },
        ))
    })();
    let Some((parsed, prepared, identity)) = ready else {
        return lower_one(frontend, body, host, policy, startup);
    };
    memo.counts.key_preparation_ns.fetch_add(
        key_start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
        std::sync::atomic::Ordering::Relaxed,
    );
    let lookup_start = std::time::Instant::now();
    let note = |outcome, reason, changed_query| {
        memo.counts.lookup_ns.fetch_add(
            lookup_start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
            std::sync::atomic::Ordering::Relaxed,
        );
        memo.note(crate::lowering_memo::MemoExplanation {
            identity,
            outcome,
            reason,
            changed_query,
        });
    };
    use crate::lowering_memo::{MemoMissReason, MemoOutcome};
    let (value, changed_query) = memo.values.lookup_explained(&key, host);
    let mut miss = changed_query.map_or(MemoMissReason::NoExactVariant, |_| {
        MemoMissReason::ReadMeaningChanged
    });
    if let Some(value) = value {
        // AST-bearing private sidecars still contain expanded spans. Ordinary
        // code contains only symbolic operands/debug ordinals and can move.
        let previous = &value.unit;
        let rebased = crate::lowering_memo::rebase_debug(frontend, body, &value.relative_debug);
        let absolute_sidecars =
            !previous.code.modified_instances.is_empty() || !previous.source_helpers.is_empty();
        if rebased.as_ref().is_some_and(|origins| {
            !absolute_sidecars
                || (previous.origin.expanded_span == body.expanded_span
                    && *origins == previous.debug_origins)
        }) {
            memo.counts
                .resident_hits
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let mut unit = previous.clone();
            unit.debug_origins = rebased.expect("checked relative origins");
            unit.origin = body.clone();
            if let Some(member) = frontend.snapshot.tree.member(body.member) {
                if let Some(metadata) = &member.metadata.procedure {
                    unit.metadata = Arc::clone(metadata);
                }
                unit.effective =
                    frontend
                        .snapshot
                        .tree
                        .resolve(member.owner, member.name, member.kind)
                        == Some(body.member);
            }
            note(MemoOutcome::ResidentHit, None, None);
            return Ok(unit);
        }
        miss = MemoMissReason::UnrebasablePrivateSidecar;
    }
    let disk = memo.lookup_procedure(
        &key,
        identity,
        frontend,
        body,
        host,
        &prepared,
        parsed.as_ref().map(|parsed| parsed.item()),
    );
    if let Some(errors) = disk
        .errors
        .and_then(|errors| replay_errors(frontend, body, identity, errors))
    {
        memo.counts
            .disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        note(MemoOutcome::DiskHit, None, None);
        return Err(errors);
    }
    if let Some(unit) = disk.unit {
        memo.counts
            .disk_hits
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        note(MemoOutcome::DiskHit, None, None);
        return Ok(unit);
    }
    if let Some(reason) = disk.miss {
        miss = reason;
    }
    let changed_query = changed_query.or(disk.changed_query);
    if changed_query.is_some() {
        miss = MemoMissReason::ReadMeaningChanged;
    }
    note(MemoOutcome::Recomputed, Some(miss), changed_query);
    memo.counts
        .recomputed
        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    // Replay validates the stored complete read ledger (or its trusted domain
    // receipt). Issue mandatory reads only when producing a new executable.
    let occurrence_start = std::time::Instant::now();
    recording.record_occurrence(identity);
    memo.counts.occurrence_reads_ns.fetch_add(
        occurrence_start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
        std::sync::atomic::Ordering::Relaxed,
    );
    let capture = RefCell::new(MemoCapture::default());
    let result = lower_one_captured(
        frontend,
        body,
        &recording,
        policy,
        startup,
        Some(&capture),
        parsed.map(|parsed| (parsed, prepared)),
    );
    if let Ok(unit) = &result {
        let reads = recording.reads();
        let relative_debug = capture.borrow().debug.clone();
        if relative_debug.len() == unit.debug_origins.entries.len()
            && crate::lowering_memo::rebase_debug(frontend, body, &relative_debug).as_ref()
                == Some(&unit.debug_origins)
        {
            memo.queue_disk(
                &key,
                &reads,
                unit,
                &relative_debug,
                &recording.domain_receipts(),
            );
            memo.remember(
                key,
                reads,
                unit,
                relative_debug,
                recording.domain_receipts(),
            );
        }
    } else if let Some(errors) = &capture.borrow().errors {
        memo.remember_failure(
            &key,
            Some(identity),
            &recording.reads(),
            errors,
            &recording.domain_receipts(),
        );
    }
    result
}
fn lower_one<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    host: &R,
    policy: &P,
    startup: Option<&crate::startup::CapturedStartup>,
) -> Result<LoweredUnit, Vec<LoweringDiagnostic>> {
    lower_one_captured(frontend, body, host, policy, startup, None, None)
}
fn lower_one_captured<R: Resolver, P: AbiPolicy>(
    frontend: &ColdFrontend,
    body: &BodyOccurrence,
    host: &R,
    policy: &P,
    startup: Option<&crate::startup::CapturedStartup>,
    capture: Option<&RefCell<MemoCapture>>,
    ready: Option<(dm_tree::frontend::ParsedBody<'_>, PreparedUnit)>,
) -> Result<LoweredUnit, Vec<LoweringDiagnostic>> {
    let tree = &frontend.snapshot.tree;
    let error = |identity, message| {
        vec![LoweringDiagnostic {
            kind: DiagnosticKind::Internal,
            identity,
            origin: body.source.clone(),
            message,
        }]
    };
    if let Some(captured) = startup {
        captured
            .validate_for(frontend)
            .map_err(|message| error(None, message))?;
    }
    let node = tree
        .member(body.member)
        .ok_or_else(|| error(None, "body member missing from immutable tree".into()))?;
    let owner = tree
        .type_node(node.owner)
        .ok_or_else(|| error(None, "body owner missing from immutable tree".into()))?
        .path;
    let namespace = match node.kind {
        MemberKind::Proc => Namespace::Proc,
        MemberKind::Verb => Namespace::Verb,
        MemberKind::Var => return Err(error(None, "variable cannot own a procedure body".into())),
    };
    let occurrence = tree
        .override_chain(body.member)
        .iter()
        .filter(|id| {
            tree.member(**id).is_some_and(|previous| {
                previous.owner == node.owner
                    && previous.kind == node.kind
                    && previous.name == node.name
            })
        })
        .count()
        - 1;
    let occurrence = u32::try_from(occurrence)
        .map_err(|_| error(None, "procedure occurrence exceeds u32".into()))?;
    let identity = UnitIdentity {
        owner,
        name: node.name,
        namespace,
        occurrence,
    };
    let unsupported = |message| {
        vec![LoweringDiagnostic {
            kind: DiagnosticKind::UnsupportedModel,
            identity: Some(identity),
            origin: body.source.clone(),
            message,
        }]
    };
    let metadata = node
        .metadata
        .procedure
        .as_ref()
        .ok_or_else(|| unsupported("procedure signature metadata unsupported".into()))?;
    let symbols = startup.map_or(tree.symbols(), |captured| captured.plan().symbols.as_ref());
    let (parsed, prepared) = if let Some(ready) = ready {
        ready
    } else {
        let parsed = frontend.parse_body(body).map_err(|diagnostic| {
            vec![LoweringDiagnostic {
                kind: diagnostic.kind,
                identity: Some(identity),
                origin: diagnostic.location.unwrap_or_else(|| body.source.clone()),
                message: diagnostic.message,
            }]
        })?;
        let context = AbiContext {
            identity,
            symbols,
            origin: &body.source,
            resolver: host,
        };
        let prepared = policy
            .prepare_captured(metadata, &parsed, &context)
            .map_err(unsupported)?;
        (parsed, prepared)
    };
    let parsed = parsed.item();
    let procedure_identity = dm_ir::ProcedureIdentity {
        owner: identity.owner,
        name: identity.name,
        verb: identity.namespace == Namespace::Verb,
        occurrence: identity.occurrence,
    };
    let mut inputs = prepared.inputs;
    if inputs
        .procedure_identity
        .is_some_and(|supplied| supplied != procedure_identity)
    {
        return Err(unsupported(
            "procedure ABI identity differs from current body".into(),
        ));
    }
    inputs.procedure_identity = Some(procedure_identity);
    let executable_body = if let Some(startup) = startup {
        let captured = startup
            .procedure(body.declaration)
            .ok_or_else(|| unsupported("procedure startup inventory missing".into()))?;
        if captured.procedure != procedure_identity {
            return Err(unsupported(
                "procedure startup inventory differs from current body".into(),
            ));
        }
        if captured.declarations.is_empty()
            && captured.origins.is_empty()
            && !dm_tree::procedure_statics::items_may_contain_stored_declarations(
                &prepared.executable_body,
            )
        {
            prepared.executable_body
        } else {
            let current =
                dm_tree::procedure_statics::capture(procedure_identity, &prepared.executable_body)
                    .map_err(unsupported)?;
            if captured.procedure != current.procedure
                || captured.declarations != current.declarations
                || captured.origins != current.origins
            {
                return Err(unsupported(
                    "procedure startup inventory differs from current body".into(),
                ));
            }
            current.executable_body
        }
    } else {
        if dm_tree::procedure_statics::items_may_contain_stored_declarations(
            &prepared.executable_body,
        ) {
            let static_plan =
                dm_tree::procedure_statics::capture(procedure_identity, &prepared.executable_body)
                    .map_err(unsupported)?;
            if !static_plan.declarations.is_empty() {
                return Err(unsupported(
                    "procedure statics require verified shared-slot/default/startup admission"
                        .into(),
                ));
            }
        }
        prepared.executable_body
    };
    let owner_text = symbols
        .text(owner)
        .ok_or_else(|| error(Some(identity), "owner spelling missing".into()))?;
    let name = symbols
        .text(node.name)
        .ok_or_else(|| error(Some(identity), "procedure spelling missing".into()))?;
    inputs.current_type_path = (owner_text != "/").then(|| owner_text.into());
    inputs.current_proc_path = Some(format!(
        "{}/{}/{}",
        owner_text.trim_end_matches('/'),
        if namespace == Namespace::Verb {
            "verb"
        } else {
            "proc"
        },
        name
    ));
    let debug = MemoDebugProvider {
        original: FrontendDebugProvider::new(frontend, parsed.header_span.start),
        base: body.expanded_span.start,
        entry: parsed.header_span.start,
        capture,
    };
    let code = compile_simple_proc_with_resolver_and_debug(
        &executable_body,
        &inputs,
        symbols,
        host,
        Some(&debug),
    )
    .map_err(|errors| {
        if let Some(capture) = capture {
            let relative = errors
                .iter()
                .map(|error| {
                    if error.kind == dm_codegen_byond::LowerErrorKind::Internal {
                        return None;
                    }
                    let mut error = error.clone();
                    if let Some(span) = &mut error.span {
                        span.start = span.start.checked_sub(body.expanded_span.start)?;
                        span.end = span.end.checked_sub(body.expanded_span.start)?;
                        if span.end > body.expanded_span.end - body.expanded_span.start {
                            return None;
                        }
                    }
                    Some(error)
                })
                .collect::<Option<Vec<_>>>();
            capture.borrow_mut().errors = relative;
        }
        errors
            .into_iter()
            .map(|e| LoweringDiagnostic {
                kind: match e.kind {
                    dm_codegen_byond::LowerErrorKind::SourceError => DiagnosticKind::SourceError,
                    dm_codegen_byond::LowerErrorKind::UnsupportedModel => {
                        DiagnosticKind::UnsupportedModel
                    }
                    dm_codegen_byond::LowerErrorKind::Internal => DiagnosticKind::Internal,
                },
                identity: Some(identity),
                origin: e
                    .span
                    .and_then(|span| frontend.location(span.start))
                    .unwrap_or_else(|| body.source.clone()),
                message: if e.statement.is_empty() {
                    e.reason
                } else {
                    format!("{}: {}", e.statement, e.reason)
                },
            })
            .collect::<Vec<_>>()
    })?;
    let source_helpers = match prepared.abi.as_ref() {
        Some(abi) => crate::argument_sources::lower_helpers(
            crate::argument_sources::HelperInputs {
                frontend,
                parsed: &parsed,
                metadata,
                owner: identity,
                inputs: &inputs,
                helpers: &abi.source_helpers,
                symbols,
            },
            host,
        )
        .map_err(unsupported)?,
        None => Vec::new(),
    };
    Ok(LoweredUnit {
        identity,
        effective: tree.resolve(node.owner, node.name, node.kind) == Some(body.member),
        origin: body.clone(),
        code,
        metadata: Arc::clone(metadata),
        abi: prepared.abi,
        debug_origins: debug.original.finish(),
        source_helpers,
    })
}
/// A deterministic identity index for subsequent linking; duplicate structural
/// identities are a driver/model error, never silently overwritten.
impl LoweringBatch {
    /// Symbolic-only lowering may use local policies. Full output must have
    /// authoritative metadata and actual linked argument-source artifacts.
    pub fn require_production_abi(&self) -> Result<(), String> {
        for unit in &self.units {
            let abi = unit.abi.as_ref().ok_or_else(|| {
                format!(
                    "authoritative procedure ABI missing for {:?}",
                    unit.identity
                )
            })?;
            if abi.source_helpers.len() != unit.source_helpers.len()
                || abi
                    .source_helpers
                    .iter()
                    .zip(unit.source_helpers.iter())
                    .any(|(expected, actual)| {
                        actual.owner != unit.identity
                            || usize::try_from(actual.argument).ok() != Some(expected.argument)
                    })
            {
                return Err(format!(
                    "argument-source helper lowering is incomplete for {:?}",
                    unit.identity
                ));
            }
        }
        Ok(())
    }
    pub fn identity_index(&self) -> Result<BTreeMap<UnitIdentity, usize>, UnitIdentity> {
        let mut index = BTreeMap::new();
        for (position, unit) in self.units.iter().enumerate() {
            if index.insert(unit.identity, position).is_some() {
                return Err(unit.identity);
            }
        }
        Ok(index)
    }
}

#[cfg(test)]
#[path = "lowering_tests.rs"]
mod tests;
