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
    pub frozen: Arc<FrozenProc>,
    current_image: Option<CurrentImage>,
    features: BytecodeFeatures,
}
pub struct FrozenHelper {
    pub owner: UnitIdentity,
    pub argument: u32,
    pub frozen: Arc<FrozenProc>,
    current_image: Option<CurrentImage>,
    features: BytecodeFeatures,
    pub debug_origins: crate::debug_sources::DebugOrigins,
    pub local_names: Vec<String>,
}
/// Feature facts from encoder-validated instruction boundaries, never operand words.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct BytecodeFeatures {
    pub external: bool,
    pub debug: bool,
}
impl BytecodeFeatures {
    fn of(code: &dm_codegen_byond::SymbolicProc) -> Self {
        use byond_dmb::bytecode::opcode;
        let mut value = Self::default();
        for item in &code.items {
            if let dm_codegen_byond::Item::Instruction(instruction) = item {
                value.external |= matches!(instruction.opcode, opcode::LOAD_EXT | opcode::CALL_EXT);
                value.debug |= matches!(instruction.opcode, opcode::DBG_FILE | opcode::DBG_LINE);
            }
        }
        value
    }
}
/// Request-local certificate. Neither dense words nor table bindings enter memo storage.
struct CurrentImage {
    frozen: Arc<FrozenProc>,
    tables: LinkTables,
    paths: Vec<String>,
    origins: Vec<(usize, u32)>,
    image: ProcedureImage,
    features: BytecodeFeatures,
}
impl CurrentImage {
    fn issue(
        frozen: &Arc<FrozenProc>,
        origins: &crate::debug_sources::DebugOrigins,
        tables: &LinkTables,
        features: BytecodeFeatures,
    ) -> Result<Self, IntegrationError> {
        let image = {
            let source = origins.source_bindings();
            tables
                .link(frozen.code(), &source)
                .map_err(IntegrationError::Link)?
        };
        let mut paths = Vec::new();
        let mut indexes = std::collections::HashMap::new();
        let roster = origins
            .entries
            .iter()
            .map(|origin| {
                let index = *indexes
                    .entry(origin.semantic_path.as_str())
                    .or_insert_with(|| {
                        let index = paths.len();
                        paths.push(origin.semantic_path.clone());
                        index
                    });
                (index, origin.line)
            })
            .collect();
        Ok(Self {
            frozen: Arc::clone(frozen),
            tables: tables.clone(),
            paths,
            origins: roster,
            image,
            features,
        })
    }
    fn matches(
        &self,
        frozen: &Arc<FrozenProc>,
        origins: &crate::debug_sources::DebugOrigins,
        tables: &LinkTables,
    ) -> bool {
        Arc::ptr_eq(&self.frozen, frozen)
            && std::ptr::eq(self.tables.assignments(), tables.assignments())
            && self.origins.len() == origins.entries.len()
            && self
                .origins
                .iter()
                .zip(&origins.entries)
                .all(|(&(path, line), current)| {
                    line == current.line && self.paths[path] == current.semantic_path
                })
    }
}
fn current_link(
    frozen: &Arc<FrozenProc>,
    origins: &crate::debug_sources::DebugOrigins,
    tables: &LinkTables,
    certificate: Option<&CurrentImage>,
) -> Result<ProcedureImage, IntegrationError> {
    if let Some(certificate) = certificate.filter(|value| value.matches(frozen, origins, tables)) {
        return Ok(certificate.image.clone());
    }
    tables
        .link(frozen.code(), &origins.source_bindings())
        .map_err(IntegrationError::Link)
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
    pub frozen: Arc<FrozenProc>,
    current_image: Option<CurrentImage>,
    features: BytecodeFeatures,
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
    /// Borrow current certified words once. Callers must compare the actual
    /// composed words before using the associated features; public artifacts
    /// may have changed since freeze and then are deliberately omitted.
    pub(crate) fn feature_images(
        &self,
    ) -> std::collections::HashMap<u32, (&[u32], BytecodeFeatures)> {
        let mut result = std::collections::HashMap::with_capacity(
            self.units.len() + self.helpers.len() + self.initializers.len(),
        );
        fn add<'a>(
            result: &mut std::collections::HashMap<u32, (&'a [u32], BytecodeFeatures)>,
            tables: &LinkTables,
            key: Key,
            frozen: &Arc<FrozenProc>,
            origins: &crate::debug_sources::DebugOrigins,
            image: &'a Option<CurrentImage>,
        ) {
            if let Some(image) = image
                .as_ref()
                .filter(|image| image.matches(frozen, origins, tables))
            {
                if let Some(index) = tables.index(key) {
                    result.insert(index, (image.image.words.as_ref(), image.features));
                }
            }
        }
        for unit in &self.units {
            add(
                &mut result,
                &self.tables,
                unit_key(unit.lowered.identity),
                &unit.frozen,
                &unit.lowered.debug_origins,
                &unit.current_image,
            );
        }
        for helper in &self.helpers {
            add(
                &mut result,
                &self.tables,
                helper_key(helper.owner, helper.argument),
                &helper.frozen,
                &helper.debug_origins,
                &helper.current_image,
            );
        }
        for unit in &self.initializers {
            add(
                &mut result,
                &self.tables,
                dm_link::Key::Initializer(unit.identity),
                &unit.frozen,
                &unit.debug_origins,
                &unit.current_image,
            );
        }
        result
    }

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
        if source.first_line == 0 && source.files.is_empty() && source.lines.is_empty() {
            current_link(
                &unit.frozen,
                &unit.lowered.debug_origins,
                &self.tables,
                unit.current_image.as_ref(),
            )
        } else {
            self.tables
                .link(unit.frozen.code(), source)
                .map_err(IntegrationError::Link)
        }
    }
    pub(crate) fn link_helper(
        &self,
        helper: &FrozenHelper,
    ) -> Result<ProcedureImage, IntegrationError> {
        current_link(
            &helper.frozen,
            &helper.debug_origins,
            &self.tables,
            helper.current_image.as_ref(),
        )
    }
    pub(crate) fn link_initializer(
        &self,
        unit: &FrozenInitializer,
    ) -> Result<ProcedureImage, IntegrationError> {
        current_link(
            &unit.frozen,
            &unit.debug_origins,
            &self.tables,
            unit.current_image.as_ref(),
        )
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
    let mut string_inventory = StringInventory::new(&inventory);
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
    let freeze_profile = dm_profile::stage("linking.freeze_artifacts");
    for lowered in batch.units {
        let frozen = freeze_artifact(
            &lowered.code,
            lowered.identity,
            &source_bindings,
            external,
            &mut inventory,
            &mut string_inventory,
        )?;
        for id in [lowered.identity.owner, lowered.identity.name] {
            string_inventory.append_spelling(
                &mut inventory,
                id,
                symbols
                    .text(id)
                    .ok_or(IntegrationError::MissingSpelling(id))?
                    .as_bytes(),
            );
        }
        append_debug_inventory(
            &lowered.debug_origins,
            &mut inventory,
            &mut string_inventory,
        );
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
                &mut string_inventory,
            )?;
            append_debug_inventory(&helper.debug_origins, &mut inventory, &mut string_inventory);
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
                frozen: Arc::new(frozen_helper),
                current_image: None,
                features: BytecodeFeatures::of(&helper.code.procedure.code),
                debug_origins: helper.debug_origins.clone(),
                local_names: helper.code.procedure.local_names.clone(),
            });
        }
        units.push(FrozenUnit {
            features: BytecodeFeatures::of(&lowered.code.procedure.code),
            lowered,
            frozen: Arc::new(frozen),
            current_image: None,
        });
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
            string_inventory.append_spelling(
                &mut inventory,
                owner,
                symbols
                    .text(owner)
                    .ok_or(IntegrationError::MissingSpelling(owner))?
                    .as_bytes(),
            );
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
            &mut string_inventory,
        )?;
        append_debug_inventory(&unit.debug_origins, &mut inventory, &mut string_inventory);
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
            crate::initialization_artifact::InitializationCoverage::ModifiedAssignments {
                count,
                canonical_body,
            } => {
                content.push(2);
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
            frozen: Arc::new(frozen),
            current_image: None,
            features: BytecodeFeatures::of(&unit.code.procedure.code),
            debug_origins: unit.debug_origins,
            local_names: unit.code.procedure.local_names.clone(),
        });
    }
    drop(freeze_profile);
    let tables = {
        let _profile = dm_profile::stage("linking.table_assignment");
        LinkTables::build(inventory).map_err(IntegrationError::Link)?
    };
    // Validate once and retain images certified for these exact current inputs.
    let image_profile = dm_profile::stage("linking.current_images");
    for unit in &mut units {
        unit.current_image = Some(CurrentImage::issue(
            &unit.frozen,
            &unit.lowered.debug_origins,
            &tables,
            unit.features,
        )?);
    }
    for helper in &mut helpers {
        helper.current_image = Some(CurrentImage::issue(
            &helper.frozen,
            &helper.debug_origins,
            &tables,
            helper.features,
        )?);
    }
    for unit in &mut initializers {
        unit.current_image = Some(CurrentImage::issue(
            &unit.frozen,
            &unit.debug_origins,
            &tables,
            unit.features,
        )?);
    }
    drop(image_profile);
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

