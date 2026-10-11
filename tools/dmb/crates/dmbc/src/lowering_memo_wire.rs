//! Versioned disk payload for supported symbolic procedure results.
//! Descriptors are reissued by the private factory; helpers reuse current ABI preparation.
use crate::lowering::{LoweredUnit, Namespace, UnitIdentity};
use crate::lowering_memo::ResolverRead;
use dm_codegen_byond::lower_resolver::{ResolvedInstance, ResolvedSlot, ResolverProc};
use dm_codegen_byond::procedure_abi::{ArgumentSource, Category, ProcLayout};
use dm_ir::{ProcedureIdentity, ProcedureStaticIdentity, ResolveQuery, Resolver, SymRef, SymbolId};
use serde::{Deserialize, Serialize};
use std::{borrow::Cow, collections::BTreeMap, sync::Arc};
const EXECUTABLE_SCHEMA: u32 = 0x0206_001e;
// Common nameof member diagnostics now retain the authored receiver/operator.
// Prior failure frames can contain selector-only wording under the same key.
// Relative dot-formals additionally admit exact global-only formal proofs.
// Old method-only negative frames must not bypass that current lookup.
// Ordinary return-nameof failures also retain their typed recovery sequence;
// old primary-only failures must not replay under an unchanged procedure key.
const FAILURE_SCHEMA: u32 = 0x0206_0023;
#[path = "lowering_memo_failure_wire.rs"]
mod failure_wire;
#[path = "lowering_memo_read_wire.rs"]
pub(crate) mod read_wire;
use read_wire::{CanonicalRead, ReadWire};
#[path = "lowering_memo_private.rs"]
mod private;
#[path = "lowering_memo_selected_wire.rs"]
mod selected_wire;
#[path = "lowering_memo_simple_proc_wire.rs"]
mod simple_proc_wire;
use failure_wire::{ErrorWire, FailurePayload};
#[derive(Serialize, Deserialize)]
enum ArgumentWire {
    Builtin((u8, u8)),
    Helper { argument: usize },
}

#[derive(Serialize, Deserialize)]
struct Abi {
    display: Option<Vec<u8>>,
    description: Option<Vec<u8>>,
    category: u8,
    category_text: Vec<u8>,
    source_kind: u8,
    source_parameter: u8,
    flags: u32,
    invisibility: Option<u8>,
    arguments: Vec<ArgumentWire>,
}

