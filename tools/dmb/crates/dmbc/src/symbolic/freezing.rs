use super::*;
pub(super) fn freeze_artifact_to_sink(
    code: &dm_codegen_byond::lower_resolver::ResolverProc,
    identity: UnitIdentity,
    source_bindings: &BTreeMap<Symbol, SymRef>,
    external: &ReferenceBindings,
    sink: &mut dyn InventorySink,
    freeze_detail: bool,
) -> Result<FrozenProc, IntegrationError> {
    let mut bindings = BTreeMap::new();
    for spelling in &code.procedure.strings {
        let bytes = code
            .procedure
            .format_templates
            .get(spelling)
            .map(|bytes| bytes.as_slice())
            .unwrap_or(spelling.as_bytes());
        let id = SymbolId::of_bytes(bytes);
        insert(
            &mut bindings,
            Symbol::new(Table::String, spelling),
            SymRef::String(id),
        )?;
        sink.string(id, bytes);
    }
    for (symbol, identity) in &code.procedure_statics {
        insert(
            &mut bindings,
            symbol.clone(),
            SymRef::ProcedureStatic(*identity),
        )?;
    }
    for (symbol, identity) in &code.procedure_values {
        let reference = if identity.verb {
            SymRef::Verb {
                owner: identity.owner,
                name: identity.name,
                occurrence: identity.occurrence,
            }
        } else {
            SymRef::Proc {
                owner: identity.owner,
                name: identity.name,
                occurrence: identity.occurrence,
            }
        };
        insert(&mut bindings, symbol.clone(), reference)?;
    }
    for (symbol, slot) in &code.slots {
        insert(
            &mut bindings,
            symbol.clone(),
            SymRef::VariableSlot(slot.symbol),
        )?;
        sink.slot(SlotAlias {
            symbol: slot.symbol,
            owner: slot.owner,
            name: slot.name,
        });
        // Slot payload/type/default is not derivable from presence. The
        // caller supplies its actual entry; only identity is recorded here.
    }
    for (symbol, captured) in &code.modified_instances {
        let alias = captured.descriptor.alias();
        if symbol != &Symbol::new(Table::Instance, &alias) {
            return Err(IntegrationError::InvalidInitializer(
                "modified descriptor symbol differs from exact content".into(),
            ));
        }
        insert(
            &mut bindings,
            symbol.clone(),
            SymRef::Instance(SymbolId::of(&alias)),
        )?;
    }
    for (path, instance) in &code.instances {
        insert(
            &mut bindings,
            Symbol::new(Table::Instance, path),
            SymRef::Instance(instance.alias),
        )?;
        // Runtime type is known; the captured modifier artifact is not
        // inferred here and must exist in the caller's inventory.
    }
    for (path, content) in &code.resources {
        insert(
            &mut bindings,
            Symbol::new(Table::Resource, path),
            SymRef::Resource(*content),
        )?;
    }
    insert(
        &mut bindings,
        Symbol::new(
            Table::Variable,
            dm_codegen_byond::BUILTIN_GLOBAL_VARS_SYMBOL,
        ),
        SymRef::BuiltinGlobalVars,
    )?;
    let frozen = freeze_proc_observed(
        &code.procedure.code,
        |symbol| {
            let local = bindings.get(symbol).copied();
            let source = source_bindings.get(symbol).copied();
            let captured = external.references.get(symbol).copied();
            let selected = local
                .or(source)
                .or(captured)
                .ok_or_else(|| format!("uncaptured semantic reference {symbol:?}"))?;
            if [local, source, captured]
                .into_iter()
                .flatten()
                .any(|reference| reference != selected)
            {
                return Err(format!(
                    "conflicting captured semantic reference {symbol:?}"
                ));
            }
            Ok(selected)
        },
        |stage| {
            freeze_detail.then(|| {
                dm_profile::item(match stage {
                    FreezeStage::Encoding => "freeze.encoding",
                    FreezeStage::DecodeValidation => "freeze.decode_validation",
                    FreezeStage::Binding => "freeze.semantic_binding",
                    FreezeStage::SymbolicConstruction => "freeze.symbolic_construction",
                    FreezeStage::SiteValidation => "freeze.site_validation",
                })
            })
        },
    )
    .map_err(|error| IntegrationError::Freeze {
        unit: identity,
        message: error.to_string(),
    })?;
    Ok(frozen)
}
