//! Where each string of a fresh String order was first seen, so a body patch can number a unit's changed literals as a
//! fresh link of the patched program numbers them (doc/rewrite/native_compiler_issues.md, "Incremental numbering").
//!
//! A fresh link orders strings by first occurrence: the registered strings, then every inventory entry in order
//! (`dmbc` `string_order`). A unit's literals are one strings chunk at the unit's place in that sequence, and the chunk
//! introduces the strings no earlier entry named, at consecutive positions. Replacing the chunk of one unit changes
//! the fresh order only at those positions when the unit introduces as many strings as before, no string it no longer
//! names has a later reference (its first occurrence would move), no string it now names was first seen after it, and
//! every string whose index changes is named by that unit alone. Then the patched order is the retained one with
//! those positions holding the new strings, and only the unit's own words and those table entries change.
use super::*;
use std::collections::HashSet;

#[derive(Clone, Copy, Debug, serde::Serialize, serde::Deserialize)]
struct Placed {
    /// Position in the String append order (the index is the position's allocated slot).
    position: u32,
    /// Inventory entries naming the string.
    references: u32,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
struct Chunk {
    /// Order position of the first string the chunk introduces (where it would introduce one when it introduces none).
    start: u32,
    introduced: u32,
    strings: Vec<SymbolId>,
}

/// First occurrences and reference counts of a fresh String order (see the module documentation). It is kept with a stored
/// patch base (`dmbc` `variant_spill`), so it encodes.
#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
pub struct StringLedger {
    strings: HashMap<SymbolId, Placed>,
    /// Strings chunks by owner key; `None` when one key owns two chunks.
    chunks: BTreeMap<Key, Option<Chunk>>,
}

/// One changed String table slot of a replacement: `index` held `old` and holds `new`.
#[derive(Clone, Debug)]
pub struct StringSlot {
    pub index: u32,
    pub old: Key,
    pub new: Key,
}

impl StringLedger {
    /// The ledger of `inventory`, whose String append order is complete and starts with `registered` registered strings.
    pub fn build(inventory: &LinkInventory, registered: usize) -> Option<Self> {
        let order = inventory.append_orders.get(&Table::String)?;
        let mut strings: HashMap<SymbolId, Placed> = HashMap::with_capacity(order.len());
        for (position, key) in order.iter().enumerate() {
            if let Key::String(id) = key {
                strings.insert(
                    *id,
                    Placed {
                        position: u32::try_from(position).ok()?,
                        references: 0,
                    },
                );
            }
        }
        let mut frontier = u32::try_from(registered).ok()?;
        let mut visit = |id: SymbolId, frontier: &mut u32| {
            if let Some(placed) = strings.get_mut(&id) {
                placed.references += 1;
                if placed.position >= *frontier {
                    *frontier = placed.position + 1;
                }
            }
        };
        let mut chunks: BTreeMap<Key, Option<Chunk>> = BTreeMap::new();
        let mut row = 0;
        for chunk in &inventory.shared {
            while row < chunk.entries_before {
                if let Key::String(id) = inventory.entries[row].key {
                    visit(id, &mut frontier);
                }
                row += 1;
            }
            if chunk.strings {
                let start = frontier;
                for payload in chunk.owner.strings() {
                    visit(payload.id, &mut frontier);
                }
                let value = Chunk {
                    start,
                    introduced: frontier - start,
                    strings: chunk.owner.strings().iter().map(|payload| payload.id).collect(),
                };
                chunks
                    .entry(chunk.owner.entry().key)
                    .and_modify(|seen| *seen = None)
                    .or_insert(Some(value));
            } else if let Key::String(id) = chunk.owner.entry().key {
                visit(id, &mut frontier);
            }
        }
        for entry in &inventory.entries[row.min(inventory.entries.len())..] {
            if let Key::String(id) = entry.key {
                visit(id, &mut frontier);
            }
        }
        Some(Self { strings, chunks })
    }

    /// Strings the ledger numbers (fixed strings aside).
    pub fn len(&self) -> usize {
        self.strings.len()
    }
    pub fn is_empty(&self) -> bool {
        self.strings.is_empty()
    }

