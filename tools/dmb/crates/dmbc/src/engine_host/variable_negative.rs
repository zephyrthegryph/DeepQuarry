//! Exact finite negative-variable qualification on the existing coverage owner.
use super::*;

// Positive enriched scalar IDs and structural negative IDs have independent
// issuers. The provider half explicitly separates those branches, with checked
// bounds so reserving two branch bits never truncates either issuer.
pub(super) fn qualified(base: u64, provider: u64, negative: bool) -> Option<u128> {
    qualified_tag(base, provider, u64::from(negative))
}
fn qualified_tag(base: u64, provider: u64, tag: u64) -> Option<u128> {
    let provider = provider.checked_mul(4)?.checked_add(tag)?;
    Some((u128::from(base) << 64) | u128::from(provider))
}
impl<R: Resolver + Send> EngineResolverHost<R> {
    /// The named source receipt covers the authored selection even when the
    /// incomplete intrinsic inventory makes its public presence Unsupported.
    /// Pinned coverage closes only that intrinsic gap; exact current authored
    /// absence is obtained from the same tree's declaration resolver.
    pub(super) fn current_variable_absence(&self, query: Q) -> Option<u128> {
        let (owner, name) = match query {
            Q::GlobalVar(name) => (SymbolId::of("/"), name),
            Q::Var { owner, name }
            | Q::HasMemberVar { owner, name }
            | Q::DeclaredVarType { owner, name }
            | Q::VarStorage { owner, name }
            | Q::StaticVar { owner, name }
            | Q::Constant { owner, name } => (owner, name),
            _ => return None,
        };
        let coverage = self.variable_absence.as_ref()?;
        if !coverage.payload.covers(query)
            || !coverage.source.intrinsic_hierarchy_certified()
            || !self.runtime.ordinary.contains(&owner)
        {
            return None;
        }
        let source_owner = coverage.source.lookup_type(owner)?;
        if coverage
            .source
            .resolve(source_owner, name, dm_tree::MemberKind::Var)
            .is_some()
        {
            return None;
        }
        let presence = Q::HasMemberVar { owner, name };
        if let Some(base) = coverage.source.domain_version(presence.domain()) {
            return (self.tree.domain_version(presence.domain()) == Some(base)).then_some(base);
        }
        // Legacy one-shot source trees may not issue demanded-name tokens.
        // Only previously admitted finite names may use their full semantic
        // domain. The generalized root policy never borrows this fallback.
        if !coverage.payload.names.contains(&name) {
            return None;
        }
        let base = coverage.source.domain_version(dm_ir::ReadDomain::Tree)?;
        (self.tree.domain_version(dm_ir::ReadDomain::Tree) == Some(base)).then_some(base)
    }
    pub(super) fn predefined_absence_version(&self, name: SymbolId) -> Option<u128> {
        let coverage = self.variable_absence.as_ref()?;
        if self.constants.values.contains_key(&name)
            || !coverage.payload.covers_predefined_absence(name)
        {
            return None;
        }
        // Ordinary names require a current named receipt; they cannot take the
        // legacy finite-name whole-tree compatibility path.
        let presence = Q::HasMemberVar {
            owner: SymbolId::of("/"),
            name,
        };
        coverage.source.domain_version(presence.domain())?;
        let base = self.current_variable_absence(Q::GlobalVar(name))?;
        qualified_tag(u64::try_from(base).ok()?, coverage.issuer?, 2)
    }
    pub(super) fn variable_negative_version(&self, query: Q) -> Option<u128> {
        // Resolution uses current_variable_absence without calling this method,
        // so qualification cannot recursively re-enter its own fallback.
        if !matches!(self.resolve(query), M::Missing | M::Presence(false)) {
            return None;
        }
        let base = self.current_variable_absence(query)?;
        let coverage = self.variable_absence.as_ref()?;
        qualified(u64::try_from(base).ok()?, coverage.issuer?, true)
    }
}

#[cfg(test)]
#[path = "variable_negative_tests.rs"]
mod tests;
