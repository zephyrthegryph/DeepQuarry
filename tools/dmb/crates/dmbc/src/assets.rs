//! Production asset capture orchestration over authored sources and map sidecars.
//! Capture is explicit I/O; lowering subsequently uses only the frozen resolver.
use dm_resources::capture::{
    CaptureConfig, CaptureError, CaptureProvider, CapturedResources, LiteralRequest,
};
use dm_resources::ResourceRequest;
use dm_syntax::Span;
use dm_tree::frontend::ColdFrontend;
use dm_tree::maps::MapPlan;
use dm_tree::non_text::CapturedSkin;
use std::path::{Path, PathBuf};
use std::sync::Arc;

#[derive(Clone, Debug)]
pub struct AssetOrigin {
    pub source: Arc<PathBuf>,
    pub include_occurrence: u32,
    pub span: Span,
}
#[derive(Clone, Debug)]
pub struct ExtraAssets {
    pub literals: Vec<LiteralRequest>,
    pub origins: Vec<AssetOrigin>,
    pub skins: Vec<ResourceRequest>,
    pub encoded_skins: Vec<dm_resources::capture::EncodedResourceInput>,
}
/// Resource literals are discovered in exact assignment slices, including
/// interpolation expressions. Plain quoted grid/string contents are not assets.
pub fn discover_extra(
    project_root: &Path,
    maps: &[MapPlan],
    skins: &[CapturedSkin],
) -> Result<ExtraAssets, CaptureError> {
    let mut result = ExtraAssets {
        literals: Vec::new(),
        origins: Vec::new(),
        skins: Vec::new(),
        encoded_skins: Vec::new(),
    };
    for map in maps {
        for template in map.template_origins.iter() {
            for atom in template.atoms.iter() {
                for assignment in atom.assignments.iter() {
                    let text = map
                        .captured
                        .source
                        .get(assignment.value_span.range())
                        .ok_or_else(|| {
                            CaptureError::Invalid(
                                "map resource origin exceeds captured source".into(),
                            )
                        })?;
                    for mut literal in dm_resources::capture::discover_literals(text)? {
                        literal.span.start += assignment.value_span.start;
                        literal.span.end += assignment.value_span.start;
                        result.origins.push(AssetOrigin {
                            source: map.captured.path.clone(),
                            include_occurrence: map.captured.include_occurrence,
                            span: literal.span,
                        });
                        result.literals.push(literal);
                    }
                }
            }
        }
    }
    for skin in skins {
        let relative = skin.path.strip_prefix(project_root).map_err(|_| {
            CaptureError::Invalid(
                "skin include outside project requires an explicit archive alias".into(),
            )
        })?;
        let archive_name = relative
            .to_str()
            .ok_or_else(|| CaptureError::Invalid("skin archive path is not UTF-8".into()))?
            .replace('\\', "/");
        let request = ResourceRequest {
            archive_name,
            disk_path: skin.path.as_ref().clone(),
        };
        let encoded = dm_resources::encoding::encode_raw(
            request.clone(),
            skin.source.as_bytes(),
            &dm_resources::encoding::byond516_raw_policy(),
        )
        .map_err(|source| CaptureError::Io {
            path: request.disk_path.clone(),
            source,
        })?;
        result.encoded_skins.push(encoded);
        result.skins.push(request);
        for literal in dm_resources::capture::discover_literals(&skin.source)? {
            result.origins.push(AssetOrigin {
                source: skin.path.clone(),
                include_occurrence: skin.include_occurrence,
                span: literal.span,
            });
            result.literals.push(literal);
        }
    }
    Ok(result)
}
/// Extra aliases follow source literals through the same exact project-direct /
/// reverse FILE_DIR search. A missing asset remains a negative captured query;
/// unsupported payload formats remain explicit, never guessed raw bytes.
pub fn capture<P: CaptureProvider>(
    frontend: &ColdFrontend,
    extra: &ExtraAssets,
    provider: &P,
) -> Result<CapturedResources, CaptureError> {
    let policy = dm_resources::encoding::byond516_raw_policy();
    dm_resources::capture::capture_expanded_with_literals(
        &frontend.plan,
        &frontend.expanded,
        CaptureConfig {
            policy: &policy,
            encoded: &extra.encoded_skins,
            additional: &extra.skins,
        },
        &extra.literals,
        provider,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn map_resources_have_exact_assignment_sources_and_skin_encoding_is_bound() {
        let map=dm_tree::maps::plan(dm_tree::maps::CapturedMap {path:Arc::new(PathBuf::from("game/maps/probe.dmm")),include_occurrence:3,source:Arc::from("\"a\"=(/obj{icon='icons/a.dmi';message=\"ordinary 'ignored.png'\";sound='sound/a.ogg'})\n(1,1,1)={\"a\"}")}).unwrap();
        let skin = CapturedSkin {
            path: Arc::new(PathBuf::from("game/interface/main.dmf")),
            include_occurrence: 4,
            source: Arc::from("window \"main\"\n icon = 'icons/ui.png'\n"),
            source_identity: 0,
        };
        let extra = discover_extra(
            Path::new("game"),
            std::slice::from_ref(&map),
            std::slice::from_ref(&skin),
        )
        .unwrap();
        assert_eq!(
            extra
                .literals
                .iter()
                .map(|literal| literal.path.as_str())
                .collect::<Vec<_>>(),
            ["icons/a.dmi", "sound/a.ogg", "icons/ui.png"]
        );
        assert_eq!(
            &map.captured.source[extra.origins[0].span.range()],
            "'icons/a.dmi'"
        );
        assert_eq!(extra.skins[0].archive_name, "interface/main.dmf");
        assert_eq!(
            extra.encoded_skins[0].input.named.asset_bytes().unwrap(),
            skin.source.as_bytes()
        );
    }
}

/// Immutable resource output projection from a caller-certified archive order.
/// The order determines first-kind behavior for equal runtime content IDs.
pub struct ResourceProjection {
    pub rsc: Vec<u8>,
    pub records: Vec<(u128, byond_dmb::dmb::ResourceRef)>,
    pub inventory: Vec<dm_link::Entry>,
}
#[derive(Debug)]
pub enum ResourceOutputError {
    InvalidOrder,
    InvalidPayload(std::io::Error),
    ContentCollision,
    RuntimeIdCollision,
    InvalidBinding(u128),
    NonContiguous,
}
pub fn project_resources(
    resources: &dm_resources::ResourceSet,
    archive_order: &[usize],
) -> Result<ResourceProjection, ResourceOutputError> {
    use std::collections::{BTreeMap, BTreeSet};
    if archive_order.len() != resources.inputs.len() {
        return Err(ResourceOutputError::InvalidOrder);
    }
    let mut seen = BTreeSet::new();
    let mut named = Vec::with_capacity(archive_order.len());
    let mut records = Vec::new();
    let mut inventory = Vec::new();
    let mut runtime_ids = BTreeMap::<u32, (u128, &[u8])>::new();
    let mut hashes = BTreeMap::<u128, &[u8]>::new();
    for ordinal in archive_order {
        if !seen.insert(*ordinal) {
            return Err(ResourceOutputError::InvalidOrder);
        }
        let input = resources
            .inputs
            .get(*ordinal)
            .ok_or(ResourceOutputError::InvalidOrder)?;
        let payload = input
            .named
            .asset_bytes()
            .map_err(ResourceOutputError::InvalidPayload)?;
        if input.named.name != input.archive_name.as_bytes()
            || input
                .named
                .content_id()
                .map_err(ResourceOutputError::InvalidPayload)?
                != input.named.id
        {
            return Err(ResourceOutputError::InvalidPayload(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "resource alias/runtime content identity mismatch",
            )));
        }
        named.push(&input.named);
        let content = xxhash_rust::xxh3::xxh3_128(payload);
        if hashes
            .insert(content, payload)
            .is_some_and(|previous| previous != payload)
        {
            return Err(ResourceOutputError::ContentCollision);
        }
        if let Some((previous_content, previous)) = runtime_ids.get(&input.named.id) {
            if *previous_content != content || *previous != payload {
                return Err(ResourceOutputError::RuntimeIdCollision);
            }
            continue;
        }
        runtime_ids.insert(input.named.id, (content, payload));
        records.push((
            content,
            byond_dmb::dmb::ResourceRef {
                id: input.named.id,
                kind: input.named.kind,
            },
        ));
        inventory.push(dm_link::Entry {
            key: dm_link::Key::Resource(content),
            content: Arc::from(payload),
        });
    }
    let rsc =
        byond_dmb::rsc::named_archive_bytes(&named).map_err(ResourceOutputError::InvalidPayload)?;
    Ok(ResourceProjection {
        rsc,
        records,
        inventory,
    })
}
/// Record composition only: no filesystem, alias resolution or mutable semantic
/// queries. Pinned resources require their own exact retained-payload contract.
pub fn attach_resources(
    dmb: &mut byond_dmb::dmb::Dmb,
    projection: &ResourceProjection,
    tables: &dm_link::LinkTables,
) -> Result<(), ResourceOutputError> {
    if !dmb.resources.is_empty() {
        return Err(ResourceOutputError::NonContiguous);
    }
    if projection.inventory.len() != projection.records.len() {
        return Err(ResourceOutputError::InvalidOrder);
    }
    let mut ordered = Vec::with_capacity(projection.records.len());
    for ((content, record), exact) in projection.records.iter().zip(&projection.inventory) {
        let index = tables
            .index(dm_link::Key::Resource(*content))
            .ok_or(ResourceOutputError::InvalidBinding(*content))?;
        if exact.key != dm_link::Key::Resource(*content) {
            return Err(ResourceOutputError::InvalidBinding(*content));
        }
        if tables.content(exact.key) != Some(exact.content.as_ref()) {
            return Err(ResourceOutputError::InvalidBinding(*content));
        }
        ordered.push((index, record.clone()));
    }
    ordered.sort_by_key(|(index, _)| *index);
    for (expected, (index, _)) in ordered.iter().enumerate() {
        if usize::try_from(*index).ok() != Some(expected) {
            return Err(ResourceOutputError::NonContiguous);
        }
    }
    dmb.resources = ordered.into_iter().map(|(_, record)| record).collect();
    if dmb.resources.len() > usize::from(u16::MAX) {
        dmb.header.flags |= 0x4000_0000;
    }
    Ok(())
}

