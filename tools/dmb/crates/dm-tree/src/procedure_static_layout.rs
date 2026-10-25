//! Process-local receipt of an exact captured procedure static declaration roster.
use super::*;
use crate::token_digest::TokenDigest;
#[derive(Debug)]
pub struct StaticLayout {
    procedure: ProcedureIdentity,
    declarations: Arc<[Arc<ProcedureStaticDeclaration>]>,
    token: u128,
}
impl StaticLayout {
    /// Called by the admitted artifact producer, after current syntax capture.
    /// Exhaustion or malformed identities decline certification, not compilation.
    pub fn capture(
        procedure: ProcedureIdentity,
        declarations: Arc<[Arc<ProcedureStaticDeclaration>]>,
    ) -> Option<Self> {
        let mut names = HashSet::new();
        if declarations.iter().any(|declaration| {
            declaration.identity.procedure != procedure || !names.insert(declaration.identity.name)
        }) {
            return None;
        }
        // The digest of the procedure and its exact declaration roster (see `token_digest`).
        let token = {
            let mut digest = TokenDigest::new(b"procedure-static-layout-token-v1");
            digest
                .symbol(procedure.owner)
                .symbol(procedure.name)
                .bool(procedure.verb)
                .u32(procedure.occurrence)
                .len(declarations.len());
            for declaration in declarations.iter() {
                digest.bytes(&declaration.canonical_bytes());
            }
            digest.finish()
        };
        Some(Self {
            procedure,
            declarations,
            token,
        })
    }
    pub fn declarations(&self) -> &Arc<[Arc<ProcedureStaticDeclaration>]> {
        &self.declarations
    }
    pub(super) fn matches(
        &self,
        procedure: ProcedureIdentity,
        declarations: &[Arc<ProcedureStaticDeclaration>],
    ) -> bool {
        self.procedure == procedure && self.declarations.as_ref() == declarations
    }
    pub(super) fn certificate(&self) -> u128 {
        self.token
    }
}
