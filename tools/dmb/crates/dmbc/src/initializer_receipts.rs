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
            RuntimeValue::SizedArrayExplicit {
                dimensions,
                expression,
            } => Self::SizedArrayExplicit(Arc::clone(dimensions), expression.is_some()),
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
    pub fn fragment(duplicate: usize, inputs: FragmentInputs) -> Self {
        let key = fragment_locator(&inputs.write);
        Self::new(key, duplicate, Inputs::Fragment(inputs))
    }
    pub fn assembly(
        receiver: Option<dm_ir::SymbolId>,
        duplicate: usize,
        writes: Vec<GroupWrite>,
    ) -> Self {
        let mut key = b"initializer-assembly-placement-v5".to_vec();
        match receiver {
            None => key.push(0),
            Some(receiver) => {
                key.push(1);
                symbol(&mut key, receiver);
            }
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
    let mut key = b"initializer-fragment-placement-v5".to_vec();
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
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) enum Domain {
    Input,
    Semantic(ReadDomain),
}
pub(crate) type Store<T> = dm_session::ObservedArtifactStore<T, Query, Answer, Domain>;
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
    fn version(&self, domain: &Domain) -> Option<u128> {
        match domain {
            Domain::Input => None,
            Domain::Semantic(domain) => self.resolver.domain_version(*domain),
        }
    }
    fn equivalent(&self, a: &Answer, b: &Answer) -> bool {
        match (a, b) {
            (Answer::Input(a), Answer::Input(b)) => Arc::ptr_eq(a, b) || a == b,
            (Answer::Semantic(a), Answer::Semantic(b)) => {
                a.canonical_bytes() == b.canonical_bytes()
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
pub(crate) fn versions(values: Vec<(ReadDomain, u128)>) -> Vec<(Domain, u128)> {
    values
        .into_iter()
        .map(|(domain, version)| (Domain::Semantic(domain), version))
        .collect()
}