/// Automatic order is safe only when no two distinct aliases share a runtime
/// content ID. General alias collisions require the grammar phase contract.
pub fn unambiguous_archive_order(
    resources: &dm_resources::ResourceSet,
) -> Result<Vec<usize>, ResourceOutputError> {
    let mut ids = std::collections::BTreeSet::new();
    for input in &resources.inputs {
        if !ids.insert(input.named.id) {
            return Err(ResourceOutputError::InvalidOrder);
        }
    }
    Ok((0..resources.inputs.len()).collect())
}
impl ResourceProjection {
    /// Merge exact payload entries before the single linker table assignment.
    /// Alias names map to captured content through the resource resolver, never
    /// through this output inventory or a rewritten archive.
    pub fn extend_inventory(&self, inventory: &mut dm_link::LinkInventory) {
        inventory.entries.extend(self.inventory.iter().cloned());
    }
}
#[cfg(test)]
mod resource_output_tests {
    use super::*;
    fn resources() -> dm_resources::ResourceSet {
        let policy = dm_resources::encoding::byond516_raw_policy();
        let inputs = [
            ("a.txt", b"same".as_slice()),
            ("b.png", b"same".as_slice()),
            ("c.txt", b"different".as_slice()),
        ]
        .into_iter()
        .map(|(name, bytes)| {
            dm_resources::encoding::encode_raw(
                ResourceRequest {
                    archive_name: name.into(),
                    disk_path: name.into(),
                },
                bytes,
                &policy,
            )
            .unwrap()
            .input
        })
        .collect();
        dm_resources::ResourceSet {
            inputs,
            fingerprint: [0; 32],
        }
    }
    #[test]
    fn exact_alias_order_controls_first_kind_and_real_archive() {
        let resources = resources();
        assert!(unambiguous_archive_order(&resources).is_err());
        let projection = project_resources(&resources, &[1, 0, 2]).unwrap();
        assert_eq!(projection.records.len(), 2);
        assert_eq!(projection.records[0].1.kind, 6);
        let mut cursor = std::io::Cursor::new(&projection.rsc);
        let mut names = Vec::new();
        while let Some(entry) = byond_dmb::rsc::read_entry(&mut cursor).unwrap() {
            if let byond_dmb::rsc::Entry::Named(named) = entry {
                names.push(named.name);
            }
        }
        assert_eq!(
            names,
            [b"b.png".to_vec(), b"a.txt".to_vec(), b"c.txt".to_vec()]
        );
        assert!(matches!(
            project_resources(&resources, &[0, 0, 2]),
            Err(ResourceOutputError::InvalidOrder)
        ));
        let mut inventory = dm_link::LinkInventory::default();
        projection.extend_inventory(&mut inventory);
        let tables = dm_link::LinkTables::build(inventory).unwrap();
        let mut dmb = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_template.bin"
        ))
        .unwrap();
        assert!(dmb.resources.is_empty());
        attach_resources(&mut dmb, &projection, &tables).unwrap();
        assert_eq!(dmb.resources.len(), 2);
        assert_eq!(
            dmb.resources[tables
                .index(dm_link::Key::Resource(projection.records[0].0))
                .unwrap() as usize]
                .kind,
            6
        );
    }
}
