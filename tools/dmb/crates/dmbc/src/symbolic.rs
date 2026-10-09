//! Real lowering→shared encoder→canonical linker bridge, with explicit externals.
use crate::lowering::{LoweredUnit, LoweringBatch, Namespace, UnitIdentity};
use dm_codegen_byond::encoder::{freeze_proc_observed, FreezeStage};
use dm_codegen_byond::FrozenProc;
use dm_ir::{SymRef, SymbolId, SymbolTable};
use dm_link::{Entry, Key, LinkInventory, LinkTables, ProcedureImage, SlotAlias, SourceBindings};
use std::sync::Arc;

/// External engine/class/proc/instance/list/resource facts must be captured by the
/// caller. No legacy ledger, dense IDs or fabricated missing payloads are used.
#[derive(Clone, Debug, Default)]
pub struct ReferenceBindings {
    pub references: std::collections::BTreeSet<SymRef>,
}
pub struct FrozenUnit {
    pub lowered: FrozenUnitMetadata,
    pub frozen: Arc<FrozenProc>,
    current_image: Option<CurrentImage>,
    image_owner: Arc<latest_image::LatestImage>,
    features: BytecodeFeatures,
}
impl FrozenUnit {
    pub(crate) fn latest_image(&self) -> &Arc<latest_image::LatestImage> {
        &self.image_owner
    }
}
/// Composition-only metadata: resolver receipts and rich instructions are released.
pub struct FrozenUnitMetadata {
    pub identity: UnitIdentity,
    pub origin: dm_tree::frontend::BodyOccurrence,
    pub abi: Option<Arc<crate::procedure_policy::PreparedAbi>>,
    pub debug_origins: crate::debug_sources::FrozenDebugOrigins,
    pub frame: FrozenFrame,
}
pub struct FrozenFrame {
    pub local_count: u32,
    pub local_names: Vec<String>,
    pub argument_names: Vec<String>,
    pub argument_type_flags: Vec<u32>,
}
impl FrozenUnitMetadata {
    fn consume(unit: LoweredUnit) -> Self {
        let procedure = unit.code.procedure;
        Self {
            identity: unit.identity,
            origin: unit.origin,
            abi: unit.abi,
            debug_origins: unit.debug_origins.into(),
            frame: FrozenFrame {
                local_count: procedure.local_count,
                local_names: procedure.local_names,
                argument_names: procedure.argument_names,
                argument_type_flags: procedure.argument_type_flags,
            },
        }
    }
}
pub struct FrozenHelper {
    pub owner: UnitIdentity,
    pub argument: u32,
    pub frozen: Arc<FrozenProc>,
    current_image: Option<CurrentImage>,
    image_owner: Arc<latest_image::LatestImage>,
    features: BytecodeFeatures,
    pub debug_origins: crate::debug_sources::FrozenDebugOrigins,
    pub local_names: Vec<String>,
}
impl FrozenHelper {
    pub(crate) fn latest_image(&self) -> &Arc<latest_image::LatestImage> {
        &self.image_owner
    }
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
    bindings: dm_link::BindingTables,
    origins: crate::debug_sources::FrozenDebugOrigins,
    image: ProcedureImage,
    features: BytecodeFeatures,
}
impl CurrentImage {
    fn issue(
        frozen: &Arc<FrozenProc>,
        origins: &crate::debug_sources::FrozenDebugOrigins,
        tables: &LinkTables,
        features: BytecodeFeatures,
        owner: &Arc<latest_image::LatestImage>,
    ) -> Result<Self, IntegrationError> {
        // A uniquely owned completion has no retained artifact consumer. Keep
        // the ordinary cold path movable rather than retaining its own image
        // and forcing a second full word allocation during output emission.
        let image = if Arc::strong_count(owner) > 1 {
            owner.link(frozen, origins, tables)?
        } else {
            tables
                .link(frozen.code(), &origins.source_bindings())
                .map_err(IntegrationError::Link)?
        };
        Ok(Self {
            frozen: Arc::clone(frozen),
            bindings: tables.binding_tables(),
            origins: origins.clone(),
            image,
            features,
        })
    }
    fn matches(
        &self,
        frozen: &Arc<FrozenProc>,
        origins: &crate::debug_sources::FrozenDebugOrigins,
        tables: &LinkTables,
    ) -> bool {
        Arc::ptr_eq(&self.frozen, frozen)
            && self.bindings.same_owner(&tables.binding_tables())
            && self.origins == *origins
    }
}
fn current_link(
    frozen: &Arc<FrozenProc>,
    origins: &crate::debug_sources::FrozenDebugOrigins,
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
fn take_current_link(
    frozen: &Arc<FrozenProc>,
    origins: &crate::debug_sources::FrozenDebugOrigins,
    tables: &LinkTables,
    certificate: &mut Option<CurrentImage>,
) -> Result<ProcedureImage, IntegrationError> {
    // Check the exact frozen/table/origin contract before moving any image data.
    // Changed public artifacts retain the borrowed API's exact re-link fallback.
    if certificate
        .as_ref()
        .is_some_and(|image| image.matches(frozen, origins, tables))
    {
        return Ok(certificate.take().expect("checked current image").image);
    }
    *certificate = None;
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
    image_owner: Arc<latest_image::LatestImage>,
    features: BytecodeFeatures,
    pub debug_origins: crate::debug_sources::FrozenDebugOrigins,
    pub local_names: Vec<String>,
}
impl FrozenInitializer {
    pub(crate) fn latest_image(&self) -> &Arc<latest_image::LatestImage> {
        &self.image_owner
    }

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
    WireDomain(dm_link::WireDomainError),
    CurrentImageWorker(String),
    InvalidInitializer(String),
    LoweringFailed(usize),
    MissingSpelling(SymbolId),
    DuplicateUnit(UnitIdentity),
    ConflictingBinding(SymRef),
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
            origins: &crate::debug_sources::FrozenDebugOrigins,
            image: &'a Option<CurrentImage>,
        ) {
            if let Some(image) = image
                .as_ref()
                .filter(|image| image.matches(frozen, origins, tables))
            {
                if let Some(index) = tables.index(key) {
                    result.insert(index, (image.image.words.as_slice(), image.features));
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

    /// Consume a linked image for output ownership transfer. Final composed
    /// instructions still require complete validation after mutable output stages.
    pub fn take_unit_image(
        &mut self,
        index: usize,
        source: &SourceBindings,
    ) -> Result<ProcedureImage, IntegrationError> {
        let unit = self
            .units
            .get_mut(index)
            .ok_or(IntegrationError::LoweringFailed(index))?;
        if source.first_line == 0 && source.files.is_empty() && source.lines.is_empty() {
            take_current_link(
                &unit.frozen,
                &unit.lowered.debug_origins,
                &self.tables,
                &mut unit.current_image,
            )
        } else {
            unit.current_image = None;
            self.tables
                .link(unit.frozen.code(), source)
                .map_err(IntegrationError::Link)
        }
    }
    pub(crate) fn take_helper_image(
        &mut self,
        index: usize,
    ) -> Result<ProcedureImage, IntegrationError> {
        let unit = self
            .helpers
            .get_mut(index)
            .ok_or(IntegrationError::LoweringFailed(index))?;
        take_current_link(
            &unit.frozen,
            &unit.debug_origins,
            &self.tables,
            &mut unit.current_image,
        )
    }
    pub(crate) fn take_initializer_image(
        &mut self,
        index: usize,
    ) -> Result<ProcedureImage, IntegrationError> {
        let unit = self
            .initializers
            .get_mut(index)
            .ok_or(IntegrationError::LoweringFailed(index))?;
        take_current_link(
            &unit.frozen,
            &unit.debug_origins,
            &self.tables,
            &mut unit.current_image,
        )
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
    inventory: LinkInventory,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
) -> Result<FrozenBatch, IntegrationError> {
    freeze_artifact_tables_with_workers(batch, symbols, external, inventory, initialization, 1)
}
/// Bounded unit/helper freezing; global inventory mutations remain source ordered.
pub fn freeze_artifact_tables_with_workers(
    batch: LoweringBatch,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    inventory: LinkInventory,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
    workers: usize,
) -> Result<FrozenBatch, IntegrationError> {
    let executor = dm_exec::BuildExecutor::new(workers)
        .map_err(|error| IntegrationError::InvalidInitializer(format!("executor: {error}")))?;
    freeze_artifact_tables_with_executor(
        batch,
        symbols,
        external,
        inventory,
        initialization,
        &executor,
    )
}

pub fn freeze_artifact_tables_with_executor(
    batch: LoweringBatch,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    mut inventory: LinkInventory,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
    executor: &dm_exec::BuildExecutor,
) -> Result<FrozenBatch, IntegrationError> {
    if !batch.diagnostics.is_empty() {
        return Err(IntegrationError::LoweringFailed(batch.diagnostics.len()));
    }
    batch
        .identity_index()
        .map_err(IntegrationError::DuplicateUnit)?;
    let mut units = Vec::with_capacity(batch.units.len());
    let mut helpers = Vec::new();
    let mut source_bindings = std::collections::BTreeSet::new();
    let mut string_inventory = StringInventory::new(&inventory);
    for entry in &inventory.entries {
        if let Key::Type(id) = entry.key {
            let path = symbols
                .text(id)
                .ok_or(IntegrationError::MissingSpelling(id))?;
            if SymbolId::of(path) != id {
                return Err(IntegrationError::MissingSpelling(id));
            }
            source_bindings.insert(SymRef::Type(id));
        }
    }
    for unit in &batch.units {
        if !unit.effective {
            continue;
        }
        for symbol in [unit.identity.owner, unit.identity.name] {
            symbols
                .text(symbol)
                .ok_or(IntegrationError::MissingSpelling(symbol))?;
        }
        let reference = unit_reference(unit.identity);
        if !source_bindings.insert(reference) {
            return Err(IntegrationError::DuplicateUnit(unit.identity));
        }
    }
    // Tiny per-procedure scopes materially perturb throughput and yield broad
    // quantization bounds. Enable them only for a separate diagnostic run.
    let freeze_detail =
        std::env::var_os("DMB_PROFILE_FREEZE_DETAIL").is_some_and(|value| value == "1");
    let freeze_profile = dm_profile::stage("linking.freeze_artifacts");
    let contributions = parallel::freeze_units_with_executor(
        batch.units,
        symbols,
        &source_bindings,
        external,
        freeze_detail,
        executor,
        |contribution| {
            contribution.replay(
                &mut inventory,
                &mut string_inventory,
                symbols,
                &mut units,
                &mut helpers,
            );
        },
    );
    contributions?;
    drop(freeze_profile);
    finish_frozen_inventory(
        FrozenInventory {
            inventory,
            string_inventory,
            units,
            helpers,
            source_bindings,
        },
        symbols,
        external,
        initialization,
        freeze_detail,
        Some(executor),
        None,
    )
}
struct FrozenInventory {
    inventory: LinkInventory,
    string_inventory: StringInventory,
    units: Vec<FrozenUnit>,
    helpers: Vec<FrozenHelper>,
    source_bindings: std::collections::BTreeSet<SymRef>,
}
fn finish_frozen_inventory(
    state: FrozenInventory,
    symbols: &SymbolTable,
    external: &ReferenceBindings,
    initialization: Vec<crate::initialization_artifact::InitializationArtifact>,
    freeze_detail: bool,
    executor: Option<&dm_exec::BuildExecutor>,
    bindings: Option<&dm_link::RetainedBindings>,
) -> Result<FrozenBatch, IntegrationError> {
    let FrozenInventory {
        mut inventory,
        mut string_inventory,
        mut units,
        mut helpers,
        source_bindings,
    } = state;
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
        let contribution = initializer_contribution::freeze_current(
            &unit,
            context,
            &source_bindings,
            external,
            freeze_detail,
        )?;
        contribution.replay(&mut inventory, &mut string_inventory);
        let frozen = Arc::clone(&contribution.frozen);
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
        let shared_code = frozen.shared_code();
        content.extend_from_slice(&(shared_code.canonical_len() as u64).to_le_bytes());
        let mut suffix = Vec::new();
        for name in &unit.code.procedure.local_names {
            suffix.extend_from_slice(&(name.len() as u64).to_le_bytes());
            suffix.extend_from_slice(name.as_bytes());
        }
        inventory.entries.push(Entry {
            key,
            content: dm_link::EntryContent::symbolic(content.into(), shared_code, suffix.into()),
        });
        initializers.push(FrozenInitializer {
            identity,
            coverage: unit.coverage,
            frozen,
            current_image: None,
            image_owner: Arc::clone(&contribution.image_owner),
            features: BytecodeFeatures::of(&unit.code.procedure.code),
            debug_origins: unit.debug_origins.into(),
            local_names: unit.code.procedure.local_names.clone(),
        });
    }

    drop(source_bindings);
    drop(string_inventory);
    let tables = {
        let _profile = dm_profile::stage("linking.table_assignment");
        match bindings {
            Some(bindings) => bindings.build(inventory),
            None => LinkTables::build(inventory),
        }
        .map_err(IntegrationError::Link)?
    };
    // Validate once and retain images certified for these exact current inputs.
    let image_profile = dm_profile::stage("linking.current_images");
    current_images::issue(
        &mut units,
        &mut helpers,
        &mut initializers,
        &tables,
        executor,
    )?;
    drop(image_profile);
    Ok(FrozenBatch {
        units,
        tables,
        helpers,
        initializers,
    })
}
fn procedure_content(
    lowered: &LoweredUnit,
    code: Arc<dm_ir::SymbolicCode>,
) -> dm_link::EntryContent {
    let mut prefix = b"dm-frozen-procedure-v2\0".to_vec();
    match &lowered.abi {
        None => prefix.push(0),
        Some(abi) => {
            prefix.push(1);
            let encoded = abi.canonical_bytes();
            prefix.extend_from_slice(&(encoded.len() as u64).to_le_bytes());
            prefix.extend_from_slice(&encoded);
        }
    }
    let metadata = lowered.metadata.canonical_bytes();
    prefix.extend_from_slice(&(code.canonical_len() as u64).to_le_bytes());
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&(metadata.len() as u64).to_le_bytes());
    bytes.extend_from_slice(&metadata);
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
    dm_link::EntryContent::symbolic(prefix.into(), code, bytes.into())
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
pub(crate) fn unit_key(identity: UnitIdentity) -> Key {
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
                    Key::String(id) => Some((id, entry.content.shared_bytes())),
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
                content: bytes.into(),
            });
        }
    }
}
fn append_debug_inventory(
    origins: &impl crate::debug_sources::OriginAccess,
    inventory: &mut LinkInventory,
    strings: &mut StringInventory,
) {
    // Lines retain separate debug origins, but identical path spellings need
    // only one inventory entry. Compare the full spelling, never just its hash.
    let mut paths = std::collections::HashSet::new();
    for origin in origins.iter() {
        if !paths.insert(origin.semantic_path.as_ref()) {
            continue;
        }
        let symbol = SymbolId::of(origin.semantic_path);
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
trait InventorySink {
    fn string(&mut self, id: SymbolId, bytes: &[u8]);
    fn slot(&mut self, alias: SlotAlias);
}
mod current_images;
mod freezing;
mod initializer_contribution;
pub(crate) mod latest_image;
mod wire_image;
pub(crate) use initializer_contribution::InitializerEncoding;
#[cfg(test)]
mod helper_reuse_tests;
pub(crate) mod origin_roster;
mod parallel;
mod prepared_contribution;
mod procedure_artifact;
pub use prepared_contribution::{
    link_prepared_artifact_tables, link_prepared_artifact_tables_on_executor,
    link_prepared_artifact_tables_on_executor_with_bindings, prepare_contribution,
    PreparedContribution, PreparedModifiedSeed, ReusableProcedureArtifact,
};

#[cfg(test)]
#[path = "symbolic_tests.rs"]
mod tests;
