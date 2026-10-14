//! Bounded neutral record staging shared by semantic producers.
use crate::{sink::record_charge, CacheError, Record, RecordKey};
use std::collections::BTreeMap;
#[derive(Default)]
pub struct PendingRecords {
    records: BTreeMap<RecordKey, Record>,
    bytes: u64,
}
impl PendingRecords {
    pub fn len(&self) -> usize {
        self.records.len()
    }
    pub fn get(&self, key: &RecordKey) -> Option<&Record> {
        self.records.get(key)
    }
    pub fn is_empty(&self) -> bool {
        self.records.is_empty()
    }
    pub fn bytes(&self) -> u64 {
        self.bytes
    }
    pub fn take(&mut self) -> Vec<Record> {
        self.bytes = 0;
        std::mem::take(&mut self.records).into_values().collect()
    }
    /// Return batches ready for publication; no I/O occurs while staging.
    /// Distinct same-locator records are never overwritten. Oversized records
    /// are emitted individually, never excluded by the working-memory budget.
    pub fn push(&mut self, record: Record, budget: u64) -> Result<Vec<Vec<Record>>, CacheError> {
        let charge = record_charge(&record)?;
        let mut ready = Vec::new();
        if self
            .records
            .get(&record.key)
            .is_some_and(|old| old == &record)
        {
            return Ok(ready);
        }
        if !self.records.is_empty()
            && (self.records.contains_key(&record.key)
                || self.bytes.saturating_add(charge) > budget)
        {
            ready.push(self.take());
        }
        if charge > budget {
            ready.push(vec![record]);
        } else {
            self.bytes = self
                .bytes
                .checked_add(charge)
                .ok_or_else(|| CacheError::Invalid("pending record charge overflow".into()))?;
            self.records.insert(record.key, record);
        }
        Ok(ready)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    fn record(payload: &[u8]) -> Record {
        Record {
            key: RecordKey {
                stage: 1,
                version: 1,
                content: 1,
            },
            symbols: vec![],
            payload: Arc::from(payload),
        }
    }
    #[test]
    fn collisions_preserve_every_context_without_merging_or_count_ceiling() {
        let mut pending = PendingRecords::default();
        let mut emitted = Vec::new();
        for i in 0..6u8 {
            emitted.extend(
                pending
                    .push(record(&[i]), 1024)
                    .unwrap()
                    .into_iter()
                    .flatten(),
            );
        }
        emitted.extend(pending.take());
        assert_eq!(
            emitted.iter().map(|r| r.payload[0]).collect::<Vec<_>>(),
            [0, 1, 2, 3, 4, 5]
        );
        assert_eq!(pending.bytes(), 0);
    }
    #[test]
    fn identical_records_deduplicate_and_oversized_record_is_published() {
        let mut pending = PendingRecords::default();
        assert!(pending.push(record(b"a"), 1024).unwrap().is_empty());
        let bytes = pending.bytes();
        assert!(pending.push(record(b"a"), 1024).unwrap().is_empty());
        assert_eq!(pending.bytes(), bytes);
        let ready = pending.push(record(b"oversized"), 0).unwrap();
        assert_eq!(ready.len(), 2);
        assert_eq!(ready[0][0].payload.as_ref(), b"a");
        assert_eq!(ready[1][0].payload.as_ref(), b"oversized");
        assert_eq!(pending.bytes(), 0);
    }
}
