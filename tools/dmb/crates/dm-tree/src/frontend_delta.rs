//! What one front end revision changed against the one it was built from: files, declarations and procedure bodies, under
//! identities that stay the same across edits (doc/retained_frontend.md, "Front end edit floor", the delta).
//!
//! Identities:
//! * a file is its semantic path (the path as the project names it);
//! * a declaration is (file, owner type path, member name and kind, ordinal): the ordinal counts the earlier declarations
//!   of the same owner, name and kind in the same file, so an edit elsewhere in the file keeps it; a type declaration has
//!   no member name (kind `None`);
//! * a body is the identity of the declaration (proc or verb) it belongs to.
//!
//! Work is proportional to the edit: only the files that hold a region the plan did not copy verbatim from the previous
//! revision are compared (every declaration and body of a copied region is the previous revision's, at the same place in
//! the same file). Items of those files are matched by identity on both sides; an item in both whose content (the
//! declaration's own content digest, the body's expanded text) differs is `Changed`, one whose content is the same but
//! whose line moved is `Moved`. A revision built without a usable previous one, or whose edit reaches more than
//! `DELTA_FILE_LIMIT` files, has no delta (`ColdFrontend::delta` is `None`): every consumer recomputes.
use super::*;
use std::collections::BTreeSet;

/// One declaration's identity.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct DeclarationKey {
    pub file: Arc<str>,
    pub owner: Arc<str>,
    /// `None` for the type declaration itself.
    pub member: Option<(Arc<str>, MemberKind)>,
    pub ordinal: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Change {
    Added,
    Removed,
    /// The same identity with other content.
    Changed,
    /// The same identity and content at another line.
    Moved,
}

/// The change from revision `base` to revision `revision` of one session's front end.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct FrontendDelta {
    pub base: u64,
    pub revision: u64,
    /// Semantic paths of the files whose regions were planned or expanded again (an edited file, or one whose macro
    /// environment changed), sorted.
    pub files: Vec<Arc<str>>,
    /// Sorted by key.
    pub declarations: Vec<(DeclarationKey, Change)>,
    /// Procedure bodies, by the key of their declaration; sorted by key.
    pub bodies: Vec<(DeclarationKey, Change)>,
}

impl FrontendDelta {
    pub fn is_empty(&self) -> bool {
        self.files.is_empty() && self.declarations.is_empty() && self.bodies.is_empty()
    }
    /// This delta followed by `later` (whose base is this delta's revision): the change from this base to `later`'s
    /// revision. `None` when they do not chain.
    pub fn then(&self, later: &FrontendDelta) -> Option<FrontendDelta> {
        if later.base != self.revision {
            return None;
        }
        let mut files: BTreeSet<Arc<str>> = self.files.iter().cloned().collect();
        files.extend(later.files.iter().cloned());
        Some(FrontendDelta {
            base: self.base,
            revision: later.revision,
            files: files.into_iter().collect(),
            declarations: compose(&self.declarations, &later.declarations),
            bodies: compose(&self.bodies, &later.bodies),
        })
    }
}

/// `first` then `second`, per key.
fn compose(first: &[(DeclarationKey, Change)], second: &[(DeclarationKey, Change)]) -> Vec<(DeclarationKey, Change)> {
    use Change::*;
    let mut out: BTreeMap<DeclarationKey, Option<Change>> = first.iter().map(|(k, c)| (k.clone(), Some(*c))).collect();
    for (key, change) in second {
        let merged = match (out.get(key).copied().flatten(), *change) {
            (None, later) => Some(later),
            // Added, then anything but a removal: still new against the base.
            (Some(Added), Removed) => None,
            (Some(Added), _) => Some(Added),
            (Some(Removed), Added) => Some(Changed),
            (Some(Removed), later) => Some(later),
            (Some(Changed), Removed) => Some(Removed),
            (Some(Changed), _) => Some(Changed),
            (Some(Moved), Moved) => Some(Moved),
            (Some(Moved), later) => Some(later),
        };
        out.insert(key.clone(), merged);
    }
    out.into_iter().filter_map(|(k, c)| c.map(|c| (k, c))).collect()
}

/// One side's view of an item for the comparison: content digest and line.
struct Item {
    content: u128,
    line: u32,
}

