//! Selected-record candidate admission. Rejection of a semantic context is a
//! healthy miss; a malformed record still rejects its complete immutable segment.
use super::*;
use std::cell::Cell;
impl CacheSnapshot {
    /// Visit healthy candidates in the snapshot's existing immutable segment order.
    /// `Ok(false)` means structurally valid but unsuitable for this context;
    /// `Err` means invalid typed bytes and rejects the complete segment.
    /// Only a successful `Ok(true)` candidate enters the used-key reachability set.
    /// Payload and spelling slices borrow their immutable mapped segment.
    pub fn get_candidate<'a>(
        &'a self,
        key: RecordKey,
        validate_and_accept: impl Fn(&[u8], &[(u64, &[u8])]) -> Result<bool, String>,
    ) -> Option<RecordView<'a>> {
        loop {
            let superseded = self.current_superseded();
            let mut retry = false;
            for &ordinal in self.index.get(&key)? {
                let (path, segment) = &self.segments[ordinal];
                if segment.is_rejected() || superseded.contains(&segment.id()) {
                    continue;
                }
                let accepted = Cell::new(false);
                let candidate = segment.get(key, |payload, symbols| {
                    accepted.set(validate_and_accept(payload, symbols)?);
                    Ok(())
                });
                match candidate {
                    Ok(Some(view)) if accepted.get() => {
                        self.used_keys
                            .lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .insert(key);
                        return Some(view);
                    }
                    Ok(_) => {}
                    Err(error) => {
                        self.rejection_generation.fetch_add(1, Ordering::AcqRel);
                        self.rejected
                            .lock()
                            .unwrap_or_else(|p| p.into_inner())
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
                return None;
            }
        }
    }
}

#[cfg(test)]
#[path = "store_candidate_tests.rs"]
mod tests;
