//! Snapshot-local retained owner accounting. No fingerprint grants ownership.
//! Every referenced owner must stay live for this walk (as CapturedPolicyInputs
//! already guarantees); pointer identities are never persisted or sent on wire.
use dm_preprocess::{SourceText, SourceTextStorage};
use dm_resources::SharedBytes;
use std::{
    collections::{BTreeMap, BTreeSet},
    io,
    sync::Arc,
};
#[derive(Default, Debug, Clone, Copy, Eq, PartialEq)]
pub(super) struct Totals {
    pub payload_capacity: usize,
    pub owner_records: usize,
    pub memo_capacity: usize,
    pub text_backings: usize,
    pub text_payloads: usize,
    pub byte_backings: usize,
}
impl Totals {
    pub fn charge(self) -> io::Result<usize> {
        self.payload_capacity
            .checked_add(self.owner_records)
            .and_then(|n| n.checked_add(self.memo_capacity))
            .ok_or_else(overflow)
    }
}
fn overflow() -> io::Error {
    io::Error::other("policy owner admission charge overflow")
}
fn add(to: &mut usize, n: usize) -> io::Result<()> {
    *to = to.checked_add(n).ok_or_else(overflow)?;
    Ok(())
}
#[derive(Default)]
pub(super) struct Owners {
    // Namespaces prevent unrelated allocation classes from aliasing. Empty
    // allocations have zero payload capacity and are never charged by address.
    seen: BTreeSet<(u8, usize)>,
    totals: Totals,
    // Fingerprint vectors may grow while another policy uses the shared arena.
    // Key memo capacity by its stable live Backing owner, not reallocatable data.
    memo_by_backing: BTreeMap<usize, usize>,
}
impl Owners {
    pub fn text(&mut self, text: &SourceText) -> io::Result<()> {
        let mut result: io::Result<()> = Ok(());
        let mut backing = 0;
        text.visit_storage(|pointer, size, storage| {
            backing = pointer;
            result = (|| {
                if self.seen.insert((0, pointer)) {
                    add(
                        &mut self.totals.owner_records,
                        size + 2 * std::mem::size_of::<usize>(),
                    )?;
                    self.totals.text_backings += 1;
                }
                let (class, pointer, capacity, header) = match storage {
                    SourceTextStorage::Original(owner) => (
                        1,
                        owner.as_ptr() as usize,
                        owner.len(),
                        2 * std::mem::size_of::<usize>(),
                    ),
                    SourceTextStorage::Transformed(owner) => {
                        (2, owner.as_ptr() as usize, owner.capacity(), 0)
                    }
                    SourceTextStorage::Reserved { text, committed } => {
                        (2, text.as_ptr() as usize, committed, 0)
                    }
                };
                if (capacity > 0 || header > 0) && self.seen.insert((class, pointer)) {
                    add(&mut self.totals.payload_capacity, capacity)?;
                    add(&mut self.totals.owner_records, header)?;
                    self.totals.text_payloads += 1;
                }
                Ok(())
            })();
        });
        result?;
        let mut memo_result = Ok(());
        text.visit_fingerprint_storage(|_pointer, _logical, capacity| {
            let charged = self.memo_by_backing.entry(backing).or_default();
            if capacity > *charged {
                memo_result = add(&mut self.totals.memo_capacity, capacity - *charged);
                *charged = capacity;
            }
        });
        memo_result
    }
    pub fn bytes(&mut self, bytes: &SharedBytes) -> io::Result<()> {
        let owner = bytes.shared_owner();
        if self.seen.insert((4, owner as *const dm_resources::SharedBytesOwner as usize)) {
            add(
                &mut self.totals.owner_records,
                std::mem::size_of_val(owner) + 2 * std::mem::size_of::<usize>(),
            )?;
            add(&mut self.totals.payload_capacity, owner.bytes().capacity())?;
            self.totals.byte_backings += 1;
        }
        Ok(())
    }
    pub fn original_header_storage(&mut self, address: usize, capacity: usize) -> io::Result<()> {
        if capacity != 0 && self.seen.insert((5, address)) {
            add(&mut self.totals.payload_capacity, capacity)?;
        }
        Ok(())
    }
    pub fn totals(&self) -> Totals {
        self.totals
    }
}
#[cfg(test)]
#[path = "policy_owner_charge_tests.rs"]
mod tests;
