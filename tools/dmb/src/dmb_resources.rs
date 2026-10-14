use super::*;

/// Reusable index for looking up many DMB resource references in one archive.
pub struct ResourceLookup<'a> {
    pub(super) archive: &'a [crate::rsc::Entry],
    pub(super) by_key: HashMap<(u32, u8), usize>,
}

impl<'a> ResourceLookup<'a> {
    pub fn new(archive: &'a [crate::rsc::Entry]) -> Self {
        let mut by_key = HashMap::new();
        for (index, entry) in archive.iter().enumerate() {
            if let crate::rsc::Entry::Named(resource) = entry {
                by_key.entry((resource.id, resource.kind)).or_insert(index);
            }
        }
        Self { archive, by_key }
    }

    pub fn get(&self, dmb: &Dmb, index: ResourceId) -> Option<&'a crate::rsc::NamedResource> {
        let reference = dmb.resources.get(index.index())?;
        let entry = self
            .archive
            .get(*self.by_key.get(&(reference.id, reference.kind))?)?;
        match entry {
            crate::rsc::Entry::Named(resource) => Some(resource),
            crate::rsc::Entry::Opaque { .. } => None,
        }
    }
}

/// Attach borrowed assets while retaining only references to archive payloads.
/// Distinct spellings of identical content share a table and archive entry.
pub fn attach_resource_refs<'a>(
    dmb: &mut Dmb,
    resources: impl IntoIterator<Item = &'a crate::rsc::NamedResource>,
) -> io::Result<(Vec<ResourceId>, Vec<&'a crate::rsc::NamedResource>)> {
    let mut references = HashMap::new();
    for (id, resource) in dmb.resources.iter().enumerate() {
        references
            .entry((resource.id, resource.kind))
            .or_insert(id as u32);
    }
    let mut archive: Vec<&crate::rsc::NamedResource> = Vec::new();
    let mut entries: HashMap<(u32, u8), usize> = HashMap::new();
    let mut ids = Vec::new();
    for resource in resources {
        if resource.content_id()? != resource.id {
            return Err(invalid("RSC resource ID does not match asset content"));
        }
        let key = (resource.id, resource.kind);
        if let Some(&entry) = entries.get(&key) {
            if archive[entry].asset_bytes()? != resource.asset_bytes()? {
                return Err(invalid("RSC resource ID collision"));
            }
        } else {
            entries.insert(key, archive.len());
            archive.push(resource);
        }
        let index = if let Some(&index) = references.get(&key) {
            index
        } else {
            let index = u32::try_from(dmb.resources.len())
                .map_err(|_| invalid("resource index exceeds u32"))?;
            ResourceId::from_raw(index).ok_or_else(|| invalid("reserved resource index"))?;
            dmb.resources.push(ResourceRef {
                id: resource.id,
                kind: resource.kind,
            });
            references.insert(key, index);
            index
        };
        ids.push(ResourceId::from_raw(index).ok_or_else(|| invalid("reserved resource index"))?);
    }
    Ok((ids, archive))
}

/// Keeps resource tables indexed while inserting a batch of assets.
pub struct ResourceAttachment<'a> {
    pub(super) dmb: &'a mut Dmb,
    pub(super) archive: &'a mut Vec<crate::rsc::Entry>,
    pub(super) references: HashMap<(u32, u8), u32>,
    pub(super) archive_entries: HashMap<(u32, u8), usize>,
}

impl<'a> ResourceAttachment<'a> {
    pub fn new(dmb: &'a mut Dmb, archive: &'a mut Vec<crate::rsc::Entry>) -> Self {
        let mut references = HashMap::new();
        for (index, reference) in dmb.resources.iter().enumerate() {
            references
                .entry((reference.id, reference.kind))
                .or_insert(index as u32);
        }
        let mut archive_entries = HashMap::new();
        for (index, entry) in archive.iter().enumerate() {
            if let crate::rsc::Entry::Named(resource) = entry {
                archive_entries
                    .entry((resource.id, resource.kind))
                    .or_insert(index);
            }
        }
        Self {
            dmb,
            archive,
            references,
            archive_entries,
        }
    }

    pub fn attach(&mut self, resource: crate::rsc::NamedResource) -> io::Result<ResourceId> {
        if resource.content_id()? != resource.id {
            return Err(invalid("RSC resource ID does not match asset content"));
        }
        let key = (resource.id, resource.kind);
        if let Some(&index) = self.references.get(&key) {
            let entry = self
                .archive_entries
                .get(&key)
                .and_then(|&position| self.archive.get(position))
                .ok_or_else(|| invalid("DMB resource reference missing from RSC"))?;
            let crate::rsc::Entry::Named(existing) = entry else {
                return Err(invalid("RSC resource index is not named"));
            };
            if existing.asset_bytes()? != resource.asset_bytes()? {
                return Err(invalid("RSC resource ID collision"));
            }
            return ResourceId::from_raw(index).ok_or_else(|| invalid("reserved resource index"));
        }
        let index = u32::try_from(self.dmb.resources.len())
            .map_err(|_| invalid("resource index exceeds u32"))?;
        let typed =
            ResourceId::from_raw(index).ok_or_else(|| invalid("reserved resource index"))?;
        self.dmb.resources.push(ResourceRef {
            id: resource.id,
            kind: resource.kind,
        });
        self.references.insert(key, index);
        self.archive_entries.insert(key, self.archive.len());
        self.archive.push(crate::rsc::Entry::Named(resource));
        Ok(typed)
    }
}
