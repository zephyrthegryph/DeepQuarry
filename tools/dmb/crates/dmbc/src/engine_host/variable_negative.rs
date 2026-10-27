//! Exact finite negative-variable qualification on the existing coverage owner.
use super::*;

impl<R: Resolver + Send> EngineResolverHost<R> {
    /// The pinned coverage closes the gap the incomplete intrinsic inventory leaves in the public presence answer.
    /// It holds for this query when the source it was captured from has no authored declaration of the name on the
    /// owner and the current tree answers the owner's ancestry and the name's presence exactly as that source does.
    pub(super) fn current_variable_absence(&self, query: Q) -> bool {
        self.variable_absence_of(query).is_some()
    }
    fn variable_absence_of(&self, query: Q) -> Option<()> {
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
        let source: &dm_tree::SemanticTree = coverage.source.as_ref();
        let same = |query: Q| dm_ir::Resolver::resolve(source, query) == self.tree.resolve(query);
        (same(Q::Ancestry(owner)) && same(Q::HasMemberVar { owner, name })).then_some(())
    }
    /// A predefined constant name the pinned coverage proves absent from the source as a global variable.
    pub(super) fn predefined_absence_proven(&self, name: SymbolId) -> bool {
        let Some(coverage) = self.variable_absence.as_ref() else {
            return false;
        };
        !self.constants.values.contains_key(&name)
            && coverage.payload.covers_predefined_absence(name)
            && self.current_variable_absence(Q::GlobalVar(name))
    }
}

#[cfg(test)]
#[path = "variable_negative_tests.rs"]
mod tests;
