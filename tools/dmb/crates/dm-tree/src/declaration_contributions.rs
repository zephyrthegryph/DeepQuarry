//! Exact immutable declaration contributions, separated from the global authored
//! roster. Keys describe source families, never resolved member/output IDs.
pub(crate) mod authored;
#[path = "declaration_delta.rs"]
mod delta;
use crate::{MemberKind, Skeleton};
pub use delta::{DeclarationChange, DeclarationDelta};
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
    metadata_fingerprint: u128,
}
impl DeclarationRow {
    pub(crate) fn metadata_fingerprint(&self) -> u128 {
        self.metadata_fingerprint
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DeclarationShape {
    pub key: DeclarationKey,
    pub mode: Option<crate::DefinitionMode>,
    pub explicit_parent: Option<SymbolId>,
}
#[derive(Clone, Debug)]
pub struct TypeContribution {
    owner: SymbolId,
    rows: Arc<[DeclarationRow]>,
    shape: Arc<[DeclarationShape]>,
    /// The identity digest of `rows` (`tree_identity::owner_digest`): the tree's declaration identity combines one per owner, so a
    /// request recomputes only the owners it changed.
    digest: u128,
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
    pub fn shared_shape(&self) -> &Arc<[DeclarationShape]> {
        &self.shape
    }
    pub(crate) fn digest(&self) -> u128 {
        self.digest
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
/// The contribution of `owner` with these rows (in authored order): `prior` itself when its rows are equal (`true`: reused),
/// else a new one that takes each unchanged row's metadata fingerprint and an equal shape from `prior`.
fn owner_contribution(
    owner: SymbolId,
    skeletons: &[&Skeleton],
    prior: Option<&Arc<TypeContribution>>,
) -> Result<(Arc<TypeContribution>, bool), ContributionError> {
    if let Some(prior) = prior.filter(|prior| {
        prior.rows.len() == skeletons.len()
            && prior.rows.iter().zip(skeletons).all(|(row, skeleton)| row.skeleton == **skeleton)
    }) {
        return Ok((Arc::clone(prior), true));
    }
    let prior_rows: BTreeMap<_, _> =
        prior.into_iter().flat_map(|owner| owner.rows.iter()).map(|row| (row.key, row)).collect();
    let mut occurrences = HashMap::<DeclarationFamily, u32>::new();
    let mut rows = Vec::with_capacity(skeletons.len());
    for skeleton in skeletons {
        let skeleton = *skeleton;
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
        let metadata_fingerprint = prior_rows
            .get(&key)
            .filter(|row| row.skeleton == *skeleton)
            .map(|row| row.metadata_fingerprint)
            .unwrap_or_else(|| match skeleton {
                Skeleton::Member { metadata, .. } => crate::metadata_fingerprint(metadata),
                Skeleton::Type { .. } => 0,
            });
        rows.push(DeclarationRow {
            key,
            skeleton: skeleton.clone(),
            metadata_fingerprint,
        });
    }
    let shape: Vec<_> = rows
        .iter()
        .map(|row| {
            let (mode, explicit_parent) = match &row.skeleton {
                Skeleton::Type {
                    explicit_parent, ..
                } => (None, *explicit_parent),
                Skeleton::Member { mode, .. } => (Some(*mode), None),
            };
            DeclarationShape {
                key: row.key,
                mode,
                explicit_parent,
            }
        })
        .collect();
    let shape = prior
        .filter(|prior| prior.shape.as_ref() == shape)
        .map(|prior| Arc::clone(&prior.shape))
        .unwrap_or_else(|| shape.into());
    let digest = crate::tree_identity::owner_digest(&rows);
    Ok((
        Arc::new(TypeContribution {
            owner,
            rows: rows.into(),
            shape,
            digest,
        }),
        false,
    ))
}
impl KeyedDeclarations {
    /// Build a new current roster. No old coordinates, symbols, or tree authority
    /// are retained here. Unchanged owners share only after exact row equality.
    pub fn capture(
        previous: Option<&Self>,
        skeletons: &[Skeleton],
    ) -> Result<(Self, ContributionChanges), ContributionError> {
        Self::capture_view(previous, skeletons.into())
    }
    pub(crate) fn capture_view(
        previous: Option<&Self>,
        skeletons: crate::skeleton_roster::SkeletonView<'_>,
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
            let rows: Vec<&Skeleton> = indices.iter().map(|&index| &skeletons[index]).collect();
            let (value, reused) =
                owner_contribution(owner, &rows, previous.and_then(|previous| previous.owners.get(&owner)))?;
            owners.insert(owner, value);
            if reused {
                changes.reused_owners += 1;
            } else {
                changes.changed_owners += 1;
            }
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
    /// `capture_view` of `leaves` when the previous roster was captured from `previous_leaves` (the same rows, leaf for leaf):
    /// only the leaves that differ are read, so the work is the changed rows', the rows of the owners they touch, and one pass
    /// over the handles (no row is compared or hashed again). `None` when the leaves changed in more than a few places or touch
    /// many owners: the caller captures in full. The answer equals `capture_view`'s (`DMB_FRONTEND_VERIFY=1` checks it).
    pub(crate) fn capture_leaves(
        previous: &Self,
        previous_leaves: &[Arc<Vec<Skeleton>>],
        leaves: &[Arc<Vec<Skeleton>>],
    ) -> Option<Result<(Self, ContributionChanges), ContributionError>> {
        const MAX_CHANGED_ROWS: usize = 16 * 1024;
        const MAX_OWNERS: usize = 256;
        let same = |a: &Arc<Vec<Skeleton>>, b: &Arc<Vec<Skeleton>>| Arc::ptr_eq(a, b) || a == b;
        // Changed runs of leaves: (old leaf range, new leaf range).
        let mut runs: Vec<(std::ops::Range<usize>, std::ops::Range<usize>)> = Vec::new();
        if previous_leaves.len() == leaves.len() {
            let mut index = 0;
            while index < leaves.len() {
                if same(&previous_leaves[index], &leaves[index]) {
                    index += 1;
                    continue;
                }
                let start = index;
                while index < leaves.len() && !same(&previous_leaves[index], &leaves[index]) {
                    index += 1;
                }
                runs.push((start..index, start..index));
                if runs.len() > 64 {
                    return None;
                }
            }
        } else {
            let shorter = previous_leaves.len().min(leaves.len());
            let prefix = (0..shorter).take_while(|&i| same(&previous_leaves[i], &leaves[i])).count();
            let suffix = (0..shorter - prefix)
                .take_while(|&i| same(&previous_leaves[previous_leaves.len() - 1 - i], &leaves[leaves.len() - 1 - i]))
                .count();
            runs.push((prefix..previous_leaves.len() - suffix, prefix..leaves.len() - suffix));
        }
        let starts_of = |leaves: &[Arc<Vec<Skeleton>>]| -> Vec<usize> {
            let mut starts = Vec::with_capacity(leaves.len() + 1);
            let mut at = 0;
            for leaf in leaves {
                starts.push(at);
                at += leaf.len();
            }
            starts.push(at);
            starts
        };
        let (old_starts, new_starts) = (starts_of(previous_leaves), starts_of(leaves));
        if old_starts.last() != Some(&previous.roster.len()) {
            return None;
        }
        // Row ranges of each run, and the owners they touch.
        let mut row_runs = Vec::with_capacity(runs.len());
        let mut affected: Vec<SymbolId> = Vec::new();
        let mut changed_rows = 0;
        for (old, new) in &runs {
            let old_rows = old_starts[old.start]..old_starts[old.end];
            changed_rows += old_rows.len() + (new_starts[new.end] - new_starts[new.start]);
            if changed_rows > MAX_CHANGED_ROWS {
                return None;
            }
            affected.extend(previous.roster[old_rows.clone()].iter().map(|handle| handle.owner));
            affected.extend(leaves[new.clone()].iter().flat_map(|leaf| leaf.iter()).map(owner));
            row_runs.push((old_rows, new.clone()));
        }
        affected.sort_unstable();
        affected.dedup();
        if affected.len() > MAX_OWNERS {
            return None;
        }
        // One pass over the handles: an unaffected owner's handle is the previous one; an affected owner's rows are
        // renumbered and collected (a previous row by its index, a new row by reference).
        enum Source<'a> {
            Old(u32),
            New(&'a Skeleton),
        }
        let mut sources: Vec<Vec<Source<'_>>> = (0..affected.len()).map(|_| Vec::new()).collect();
        let total = new_starts.last().copied().unwrap_or(0);
        let mut roster: Vec<DeclarationHandle> = Vec::with_capacity(total);
        let mut identical = total == previous.roster.len();
        let mut cursor = 0;
        let mut copy_old = |roster: &mut Vec<DeclarationHandle>,
                            sources: &mut Vec<Vec<Source<'_>>>,
                            identical: &mut bool,
                            range: std::ops::Range<usize>|
         -> Result<(), ContributionError> {
            for &handle in &previous.roster[range] {
                let handle = match affected.binary_search(&handle.owner) {
                    Ok(slot) => {
                        let row = u32::try_from(sources[slot].len())
                            .map_err(|_| ContributionError::TooManyOwnerDeclarations(handle.owner))?;
                        sources[slot].push(Source::Old(handle.row));
                        DeclarationHandle { owner: handle.owner, row }
                    }
                    Err(_) => handle,
                };
                if *identical && previous.roster.get(roster.len()) != Some(&handle) {
                    *identical = false;
                }
                roster.push(handle);
            }
            Ok(())
        };
        for (old_rows, new_leaves) in &row_runs {
            if let Err(error) = copy_old(&mut roster, &mut sources, &mut identical, cursor..old_rows.start) {
                return Some(Err(error));
            }
            for skeleton in leaves[new_leaves.clone()].iter().flat_map(|leaf| leaf.iter()) {
                let owner = owner(skeleton);
                let slot = affected.binary_search(&owner).ok()?;
                let row = match u32::try_from(sources[slot].len()) {
                    Ok(row) => row,
                    Err(_) => return Some(Err(ContributionError::TooManyOwnerDeclarations(owner))),
                };
                sources[slot].push(Source::New(skeleton));
                let handle = DeclarationHandle { owner, row };
                if identical && previous.roster.get(roster.len()) != Some(&handle) {
                    identical = false;
                }
                roster.push(handle);
            }
            cursor = old_rows.end;
        }
        if let Err(error) = copy_old(&mut roster, &mut sources, &mut identical, cursor..previous.roster.len()) {
            return Some(Err(error));
        }
        let mut owners = previous.owners.clone();
        let mut changes = ContributionChanges { same_handle_order: identical, ..Default::default() };
        let mut structure_kept = identical;
        for (&owner, sources) in affected.iter().zip(&sources) {
            let prior = previous.owners.get(&owner);
            if sources.is_empty() {
                owners.remove(&owner);
                changes.removed_owners += usize::from(prior.is_some());
                structure_kept = false;
                continue;
            }
            let mut rows = Vec::with_capacity(sources.len());
            for source in sources {
                rows.push(match source {
                    Source::Old(index) => &prior?.rows.get(*index as usize)?.skeleton,
                    Source::New(skeleton) => *skeleton,
                });
            }
            let (value, reused) = match owner_contribution(owner, &rows, prior) {
                Ok(result) => result,
                Err(error) => return Some(Err(error)),
            };
            if !reused {
                changes.changed_owners += 1;
                structure_kept &= prior.is_some_and(|prior| same_owner_structure(prior, &value));
            }
            owners.insert(owner, value);
        }
        changes.reused_owners = owners.len() - changes.changed_owners;
        changes.structural_roster_unchanged = structure_kept;
        let roster = if identical { previous.roster.clone() } else { roster.into() };
        Some(Ok((Self { owners, roster }, changes)))
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
        self.roster == other.roster && self.ordered().zip(other.ordered()).all(|(a, b)| same_row_structure(a, b))
    }
}
/// `same_structure` for one owner whose rows are in the same roster positions.
fn same_owner_structure(a: &TypeContribution, b: &TypeContribution) -> bool {
    a.rows.len() == b.rows.len() && a.rows.iter().zip(b.rows.iter()).all(|(a, b)| same_row_structure(a, b))
}
fn same_row_structure(a: &DeclarationRow, b: &DeclarationRow) -> bool {
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
}

#[cfg(test)]
#[path = "declaration_contribution_tests.rs"]
mod tests;
