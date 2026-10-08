//! Bounded immutable unit freezing with deterministic ordered inventory replay.
use super::*;

enum Op {
    Slot(SlotAlias),
    Entry(Entry),
}
#[derive(Default)]
struct Ops(Vec<Op>);
impl InventorySink for Ops {
    // Freezing emits only procedure.strings (see freezing.rs). Retain that
    // exact ordered roster by moving its buffers after successful validation,
    // rather than copying every occurrence into an Arc before deduplication.
    fn string(&mut self, _id: SymbolId, _bytes: &[u8]) {}
    fn slot(&mut self, alias: SlotAlias) {
        self.0.push(Op::Slot(alias));
    }
}
struct OwnedStrings {
    spellings: Vec<String>,
    templates: std::collections::HashMap<String, Vec<u8>>,
}

impl OwnedStrings {
    fn take(procedure: &mut dm_codegen_byond::SimpleProc) -> Self {
        Self {
            spellings: std::mem::take(&mut procedure.strings),
            templates: std::mem::take(&mut procedure.format_templates),
        }
    }
    fn replay(&self, inventory: &mut LinkInventory, strings: &mut StringInventory) {
        for spelling in &self.spellings {
            let bytes = self
                .templates
                .get(spelling)
                .map(Vec::as_slice)
                .unwrap_or_else(|| spelling.as_bytes());
            strings.append(inventory, SymbolId::of_bytes(bytes), bytes);
        }
    }
}
struct HelperContribution {
    helper: FrozenHelper,
    strings: OwnedStrings,
    ops: Ops,
}
pub(super) struct Contribution {
    unit: FrozenUnit,
    strings: OwnedStrings,
    helpers: Vec<HelperContribution>,
    ops: Ops,
}
impl Contribution {
    pub(super) fn replay(
        self,
        inventory: &mut LinkInventory,
        strings: &mut StringInventory,
        symbols: &SymbolTable,
        units: &mut Vec<FrozenUnit>,
        helpers: &mut Vec<FrozenHelper>,
    ) {
        self.strings.replay(inventory, strings);
        for id in [
            self.unit.lowered.identity.owner,
            self.unit.lowered.identity.name,
        ] {
            strings.append_spelling(
                inventory,
                id,
                symbols
                    .text(id)
                    .expect("spelling checked before contribution publication")
                    .as_bytes(),
            );
        }
        append_debug_inventory(&self.unit.lowered.debug_origins, inventory, strings);
        replay_ops(self.ops, inventory);
        units.push(self.unit);
        for contribution in self.helpers {
            contribution.strings.replay(inventory, strings);
            append_debug_inventory(&contribution.helper.debug_origins, inventory, strings);
            replay_ops(contribution.ops, inventory);
            helpers.push(contribution.helper);
        }
    }
}
fn replay_ops(ops: Ops, inventory: &mut LinkInventory) {
    for op in ops.0 {
        match op {
            Op::Slot(alias) => inventory.slots.push(alias),
            Op::Entry(entry) => inventory.entries.push(entry),
        }
    }
}
fn freeze_unit(
    mut lowered: LoweredUnit,
    symbols: &SymbolTable,
    source_bindings: &BTreeMap<Symbol, SymRef>,
    external: &ReferenceBindings,
    freeze_detail: bool,
) -> Result<Contribution, IntegrationError> {
    let mut ops = Ops::default();
    let mut helpers = Vec::new();
    let frozen = freezing::freeze_artifact_to_sink(
        &lowered.code,
        lowered.identity,
        source_bindings,
        external,
        &mut ops,
        freeze_detail,
    )?;
    for id in [lowered.identity.owner, lowered.identity.name] {
        symbols
            .text(id)
            .ok_or(IntegrationError::MissingSpelling(id))?;
    }
    // Exact frozen code content is known. Remaining proc metadata belongs
    // to explicit emitter policy, separately retained in LoweredUnit.
    ops.0.push(Op::Entry(Entry {
        key: unit_key(lowered.identity),
        content: procedure_content(&lowered, &frozen.code().canonical_bytes()),
    }));
    let strings = OwnedStrings::take(&mut lowered.code.procedure);
    for mut helper in std::mem::take(&mut lowered.source_helpers) {
        if helper.owner != lowered.identity || !helper.code.procedure.argument_names.is_empty() {
            return Err(IntegrationError::Freeze {
                unit: lowered.identity,
                message: "invalid companion owner/formal frame".into(),
            });
        }
        let mut helper_ops = Ops::default();
        let frozen_helper = freezing::freeze_artifact_to_sink(
            &helper.code,
            helper.owner,
            source_bindings,
            external,
            &mut helper_ops,
            freeze_detail,
        )?;
        let key = helper_key(helper.owner, helper.argument);
        let mut content = b"dm-argument-source-v1\0".to_vec();
        let code = frozen_helper.code().canonical_bytes();
        content.extend_from_slice(&(code.len() as u64).to_le_bytes());
        content.extend_from_slice(&code);
        for name in &helper.code.procedure.local_names {
            content.extend_from_slice(&(name.len() as u64).to_le_bytes());
            content.extend_from_slice(name.as_bytes());
        }
        helper_ops.0.push(Op::Entry(Entry {
            key,
            content: content.into(),
        }));
        let helper_strings = OwnedStrings::take(&mut helper.code.procedure);
        helpers.push(HelperContribution {
            strings: helper_strings,
            ops: helper_ops,
            helper: FrozenHelper {
                owner: helper.owner,
                argument: helper.argument,
                frozen: Arc::new(frozen_helper),
                current_image: None,
                features: BytecodeFeatures::of(&helper.code.procedure.code),
                debug_origins: helper.debug_origins,
                local_names: helper.code.procedure.local_names,
            },
        });
    }
    let unit = FrozenUnit {
        features: BytecodeFeatures::of(&lowered.code.procedure.code),
        lowered: FrozenUnitMetadata::consume(lowered),
        frozen: Arc::new(frozen),
        current_image: None,
    };
    Ok(Contribution {
        unit,
        strings,
        helpers,
        ops,
    })
}

