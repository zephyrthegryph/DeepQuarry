use super::*;
use std::{collections::BTreeSet, sync::Arc};
fn read(name: &str, answer: ResolvedMeaning) -> ResolverRead {
    let query = ResolveQuery::GlobalVar(SymbolId::of(name));
    ResolverRead {
        query,
        domain: query.domain(),
        answer,
    }
}
fn exposed_bytes(receipts: &[ProcedureReceipt], pool: &ProcedureGroups) -> usize {
    let mut seen = BTreeSet::new();
    let mut bytes = 0;
    for receipt in receipts {
        receipt.visit_storage(|view| match view {
            dm_session::ReceiptStorageView::Flat(owner) => {
                if seen.insert(owner.as_ptr() as usize) {
                    bytes += owner.len() * std::mem::size_of::<ResolverRead>();
                }
            }
            dm_session::ReceiptStorageView::Groups(owner) => {
                if seen.insert(owner.as_ptr() as usize) {
                    bytes += owner.len() * std::mem::size_of::<Arc<[ResolverRead]>>();
                }
            }
        });
    }
    pool.visit_storage(|_, _, capacity| bytes += capacity);
    bytes
}
#[test]
fn global_owner_leaves_share_common_answers_with_distinct_tails_and_reduce_exposed_union() {
    let common = read("common_global", ResolvedMeaning::Missing);
    let inputs: Vec<_> = (0..64)
        .map(|index| {
            let mut rows = vec![
                common.clone(),
                read(&format!("tail_{index}"), ResolvedMeaning::Presence(false)),
            ];
            rows.sort_by_key(|r| r.query);
            rows
        })
        .collect();
    let before_pool = ProcedureGroups::default();
    let before: Vec<_> = inputs
        .iter()
        .map(|rows| {
            before_pool
                .intern_receipt(rows.clone(), |a, b| {
                    family(a.query) == family(b.query)
                        && domain_family(a.domain) == domain_family(b.domain)
                })
                .unwrap()
        })
        .collect();
    let pool = ProcedureGroups::default();
    let after: Vec<_> = inputs
        .iter()
        .map(|rows| grouped(&pool, rows.clone()))
        .collect();
    let common_leaf = |receipt: &ProcedureReceipt| {
        let mut found = None;
        receipt.visit_storage(|view| {
            if let dm_session::ReceiptStorageView::Flat(leaf) = view {
                if leaf.len() == 1 && leaf[0].query == common.query {
                    found = Some(Arc::clone(leaf));
                }
            }
        });
        found.unwrap()
    };
    let shared = common_leaf(&after[0]);
    for (receipt, input) in after.iter().zip(&inputs) {
        assert!(Arc::ptr_eq(&shared, &common_leaf(receipt)));
        assert_eq!(receipt.iter().cloned().collect::<Vec<_>>(), *input);
    }
    assert!(
        exposed_bytes(&after, &pool) < exposed_bytes(&before, &before_pool),
        "actual observation/group/weak-Vec buffer union includes added leaf descriptors"
    );
    // Arc control blocks, private BTree nodes and allocator overhead are unknown;
    // this is an exposed-buffer comparison, not total/private-byte savings.
}
#[test]
fn global_owner_grouping_preserves_conflicting_repeated_query_answers() {
    let pool = ProcedureGroups::default();
    let a = read("same", ResolvedMeaning::Missing);
    let b = read("same", ResolvedMeaning::Presence(false));
    let rows = vec![a, b];
    let receipt = grouped(&pool, rows.clone());
    assert_eq!(receipt.iter().cloned().collect::<Vec<_>>(), rows);
    let mut lengths = Vec::new();
    receipt.visit_storage(|view| {
        if let dm_session::ReceiptStorageView::Flat(leaf) = view {
            lengths.push(leaf.len());
        }
    });
    assert_eq!(lengths, vec![2]);
}
