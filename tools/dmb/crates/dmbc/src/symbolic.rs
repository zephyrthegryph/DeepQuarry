//! Real lowering→shared encoder→canonical linker bridge, with explicit externals.
use crate::lowering::{LoweredUnit, LoweringBatch, Namespace, UnitIdentity};
use dm_codegen_byond::{freeze_proc, FrozenProc, Symbol, Table};
use dm_ir::{SymRef, SymbolId, SymbolTable};
use dm_link::{Entry, Key, LinkInventory, LinkTables, ProcedureImage, SlotAlias, SourceBindings};
use std::{collections::BTreeMap, sync::Arc};

/// External engine/class/proc/instance/list/resource facts must be captured by the
/// caller. No legacy ledger, dense IDs or fabricated missing payloads are used.
#[derive(Clone, Debug, Default)]
pub struct ReferenceBindings {
    pub references: BTreeMap<Symbol, SymRef>,
}
pub struct FrozenUnit {
    pub lowered: LoweredUnit,
    pub frozen: FrozenProc,
}
pub struct FrozenBatch {
    pub units: Vec<FrozenUnit>,
    pub tables: LinkTables,
}
#[derive(Debug)]
pub enum IntegrationError {
    LoweringFailed(usize),
    MissingSpelling(SymbolId),
    DuplicateUnit(UnitIdentity),
    ConflictingBinding(Symbol),
    Freeze { unit: UnitIdentity, message: String },
    Link(dm_link::LinkError),
}
impl FrozenBatch {
    /// Current source origins stay outside reusable code. Shared IR encoding is
    /// the only packed/direct path. This does not write a DMB section.
    pub fn link_unit(
        &self,
        index: usize,
        source: &SourceBindings,
    ) -> Result<ProcedureImage, IntegrationError> {
        let unit = self
            .units
            .get(index)
            .ok_or(IntegrationError::LoweringFailed(index))?;
        let current = unit.lowered.debug_origins.source_bindings();
        let source = if source.files.is_empty() && source.lines.is_empty() {
            &current
        } else {
            source
        };
        self.tables
            .link(unit.frozen.code(), source)
            .map_err(IntegrationError::Link)
    }
}
pub fn freeze_and_link_tables(
    batch: LoweringBatch,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    mut inventory: LinkInventory,
) -> Result<FrozenBatch, IntegrationError> {
    if !batch.diagnostics.is_empty() {
        return Err(IntegrationError::LoweringFailed(batch.diagnostics.len()));
    }
    batch
        .identity_index()
        .map_err(IntegrationError::DuplicateUnit)?;
    let mut units = Vec::with_capacity(batch.units.len());
    let mut source_procs = BTreeMap::new();
    for unit in &batch.units {
        let owner = symbols
            .text(unit.identity.owner)
            .ok_or(IntegrationError::MissingSpelling(unit.identity.owner))?;
        let name = symbols
            .text(unit.identity.name)
            .ok_or(IntegrationError::MissingSpelling(unit.identity.name))?;
        let path = format!(
            "{}/{}/{}",
            owner.trim_end_matches('/'),
            if unit.identity.namespace == Namespace::Verb {
                "verb"
            } else {
                "proc"
            },
            name
        );
        let reference = unit_reference(unit.identity);
        source_procs
            .entry(Symbol::new(Table::Proc, path))
            .and_modify(|old: &mut (u32, SymRef)| {
                if old.0 < unit.identity.occurrence {
                    *old = (unit.identity.occurrence, reference);
                }
            })
            .or_insert((unit.identity.occurrence, reference));
    }
    for lowered in batch.units {
        let mut bindings = BTreeMap::new();
        for spelling in &lowered.code.procedure.strings {
            let bytes = lowered
                .code
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
            inventory.spellings.push((id, Arc::from(bytes)));
            inventory.entries.push(Entry {
                key: Key::String(id),
                content: Arc::from(bytes),
            });
        }
        for (symbol, slot) in &lowered.code.slots {
            insert(
                &mut bindings,
                symbol.clone(),
                SymRef::VariableSlot(slot.symbol),
            )?;
            inventory.slots.push(SlotAlias {
                symbol: slot.symbol,
                owner: slot.owner,
                name: slot.name,
            });
            // Slot payload/type/default is not derivable from presence. The
            // caller supplies its actual entry; only identity is recorded here.
        }
        for (path, instance) in &lowered.code.instances {
            insert(
                &mut bindings,
                Symbol::new(Table::Instance, path),
                SymRef::Instance(instance.alias),
            )?;
            // Runtime type is known; the captured modifier artifact is not
            // inferred here and must exist in the caller's inventory.
        }
        for (path, content) in &lowered.code.resources {
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
        let frozen = freeze_proc(&lowered.code.procedure.code, |symbol| {
            let local = bindings.get(symbol).copied();
            let source = source_procs.get(symbol).map(|(_, reference)| *reference);
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
        })
        .map_err(|error| IntegrationError::Freeze {
            unit: lowered.identity,
            message: error.to_string(),
        })?;
        for id in [lowered.identity.owner, lowered.identity.name] {
            inventory.spellings.push((
                id,
                Arc::from(
                    symbols
                        .text(id)
                        .ok_or(IntegrationError::MissingSpelling(id))?
                        .as_bytes(),
                ),
            ));
        }
        for origin in &lowered.debug_origins.entries {
            let bytes: Arc<[u8]> = Arc::from(origin.semantic_path.as_bytes());
            let symbol = SymbolId::of(&origin.semantic_path);
            inventory.spellings.push((symbol, bytes.clone()));
            inventory.entries.push(Entry {
                key: Key::String(symbol),
                content: bytes,
            });
        }
        // Exact frozen code content is known. Remaining proc metadata belongs
        // to explicit emitter policy, separately retained in LoweredUnit.
        inventory.entries.push(Entry {
            key: unit_key(lowered.identity),
            content: procedure_content(&lowered, &frozen.code().canonical_bytes()),
        });
        units.push(FrozenUnit { lowered, frozen });
    }
    let tables = LinkTables::build(inventory).map_err(IntegrationError::Link)?;
    // Validate all captured references before publishing any linked output.
    for unit in &units {
        tables
            .link(
                unit.frozen.code(),
                &unit.lowered.debug_origins.source_bindings(),
            )
            .map_err(IntegrationError::Link)?;
    }
    Ok(FrozenBatch { units, tables })
}
fn procedure_content(lowered: &LoweredUnit, code_bytes: &[u8]) -> Arc<[u8]> {
    let mut bytes = b"dm-frozen-procedure-v2\0".to_vec();
    match &lowered.abi {
        None => bytes.push(0),
        Some(abi) => {
            bytes.push(1);
            let encoded = abi.canonical_bytes();
            bytes.extend_from_slice(&(encoded.len() as u64).to_le_bytes());
            bytes.extend_from_slice(&encoded);
        }
    }
    let metadata = lowered.metadata.canonical_bytes();
    for part in [code_bytes, metadata.as_slice()] {
        bytes.extend_from_slice(&(part.len() as u64).to_le_bytes());
        bytes.extend_from_slice(part);
    }
    let procedure = &lowered.code.procedure;
    bytes.extend_from_slice(&procedure.local_count.to_le_bytes());
    for names in [&procedure.local_names, &procedure.argument_names] {
        bytes.extend_from_slice(&(names.len() as u64).to_le_bytes());
        for name in names {
            bytes.extend_from_slice(&(name.len() as u64).to_le_bytes());
            bytes.extend_from_slice(name.as_bytes());
        }
    }
    for values in [
        &procedure.argument_type_flags,
        &procedure.argument_value_sources,
    ] {
        bytes.extend_from_slice(&(values.len() as u64).to_le_bytes());
        for value in values {
            bytes.extend_from_slice(&value.to_le_bytes());
        }
    }
    bytes.into()
}
fn insert(
    bindings: &mut BTreeMap<Symbol, SymRef>,
    symbol: Symbol,
    reference: SymRef,
) -> Result<(), IntegrationError> {
    if bindings
        .insert(symbol.clone(), reference)
        .is_some_and(|old| old != reference)
    {
        return Err(IntegrationError::ConflictingBinding(symbol));
    }
    Ok(())
}
fn unit_reference(identity: UnitIdentity) -> SymRef {
    match identity.namespace {
        Namespace::Proc => SymRef::Proc {
            owner: identity.owner,
            name: identity.name,
            occurrence: identity.occurrence,
        },
        Namespace::Verb => SymRef::Verb {
            owner: identity.owner,
            name: identity.name,
            occurrence: identity.occurrence,
        },
    }
}
fn unit_key(identity: UnitIdentity) -> Key {
    match identity.namespace {
        Namespace::Proc => Key::Proc {
            owner: identity.owner,
            name: identity.name,
            occurrence: identity.occurrence,
        },
        Namespace::Verb => Key::Verb {
            owner: identity.owner,
            name: identity.name,
            occurrence: identity.occurrence,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lowering::{lower_frontend, AbiPolicy, LoweringConfig};
    use dm_codegen_byond::ProcedureInputs;
    use dm_ir::{ProcedureMetadata, ResolveQuery, ResolvedMeaning, Resolver};
    use dm_tree::frontend::{ColdFrontend, SourceLocation};
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/proc/read()\n    return \"hello\"\n".into())
        }
    }
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Unsupported(query)
        }
    }
    struct Policy;
    impl AbiPolicy for Policy {
        fn inputs(
            &self,
            _: UnitIdentity,
            metadata: &ProcedureMetadata,
            _: &SymbolTable,
            _: &SourceLocation,
        ) -> Result<ProcedureInputs, String> {
            if !metadata.signature.parameters.is_empty() {
                return Err("unsupported parameters".into());
            }
            Ok(ProcedureInputs::default())
        }
    }
    fn frontend() -> ColdFrontend {
        dm_tree::frontend::build(Path::new("project.dme"), &Source, &BTreeMap::new(), 1).unwrap()
    }
    #[test]
    fn actual_lowered_string_body_freezes_and_links_without_legacy_ledger() {
        let frontend = frontend();
        let lowered = lower_frontend(&frontend, &Host, &Policy, LoweringConfig::default());
        assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
        let batch = freeze_and_link_tables(
            lowered,
            frontend.snapshot.tree.symbols(),
            &ReferenceBindings::default(),
            LinkInventory::default(),
        )
        .unwrap();
        assert_eq!(batch.units.len(), 1);
        assert!(batch
            .tables
            .index(Key::String(SymbolId::of("hello")))
            .is_some());
        let original = batch.units[0].frozen.code().words().to_vec();
        let first = batch.link_unit(0, &SourceBindings::default()).unwrap();
        let second = batch.link_unit(0, &SourceBindings::default()).unwrap();
        assert_eq!(first, second);
        assert_eq!(batch.units[0].frozen.code().words(), original);
    }
    #[test]
    fn captured_binding_conflict_fails_before_table_assignment() {
        let frontend = frontend();
        let lowered = lower_frontend(&frontend, &Host, &Policy, LoweringConfig::default());
        let mut bindings = ReferenceBindings::default();
        bindings.references.insert(
            Symbol::new(Table::String, "hello"),
            SymRef::String(SymbolId::of("wrong")),
        );
        assert!(matches!(
            freeze_and_link_tables(
                lowered,
                frontend.snapshot.tree.symbols(),
                &bindings,
                LinkInventory::default()
            ),
            Err(IntegrationError::Freeze { .. })
        ));
    }
}
