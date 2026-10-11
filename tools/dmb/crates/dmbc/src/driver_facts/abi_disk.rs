//! Optional ABI transport. The shared store remains the sole admitted answer owner.
//! No source positions, dense member IDs or process-issued versions cross disk.
use super::{observations, UnitArtifact};
use crate::{
    procedure_policy::{PreparedAbi, PreparedUnit},
    runner_host::disk::LazyDisk,
};
use dm_codegen_byond::{
    procedure_abi::{ArgumentSource, Category, ProcLayout},
    ProcedureInputs,
};
use dm_ir::{ProcedureIdentity, ResolveQuery, ResolvedMeaning, Resolver};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Arc, OnceLock},
};
const SCHEMA: u32 = 0x0204_0012;
const ENGINE_SCHEMA: u32 = 0x0204_0011;
const LIMIT: usize = 1024 * 1024;
const VERSION: u32 = 2;
#[derive(Serialize, Deserialize, PartialEq)]
struct EngineProof {
    bytes: Vec<u8>,
    schema: u128,
    bootstrap: bool,
    compiler: u128,
    pure_policy: Option<Vec<u8>>,
}
#[derive(Serialize, Deserialize, PartialEq)]
struct InputsProof {
    engine: (u128, bool, u128),
    pure_policy: Option<Vec<u8>>,
    metadata: Vec<u8>,
    predecessor: Option<Vec<u8>>,
    boundary: Vec<u8>,
    resource: Option<u128>,
    evaluation_resource: Option<u128>,
    lexical: bool,
}
#[derive(Serialize, Deserialize)]
struct InputWire {
    identity: Option<ProcedureIdentity>,
    procedure: Option<String>,
    owner: Option<String>,
    parameters: Vec<String>,
    flags: Vec<u32>,
    sources: Vec<u32>,
    defaults: Vec<Option<String>>,
    types: BTreeMap<String, String>,
    readonly: BTreeSet<u32>,
    resource: Option<u128>,
}
#[derive(Serialize, Deserialize)]
struct AbiWire {
    display: Option<Vec<u8>>,
    description: Option<Vec<u8>>,
    category: u8,
    text: Vec<u8>,
    source_kind: u8,
    source_parameter: u8,
    flags: u32,
    invisibility: Option<u8>,
    arguments: Vec<(u8, u8)>,
}
#[derive(Serialize, Deserialize)]
struct UnitWire {
    identity: ProcedureIdentity,
    key: Vec<u8>,
    proof: InputsProof,
    inputs: InputWire,
    abi: AbiWire,
    reads: Vec<(ResolveQuery, Vec<u8>)>,
}
pub(super) struct Transport {
    disk: Arc<LazyDisk>,
    policy: u128,
    engine_owner: Arc<crate::runner_host::EnginePayload>,
    engine_admitted: OnceLock<(Option<Vec<u8>>, bool)>,
    engine_staged: OnceLock<()>,
}
impl Transport {
    pub(super) fn new(
        disk: Arc<LazyDisk>,
        policy: u128,
        engine_owner: Arc<crate::runner_host::EnginePayload>,
    ) -> Self {
        Self {
            disk,
            policy,
            engine_owner,
            engine_admitted: OnceLock::new(),
            engine_staged: OnceLock::new(),
        }
    }
    fn key(&self, stage: u32, bytes: &[u8]) -> dm_cache::RecordKey {
        let mut locator = self.policy.to_le_bytes().to_vec();
        locator.extend_from_slice(bytes);
        dm_cache::RecordKey {
            stage,
            version: VERSION,
            content: xxhash_rust::xxh3::xxh3_128(&locator),
        }
    }
    fn engine(&self, current: &observations::Inputs, pure: Option<&[u8]>) -> EngineProof {
        let (bytes, schema, bootstrap, compiler) = current.engine.disk_abi_authority();
        EngineProof {
            bytes: bytes.to_vec(),
            schema,
            bootstrap,
            compiler,
            pure_policy: pure.map(<[u8]>::to_vec),
        }
    }
    fn engine_key(&self, proof: &EngineProof) -> Option<dm_cache::RecordKey> {
        let bytes = dm_wire::encode(ENGINE_SCHEMA, proof).ok()?;
        Some(self.key(10, &bytes))
    }
    fn admit_engine(&self, current: &observations::Inputs, pure: Option<&[u8]>) -> bool {
        if !Arc::ptr_eq(&self.engine_owner, &current.engine) {
            return false;
        }
        let (policy, admitted) = self.engine_admitted.get_or_init(|| {
            let proof = self.engine(current, pure);
            let admitted = self
                .engine_key(&proof)
                .and_then(|key| {
                    self.disk.snapshot()?.get_candidate(key, |bytes, symbols| {
                        if !symbols.is_empty() {
                            return Err("ABI engine spelling sidecar".into());
                        }
                        let candidates = dm_cache::decode_variants(bytes)?;
                        let decoded: Vec<EngineProof> = candidates
                            .iter()
                            .map(|bytes| dm_wire::decode(ENGINE_SCHEMA, bytes, 32 * LIMIT))
                            .collect::<Result<_, _>>()?;
                        Ok(decoded.iter().any(|old| old == &proof))
                    })
                })
                .is_some();
            (pure.map(<[u8]>::to_vec), admitted)
        });
        policy.as_deref() == pure && *admitted
    }

