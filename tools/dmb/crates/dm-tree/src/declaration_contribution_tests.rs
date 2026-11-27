use super::*;
use crate::{DefinitionMode, MemberMetadata};
fn path(name: &str) -> SymbolId {
    SymbolId::of(name)
}
fn ty(owner: &str) -> Skeleton {
    Skeleton::Type {
        path: path(owner),
        explicit_parent: None,
    }
}
fn member(
    owner: &str,
    name: &str,
    kind: MemberKind,
    mode: DefinitionMode,
    content: u128,
) -> Skeleton {
    Skeleton::Member {
        owner: path(owner),
        name: path(name),
        kind,
        mode,
        metadata: Arc::new(MemberMetadata::default()),
        content,
    }
}
#[test]
fn one_owner_edit_shares_other_contributions_and_preserves_authored_interleaving() {
    let mut original = vec![
        ty("/a"),
        ty("/b"),
        member("/a", "p", MemberKind::Proc, DefinitionMode::Declare, 1),
        member("/b", "v", MemberKind::Var, DefinitionMode::Declare, 2),
        member("/a", "q", MemberKind::Proc, DefinitionMode::Declare, 3),
    ];
    let (first, _) = KeyedDeclarations::capture(None, &original).unwrap();
    if let Skeleton::Member { content, .. } = &mut original[2] {
        *content = 99;
    }
    let (second, changes) = KeyedDeclarations::capture(Some(&first), &original).unwrap();
    assert_eq!(changes.reused_owners, 1);
    assert_eq!(changes.changed_owners, 1);
    assert!(changes.same_handle_order && changes.structural_roster_unchanged);
    assert!(Arc::ptr_eq(
        first.owner(path("/b")).unwrap(),
        second.owner(path("/b")).unwrap()
    ));
    assert!(!Arc::ptr_eq(
        first.owner(path("/a")).unwrap(),
        second.owner(path("/a")).unwrap()
    ));
    assert!(Arc::ptr_eq(first.shared_roster(), second.shared_roster()));
    assert_eq!(
        second
            .ordered()
            .map(|row| row.skeleton.clone())
            .collect::<Vec<_>>(),
        original
    );
}
#[test]
fn stable_family_keys_do_not_confuse_namespaces_or_inserted_other_families() {
    let rows = vec![
        ty("/a"),
        member("/a", "p", MemberKind::Proc, DefinitionMode::Declare, 1),
        member("/a", "p", MemberKind::Verb, DefinitionMode::Declare, 2),
        member("/a", "p", MemberKind::Proc, DefinitionMode::Reopen, 3),
    ];
    let (first, _) = KeyedDeclarations::capture(None, &rows).unwrap();
    let prior_keys = first
        .ordered()
        .filter(|row| matches!(row.key.family, DeclarationFamily::Member { .. }))
        .map(|row| row.key)
        .collect::<Vec<_>>();
    assert_eq!(
        prior_keys
            .iter()
            .map(|key| key.occurrence)
            .collect::<Vec<_>>(),
        [0, 0, 1]
    );
    let mut changed = rows.clone();
    changed.insert(
        2,
        member("/a", "other", MemberKind::Var, DefinitionMode::Declare, 4),
    );
    let (second, changes) = KeyedDeclarations::capture(Some(&first), &changed).unwrap();
    assert!(!changes.structural_roster_unchanged);
    let current_keys = second
        .ordered()
        .filter(
            |row| matches!(row.key.family,DeclarationFamily::Member{name,..} if name==path("p")),
        )
        .map(|row| row.key)
        .collect::<Vec<_>>();
    assert_eq!(prior_keys, current_keys);
}
#[test]
fn same_handles_never_certify_parent_mode_or_global_order_changes() {
    let rows = vec![
        ty("/a"),
        ty("/b"),
        member("/a", "p", MemberKind::Proc, DefinitionMode::Declare, 1),
    ];
    let (first, _) = KeyedDeclarations::capture(None, &rows).unwrap();
    let mut changed = rows.clone();
    if let Skeleton::Type {
        explicit_parent, ..
    } = &mut changed[0]
    {
        *explicit_parent = Some(path("/b"));
    }
    let (parent, changes) = KeyedDeclarations::capture(Some(&first), &changed).unwrap();
    assert!(changes.same_handle_order);
    assert!(!changes.structural_roster_unchanged);
    assert!(!first.same_structure(&parent));
    changed = rows.clone();
    if let Skeleton::Member { mode, .. } = &mut changed[2] {
        *mode = DefinitionMode::Implicit;
    }
    let (_, changes) = KeyedDeclarations::capture(Some(&first), &changed).unwrap();
    assert!(changes.same_handle_order && !changes.structural_roster_unchanged);
    changed = rows.clone();
    changed.swap(0, 1);
    let (reordered, changes) = KeyedDeclarations::capture(Some(&first), &changed).unwrap();
    assert_eq!(changes.reused_owners, 2);
    assert!(!changes.same_handle_order && !changes.structural_roster_unchanged);
    assert_eq!(
        reordered
            .ordered()
            .rev()
            .map(|row| row.skeleton.clone())
            .collect::<Vec<_>>(),
        changed.into_iter().rev().collect::<Vec<_>>()
    );
}
#[test]
fn removal_retains_only_current_owners_and_old_shared_snapshot_remains_valid() {
    let rows = vec![ty("/a"), ty("/b")];
    let (first, _) = KeyedDeclarations::capture(None, &rows).unwrap();
    let (second, changes) = KeyedDeclarations::capture(Some(&first), &rows[..1]).unwrap();
    assert_eq!(changes.removed_owners, 1);
    assert!(second.owner(path("/b")).is_none());
    assert_eq!(first.len(), 2);
    assert_eq!(second.len(), 1);
    assert!(second
        .row(DeclarationHandle {
            owner: path("/a"),
            row: u32::MAX
        })
        .is_none());
    let (empty, changes) = KeyedDeclarations::capture(Some(&second), &[]).unwrap();
    assert!(empty.is_empty());
    assert_eq!(changes.removed_owners, 1);
}

