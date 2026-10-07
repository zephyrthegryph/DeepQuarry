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
pub struct FrozenHelper {
    pub owner: UnitIdentity,
    pub argument: u32,
    pub frozen: FrozenProc,
    pub debug_origins: crate::debug_sources::DebugOrigins,
    pub local_names: Vec<String>,
}
pub struct FrozenBatch {
    pub units: Vec<FrozenUnit>,
    pub tables: LinkTables,
    pub helpers: Vec<FrozenHelper>,
    pub initializers: Vec<FrozenInitializer>,
}
pub struct FrozenInitializer {
    pub identity: dm_link::InitializerIdentity,
    pub coverage: crate::initialization_artifact::InitializationCoverage,
    pub frozen: FrozenProc,
    pub debug_origins: crate::debug_sources::DebugOrigins,
    pub local_names: Vec<String>,
}
impl FrozenInitializer {
    pub fn declaration_writes(&self) -> &[usize] {
        match &self.coverage {
            crate::initialization_artifact::InitializationCoverage::DeclarationWrites(writes) => {
                writes
            }
            _ => &[],
        }
    }
}
#[derive(Debug)]
pub enum IntegrationError {
    InvalidInitializer(String),
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
    inventory: LinkInventory,
) -> Result<FrozenBatch, IntegrationError> {
    freeze_program_tables(batch, symbols, external, inventory, Vec::new())
}
/// Ordinary procedures, helper expressions and initializers use the same
/// binder and encoder before one immutable table assignment is published.
pub fn freeze_program_tables(
    batch: LoweringBatch,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    inventory: LinkInventory,
    initialization: Vec<crate::initializer_lowering::LoweredInitializerUnit>,
) -> Result<FrozenBatch, IntegrationError> {
    freeze_artifact_tables(
        batch,
        symbols,
        external,
        inventory,
        initialization.into_iter().map(Into::into).collect(),
    )
}
pub fn freeze_artifact_tables(
    batch: LoweringBatch,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    mut inventory: LinkInventory,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
) -> Result<FrozenBatch, IntegrationError> {
    if !batch.diagnostics.is_empty() {
        return Err(IntegrationError::LoweringFailed(batch.diagnostics.len()));
    }
    batch
        .identity_index()
        .map_err(IntegrationError::DuplicateUnit)?;
    let mut units = Vec::with_capacity(batch.units.len());
    let mut helpers = Vec::new();
    let mut source_bindings = BTreeMap::new();
    for entry in &inventory.entries {
        if let Key::Type(id) = entry.key {
            let path = symbols
                .text(id)
                .ok_or(IntegrationError::MissingSpelling(id))?;
            if SymbolId::of(path) != id {
                return Err(IntegrationError::MissingSpelling(id));
            }
            insert(
                &mut source_bindings,
                Symbol::new(Table::Class, path),
                SymRef::Type(id),
            )?;
        }
    }
    for unit in &batch.units {
        if !unit.effective {
            continue;
        }
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
        if source_bindings
            .insert(Symbol::new(Table::Proc, path), reference)
            .is_some()
        {
            return Err(IntegrationError::DuplicateUnit(unit.identity));
        }
    }
    for lowered in batch.units {
        let frozen = freeze_artifact(
            &lowered.code,
            lowered.identity,
            &source_bindings,
            external,
            &mut inventory,
        )?;
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
        append_debug_inventory(&lowered.debug_origins, &mut inventory);
        // Exact frozen code content is known. Remaining proc metadata belongs
        // to explicit emitter policy, separately retained in LoweredUnit.
        inventory.entries.push(Entry {
            key: unit_key(lowered.identity),
            content: procedure_content(&lowered, &frozen.code().canonical_bytes()),
        });
        for helper in &lowered.source_helpers {
            if helper.owner != lowered.identity || !helper.code.procedure.argument_names.is_empty()
            {
                return Err(IntegrationError::Freeze {
                    unit: lowered.identity,
                    message: "invalid companion owner/formal frame".into(),
                });
            }
            let frozen_helper = freeze_artifact(
                &helper.code,
                helper.owner,
                &source_bindings,
                external,
                &mut inventory,
            )?;
            append_debug_inventory(&helper.debug_origins, &mut inventory);
            let key = helper_key(helper.owner, helper.argument);
            let mut content = b"dm-argument-source-v1\0".to_vec();
            let code = frozen_helper.code().canonical_bytes();
            content.extend_from_slice(&(code.len() as u64).to_le_bytes());
            content.extend_from_slice(&code);
            for name in &helper.code.procedure.local_names {
                content.extend_from_slice(&(name.len() as u64).to_le_bytes());
                content.extend_from_slice(name.as_bytes());
            }
            inventory.entries.push(Entry {
                key,
                content: content.into(),
            });
            helpers.push(FrozenHelper {
                owner: helper.owner,
                argument: helper.argument,
                frozen: frozen_helper,
                debug_origins: helper.debug_origins.clone(),
                local_names: helper.code.procedure.local_names.clone(),
            });
        }
        units.push(FrozenUnit { lowered, frozen });
    }
    let mut initializers = Vec::with_capacity(initialization.len());
    let mut initialization_keys = std::collections::BTreeSet::new();
    for unit in initialization {
        unit.validate()
            .map_err(IntegrationError::InvalidInitializer)?;
        let identity = unit.identity;
        let key = Key::Initializer(identity);
        if !initialization_keys.insert(key) {
            return Err(IntegrationError::InvalidInitializer(
                "duplicate initialization scope".into(),
            ));
        }
        if let dm_link::InitializerIdentity::Class(owner) = identity {
            inventory.spellings.push((
                owner,
                Arc::from(
                    symbols
                        .text(owner)
                        .ok_or(IntegrationError::MissingSpelling(owner))?
                        .as_bytes(),
                ),
            ));
        }
        // This context labels diagnostics only; no callable identity is issued.
        let context = UnitIdentity {
            owner: match identity {
                dm_link::InitializerIdentity::Class(owner) => owner,
                _ => SymbolId::of("/"),
            },
            name: SymbolId::of("<initializer>"),
            namespace: Namespace::Proc,
            occurrence: 0,
        };
        let frozen = freeze_artifact(
            &unit.code,
            context,
            &source_bindings,
            external,
            &mut inventory,
        )?;
        append_debug_inventory(&unit.debug_origins, &mut inventory);
        let mut content = b"dm-initializer-code-v1\0".to_vec();
        match &unit.coverage {
            crate::initialization_artifact::InitializationCoverage::DeclarationWrites(_) => {
                content.push(0)
            }
            crate::initialization_artifact::InitializationCoverage::MapAssignments {
                count,
                canonical_body,
            } => {
                content.push(1);
                content.extend_from_slice(&count.to_le_bytes());
                content.extend_from_slice(&(canonical_body.len() as u64).to_le_bytes());
                content.extend_from_slice(canonical_body);
            }
        }
        let code = frozen.code().canonical_bytes();
        content.extend_from_slice(&(code.len() as u64).to_le_bytes());
        content.extend_from_slice(&code);
        for name in &unit.code.procedure.local_names {
            content.extend_from_slice(&(name.len() as u64).to_le_bytes());
            content.extend_from_slice(name.as_bytes());
        }
        inventory.entries.push(Entry {
            key,
            content: content.into(),
        });
        initializers.push(FrozenInitializer {
            identity,
            coverage: unit.coverage,
            frozen,
            debug_origins: unit.debug_origins,
            local_names: unit.code.procedure.local_names.clone(),
        });
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
    for helper in &helpers {
        tables
            .link(
                helper.frozen.code(),
                &helper.debug_origins.source_bindings(),
            )
            .map_err(IntegrationError::Link)?;
    }
    for unit in &initializers {
        tables
            .link(unit.frozen.code(), &unit.debug_origins.source_bindings())
            .map_err(IntegrationError::Link)?;
    }
    Ok(FrozenBatch {
        units,
        tables,
        helpers,
        initializers,
    })
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

fn append_debug_inventory(
    origins: &crate::debug_sources::DebugOrigins,
    inventory: &mut LinkInventory,
) {
    for origin in &origins.entries {
        let bytes: Arc<[u8]> = Arc::from(origin.semantic_path.as_bytes());
        let symbol = SymbolId::of(&origin.semantic_path);
        inventory.spellings.push((symbol, bytes.clone()));
        inventory.entries.push(Entry {
            key: Key::String(symbol),
            content: bytes,
        });
    }
}
pub fn helper_key(owner: UnitIdentity, argument: u32) -> Key {
    Key::ArgumentSource {
        owner: owner.owner,
        name: owner.name,
        verb: owner.namespace == Namespace::Verb,
        occurrence: owner.occurrence,
        argument,
    }
}
fn freeze_artifact(
    code: &dm_codegen_byond::lower_resolver::ResolverProc,
    identity: UnitIdentity,
    source_bindings: &BTreeMap<Symbol, SymRef>,
    external: &ReferenceBindings,
    inventory: &mut LinkInventory,
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
        inventory.spellings.push((id, Arc::from(bytes)));
        inventory.entries.push(Entry {
            key: Key::String(id),
            content: Arc::from(bytes),
        });
    }
    for (symbol, slot) in &code.slots {
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
    let frozen = freeze_proc(&code.procedure.code, |symbol| {
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
    })
    .map_err(|error| IntegrationError::Freeze {
        unit: identity,
        message: error.to_string(),
    })?;
    Ok(frozen)
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
    fn implicit_before_formal_binds_the_certified_effective_body() {
        struct Reopened;
        impl dm_preprocess::SourceProvider for Reopened {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok("/datum/x/read()\n    return 2\n/datum/x/proc/read()\n    return 1\n/proc/caller()\n    return /datum/x/proc/read\n".into())
            }
        }
        let frontend =
            dm_tree::frontend::build(Path::new("project.dme"), &Reopened, &Default::default(), 1)
                .unwrap();
        let batch = lower_frontend(
            &frontend,
            frontend.snapshot.tree.as_ref(),
            &Policy,
            LoweringConfig::default(),
        );
        assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
        let read = SymbolId::of("read");
        let effective = batch
            .units
            .iter()
            .find(|unit| unit.identity.name == read && unit.effective)
            .unwrap()
            .identity;
        // Identities count semantic override depth: formal base is 0 even when
        // encountered later; the earlier authored implicit override is 1.
        assert_eq!(effective.occurrence, 1);
        let selected = batch
            .units
            .iter()
            .find(|unit| unit.identity == effective)
            .unwrap();
        let executable = selected
            .code
            .procedure
            .code
            .items
            .iter()
            .filter_map(|item| match item {
                dm_codegen_byond::Item::Instruction(instruction)
                    if !matches!(instruction.opcode, 0x84 | 0x85) =>
                {
                    Some(instruction)
                }
                _ => None,
            })
            .collect::<Vec<_>>();
        // Small nonnegative integers use PUSH_INT rather than compound V.
        assert_eq!(
            executable[0].opcode,
            byond_dmb::bytecode::opcode::PUSH_INT,
            "{:?}",
            selected.code.procedure.code
        );
        assert_eq!(
            executable[0].operands,
            vec![dm_codegen_byond::Word::Immediate(2)]
        );
        assert_eq!(executable[1].opcode, byond_dmb::bytecode::opcode::RET);
        let frozen = freeze_and_link_tables(
            batch,
            frontend.snapshot.tree.symbols(),
            &ReferenceBindings::default(),
            LinkInventory::default(),
        )
        .unwrap();
        let caller = frozen
            .units
            .iter()
            .find(|unit| unit.lowered.identity.name == SymbolId::of("caller"))
            .unwrap();
        assert!(caller
            .frozen
            .code()
            .relocations()
            .iter()
            .any(|site| site.reference == unit_reference(effective)));
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
