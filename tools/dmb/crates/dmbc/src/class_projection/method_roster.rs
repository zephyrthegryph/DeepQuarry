//! Ordered symbolic method output, issued only after current member admission.
//! The owning ClassProjections retains one latest recipe, not output history.
use super::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct MethodInput {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub verb: bool,
    pub key: Key,
    pub declared: bool,
}
pub(super) struct MethodRoster {
    inputs: Arc<[MethodInput]>,
    pub declarations: Arc<BTreeMap<Key, bool>>,
    pub chains: Arc<[ProcedureChain]>,
    pub membership: Arc<[Key]>,
}
impl MethodRoster {
    /// Current contributions have already passed the ordinary producer and its
    /// receipt admission. Exact ordered equality includes every namespace/key.
    pub(super) fn input(&self, ordinal: usize) -> Option<&MethodInput> {
        self.inputs.get(ordinal)
    }
    pub(super) fn input_prefix(&self, len: usize) -> Vec<MethodInput> {
        self.inputs[..len].to_vec()
    }
    pub(super) fn len(&self) -> usize {
        self.inputs.len()
    }
    #[cfg(test)]
    pub(super) fn admit(&self, current: &[MethodInput]) -> bool {
        self.inputs.as_ref() == current
    }
    pub(super) fn produce(inputs: Vec<MethodInput>) -> Self {
        let mut declarations = BTreeMap::new();
        let mut group_order = Vec::new();
        let mut groups: BTreeMap<(SymbolId, SymbolId, bool), Vec<(bool, Key)>> = BTreeMap::new();
        for input in &inputs {
            declarations.insert(input.key, input.declared);
            let group = (input.owner, input.name, input.verb);
            if !groups.contains_key(&group) {
                group_order.push(group);
            }
            groups
                .entry(group)
                .or_default()
                .push((input.declared, input.key));
        }
        let membership = inputs
            .iter()
            .rev()
            .filter(|input| !input.declared)
            .chain(inputs.iter().rev().filter(|input| input.declared))
            .map(|input| input.key)
            .collect::<Vec<_>>()
            .into();
        let chains = group_order
            .into_iter()
            .map(|(owner, name, verb)| {
                let entries = groups
                    .remove(&(owner, name, verb))
                    .expect("issued encounter group");
                let mut formal = Vec::new();
                let mut implicit = Vec::new();
                for (declared, key) in entries {
                    if declared {
                        formal.push(key);
                    } else {
                        implicit.push(key);
                    }
                }
                implicit.reverse();
                formal.reverse();
                implicit.extend(formal);
                ProcedureChain {
                    owner,
                    name,
                    verb,
                    entries: implicit.into(),
                }
            })
            .collect::<Vec<_>>()
            .into();
        Self {
            inputs: inputs.into(),
            declarations: Arc::new(declarations),
            chains,
            membership,
        }
    }
    pub(crate) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        census.slice(
            "retained.class_projection.method_inputs",
            &self.inputs,
            true,
        );
        census.slice(
            "retained.class_projection.method_membership",
            &self.membership,
            true,
        );
        if census.slice(
            "retained.class_projection.method_chains",
            &self.chains,
            true,
        ) {
            for chain in self.chains.iter() {
                census.slice(
                    "retained.class_projection.method_chain_entries",
                    &chain.entries,
                    true,
                );
            }
        }
        if census.arc_object(
            "retained.class_projection.method_declarations",
            &self.declarations,
        ) {
            census.unknown(
                "retained.class_projection.method_declarations",
                "Private BTreeMap node backing is unavailable",
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn entry(owner: &str, name: &str, occurrence: u32, declared: bool, verb: bool) -> MethodInput {
        let owner = SymbolId::of(owner);
        let name = SymbolId::of(name);
        MethodInput {
            owner,
            name,
            verb,
            declared,
            key: if verb {
                Key::Verb {
                    owner,
                    name,
                    occurrence,
                }
            } else {
                Key::Proc {
                    owner,
                    name,
                    occurrence,
                }
            },
        }
    }
    #[test]
    fn interleaved_membership_and_chains_preserve_independent_encounter_order() {
        let inputs = vec![
            entry("/datum/a", "p", 0, true, false),
            entry("/datum/b", "q", 0, false, false),
            entry("/datum/a", "p", 1, false, false),
            entry("/datum/a", "q", 0, true, true),
            entry("/datum/a", "p", 2, false, false),
        ];
        let roster = MethodRoster::produce(inputs.clone());
        assert_eq!(
            roster.membership.as_ref(),
            &[
                inputs[4].key,
                inputs[2].key,
                inputs[1].key,
                inputs[3].key,
                inputs[0].key
            ]
        );
        assert_eq!(
            roster.chains[0].entries.as_ref(),
            &[inputs[4].key, inputs[2].key, inputs[0].key]
        );
        assert_eq!(roster.chains[1].owner, inputs[1].owner);
        assert!(roster.chains[2].verb);
        assert!(roster.admit(&inputs));
        let mut changed = inputs.clone();
        changed.swap(1, 2);
        assert!(!roster.admit(&changed));
        changed = inputs.clone();
        changed[2].declared = true;
        assert!(!roster.admit(&changed));
        changed = inputs.clone();
        changed[2].key = entry("/datum/a", "p", 99, false, false).key;
        assert!(!roster.admit(&changed));
        assert!(!roster.admit(&inputs[..4]));
        let fresh = MethodRoster::produce(inputs);
        assert_eq!(roster.chains, fresh.chains);
        assert_eq!(roster.declarations, fresh.declarations);
        assert_eq!(roster.membership, fresh.membership);
    }
}