#[derive(Serialize, Deserialize)]
struct Payload {
    version: u32,
    key: Vec<u8>,
    identity: Option<ProcedureIdentity>,
    effective: bool,
    reads: Vec<(ResolveQuery, Vec<u8>)>,
    versions: Vec<(dm_ir::ReadDomain, u128)>,
    body: CodeWire,
    debug: Vec<(String, u32)>,
    relative_debug: Vec<crate::debug_sources::RelativeDebugAnchor>,
    abi: Option<Abi>,
    helpers: Vec<HelperWire>,
    selected_references: Option<selected_wire::SelectedWire>,
}
#[derive(Serialize, Deserialize)]
struct HelperWire {
    argument: u32,
    body: CodeWire,
}
#[derive(Serialize, Deserialize)]
pub(crate) struct CodeWire {
    #[serde(with = "simple_proc_wire")]
    code: dm_codegen_byond::SimpleProc,
    slots: Vec<(SymRef, SymbolId, SymbolId, SymbolId)>,
    resources: BTreeMap<SymbolId, u128>,
    instances: Vec<(SymbolId, SymbolId, SymbolId)>,
    procedure_values: BTreeMap<SymRef, ProcedureIdentity>,
    procedure_statics: BTreeMap<SymRef, ProcedureStaticIdentity>,
    modified: Vec<(SymRef, private::DescriptorWire)>,
}
impl CodeWire {
    pub(crate) fn capture(code: &ResolverProc) -> Self {
        Self {
            code: code.procedure.clone(),
            slots: code
                .slots
                .iter()
                .map(|(key, slot)| (*key, slot.symbol, slot.owner, slot.name))
                .collect(),
            resources: code.resources.clone(),
            instances: code
                .instances
                .iter()
                .map(|(key, value)| (*key, value.alias, value.runtime_type))
                .collect(),
            procedure_values: code.procedure_values.clone(),
            procedure_statics: code.procedure_statics.clone(),
            modified: code
                .modified_instances
                .iter()
                .map(|(key, value)| (*key, private::DescriptorWire::capture(value)))
                .collect(),
        }
    }
    pub(crate) fn source_neutral_initializer(&self) -> bool {
        let mut resource_reference = false;
        // Includes nested variable/value/switch operands, not only side tables.
        self.code.code.for_each_reference(|reference| {
            resource_reference |= matches!(reference, SymRef::Resource(_));
        });
        !resource_reference
            && self.modified.is_empty()
            && self.code.warnings.is_empty()
            && self.resources.is_empty()
            && self.code.resources.is_empty()
    }
    pub(crate) fn rehydrate<R: Resolver>(
        self,
        host: &R,
        debug_count: usize,
    ) -> Option<ResolverProc> {
        if self.code.warnings.iter().any(|warning| {
            !crate::procedure_warnings::valid_receipt(warning, debug_count, |id| {
                self.code
                    .local_names
                    .iter()
                    .any(|name| !name.is_empty() && SymbolId::of(name) == id)
            })
        }) {
            return None;
        }

        let mut slots = BTreeMap::new();
        for (key, symbol, owner, name) in self.slots {
            if key != SymRef::VariableSlot(symbol) {
                return None;
            }
            if slots
                .insert(
                    key,
                    ResolvedSlot {
                        symbol,
                        owner,
                        name,
                    },
                )
                .is_some()
            {
                return None;
            }
        }
        let mut instances = BTreeMap::new();
        for (key, alias, runtime_type) in self.instances {
            if key != alias {
                return None;
            }
            if instances
                .insert(
                    key,
                    ResolvedInstance {
                        alias,
                        runtime_type,
                    },
                )
                .is_some()
            {
                return None;
            }
        }
        let mut modified_instances = BTreeMap::new();
        for (key, wire) in self.modified {
            let captured = wire.rehydrate(host, debug_count)?;
            if key != SymRef::Instance(SymbolId::of(&captured.descriptor.alias()))
                || modified_instances.insert(key, captured).is_some()
            {
                return None;
            }
        }
        if self.procedure_values.iter().any(|(key, value)| {
            *key != if value.verb {
                SymRef::Verb {
                    owner: value.owner,
                    name: value.name,
                    occurrence: value.occurrence,
                }
            } else {
                SymRef::Proc {
                    owner: value.owner,
                    name: value.name,
                    occurrence: value.occurrence,
                }
            }
        }) || self
            .procedure_statics
            .iter()
            .any(|(key, value)| *key != SymRef::ProcedureStatic(*value))
        {
            return None;
        }
        Some(ResolverProc {
            procedure: self.code,
            slots,
            resources: self.resources,
            instances,
            procedure_values: self.procedure_values,
            procedure_statics: self.procedure_statics,
            modified_instances,
        })
    }
}
pub(crate) fn encode(
    key: &[u8],
    reads: &[ResolverRead],
    versions: &[(dm_ir::ReadDomain, u128)],
    unit: &LoweredUnit,
    relative_debug: &[crate::debug_sources::RelativeDebugAnchor],
) -> Option<Vec<u8>> {
    let abi = match unit.abi.as_ref() {
        None => None,
        Some(abi) => {
            let arguments = abi
                .argument_sources
                .iter()
                .map(|source| match source {
                    ArgumentSource::Builtin { kind, parameter } => {
                        ArgumentWire::Builtin((*kind, *parameter))
                    }
                    ArgumentSource::Helper { argument } => ArgumentWire::Helper {
                        argument: *argument,
                    },
                })
                .collect::<Vec<_>>();
            let (category, category_text) = match &abi.layout.category {
                Category::Default => (0, Vec::new()),
                Category::Null => (1, Vec::new()),
                Category::Text(bytes) => (2, bytes.clone()),
            };
            Some(Abi {
                display: abi.layout.display_name.clone(),
                description: abi.layout.description.clone(),
                category,
                category_text,
                source_kind: abi.layout.source_kind,
                source_parameter: abi.layout.source_parameter,
                flags: abi.layout.flags,
                invisibility: abi.layout.invisibility,
                arguments,
            })
        }
    };
    let payload = Payload {
        version: 4,
        key: key.to_vec(),
        identity: Some(ProcedureIdentity {
            owner: unit.identity.owner,
            name: unit.identity.name,
            verb: unit.identity.namespace == Namespace::Verb,
            occurrence: unit.identity.occurrence,
        }),
        effective: unit.effective,
        selected_references: match unit.selected_references.as_deref() {
            Some(facts) => Some(selected_wire::SelectedWire::capture(facts)?),
            None => None,
        },
        versions: versions
            .iter()
            .copied()
            .filter(|(domain, _)| domain.persistent_version())
            .collect(),
        reads: reads
            .iter()
            .map(|read| (read.query, read.answer.canonical_bytes()))
            .collect(),
        body: CodeWire::capture(&unit.code),
        debug: unit
            .debug_origins
            .entries
            .iter()
            .map(|origin| (origin.semantic_path.to_string(), origin.line))
            .collect(),
        abi,
        relative_debug: relative_debug.to_vec(),
        helpers: unit
            .source_helpers
            .iter()
            .map(|helper| HelperWire {
                argument: helper.argument,
                body: CodeWire::capture(&helper.code),
            })
            .collect(),
    };
    dm_wire::encode(EXECUTABLE_SCHEMA, &payload).ok()
}
fn payload(bytes: &[u8]) -> Result<Payload, String> {
    let payload: Payload = dm_wire::decode(EXECUTABLE_SCHEMA, bytes, bytes.len())?;
    validate_versions(&payload.versions)?;
    if payload.version != 4
        || payload.abi.as_ref().is_some_and(|abi| abi.category > 2)
        || payload
            .selected_references
            .as_ref()
            .is_some_and(|facts| !facts.valid())
    {
        return Err("unsupported lowering schema/ABI".into());
    }
    Ok(payload)
}
pub(crate) fn validate_versions(versions: &[(dm_ir::ReadDomain, u128)]) -> Result<(), String> {
    if versions
        .iter()
        .any(|(domain, _)| !domain.persistent_version())
        || versions.len() > 2
        || versions
            .iter()
            .map(|(domain, _)| *domain)
            .collect::<std::collections::BTreeSet<_>>()
            .len()
            != versions.len()
    {
        return Err("invalid domain receipt roster".into());
    }
    Ok(())
}
fn read_mismatch<R: Resolver, T: CanonicalRead>(
    reads: &[T],
    versions: &[(dm_ir::ReadDomain, u128)],
    host: &R,
) -> Option<ResolveQuery> {
    let matching = crate::lowering_memo::matching_domains(versions, host);
    reads.iter().find_map(|read| {
        let query = read.query();
        (!matching.contains(&query.domain())
            && host.resolve(query).canonical_bytes().as_slice() != read.answer())
        .then_some(query)
    })
}
pub(crate) fn validate(bytes: &[u8]) -> Result<(), String> {
    if bytes.get(8..12)
        == Some(
            crate::lowering_memo_selection::SCHEMA
                .to_le_bytes()
                .as_slice(),
        )
    {
        crate::lowering_memo_selection::decode(bytes)?;
        return Ok(());
    }
    if bytes.get(8..12)
        == Some(
            crate::lowering_memo_compact::SCHEMA
                .to_le_bytes()
                .as_slice(),
        )
    {
        return crate::lowering_memo_compact::decode(bytes).map(|_| ());
    }
    if let Ok(value) =
        dm_wire::decode_borrowed::<FailurePayload>(FAILURE_SCHEMA, bytes, bytes.len())
    {
        validate_versions(&value.versions)?;
        if value.errors.is_empty()
            || value.errors.iter().any(|error| {
                error.kind == dm_codegen_byond::LowerErrorKind::Internal
                    || matches!(
                        error.primary_anchor,
                        Some(dm_codegen_byond::DiagnosticAnchor::LexerCursorAfterOffset(
                            0
                        ))
                    )
                    || error
                        .related
                        .iter()
                        .any(|note| note.span.start > note.span.end)
            })
        {
            return Err("uncacheable failure payload".into());
        }
        return Ok(());
    }
    payload(bytes).map(|_| ())
}
pub(crate) fn encode_failure(
    key: &[u8],
    identity: Option<ProcedureIdentity>,
    reads: &[ResolverRead],
    versions: &[(dm_ir::ReadDomain, u128)],
    errors: &[dm_codegen_byond::LowerError],
) -> Option<Vec<u8>> {
    if errors.is_empty()
        || errors.iter().any(|error| {
            error.kind == dm_codegen_byond::LowerErrorKind::Internal
                || matches!(
                    error.primary_anchor,
                    Some(dm_codegen_byond::DiagnosticAnchor::LexerCursorAfterOffset(
                        0
                    ))
                )
                || error
                    .related
                    .iter()
                    .any(|note| note.span.start > note.span.end)
        })
    {
        return None;
    }
    let payload = FailurePayload {
        key: Cow::Borrowed(key),
        identity,
        versions: versions
            .iter()
            .copied()
            .filter(|(domain, _)| domain.persistent_version())
            .collect(),
        reads: reads
            .iter()
            .map(|read| ReadWire {
                query: read.query,
                answer: Cow::Owned(read.answer.canonical_bytes()),
            })
            .collect(),
        errors: errors.iter().map(ErrorWire::capture).collect(),
    };
    dm_wire::encode(FAILURE_SCHEMA, &payload).ok()
}
#[cfg(test)]
pub(crate) fn decode_failure<R: Resolver>(
    bytes: &[u8],
    key: &[u8],
    identity: Option<ProcedureIdentity>,
    host: &R,
) -> Option<Vec<dm_codegen_byond::LowerError>> {
    let payload: FailurePayload =
        dm_wire::decode_borrowed(FAILURE_SCHEMA, bytes, bytes.len()).ok()?;
    if validate_versions(&payload.versions).is_err()
        || payload.errors.is_empty()
        || payload.errors.iter().any(|error| {
            error.kind == dm_codegen_byond::LowerErrorKind::Internal
                || matches!(
                    error.primary_anchor,
                    Some(dm_codegen_byond::DiagnosticAnchor::LexerCursorAfterOffset(
                        0
                    ))
                )
                || error
                    .related
                    .iter()
                    .any(|note| note.span.start > note.span.end)
        })
    {
        return None;
    }

    (payload.key.as_ref() == key
        && payload.identity == identity
        && read_mismatch(&payload.reads, &payload.versions, host).is_none())
    .then(|| {
        payload
            .errors
            .into_iter()
            .map(ErrorWire::rehydrate)
            .collect()
    })
}
#[cfg(test)]
pub(crate) fn encode_executable(
    key: &[u8],
    reads: &[ResolverRead],
    versions: &[(dm_ir::ReadDomain, u128)],
    code: &ResolverProc,
) -> Option<Vec<u8>> {
    let payload = Payload {
        version: 4,
        key: key.to_vec(),
        identity: None,
        effective: false,
        abi: None,
        debug: Vec::new(),
        relative_debug: Vec::new(),
        helpers: Vec::new(),
        selected_references: None,
        versions: versions
            .iter()
            .copied()
            .filter(|(domain, _)| domain.persistent_version())
            .collect(),
        reads: reads
            .iter()
            .map(|read| (read.query, read.answer.canonical_bytes()))
            .collect(),
        body: CodeWire::capture(code),
    };
    dm_wire::encode(EXECUTABLE_SCHEMA, &payload).ok()
}
#[cfg(test)]
pub(crate) fn decode_executable<R: Resolver>(
    bytes: &[u8],
    key: &[u8],
    host: &R,
    debug_count: usize,
) -> Option<ResolverProc> {
    let payload = payload(bytes).ok()?;
    if payload.identity.is_some()
        || payload.abi.is_some()
        || !payload.helpers.is_empty()
        || payload.selected_references.is_some()
        || payload.key != key
        || read_mismatch(&payload.reads, &payload.versions, host).is_some()
    {
        return None;
    }
    payload.body.rehydrate(host, debug_count)
}
fn rebind<R: Resolver>(
    payload: Payload,
    frontend: &dm_tree::frontend::ColdFrontend,
    body: &dm_tree::frontend::BodyOccurrence,
    host: &R,
    prepared: &crate::procedure_policy::PreparedUnit,
    parsed: Option<crate::argument_sources::ProcedureHeader<'_>>,
) -> Result<LoweredUnit, crate::lowering_memo::ReplayDecline> {
    use crate::lowering_memo::ReplayDecline as Decline;
    let identity = payload.identity.ok_or(Decline::BodyIdentity)?;
    let tree = &frontend.snapshot.tree;
    let member = tree.member(body.member).ok_or(Decline::BodyIdentity)?;
    let owner = tree
        .type_node(member.owner)
        .ok_or(Decline::BodyIdentity)?
        .path;
    let occurrence = tree
        .override_chain(body.member)
        .iter()
        .filter(|id| {
            tree.member(**id).is_some_and(|entry| {
                entry.owner == member.owner
                    && entry.name == member.name
                    && entry.kind == member.kind
            })
        })
        .count()
        .checked_sub(1)
        .ok_or(Decline::BodyIdentity)?;
    if usize::try_from(identity.occurrence).map_err(|_| Decline::BodyIdentity)? != occurrence {
        return Err(Decline::BodyIdentity);
    }
    if identity.owner != owner
        || identity.name != member.name
        || identity.verb != (member.kind == dm_tree::MemberKind::Verb)
    {
        return Err(Decline::BodyIdentity);
    }
    let metadata = Arc::clone(
        member
            .metadata
            .procedure
            .as_ref()
            .ok_or(Decline::BodyIdentity)?,
    );
    let abi = match (payload.abi, prepared.abi.as_ref()) {
        (None, None) => None,
        (Some(abi), Some(current)) => {
            let layout = ProcLayout {
                display_name: abi.display,
                description: abi.description,
                category: match abi.category {
                    0 => Category::Default,
                    1 => Category::Null,
                    2 => Category::Text(abi.category_text),
                    _ => return Err(Decline::PreparedAbi),
                },
                source_kind: abi.source_kind,
                source_parameter: abi.source_parameter,
                flags: abi.flags,
                invisibility: abi.invisibility,
            };
            let sources = abi
                .arguments
                .into_iter()
                .map(|value| match value {
                    ArgumentWire::Builtin((kind, parameter)) => {
                        ArgumentSource::Builtin { kind, parameter }
                    }
                    ArgumentWire::Helper { argument } => ArgumentSource::Helper { argument },
                })
                .collect::<Vec<_>>();
            if layout != current.layout || sources != current.argument_sources {
                return Err(Decline::PreparedAbi);
            }
            Some(Arc::clone(current))
        }
        _ => return Err(Decline::PreparedAbi),
    };
    if payload.relative_debug.len() != payload.debug.len() {
        return Err(Decline::DebugOrigins);
    }
    let debug_origins = crate::lowering_memo::rebase_debug(frontend, body, &payload.relative_debug)
        .ok_or(Decline::DebugOrigins)?;
    let code = payload
        .body
        .rehydrate(host, debug_origins.entries.len())
        .ok_or(Decline::ExecutableIssuer)?;
    let unit_identity = UnitIdentity {
        owner: identity.owner,
        name: identity.name,
        namespace: if identity.verb {
            Namespace::Verb
        } else {
            Namespace::Proc
        },
        occurrence: identity.occurrence,
    };
    if prepared
        .inputs
        .procedure_identity
        .is_some_and(|current| current != identity)
    {
        return Err(Decline::PreparedIdentity);
    }
    let expected_helpers = abi
        .as_ref()
        .map_or(&[][..], |value| value.source_helpers.as_slice());
    if payload.helpers.len() != expected_helpers.len() {
        return Err(Decline::HelperInventory);
    }
    let mut source_helpers = Vec::with_capacity(payload.helpers.len());
    for (wire, expected) in payload.helpers.into_iter().zip(expected_helpers) {
        if wire.argument as usize != expected.argument {
            return Err(Decline::HelperInventory);
        }
        let helper_code = wire.body.rehydrate(host, 1).ok_or(Decline::HelperIssuer)?;
        source_helpers.push(
            crate::argument_sources::rebase_cached_helper(
                crate::argument_sources::HelperInputs {
                    frontend,
                    parsed: parsed.ok_or(Decline::HelperIssuer)?,
                    metadata: &metadata,
                    owner: unit_identity,
                    inputs: &prepared.inputs,
                    helpers: expected_helpers,
                    symbols: frontend.snapshot.tree.symbols(),
                },
                wire.argument,
                helper_code,
            )
            .map_err(|_| Decline::HelperIssuer)?,
        );
    }
    Ok(LoweredUnit {
        identity: unit_identity,
        effective: tree.resolve(member.owner, member.name, member.kind) == Some(body.member),
        origin: body.clone(),
        metadata,
        abi,
        code,
        selected_references: payload
            .selected_references
            .map(|facts| {
                facts
                    .rehydrate()
                    .map(Arc::new)
                    .ok_or(Decline::ExecutableIssuer)
            })
            .transpose()?,
        debug_origins,
        source_helpers,
    })
}

