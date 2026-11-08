//! Content-derived symbols shared across independent compiler processes.
//!
//! These are semantic names, never BYOND table indexes. The linker assigns wire
//! indexes separately. Hash collisions are errors and leave the table unchanged.

use std::collections::HashMap;
use std::fmt;
use std::sync::Arc;

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
pub struct SymbolId(u64);

impl SymbolId {
    pub(crate) const ZERO: Self = Self(0);

    pub fn of(text: &str) -> Self {
        Self::of_bytes(text.as_bytes())
    }

    /// Runtime string payloads can contain non-UTF-8 BYOND formatting bytes.
    /// Their identity uses exact bytes, never a lossy Unicode conversion.
    pub fn of_bytes(bytes: &[u8]) -> Self {
        Self(xxhash_rust::xxh3::xxh3_64(bytes))
    }

    pub const fn bits(self) -> u64 {
        self.0
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SymbolCollision {
    pub id: SymbolId,
    pub existing: Arc<str>,
    pub incoming: Arc<str>,
}

impl fmt::Display for SymbolCollision {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "symbol hash collision {:016x}: {:?} and {:?}",
            self.id.bits(),
            self.existing,
            self.incoming
        )
    }
}

impl std::error::Error for SymbolCollision {}

#[derive(Clone, Debug, Default)]
pub struct SymbolTable {
    texts: HashMap<SymbolId, Arc<str>>,
    parent: Option<Arc<SymbolTable>>,
    local_spelling_bytes: usize,
    non_intern_epoch: usize,
}

/// Borrowed backing inventory for diagnostic ownership traversal. HashMap's
/// usable capacity is exposed; its private bucket allocation is not fabricated.
pub struct SymbolTableStorage<'a> {
    pub local_len: usize,
    pub local_capacity: usize,
    pub parent: Option<&'a Arc<SymbolTable>>,
}

/// Local accounting only. No parent, semantic identity or bucket layout.
#[derive(Clone, Copy)]
pub struct LocalSymbolStorage {
    len: usize,
    capacity: usize,
    spelling_bytes: usize,
    non_intern_epoch: usize,
}

impl LocalSymbolStorage {
    /// Compare two observations of the SAME append-only table. HashMap's
    /// capacity guarantees that inserting through that old limit cannot
    /// reallocate. A vacant entry is the only intern path that can grow the
    /// map; an occupied entry only borrows an existing spelling.
    pub fn spelling_delta_without_bucket_growth(self, before: Self) -> Option<usize> {
        if before.non_intern_epoch != self.non_intern_epoch || self.non_intern_epoch == usize::MAX
            || before.capacity != self.capacity || self.len < before.len || self.len > before.capacity
            || self.spelling_bytes == usize::MAX
        {
            return None;
        }
        self.spelling_bytes.checked_sub(before.spelling_bytes)
    }
}

fn arc_spelling_bytes(text: &str) -> usize {
    use std::{alloc::Layout, sync::atomic::AtomicUsize};
    // std's Arc<str> copies the bytes into ArcInner<[u8]>: two AtomicUsize
    // counts and the exact unsized payload, padded to the allocation alignment.
    // This measures the allocation layout, never allocator overhead or RSS.
    Layout::new::<[AtomicUsize; 2]>().extend(Layout::for_value(text))
        .map_or(usize::MAX, |(layout, _)| layout.pad_to_align().size())
}

impl SymbolTable {
    pub fn local_storage(&self) -> LocalSymbolStorage {
        LocalSymbolStorage {
            len: self.texts.len(), capacity: self.texts.capacity(),
            spelling_bytes: self.local_spelling_bytes, non_intern_epoch: self.non_intern_epoch,
        }
    }

    /// Borrow actual local Arc owners; stop immediately at the first failure.
    pub fn try_visit_local_spellings<E>(&self, mut visit: impl FnMut(&Arc<str>) -> Result<(), E>) -> Result<(), E> {
        for text in self.texts.values() {
            visit(text)?;
        }
        Ok(())
    }

