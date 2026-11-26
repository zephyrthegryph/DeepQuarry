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
