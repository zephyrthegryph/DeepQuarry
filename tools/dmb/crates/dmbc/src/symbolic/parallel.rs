//! Bounded immutable unit freezing with deterministic ordered inventory replay.
use super::procedure_artifact::Contribution;
use super::*;
#[cfg(test)]
use dm_link::EntryContent;

#[derive(Default, Clone)]
pub(super) struct Slots(pub(super) Vec<SlotAlias>);
impl InventorySink for Slots {
    // Freezing emits only procedure.strings (see freezing.rs). Retain that
    // exact ordered roster by moving its buffers after successful validation,
    // rather than copying every occurrence into an Arc before deduplication.
    fn string(&mut self, _id: SymbolId, _bytes: &[u8]) {}
    fn slot(&mut self, alias: SlotAlias) {
        self.0.push(alias);
    }
}
#[derive(Clone)]
pub(super) struct OwnedStrings(pub(super) Vec<dm_ir::StringPayload>);
impl OwnedStrings {
    fn take(procedure: &mut dm_codegen_byond::SimpleProc) -> Self {
        Self(std::mem::take(&mut procedure.strings))
    }
    #[cfg(test)]
    pub(super) fn replay(&self, inventory: &mut LinkInventory, strings: &mut StringInventory) {
        for payload in &self.0 {
            strings.append(inventory, payload.id, &payload.bytes);
        }
    }
}
pub(super) struct HelperContribution {
    pub(super) helper: FrozenHelper,
    pub(super) strings: OwnedStrings,
    pub(super) slots: Slots,
    pub(super) content: dm_link::EntryContent,
    pub(super) instances: Vec<(SymbolId, SymbolId)>,
}
pub(super) struct BoundContribution {
    pub(super) unit: FrozenUnit,
    pub(super) strings: OwnedStrings,
    pub(super) helpers: Vec<HelperContribution>,
    pub(super) slots: Slots,
    pub(super) content: dm_link::EntryContent,
    pub(super) instances: Vec<(SymbolId, SymbolId)>,
}
fn compact_vec<T>(values: &mut Vec<T>) {
    if values.capacity() > values.len() {
        values.shrink_to_fit();
    }
}
fn compact_names(values: &mut Vec<String>) {
    for value in values.iter_mut() {
        if value.capacity() > value.len() {
            value.shrink_to_fit();
        }
    }
    compact_vec(values);
}
impl BoundContribution {
    /// Only retained completion payloads are compacted; discarded rich IR is untouched.
    fn compact_retained(&mut self) {
        compact_vec(&mut self.instances);
        let frame = Arc::make_mut(&mut self.unit.lowered.frame);
        compact_names(&mut frame.local_names);
        compact_names(&mut frame.argument_names);
        compact_vec(&mut frame.argument_type_flags);
        compact_vec(&mut self.strings.0);
        compact_vec(&mut self.slots.0);
        for helper in &mut self.helpers {
            compact_vec(&mut helper.instances);
            compact_names(Arc::make_mut(&mut helper.helper.local_names));
            compact_vec(&mut helper.strings.0);
            compact_vec(&mut helper.slots.0);
        }
        compact_vec(&mut self.helpers);
    }
}
pub(super) fn replay_shared_unit(
    unit: &FrozenUnit,
    contribution: Arc<dm_link::InventoryContribution>,
    inventory: &mut LinkInventory,
    strings: &mut StringInventory,
    symbols: &SymbolTable,
) {
    inventory.append_shared_strings(Arc::clone(&contribution));
    for id in [unit.lowered.identity.owner, unit.lowered.identity.name] {
        strings.append_spelling(
            inventory,
            id,
            symbols
                .text(id)
                .expect("spelling checked before contribution publication")
                .as_bytes(),
        );
    }
    append_debug_inventory(&unit.lowered.debug_origins, inventory, strings);
    inventory.append_shared(contribution);
}
pub(super) fn replay_shared_helper(
    helper: &FrozenHelper,
    contribution: Arc<dm_link::InventoryContribution>,
    inventory: &mut LinkInventory,
    strings: &mut StringInventory,
) {
    inventory.append_shared_strings(Arc::clone(&contribution));
    append_debug_inventory(&helper.debug_origins, inventory, strings);
    inventory.append_shared(contribution);
}
#[cfg(test)]
fn replay_inventory(
    slots: impl IntoIterator<Item = SlotAlias>,
    key: Key,
    content: EntryContent,
    inventory: &mut LinkInventory,
) {
    inventory.slots.extend(slots);
    inventory.entries.push(Entry { key, content });
}
pub(super) fn freeze_unit(
    mut lowered: LoweredUnit,
    symbols: &SymbolTable,
    source_bindings: &std::collections::BTreeSet<SymRef>,
    external: &ReferenceBindings,
    freeze_detail: bool,
) -> Result<Contribution, IntegrationError> {
    crate::procedure_warnings::validate(
        &lowered.code.procedure.warnings,
        lowered.debug_origins.entries.len(),
        symbols,
        &lowered.code.procedure.local_names,
    )
    .map_err(|message| IntegrationError::Freeze {
        unit: lowered.identity,
        message,
    })?;
    let mut slots = Slots::default();
    let mut helpers = Vec::new();
    let frozen = freezing::freeze_artifact_to_sink(
        &lowered.code,
        lowered.identity,
        source_bindings,
        external,
        &mut slots,
        freeze_detail,
    )?;
    for id in [lowered.identity.owner, lowered.identity.name] {
        symbols
            .text(id)
            .ok_or(IntegrationError::MissingSpelling(id))?;
    }
    // Exact frozen code content is known. Remaining proc metadata belongs
    // to explicit emitter policy, separately retained in LoweredUnit.
    let content = procedure_content(&lowered, frozen.shared_code());
    let strings = OwnedStrings::take(&mut lowered.code.procedure);
    for mut helper in std::mem::take(&mut lowered.source_helpers) {
        if helper.owner != lowered.identity || !helper.code.procedure.argument_names.is_empty() {
            return Err(IntegrationError::Freeze {
                unit: lowered.identity,
                message: "invalid companion owner/formal frame".into(),
            });
        }
        crate::procedure_warnings::validate(
            &helper.code.procedure.warnings,
            helper.debug_origins.entries.len(),
            symbols,
            &helper.code.procedure.local_names,
        )
        .map_err(|message| IntegrationError::Freeze {
            unit: lowered.identity,
            message,
        })?;
        let mut helper_slots = Slots::default();
        let frozen_helper = freezing::freeze_artifact_to_sink(
            &helper.code,
            helper.owner,
            source_bindings,
            external,
            &mut helper_slots,
            freeze_detail,
        )?;
        let mut prefix = b"dm-argument-source-v1\0".to_vec();
        let code = frozen_helper.shared_code();
        prefix.extend_from_slice(&(code.canonical_len() as u64).to_le_bytes());
        let mut suffix = Vec::new();
        for name in &helper.code.procedure.local_names {
            suffix.extend_from_slice(&(name.len() as u64).to_le_bytes());
            suffix.extend_from_slice(name.as_bytes());
        }
        let content = dm_link::EntryContent::symbolic(prefix.into(), code, suffix.into());
        let helper_strings = OwnedStrings::take(&mut helper.code.procedure);
        helpers.push(HelperContribution {
            instances: helper
                .code
                .instances
                .iter()
                .map(|(alias, value)| (*alias, value.runtime_type))
                .collect(),
            strings: helper_strings,
            slots: helper_slots,
            content,
            helper: FrozenHelper {
                warnings: std::mem::take(&mut helper.code.procedure.warnings).into(),
                owner: helper.owner,
                argument: helper.argument,
                frozen: Arc::new(frozen_helper),
                current_image: None,
                image_owner: Arc::new(Default::default()),
                features: BytecodeFeatures::from_procedure(&helper.code.procedure),
                debug_origins: helper.debug_origins.into(),
                local_names: Arc::new(helper.code.procedure.local_names),
            },
        });
    }
    let metadata_recipe = crate::composition::ProcedureMetadataRecipe::capture(
        lowered.identity,
        symbols,
        lowered.abi.as_deref(),
    )
    .map_err(|error| IntegrationError::Freeze {
        unit: lowered.identity,
        message: format!("procedure metadata recipe {error:?}"),
    })?;
    let instances = lowered
        .code
        .instances
        .iter()
        .map(|(alias, value)| (*alias, value.runtime_type))
        .collect();
    let unit = FrozenUnit {
        metadata_recipe: Arc::new(metadata_recipe),
        features: BytecodeFeatures::from_procedure(&lowered.code.procedure),
        lowered: FrozenUnitMetadata::consume(lowered),
        frozen: Arc::new(frozen),
        current_image: None,
        image_owner: Arc::new(Default::default()),
    };
    let mut contribution = BoundContribution {
        unit,
        strings,
        helpers,
        slots,
        content,
        instances,
    };
    contribution.compact_retained();
    Ok(Contribution::from_bound(contribution))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordered_string_roster_and_binary_templates_move_without_payload_copies() {
        let literal_payload = dm_ir::StringPayload::new(Arc::<[u8]>::from(&b"literal"[..]));
        let template_payload =
            dm_ir::StringPayload::new(Arc::<[u8]>::from(&[0xff, 0x16, b'X'][..]));
        let mut procedure = dm_codegen_byond::SimpleProc {
            strings: vec![literal_payload.clone(), template_payload, literal_payload],
            ..Default::default()
        };
        let literal = procedure.strings[0].bytes.as_ptr();
        let template = procedure.strings[1].bytes.as_ptr();
        let owned = OwnedStrings::take(&mut procedure);
        assert!(procedure.strings.is_empty());
        assert_eq!(owned.0[0].bytes.as_ptr(), literal);
        assert_eq!(owned.0[1].bytes.as_ptr(), template);
        assert_eq!(owned.0[0], owned.0[2]);
        let mut inventory = LinkInventory::default();
        let mut strings = StringInventory::new(&inventory);
        owned.replay(&mut inventory, &mut strings);
        assert_eq!(inventory.entries.len(), 2);
        assert_eq!(
            inventory.entries[0].key,
            Key::String(SymbolId::of("literal"))
        );
        assert_eq!(inventory.entries[1].content.as_ref(), &[0xff, 0x16, b'X']);
    }
}

#[cfg(test)]
mod inventory_tests {
    use super::*;
    #[test]
    fn compact_inventory_preserves_slots_and_exact_entry_content() {
        let first = SlotAlias {
            symbol: SymbolId::of("slot-a"),
            owner: SymbolId::of("/datum/a"),
            name: SymbolId::of("a"),
        };
        let second = SlotAlias {
            symbol: SymbolId::of("slot-b"),
            owner: SymbolId::of("/datum/b"),
            name: SymbolId::of("b"),
        };
        let key = unit_key(UnitIdentity {
            owner: SymbolId::of("/datum/a"),
            name: SymbolId::of("run"),
            namespace: Namespace::Proc,
            occurrence: 7,
        });
        let content: Arc<[u8]> = Arc::from(&b"exact retained content"[..]);
        let original = Arc::clone(&content);
        let mut inventory = LinkInventory::default();
        replay_inventory(vec![first, second], key, content.into(), &mut inventory);
        assert_eq!(inventory.slots, vec![first, second]);
        assert_eq!(inventory.entries.len(), 1);
        assert_eq!(inventory.entries[0].key, key);
        assert!(Arc::ptr_eq(
            &inventory.entries[0].content.shared_bytes(),
            &original
        ));
    }
}
