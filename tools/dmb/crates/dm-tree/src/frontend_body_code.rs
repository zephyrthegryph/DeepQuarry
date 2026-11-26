//! Exact source-neutral body owner with separately current lexical boundary.
use super::*;
#[derive(Clone, Debug)]
pub(super) struct BodyCodeOwner {
    pub(super) identity: Arc<BodyCodeIdentity>,
    pub(super) termination: dm_syntax::BodyTermination,
}
pub struct IssuedBodyCode<'a> {
    occurrence: &'a BodyOccurrence,
    owner: &'a BodyCodeOwner,
}
impl<'a> IssuedBodyCode<'a> {
    pub fn occurrence(&self) -> &'a BodyOccurrence {
        self.occurrence
    }
    pub fn identity(&self) -> &Arc<BodyCodeIdentity> {
        &self.owner.identity
    }
    pub fn termination(&self) -> dm_syntax::BodyTermination {
        self.owner.termination
    }
}
impl ColdFrontend {
    pub fn visit_body_code_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        let size = std::mem::size_of_val(self.issued_body_codes.as_ref());
        visit(self.issued_body_codes.as_ptr() as usize, size, size);
        for owner in self.issued_body_codes.iter() {
            visit(
                Arc::as_ptr(&owner.identity) as usize,
                std::mem::size_of::<BodyCodeIdentity>(),
                std::mem::size_of::<BodyCodeIdentity>(),
            );
        }
    }

    /// Capability is bound only to the current private syntax, source and body arena.
    /// Copied/selected descriptors still use the existing exact compact admission.
    pub fn body_code<'a>(
        &'a self,
        body: &BodyOccurrence,
    ) -> Result<IssuedBodyCode<'a>, Diagnostic> {
        if !Arc::ptr_eq(&self.bodies, &self.issued_bodies)
            || !Arc::ptr_eq(&self.syntax, &self.issued_syntax)
            || !self.expanded.text.same_view(&self.issued_arena)
        {
            return Err(internal("body code differs from current frontend issuance"));
        }
        self.callable_roster()
            .map_err(|message| internal(&message))?;
        let index = *self
            .body_by_declaration
            .get(&body.declaration)
            .ok_or_else(|| internal("body code declaration missing"))?;
        let occurrence = &self.issued_bodies[index];
        if !std::ptr::eq(occurrence, body) {
            self.compact_body(body)?;
        }
        let owner = self
            .issued_body_codes
            .get(index)
            .ok_or_else(|| internal("body code owner missing"))?;
        Ok(IssuedBodyCode { occurrence, owner })
    }
}

#[cfg(test)]
#[path = "frontend_body_code_tests.rs"]
mod tests;
