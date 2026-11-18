//! Exact source-neutral body owner with separately current lexical boundary.
use super::*;
#[derive(Clone, Debug)]
pub(super) struct BodyCodeOwner {
    pub(super) identity: Option<Arc<BodyCodeIdentity>>,
    pub(super) termination: dm_syntax::BodyTermination,
}
enum IssuedCodeIdentity<'a>{Borrowed(&'a Arc<BodyCodeIdentity>),Demand(Arc<BodyCodeIdentity>)}
pub struct IssuedBodyCode<'a>{occurrence:&'a BodyOccurrence,identity:IssuedCodeIdentity<'a>,termination:dm_syntax::BodyTermination}
impl<'a> IssuedBodyCode<'a> {
    pub fn occurrence(&self) -> &'a BodyOccurrence {
        self.occurrence
    }
    pub fn identity(&self) -> &Arc<BodyCodeIdentity> {
        match &self.identity{IssuedCodeIdentity::Borrowed(code)=>code,IssuedCodeIdentity::Demand(code)=>code}
    }
    pub fn termination(&self) -> dm_syntax::BodyTermination {
        self.termination
    }
}
pub(super) fn issue_archived_code<'a>(
    occurrence: &'a BodyOccurrence,
    owner: &'a BodyCodeOwner,
) -> IssuedBodyCode<'a> {
    IssuedBodyCode{occurrence,identity:IssuedCodeIdentity::Borrowed(owner.identity.as_ref().expect("actual eager issued Code")),termination:owner.termination}
}
pub(super) fn issue_archived_demand_code<'a>(occurrence:&'a BodyOccurrence,owner:&BodyCodeOwner,code:Arc<BodyCodeIdentity>)->IssuedBodyCode<'a>{IssuedBodyCode{occurrence,identity:IssuedCodeIdentity::Demand(code),termination:owner.termination}}
pub(super) fn visit_issued_code_storage(
    owners: &Arc<[BodyCodeOwner]>,
    mut visit: impl FnMut(usize, usize, usize),
) {
    let size = std::mem::size_of_val(owners.as_ref());
    visit(owners.as_ptr() as usize, size, size);
    for owner in owners.iter() {
        if let Some(code)=&owner.identity{code.visit_allocation_storage(&mut visit);}
    }
}
impl ColdFrontend {
    pub(super) fn require_current_body_code_owners(&self)->Result<(),Diagnostic>{
        if !Arc::ptr_eq(&self.bodies, &self.issued_bodies)
            || !Arc::ptr_eq(&self.syntax, &self.issued_syntax)
            || !self.expanded.text.same_view(&self.issued_arena)
        {
            return Err(internal("body code differs from current frontend issuance"));
        }
        self.callable_roster()
            .map_err(|message| internal(&message))?;
        if self.issued_bodies.len()!=self.issued_body_codes.len(){return Err(internal("body code owner roster differs from issued bodies"));}
        Ok(())
    }

    pub fn visit_body_code_storage(&self, visit: impl FnMut(usize, usize, usize)) {
        visit_issued_code_storage(&self.issued_body_codes, visit)
    }

    /// Capability is bound only to the current private syntax, source and body arena.
    /// Copied/selected descriptors still use the existing exact compact admission.
    pub fn body_code<'a>(
        &'a self,
        body: &BodyOccurrence,
    ) -> Result<IssuedBodyCode<'a>, Diagnostic> {
        self.require_current_body_code_owners()?;
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
        let identity=match &owner.identity{Some(code)=>IssuedCodeIdentity::Borrowed(code),None=>IssuedCodeIdentity::Demand(self.issued_syntax.original_header_recipe(occurrence.expanded_span).map_err(|e|internal(&e.message))?.issued_code_for_binding().map_err(|error|internal(&error.to_string()))?.ok_or_else(||internal("ordinary Code is not issued; use checked body Code demand"))?)};
        Ok(IssuedBodyCode{occurrence,identity,termination:owner.termination})
    }
}

#[cfg(test)]
#[path = "frontend_body_code_tests.rs"]
mod tests;