    /// Replace the strings chunk of `owner` with `strings` (in entry order) in `ledger` and `tables` when a fresh link of
    /// the result numbers every other string as before; the changed slots, or why not.
    fn replace(
        &mut self,
        tables: &mut ReplacedTables,
        owner: Key,
        strings: &[(Key, EntryContent)],
    ) -> Result<Vec<StringSlot>, String> {
        let chunk = match self.chunks.get(&owner) {
            Some(Some(chunk)) => chunk.clone(),
            Some(None) => return Err(format!("{owner:?} owns two strings chunks")),
            None if strings.is_empty() => return Ok(Vec::new()),
            None => return Err(format!("{owner:?} introduces strings and has no strings chunk")),
        };
        let mut new_ids = Vec::with_capacity(strings.len());
        for (key, _) in strings {
            match key {
                Key::String(id) => new_ids.push(*id),
                other => return Err(format!("{other:?} is not a string")),
            }
        }
        let end = chunk.start + chunk.introduced;
        let in_chunk = |placed: &Placed| (chunk.start..end).contains(&placed.position);
        let occurrences = |ids: &[SymbolId]| {
            let mut counts: HashMap<SymbolId, u32> = HashMap::new();
            for id in ids {
                *counts.entry(*id).or_default() += 1;
            }
            counts
        };
        let (old_counts, new_counts) = (occurrences(&chunk.strings), occurrences(&new_ids));
        // The strings the old chunk introduced, by position.
        let mut old_introduced = vec![None; chunk.introduced as usize];
        for id in chunk.strings.iter() {
            if let Some(placed) = self.strings.get(id).filter(|placed| in_chunk(placed)) {
                old_introduced[(placed.position - chunk.start) as usize] = Some(*id);
            }
        }
        let old_introduced: Vec<SymbolId> = old_introduced
            .into_iter()
            .collect::<Option<_>>()
            .ok_or("the strings chunk's introductions are not its own")?;
        // The strings the new chunk introduces, in order.
        let mut seen = HashSet::new();
        let mut introduced = Vec::new();
        for id in &new_ids {
            if !seen.insert(*id) {
                continue;
            }
            match self.strings.get(id) {
                Some(placed) if placed.position < chunk.start => {}
                Some(placed) if placed.position >= end => {
                    return Err("a literal first seen after the unit moves before it".into())
                }
                Some(_) => introduced.push(*id),
                None if tables.indexes.contains_key(&Key::String(*id)) => {} // fixed
                None => introduced.push(*id),
            }
        }
        if introduced.len() != old_introduced.len() {
            return Err(format!(
                "the unit introduces {} strings instead of {}: later strings would move (chunk at {}, old strings at {:?})",
                introduced.len(),
                old_introduced.len(),
                chunk.start,
                chunk
                    .strings
                    .iter()
                    .map(|id| (self.strings.get(id).map(|placed| (placed.position, placed.references)), tables.indexes.get(&Key::String(*id)).copied()))
                    .collect::<Vec<_>>()
            ) + &format!(" ledger {} strings", self.strings.len()));
        }
        let exclusive = |id: &SymbolId| {
            self.strings
                .get(id)
                .is_some_and(|placed| placed.references == old_counts.get(id).copied().unwrap_or(0))
        };
        // A string the unit no longer names keeps its place only when an earlier entry introduced it.
        for (id, _) in old_counts.iter().filter(|(id, _)| !new_counts.contains_key(id)) {
            if let Some(placed) = self.strings.get(id) {
                if in_chunk(placed) && !exclusive(id) {
                    return Err("a dropped literal has a later reference: its first occurrence moves".into());
                }
                if !in_chunk(placed) && exclusive(id) {
                    // Numbered before the unit (registered) and named by nothing else: it would leave the order.
                    return Err("a dropped string is named by nothing else".into());
                }
            }
        }
        let mut slots = Vec::new();
        for (position, (old, new)) in old_introduced.iter().zip(&introduced).enumerate() {
            if old == new {
                continue;
            }
            if !exclusive(old) || (self.strings.contains_key(new) && !exclusive(new)) {
                return Err("a string another unit names would change its index".into());
            }
            let index = *tables
                .indexes
                .get(&Key::String(*old))
                .ok_or("an introduced string is not numbered")?;
            slots.push((chunk.start + position as u32, index, *old, *new));
        }
        // Apply: tables first (every old key of a changed slot leaves; every new key takes its slot), then the ledger.
        let contents: HashMap<SymbolId, &EntryContent> = strings
            .iter()
            .filter_map(|(key, content)| match key {
                Key::String(id) => Some((*id, content)),
                _ => None,
            })
            .collect();
        for &(_, _, old, _) in &slots {
            tables.indexes.remove(&Key::String(old));
            if !new_counts.contains_key(&old) {
                tables.content.remove(&Key::String(old));
            }
        }
        for &(_, index, _, new) in &slots {
            let key = Key::String(new);
            tables.indexes.insert(key, index);
            let content = contents.get(&new).ok_or("new string content")?;
            if let Some(existing) = tables.content.get(&key) {
                if existing != *content {
                    return Err(format!("{key:?} content collision"));
                }
            } else {
                tables.content.insert(key, (*content).clone());
            }
        }
        for (id, count) in &old_counts {
            if let Some(placed) = self.strings.get_mut(id) {
                placed.references -= count;
            }
        }
        for &(position, _, old, new) in &slots {
            if self.strings.get(&old).is_some_and(|placed| placed.position == position) {
                self.strings.remove(&old);
            }
            self.strings.insert(
                new,
                Placed {
                    position,
                    references: 0,
                },
            );
        }
        for (id, count) in &new_counts {
            if let Some(placed) = self.strings.get_mut(id) {
                placed.references += count;
            }
        }
        // A moved string (named again, at another introduced position) was re-inserted above; one dropped is gone.
        self.strings.retain(|_, placed| placed.references > 0);
        self.chunks.insert(
            owner,
            Some(Chunk {
                start: chunk.start,
                introduced: chunk.introduced,
                strings: new_ids,
            }),
        );
        Ok(slots
            .into_iter()
            .map(|(_, index, old, new)| StringSlot {
                index,
                old: Key::String(old),
                new: Key::String(new),
            })
            .collect())
    }
}

struct ReplacedTables {
    indexes: BTreeMap<Key, u32>,
    content: BTreeMap<Key, EntryContent>,
}

impl LinkTables {
    /// The tables' String ledger (a fresh link's; `None` after `extended` or `renumbered`, and after a restore unless it
    /// was stored with them).
    pub fn string_ledger(&self) -> Option<&StringLedger> {
        self.strings.as_deref()
    }
    /// The same tables with `ledger` as their String ledger (restored beside the tables it was built with).
    pub fn with_string_ledger(mut self, ledger: Option<StringLedger>) -> Self {
        self.strings = ledger.map(Arc::new);
        self
    }

