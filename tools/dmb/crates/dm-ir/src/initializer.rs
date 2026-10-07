//! Symbolic initializer inputs. Scheduling/materialization policy belongs to
//! the target backend; source origins and output table IDs stay outside this IR.
use crate::{
    ArrayDeclaration, ProcedureIdentity, ProcedureStaticIdentity, SymbolId, SymbolicExpression,
};
use std::sync::Arc;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum InitializerTarget {
    ProcedureStatic(ProcedureStaticIdentity),
    Shared {
        slot: SymbolId,
        owner: SymbolId,
        name: SymbolId,
    },
    Instance {
        declaring_owner: SymbolId,
        receiver_owner: SymbolId,
        name: SymbolId,
    },
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum InitializerValue {
    Expression(SymbolicExpression),
    ArrayAllocation(Arc<ArrayDeclaration>),
    /// No authored initializer/allocation. This is not an invented null value.
    NoAuthoredValue,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InitializerWrite {
    pub target: InitializerTarget,
    /// Declaration/assignment scope for name and type resolution.
    pub lexical_owner: SymbolId,
    pub lexical_procedure: Option<ProcedureIdentity>,
    pub value: InitializerValue,
    /// Authored formal array shape, even when an explicit expression exists.
    /// An assignment inheriting array metadata has no authored shape here.
    pub declared_array: Option<Arc<ArrayDeclaration>>,
    /// None means opaque inherited modifier knowledge, never syntax-only zero.
    pub declaration_flags: Option<u32>,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InitializerScope {
    Global,
    Instance(SymbolId),
}
/// An explicitly ordered unit selected by backend policy. Constructing this
/// value does not infer that all writes are runtime operations.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InitializerUnit {
    pub scope: InitializerScope,
    pub writes: Arc<[InitializerWrite]>,
}
fn symbol(bytes: &mut Vec<u8>, value: SymbolId) {
    bytes.extend_from_slice(&value.bits().to_le_bytes());
}
fn framed(bytes: &mut Vec<u8>, value: &[u8]) {
    bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
    bytes.extend_from_slice(value);
}
impl InitializerWrite {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = b"dm-initializer-write-v2\0".to_vec();
        match self.target {
            InitializerTarget::ProcedureStatic(identity) => {
                bytes.push(2);
                framed(&mut bytes, &identity.canonical_bytes());
            }
            InitializerTarget::Shared { slot, owner, name } => {
                bytes.push(0);
                symbol(&mut bytes, slot);
                symbol(&mut bytes, owner);
                symbol(&mut bytes, name);
            }
            InitializerTarget::Instance {
                declaring_owner,
                receiver_owner,
                name,
            } => {
                bytes.push(1);
                symbol(&mut bytes, declaring_owner);
                symbol(&mut bytes, receiver_owner);
                symbol(&mut bytes, name);
            }
        }
        symbol(&mut bytes, self.lexical_owner);
        bytes.push(u8::from(self.lexical_procedure.is_some()));
        if let Some(procedure) = self.lexical_procedure {
            symbol(&mut bytes, procedure.owner);
            symbol(&mut bytes, procedure.name);
            bytes.push(u8::from(procedure.verb));
            bytes.extend_from_slice(&procedure.occurrence.to_le_bytes());
        }
        bytes.push(u8::from(self.declaration_flags.is_some()));
        if let Some(flags) = self.declaration_flags {
            bytes.extend_from_slice(&flags.to_le_bytes());
        }
        bytes.push(u8::from(self.declared_array.is_some()));
        if let Some(array) = &self.declared_array {
            framed(&mut bytes, &array.canonical_bytes());
        }
        match &self.value {
            InitializerValue::NoAuthoredValue => bytes.push(0),
            InitializerValue::Expression(expression) => {
                bytes.push(1);
                framed(&mut bytes, &expression.canonical_bytes());
            }
            InitializerValue::ArrayAllocation(array) => {
                bytes.push(2);
                framed(&mut bytes, &array.canonical_bytes());
            }
        }
        bytes
    }
}
impl InitializerUnit {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = b"dm-initializer-unit-v1\0".to_vec();
        match self.scope {
            InitializerScope::Global => bytes.push(0),
            InitializerScope::Instance(owner) => {
                bytes.push(1);
                symbol(&mut bytes, owner);
            }
        }
        bytes.extend_from_slice(&(self.writes.len() as u64).to_le_bytes());
        for write in self.writes.iter() {
            framed(&mut bytes, &write.canonical_bytes());
        }
        bytes
    }
}
