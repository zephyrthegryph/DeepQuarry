//! Typed exact inputs on the existing artifact observation core.
//! Locators carry symbolic placement and local duplicate slots only; every hit
//! replays the complete typed input receipt.
use crate::initializer_policy::{ClassificationOwner, DefaultValue, RuntimeValue};
use dm_ir::{InitializerWrite, ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
use std::sync::Arc;
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Shape {
    Expression,
    SizedArray(Arc<[u16]>),
    SizedArrayExplicit(Arc<[u16]>, bool),
}
impl From<&RuntimeValue> for Shape {
    fn from(value: &RuntimeValue) -> Self {
        match value {
            RuntimeValue::Expression(_) => Self::Expression,
            RuntimeValue::SizedArray(value) => Self::SizedArray(Arc::clone(value)),
            RuntimeValue::SizedArrayExplicit(explicit) => {
                Self::SizedArrayExplicit(Arc::clone(&explicit.dimensions), explicit.expression.is_some())
            }
        }
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct FragmentInputs {
    pub write: InitializerWrite,
    pub shape: Shape,
    pub policy: u128,
    pub resource_context: Option<u128>,
    pub debug_enabled: bool,
    pub accepted: Option<ClassificationOwner>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct GroupWrite {
    pub fragment: Arc<Inputs>,
    pub default: DefaultValue,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Inputs {
    Fragment(FragmentInputs),
    Modified {
        canonical: Arc<[u8]>,
        policy: Option<u128>,
        lexical_owner: dm_ir::SymbolId,
        runtime_type: dm_ir::SymbolId,
        field_count: usize,
        resource_context: Option<u128>,
    },
    Assembly {
        receiver: Option<dm_ir::SymbolId>,
        writes: Vec<GroupWrite>,
    },
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Binding {
    pub key: Arc<[u8]>,
    pub inputs: Arc<Inputs>,
}
impl Binding {
    /// `debug_ops` is whether the build emits DbgFile/DbgLine ops (the DEBUG define): the lowered code differs by it, so equal
    /// placement under the other setting is another artifact (the store is shared by every session and variant).
    pub fn modified(
        reference: dm_ir::SymRef,
        descriptor: &dm_ir::ModifiedInstance,
        policy: Option<u128>,
        debug_ops: bool,
    ) -> Self {
        let mut key = b"initializer-modified-placement-v2".to_vec();
        key.push(u8::from(debug_ops));
        // Symbolic identity locates only; full canonical input is replayed.
        if let dm_ir::SymRef::Instance(name) = reference {
            symbol(&mut key, name);
        }
        Self::new(
            key,
            0,
            Inputs::Modified {
                canonical: Arc::from(descriptor.canonical_bytes()),
                policy,
                lexical_owner: descriptor.lexical_owner(),
                runtime_type: descriptor.runtime_type(),
                field_count: descriptor.fields().len(),
                resource_context: descriptor.resource_context(),
            },
        )
    }
    pub fn fragment(duplicate: usize, inputs: FragmentInputs) -> Self {
        let mut key = fragment_locator(&inputs.write);
        // Fragment code depends on the policy's build flags (see `assembly`): equal placement under another flag set is a
        // different artifact for every session and variant sharing the store.
        key.extend_from_slice(&inputs.policy.to_le_bytes());
        Self::new(key, duplicate, Inputs::Fragment(inputs))
    }
    pub fn assembly(
        receiver: Option<dm_ir::SymbolId>,
        duplicate: usize,
        writes: Vec<GroupWrite>,
    ) -> Self {
        let mut key = b"initializer-assembly-placement-v9".to_vec();
        match receiver {
            None => key.push(0),
            Some(receiver) => {
                key.push(1);
                symbol(&mut key, receiver);
            }
        }
        // The assembled code carries the build flags of its fragments' policy (DEBUG adds line ops). Equal placement under
        // another policy is another artifact, so the policy is part of the key: sessions and variants that share the store
        // never claim code built for another flag set.
        match writes.iter().find_map(|write| match write.fragment.as_ref() {
            Inputs::Fragment(fragment) => Some(fragment.policy),
            _ => None,
        }) {
            Some(policy) => {
                key.push(1);
                key.extend_from_slice(&policy.to_le_bytes());
            }
            None => key.push(0),
        }
        Self::new(key, duplicate, Inputs::Assembly { receiver, writes })
    }
    fn new(mut key: Vec<u8>, duplicate: usize, inputs: Inputs) -> Self {
        key.extend_from_slice(&(duplicate as u128).to_le_bytes());
        Self {
            key: key.into(),
            inputs: Arc::new(inputs),
        }
    }
    #[cfg(test)]
    pub fn fixture(key: &[u8]) -> Self {
        Self {
            key: key.into(),
            inputs: Arc::new(Inputs::Assembly {
                receiver: None,
                writes: Vec::new(),
            }),
        }
    }
}
// Exact bounded symbolic identity bytes, never expression/default payloads.
// These select candidates only; collisions or shifted duplicates still replay Inputs.
pub(crate) fn fragment_locator(write: &InitializerWrite) -> Vec<u8> {
    use dm_ir::{InitializerTarget, InitializerValue};
    // Short version tag: this locator is a prefix of every retained initializer key.
    let mut key = b"ifp\x06".to_vec();
    match write.target {
        InitializerTarget::ProcedureStatic(identity) => {
            key.push(0);
            procedure(&mut key, identity.procedure);
            symbol(&mut key, identity.name);
        }
        InitializerTarget::Shared { slot, owner, name } => {
            key.push(1);
            for value in [slot, owner, name] {
                symbol(&mut key, value);
            }
        }
        InitializerTarget::Instance {
            declaring_owner,
            receiver_owner,
            name,
        } => {
            key.push(2);
            for value in [declaring_owner, receiver_owner, name] {
                symbol(&mut key, value);
            }
        }
    }
    symbol(&mut key, write.lexical_owner);
    match write.lexical_procedure {
        None => key.push(0),
        Some(identity) => {
            key.push(1);
            procedure(&mut key, identity);
        }
    }
    key.push(match write.value {
        InitializerValue::Expression(_) => 0,
        InitializerValue::ArrayAllocation(_) => 1,
        InitializerValue::NoAuthoredValue => 2,
    });
    key
}
fn symbol(key: &mut Vec<u8>, value: dm_ir::SymbolId) {
    key.extend_from_slice(&value.bits().to_le_bytes());
}
fn procedure(key: &mut Vec<u8>, value: dm_ir::ProcedureIdentity) {
    symbol(key, value.owner);
    symbol(key, value.name);
    key.push(u8::from(value.verb));
    key.extend_from_slice(&value.occurrence.to_le_bytes());
}
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum Query {
    Input,
    Semantic(ResolveQuery),
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum Answer {
    Input(Arc<Inputs>),
    Semantic(ResolvedMeaning),
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum Domain {
    Input,
    Semantic(ReadDomain),
}
pub(crate) use crate::artifact_publication_store as publication_store;
pub(crate) type Store<T> = publication_store::Store<T, Query, Answer, Domain>;
pub(crate) type Storage<'a, T> =
    dm_session::ObservedArtifactStorageView<'a, T, Query, Answer, Domain>;
pub(crate) struct Host<'a, R: Resolver> {
    pub binding: &'a Binding,
    pub resolver: &'a R,
}
impl<R: Resolver> dm_session::ObservationHost<Query, Answer, Domain> for Host<'_, R> {
    fn answer(&self, query: &Query) -> Answer {
        match query {
            Query::Input => Answer::Input(Arc::clone(&self.binding.inputs)),
            Query::Semantic(query) => Answer::Semantic(self.resolver.resolve(*query)),
        }
    }
    fn equivalent(&self, a: &Answer, b: &Answer) -> bool {
        match (a, b) {
            (Answer::Input(a), Answer::Input(b)) => Arc::ptr_eq(a, b) || a == b,
            (Answer::Semantic(a), Answer::Semantic(b)) => {
                a == b || a.canonical_bytes() == b.canonical_bytes()
            }
            _ => false,
        }
    }
}
pub(crate) fn reads(
    binding: &Binding,
    reads: Vec<dm_session::ResolverRead>,
) -> Vec<dm_session::Observation<Query, Answer, Domain>> {
    let mut result = Vec::with_capacity(reads.len() + 1);
    result.push(dm_session::Observation {
        query: Query::Input,
        answer: Answer::Input(Arc::clone(&binding.inputs)),
        domain: Domain::Input,
    });
    result.extend(reads.into_iter().map(|read| dm_session::Observation {
        query: Query::Semantic(read.query),
        answer: Answer::Semantic(read.answer),
        domain: Domain::Semantic(read.domain),
    }));
    result
}

#[cfg(test)]
mod equivalence_tests {
    use super::*;
    use dm_session::ObservationHost;
    struct UnusedResolver;
    impl Resolver for UnusedResolver {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            panic!("equivalence must not resolve {query:?}")
        }
    }
    #[test]
    fn exact_semantic_answers_and_canonical_relocated_answers_remain_equivalent() {
        let binding = Binding::fixture(b"equivalence");
        let host = Host {
            binding: &binding,
            resolver: &UnusedResolver,
        };
        let exact = Answer::Semantic(ResolvedMeaning::Missing);
        assert!(host.equivalent(&exact, &exact));
        let retained = |wire_proc, engine_identity: u128| {
            Answer::Semantic(ResolvedMeaning::RetainedProc {
                declaring_owner: dm_ir::SymbolId::of("/datum/native"),
                name: dm_ir::SymbolId::of("method"),
                verb: false,
                engine_identity: engine_identity.into(),
                wire_proc,
            })
        };
        let old = retained(1, 7);
        let relocated = retained(9, 7);
        assert_ne!(old, relocated, "physical proc index differs");
        assert!(
            host.equivalent(&old, &relocated),
            "canonical comparison remains required for relocated answers"
        );
        assert!(
            !host.equivalent(&old, &retained(9, 8)),
            "changed engine authority cannot be normalized away"
        );
        assert!(!host.equivalent(&exact, &Answer::Semantic(ResolvedMeaning::Presence(false))));
        assert!(!host.equivalent(&exact, &Answer::Input(Arc::clone(&binding.inputs))));
    }
}
