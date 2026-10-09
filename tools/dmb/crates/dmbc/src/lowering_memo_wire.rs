//! Versioned disk payload for supported symbolic procedure results.
//! Descriptors are reissued by the private factory; helpers reuse current ABI preparation.
use crate::lowering::{LoweredUnit, Namespace, UnitIdentity};
use crate::lowering_memo::ResolverRead;
use dm_codegen_byond::lower_resolver::{ResolvedInstance, ResolvedSlot, ResolverProc};
use dm_codegen_byond::procedure_abi::{ArgumentSource, Category, ProcLayout};
use dm_ir::{ProcedureIdentity, ProcedureStaticIdentity, ResolveQuery, Resolver, SymRef, SymbolId};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, sync::Arc};
const EXECUTABLE_SCHEMA: u32 = 0x0206_0001;
const FAILURE_SCHEMA: u32 = 0x0206_0002;
#[path = "lowering_memo_private.rs"]
mod private;
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
    relative_debug: Vec<usize>,
    abi: Option<Abi>,
    helpers: Vec<HelperWire>,
}
#[derive(Serialize, Deserialize)]
struct HelperWire {
    argument: u32,
    body: CodeWire,
}
#[derive(Serialize, Deserialize)]
struct CodeWire {
    code: dm_codegen_byond::SimpleProc,
    slots: Vec<(SymRef, SymbolId, SymbolId, SymbolId)>,
    resources: BTreeMap<SymbolId, u128>,
    instances: Vec<(SymbolId, SymbolId, SymbolId)>,
    procedure_values: BTreeMap<SymRef, ProcedureIdentity>,
    procedure_statics: BTreeMap<SymRef, ProcedureStaticIdentity>,
    modified: Vec<(SymRef, private::DescriptorWire)>,
}
impl CodeWire {
    fn capture(code: &ResolverProc) -> Self {
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
    fn rehydrate<R: Resolver>(self, host: &R, debug_count: usize) -> Option<ResolverProc> {
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
    relative_debug: &[usize],
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
        version: 1,
        key: key.to_vec(),
        identity: Some(ProcedureIdentity {
            owner: unit.identity.owner,
            name: unit.identity.name,
            verb: unit.identity.namespace == Namespace::Verb,
            occurrence: unit.identity.occurrence,
        }),
        effective: unit.effective,
        versions: versions.to_vec(),
        reads: reads
            .iter()
            .map(|read| (read.query, read.answer.canonical_bytes()))
            .collect(),
        body: CodeWire::capture(&unit.code),
        debug: unit
            .debug_origins
            .entries
            .iter()
            .map(|origin| (origin.semantic_path.clone(), origin.line))
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
    if payload.version != 1 || payload.abi.as_ref().is_some_and(|abi| abi.category > 2) {
        return Err("unsupported lowering schema/ABI".into());
    }
    Ok(payload)
}
fn validate_versions(versions: &[(dm_ir::ReadDomain, u128)]) -> Result<(), String> {
    if versions.len() > 2
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
fn read_mismatch<R: Resolver>(
    reads: &[(ResolveQuery, Vec<u8>)],
    versions: &[(dm_ir::ReadDomain, u128)],
    host: &R,
) -> Option<ResolveQuery> {
    let matching = crate::lowering_memo::matching_domains(versions, host);
    reads.iter().find_map(|(query, answer)| {
        (!matching.contains(&query.domain()) && host.resolve(*query).canonical_bytes() != *answer)
            .then_some(*query)
    })
}
pub(crate) fn validate(bytes: &[u8]) -> Result<(), String> {
    if let Ok(value) = dm_wire::decode::<FailurePayload>(FAILURE_SCHEMA, bytes, bytes.len()) {
        validate_versions(&value.versions)?;
        if value.errors.is_empty()
            || value
                .errors
                .iter()
                .any(|error| error.kind == dm_codegen_byond::LowerErrorKind::Internal)
        {
            return Err("uncacheable failure payload".into());
        }
        return Ok(());
    }
    payload(bytes).map(|_| ())
}
#[derive(Serialize, Deserialize)]
struct ErrorWire {
    statement: String,
    reason: String,
    span: Option<dm_codegen_byond::LowerSpan>,
    kind: dm_codegen_byond::LowerErrorKind,
}
impl ErrorWire {
    fn capture(error: &dm_codegen_byond::LowerError) -> Self {
        Self {
            statement: error.statement.clone(),
            reason: error.reason.clone(),
            span: error.span,
            kind: error.kind,
        }
    }
    fn rehydrate(self) -> dm_codegen_byond::LowerError {
        dm_codegen_byond::LowerError {
            statement: self.statement,
            reason: self.reason,
            span: self.span,
            kind: self.kind,
        }
    }
}
#[derive(Serialize, Deserialize)]
struct FailurePayload {
    key: Vec<u8>,
    identity: Option<ProcedureIdentity>,
    reads: Vec<(ResolveQuery, Vec<u8>)>,
    versions: Vec<(dm_ir::ReadDomain, u128)>,
    errors: Vec<ErrorWire>,
}
pub(crate) fn encode_failure(
    key: &[u8],
    identity: Option<ProcedureIdentity>,
    reads: &[ResolverRead],
    versions: &[(dm_ir::ReadDomain, u128)],
    errors: &[dm_codegen_byond::LowerError],
) -> Option<Vec<u8>> {
    if errors.is_empty()
        || errors
            .iter()
            .any(|error| error.kind == dm_codegen_byond::LowerErrorKind::Internal)
    {
        return None;
    }
    let payload = FailurePayload {
        key: key.to_vec(),
        identity,
        versions: versions.to_vec(),
        reads: reads
            .iter()
            .map(|read| (read.query, read.answer.canonical_bytes()))
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
    let payload: FailurePayload = dm_wire::decode(FAILURE_SCHEMA, bytes, bytes.len()).ok()?;
    if validate_versions(&payload.versions).is_err()
        || payload.errors.is_empty()
        || payload
            .errors
            .iter()
            .any(|error| error.kind == dm_codegen_byond::LowerErrorKind::Internal)
    {
        return None;
    }

    (payload.key == key
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
pub(crate) fn encode_executable(
    key: &[u8],
    reads: &[ResolverRead],
    versions: &[(dm_ir::ReadDomain, u128)],
    code: &ResolverProc,
) -> Option<Vec<u8>> {
    let payload = Payload {
        version: 1,
        key: key.to_vec(),
        identity: None,
        effective: false,
        abi: None,
        debug: Vec::new(),
        relative_debug: Vec::new(),
        helpers: Vec::new(),
        versions: versions.to_vec(),
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
    parsed: Option<&dm_syntax::Item>,
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
        debug_origins,
        source_helpers,
    })
}

/// All variants have been typed and checked before any current resolver reads.
pub(crate) struct Candidates(Vec<Candidate>);
enum Candidate {
    Executable(Box<Payload>),
    Failure(FailurePayload),
}
/// Current source occurrence used when rebasing a persisted procedure result.
pub(crate) struct ProcedureReplayContext<'a> {
    pub frontend: &'a dm_tree::frontend::ColdFrontend,
    pub body: &'a dm_tree::frontend::BodyOccurrence,
    pub parsed: Option<&'a dm_syntax::Item>,
}
#[derive(Default)]
pub(crate) struct ProcedureLookup {
    pub unit: Option<LoweredUnit>,
    pub errors: Option<Vec<dm_codegen_byond::LowerError>>,
    pub changed_query: Option<ResolveQuery>,
    pub miss: Option<crate::lowering_memo::MemoMissReason>,
}
pub(crate) fn candidates(bytes: &[u8]) -> Result<Candidates, String> {
    let mut values = Vec::new();
    for bytes in dm_cache::decode_variants(bytes)? {
        if let Ok(value) = dm_wire::decode::<FailurePayload>(FAILURE_SCHEMA, bytes, bytes.len()) {
            validate_versions(&value.versions)?;
            if value.errors.is_empty()
                || value
                    .errors
                    .iter()
                    .any(|error| error.kind == dm_codegen_byond::LowerErrorKind::Internal)
            {
                return Err("uncacheable failure candidate".into());
            }
            values.push(Candidate::Failure(value));
        } else {
            values.push(Candidate::Executable(Box::new(payload(bytes)?)));
        }
    }
    Ok(Candidates(values))
}
#[derive(Default)]
pub(crate) struct AnonymousLookup {
    pub code: Option<ResolverProc>,
    pub errors: Option<Vec<dm_codegen_byond::LowerError>>,
}
impl Candidates {
    pub(crate) fn anonymous<R: Resolver>(
        self,
        key: &[u8],
        host: &R,
        debug_count: usize,
    ) -> AnonymousLookup {
        // Preserve the existing failure-first semantics across variants. Typed
        // payload admission happens once before either outcome is inspected.
        let mut executables = Vec::new();
        for candidate in self.0.into_iter().rev() {
            match candidate {
                Candidate::Failure(value) => {
                    if value.identity.is_none()
                        && value.key == key
                        && read_mismatch(&value.reads, &value.versions, host).is_none()
                    {
                        return AnonymousLookup {
                            errors: Some(
                                value.errors.into_iter().map(ErrorWire::rehydrate).collect(),
                            ),
                            code: None,
                        };
                    }
                }
                Candidate::Executable(value) => executables.push(value),
            }
        }
        for value in executables {
            if value.identity.is_some()
                || value.abi.is_some()
                || !value.helpers.is_empty()
                || value.key != key
                || read_mismatch(&value.reads, &value.versions, host).is_some()
            {
                continue;
            }
            if let Some(code) = value.body.rehydrate(host, debug_count) {
                return AnonymousLookup {
                    code: Some(code),
                    errors: None,
                };
            }
        }
        AnonymousLookup::default()
    }

    pub(crate) fn procedure<R: Resolver>(
        self,
        key: &[u8],
        identity: ProcedureIdentity,
        context: ProcedureReplayContext<'_>,
        host: &R,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> ProcedureLookup {
        let mut result = ProcedureLookup {
            miss: Some(crate::lowering_memo::MemoMissReason::FullKeyMismatch),
            ..Default::default()
        };
        for value in self.0.into_iter().rev() {
            let (candidate, owner, reads, versions) = match &value {
                Candidate::Executable(v) => (&v.key, v.identity, &v.reads, &v.versions),
                Candidate::Failure(v) => (&v.key, v.identity, &v.reads, &v.versions),
            };
            if candidate != key || owner != Some(identity) {
                continue;
            }
            result.miss = Some(crate::lowering_memo::MemoMissReason::NoExactVariant);
            if let Some(query) = read_mismatch(reads, versions, host) {
                result.changed_query.get_or_insert(query);
                continue;
            }
            match value {
                Candidate::Failure(v) => {
                    result.errors = Some(v.errors.into_iter().map(ErrorWire::rehydrate).collect());
                    return result;
                }
                Candidate::Executable(v) => {
                    match rebind(
                        *v,
                        context.frontend,
                        context.body,
                        host,
                        prepared,
                        context.parsed,
                    ) {
                        Ok(unit) => {
                            result.unit = Some(unit);
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
mod executable_tests {
    use super::*;
    struct Host(bool);
    impl Resolver for Host {
        fn resolve(&self, _: ResolveQuery) -> dm_ir::ResolvedMeaning {
            if self.0 {
                dm_ir::ResolvedMeaning::Symbol(SymbolId::of("/datum"))
            } else {
                dm_ir::ResolvedMeaning::Missing
            }
        }
    }
    #[test]
    fn anonymous_executable_roundtrips_and_rechecks_negative_reads() {
        let ast = dm_syntax::parse("/proc/p()\n    return 7\n");
        let body = &ast.items[0].children;
        let recorder = crate::lowering_memo::RecordingResolver::new(&Host(false));
        recorder.resolve(ResolveQuery::GlobalVar(SymbolId::of("absent")));
        let code = dm_codegen_byond::compile_simple_proc_with_resolver(
            body,
            &Default::default(),
            &Default::default(),
            &recorder,
        )
        .unwrap();
        let bytes = encode_executable(
            b"exact typed initializer",
            &recorder.reads(),
            &recorder.domain_receipts(),
            &code,
        )
        .unwrap();
        let restored =
            decode_executable(&bytes, b"exact typed initializer", &Host(false), 0).unwrap();
        let framed = dm_cache::encode_variants(std::slice::from_ref(&bytes)).unwrap();
        assert_eq!(candidates(&framed).unwrap().0.len(), 1);
        let mut bad = bytes.clone();
        *bad.last_mut().unwrap() ^= 1;
        let bad = dm_cache::encode_variants(&[bytes.clone(), bad]).unwrap();
        assert!(
            candidates(&bad).is_err(),
            "every variant must validate before replay"
        );

        assert_eq!(code.procedure, restored.procedure);
        assert!(decode_executable(&bytes, b"exact typed initializer", &Host(true), 0).is_none());
        assert!(decode_executable(&bytes, b"different initializer", &Host(false), 0).is_none());
        for end in [0, 8, 31, bytes.len() - 1] {
            assert!(
                decode_executable(&bytes[..end], b"exact typed initializer", &Host(false), 0)
                    .is_none()
            );
        }
        let mut tampered = bytes.clone();
        *tampered.last_mut().unwrap() ^= 1;
        assert!(
            decode_executable(&tampered, b"exact typed initializer", &Host(false), 0).is_none()
        );
        assert!(dm_wire::decode::<Payload>(EXECUTABLE_SCHEMA, &bytes, 1).is_err());
        let changed = Payload {
            version: 1,
            key: b"other key".to_vec(),
            identity: None,
            effective: false,
            reads: vec![],
            versions: vec![],
            body: CodeWire::capture(&code),
            debug: vec![],
            relative_debug: vec![],
            abi: None,
            helpers: vec![],
        };
        let changed = dm_wire::encode(EXECUTABLE_SCHEMA, &changed).unwrap();
        assert!(decode_executable(&changed, b"exact typed initializer", &Host(false), 0).is_none());
    }
    #[test]
    fn binary_failure_wire_preserves_optional_spans_and_rechecks_answers() {
        let errors = vec![
            dm_codegen_byond::LowerError {
                statement: "first".into(),
                reason: "unknown".into(),
                span: None,
                kind: dm_codegen_byond::LowerErrorKind::UnsupportedModel,
            },
            dm_codegen_byond::LowerError {
                statement: "second".into(),
                reason: "duplicate".into(),
                span: Some(dm_codegen_byond::LowerSpan { start: 3, end: 4 }),
                kind: dm_codegen_byond::LowerErrorKind::SourceError,
            },
        ];
        let recorder = crate::lowering_memo::RecordingResolver::new(&Host(false));
        recorder.resolve(ResolveQuery::GlobalVar(SymbolId::of("absent")));
        let bytes = encode_failure(
            b"failure",
            None,
            &recorder.reads(),
            &recorder.domain_receipts(),
            &errors,
        )
        .unwrap();
        assert_eq!(
            decode_failure(&bytes, b"failure", None, &Host(false)).unwrap(),
            errors
        );
        assert!(decode_failure(&bytes, b"failure", None, &Host(true)).is_none());
        assert!(decode_failure(&bytes, b"other", None, &Host(false)).is_none());
        let mut invalid = bytes;
        *invalid.last_mut().unwrap() ^= 1;
        assert!(validate(&invalid).is_err());
    }
    #[test]
    fn domain_receipts_apply_to_anonymous_success_and_failure_wire() {
        struct Versioned {
            version: Option<u128>,
            calls: std::sync::atomic::AtomicUsize,
            changed: bool,
        }
        impl Resolver for Versioned {
            fn domain_version(&self, _: dm_ir::ReadDomain) -> Option<u128> {
                self.version
            }
            fn resolve(&self, _: ResolveQuery) -> dm_ir::ResolvedMeaning {
                self.calls
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                if self.changed {
                    dm_ir::ResolvedMeaning::Symbol(SymbolId::of("changed"))
                } else {
                    dm_ir::ResolvedMeaning::Missing
                }
            }
        }
        let host = |version, changed| Versioned {
            version,
            changed,
            calls: Default::default(),
        };
        let original = host(Some(9), false);
        let recorder = crate::lowering_memo::RecordingResolver::new(&original);
        recorder.resolve(ResolveQuery::GlobalVar(SymbolId::of("absent")));
        let ast = dm_syntax::parse("/proc/p()\n    return 7\n");
        let code = dm_codegen_byond::compile_simple_proc_with_resolver(
            &ast.items[0].children,
            &Default::default(),
            &Default::default(),
            &recorder,
        )
        .unwrap();
        let success = encode_executable(
            b"versioned",
            &recorder.reads(),
            &recorder.domain_receipts(),
            &code,
        )
        .unwrap();
        let failure = encode_failure(
            b"versioned",
            None,
            &recorder.reads(),
            &recorder.domain_receipts(),
            &[dm_codegen_byond::LowerError {
                statement: "bad".into(),
                reason: "unsupported".into(),
                span: None,
                kind: dm_codegen_byond::LowerErrorKind::UnsupportedModel,
            }],
        )
        .unwrap();
        let same = host(Some(9), false);
        assert!(decode_executable(&success, b"versioned", &same, 0).is_some());
        assert!(decode_failure(&failure, b"versioned", None, &same).is_some());
        assert_eq!(same.calls.load(std::sync::atomic::Ordering::Relaxed), 0);
        let unknown = host(None, false);
        assert!(decode_executable(&success, b"versioned", &unknown, 0).is_some());
        assert!(decode_failure(&failure, b"versioned", None, &unknown).is_some());
        assert!(unknown.calls.load(std::sync::atomic::Ordering::Relaxed) >= 2);
        let changed = host(Some(10), true);
        assert!(decode_executable(&success, b"versioned", &changed, 0).is_none());
        assert!(decode_failure(&failure, b"versioned", None, &changed).is_none());
        assert!(
            validate_versions(&[(dm_ir::ReadDomain::Tree, 1), (dm_ir::ReadDomain::Tree, 2)])
                .is_err()
        );
    }
    #[test]
    fn unified_anonymous_lookup_preserves_failure_priority_and_exact_read_invalidation() {
        let ast = dm_syntax::parse("/proc/p()\n    return 7\n");
        let recorder = crate::lowering_memo::RecordingResolver::new(&Host(false));
        recorder.resolve(ResolveQuery::GlobalVar(SymbolId::of("absent")));
        let code = dm_codegen_byond::compile_simple_proc_with_resolver(
            &ast.items[0].children,
            &Default::default(),
            &Default::default(),
            &recorder,
        )
        .unwrap();
        let success = encode_executable(
            b"anonymous",
            &recorder.reads(),
            &recorder.domain_receipts(),
            &code,
        )
        .unwrap();
        let errors = vec![dm_codegen_byond::LowerError {
            statement: "unsupported".into(),
            reason: "captured failure".into(),
            span: None,
            kind: dm_codegen_byond::LowerErrorKind::UnsupportedModel,
        }];
        let failure = encode_failure(
            b"anonymous",
            None,
            &recorder.reads(),
            &recorder.domain_receipts(),
            &errors,
        )
        .unwrap();
        let success_only = dm_cache::encode_variants(std::slice::from_ref(&success)).unwrap();
        let replay = candidates(&success_only)
            .unwrap()
            .anonymous(b"anonymous", &Host(false), 0);
        assert_eq!(replay.code.unwrap().procedure, code.procedure);
        let mixed = dm_cache::encode_variants(&[failure, success]).unwrap();
        let replay = candidates(&mixed)
            .unwrap()
            .anonymous(b"anonymous", &Host(false), 0);
        assert_eq!(replay.errors, Some(errors));
        assert!(
            replay.code.is_none(),
            "failure priority preserved even when success is newer"
        );
        let changed = candidates(&mixed)
            .unwrap()
            .anonymous(b"anonymous", &Host(true), 0);
        assert!(changed.code.is_none() && changed.errors.is_none());
        let other = candidates(&mixed)
            .unwrap()
            .anonymous(b"other", &Host(false), 0);
        assert!(other.code.is_none() && other.errors.is_none());
    }
}

#[cfg(test)]
#[path = "lowering_memo_wire_typed_tests.rs"]
mod typed_identity_tests;