    /// Visit local shared spellings without sorting, copying, or materializing
    /// inherited entries. Callers can deduplicate the immutable parent separately.
    pub fn visit_storage(
        &self,
        mut visitor: impl FnMut(SymbolId, &Arc<str>),
    ) -> SymbolTableStorage<'_> {
        for (&id, text) in &self.texts {
            visitor(id, text);
        }
        SymbolTableStorage {
            local_len: self.texts.len(),
            local_capacity: self.texts.capacity(),
            parent: self.parent.as_ref(),
        }
    }
    /// Immutable spelling backing plus a small collision-checked local delta.
    /// Exact immutable catalog authority: no local delta and the same owned parent.
    pub fn is_empty_overlay_of(&self, source: &Arc<SymbolTable>) -> bool {
        self.texts.is_empty()
            && self
                .parent
                .as_ref()
                .is_some_and(|parent| Arc::ptr_eq(parent, source))
    }
    pub fn overlay(parent: Arc<SymbolTable>) -> Self {
        Self {
            texts: HashMap::new(),
            parent: Some(parent),
            local_spelling_bytes: 0,
            non_intern_epoch: 0,
        }
    }
    /// Accept only this dictionary or an overlay issued over this exact immutable
    /// backing. Overlay insertion rejects collisions with every ancestor, so
    /// added spellings cannot alter an existing source meaning.
    pub fn is_extension_of(&self, source: &SymbolTable) -> bool {
        std::ptr::eq(self, source)
            || self
                .parent
                .as_ref()
                .is_some_and(|parent| parent.is_extension_of(source))
    }
    pub fn intern(&mut self, text: &str) -> Result<SymbolId, SymbolCollision> {
        self.insert(SymbolId::of(text), text)
    }

    /// Reuse the primary exact spelling allocation proof for a caller with
    /// an existing operation budget. Only a genuinely vacant entry strictly
    /// inside the current table capacity has the no-bucket-growth guarantee.
    /// Existing hits, collisions, and a full table keep the ordinary intern
    /// path. A returned backing reference identifies the newly funded Arc.
    pub fn intern_funding_spare_spelling<E>(
        &mut self, text: &str, fund: impl FnOnce(usize) -> Result<(), E>,
    ) -> Result<Result<(SymbolId, Option<&Arc<str>>), SymbolCollision>, E> {
        let id = SymbolId::of(text);
        let funded = self.text(id).is_none() && self.texts.len() < self.texts.capacity();
        if funded {
            fund(arc_spelling_bytes(text))?;
        }
        Ok(self.insert(id, text).map(|id| {
            let backing = funded.then(|| self.texts.get(&id).expect("new local spelling"));
            (id, backing)
        }))
    }

    /// Merge certified IDs and shared spellings without hashing their text again.
    /// Validate the complete incoming ancestry before mutating this dictionary.
    pub fn merge_from(&mut self, source: &SymbolTable) -> Result<(), SymbolCollision> {
        fn check(
            target: &SymbolTable,
            source: &SymbolTable,
            collision: &mut Option<SymbolCollision>,
        ) {
            if let Some(parent) = &source.parent {
                check(target, parent, collision);
            }
            for (&id, incoming) in &source.texts {
                if let Some(existing) = target.text(id) {
                    if existing != incoming.as_ref()
                        && collision.as_ref().is_none_or(|previous| id < previous.id)
                    {
                        *collision = Some(SymbolCollision {
                            id,
                            existing: Arc::from(existing),
                            incoming: Arc::clone(incoming),
                        });
                    }
                }
            }
        }
        fn append(target: &mut SymbolTable, source: &SymbolTable) {
            if let Some(parent) = &source.parent {
                append(target, parent);
            }
            for (&id, text) in &source.texts {
                if target.text(id).is_none() {
                    target.texts.insert(id, Arc::clone(text));
                    target.local_spelling_bytes = target.local_spelling_bytes.saturating_add(arc_spelling_bytes(text));
                }
            }
        }
        let mut collision = None;
        check(self, source, &mut collision);
        if let Some(collision) = collision {
            return Err(collision);
        }
        let before = self.texts.len();
        append(self, source);
        if self.texts.len() != before {
            self.non_intern_epoch = self.non_intern_epoch.saturating_add(1);
        }
        Ok(())
    }

    /// Remove inactive local entries while preserving immutable parent backing.
    pub fn retain_local(&mut self, mut keep: impl FnMut(SymbolId) -> bool) {
        self.non_intern_epoch = self.non_intern_epoch.saturating_add(1);
        let mut bytes = 0usize;
        self.texts.retain(|&id, text| {
            let retained = keep(id);
            if retained {
                bytes = bytes.saturating_add(arc_spelling_bytes(text));
            }
            retained
        });
        self.local_spelling_bytes = bytes;
    }
    /// Drop one local spelling (an inherited one is the parent's and stays).
    pub fn remove_local(&mut self, id: SymbolId) -> bool {
        let Some(text) = self.texts.remove(&id) else { return false };
        if self.local_spelling_bytes != usize::MAX {
            self.local_spelling_bytes -= arc_spelling_bytes(&text);
        }
        self.non_intern_epoch = self.non_intern_epoch.saturating_add(1);
        true
    }

    fn insert(&mut self, id: SymbolId, text: &str) -> Result<SymbolId, SymbolCollision> {
        if let Some(existing) = self.parent.as_ref().and_then(|parent| parent.text(id)) {
            if existing != text {
                return Err(SymbolCollision {
                    id,
                    existing: Arc::from(existing),
                    incoming: Arc::from(text),
                });
            }
            return Ok(id);
        }
        match self.texts.entry(id) {
            std::collections::hash_map::Entry::Occupied(entry) => {
                if entry.get().as_ref() != text {
                    return Err(SymbolCollision {
                        id,
                        existing: Arc::clone(entry.get()),
                        incoming: Arc::from(text),
                    });
                }
            }
            std::collections::hash_map::Entry::Vacant(entry) => {
                entry.insert(Arc::from(text));
                self.local_spelling_bytes = self.local_spelling_bytes.saturating_add(arc_spelling_bytes(text));
            }
        }
        Ok(id)
    }

    pub fn text(&self, id: SymbolId) -> Option<&str> {
        self.shared_text(id).map(AsRef::as_ref)
    }

    /// Borrow the existing immutable spelling owner through the same overlay
    /// precedence as `text`. Shared storage is not symbol or revision authority.
    pub fn shared_text(&self, id: SymbolId) -> Option<&Arc<str>> {
        self.texts.get(&id).or_else(|| {
            self.parent
                .as_ref()
                .and_then(|parent| parent.shared_text(id))
        })
    }

    pub fn len(&self) -> usize {
        self.texts.len() + self.parent.as_ref().map_or(0, |parent| parent.len())
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Deterministic traversal for export and self-contained cache segments.
    /// True only for an immutable overlay retaining this exact original table.
    /// Interning consults every parent before insertion, so an overlay cannot
    /// replace an existing symbolic binding. No roster materialization occurs.
    pub fn is_overlay_of(&self,original:&Arc<Self>)->bool {
        let mut parent=self.parent.as_ref();
        while let Some(table)=parent {
            if Arc::ptr_eq(table,original) { return true; }
            parent=table.parent.as_ref();
        }
        false
    }

    pub fn ordered(&self) -> Vec<(SymbolId, &str)> {
        let mut symbols: Vec<_> = self
            .texts
            .iter()
            .map(|(&id, text)| (id, text.as_ref()))
            .collect();
        if let Some(parent) = &self.parent {
            symbols.extend(parent.ordered());
        }
        symbols.sort_unstable_by_key(|&(id, _)| id);
        symbols
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_spelling_delta_requires_same_bucket_capacity_and_only_intern_mutations() {
        let mut table = SymbolTable::default();
        let empty = table.local_storage();
        let a = table.intern("first").unwrap();
        assert_eq!(table.local_storage().spelling_delta_without_bucket_growth(empty), None);
        table.texts.reserve(2);
        let one = table.local_storage();
        table.intern("second").unwrap();
        table.intern("third").unwrap();
        let full = table.local_storage();
        assert_eq!(full.spelling_delta_without_bucket_growth(one),
            Some(arc_spelling_bytes("second") + arc_spelling_bytes("third")));
        table.intern("third").unwrap();
        assert_eq!(table.local_storage().spelling_delta_without_bucket_growth(full), Some(0));
        assert!(table.remove_local(a));
        table.intern("first").unwrap();
        assert_eq!(table.local_storage().spelling_delta_without_bucket_growth(full), None);
        let after = table.local_storage();
        let mut source = SymbolTable::default();
        source.intern("first").unwrap();
        source.intern("added through merge").unwrap();
        table.merge_from(&source).unwrap();
        assert_eq!(table.local_storage().spelling_delta_without_bucket_growth(after), None);
        let mut total = 0;
        table.try_visit_local_spellings(|text| {
            total += arc_spelling_bytes(text);
            Ok::<_, std::convert::Infallible>(())
        }).unwrap();
        assert_eq!(total, table.local_storage().spelling_bytes);
    }

    #[test]
    fn shared_text_lookup_preserves_multilevel_overlay_owners_and_absence() {
        let mut base = SymbolTable::default();
        let original = base.intern("/datum/base").unwrap();
        let base = Arc::new(base);
        let mut middle = SymbolTable::overlay(Arc::clone(&base));
        let inherited = middle.intern("/datum/base/child").unwrap();
        let middle = Arc::new(middle);
        let mut local = SymbolTable::overlay(Arc::clone(&middle));
        let added = local.intern("/datum/base/child/grandchild").unwrap();
        assert!(Arc::ptr_eq(
            local.shared_text(original).unwrap(),
            base.shared_text(original).unwrap()
        ));
        assert!(Arc::ptr_eq(
            local.shared_text(inherited).unwrap(),
            middle.shared_text(inherited).unwrap()
        ));
        assert!(Arc::ptr_eq(
            local.shared_text(added).unwrap(),
            &local.texts[&added]
        ));
        assert_eq!(
            local.text(inherited),
            local.shared_text(inherited).map(AsRef::as_ref)
        );
        assert!(local.shared_text(SymbolId::of("missing")).is_none());
        assert!(local.insert(original, "changed").is_err());
        local.retain_local(|_| false);
        assert!(local.shared_text(added).is_none());
        assert!(Arc::ptr_eq(
            local.shared_text(original).unwrap(),
            base.shared_text(original).unwrap()
        ));
    }

    #[test]
    fn certified_merge_shares_spellings_and_preserves_parent() {
        let mut base = SymbolTable::default();
        let a = base.intern("a").unwrap();
        let base = Arc::new(base);
        let mut source = SymbolTable::overlay(Arc::clone(&base));
        let b = source.intern("b").unwrap();
        let mut target = SymbolTable::overlay(Arc::clone(&base));
        target.merge_from(&source).unwrap();
        assert!(Arc::ptr_eq(&target.texts[&b], &source.texts[&b]));
        assert_eq!(target.texts.len(), 1);
        target.retain_local(|_| false);
        assert_eq!(target.text(a), Some("a"));
        assert_eq!(target.text(b), None);
        assert!(target.is_extension_of(&base));
    }

    #[test]
    fn certified_merge_collision_is_atomic_across_ancestry() {
        let mut target = SymbolTable::default();
        let collision = target.intern("existing").unwrap();
        let mut source_parent = SymbolTable::default();
        source_parent.intern("new ancestor").unwrap();
        let mut source = SymbolTable::overlay(Arc::new(source_parent));
        source.insert(collision, "different").unwrap();
        source.intern("new local").unwrap();
        let before = target.ordered();
        let before: Vec<_> = before
            .into_iter()
            .map(|(id, text)| (id, text.to_owned()))
            .collect();
        assert!(target.merge_from(&source).is_err());
        assert_eq!(
            target
                .ordered()
                .into_iter()
                .map(|(id, text)| (id, text.to_owned()))
                .collect::<Vec<_>>(),
            before
        );
    }

    #[test]
    fn certified_merge_reports_lowest_collision_id_deterministically() {
        let mut target = SymbolTable::default();
        let first = target.intern("first").unwrap();
        let second = target.intern("second").unwrap();
        let mut source = SymbolTable::default();
        source.insert(first, "other first").unwrap();
        source.insert(second, "other second").unwrap();
        assert_eq!(
            target.merge_from(&source).unwrap_err().id,
            first.min(second)
        );
        assert_eq!(target.len(), 2);
    }

    #[test]
    fn overlay_shares_backing_and_rejects_parent_collisions() {
        let mut base = SymbolTable::default();
        let a = base.intern("a").unwrap();
        let base = Arc::new(base);
        let mut local = SymbolTable::overlay(Arc::clone(&base));
        assert_eq!(local.intern("a").unwrap(), a);
        local.intern("b").unwrap();
        assert_eq!(base.len(), 1);
        assert_eq!(local.len(), 2);
        assert_eq!(local.text(a), Some("a"));
        assert!(local.is_extension_of(&base));
        assert!(!SymbolTable::default().is_extension_of(&base));
        assert!(local.insert(a, "different").is_err());
        assert_eq!(local.text(a), Some("a"));
        assert!(local.is_extension_of(&base));
        assert!(!SymbolTable::default().is_extension_of(&base));
        assert_eq!(local.ordered().len(), 2);
    }
    #[test]
    fn insertion_order_does_not_change_ids_or_export() {
        let mut first = SymbolTable::default();
        let mut second = SymbolTable::default();
        for text in ["/datum/example", "name", "", "é"] {
            first.intern(text).unwrap();
        }
        for text in ["é", "", "name", "/datum/example"] {
            second.intern(text).unwrap();
        }
        assert_eq!(first.ordered(), second.ordered());
        assert_eq!(first.text(SymbolId::of("é")), Some("é"));
        assert_eq!(first.len(), 4);
        first.intern("name").unwrap();
        assert_eq!(first.len(), 4);
    }

    #[test]
    fn collision_preserves_original_text() {
        let mut table = SymbolTable::default();
        let id = table.intern("original").unwrap();
        let error = table.insert(id, "different").unwrap_err();
        assert_eq!(error.existing.as_ref(), "original");
        assert_eq!(error.incoming.as_ref(), "different");
        assert_eq!(table.text(id), Some("original"));
        assert_eq!(table.len(), 1);
    }
}


#[cfg(test)]
mod spare_spelling_funding_tests {
    use super::*;
    #[test]
    fn spare_symbol_funding_is_before_mutation_and_borrows_actual_new_backing() {
        let mut table = SymbolTable::default();
        table.texts.reserve(8);
        let before = table.local_storage();
        let spelling = "/datum/exact_new_spelling";
        let expected = arc_spelling_bytes(spelling);
        assert_eq!(table.intern_funding_spare_spelling(spelling, |bytes| {
            assert_eq!(bytes, expected);
            Err("denied")
        }), Err("denied"));
        assert!(table.text(SymbolId::of(spelling)).is_none());
        let (id, funded) = table.intern_funding_spare_spelling(spelling, |bytes| {
            assert_eq!(bytes, expected);
            Ok::<_, ()>(())
        }).unwrap().unwrap();
        let funded_allocation = Arc::as_ptr(funded.unwrap());
        assert!(std::ptr::eq(funded_allocation, Arc::as_ptr(table.shared_text(id).unwrap())));
        assert_eq!(table.local_storage().spelling_delta_without_bucket_growth(before), Some(expected));
        let (repeat, funded) = table.intern_funding_spare_spelling(spelling, |_| -> Result<(), ()> {
            panic!("existing spelling must not reserve twice")
        }).unwrap().unwrap();
        assert_eq!(repeat, id);
        assert!(funded.is_none());
    }

    #[test]
    fn empty_table_bucket_growth_keeps_the_unmetered_legacy_fallback() {
        let mut table = SymbolTable::default();
        assert_eq!(table.texts.capacity(), 0);
        let (id, funded) = table.intern_funding_spare_spelling("first", |_| -> Result<(), ()> {
            panic!("the capacity proof cannot authorize bucket growth")
        }).unwrap().unwrap();
        assert!(funded.is_none());
        assert_eq!(table.text(id), Some("first"));
    }
}
