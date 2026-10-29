//! An exact captured procedure static declaration roster.
use super::*;
#[derive(Debug)]
pub struct StaticLayout {
    procedure: ProcedureIdentity,
    declarations: Arc<[Arc<ProcedureStaticDeclaration>]>,
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
        Some(Self {
            procedure,
            declarations,
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
}
