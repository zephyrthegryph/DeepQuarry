//! Admission of exact typed relocations before shared direct encoding.
use super::*;
pub(super) fn freeze_artifact_to_sink(
    code: &dm_codegen_byond::lower_resolver::ResolverProc,
    identity: UnitIdentity,
    source_bindings: &std::collections::BTreeSet<SymRef>,
    external: &ReferenceBindings,
    sink: &mut dyn InventorySink,
    freeze_detail: bool,
) -> Result<FrozenProc, IntegrationError> {
    let mut admitted = std::collections::BTreeSet::new();
    for payload in &code.procedure.strings {
        if SymbolId::of_bytes(&payload.bytes) != payload.id {
            return Err(IntegrationError::MissingSpelling(payload.id));
        }
        admitted.insert(SymRef::String(payload.id));
        sink.string(payload.id, &payload.bytes);
    }
    for (reference, identity) in &code.procedure_statics {
        if *reference != SymRef::ProcedureStatic(*identity) {
            return Err(IntegrationError::ConflictingBinding(*reference));
        }
        admitted.insert(*reference);
    }
    for (reference, value) in &code.procedure_values {
        let expected = unit_reference(UnitIdentity {
            owner: value.owner,
            name: value.name,
            namespace: if value.verb {
                Namespace::Verb
            } else {
                Namespace::Proc
            },
            occurrence: value.occurrence,
        });
        if *reference != expected {
            return Err(IntegrationError::ConflictingBinding(*reference));
        }
        admitted.insert(*reference);
    }
    for (reference, slot) in &code.slots {
        if *reference != SymRef::VariableSlot(slot.symbol) {
            return Err(IntegrationError::ConflictingBinding(*reference));
        }
        admitted.insert(*reference);
        sink.slot(SlotAlias {
            symbol: slot.symbol,
            owner: slot.owner,
            name: slot.name,
        });
    }
    for (reference, captured) in &code.modified_instances {
        if *reference != SymRef::Instance(SymbolId::of(&captured.descriptor.alias())) {
            return Err(IntegrationError::InvalidInitializer(
                "modified descriptor identity differs from exact content".into(),
            ));
        }
        admitted.insert(*reference);
    }
    for (alias, instance) in &code.instances {
        if *alias != instance.alias {
            return Err(IntegrationError::InvalidInitializer(
                "instance alias differs from resolver tuple".into(),
            ));
        }
        admitted.insert(SymRef::Instance(instance.alias));
    }
    for content in code.resources.values() {
        admitted.insert(SymRef::Resource(*content));
    }
    admitted.insert(SymRef::BuiltinGlobalVars);
    let mut unlicensed = None;
    code.procedure.code.for_each_reference(|reference| {
        if matches!(reference, SymRef::SourceFile(_) | SymRef::SourceLine(_)) {
            return;
        }
        if !admitted.contains(&reference)
            && !source_bindings.contains(&reference)
            && !external.references.contains(&reference)
        {
            unlicensed.get_or_insert(reference);
        }
    });
    if let Some(reference) = unlicensed {
        return Err(IntegrationError::Freeze {
            unit: identity,
            message: format!("uncaptured semantic reference {reference:?}"),
        });
    }
    freeze_proc_observed(&code.procedure.code, |stage| {
        freeze_detail.then(|| {
            dm_profile::item(match stage {
                FreezeStage::Encoding => "freeze.encoding",
                FreezeStage::DecodeValidation => "freeze.decode_validation",
                FreezeStage::SymbolicConstruction => "freeze.symbolic_construction",
                FreezeStage::SiteValidation => "freeze.site_validation",
            })
        })
    })
    .map_err(|error| IntegrationError::Freeze {
        unit: identity,
        message: error.to_string(),
    })
}
