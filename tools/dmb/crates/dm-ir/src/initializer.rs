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
fn symbol(write: &mut impl FnMut(&[u8]), value: SymbolId) {
    write(&value.bits().to_le_bytes());
}
fn byte(write: &mut impl FnMut(&[u8]), value: u8) {
    write(&[value]);
}
impl InitializerWrite {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        self.write_canonical(|chunk| bytes.extend_from_slice(chunk));
        bytes
    }
    pub fn canonical_len(&self) -> usize {
        let mut length = 0;
        self.write_canonical(|chunk| length += chunk.len());
        length
    }
    pub fn write_canonical(&self, mut write: impl FnMut(&[u8])) {
        write(b"dm-initializer-write-v2\0");
        match self.target {
            InitializerTarget::ProcedureStatic(identity) => {
                byte(&mut write, 2);
                let mut length = 0;
                identity.write_canonical(|chunk| length += chunk.len());
                write(&(length as u64).to_le_bytes());
                identity.write_canonical(&mut write);
            }
            InitializerTarget::Shared { slot, owner, name } => {
                byte(&mut write, 0);
                symbol(&mut write, slot);
                symbol(&mut write, owner);
                symbol(&mut write, name);
            }
            InitializerTarget::Instance {
                declaring_owner,
                receiver_owner,
                name,
            } => {
                byte(&mut write, 1);
                symbol(&mut write, declaring_owner);
                symbol(&mut write, receiver_owner);
                symbol(&mut write, name);
            }
        }
        symbol(&mut write, self.lexical_owner);
        byte(&mut write, u8::from(self.lexical_procedure.is_some()));
        if let Some(procedure) = self.lexical_procedure {
            symbol(&mut write, procedure.owner);
            symbol(&mut write, procedure.name);
            byte(&mut write, u8::from(procedure.verb));
            write(&procedure.occurrence.to_le_bytes());
        }
        byte(&mut write, u8::from(self.declaration_flags.is_some()));
        if let Some(flags) = self.declaration_flags {
            write(&flags.to_le_bytes());
        }
        byte(&mut write, u8::from(self.declared_array.is_some()));
        if let Some(array) = &self.declared_array {
            write(&(array.canonical_len() as u64).to_le_bytes());
            array.write_canonical(&mut write);
        }
        match &self.value {
            InitializerValue::NoAuthoredValue => byte(&mut write, 0),
            InitializerValue::Expression(expression) => {
                byte(&mut write, 1);
                write(&(expression.canonical_len() as u64).to_le_bytes());
                expression.write_canonical(&mut write);
            }
            InitializerValue::ArrayAllocation(array) => {
                byte(&mut write, 2);
                write(&(array.canonical_len() as u64).to_le_bytes());
                array.write_canonical(&mut write);
            }
        }
    }
}
impl InitializerUnit {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        self.write_canonical(|chunk| bytes.extend_from_slice(chunk));
        bytes
    }
    pub fn canonical_len(&self) -> usize {
        let mut length = 0;
        self.write_canonical(|chunk| length += chunk.len());
        length
    }
    pub fn write_canonical(&self, mut write: impl FnMut(&[u8])) {
        write(b"dm-initializer-unit-v1\0");
        match self.scope {
            InitializerScope::Global => byte(&mut write, 0),
            InitializerScope::Instance(owner) => {
                byte(&mut write, 1);
                symbol(&mut write, owner);
            }
        }
        write(&(self.writes.len() as u64).to_le_bytes());
        for item in self.writes.iter() {
            write(&(item.canonical_len() as u64).to_le_bytes());
            item.write_canonical(&mut write);
        }
    }
}

#[cfg(test)]
#[path = "initializer_codec_tests.rs"]
mod codec_tests;
