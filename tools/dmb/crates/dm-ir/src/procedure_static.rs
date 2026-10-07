//! Procedure-local shared declarations have a distinct structural namespace.
//! Neither a synthetic class path nor an output variable index identifies them.
use crate::{ArrayDeclaration, InitializerValue, SymbolId};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ProcedureIdentity {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub verb: bool,
    pub occurrence: u32,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ProcedureStaticIdentity {
    pub procedure: ProcedureIdentity,
    pub name: SymbolId,
}
impl ProcedureStaticIdentity {
    pub fn canonical_bytes(self) -> Vec<u8> {
        let mut bytes = b"dm-procedure-static-identity-v1\0".to_vec();
        bytes.extend_from_slice(&self.procedure.owner.bits().to_le_bytes());
        bytes.extend_from_slice(&self.procedure.name.bits().to_le_bytes());
        bytes.push(u8::from(self.procedure.verb));
        bytes.extend_from_slice(&self.procedure.occurrence.to_le_bytes());
        bytes.extend_from_slice(&self.name.bits().to_le_bytes());
        bytes
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProcedureStaticDeclaration {
    pub identity: ProcedureStaticIdentity,
    pub declared_type: Option<SymbolId>,
    /// Authored modifier bits, not native footer/variable-record flags.
    pub modifiers: u32,
    pub declared_array: Option<Arc<ArrayDeclaration>>,
    pub initializer: InitializerValue,
}
impl ProcedureStaticDeclaration {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut bytes = b"dm-procedure-static-declaration-v1\0".to_vec();
        bytes.extend_from_slice(&self.identity.canonical_bytes());
        bytes.extend_from_slice(&self.modifiers.to_le_bytes());
        match self.declared_type {
            None => bytes.push(0),
            Some(path) => {
                bytes.push(1);
                bytes.extend_from_slice(&path.bits().to_le_bytes());
            }
        }
        fn part(bytes: &mut Vec<u8>, value: &[u8]) {
            bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
            bytes.extend_from_slice(value);
        }
        match &self.declared_array {
            None => bytes.push(0),
            Some(array) => {
                bytes.push(1);
                part(&mut bytes, &array.canonical_bytes());
            }
        }
        match &self.initializer {
            InitializerValue::NoAuthoredValue => bytes.push(0),
            InitializerValue::Expression(value) => {
                bytes.push(1);
                part(&mut bytes, &value.canonical_bytes());
            }
            InitializerValue::ArrayAllocation(value) => {
                bytes.push(2);
                part(&mut bytes, &value.canonical_bytes());
            }
        }
        bytes
    }
}
