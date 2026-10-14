use super::*;
use std::io::Read;
pub(super) fn superseded(
    segments: &[(PathBuf, Arc<Segment>)],
    groups: &[(PathBuf, group_manifest::GroupManifest)],
) -> BTreeSet<u128> {
    let healthy = segments
        .iter()
        .filter(|(_, s)| !s.is_rejected())
        .map(|(_, s)| s.id())
        .collect();
    let activation = group_activation::activate(groups.iter().map(|(_, group)| group), &healthy);
    let group_superseded = activation.supersedes_segments;
    let mut superseded = group_superseded.clone();
    // Retired legacy tombstones cannot hide newly reused content-derived leaves.
    for (_, segment) in segments {
        if !segment.is_rejected() && !group_superseded.contains(&segment.id()) {
            superseded.extend(segment.supersedes().iter().copied());
        }
    }
    superseded
}
impl Cache {
    pub(super) fn read_groups(
        &self,
        rejected: &mut Vec<RejectedSegment>,
    ) -> Result<Vec<(PathBuf, group_manifest::GroupManifest)>, CacheError> {
        let mut paths = Vec::new();
        for entry in fs::read_dir(&self.root)? {
            let entry = entry?;
            if entry.file_type()?.is_file()
                && entry.path().extension().is_some_and(|ext| ext == "grp")
            {
                paths.push(entry.path());
            }
        }
        paths.sort();
        let mut groups = Vec::new();
        for path in paths {
            let load = (|| {
                let file = fs::File::open(&path)?;
                if file.metadata()?.len() > group_manifest::MAX_GROUP_BYTES as u64 {
                    return Err(CacheError::Invalid("group metadata exceeds bound".into()));
                }
                let mut bytes = Vec::new();
                file.take(group_manifest::MAX_GROUP_BYTES as u64 + 1)
                    .read_to_end(&mut bytes)?;
                let group = group_manifest::GroupManifest::decode(&bytes)?;
                if path.file_stem().and_then(|stem| stem.to_str())
                    != Some(format!("{:032x}", group.id).as_str())
                {
                    return Err(CacheError::Invalid("group identity/name mismatch".into()));
                }
                Ok(group)
            })();
            match load {
                Ok(group) => groups.push((path, group)),
                Err(error) => rejected.push(RejectedSegment {
                    path,
                    reason: error.to_string(),
                }),
            }
        }
        let all_members = groups
            .iter()
            .flat_map(|(_, group)| group.members.iter().copied())
            .collect();
        let cycles =
            group_activation::activate(groups.iter().map(|(_, group)| group), &all_members)
                .cyclic_groups;
        groups.retain(|(path, group)| {
            if cycles.contains(&group.id) {
                rejected.push(RejectedSegment {
                    path: path.clone(),
                    reason: "cyclic compaction group metadata".into(),
                });
                false
            } else {
                true
            }
        });
        Ok(groups)
    }
    pub(super) fn publish_group(
        &self,
        members: &[u128],
        segments: &[u128],
        groups: &[u128],
    ) -> Result<u128, CacheError> {
        let (group, bytes) = group_manifest::GroupManifest::encode(members, segments, groups)?;
        self.publish_bytes(group.id, &bytes, "grp")
    }
}
impl CacheSnapshot {
    pub(super) fn current_superseded(&self) -> Arc<BTreeSet<u128>> {
        let generation = self.rejection_generation.load(Ordering::Acquire);
        if generation == 0 {
            return Arc::clone(&self.superseded);
        }
        let mut revised = self
            .revised_superseded
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if revised.0 != generation {
            revised.1 = Arc::new(superseded(&self.segments, &self.groups));
            revised.0 = generation;
        }
        Arc::clone(&revised.1)
    }
    /// Admit every structurally valid mapped candidate in immutable segment order.
    /// This collection does not claim semantic use or record any reachability key.
    pub fn validated_candidates<'a>(
        &'a self,
        key: RecordKey,
        validate: impl Fn(&[u8], &[(u64, &[u8])]) -> Result<(), String>,
    ) -> Vec<RecordView<'a>> {
        loop {
            let superseded = self.current_superseded();
            let mut values = Vec::new();
            let mut retry = false;
            for ordinal in self.index.get(&key).into_iter().flatten() {
                let (path, segment) = &self.segments[*ordinal];
                if segment.is_rejected() || superseded.contains(&segment.id()) {
                    continue;
                }
                match segment.get(key, &validate) {
                    Ok(Some(view)) => values.push(view),
                    Ok(None) => {}
                    Err(error) => {
                        self.rejection_generation.fetch_add(1, Ordering::AcqRel);
                        self.rejected
                            .lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .push(RejectedSegment {
                                path: path.clone(),
                                reason: error.to_string(),
                            });
                        retry = true;
                        break;
                    }
                }
            }
            if !retry {
                return values;
            }
        }
    }
}

#[cfg(test)]
#[path = "store_group_tests.rs"]
mod tests;