#[test]
fn scalar_owner_shape_is_shared_across_metadata_content_changes() {
    let mut rows = vec![
        ty("/a"),
        member("/a", "x", MemberKind::Var, DefinitionMode::Declare, 1),
    ];
    let (first, _) = KeyedDeclarations::capture(None, &rows).unwrap();
    if let Skeleton::Member { content, .. } = &mut rows[1] {
        *content = 2;
    }
    let (second, _) = KeyedDeclarations::capture(Some(&first), &rows).unwrap();
    let first = first.owner(path("/a")).unwrap();
    let second = second.owner(path("/a")).unwrap();
    assert!(!Arc::ptr_eq(first, second));
    assert!(Arc::ptr_eq(first.shared_shape(), second.shared_shape()));
    assert_eq!(first.shared_shape()[1].mode, Some(DefinitionMode::Declare));
    if let Skeleton::Member { mode, .. } = &mut rows[1] {
        *mode = DefinitionMode::Implicit;
    }
    let (third, _) = KeyedDeclarations::capture(None, &rows).unwrap();
    assert_ne!(
        second.shared_shape().as_ref(),
        third.owner(path("/a")).unwrap().shared_shape().as_ref()
    );
}
#[test]
fn leaf_capture_equals_a_full_capture_through_edits() {
    let leaf = |rows: Vec<Skeleton>| Arc::new(rows);
    let flat = |leaves: &[Arc<Vec<Skeleton>>]| leaves.iter().flat_map(|leaf| leaf.iter().cloned()).collect::<Vec<_>>();
    let same = |a: &KeyedDeclarations, b: &KeyedDeclarations| {
        a.roster() == b.roster()
            && a.owners().len() == b.owners().len()
            && a.owners().zip(b.owners()).all(|((ao, av), (bo, bv))| {
                ao == bo && av.digest() == bv.digest() && av.rows() == bv.rows() && av.shared_shape() == bv.shared_shape()
            })
    };
    let mut leaves = vec![
        leaf(vec![ty("/a"), member("/a", "p", MemberKind::Proc, DefinitionMode::Declare, 1)]),
        leaf(vec![ty("/b"), member("/b", "v", MemberKind::Var, DefinitionMode::Declare, 2)]),
        leaf(vec![member("/a", "q", MemberKind::Proc, DefinitionMode::Declare, 3), member("/b", "w", MemberKind::Var, DefinitionMode::Declare, 4)]),
        leaf(vec![]),
        leaf(vec![ty("/c"), member("/a", "p", MemberKind::Proc, DefinitionMode::Override, 5)]),
    ];
    let (mut previous, _) = KeyedDeclarations::capture(None, &flat(&leaves)).unwrap();
    let edits: Vec<Box<dyn Fn(&mut Vec<Arc<Vec<Skeleton>>>)>> = vec![
        // A new var in the middle leaf.
        Box::new(|leaves| {
            let mut rows = leaves[1].as_ref().clone();
            rows.push(member("/b", "probe", MemberKind::Var, DefinitionMode::Declare, 9));
            leaves[1] = Arc::new(rows);
        }),
        // Its removal.
        Box::new(|leaves| {
            let mut rows = leaves[1].as_ref().clone();
            rows.pop();
            leaves[1] = Arc::new(rows);
        }),
        // A new proc on /a before its other rows' later occurrences, and a content edit elsewhere (two runs).
        Box::new(|leaves| {
            let mut rows = leaves[0].as_ref().clone();
            rows.push(member("/a", "p", MemberKind::Proc, DefinitionMode::Override, 7));
            leaves[0] = Arc::new(rows);
            let mut rows = leaves[4].as_ref().clone();
            if let Skeleton::Member { content, .. } = &mut rows[1] {
                *content = 55;
            }
            leaves[4] = Arc::new(rows);
        }),
        // A row moves to another owner.
        Box::new(|leaves| {
            let mut rows = leaves[2].as_ref().clone();
            rows[0] = member("/c", "q", MemberKind::Proc, DefinitionMode::Declare, 3);
            leaves[2] = Arc::new(rows);
        }),
        // A new leaf with a new owner, then an owner's last rows removed with their leaf.
        Box::new(|leaves| leaves.insert(2, Arc::new(vec![ty("/d"), member("/d", "x", MemberKind::Var, DefinitionMode::Declare, 8)]))),
        Box::new(|leaves| {
            leaves.remove(2);
        }),
        Box::new(|leaves| {
            leaves.remove(4);
            leaves.remove(2);
        }),
        // Equal content in another allocation: nothing changes.
        Box::new(|leaves| leaves[0] = Arc::new(leaves[0].as_ref().clone())),
    ];
    for (step, edit) in edits.iter().enumerate() {
        let before = leaves.clone();
        edit(&mut leaves);
        let (full, full_changes) = KeyedDeclarations::capture(Some(&previous), &flat(&leaves)).unwrap();
        let (incremental, changes) = KeyedDeclarations::capture_leaves(&previous, &before, &leaves)
            .expect("a small edit is captured from its leaves")
            .unwrap();
        assert!(same(&incremental, &full), "step {step}");
        assert_eq!(changes, full_changes, "step {step}");
        for (owner, value) in full.owners() {
            assert_eq!(
                Arc::ptr_eq(value, previous.owner(*owner).unwrap_or(value)),
                Arc::ptr_eq(incremental.owner(*owner).unwrap(), previous.owner(*owner).unwrap_or(incremental.owner(*owner).unwrap())),
                "step {step}: sharing of {owner:?}"
            );
        }
        assert_eq!(Arc::ptr_eq(full.shared_roster(), previous.shared_roster()), Arc::ptr_eq(incremental.shared_roster(), previous.shared_roster()), "step {step}");
        previous = incremental;
    }
}