/// Every declaration occurrence's identity in this revision (indexed by `OccurrenceId`; `None` for one the tree does not hold): the keys
/// the delta names, for a consumer that records which declarations it read and asks the next delta whether any of them changed.
pub fn declaration_keys(frontend: &ColdFrontend) -> Vec<Option<DeclarationKey>> {
    let tree = &frontend.snapshot.tree;
    let symbols = tree.symbols();
    let text = |id| symbols.text(id).map(Arc::<str>::from).unwrap_or_else(|| Arc::from(""));
    let mut ordinals: HashMap<(Arc<str>, Arc<str>, Option<(Arc<str>, MemberKind)>), u32> = HashMap::new();
    let mut out = Vec::with_capacity(frontend.declaration_regions.len());
    for (index, &region) in frontend.declaration_regions.iter().enumerate() {
        let occurrence = frontend.plan.regions[region as usize].occurrence;
        let file = Arc::clone(&frontend.plan.occurrences[occurrence].semantic_path);
        let (owner, member) = match tree.declarations().get(index) {
            Some(Target::Type(id)) => match tree.type_node(*id) {
                Some(node) => (text(node.path), None),
                None => {
                    out.push(None);
                    continue;
                }
            },
            Some(Target::Member(id)) => match tree.member(*id) {
                Some(node) => (tree.type_node(node.owner).map(|t| text(t.path)).unwrap_or_else(|| Arc::from("")), Some((text(node.name), node.kind))),
                None => {
                    out.push(None);
                    continue;
                }
            },
            None => {
                out.push(None);
                continue;
            }
        };
        let ordinal = ordinals.entry((Arc::clone(&file), Arc::clone(&owner), member.clone())).or_insert(0);
        out.push(Some(DeclarationKey { file, owner, member, ordinal: *ordinal }));
        *ordinal += 1;
    }
    out
}

/// The declarations and bodies of `files` in one revision, by identity.
fn items_of(
    frontend: &ColdFrontend,
    regions: &[u32],
    region_in: &dyn Fn(usize) -> bool,
) -> (BTreeMap<DeclarationKey, Item>, BTreeMap<DeclarationKey, Item>) {
    let tree = &frontend.snapshot.tree;
    let symbols = tree.symbols();
    let text = |id| symbols.text(id).map(Arc::<str>::from).unwrap_or_else(|| Arc::from(""));
    let mut ordinals: HashMap<(Arc<str>, Arc<str>, Option<(Arc<str>, MemberKind)>), u32> = HashMap::new();
    let mut declarations = BTreeMap::new();
    let mut keys = HashMap::new();
    for (index, &region) in regions.iter().enumerate() {
        if !region_in(region as usize) {
            continue;
        }
        let occurrence = frontend.plan.regions[region as usize].occurrence;
        let file = Arc::clone(&frontend.plan.occurrences[occurrence].semantic_path);
        let (owner, member, content) = match tree.declarations().get(index) {
            Some(Target::Type(id)) => match tree.type_node(*id) {
                Some(node) => (text(node.path), None, 0),
                None => continue,
            },
            Some(Target::Member(id)) => match tree.member(*id) {
                Some(node) => {
                    let owner = tree.type_node(node.owner).map(|t| text(t.path)).unwrap_or_else(|| Arc::from(""));
                    (owner, Some((text(node.name), node.kind)), node.content)
                }
                None => continue,
            },
            None => continue,
        };
        let ordinal = ordinals.entry((Arc::clone(&file), Arc::clone(&owner), member.clone())).or_insert(0);
        let key = DeclarationKey { file, owner, member, ordinal: *ordinal };
        *ordinal += 1;
        let line = frontend.snapshot.occurrences.get(OccurrenceId(index as u32)).map_or(0, |o| o.provenance.span.start);
        keys.insert(index, key.clone());
        declarations.insert(key, Item { content, line });
    }
    let mut bodies = BTreeMap::new();
    for body in frontend.bodies.iter() {
        let Some(key) = keys.get(&(body.declaration.0 as usize)) else {
            continue;
        };
        let span = body.expanded_span;
        let content = frontend
            .expanded
            .text
            .as_str()
            .get(span.start..span.end)
            .map_or(0, |text| xxhash_rust::xxh3::xxh3_128(text.as_bytes()));
        bodies.insert(key.clone(), Item { content, line: body.source.line as u32 });
    }
    (declarations, bodies)
}

