use super::*;
impl Cache {
    pub(super) fn compact_group(
        &self,
        live: &BTreeSet<RecordKey>,
        validate: &impl Fn(RecordKey, &[u8], &[(u64, &[u8])]) -> Result<(), String>,
    ) -> Result<CompactResult, CacheError> {
        let snapshot = self.snapshot()?;
        // Bytecheck every candidate before writing. Later rejection of another
        // record in the same segment invalidates all its earlier candidates.
        loop {
            let before = snapshot.rejection_generation.load(Ordering::Acquire);
            for key in live {
                snapshot
                    .validated_candidates(*key, |bytes, symbols| validate(*key, bytes, symbols));
            }
            if snapshot.rejection_generation.load(Ordering::Acquire) == before {
                break;
            }
        }
        if snapshot.segments.is_empty() && snapshot.groups.is_empty() {
            return Ok(CompactResult {
                segment: None,
                group: None,
                segments: vec![],
                records: 0,
                deleted: 0,
                deferred_deletes: vec![],
            });
        }
        let admitted_generation = snapshot.rejection_generation.load(Ordering::Acquire);
        let mut pending = crate::PendingRecords::default();
        let mut members = Vec::new();
        let mut count = 0;
        let budget = self.limits.segment_bytes.saturating_sub(72);
        for key in live {
            let candidates = snapshot
                .validated_candidates(*key, |bytes, symbols| validate(*key, bytes, symbols));
            let mut seen: Vec<&RecordView<'_>> = Vec::new();
            for candidate in &candidates {
                if seen
                    .iter()
                    .any(|old| old.payload == candidate.payload && old.symbols == candidate.symbols)
                {
                    continue;
                }
                seen.push(candidate);
                let record = Record {
                    key: *key,
                    payload: Arc::from(candidate.payload),
                    symbols: candidate
                        .symbols
                        .iter()
                        .map(|(id, text)| crate::SymbolText {
                            id: *id,
                            text: Arc::from(*text),
                        })
                        .collect(),
                };
                if !pending.is_empty() && pending.len() >= self.limits.records as usize {
                    members.push(self.publish(&pending.take())?);
                }
                for batch in pending.push(record, budget)? {
                    members.push(self.publish(&batch)?);
                }
                count += 1;
            }
        }
        let final_batch = pending.take();
        if !final_batch.is_empty() || members.is_empty() {
            members.push(self.publish(&final_batch)?);
        }
        members.sort_unstable();
        members.dedup();
        if snapshot.rejection_generation.load(Ordering::Acquire) != admitted_generation {
            // Published leaves remain harmless non-superseding candidates. Never
            // certify a selection changed by a late validator rejection.
            return Err(CacheError::Invalid(
                "compaction admission changed during output staging".into(),
            ));
        }
        let supersedes = snapshot
            .segments
            .iter()
            .map(|(_, s)| s.id())
            .filter(|id| members.binary_search(id).is_err())
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        let previous_groups = snapshot
            .groups
            .iter()
            .map(|(_, g)| g.id)
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        // The one atomic marker is the only superseding publication. A crash or
        // I/O failure during any preceding split leaf cannot hide source keys.
        let group = self.publish_group(&members, &supersedes, &previous_groups)?;
        let old = snapshot
            .segments
            .iter()
            .map(|(path, s)| (path.clone(), s.id(), false))
            .chain(
                snapshot
                    .groups
                    .iter()
                    .map(|(path, g)| (path.clone(), g.id, true)),
            )
            .collect::<Vec<_>>();
        drop(snapshot);
        let mut deleted = 0;
        let mut deferred_deletes = Vec::new();
        for (path, id, is_group) in old {
            if (is_group && id != group) || (!is_group && supersedes.binary_search(&id).is_ok()) {
                match fs::remove_file(&path) {
                    Ok(()) => deleted += 1,
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                    Err(_) => deferred_deletes.push(path),
                }
            }
        }
        Ok(CompactResult {
            segment: members.first().copied(),
            group: Some(group),
            segments: members,
            records: count,
            deleted,
            deferred_deletes,
        })
    }
}
