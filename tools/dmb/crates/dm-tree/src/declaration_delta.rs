//! Borrowed producer delta: stable source keys, never dense semantic IDs.
use super::*;

#[derive(Debug)]
pub struct DeclarationChange<'a> {
    pub key: DeclarationKey,
    pub previous: Option<&'a DeclarationRow>,
    pub current: Option<&'a DeclarationRow>,
}
#[derive(Debug)]
pub struct DeclarationDelta<'a> {
    pub changes: Vec<DeclarationChange<'a>>,
    pub order_changed: bool,
}
impl KeyedDeclarations {
    /// Exact row authority includes metadata, definition mode and parent clauses.
    /// The returned references cannot outlive either admitted source roster.
    pub fn delta_since<'a>(&'a self, previous: &'a Self) -> DeclarationDelta<'a> {
        let mut changes = Vec::new();
        // Both owner maps in owner order, stepped together: an owner whose contribution is the same allocation is skipped
        // without a lookup.
        let mut differing: Vec<(SymbolId, Option<&'a Arc<TypeContribution>>, Option<&'a Arc<TypeContribution>>)> = Vec::new();
        {
            let mut before = previous.owners.iter().peekable();
            let mut after = self.owners.iter().peekable();
            loop {
                match (before.peek(), after.peek()) {
                    (None, None) => break,
                    (Some((a, _)), Some((b, _))) if a == b => {
                        let (owner, old) = before.next().expect("peeked");
                        let (_, new) = after.next().expect("peeked");
                        if !Arc::ptr_eq(old, new) {
                            differing.push((*owner, Some(old), Some(new)));
                        }
                    }
                    (Some((a, _)), Some((b, _))) if a < b => {
                        let (owner, old) = before.next().expect("peeked");
                        differing.push((*owner, Some(old), None));
                    }
                    (Some(_), None) => {
                        let (owner, old) = before.next().expect("peeked");
                        differing.push((*owner, Some(old), None));
                    }
                    _ => {
                        let (owner, new) = after.next().expect("peeked");
                        differing.push((*owner, None, Some(new)));
                    }
                }
            }
        }
        for &(_, before, after) in &differing {
            let before: BTreeMap<_, _> = before
                .into_iter()
                .flat_map(|owner| owner.rows.iter())
                .map(|row| (row.key, row))
                .collect();
            let after: BTreeMap<_, _> = after
                .into_iter()
                .flat_map(|owner| owner.rows.iter())
                .map(|row| (row.key, row))
                .collect();
            let keys: std::collections::BTreeSet<_> =
                before.keys().chain(after.keys()).copied().collect();
            for key in keys {
                let old = before.get(&key).copied();
                let new = after.get(&key).copied();
                if old != new {
                    changes.push(DeclarationChange {
                        key,
                        previous: old,
                        current: new,
                    });
                }
            }
        }
        // The keys in roster order differ only where the handles differ or a handle names a row of a differing owner (an
        // unchanged owner's handle names the same row, so the same key).
        let changed_owners: Vec<SymbolId> = differing.iter().map(|(owner, _, _)| *owner).collect();
        let key_at = |index: &'a Self, handle: &DeclarationHandle| index.row(*handle).map(|row| row.key);
        let order_changed = self.roster.len() != previous.roster.len()
            || self.roster.iter().zip(previous.roster.iter()).any(|(now, before)| {
                (now != before || changed_owners.binary_search(&now.owner).is_ok())
                    && key_at(self, now) != key_at(previous, before)
            });
        DeclarationDelta {
            changes,
            order_changed,
        }
    }
}