/// At most one outstanding owned unit per worker; results cannot accumulate a
/// second unbounded rich-IR batch. All workers are joined before errors escape.
pub(super) fn freeze_units(
    units: Vec<LoweredUnit>,
    symbols: &SymbolTable,
    source_bindings: &BTreeMap<Symbol, SymRef>,
    external: &ReferenceBindings,
    freeze_detail: bool,
    workers: usize,
    mut emit: impl FnMut(Contribution),
) -> Result<(), IntegrationError> {
    let workers = workers.clamp(1, 8).min(units.len().max(1));
    if workers == 1 {
        for unit in units {
            emit(freeze_unit(
                unit,
                symbols,
                source_bindings,
                external,
                freeze_detail,
            )?);
        }
        return Ok(());
    }
    std::thread::scope(|scope| {
        let (completed_tx, completed_rx) = std::sync::mpsc::sync_channel(workers);
        let mut senders = Vec::new();
        let mut handles = Vec::new();
        for _ in 0..workers {
            let (tx, rx) = std::sync::mpsc::sync_channel::<(usize, LoweredUnit)>(1);
            senders.push(tx);
            let completed = completed_tx.clone();
            handles.push(scope.spawn(move || {
                // One natural lifetime scope records all worker CPU, including
                // shared encoder scopes only when detail profiling is requested.
                let _profile = dm_profile::stage("linking.freeze_artifacts");
                while let Ok((index, unit)) = rx.recv() {
                    let identity = unit.identity;
                    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                        freeze_unit(unit, symbols, source_bindings, external, freeze_detail)
                    }))
                    .unwrap_or_else(|_| {
                        Err(IntegrationError::Freeze {
                            unit: identity,
                            message: "unit freezing worker panicked".into(),
                        })
                    });
                    if completed.send((index, result)).is_err() {
                        break;
                    }
                }
            }));
        }
        drop(completed_tx);
        let mut pending = units.into_iter();
        let mut outcome = Ok(());
        loop {
            let wave: Vec<_> = pending.by_ref().take(workers).collect();
            if wave.is_empty() {
                break;
            }
            let count = wave.len();
            for (index, unit) in wave.into_iter().enumerate() {
                senders[index]
                    .send((index, unit))
                    .expect("freeze worker receiver vanished");
            }
            let mut ordered: Vec<_> = (0..count).map(|_| None).collect();
            for _ in 0..count {
                let (index, result) = completed_rx.recv().expect("freeze worker result vanished");
                ordered[index] = Some(result);
            }
            for result in ordered {
                match result.expect("every freeze task has an indexed result") {
                    Ok(contribution) => emit(contribution),
                    Err(error) => {
                        outcome = Err(error);
                        break;
                    }
                }
            }
            if outcome.is_err() {
                break;
            }
        }
        drop(senders);
        for handle in handles {
            handle.join().expect("unit freezing scheduler panicked");
        }
        outcome
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordered_string_roster_and_binary_templates_move_without_payload_copies() {
        let mut procedure = dm_codegen_byond::SimpleProc {
            strings: vec!["literal".into(), "template".into(), "literal".into()],
            ..Default::default()
        };
        procedure
            .format_templates
            .insert("template".into(), vec![0xff, 0x16, b'X']);
        let literal = procedure.strings[0].as_ptr();
        let template = procedure.format_templates["template"].as_ptr();
        let owned = OwnedStrings::take(&mut procedure);
        assert!(procedure.strings.is_empty());
        assert!(procedure.format_templates.is_empty());
        assert_eq!(owned.spellings[0].as_ptr(), literal);
        assert_eq!(owned.templates["template"].as_ptr(), template);
        assert_eq!(owned.spellings, ["literal", "template", "literal"]);
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
