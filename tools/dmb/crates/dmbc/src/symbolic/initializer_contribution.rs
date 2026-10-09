//! Shared anonymous encoding payload. Current coverage and source origins remain
//! outside this owner and must be admitted on every request before replay.
use super::*;

/// Installed only on an initializer assembly admitted by the common artifact
/// store. This memo belongs to that semantic payload, never to a dense output.
#[derive(Default)]
pub(crate) struct InitializerEncoding {
    ready: std::sync::OnceLock<Arc<FrozenInitializerContribution>>,
}

pub(crate) struct FrozenInitializerContribution {
    pub(crate) frozen: Arc<FrozenProc>,
    pub(crate) slots: Vec<SlotAlias>,
    pub(crate) strings: Vec<dm_ir::StringPayload>,
}

impl InitializerEncoding {
    pub(crate) fn retained(&self) -> Option<&Arc<FrozenInitializerContribution>> {
        self.ready.get()
    }

    pub(crate) fn get(&self) -> Option<Arc<FrozenInitializerContribution>> {
        self.ready.get().map(Arc::clone)
    }

    /// The caller must complete the same current semantic-reference licensing
    /// as the fresh freeze path before reading or publishing this payload.
    pub(crate) fn install(
        &self,
        contribution: FrozenInitializerContribution,
    ) -> Arc<FrozenInitializerContribution> {
        Arc::clone(self.ready.get_or_init(|| Arc::new(contribution)))
    }
}

impl FrozenInitializerContribution {
    pub(super) fn replay(&self, inventory: &mut LinkInventory, strings: &mut StringInventory) {
        for payload in &self.strings {
            strings.append(inventory, payload.id, &payload.bytes);
        }
        inventory.slots.extend(self.slots.iter().copied());
    }
}

struct Admission {
    slots: Vec<SlotAlias>,
}
impl InventorySink for Admission {
    fn string(&mut self, _id: SymbolId, _bytes: &[u8]) {}
    fn slot(&mut self, slot: SlotAlias) {
        self.slots.push(slot);
    }
}
pub(super) fn freeze_current(
    unit: &crate::initialization_artifact::InitializationArtifact,
    identity: UnitIdentity,
    source_bindings: &std::collections::BTreeSet<SymRef>,
    external: &ReferenceBindings,
    freeze_detail: bool,
) -> Result<Arc<FrozenInitializerContribution>, IntegrationError> {
    let mut admission = Admission { slots: Vec::new() };
    // Even an encoding hit authenticates all sidecars and current captured
    // reference licenses. Cached words remain symbolic, not table-bound.
    freezing::admit_artifact_to_sink(
        &unit.code,
        identity,
        source_bindings,
        external,
        &mut admission,
    )?;
    if let Some(hit) = unit.encoding.as_ref().and_then(|owner| owner.get()) {
        return Ok(hit);
    }
    let frozen = freezing::encode_admitted(&unit.code, identity, freeze_detail)?;
    let contribution = FrozenInitializerContribution {
        frozen: Arc::new(frozen),
        slots: admission.slots,
        strings: unit.code.procedure.strings.clone(),
    };
    Ok(match &unit.encoding {
        Some(owner) => owner.install(contribution),
        None => Arc::new(contribution),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shared_encoding_rebinds_current_coverage_and_rejects_missing_license() {
        use crate::initialization_artifact::{InitializationArtifact, InitializationCoverage};
        use dm_codegen_byond::lower_resolver::ResolverProc;
        let encoding = Arc::new(InitializerEncoding::default());
        let code = ResolverProc {
            procedure: Default::default(),
            modified_instances: Default::default(),
            procedure_values: Default::default(),
            procedure_statics: Default::default(),
            slots: Default::default(),
            resources: Default::default(),
            instances: Default::default(),
        };
        let mut unit = InitializationArtifact {
            identity: dm_link::InitializerIdentity::Global,
            code: Arc::new(code),
            debug_origins: Arc::new(Default::default()),
            coverage: InitializationCoverage::DeclarationWrites(vec![2]),
            encoding: Some(encoding),
        };
        let context = UnitIdentity {
            owner: SymbolId::of("/"),
            name: SymbolId::of("<initializer>"),
            namespace: Namespace::Proc,
            occurrence: 0,
        };
        let bindings = Default::default();
        let external = ReferenceBindings::default();
        let first = freeze_current(&unit, context, &bindings, &external, false).unwrap();
        unit.coverage = InitializationCoverage::DeclarationWrites(vec![500]);
        let shifted = freeze_current(&unit, context, &bindings, &external, false).unwrap();
        assert!(Arc::ptr_eq(&first, &shifted));
        let mut fresh = unit.clone();
        fresh.encoding = None;
        let independent = freeze_current(&fresh, context, &bindings, &external, false).unwrap();
        assert_eq!(
            first.frozen.code().canonical_bytes(),
            independent.frozen.code().canonical_bytes()
        );
        let invalid = Arc::make_mut(&mut unit.code);
        invalid
            .procedure
            .code
            .items
            .push(dm_codegen_byond::Item::Instruction(
                dm_codegen_byond::Instruction {
                    opcode: 0,
                    operands: vec![dm_codegen_byond::Word::Reference(SymRef::String(
                        SymbolId::of("unlicensed"),
                    ))],
                },
            ));
        assert!(freeze_current(&unit, context, &bindings, &external, false).is_err());
    }
}
