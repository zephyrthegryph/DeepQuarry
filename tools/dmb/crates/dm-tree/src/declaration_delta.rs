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
        let owners: std::collections::BTreeSet<_> = self
            .owners
            .keys()
            .chain(previous.owners.keys())
            .copied()
            .collect();
        for owner in owners {
            let before = previous.owners.get(&owner);
            let after = self.owners.get(&owner);
            if matches!((before, after), (Some(a), Some(b)) if Arc::ptr_eq(a, b)) {
                continue;
            }
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
        DeclarationDelta {
            changes,
            order_changed: !self
                .ordered()
                .map(|row| row.key)
                .eq(previous.ordered().map(|row| row.key)),
        }
    }
}
