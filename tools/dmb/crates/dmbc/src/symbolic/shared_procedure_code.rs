//! Physical code sharing after ordinary freezing; no resolver or source proof is reused.
use super::{FrozenProc, UnitIdentity};
use std::sync::Arc;

#[derive(Clone)]
pub(crate) struct CodeOwner(pub(crate) Arc<FrozenProc>);
impl PartialEq for CodeOwner {
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.0, &other.0)
            || self.0.code() == other.0.code() && self.0.labels() == other.0.labels()
    }
}
impl Eq for CodeOwner {}
type Store = dm_session::ObservedArtifactStore<CodeOwner, (), CodeOwner, ()>;
pub(crate) type Lease = dm_session::ObservedArtifactLease<CodeOwner, (), CodeOwner, ()>;
pub(crate) struct SharedProcedureCode(Arc<Store>);
impl Default for SharedProcedureCode {
    fn default() -> Self {
        Self(Store::shared_current_rosters())
    }
}
impl SharedProcedureCode {
    pub(crate) fn lease(&self) -> Lease {
        self.0.lease()
    }
    pub(crate) fn visit_storage(
        &self,
        visit: impl FnMut(dm_session::ObservedArtifactStorageView<'_, CodeOwner, (), CodeOwner, ()>),
    ) {
        self.0.visit_storage(visit);
    }
}
struct Current(CodeOwner);
impl dm_session::ObservationHost<(), CodeOwner, ()> for Current {
    fn answer(&self, _: &()) -> CodeOwner {
        self.0.clone()
    }
}
pub(crate) fn key(identity: UnitIdentity, helper: Option<u32>) -> Vec<u8> {
    let mut bytes = b"frozen-procedure-owner-v1".to_vec();
    bytes.extend_from_slice(&identity.owner.bits().to_le_bytes());
    bytes.extend_from_slice(&identity.name.bits().to_le_bytes());
    bytes.push(match identity.namespace {
        crate::lowering::Namespace::Proc => 0,
        crate::lowering::Namespace::Verb => 1,
    });
    bytes.extend_from_slice(&identity.occurrence.to_le_bytes());
    bytes.push(u8::from(helper.is_some()));
    if let Some(argument) = helper {
        bytes.extend_from_slice(&argument.to_le_bytes());
    }
    bytes
}
pub(crate) fn share(
    lease: &Lease,
    identity: UnitIdentity,
    helper: Option<u32>,
    code: &mut Arc<FrozenProc>,
) {
    let key = key(identity, helper);
    let current = Current(CodeOwner(Arc::clone(code)));
    let accepted = lease
        .visit_explained(&key, &current, &mut |_| true)
        .0
        .or_else(|| {
            lease.insert_with_owned(
                key.into(),
                vec![dm_session::Observation {
                    query: (),
                    answer: current.0.clone(),
                    domain: (),
                }],
                vec![],
                1,
                || current.0.clone(),
            )
        });
    if let Some(owner) = accepted {
        *code = Arc::clone(&owner.0);
    }
}

pub(crate) fn census(
    owner: &Arc<SharedProcedureCode>,
    census: &mut crate::heap_census::HeapCensus,
) {
    use dm_session::ObservedArtifactStorageView as View;
    if !census.arc_object("shared_procedure_code.owner", owner) {
        return;
    }
    if !census.arc_object("shared_procedure_code.store", &owner.0) {
        return;
    }
    owner.visit_storage(|view| match view {
        View::Store { entries, .. } => {
            census.observe_items("shared_procedure_code.entries", entries);
            census.unknown(
                "shared_procedure_code.index",
                "private BTree nodes, lease rosters and claim index backing excluded",
            );
        }
        View::Bucket {
            address,
            len,
            capacity,
            element_size,
        } => {
            census.exposed_buffer(
                "shared_procedure_code.buckets",
                address,
                len.saturating_mul(element_size),
                capacity.saturating_mul(element_size),
            );
        }
        View::Entry {
            key,
            reads,
            versions,
            value,
        } => {
            census.slice("shared_procedure_code.keys", key, true);
            if census.receipt("shared_procedure_code.reads", reads) {
                for read in reads.iter() {
                    census.shared_frozen_code(&read.answer.0);
                }
            }
            census.slice("shared_procedure_code.versions", versions, true);
            if census.arc_object("shared_procedure_code.value", value) {
                census.shared_frozen_code(&value.0);
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    fn code(word: u32) -> Arc<FrozenProc> {
        Arc::new(
            FrozenProc::restore(
                dm_ir::SymbolicCode::new(vec![word], vec![]).unwrap(),
                vec![],
            )
            .unwrap(),
        )
    }
    #[test]
    fn changed_words_or_labels_do_not_share_an_identity_candidate() {
        let pool = SharedProcedureCode::default();
        let first = pool.lease();
        let second = pool.lease();
        let identity = UnitIdentity {
            owner: dm_ir::SymbolId::of("/datum/probe"),
            name: dm_ir::SymbolId::of("check"),
            namespace: crate::lowering::Namespace::Proc,
            occurrence: 0,
        };
        let mut original = code(0);
        let mut changed = Arc::new(
            FrozenProc::restore(
                dm_ir::SymbolicCode::new(vec![0, 0], vec![]).unwrap(),
                vec![],
            )
            .unwrap(),
        );
        share(&first, identity, None, &mut original);
        share(&second, identity, None, &mut changed);
        assert!(!Arc::ptr_eq(&original, &changed));
        let mut labels = Arc::new(
            FrozenProc::restore(
                dm_ir::SymbolicCode::new(vec![0], vec![]).unwrap(),
                vec![Some(0)],
            )
            .unwrap(),
        );
        share(&second, identity, None, &mut labels);
        assert!(!Arc::ptr_eq(&original, &labels));
    }
    #[test]
    fn changed_relocation_target_rejects_identical_words_and_labels() {
        let pool = SharedProcedureCode::default();
        let lease = pool.lease();
        let identity = UnitIdentity {
            owner: dm_ir::SymbolId::of("/datum/probe"),
            name: dm_ir::SymbolId::of("check"),
            namespace: crate::lowering::Namespace::Proc,
            occurrence: 0,
        };
        let make = |text: &str| {
            Arc::new(
                dm_codegen_byond::encoder::freeze_proc(&dm_codegen_byond::SymbolicProc {
                    items: vec![
                        dm_codegen_byond::Item::Instruction(dm_codegen_byond::Instruction {
                            opcode: 0x60,
                            operands: vec![dm_codegen_byond::Word::Value(
                                dm_codegen_byond::ValueWord::String(dm_ir::SymbolId::of(text)),
                            )],
                        }),
                        dm_codegen_byond::Item::Instruction(dm_codegen_byond::Instruction {
                            opcode: 0,
                            operands: vec![],
                        }),
                    ],
                })
                .unwrap(),
            )
        };
        let mut a = make("first");
        let mut b = make("second");
        assert_eq!(a.code().words(), b.code().words());
        assert_eq!(a.labels(), b.labels());
        share(&lease, identity, None, &mut a);
        let old = Arc::downgrade(&a);
        share(&lease, identity, None, &mut b);
        assert!(!Arc::ptr_eq(&a, &b));
        // An external old record may keep its immutable payload temporarily,
        // but replacing the lease claim must not keep it after that record drops.
        drop(a);
        assert!(old.upgrade().is_none());
        let mut helper = make("helper");
        share(&lease, identity, Some(1), &mut helper);
        let helper_old = Arc::downgrade(&helper);
        drop(helper);
        let main = key(identity, None);
        lease.retain_current_keys([main.as_slice()]);
        assert!(helper_old.upgrade().is_none());
    }
    #[test]
    fn equal_code_shares_and_last_session_drop_releases_current_payload() {
        let pool = SharedProcedureCode::default();
        let first = pool.lease();
        let second = pool.lease();
        let identity = UnitIdentity {
            owner: dm_ir::SymbolId::of("/datum/probe"),
            name: dm_ir::SymbolId::of("check"),
            namespace: crate::lowering::Namespace::Proc,
            occurrence: 0,
        };
        let mut a = code(0);
        let mut b = code(0);
        share(&first, identity, None, &mut a);
        share(&second, identity, None, &mut b);
        assert!(Arc::ptr_eq(&a, &b));
        let weak = Arc::downgrade(&a);
        drop(a);
        drop(b);
        drop(first);
        assert!(weak.upgrade().is_some());
        second.retain_current_keys(std::iter::empty::<&[u8]>());
        assert!(weak.upgrade().is_none());
    }
}
