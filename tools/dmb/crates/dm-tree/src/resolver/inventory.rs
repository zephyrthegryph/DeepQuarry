//! Independent resolved storage facts, merged in the original declaration order.
use super::*;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Mutex,
};
#[derive(Clone, Copy)]
struct Fact {
    name: SymbolId,
    slot: Option<(SymbolId, SymbolId)>,
    instance: bool,
}
fn fact(tree: &SemanticTree, id: MemberId) -> Option<Fact> {
    let member = &tree.members[id.index()];
    if member.kind != MemberKind::Var {
        return None;
    }
    let storage = tree.variable_storage_for_member(id);
    Some(Fact {
        name: member.name,
        slot: match &storage {
            M::Slot { owner, name, .. } => Some((*owner, *name)),
            _ => None,
        },
        instance: matches!(storage, M::InstanceField { .. }),
    })
}
type IndexedFactChunk = Vec<(usize, Fact)>;
type FactSlot = Mutex<Option<IndexedFactChunk>>;
fn facts(tree: &SemanticTree, executor: Option<&dm_exec::BuildExecutor>) -> Vec<Option<Fact>> {
    let Some(executor) = executor else {
        return (0..tree.members.len())
            .map(|index| fact(tree, MemberId(index as u32)))
            .collect();
    };
    let next = AtomicUsize::new(0);
    let groups: Vec<FactSlot> = (0..tree.types.len()).map(|_| Mutex::new(None)).collect();
    executor.scope(|scope| {
        for _ in 0..executor.workers().min(tree.types.len()) {
            let next = &next;
            let groups = &groups;
            scope.spawn(move |_| {
                let _stage = dm_profile::stage("frontend.tree_resolution");
                loop {
                    let index = next.fetch_add(1, Ordering::Relaxed);
                    let Some(node) = tree.types.get(index) else {
                        break;
                    };
                    let output = node
                        .members
                        .iter()
                        .filter_map(|&id| fact(tree, id).map(|fact| (id.index(), fact)))
                        .collect();
                    *groups[index]
                        .lock()
                        .expect("tree inventory result lock poisoned") = Some(output);
                }
            });
        }
    });
    let mut ordered = vec![None; tree.members.len()];
    for group in groups {
        for (index, fact) in group
            .into_inner()
            .expect("tree inventory result lock poisoned")
            .expect("tree inventory worker did not publish type")
        {
            ordered[index] = Some(fact);
        }
    }
    ordered
}
pub(super) fn rebuild(tree: &mut SemanticTree, executor: Option<&dm_exec::BuildExecutor>) {
    let facts = facts(tree, executor);
    let mut unique = HashMap::new();
    let mut non_unique = HashSet::new();
    let mut shared = HashMap::new();
    let mut add = |name, slot| {
        unique
            .entry(name)
            .and_modify(|previous| {
                if *previous != slot {
                    *previous = None;
                }
            })
            .or_insert(slot);
    };
    for Fact {
        name,
        slot,
        instance,
    } in facts.into_iter().flatten()
    {
        if instance {
            non_unique.insert(name);
        }
        if let Some((owner, _)) = slot {
            if shared
                .insert(name, owner)
                .is_some_and(|previous| previous != owner)
            {
                non_unique.insert(name);
            }
        }
        add(name, slot);
    }
    for entry in tree.inventory.intrinsic.iter() {
        if entry.kind == MemberKind::Var {
            let authored = tree
                .lookup_type(entry.owner)
                .and_then(|owner| tree.direct.get(&(owner, entry.name, MemberKind::Var)))
                .is_some();
            if !authored {
                if entry.instance_storage_proven {
                    non_unique.insert(entry.name);
                }
                if let Some(owner) = entry.shared_owner {
                    if shared
                        .insert(entry.name, owner)
                        .is_some_and(|previous| previous != owner)
                    {
                        non_unique.insert(entry.name);
                    }
                }
                add(
                    entry.name,
                    entry.shared_owner.map(|owner| (owner, entry.name)),
                );
            }
        }
    }
    tree.inventory.unique = unique;
    tree.inventory.non_unique = non_unique;
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn per_type_storage_facts_preserve_inventory_and_resolved_order() {
        let adapted=crate::adapter::from_ast(&dm_syntax::parse("/var/global = 1\n/datum/base\n    var/static/shared = 2\n    var/instance = 3\n/datum/base/child\n    shared = 4\n/datum/other\n    var/static/shared = 5\n"),SymbolTable::default(),dm_ir::FileId(0),0,0).unwrap();
        let tree = crate::build(adapted.symbols, &adapted.skeletons).unwrap();
        let hierarchy = EngineHierarchy {
            schema: 1,
            parents: tree
                .types
                .iter()
                .map(|node| (node.path, node.parent.map(|id| tree.types[id.index()].path)))
                .collect(),
        };
        let intrinsic = vec![IntrinsicMember {
            owner: SymbolId::of("/datum/base"),
            name: SymbolId::of("native_field"),
            kind: MemberKind::Var,
            shared_owner: None,
            instance_storage_proven: true,
        }];
        let serial = tree.with_engine_intrinsics(hierarchy, intrinsic).unwrap();
        for workers in [1, 2, 8] {
            let executor = dm_exec::BuildExecutor::new(workers).unwrap();
            let mut parallel = serial.clone();
            parallel.rebuild_inventory_on_executor(Some(&executor));
            assert_eq!(parallel.inventory.unique, serial.inventory.unique);
            assert_eq!(parallel.inventory.non_unique, serial.inventory.non_unique);
            assert_eq!(parallel.identity(), serial.identity());
            assert_eq!(parallel.declarations(), serial.declarations());
            for index in 0..serial.members.len() {
                assert_eq!(
                    parallel.members[index].previous,
                    serial.members[index].previous
                );
                assert_eq!(
                    parallel.members[index].metadata,
                    serial.members[index].metadata
                );
            }
        }
    }
}
