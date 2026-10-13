//! Body-edit patch support (see `crate::body_patch`): the link footprint of one
//! procedure contribution, and linking its code alone against retained tables.
//!
//! A procedure feeds the linker and composer more than its own code words: its
//! inventory entry key, slot aliases and owned strings, owner/name spellings,
//! debug path strings, frame (local and argument records), ABI (procedure
//! record, argument lists, helpers), warnings, instance aliases and bytecode
//! features (header flags). When all of these are equal for the old and new
//! contribution of the same identity, every table assignment and every other
//! output record is unchanged, and only the procedure's code list differs.
use super::*;
use xxhash_rust::xxh3::Xxh3;

/// Retained, cheap (Arc-only) copy of what a footprint needs from one
/// contribution, captured from every unit of a full build.
#[derive(Clone)]
pub(crate) struct PatchRecord {
    artifact: Arc<ReusableProcedureArtifact>,
    debug: crate::debug_sources::FrozenDebugOrigins,
    helpers: Vec<crate::debug_sources::FrozenDebugOrigins>,
    abi: Option<Arc<crate::procedure_policy::PreparedAbi>>,
}

/// Named digests, compared part by part so a fallback can say what changed.
pub(crate) type Footprint = Vec<(&'static str, u128)>;

impl Contribution {
    pub(in crate::symbolic) fn patch_record(&self) -> PatchRecord {
        PatchRecord {
            artifact: Arc::clone(&self.artifact),
            debug: self.binding.debug.clone(),
            helpers: self.binding.helpers.clone(),
            abi: self.binding.abi.clone(),
        }
    }
}

fn inventory(hash: &mut Xxh3, contribution: &dm_link::InventoryContribution) {
    hash.update(format!("{:?}", contribution.entry().key).as_bytes());
    for slot in contribution.slots() {
        hash.update(format!("{:?}/{:?}/{:?};", slot.symbol, slot.owner, slot.name).as_bytes());
    }
    for string in contribution.strings() {
        hash.update(format!("{:?}:", string.id).as_bytes());
        hash.update(&(string.bytes.len() as u64).to_le_bytes());
        hash.update(&string.bytes);
    }
}

fn debug_paths(hash: &mut Xxh3, origins: &crate::debug_sources::FrozenDebugOrigins) {
    use crate::debug_sources::OriginAccess;
    let mut seen = std::collections::HashSet::new();
    for origin in origins.iter() {
        if seen.insert(origin.semantic_path.as_ref()) {
            hash.update(&(origin.semantic_path.len() as u64).to_le_bytes());
            hash.update(origin.semantic_path.as_bytes());
        }
    }
}

fn part(name: &'static str, write: impl FnOnce(&mut Xxh3)) -> (&'static str, u128) {
    let mut hash = Xxh3::new();
    write(&mut hash);
    (name, hash.digest128())
}

impl PatchRecord {
    pub(crate) fn identity(&self) -> UnitIdentity {
        self.artifact.identity
    }
    /// Link-relevant digests. Code words, debug lines and label offsets are
    /// excluded on purpose: those only change this procedure's code list.
    pub(crate) fn footprint(&self) -> Footprint {
        let artifact = &self.artifact;
        vec![
            part("identity", |h| h.update(format!("{:?}", artifact.identity).as_bytes())),
            part("frame", |h| h.update(format!("{:?}", artifact.frame).as_bytes())),
            part("abi", |h| {
                if let Some(abi) = &artifact.abi {
                    h.update(&abi.canonical_bytes());
                }
                h.update(format!("{:?}", self.abi).as_bytes());
            }),
            part("features", |h| h.update(format!("{:?}", artifact.features).as_bytes())),
            part("warnings", |h| {
                h.update(format!("{:?}", artifact.warnings).as_bytes());
                for helper in &artifact.helpers {
                    h.update(format!("{:?}", helper.warnings).as_bytes());
                }
            }),
            part("inventory", |h| inventory(h, &artifact.inventory)),
            part("value_strings", |h| {
                for id in super::super::string_order::value_string_registrations(
                    artifact.frozen.code(),
                ) {
                    h.update(format!("{id:?};").as_bytes());
                }
            }),
            part("debug_paths", |h| {
                debug_paths(h, &self.debug);
                for helper in &self.helpers {
                    h.update(b"|");
                    debug_paths(h, helper);
                }
            }),
            part("instances", |h| {
                h.update(format!("{:?}", artifact.instances).as_bytes());
                for helper in &artifact.helpers {
                    h.update(format!("{:?}", helper.instances).as_bytes());
                }
            }),
            // Helper code is compared exactly; a changed helper is not patched.
            part("helpers", |h| {
                for helper in &artifact.helpers {
                    h.update(&helper.argument.to_le_bytes());
                    h.update(format!("{:?}", helper.local_names).as_bytes());
                    h.update(&helper.frozen.code().canonical_bytes());
                    h.update(format!("{:?}", helper.frozen.labels()).as_bytes());
                    h.update(format!("{:?}", helper.features).as_bytes());
                    inventory(h, &helper.inventory);
                }
                for origins in &self.helpers {
                    h.update(format!("{:?}", origins.to_owned_origins()).as_bytes());
                }
            }),
        ]
    }
    /// Whether any warning is attached; warning output is rendered from the
    /// full build and is not rebound by a patch.
    pub(crate) fn has_warnings(&self) -> bool {
        !self.artifact.warnings.is_empty()
            || self.artifact.helpers.iter().any(|helper| !helper.warnings.is_empty())
    }
    /// Current linked words of this procedure against retained tables, wired
    /// exactly as composition wires a unit (`BatchAccess::unit_words`).
    pub(crate) fn link_words(
        &self,
        tables: &LinkTables,
        mobs: &dm_link::MobBindings,
    ) -> Result<Arc<Vec<u32>>, IntegrationError> {
        let image = tables
            .link_from(self.artifact.frozen.code(), &self.debug)
            .map_err(IntegrationError::Link)?;
        latest_image::LatestImage::wire_image(
            &self.artifact.image_owner,
            image,
            self.artifact.frozen.code(),
            tables,
            mobs,
        )
        .map(|image| image.words)
    }
}
