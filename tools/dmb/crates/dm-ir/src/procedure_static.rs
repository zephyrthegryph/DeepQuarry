//! Procedure-local shared declarations have a distinct structural namespace.
//! Neither a synthetic class path nor an output variable index identifies them.
use crate::{ArrayDeclaration, InitializerValue, SymbolId};
use std::sync::Arc;

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
pub struct ProcedureIdentity {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub verb: bool,
    pub occurrence: u32,
}
#[derive(
    Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
pub struct ProcedureStaticIdentity {
    pub procedure: ProcedureIdentity,
    pub name: SymbolId,
}
impl ProcedureStaticIdentity {
    pub fn canonical_bytes(self) -> Vec<u8> {
        let mut bytes = Vec::new();
        self.write_canonical(|chunk| bytes.extend_from_slice(chunk));
        bytes
    }
    pub(crate) fn write_canonical(self, mut write: impl FnMut(&[u8])) {
        write(b"dm-procedure-static-identity-v1\0");
        write(&self.procedure.owner.bits().to_le_bytes());
        write(&self.procedure.name.bits().to_le_bytes());
        write(&[u8::from(self.procedure.verb)]);
        write(&self.procedure.occurrence.to_le_bytes());
        write(&self.name.bits().to_le_bytes());
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
    /// Exact ordinary locals visible when this stored declaration was captured.
    pub lexical_locals: Arc<[(SymbolId, Option<SymbolId>)]>,
}
impl ProcedureStaticDeclaration {
    pub fn canonical_bytes(&self) -> Vec<u8> {
        self.canonical_bytes_using(&mut crate::canonical_encoding::Unmetered)
            .expect("unmetered native canonical allocation failed")
    }
    /// SAME byte encoder; transient allocations are funded before growth.
    pub fn canonical_bytes_using(&self, work: &mut dyn crate::CanonicalWork) -> std::io::Result<Vec<u8>> {
        crate::canonical_encoding::encode(crate::canonical_encoding::Root::Static(self), work)
    }
}
