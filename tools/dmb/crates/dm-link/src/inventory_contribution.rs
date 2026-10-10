//! Immutable descriptor chunks replayed through the ordinary linker validator.
use super::*;
#[derive(Clone, Debug)]
pub struct InventoryContribution {
    entry: Entry,
    slots: Vec<SlotAlias>,
    strings: Vec<dm_ir::StringPayload>,
}
impl InventoryContribution {
    pub fn new(key: Key, content: EntryContent, slots: Vec<SlotAlias>) -> Self {
        Self {
            entry: Entry { key, content },
            slots,
            strings: Vec::new(),
        }
    }
    pub fn entry(&self) -> &Entry {
        &self.entry
    }
    pub fn slots(&self) -> &Vec<SlotAlias> {
        &self.slots
    }
    pub fn with_strings(mut self, strings: Vec<dm_ir::StringPayload>) -> Self {
        self.strings = strings;
        self
    }
    pub fn strings(&self) -> &Vec<dm_ir::StringPayload> {
        &self.strings
    }
    pub fn into_parts(self) -> (Entry, Vec<SlotAlias>, Vec<dm_ir::StringPayload>) {
        (self.entry, self.slots, self.strings)
    }
}
/// Offsets refer only to the inventory's owned rows, preserving insertion order
/// without flattening shared descriptors. The builder validates offsets first.
#[derive(Clone, Debug)]
pub struct SharedContribution {
    pub entries_before: usize,
    pub slots_before: usize,
    pub spellings_before: usize,
    pub strings: bool,
    pub owner: Arc<InventoryContribution>,
}
impl LinkInventory {
    pub fn append_shared(&mut self, owner: Arc<InventoryContribution>) {
        self.shared.push(SharedContribution {
            entries_before: self.entries.len(),
            slots_before: self.slots.len(),
            spellings_before: self.spellings.len(),
            strings: false,
            owner,
        });
    }
    /// Replay immutable strings before current debug/source entries; code/slots
    /// are appended separately after those current inputs have been captured.
    pub fn append_shared_strings(&mut self, owner: Arc<InventoryContribution>) {
        if owner.strings.is_empty() {
            return;
        }
        self.shared.push(SharedContribution {
            entries_before: self.entries.len(),
            slots_before: self.slots.len(),
            spellings_before: self.spellings.len(),
            strings: true,
            owner,
        });
    }
    pub fn spelling_iter(&self) -> impl Iterator<Item = (SymbolId, &Arc<[u8]>)> {
        SpellingIter {
            inventory: self,
            row: 0,
            chunk: 0,
            local: 0,
        }
    }
    /// Stream descriptors directly from immutable payloads; no retained or
    /// request-wide flattened string Entry roster is constructed.
    pub fn entry_iter(&self) -> impl Iterator<Item = Entry> + '_ {
        EntryIter {
            inventory: self,
            row: 0,
            chunk: 0,
            local: 0,
        }
    }
    pub fn slot_iter(&self) -> impl Iterator<Item = &SlotAlias> {
        Spliced::new(
            &self.slots,
            &self.shared,
            |chunk| chunk.slots_before,
            |chunk| {
                if chunk.strings {
                    &[]
                } else {
                    chunk.owner.slots().as_slice()
                }
            },
        )
    }
    pub(super) fn validate_shared(&self) -> Result<(), LinkError> {
        let mut last = (0, 0, 0);
        for chunk in &self.shared {
            if chunk.entries_before < last.0
                || chunk.entries_before > self.entries.len()
                || chunk.slots_before < last.1
                || chunk.slots_before > self.slots.len()
                || chunk.spellings_before < last.2
                || chunk.spellings_before > self.spellings.len()
            {
                return Err(LinkError::InvalidContributionOrder);
            }
            last = (
                chunk.entries_before,
                chunk.slots_before,
                chunk.spellings_before,
            );
        }
        Ok(())
    }
}
struct EntryIter<'a> {
    inventory: &'a LinkInventory,
    row: usize,
    chunk: usize,
    local: usize,
}
impl Iterator for EntryIter<'_> {
    type Item = Entry;
    fn next(&mut self) -> Option<Self::Item> {
        while let Some(chunk) = self.inventory.shared.get(self.chunk) {
            if self.row < chunk.entries_before {
                let value = self.inventory.entries.get(self.row)?.clone();
                self.row += 1;
                return Some(value);
            }
            if chunk.strings {
                if let Some(payload) = chunk.owner.strings.get(self.local) {
                    self.local += 1;
                    return Some(Entry {
                        key: Key::String(payload.id),
                        content: Arc::clone(&payload.bytes).into(),
                    });
                }
            } else if self.local == 0 {
                self.local = 1;
                return Some(chunk.owner.entry.clone());
            }
            self.chunk += 1;
            self.local = 0;
        }
        let value = self.inventory.entries.get(self.row)?.clone();
        self.row += 1;
        Some(value)
    }
}
struct SpellingIter<'a> {
    inventory: &'a LinkInventory,
    row: usize,
    chunk: usize,
    local: usize,
}
impl<'a> Iterator for SpellingIter<'a> {
    type Item = (SymbolId, &'a Arc<[u8]>);
    fn next(&mut self) -> Option<Self::Item> {
        while let Some(chunk) = self.inventory.shared.get(self.chunk) {
            if self.row < chunk.spellings_before {
                let (id, bytes) = self.inventory.spellings.get(self.row)?;
                self.row += 1;
                return Some((*id, bytes));
            }
            if chunk.strings {
                if let Some(payload) = chunk.owner.strings.get(self.local) {
                    self.local += 1;
                    return Some((payload.id, &payload.bytes));
                }
            }
            self.chunk += 1;
            self.local = 0;
        }
        let (id, bytes) = self.inventory.spellings.get(self.row)?;
        self.row += 1;
        Some((*id, bytes))
    }
}
struct Spliced<'a, T> {
    owned: &'a [T],
    chunks: &'a [SharedContribution],
    row: usize,
    chunk: usize,
    local: usize,
    offset: fn(&SharedContribution) -> usize,
    values: fn(&SharedContribution) -> &[T],
}
impl<'a, T> Spliced<'a, T> {
    fn new(
        owned: &'a [T],
        chunks: &'a [SharedContribution],
        offset: fn(&SharedContribution) -> usize,
        values: fn(&SharedContribution) -> &[T],
    ) -> Self {
        Self {
            owned,
            chunks,
            row: 0,
            chunk: 0,
            local: 0,
            offset,
            values,
        }
    }
}
impl<'a, T> Iterator for Spliced<'a, T> {
    type Item = &'a T;
    fn next(&mut self) -> Option<Self::Item> {
        while let Some(chunk) = self.chunks.get(self.chunk) {
            if self.row < (self.offset)(chunk) {
                let value = self.owned.get(self.row)?;
                self.row += 1;
                return Some(value);
            }
            if let Some(value) = (self.values)(chunk).get(self.local) {
                self.local += 1;
                return Some(value);
            }
            self.chunk += 1;
            self.local = 0;
        }
        let value = self.owned.get(self.row)?;
        self.row += 1;
        Some(value)
    }
}
#[cfg(test)]
#[path = "inventory_contribution_tests.rs"]
mod tests;