    /// The tables of the same program with the strings chunks of `units` replaced (each by its strings in entry order),
    /// numbered exactly as a fresh link of that program numbers them, and the String slots that changed; an error when
    /// that would move any other string (the caller links the whole program then). Needs the ledger of a fresh link.
    pub fn replaced_unit_strings(
        &self,
        units: &[(Key, Vec<(Key, EntryContent)>)],
    ) -> Result<(Self, Vec<StringSlot>), String> {
        let mut ledger = self
            .strings
            .as_deref()
            .ok_or("the tables carry no string ledger")?
            .clone();
        let mut tables = ReplacedTables {
            indexes: self.bindings.assignments().clone(),
            content: (*self.content).clone(),
        };
        let mut slots = Vec::new();
        let mut touched = BTreeSet::new();
        for (owner, strings) in units {
            let changed = ledger.replace(&mut tables, *owner, strings)?;
            for slot in &changed {
                // Two units exchanging strings would make each replacement's exclusivity check see the other's.
                if !touched.insert(slot.old) || !touched.insert(slot.new) {
                    return Err("two edited units change the same string".into());
                }
            }
            slots.extend(changed);
        }
        let slot_map = self.bindings.slots().clone();
        Ok((
            Self {
                bindings: BindingTables::validated(tables.indexes, slot_map, None),
                content: Arc::new(tables.content),
                strip_debug_ops: self.strip_debug_ops,
                strings: Some(Arc::new(ledger)),
            },
            slots,
        ))
    }
}

#[cfg(test)]
#[path = "string_ledger_tests.rs"]
mod tests;
