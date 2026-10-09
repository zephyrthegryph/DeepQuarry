//! Exact immutable declaration contributions, separated from the global authored
//! roster. Keys describe source families, never resolved member/output IDs.
use crate::{MemberKind, Skeleton};
use dm_ir::SymbolId;
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum DeclarationFamily {
    Type,
    Member { name: SymbolId, kind: MemberKind },
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct DeclarationKey {
    pub owner: SymbolId,
    pub family: DeclarationFamily,
    /// Authored occurrence within this owner's family. Resolution still issues
    /// normalized callable occurrences through the existing semantic core.
    pub occurrence: u32,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DeclarationRow {
    pub key: DeclarationKey,
    pub skeleton: Skeleton,
}
#[derive(Clone, Debug)]
pub struct TypeContribution {
    owner: SymbolId,
    rows: Arc<[DeclarationRow]>,
}
impl TypeContribution {
    pub fn owner(&self) -> SymbolId {
        self.owner
    }
    pub fn rows(&self) -> &[DeclarationRow] {
        &self.rows
    }
    pub fn shared_rows(&self) -> &Arc<[DeclarationRow]> {
        &self.rows
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DeclarationHandle {
    pub owner: SymbolId,
    pub row: u32,
}
#[derive(Clone, Debug, Default)]
pub struct KeyedDeclarations {
    owners: BTreeMap<SymbolId, Arc<TypeContribution>>,
    roster: Arc<[DeclarationHandle]>,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct ContributionChanges {
    pub reused_owners: usize,
    pub changed_owners: usize,
    pub removed_owners: usize,
    pub same_handle_order: bool,
    pub structural_roster_unchanged: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ContributionError {
    TooManyOwnerDeclarations(SymbolId),
    TooManyFamilyDeclarations(SymbolId),
}
fn owner(skeleton: &Skeleton) -> SymbolId {
    match skeleton {
        Skeleton::Type { path, .. } => *path,
        Skeleton::Member { owner, .. } => *owner,
    }
}
fn family(skeleton: &Skeleton) -> DeclarationFamily {
    match skeleton {
        Skeleton::Type { .. } => DeclarationFamily::Type,
        Skeleton::Member { name, kind, .. } => DeclarationFamily::Member {
            name: *name,
            kind: *kind,
        },
    }
}
impl KeyedDeclarations {
    /// Build a new current roster. No old coordinates, symbols, or tree authority
    /// are retained here. Unchanged owners share only after exact row equality.
    pub fn capture(
        previous: Option<&Self>,
        skeletons: &[Skeleton],
    ) -> Result<(Self, ContributionChanges), ContributionError> {
        let mut grouped = BTreeMap::<SymbolId, Vec<usize>>::new();
        let mut roster = Vec::with_capacity(skeletons.len());
        for (index, skeleton) in skeletons.iter().enumerate() {
            let owner = owner(skeleton);
            let group = grouped.entry(owner).or_default();
            let row = u32::try_from(group.len())
                .map_err(|_| ContributionError::TooManyOwnerDeclarations(owner))?;
            roster.push(DeclarationHandle { owner, row });
            group.push(index);
        }
        let mut owners = BTreeMap::new();
        let mut changes = ContributionChanges::default();
        for (owner, indices) in grouped {
            if let Some(prior) = previous
                .and_then(|previous| previous.owners.get(&owner))
                .filter(|prior| {
                    prior.rows.len() == indices.len()
                        && prior
                            .rows
                            .iter()
                            .zip(&indices)
                            .all(|(row, index)| row.skeleton == skeletons[*index])
                })
            {
                owners.insert(owner, prior.clone());
                changes.reused_owners += 1;
                continue;
            }
            let mut occurrences = HashMap::<DeclarationFamily, u32>::new();
            let mut rows = Vec::with_capacity(indices.len());
            for index in indices {
                let skeleton = &skeletons[index];
                let family = family(skeleton);
                let occurrence = occurrences.entry(family).or_default();
                let key = DeclarationKey {
                    owner,
                    family,
                    occurrence: *occurrence,
                };
                *occurrence = occurrence
                    .checked_add(1)
                    .ok_or(ContributionError::TooManyFamilyDeclarations(owner))?;
                rows.push(DeclarationRow {
                    key,
                    skeleton: skeleton.clone(),
                });
            }
            owners.insert(
                owner,
                Arc::new(TypeContribution {
                    owner,
                    rows: rows.into(),
                }),
            );
            changes.changed_owners += 1;
        }
        if let Some(previous) = previous {
            changes.removed_owners = previous
                .owners
                .keys()
                .filter(|owner| !owners.contains_key(owner))
                .count();
            changes.same_handle_order = previous.roster.as_ref() == roster;
        }
        let roster = match previous.filter(|previous| previous.roster.as_ref() == roster) {
            Some(previous) => previous.roster.clone(),
            None => roster.into(),
        };
        let current = Self { owners, roster };
        changes.structural_roster_unchanged =
            previous.is_some_and(|previous| previous.same_structure(&current));
        Ok((current, changes))
    }
    pub fn owner(&self, owner: SymbolId) -> Option<&Arc<TypeContribution>> {
        self.owners.get(&owner)
    }
    pub fn owners(&self) -> impl ExactSizeIterator<Item = (&SymbolId, &Arc<TypeContribution>)> {
        self.owners.iter()
    }
    pub fn roster(&self) -> &[DeclarationHandle] {
        &self.roster
    }
    pub fn shared_roster(&self) -> &Arc<[DeclarationHandle]> {
        &self.roster
    }
    pub fn len(&self) -> usize {
        self.roster.len()
    }
    pub fn is_empty(&self) -> bool {
        self.roster.is_empty()
    }
    pub fn row(&self, handle: DeclarationHandle) -> Option<&DeclarationRow> {
        self.owners
            .get(&handle.owner)?
            .rows
            .get(handle.row as usize)
    }
    pub fn ordered(&self) -> impl ExactSizeIterator<Item = &DeclarationRow> + DoubleEndedIterator {
        self.roster.iter().map(|handle| {
            self.row(*handle)
                .expect("private roster references its exact contribution")
        })
    }
    /// Borrow the exact authored sequence without constructing a flat roster.
    pub fn skeletons(
        &self,
    ) -> impl ExactSizeIterator<Item = &Skeleton> + DoubleEndedIterator + Clone {
        self.roster.iter().map(|handle| {
            &self
                .row(*handle)
                .expect("private roster references its exact contribution")
                .skeleton
        })
    }
    /// Exact structure includes owner/family order, definition modes and parent
    /// clauses. Stable handles alone are insufficient after a row insertion.
    pub fn same_structure(&self, other: &Self) -> bool {
        self.roster == other.roster
            && self.ordered().zip(other.ordered()).all(|(a, b)| {
                a.key == b.key
                    && match (&a.skeleton, &b.skeleton) {
                        (
                            Skeleton::Type {
                                path: a,
                                explicit_parent: ap,
                            },
                            Skeleton::Type {
                                path: b,
                                explicit_parent: bp,
                            },
                        ) => a == b && ap == bp,
                        (
                            Skeleton::Member {
                                owner: a,
                                name: an,
                                kind: ak,
                                mode: am,
                                ..
                            },
                            Skeleton::Member {
                                owner: b,
                                name: bn,
                                kind: bk,
                                mode: bm,
                                ..
                            },
                        ) => a == b && an == bn && ak == bk && am == bm,
                        _ => false,
                    }
            })
    }
}

#[cfg(test)]
#[path = "declaration_contribution_tests.rs"]
mod tests;
