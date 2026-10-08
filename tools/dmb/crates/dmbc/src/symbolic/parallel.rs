//! Bounded immutable unit freezing with deterministic ordered inventory replay.
use super::*;

enum Op {
    String(SymbolId, Arc<[u8]>),
    Spelling(SymbolId, Arc<[u8]>),
    Slot(SlotAlias),
    Entry(Entry),
}
#[derive(Default)]
struct Ops(Vec<Op>);
impl InventorySink for Ops {
    fn string(&mut self, id: SymbolId, bytes: &[u8]) {
        self.0.push(Op::String(id, Arc::from(bytes)));
    }
    fn slot(&mut self, alias: SlotAlias) {
        self.0.push(Op::Slot(alias));
    }
}
impl Ops {
    fn spelling(&mut self, id: SymbolId, bytes: &[u8]) {
        self.0.push(Op::Spelling(id, Arc::from(bytes)));
    }
    fn debug(&mut self, origins: &crate::debug_sources::DebugOrigins) {
        let mut seen = std::collections::HashSet::new();
        for origin in &origins.entries {
            if seen.insert(origin.semantic_path.as_str()) {
                self.string(
                    SymbolId::of(&origin.semantic_path),
                    origin.semantic_path.as_bytes(),
                );
            }
        }
    }
}
pub(super) struct Contribution {
    unit: FrozenUnit,
    helpers: Vec<FrozenHelper>,
    ops: Ops,
}
impl Contribution {
    pub(super) fn replay(
        self,
        inventory: &mut LinkInventory,
        strings: &mut StringInventory,
        units: &mut Vec<FrozenUnit>,
        helpers: &mut Vec<FrozenHelper>,
    ) {
        for op in self.ops.0 {
            match op {
                Op::String(id, bytes) => strings.append(inventory, id, &bytes),
                Op::Spelling(id, bytes) => strings.append_spelling(inventory, id, &bytes),
                Op::Slot(alias) => inventory.slots.push(alias),
                Op::Entry(entry) => inventory.entries.push(entry),
            }
        }
        units.push(self.unit);
        helpers.extend(self.helpers);
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
        ops.spelling(
            id,
            symbols
                .text(id)
                .ok_or(IntegrationError::MissingSpelling(id))?
                .as_bytes(),
        );
    }
    ops.debug(&lowered.debug_origins);
    // Exact frozen code content is known. Remaining proc metadata belongs
    // to explicit emitter policy, separately retained in LoweredUnit.
    ops.0.push(Op::Entry(Entry {
        key: unit_key(lowered.identity),
        content: procedure_content(&lowered, &frozen.code().canonical_bytes()),
    }));
    for helper in std::mem::take(&mut lowered.source_helpers) {
        if helper.owner != lowered.identity || !helper.code.procedure.argument_names.is_empty() {
            return Err(IntegrationError::Freeze {
                unit: lowered.identity,
                message: "invalid companion owner/formal frame".into(),
            });
        }
        let frozen_helper = freezing::freeze_artifact_to_sink(
            &helper.code,
            helper.owner,
            source_bindings,
            external,
            &mut ops,
            freeze_detail,
        )?;
        ops.debug(&helper.debug_origins);
        let key = helper_key(helper.owner, helper.argument);
        let mut content = b"dm-argument-source-v1\0".to_vec();
        let code = frozen_helper.code().canonical_bytes();
        content.extend_from_slice(&(code.len() as u64).to_le_bytes());
        content.extend_from_slice(&code);
        for name in &helper.code.procedure.local_names {
            content.extend_from_slice(&(name.len() as u64).to_le_bytes());
            content.extend_from_slice(name.as_bytes());
        }
        ops.0.push(Op::Entry(Entry {
            key,
            content: content.into(),
        }));
        helpers.push(FrozenHelper {
            owner: helper.owner,
            argument: helper.argument,
            frozen: Arc::new(frozen_helper),
            current_image: None,
            features: BytecodeFeatures::of(&helper.code.procedure.code),
            debug_origins: helper.debug_origins,
            local_names: helper.code.procedure.local_names,
        });
    }
    let unit = FrozenUnit {
        features: BytecodeFeatures::of(&lowered.code.procedure.code),
        lowered: FrozenUnitMetadata::consume(lowered),
        frozen: Arc::new(frozen),
        current_image: None,
    };
    Ok(Contribution { unit, helpers, ops })
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
