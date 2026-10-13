//! Real lowering→shared encoder→canonical linker bridge, with explicit externals.
use crate::lowering::{LoweredUnit, Namespace, UnitIdentity};
use dm_codegen_byond::encoder::{freeze_proc_observed, FreezeStage};
use dm_codegen_byond::FrozenProc;
use dm_ir::{SymRef, SymbolId, SymbolTable};
use dm_link::{Entry, Key, LinkInventory, LinkTables, ProcedureImage, SlotAlias, SourceBindings};
use std::sync::Arc;
pub(crate) mod shared_procedure_code;

/// External engine/class/proc/instance/list/resource facts must be captured by the
/// caller. No legacy ledger, dense IDs or fabricated missing payloads are used.
#[derive(Clone, Debug, Default)]
pub struct ReferenceBindings {
    pub references: std::collections::BTreeSet<SymRef>,
}
pub struct FrozenUnit {
    pub lowered: FrozenUnitMetadata,
    pub frozen: Arc<FrozenProc>,
    pub(crate) metadata_recipe: Arc<crate::composition::ProcedureMetadataRecipe>,
    current_image: Option<CurrentImage>,
    image_owner: Arc<latest_image::LatestImage>,
    features: BytecodeFeatures,
}
impl FrozenUnit {
    pub(crate) fn bytecode_features(&self) -> BytecodeFeatures {
        self.features
    }
    pub(crate) fn latest_image(&self) -> &Arc<latest_image::LatestImage> {
        &self.image_owner
    }
}
/// Composition-only metadata: resolver receipts and rich instructions are released.
pub struct FrozenUnitMetadata {
    pub(crate) warnings: Arc<[dm_codegen_byond::ProcedureWarning]>,
    pub identity: UnitIdentity,
    pub origin: dm_tree::frontend::BodyOccurrence,
    pub abi: Option<Arc<crate::procedure_policy::PreparedAbi>>,
    pub debug_origins: crate::debug_sources::FrozenDebugOrigins,
    pub frame: Arc<FrozenFrame>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
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
            warnings: procedure.warnings.into(),
            frame: Arc::new(FrozenFrame {
                local_count: procedure.local_count,
                local_names: procedure.local_names,
                argument_names: procedure.argument_names,
                argument_type_flags: procedure.argument_type_flags,
            }),
        }
    }
}
pub struct FrozenHelper {
    pub(crate) warnings: Arc<[dm_codegen_byond::ProcedureWarning]>,
    pub owner: UnitIdentity,
    pub argument: u32,
    pub frozen: Arc<FrozenProc>,
    current_image: Option<CurrentImage>,
    image_owner: Arc<latest_image::LatestImage>,
    features: BytecodeFeatures,
    pub debug_origins: crate::debug_sources::FrozenDebugOrigins,
    pub local_names: Arc<Vec<String>>,
}
impl FrozenHelper {
    pub(crate) fn bytecode_features(&self) -> BytecodeFeatures {
        self.features
    }
    pub(crate) fn latest_image(&self) -> &Arc<latest_image::LatestImage> {
        &self.image_owner
    }
}
/// Feature facts from encoder-validated instruction boundaries, never operand words.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct BytecodeFeatures {
    pub external: bool,
    pub debug: bool,
    pub source_features: dm_codegen_byond::SourceFeatures,
}
impl BytecodeFeatures {
    fn from_procedure(procedure: &dm_codegen_byond::SimpleProc) -> Self {
        Self {
            source_features: procedure.source_features,
            ..Self::of(&procedure.code)
        }
    }
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
                .link_from(frozen.code(), origins)
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
        .link_from(frozen.code(), origins)
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
        .link_from(frozen.code(), origins)
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
    pub(crate) fn bytecode_features(&self) -> BytecodeFeatures {
        self.features
    }
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
    #[cfg(test)]
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
#[cfg(test)]
mod test_batch;
#[cfg(test)]
pub(crate) use test_batch::{link_test_batch, link_test_artifacts, link_test_artifacts_with_workers};
// Preserve this test-only facade for an independently edited initializer fixture.
// It delegates to the current contribution producer; no eager freezer remains.
#[cfg(test)]
pub(crate) use test_batch::link_test_artifacts_with_workers as freeze_artifact_tables_with_workers;
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
            crate::initialization_artifact::InitializationCoverage::DeclarationWrites(_)
            | crate::initialization_artifact::InitializationCoverage::DeclarationPresence(_) => {
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
            features: BytecodeFeatures::from_procedure(&unit.code.procedure),
            debug_origins: unit.debug_origins.into(),
            local_names: unit.code.procedure.local_names.clone(),
        });
    }

    drop(source_bindings);
    drop(string_inventory);
    procedure_order::complete(&mut inventory).map_err(IntegrationError::InvalidInitializer)?;
    string_order::complete(&mut inventory, &units).map_err(IntegrationError::InvalidInitializer)?;
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
    let procedure = &lowered.code.procedure;
    procedure_content_fields(
        lowered.abi.as_deref(),
        &lowered.metadata,
        procedure.local_count,
        &procedure.local_names,
        &procedure.argument_names,
        &procedure.argument_type_flags,
        &procedure.argument_value_sources,
        code,
    )
}
#[allow(clippy::too_many_arguments)]
fn procedure_content_fields(
    abi: Option<&crate::procedure_policy::PreparedAbi>,
    metadata: &dm_ir::ProcedureMetadata,
    local_count: u32,
    local_names: &[String],
    argument_names: &[String],
    argument_type_flags: &[u32],
    value_sources: &[u32],
    code: Arc<dm_ir::SymbolicCode>,
) -> dm_link::EntryContent {
    let mut prefix = b"dm-frozen-procedure-v2\0".to_vec();
    match abi {
        None => prefix.push(0),
        Some(abi) => {
            prefix.push(1);
            let encoded = abi.canonical_bytes();
            prefix.extend_from_slice(&(encoded.len() as u64).to_le_bytes());
            prefix.extend_from_slice(&encoded);
        }
    }
    let metadata = metadata.canonical_bytes();
    prefix.extend_from_slice(&(code.canonical_len() as u64).to_le_bytes());
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&(metadata.len() as u64).to_le_bytes());
    bytes.extend_from_slice(&metadata);
    bytes.extend_from_slice(&local_count.to_le_bytes());
    for names in [local_names, argument_names] {
        bytes.extend_from_slice(&(names.len() as u64).to_le_bytes());
        for name in names {
            bytes.extend_from_slice(&(name.len() as u64).to_le_bytes());
            bytes.extend_from_slice(name.as_bytes());
        }
    }
    for values in [argument_type_flags, value_sources] {
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
                .spelling_iter()
                .map(|(id, bytes)| (id, Arc::clone(bytes)))
                .collect(),
            content: inventory
                .entry_iter()
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
pub(crate) mod procedure_artifact;
mod procedure_order;
mod string_order;
pub use prepared_contribution::{
    link_prepared_artifact_tables, link_prepared_artifact_tables_on_executor,
    link_prepared_artifact_tables_on_executor_with_bindings, prepare_contribution,
    PreparedContribution, PreparedModifiedSeed, ReusableProcedureArtifact,
};
pub(crate) use prepared_contribution::PreparedPatchRecord;

#[cfg(test)]
#[path = "symbolic_tests.rs"]
mod tests;

/// Position-bearing code kept for body-edit patches (see `crate::body_patch`):
/// an initializer procedure whose debug lines must follow a line shift.
#[derive(Clone)]
pub(crate) struct PositionedCode {
    pub key: Key,
    frozen: Arc<FrozenProc>,
    origins: crate::debug_sources::FrozenDebugOrigins,
    image_owner: Arc<latest_image::LatestImage>,
}
impl PositionedCode {
    /// Relink with every debug line mapped through `shift(path, line)`.
    /// `None` when no line moves (the retained code list is still exact);
    /// otherwise the new words and this code with its shifted origins, which
    /// the next patch must start from.
    pub(crate) fn relink_shifted(
        &self,
        tables: &LinkTables,
        mobs: &dm_link::MobBindings,
        shift: &dyn Fn(&str, u32) -> u32,
    ) -> Result<Option<(Arc<Vec<u32>>, Self)>, IntegrationError> {
        let mut origins = self.origins.to_owned_origins();
        let mut moved = false;
        for origin in &mut origins.entries {
            let line = shift(&origin.semantic_path, origin.line);
            moved |= line != origin.line;
            origin.line = line;
        }
        if !moved {
            return Ok(None);
        }
        let origins: crate::debug_sources::FrozenDebugOrigins = origins.into();
        let image = tables
            .link_from(self.frozen.code(), &origins)
            .map_err(IntegrationError::Link)?;
        let words = latest_image::LatestImage::wire_image(
            &self.image_owner,
            image,
            self.frozen.code(),
            tables,
            mobs,
        )?
        .words;
        Ok(Some((
            words,
            Self {
                key: self.key,
                frozen: Arc::clone(&self.frozen),
                origins,
                image_owner: Arc::clone(&self.image_owner),
            },
        )))
    }
}
impl FrozenBatch {
    pub(crate) fn initializer_patch_code(&self) -> Vec<PositionedCode> {
        self.initializers
            .iter()
            .map(|unit| PositionedCode {
                key: Key::Initializer(unit.identity),
                frozen: Arc::clone(&unit.frozen),
                origins: unit.debug_origins.clone(),
                image_owner: Arc::clone(&unit.image_owner),
            })
            .collect()
    }
}