fn diff(before: &BTreeMap<DeclarationKey, Item>, after: &BTreeMap<DeclarationKey, Item>) -> Vec<(DeclarationKey, Change)> {
    let mut out = Vec::new();
    for (key, now) in after {
        match before.get(key) {
            None => out.push((key.clone(), Change::Added)),
            Some(was) if was.content != now.content => out.push((key.clone(), Change::Changed)),
            Some(was) if was.line != now.line => out.push((key.clone(), Change::Moved)),
            Some(_) => {}
        }
    }
    for key in before.keys() {
        if !after.contains_key(key) {
            out.push((key.clone(), Change::Removed));
        }
    }
    out.sort();
    out
}

/// Above this many files a revision has no delta: comparing them would cost seconds (a widely read `#define`), and a consumer
/// that recomputes pays no more.
const DELTA_FILE_LIMIT: usize = 256;

/// The delta of `current` against `previous`, given which current regions are verbatim copies of which previous ones
/// (`PlanReuse::regions`). `None` when the plan copied nothing (a cold or fully re-planned revision: no delta is cheaper
/// than recomputing).
pub(super) fn compute(
    previous: &ColdFrontend,
    current: &ColdFrontend,
    copies: &[Option<usize>],
    base: u64,
    revision: u64,
) -> Option<FrontendDelta> {
    if copies.len() != current.plan.regions.len() || copies.iter().all(Option::is_none) {
        return None;
    }
    let mut copied_previous = vec![false; previous.plan.regions.len()];
    for &from in copies.iter().flatten() {
        *copied_previous.get_mut(from)? = true;
    }
    // A file is compared whole when any of its regions, on either side, is not a verbatim copy.
    let mut files: BTreeSet<Arc<str>> = BTreeSet::new();
    for (region, copy) in copies.iter().enumerate() {
        if copy.is_none() {
            files.insert(Arc::clone(&current.plan.occurrences[current.plan.regions[region].occurrence].semantic_path));
        }
    }
    for (region, copied) in copied_previous.iter().enumerate() {
        if !copied {
            files.insert(Arc::clone(&previous.plan.occurrences[previous.plan.regions[region].occurrence].semantic_path));
        }
    }
    // An edit that reaches this many files (a `#define` most of the tree reads) is cheaper to recompute than to compare.
    if files.len() > DELTA_FILE_LIMIT {
        return None;
    }
    let in_files = |frontend: &ColdFrontend| -> Vec<bool> {
        frontend
            .plan
            .regions
            .iter()
            .map(|region| files.contains(&frontend.plan.occurrences[region.occurrence].semantic_path))
            .collect()
    };
    let (current_in, previous_in) = (in_files(current), in_files(previous));
    let (before_declarations, before_bodies) =
        items_of(previous, &previous.declaration_regions, &|region| previous_in[region]);
    let (after_declarations, after_bodies) = items_of(current, &current.declaration_regions, &|region| current_in[region]);
    Some(FrontendDelta {
        base,
        revision,
        files: files.into_iter().collect(),
        declarations: diff(&before_declarations, &after_declarations),
        bodies: diff(&before_bodies, &after_bodies),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(owner: &str, name: &str) -> DeclarationKey {
        DeclarationKey { file: Arc::from("a.dm"), owner: Arc::from(owner), member: Some((Arc::from(name), MemberKind::Proc)), ordinal: 0 }
    }

    #[test]
    fn composed_deltas_say_what_changed_against_the_first_base() {
        let first = FrontendDelta {
            base: 1,
            revision: 2,
            files: vec![Arc::from("a.dm")],
            declarations: vec![(key("/a", "x"), Change::Added), (key("/a", "y"), Change::Moved), (key("/a", "z"), Change::Removed)],
            bodies: vec![(key("/a", "y"), Change::Changed)],
        };
        let second = FrontendDelta {
            base: 2,
            revision: 3,
            files: vec![Arc::from("b.dm")],
            declarations: vec![(key("/a", "x"), Change::Removed), (key("/a", "y"), Change::Changed), (key("/a", "z"), Change::Added)],
            bodies: vec![(key("/a", "y"), Change::Moved)],
        };
        let both = first.then(&second).unwrap();
        assert_eq!((both.base, both.revision), (1, 3));
        assert_eq!(both.files, vec![Arc::<str>::from("a.dm"), Arc::from("b.dm")]);
        assert_eq!(both.declarations, vec![(key("/a", "y"), Change::Changed), (key("/a", "z"), Change::Changed)]);
        assert_eq!(both.bodies, vec![(key("/a", "y"), Change::Changed)]);
        assert!(second.then(&first).is_none());
    }
}