/// Request-local exact byte interning. Conflicting hash identities are retained
/// for the linker's existing collision diagnostics, never silently coalesced.
struct StringInventory {
    spellings: std::collections::HashMap<SymbolId, Arc<[u8]>>,
    content: std::collections::HashMap<SymbolId, Arc<[u8]>>,
}
impl StringInventory {
    fn new(inventory: &LinkInventory) -> Self {
        Self {
            spellings: inventory
                .spellings
                .iter()
                .map(|(id, bytes)| (*id, Arc::clone(bytes)))
                .collect(),
            content: inventory
                .entries
                .iter()
                .filter_map(|entry| match entry.key {
                    Key::String(id) => Some((id, Arc::clone(&entry.content))),
                    _ => None,
                })
                .collect(),
        }
    }
    fn append_spelling(&mut self, inventory: &mut LinkInventory, id: SymbolId, bytes: &[u8]) {
        if self
            .spellings
            .get(&id)
            .is_some_and(|old| old.as_ref() == bytes)
        {
            return;
        }
        let bytes: Arc<[u8]> = Arc::from(bytes);
        self.spellings
            .entry(id)
            .or_insert_with(|| Arc::clone(&bytes));
        inventory.spellings.push((id, bytes));
    }
    fn append(&mut self, inventory: &mut LinkInventory, id: SymbolId, bytes: &[u8]) {
        let spelling_needed = self
            .spellings
            .get(&id)
            .is_none_or(|old| old.as_ref() != bytes);
        let content_needed = self
            .content
            .get(&id)
            .is_none_or(|old| old.as_ref() != bytes);
        if !spelling_needed && !content_needed {
            return;
        }
        let bytes: Arc<[u8]> = Arc::from(bytes);
        if spelling_needed {
            self.spellings
                .entry(id)
                .or_insert_with(|| Arc::clone(&bytes));
            inventory.spellings.push((id, Arc::clone(&bytes)));
        }
        if content_needed {
            self.content.entry(id).or_insert_with(|| Arc::clone(&bytes));
            inventory.entries.push(Entry {
                key: Key::String(id),
                content: bytes,
            });
        }
    }
}
fn append_debug_inventory(
    origins: &crate::debug_sources::DebugOrigins,
    inventory: &mut LinkInventory,
    strings: &mut StringInventory,
) {
    // Lines retain separate debug origins, but identical path spellings need
    // only one inventory entry. Compare the full spelling, never just its hash.
    let mut paths = std::collections::HashSet::new();
    for origin in &origins.entries {
        if !paths.insert(origin.semantic_path.as_str()) {
            continue;
        }
        let symbol = SymbolId::of(&origin.semantic_path);
        strings.append(inventory, symbol, origin.semantic_path.as_bytes());
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
    strings: &mut StringInventory,
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
        strings.append(inventory, id, bytes);
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
        inventory.slots.push(SlotAlias {
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
#[path = "symbolic_tests.rs"]
mod tests;
