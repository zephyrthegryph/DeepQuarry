//! One portable observation stream for lowering, Salsa replay and disk witnesses.
//! Values describe resolved facts; table IDs and source offsets are not identities.
use serde::{Deserialize, Serialize};
use std::cell::RefCell;
use std::collections::BTreeMap;

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Hash, Serialize, Deserialize)]
pub enum BindingFact {
    Field(String),
    Global(String),
    GlobalProc(String),
    FieldType(String),
    GlobalType(String),
    MemberType(String, String),
    MemberGlobal(String, String),
    UniqueMemberGlobal(String),
    MemberProc(String, String),
    DeclaredMemberProc(String, String),
    GlobalProcReturnType(String),
    MemberProcReturnType(String, String),
    ParentProcReturnType(String, String),
    NumericConstant(String),
    StringConstant(String),
    ModifiedInstance(String),
    SharedPresence,
}

impl BindingFact {
    /// These resolutions depend only on the immutable declaration snapshot.
    /// Unqualified field/global reads retain their invocation-local overlay.
    pub fn is_shared(&self) -> bool {
        !matches!(self, Self::Field(_) | Self::Global(_) | Self::GlobalProc(_)
            | Self::FieldType(_) | Self::GlobalType(_))
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum FactValue {
    Absent,
    Boolean(bool),
    Text(String),
    Bits(u32),
}
impl FactValue {
    pub fn text(value: Option<&str>) -> Self {
        value.map_or(Self::Absent, |value| Self::Text(value.to_owned()))
    }
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BindingWitness {
    pub fact: BindingFact,
    pub value: FactValue,
}

thread_local! {
    static READS: RefCell<Vec<BTreeMap<BindingFact, FactValue>>> = const { RefCell::new(Vec::new()) };
}

pub(crate) fn observe(fact: BindingFact, value: FactValue) {
    READS.with(|reads| {
        if let Some(frame) = reads.borrow_mut().last_mut() {
            if let Some(previous) = frame.insert(fact, value.clone()) {
                assert_eq!(
                    previous, value,
                    "lowering observed a mutable semantic snapshot"
                );
            }
        }
    });
}

struct Scope(bool);
impl Drop for Scope {
    fn drop(&mut self) {
        if self.0 {
            READS.with(|reads| {
                reads.borrow_mut().pop();
            });
        }
    }
}

/// Captures only the immediate operation's reads. Panic unwinding restores the
/// outer recorder; simultaneous worker threads have independent recorder stacks.
pub fn capture_binding_reads<R>(operation: impl FnOnce() -> R) -> (R, Vec<BindingWitness>) {
    READS.with(|reads| reads.borrow_mut().push(BTreeMap::new()));
    let mut scope = Scope(true);
    let value = operation();
    let reads = READS.with(|reads| reads.borrow_mut().pop().expect("dependency frame"));
    scope.0 = false;
    (
        value,
        reads
            .into_iter()
            .map(|(fact, value)| BindingWitness { fact, value })
            .collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn nested_and_panicked_recorders_do_not_leak() {
        let (_, outer) = capture_binding_reads(|| {
            observe(
                BindingFact::Global("outer".into()),
                FactValue::Boolean(false),
            );
            let (_, inner) = capture_binding_reads(|| {
                observe(
                    BindingFact::Global("inner".into()),
                    FactValue::Boolean(true),
                );
            });
            assert_eq!(inner.len(), 1);
            let _ = std::panic::catch_unwind(|| capture_binding_reads(|| panic!("cancel")));
        });
        assert_eq!(outer.len(), 1);
        assert_eq!(outer[0].fact, BindingFact::Global("outer".into()));
        let (_, empty) = capture_binding_reads(|| ());
        assert!(empty.is_empty());
    }
}
