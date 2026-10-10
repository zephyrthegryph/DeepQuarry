//! Process-local receipt of an exact captured procedure static declaration roster.
use super::*;
use std::sync::atomic::{AtomicU64, Ordering};
#[derive(Debug)]
pub struct StaticLayout {
    procedure: ProcedureIdentity,
    declarations: Arc<[Arc<ProcedureStaticDeclaration>]>,
    token: u64,
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
        static NEXT: AtomicU64 = AtomicU64::new(1);
        let token = NEXT
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
                value.checked_add(1)
            })
            .ok()?;
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
        u128::from(self.token)
    }
}
