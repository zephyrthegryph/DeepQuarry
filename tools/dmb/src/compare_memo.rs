//! Request-local normalization, qualified by one immutably borrowed DMB.
//! Numeric IDs have meaning only in this owner's tables; no cross-file cache.
use super::*;
use std::{cell::RefCell, ops::Deref, sync::Arc};

type Assignments = Arc<BTreeMap<Vec<u8>, maps::MapConstant>>;
pub(super) struct NormalizationContext<'a> {
    owner: &'a Dmb,
    instances: RefCell<BTreeMap<u32, NormalValue>>,
    assignments: RefCell<BTreeMap<u32, Option<Assignments>>>,
    verbs: BTreeSet<u32>,
}
impl<'a> NormalizationContext<'a> {
    pub(super) fn new(owner: &'a Dmb) -> Self {
        Self {
            owner,
            instances: Default::default(),
            assignments: Default::default(),
            verbs: owner
                .classes
                .iter()
                .flat_map(|class| {
                    owner
                        .lists
                        .get(class.verb_list_id() as usize)
                        .into_iter()
                        .flatten()
                        .copied()
                })
                .collect(),
        }
    }
    pub(super) fn reference_path(&self, id: u32) -> Option<Vec<u8>> {
        let raw = proc_path(self.owner, id)?;
        let explicit_verb = raw.windows(6).any(|part| part == b"/verb/");
        let mut name = canonical_proc_path(raw);
        if (explicit_verb || self.verbs.contains(&id))
            && !name.windows(6).any(|part| part == b"/verb/")
        {
            // Grouping removes physical markers. Typed references must retain
            // actual verb namespace, including bare native bound paths.
            let slash = name.iter().rposition(|byte| *byte == b'/')?;
            name.splice(slash + 1..slash + 1, b"verb/".iter().copied());
        }
        Some(name)
    }
    pub(super) fn instance(&self, id: u32, compute: impl FnOnce() -> NormalValue) -> NormalValue {
        if let Some(value) = self.instances.borrow().get(&id) {
            return value.clone();
        }
        // Release the borrow before invoking the common normalization core.
        let value = compute();
        self.instances.borrow_mut().insert(id, value.clone());
        value
    }
    pub(super) fn assignments(
        &self,
        id: u32,
        compute: impl FnOnce() -> Option<Assignments>,
    ) -> Option<Assignments> {
        if let Some(value) = self.assignments.borrow().get(&id) {
            return value.clone();
        }
        let value = compute();
        self.assignments.borrow_mut().insert(id, value.clone());
        value
    }
}
impl Deref for NormalizationContext<'_> {
    type Target = Dmb;
    fn deref(&self) -> &Dmb {
        self.owner
    }
}

#[cfg(test)]
#[path = "compare_proc_reference_tests.rs"]
mod reference_tests;

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn actual_instance_answers_decode_once_and_same_id_in_other_file_is_independent() {
        let mut expected = Dmb::from_bytes(include_bytes!(
            "../fixtures/translation/input_selection/input_selection.native.bin"
        ))
        .unwrap();
        let code = expected.lists.len() as u32;
        expected
            .lists
            .push(vec![0x50, 1, 0x34, 0xffdc, 0xffce, 0, 0]);
        expected.procs[0].code_locals_args[0] = code;
        let id = expected.instances.len() as u32;
        expected.instances.push(crate::dmb::Instance {
            kind: 32,
            class: 0,
            initializer: 0,
        });
        let mut actual = expected.clone();
        actual.lists[code as usize][1] = 2;
        let raw = Value {
            tag_word: 41,
            data_word: id,
            extra_word: None,
        };
        let left = NormalizationContext::new(&expected);
        let right = NormalizationContext::new(&actual);
        let first = value(&left, raw);
        let repeated = value(&left, raw);
        assert_eq!(first, repeated);
        assert_ne!(first, value(&right, raw));
        assert_eq!(left.instances.borrow().len(), 1);
        assert_eq!(left.assignments.borrow().len(), 1);
        match (&first, &repeated) {
            (
                NormalValue::InstanceType(_, _, values::InstanceInitializer::Constants(a)),
                NormalValue::InstanceType(_, _, values::InstanceInitializer::Constants(b)),
            ) => assert!(Arc::ptr_eq(a, b)),
            _ => panic!("constant initializer fixture"),
        }
    }
    #[test]
    fn repeated_instance_normalization_is_owner_scoped_and_preserves_exact_debug() {
        let native = Dmb::from_bytes(include_bytes!(
            "../fixtures/translation/input_selection/input_selection.native.bin"
        ))
        .unwrap();
        let left = NormalizationContext::new(&native);
        let right = NormalizationContext::new(&native);
        let first = left.instance(7, || {
            NormalValue::InstanceType(
                1,
                Some(b"/datum/a".to_vec()),
                values::InstanceInitializer::Constants("{constant: 1}".into()),
            )
        });
        assert_eq!(first, left.instance(7, || panic!("already normalized")));
        let second = right.instance(7, || {
            NormalValue::InstanceType(
                1,
                Some(b"/datum/b".to_vec()),
                values::InstanceInitializer::Constants("{constant: 2}".into()),
            )
        });
        assert_ne!(first, second);
        assert_eq!(
            format!(
                "{:?}",
                values::InstanceInitializer::Constants("{constant: 1}".into())
            ),
            "Constants(\"{constant: 1}\")"
        );
        assert!(left.assignments(4, || None).is_none());
        assert!(left
            .assignments(4, || panic!("negative decode is memoized"))
            .is_none());
        let assignments = left
            .assignments(5, || Some(Arc::new(BTreeMap::new())))
            .unwrap();
        assert!(Arc::ptr_eq(
            &assignments,
            &left.assignments(5, || panic!("already decoded")).unwrap()
        ));
    }
}
