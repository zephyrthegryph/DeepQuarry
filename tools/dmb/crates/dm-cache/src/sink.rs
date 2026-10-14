//! Bounded segment publication; semantic producers retain no whole-build batch.
use crate::{Cache, CacheError, Record, RecordKey};
use std::collections::BTreeSet;
#[derive(Debug, Default)]
pub struct PublishReport {
    pub segments: Vec<u128>,
    pub keys: BTreeSet<RecordKey>,
    pub records: usize,
}
pub struct PublishSink<'a> {
    cache: &'a Cache,
    budget: u64,
    bytes: u64,
    pending: Vec<Record>,
    pending_keys: BTreeSet<RecordKey>,
    report: PublishReport,
}
pub(crate) fn record_charge(record: &Record) -> Result<u64, CacheError> {
    let mut size = 56u64 + 4 + 8 + 15; // descriptor, count, payload length and worst alignment
    size = size
        .checked_add(record.payload.len() as u64)
        .ok_or_else(|| CacheError::Invalid("record charge overflow".into()))?;
    for symbol in &record.symbols {
        size = size
            .checked_add(12)
            .and_then(|n| n.checked_add(symbol.text.len() as u64))
            .ok_or_else(|| CacheError::Invalid("record charge overflow".into()))?;
    }
    Ok(size)
}
impl Cache {
    pub fn publish_sink(&self, pending_bytes: u64) -> PublishSink<'_> {
        PublishSink {
            cache: self,
            budget: pending_bytes.min(self.limits.segment_bytes.saturating_sub(72)),
            bytes: 0,
            pending: Vec::new(),
            pending_keys: BTreeSet::new(),
            report: PublishReport::default(),
        }
    }
}
impl PublishSink<'_> {
    pub fn push(&mut self, record: Record) -> Result<(), CacheError> {
        let charge = record_charge(&record)?;
        if !self.pending.is_empty()
            && (self.bytes.saturating_add(charge) > self.budget
                || self.pending.len() >= self.cache.limits.records as usize
                || self.pending_keys.contains(&record.key))
        {
            self.flush()?;
        }
        if charge > self.budget {
            let key = record.key;
            let id = self.cache.publish(&[record])?;
            self.report.segments.push(id);
            self.report.keys.insert(key);
            self.report.records += 1;
        } else {
            self.bytes += charge;
            self.pending_keys.insert(record.key);
            self.pending.push(record);
        }
        Ok(())
    }
    pub fn flush(&mut self) -> Result<(), CacheError> {
        if self.pending.is_empty() {
            return Ok(());
        }
        let id = self.cache.publish(&self.pending)?;
        self.report.segments.push(id);
        self.report.records += self.pending.len();
        self.report
            .keys
            .extend(self.pending.iter().map(|record| record.key));
        self.pending.clear();
        self.pending_keys.clear();
        self.bytes = 0;
        Ok(())
    }
    pub fn pending_bytes(&self) -> u64 {
        self.bytes
    }
    pub fn published_keys(&self) -> &BTreeSet<RecordKey> {
        &self.report.keys
    }
    /// Must be called explicitly. Dropping this disposable sink performs no I/O.
    pub fn finish(mut self) -> Result<PublishReport, CacheError> {
        self.flush()?;
        Ok(self.report)
    }
}