    pub(super) fn lookup(
        &self,
        key: &[u8],
        identity: ProcedureIdentity,
        current: &observations::Current<'_>,
        pure: Option<&[u8]>,
        recording: &dyn Resolver,
    ) -> Option<PreparedUnit> {
        let proof = InputsProof::capture(&current.inputs, pure)?;
        if !self.admit_engine(&current.inputs, pure) {
            return None;
        }
        let snapshot = self.disk.snapshot()?;
        let accepted = std::cell::RefCell::new(None);
        snapshot.get_candidate(self.key(9, key), |bytes, symbols| {
            if !symbols.is_empty() {
                return Err("ABI unit spelling sidecar".into());
            }
            // Validate the entire bucket before semantic callbacks. A malformed
            // older variant must not be hidden by an otherwise matching first row.
            let decoded = decode_bucket(bytes)?;
            for wire in decoded {
                if wire.key != key || wire.identity != identity || wire.proof != proof {
                    continue;
                }
                if !wire.reads.iter().all(|(query, answer)| {
                    let value = recording.resolve(*query);
                    portable(&value) && value.canonical_bytes() == *answer
                }) {
                    continue;
                }
                let unit = wire.hydrate();
                *accepted.borrow_mut() = Some(unit);
                return Ok(true);
            }
            Ok(false)
        })?;
        accepted.into_inner()
    }
    pub(super) fn stage(
        &self,
        key: &[u8],
        identity: ProcedureIdentity,
        current: &observations::Inputs,
        pure: Option<&[u8]>,
        artifact: &UnitArtifact,
        reads: &[dm_session::ResolverRead],
    ) {
        let Some(proof) = InputsProof::capture(current, pure) else {
            return;
        };
        let Some(abi) = AbiWire::capture(&artifact.abi) else {
            return;
        };
        if reads.iter().any(|read| !portable(&read.answer)) {
            return;
        }
        let wire = UnitWire {
            identity,
            key: key.to_vec(),
            proof,
            inputs: InputWire::capture(&artifact.inputs),
            abi,
            reads: reads
                .iter()
                .map(|read| (read.query, read.answer.canonical_bytes()))
                .collect(),
        };
        if wire.validate().is_err() {
            return;
        }
        let Ok(bytes) = dm_wire::encode_bounded(SCHEMA, &wire, LIMIT) else {
            return;
        };
        let Ok(payload) = dm_cache::encode_variants(&[bytes]) else {
            return;
        };
        self.engine_staged.get_or_init(|| {
            let proof = self.engine(current, pure);
            if let (Some(key), Ok(bytes)) = (
                self.engine_key(&proof),
                dm_wire::encode_bounded(ENGINE_SCHEMA, &proof, 32 * LIMIT),
            ) {
                if let Ok(payload) = dm_cache::encode_variants(&[bytes]) {
                    let _ = self.disk.append_records(vec![dm_cache::Record {
                        key,
                        symbols: Vec::new(),
                        payload: payload.into(),
                    }]);
                }
            }
        });
        // Cache failures are optional optimization failures; the common request
        // batch is poisoned/cleaned by LazyDisk and valid compiler output survives.
        let _ = self.disk.append_records(vec![dm_cache::Record {
            key: self.key(9, key),
            symbols: Vec::new(),
            payload: payload.into(),
        }]);
    }
}
fn decode_bucket(bytes: &[u8]) -> Result<Vec<UnitWire>, String> {
    let candidates = dm_cache::decode_variants(bytes)?;
    let decoded: Vec<UnitWire> = candidates
        .iter()
        .map(|bytes| dm_wire::decode(SCHEMA, bytes, LIMIT))
        .collect::<Result<_, _>>()?;
    for wire in &decoded {
        wire.validate()?;
    }
    Ok(decoded)
}
fn portable(value: &ResolvedMeaning) -> bool {
    match value {
        ResolvedMeaning::Unsupported(_) | ResolvedMeaning::RetainedProc { .. } => false,
        ResolvedMeaning::Members(values) => values.iter().all(portable),
        _ => true,
    }
}
impl InputsProof {
    fn capture(inputs: &observations::Inputs, pure: Option<&[u8]>) -> Option<Self> {
        let (bytes, schema, bootstrap, compiler) = inputs.engine.disk_abi_authority();
        // This initial codec admits only the exact checked-in template. A unit
        // cannot refer to an arbitrary engine by a content hash: collisions in
        // the shared proof bucket would otherwise lose its engine association.
        if bytes != include_bytes!("../../../../fixtures/native_template.bin") {
            return None;
        }
        let boundary = match &inputs.boundary {
            observations::Boundary::Absent => vec![0],
            observations::Boundary::Fresh => vec![1],
            observations::Boundary::Engine { owner, name, kind } => {
                let mut bytes = vec![2];
                bytes.extend_from_slice(&owner.bits().to_le_bytes());
                bytes.extend_from_slice(&name.bits().to_le_bytes());
                bytes.push(match kind {
                    dm_tree::MemberKind::Proc => 0,
                    dm_tree::MemberKind::Verb => 1,
                    _ => return None,
                });
                bytes
            }
            // This receipt includes a process-issued intrinsic identity. Never
            // turn it into a persistent authority by hashing or truncating it.
            observations::Boundary::Intrinsic { .. } => return None,
        };
        Some(Self {
            engine: (schema, bootstrap, compiler),
            pure_policy: pure.map(<[u8]>::to_vec),
            metadata: inputs.metadata.canonical_bytes(),
            predecessor: inputs.predecessor.as_ref().map(|abi| abi.canonical_bytes()),
            boundary,
            resource: inputs.resource,
            evaluation_resource: inputs.evaluation_resource,
            lexical: inputs.lexical,
        })
    }
}
impl InputWire {
    fn capture(inputs: &ProcedureInputs) -> Self {
        Self {
            identity: inputs.procedure_identity,
            procedure: inputs.current_proc_path.clone(),
            owner: inputs.current_type_path.clone(),
            parameters: inputs.parameters.clone(),
            flags: inputs.parameter_type_flags.clone(),
            sources: inputs.parameter_value_sources.clone(),
            defaults: inputs.parameter_defaults.clone(),
            types: inputs
                .parameter_types
                .iter()
                .map(|(a, b)| (a.clone(), b.clone()))
                .collect(),
            readonly: inputs.readonly_parameters.clone(),
            resource: inputs.resource_search_context,
        }
    }
    fn hydrate(self) -> ProcedureInputs {
        ProcedureInputs {
            procedure_identity: self.identity,
            current_proc_path: self.procedure,
            current_type_path: self.owner,
            parameters: self.parameters,
            parameter_type_flags: self.flags,
            parameter_value_sources: self.sources,
            parameter_defaults: self.defaults,
            parameter_types: self.types.into_iter().collect(),
            readonly_parameters: self.readonly,
            resource_search_context: self.resource,
        }
    }
}
impl AbiWire {
    fn capture(abi: &PreparedAbi) -> Option<Self> {
        // Helper expressions require their current source-binding recipe. This
        // initial transport declines them instead of persisting historical ASTs.
        if !abi.source_helpers.is_empty() {
            return None;
        }
        let arguments = abi
            .argument_sources
            .iter()
            .map(|source| match source {
                ArgumentSource::Builtin { kind, parameter } => Some((*kind, *parameter)),
                ArgumentSource::Helper { .. } => None,
            })
            .collect::<Option<Vec<_>>>()?;
        let (category, text) = match &abi.layout.category {
            Category::Default => (0, Vec::new()),
            Category::Null => (1, Vec::new()),
            Category::Text(text) => (2, text.clone()),
        };
        Some(Self {
            display: abi.layout.display_name.clone(),
            description: abi.layout.description.clone(),
            category,
            text,
            source_kind: abi.layout.source_kind,
            source_parameter: abi.layout.source_parameter,
            flags: abi.layout.flags,
            invisibility: abi.layout.invisibility,
            arguments,
        })
    }
    fn hydrate(self) -> PreparedAbi {
        PreparedAbi {
            layout: ProcLayout {
                display_name: self.display,
                description: self.description,
                category: match self.category {
                    0 => Category::Default,
                    1 => Category::Null,
                    _ => Category::Text(self.text),
                },
                source_kind: self.source_kind,
                source_parameter: self.source_parameter,
                flags: self.flags,
                invisibility: self.invisibility,
            },
            argument_sources: self
                .arguments
                .into_iter()
                .map(|(kind, parameter)| ArgumentSource::Builtin { kind, parameter })
                .collect(),
            source_helpers: Vec::new(),
        }
    }
}
fn identifier(value: &str) -> bool {
    let mut bytes = value.bytes();
    bytes
        .next()
        .is_some_and(|byte| byte.is_ascii_alphabetic() || byte == b'_')
        && bytes.all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
}
fn path(value: &str, root: bool) -> bool {
    (root && value == "/")
        || value
            .strip_prefix('/')
            .is_some_and(|rest| !rest.is_empty() && rest.split('/').all(identifier))
}
impl UnitWire {
    fn validate(&self) -> Result<(), String> {
        let identity = self.identity;
        let issued_locator = observations::locator(crate::lowering::UnitIdentity {
            owner: identity.owner,
            name: identity.name,
            occurrence: identity.occurrence,
            namespace: if identity.verb {
                crate::lowering::Namespace::Verb
            } else {
                crate::lowering::Namespace::Proc
            },
        });
        let mandatory = [
            ResolveQuery::Ancestry(identity.owner),
            ResolveQuery::DeclarationChain {
                owner: identity.owner,
                name: identity.name,
                verb: identity.verb,
            },
        ];
        let mandatory_reads = mandatory.iter().all(|query| {
            self.reads.iter().any(|(old, answer)| {
                old == query
                    && answer.starts_with(b"dm-resolved-meaning-v1\0")
                    && answer
                        .get(b"dm-resolved-meaning-v1\0".len())
                        .is_some_and(|tag| *tag != 1)
            })
        });
        let count = self.inputs.parameters.len();
        let input = &self.inputs;
        // Production prepare_verified_procedure populates every vector once per
        // formal, including absent defaults. The helper-free transport must also
        // carry exactly one encoded builtin source for each formal.
        let vectors = input.flags.len() == count
            && input.sources.len() == count
            && input.defaults.len() == count
            && self.abi.arguments.len() == count;
        let sources =
            self.abi
                .arguments
                .iter()
                .zip(&input.sources)
                .all(|((kind, parameter), encoded)| {
                    matches!(*kind, 1 | 2 | 5 | 8 | 16)
                        && *encoded == ((u32::from(*parameter) << 8) | u32::from(*kind))
                        && (*kind != 8 && *kind != 16 || *parameter == 127)
                });
        let paths = match (&input.identity, &input.procedure, &input.owner) {
            // This is the actual unbound preparation producer's representation.
            (None, None, None) => true,
            (Some(identity), Some(procedure), Some(owner)) => {
                path(owner, true)
                    && path(procedure, false)
                    && dm_ir::SymbolId::of(owner) == identity.owner
                    && procedure.rsplit('/').next().is_some_and(|name| {
                        identifier(name) && dm_ir::SymbolId::of(name) == identity.name
                    })
            }
            _ => false,
        };
        let boundary = matches!(self.proof.boundary.as_slice(), [0] | [1])
            || (self.proof.boundary.len() == 18
                && self.proof.boundary[0] == 2
                && self.proof.boundary[17] <= 1);
        if self.key != issued_locator.as_ref()
            || !mandatory_reads
            || input.identity.is_some_and(|current| current != identity)
            || self.key.is_empty()
            || self.key.len() > 128
            || count > 255
            || !vectors
            || !sources
            || !paths
            || !boundary
            || input.resource != self.proof.resource
            || input.parameters.iter().any(|name| !identifier(name))
            || input.flags.iter().any(|flags| flags & !0x1fff != 0)
            || input
                .types
                .iter()
                .any(|(name, ty)| !input.parameters.contains(name) || !path(ty, false))
            || self.reads.len() > 65536
            || self.reads.windows(2).any(|pair| pair[0].0 >= pair[1].0)
            || self.abi.category > 2
            || (self.abi.category != 2 && !self.abi.text.is_empty())
            || !matches!(self.abi.source_kind, 0 | 1 | 2 | 3 | 5 | 8 | 16)
            || input.readonly.iter().any(|slot| *slot as usize >= count)
        {
            return Err("malformed ABI unit recipe".into());
        }
        Ok(())
    }
    fn hydrate(self) -> PreparedUnit {
        let mut unit = PreparedUnit {
            canonical: None,
            inputs: Arc::new(self.inputs.hydrate()),
            abi: Some(Arc::new(self.abi.hydrate())),
            executable_body: Vec::new(),
        };
        unit.issue_canonical();
        unit
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn source_neutral_wire_roundtrips_all_supported_fields() {
        let mut inputs = ProcedureInputs::default();
        inputs.parameters = vec!["value".into()];
        inputs.parameter_type_flags = vec![8];
        inputs.parameter_value_sources = vec![(125 << 8) | 1];
        inputs.parameter_defaults = vec![Some("7".into())];
        inputs
            .parameter_types
            .insert("value".into(), "/datum".into());
        inputs.readonly_parameters.insert(0);
        let abi = PreparedAbi {
            layout: ProcLayout {
                category: Category::Text(b"Tools".to_vec()),
                invisibility: Some(0),
                ..ProcLayout::default()
            },
            argument_sources: vec![ArgumentSource::Builtin {
                kind: 1,
                parameter: 125,
            }],
            source_helpers: Vec::new(),
        };
        let identity = ProcedureIdentity {
            owner: dm_ir::SymbolId::of("/"),
            name: dm_ir::SymbolId::of("probe"),
            verb: false,
            occurrence: 0,
        };
        let locator = observations::locator(crate::lowering::UnitIdentity {
            owner: identity.owner,
            name: identity.name,
            occurrence: identity.occurrence,
            namespace: crate::lowering::Namespace::Proc,
        });
        let engine = crate::runner_host::EnginePayload::capture(
            include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
            1,
            true,
            0,
        )
        .unwrap();
        let frontend = super::super::production_tests::frontend(
            "/proc/probe(value=7)\n    return value\n",
            &engine.snapshot,
        );
        let mut reads = [
            ResolveQuery::Ancestry(identity.owner),
            ResolveQuery::DeclarationChain {
                owner: identity.owner,
                name: identity.name,
                verb: false,
            },
        ]
        .into_iter()
        .map(|query| {
            let answer = Resolver::resolve(frontend.snapshot.tree.as_ref(), query);
            assert!(portable(&answer));
            (query, answer.canonical_bytes())
        })
        .collect::<Vec<_>>();
        reads.sort_by_key(|(query, _)| *query);
        let wire = UnitWire {
            identity,
            key: locator.to_vec(),
            proof: InputsProof {
                engine: (1, true, 0),
                pure_policy: None,
                metadata: vec![1],
                predecessor: None,
                boundary: vec![1],
                resource: None,
                evaluation_resource: None,
                lexical: false,
            },
            inputs: InputWire::capture(&inputs),
            abi: AbiWire::capture(&abi).unwrap(),
            reads,
        };
        let bytes = dm_wire::encode(SCHEMA, &wire).unwrap();
        let corruptions: &[fn(&mut UnitWire)] = &[
            |wire| {
                wire.reads
                    .retain(|(query, _)| !matches!(query, ResolveQuery::Ancestry(_)));
            },
            |wire| {
                wire.reads
                    .retain(|(query, _)| !matches!(query, ResolveQuery::DeclarationChain { .. }));
            },
            |wire| {
                wire.identity.occurrence += 1;
            },
            |wire| {
                wire.key[0] ^= 1;
            },
            |wire| {
                wire.reads[0].1.clear();
            },
            |wire| {
                wire.inputs.flags.clear();
            },
            |wire| {
                wire.inputs.defaults.clear();
            },
            |wire| {
                wire.inputs.sources[0] = 0;
            },
            |wire| {
                wire.abi.arguments.clear();
            },
            |wire| {
                wire.inputs.types.insert("unknown".into(), "/datum".into());
            },
            |wire| {
                wire.inputs.owner = Some("/datum".into());
            },
            |wire| {
                wire.inputs.readonly.insert(1);
            },
            |wire| {
                wire.inputs.resource = Some(99);
            },
        ];
        for corrupt in corruptions {
            let mut row: UnitWire = dm_wire::decode(SCHEMA, &bytes, LIMIT).unwrap();
            corrupt(&mut row);
            let malformed = dm_wire::encode(SCHEMA, &row).unwrap();
            let bucket = dm_cache::encode_variants(&[bytes.clone(), malformed]).unwrap();
            assert!(
                decode_bucket(&bucket).is_err(),
                "malformed later row must reject all candidates"
            );
        }
        let decoded: UnitWire = dm_wire::decode(SCHEMA, &bytes, LIMIT).unwrap();
        decoded.validate().unwrap();
        let unit = decoded.hydrate();
        assert_eq!(unit.abi.as_ref().unwrap().as_ref(), &abi);
        assert_eq!(unit.inputs.parameter_types, inputs.parameter_types);
        assert_eq!(unit.inputs.parameter_defaults, inputs.parameter_defaults);
        assert_eq!(unit.inputs.readonly_parameters, inputs.readonly_parameters);
        assert!(unit.canonical_metadata().is_some());
        assert!(dm_wire::decode::<UnitWire>(SCHEMA + 1, &bytes, LIMIT).is_err());
        // A later validly framed but invalid typed candidate rejects the whole
        // bucket before the common lookup can invoke its semantic resolver.
        let mut malformed: UnitWire = dm_wire::decode(SCHEMA, &bytes, LIMIT).unwrap();
        malformed.abi.category = 99;
        let bad = dm_wire::encode(SCHEMA, &malformed).unwrap();
        let bucket = dm_cache::encode_variants(&[bytes, bad]).unwrap();
        assert!(decode_bucket(&bucket).is_err());
        assert!(!portable(&ResolvedMeaning::Unsupported(
            ResolveQuery::GlobalProc(dm_ir::SymbolTable::default().intern("missing").unwrap())
        )));
    }
}