/// All variants have been typed and checked before any current resolver reads.
pub(crate) struct Candidates<'a>(Vec<Candidate<'a>>);
enum Candidate<'a> {
    Executable(Box<Payload>),
    Compact(Box<crate::lowering_memo_compact::Payload<'a>>),
    Selections(Box<crate::lowering_memo_selection::Payload<'a>>),
    Failure(FailurePayload<'a>),
}
/// Current source occurrence used when rebasing a persisted procedure result.
pub(crate) struct ProcedureReplayContext<'a> {
    pub frontend: &'a dm_tree::frontend::ColdFrontend,
    pub body: &'a dm_tree::frontend::BodyOccurrence,
    pub parsed: Option<crate::argument_sources::ProcedureHeader<'a>>,
    pub bindings: Option<crate::lowering::DiskReplayBindings<'a>>,
    pub selections_only: bool,
    pub verify: bool,
    pub modified: Option<&'a dyn crate::lowering_memo_compact::ModifiedIssuer>,
}
#[derive(Default)]
pub(crate) struct ResidentPromotion {
    pub queries: Vec<ResolveQuery>,
    pub versions: Vec<(dm_ir::ReadDomain, u128)>,
    pub relative_debug: Vec<crate::debug_sources::RelativeDebugAnchor>,
}
#[derive(Default)]
pub(crate) struct ProcedureLookup {
    pub verification_reads: Option<Vec<(ResolveQuery, Vec<u8>)>>,
    pub unit: Option<LoweredUnit>,
    pub selections: Option<Arc<dm_ir::SelectedReferences>>,
    pub prepared: Option<crate::symbolic::PreparedContribution>,
    pub resident: Option<ResidentPromotion>,
    pub errors: Option<Vec<dm_codegen_byond::LowerError>>,
    pub changed_query: Option<ResolveQuery>,
    pub miss: Option<crate::lowering_memo::MemoMissReason>,
}
pub(crate) fn candidates(bytes: &[u8]) -> Result<Candidates<'_>, String> {
    let mut values = Vec::new();
    for bytes in dm_cache::decode_variants(bytes)? {
        if let Ok(value) =
            dm_wire::decode_borrowed::<FailurePayload>(FAILURE_SCHEMA, bytes, bytes.len())
        {
            validate_versions(&value.versions)?;
            if value.errors.is_empty()
                || value.errors.iter().any(|error| {
                    error.kind == dm_codegen_byond::LowerErrorKind::Internal
                        || matches!(
                            error.primary_anchor,
                            Some(dm_codegen_byond::DiagnosticAnchor::LexerCursorAfterOffset(
                                0
                            ))
                        )
                        || error
                            .related
                            .iter()
                            .any(|note| note.span.start > note.span.end)
                })
            {
                return Err("uncacheable failure candidate".into());
            }
            values.push(Candidate::Failure(value));
        } else if bytes.get(8..12)
            == Some(
                crate::lowering_memo_selection::SCHEMA
                    .to_le_bytes()
                    .as_slice(),
            )
        {
            values.push(Candidate::Selections(Box::new(
                crate::lowering_memo_selection::decode(bytes)?,
            )));
        } else if bytes.get(8..12)
            == Some(
                crate::lowering_memo_compact::SCHEMA
                    .to_le_bytes()
                    .as_slice(),
            )
        {
            values.push(Candidate::Compact(Box::new(
                crate::lowering_memo_compact::decode(bytes)?,
            )));
        } else {
            values.push(Candidate::Executable(Box::new(payload(bytes)?)));
        }
    }
    Ok(Candidates(values))
}
#[cfg(test)]
#[path = "lowering_memo_wire_anonymous.rs"]
mod anonymous;
#[cfg(test)]
pub(crate) use anonymous::AnonymousLookup;
impl Candidates<'_> {
    #[cfg(test)]
    pub(crate) fn procedure<R: Resolver>(
        self,
        key: &[u8],
        identity: ProcedureIdentity,
        context: ProcedureReplayContext<'_>,
        host: &R,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> ProcedureLookup {
        self.procedure_matching(
            &|candidate| candidate == key,
            identity,
            context,
            host,
            prepared,
        )
    }
    #[cfg(test)]
    pub(crate) fn procedure_matching<R: Resolver>(
        self,
        matches_key: &dyn Fn(&[u8]) -> bool,
        identity: ProcedureIdentity,
        context: ProcedureReplayContext<'_>,
        host: &R,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> ProcedureLookup {
        self.procedure_matching_backed(matches_key, identity, context, host, prepared, None)
    }
    pub(crate) fn procedure_matching_backed<R: Resolver>(
        self,
        matches_key: &dyn Fn(&[u8]) -> bool,
        identity: ProcedureIdentity,
        context: ProcedureReplayContext<'_>,
        host: &R,
        prepared: &crate::procedure_policy::PreparedUnit,
        backing: Option<&dm_cache::MappedPayload>,
    ) -> ProcedureLookup {
        let mut result = ProcedureLookup {
            miss: Some(crate::lowering_memo::MemoMissReason::FullKeyMismatch),
            ..Default::default()
        };
        for value in self.0.into_iter().rev() {
            if let Candidate::Selections(v) = value {
                if !context.selections_only || !v.matches_with(matches_key, identity) {
                    continue;
                }
                if let Some(query) = v.changed_read(host) {
                    result.changed_query.get_or_insert(query);
                    continue;
                }
                let promotion = v.promotion();
                let rebound = v.bind(
                    ProcedureReplayContext {
                        frontend: context.frontend,
                        body: context.body,
                        parsed: context.parsed,
                        bindings: context.bindings,
                        selections_only: true,
                        verify: context.verify,
                        modified: context.modified,
                    },
                    prepared,
                );
                if let Some(facts) = rebound {
                    return ProcedureLookup {
                        selections: Some(facts),
                        resident: Some(promotion),
                        ..Default::default()
                    };
                }
                continue;
            }
            if let Candidate::Compact(v) = value {
                if !matches_key(v.key.as_ref()) || v.identity != identity {
                    continue;
                }
                if let Some(query) = v.changed_read(host) {
                    result.changed_query.get_or_insert(query);
                    continue;
                }
                let promotion = v.promotion();
                let verification_reads = context.verify.then(|| v.verification_reads());
                match v.rebind_with_backing(
                    ProcedureReplayContext {
                        frontend: context.frontend,
                        body: context.body,
                        parsed: context.parsed,
                        bindings: context.bindings,
                        selections_only: context.selections_only,
                        verify: context.verify,
                        modified: context.modified,
                    },
                    prepared,
                    backing,
                ) {
                    Ok(value) => {
                        result.verification_reads = verification_reads;
                        result.prepared = Some(value);
                        result.resident = Some(promotion);
                        return result;
                    }
                    Err(reason) => {
                        result.miss = Some(
                            crate::lowering_memo::MemoMissReason::PrivateReplayDeclined(reason),
                        );
                    }
                }
                continue;
            }
            let (candidate, owner) = match &value {
                Candidate::Executable(v) => (v.key.as_ref(), v.identity),
                Candidate::Failure(v) => (v.key.as_ref(), v.identity),
                Candidate::Compact(_) | Candidate::Selections(_) => unreachable!(),
            };
            if !matches_key(candidate) || owner != Some(identity) {
                continue;
            }
            result.miss = Some(crate::lowering_memo::MemoMissReason::NoExactVariant);
            let changed = match &value {
                Candidate::Executable(v) => read_mismatch(&v.reads, &v.versions, host),
                Candidate::Failure(v) => read_mismatch(&v.reads, &v.versions, host),
                Candidate::Compact(_) | Candidate::Selections(_) => unreachable!(),
            };
            if let Some(query) = changed {
                result.changed_query.get_or_insert(query);
                continue;
            }
            match value {
                Candidate::Compact(_) | Candidate::Selections(_) => unreachable!(),
                Candidate::Failure(v) => {
                    result.verification_reads = context.verify.then(|| {
                        v.reads
                            .iter()
                            .map(|r| (r.query, r.answer.to_vec()))
                            .collect()
                    });
                    result.errors = Some(v.errors.into_iter().map(ErrorWire::rehydrate).collect());
                    return result;
                }
                Candidate::Executable(v) => {
                    let verification_reads = context.verify.then(|| v.reads.clone());
                    let promotion = ResidentPromotion {
                        queries: v.reads.iter().map(|(query, _)| *query).collect(),
                        versions: v.versions.clone(),
                        relative_debug: v.relative_debug.clone(),
                    };
                    match rebind(
                        *v,
                        context.frontend,
                        context.body,
                        host,
                        prepared,
                        context.parsed,
                    ) {
                        Ok(unit) => {
                            result.verification_reads = verification_reads;
                            result.unit = Some(unit);
                            result.resident = Some(promotion);
                            return result;
                        }
                        Err(reason) => {
                            result.miss = Some(
                                crate::lowering_memo::MemoMissReason::PrivateReplayDeclined(reason),
                            );
                        }
                    }
                }
            }
        }
        result
    }
}

#[cfg(test)]
#[path = "lowering_memo_wire_executable_tests.rs"]
mod executable_tests;

#[cfg(test)]
#[path = "lowering_memo_wire_typed_tests.rs"]
mod typed_identity_tests;

#[cfg(test)]
#[path = "lowering_memo_borrowed_wire_tests.rs"]
mod borrowed_wire_tests;

#[cfg(test)]
#[path = "lowering_memo_owner_domain_tests.rs"]
mod owner_domain_tests;

#[cfg(test)]
#[path = "lowering_memo_warning_wire_tests.rs"]
mod warning_wire_tests;

pub(crate) fn verification_code_equal(a: &ResolverProc, b: &ResolverProc) -> bool {
    match (
        dm_wire::encode(EXECUTABLE_SCHEMA, &CodeWire::capture(a)),
        dm_wire::encode(EXECUTABLE_SCHEMA, &CodeWire::capture(b)),
    ) {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    }
}

/// Verification-only canonical executable comparison; not an admission authority.
pub(crate) fn verification_unit_equal(a: &LoweredUnit, b: &LoweredUnit) -> bool {
    a.identity == b.identity
        && a.effective == b.effective
        && a.metadata.canonical_bytes() == b.metadata.canonical_bytes()
        && a.abi.as_ref().map(|v| v.canonical_bytes())
            == b.abi.as_ref().map(|v| v.canonical_bytes())
        && a.selected_references == b.selected_references
        && a.debug_origins == b.debug_origins
        && verification_code_equal(&a.code, &b.code)
        && a.source_helpers.len() == b.source_helpers.len()
        && a.source_helpers
            .iter()
            .zip(&b.source_helpers)
            .all(|(a, b)| {
                a.owner == b.owner
                    && a.argument == b.argument
                    && a.debug_origins == b.debug_origins
                    && verification_code_equal(&a.code, &b.code)
            })
}

#[path = "lowering_memo_wire_initializer.rs"]
pub(crate) mod initializer;
