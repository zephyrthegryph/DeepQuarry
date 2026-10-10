//! Exact finite negative-variable qualification on the existing coverage owner.
use super::*;

// Positive enriched scalar IDs and structural negative IDs have independent
// issuers. The provider half explicitly separates those branches, with checked
// bounds so reserving the bit never truncates either issuer.
pub(super) fn qualified(base: u64, provider: u64, negative: bool) -> Option<u128> {
    let provider = provider.checked_mul(2)?.checked_add(u64::from(negative))?;
    Some((u128::from(base) << 64) | u128::from(provider))
}
impl<R: Resolver + Send> EngineResolverHost<R> {
    pub(super) fn variable_negative_version(&self, query: Q) -> Option<u128> {
        let (owner, name) = match query {
            Q::Var { owner, name }
            | Q::HasMemberVar { owner, name }
            | Q::DeclaredVarType { owner, name }
            | Q::VarStorage { owner, name }
            | Q::StaticVar { owner, name } => (owner, name),
            _ => return None,
        };
        let coverage = self.variable_absence.as_ref()?;
        if !coverage.payload.names.contains(&name)
            || !self.runtime.ordinary.contains(&owner)
            || !coverage.source.intrinsic_hierarchy_certified()
            || coverage.source.lookup_type(owner).is_none()
            || !matches!(self.resolve(query), M::Missing | M::Presence(false))
        {
            return None;
        }
        let presence = Q::HasMemberVar { owner, name };
        // The one existing demanded-name issuer records all selected positive
        // and negative ancestor facts. Require the current delegated source to
        // issue the same receipt as the authenticated coverage source; an opaque
        // or unissued source cannot borrow the captured frontend's authority.
        let base = coverage.source.domain_version(presence.domain())?;
        if self.tree.domain_version(presence.domain())? != base
            || matches!(
                Resolver::resolve(coverage.source.as_ref(), presence),
                M::Presence(true)
            )
        {
            return None;
        }
        qualified(u64::try_from(base).ok()?, coverage.issuer?, true)
    }
}

#[cfg(test)]
#[path = "variable_negative_tests.rs"]
mod tests;
