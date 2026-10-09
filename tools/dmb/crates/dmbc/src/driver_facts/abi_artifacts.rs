//! Immutable ABI answers; revision authority and executable bodies remain current.
use super::*;
use crate::procedure_policy::{PreparedAbi, PreparedUnit};
use dm_codegen_byond::ProcedureInputs;
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning};
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Mutex,
};
struct Artifact {
    inputs: ProcedureInputs,
    abi: Arc<PreparedAbi>,
}
pub struct AbiArtifacts {
    store: dm_session::ArtifactStore<Artifact>,
    reused: AtomicUsize,
    recomputed: AtomicUsize,
}
impl Default for AbiArtifacts {
    fn default() -> Self {
        Self {
            store: dm_session::ArtifactStore::current_revision(),
            reused: AtomicUsize::new(0),
            recomputed: AtomicUsize::new(0),
        }
    }
}
impl AbiArtifacts {
    pub fn totals(&self) -> (usize, usize) {
        (
            self.reused.load(Ordering::Relaxed),
            self.recomputed.load(Ordering::Relaxed),
        )
    }
    pub(super) fn prune(&self, keys: &Mutex<Vec<Arc<[u8]>>>) {
        let keys = keys.lock().unwrap_or_else(|error| error.into_inner());
        self.store
            .retain_current_keys(keys.iter().map(|key| key.as_ref()));
    }
}
struct BorrowedResolver<'a>(&'a dyn Resolver);
impl Resolver for BorrowedResolver<'_> {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.0.resolve(query)
    }
    fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
        self.0.domain_version(domain)
    }
}
fn bytes(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    out.extend_from_slice(bytes);
}
fn layout_bytes(layout: &ProcLayout) -> Vec<u8> {
    PreparedAbi {
        layout: layout.clone(),
        argument_sources: Vec::new(),
        source_helpers: Vec::new(),
    }
    .canonical_bytes()
}
#[allow(clippy::too_many_arguments)] // Exact inherited boundary and current authenticated metadata are independent inputs.
fn key(
    identity: UnitIdentity,
    metadata: &dm_ir::ProcedureMetadata,
    engine: &EngineSnapshot,
    boundary: Option<&BoundaryAbi>,
    predecessor: Option<&PreparedAbi>,
    resource: Option<u128>,
    lexical: bool,
) -> Vec<u8> {
    let mut out = b"dm-process-abi-artifact-v1\0".to_vec();
    out.extend_from_slice(&engine.identity().to_le_bytes());
    out.extend_from_slice(&identity.owner.bits().to_le_bytes());
    out.extend_from_slice(&identity.name.bits().to_le_bytes());
    out.push(u8::from(identity.namespace == Namespace::Verb));
    out.extend_from_slice(&identity.occurrence.to_le_bytes());
    bytes(&mut out, &metadata.canonical_bytes());
    out.push(u8::from(lexical));
    out.push(u8::from(resource.is_some()));
    if let Some(resource) = resource {
        out.extend_from_slice(&resource.to_le_bytes());
    }
    out.push(u8::from(predecessor.is_some()));
    if let Some(predecessor) = predecessor {
        bytes(&mut out, &predecessor.canonical_bytes());
    }
    match boundary {
        None => out.push(0),
        Some(BoundaryAbi::Fresh) => out.push(1),
        Some(BoundaryAbi::CertifiedIntrinsic(receipt)) => {
            out.push(2);
            out.extend_from_slice(&receipt.engine_identity.to_le_bytes());
            out.extend_from_slice(&receipt.owner.bits().to_le_bytes());
            out.extend_from_slice(&receipt.name.bits().to_le_bytes());
            bytes(&mut out, &layout_bytes(&receipt.layout));
        }
        Some(BoundaryAbi::Engine { owner, name, kind }) => {
            out.push(3);
            out.extend_from_slice(&owner.bits().to_le_bytes());
            out.extend_from_slice(&name.bits().to_le_bytes());
            out.push(match kind {
                MemberKind::Proc => 0,
                MemberKind::Verb => 1,
                MemberKind::Var => 2,
            });
        }
    }
    out
}
#[allow(clippy::too_many_arguments)] // This is the single optional artifact adapter around current ABI preparation.
pub(super) fn prepare(
    store: &AbiArtifacts,
    keys: &Mutex<Vec<Arc<[u8]>>>,
    metadata: &dm_ir::ProcedureMetadata,
    parsed: &dm_syntax::Item,
    context: &AbiContext<'_>,
    evaluator: &DriverEvaluator<'_>,
    inherited: &DriverInheritedFacts<'_>,
    lexical: bool,
    resource: Option<u128>,
) -> Result<PreparedUnit, AbiError> {
    // Always authenticate the current issued header/settings before accepting old answers.
    let mut symbols = dm_ir::SymbolTable::default();
    if dm_tree::settings::extract_settings(&parsed.children, &mut symbols)
        .map_err(AbiError::unsupported)?
        .as_ref()
        != metadata.settings.as_ref()
    {
        return Err(AbiError::unsupported(
            "captured procedure setting tree differs from actual body",
        ));
    }
    inherited.inherited(context)?; // Current boundary/ancestry admission is not a cached certificate.
    let member = inherited
        .unit_members
        .get(&context.identity)
        .ok_or_else(|| AbiError::unsupported("body identity missing"))?;
    let node = inherited
        .frontend
        .snapshot
        .tree
        .member(*member)
        .ok_or_else(|| AbiError::unsupported("body member missing"))?;
    let predecessor = node
        .previous
        .and_then(|previous| inherited.source_layouts.get(&previous));
    let mut encoded_key = key(
        context.identity,
        metadata,
        inherited.engine,
        inherited.boundaries.get(&context.identity),
        predecessor.map(|abi| abi.as_ref()),
        resource,
        lexical,
    );
    let pure_policy = evaluator
        .pure_calls
        .map(|calls| calls.immutable_policy_identity());
    let reusable = !matches!(pure_policy, Some(None));
    match pure_policy {
        None => encoded_key.push(0),
        Some(Some(identity)) => {
            encoded_key.push(1);
            encoded_key.extend_from_slice(&identity.to_le_bytes());
        }
        Some(None) => encoded_key.push(2),
    }
    let key: Arc<[u8]> = encoded_key.into();
    keys.lock()
        .unwrap_or_else(|error| error.into_inner())
        .push(Arc::clone(&key));
    let base = BorrowedResolver(evaluator.resolver);
    if reusable {
        if let Some(artifact) = store.store.lookup(&key, &base) {
            store.reused.fetch_add(1, Ordering::Relaxed);
            return Ok(PreparedUnit {
                inputs: artifact.inputs.clone(),
                abi: Some(Arc::clone(&artifact.abi)),
                executable_body: Vec::new(),
            });
        }
    }
    let recording = dm_session::RecordingResolver::new(&base);
    recording.record_occurrence(dm_ir::ProcedureIdentity {
        owner: context.identity.owner,
        name: context.identity.name,
        verb: context.identity.namespace == Namespace::Verb,
        occurrence: context.identity.occurrence,
    });
    let evaluated = DriverEvaluator {
        pure_calls: evaluator.pure_calls,
        resource_search_context: evaluator.resource_search_context,
        resolver: &recording,
        symbols: evaluator.symbols,
    };
    let lexical_evaluator = LexicalAbiEvaluator(&evaluated);
    let selected: &dyn CapturedConstantEvaluator = if lexical {
        &lexical_evaluator
    } else {
        &evaluated
    };
    let policy = crate::procedure_policy::CapturedProcedurePolicy {
        evaluator: selected,
        inherited,
        resource_search_context: resource,
    };
    let recorded_context = AbiContext {
        resolver: &recording,
        ..*context
    };
    let mut unit = policy.prepare(metadata, parsed, &recorded_context)?;
    store.recomputed.fetch_add(1, Ordering::Relaxed);
    if reusable {
        let abi = Arc::clone(
            unit.abi
                .as_ref()
                .ok_or_else(|| AbiError::unsupported("production ABI missing"))?,
        );
        let inputs = unit.inputs.clone();
        let reads = recording.reads();
        let versions = recording.domain_receipts();
        if let Some(weight) =
            crate::heap_census::resident_abi_weight(&inputs, &abi, &key, &reads, &versions)
        {
            store
                .store
                .insert_with(key, reads, versions, weight, || Artifact { inputs, abi });
        }
    }
    unit.executable_body = Vec::new();
    Ok(unit)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn retained_key_seals_boundary_predecessor_metadata_and_resource_context() {
        let engine = EngineSnapshot::from_bytes(
            include_bytes!("../../../../fixtures/native_template.bin"),
            1,
        )
        .unwrap();
        let identity = UnitIdentity {
            owner: SymbolId::of("/datum/a"),
            name: SymbolId::of("p"),
            namespace: Namespace::Proc,
            occurrence: 0,
        };
        let mut metadata = dm_ir::ProcedureMetadata {
            signature: dm_ir::ProcedureSignature {
                parameters: Arc::from([]),
                variadic: false,
                return_annotation: None,
            },
            settings: Arc::from([]),
        };
        let fresh = BoundaryAbi::Fresh;
        let original = key(identity, &metadata, &engine, Some(&fresh), None, None, true);
        assert_ne!(
            original,
            key(identity, &metadata, &engine, None, None, None, true)
        );
        assert_ne!(
            original,
            key(
                identity,
                &metadata,
                &engine,
                Some(&fresh),
                None,
                Some(0),
                true
            )
        );
        metadata.signature.variadic = true;
        assert_ne!(
            original,
            key(identity, &metadata, &engine, Some(&fresh), None, None, true)
        );
        let mut predecessor = PreparedAbi {
            layout: ProcLayout::default(),
            argument_sources: Vec::new(),
            source_helpers: Vec::new(),
        };
        let base = key(
            identity,
            &metadata,
            &engine,
            Some(&fresh),
            Some(&predecessor),
            None,
            true,
        );
        predecessor.argument_sources.push(
            dm_codegen_byond::procedure_abi::ArgumentSource::Builtin {
                kind: 1,
                parameter: 2,
            },
        );
        assert_ne!(
            base,
            key(
                identity,
                &metadata,
                &engine,
                Some(&fresh),
                Some(&predecessor),
                None,
                true
            )
        );
        let mut changed = identity;
        changed.occurrence = 1;
        assert_ne!(
            base,
            key(
                changed,
                &metadata,
                &engine,
                Some(&fresh),
                Some(&predecessor),
                None,
                true
            )
        );
    }
}

#[cfg(test)]
#[path = "abi_artifacts_production_tests.rs"]
mod production_tests;
