//! Current source member-name availability; no native or root-global inference.
use super::*;
use std::collections::BTreeMap;
#[cfg(test)]
#[path = "resolver_member_names_tests.rs"]
mod tests;
impl SemanticTree {
    // One immutable query index, derived from final semantic members, never per request host.
    pub(crate) fn refresh_member_callable_names(&mut self) {
        let mut names = BTreeMap::new();
        let root = SymbolId::of("/");
        for node in self.members.iter() {
            if self.types[node.owner.index()].path == root || node.metadata.procedure.is_none() {
                continue;
            }
            let flag = match node.kind {
                MemberKind::Proc => 1,
                MemberKind::Verb => 2,
                _ => continue,
            };
            *names.entry(node.name).or_insert(0) |= flag;
        }
        if self.member_callable_names.as_ref() != &names {
            self.member_callable_names = Arc::new(names);
        }
    }
    pub fn member_callable_name_storage(&self) -> &Arc<BTreeMap<SymbolId, u8>> {
        &self.member_callable_names
    }
    /// Source verbs are callable through typed receivers and dynamic selectors.
    /// The call syntax separately enforces ordinary untyped-dot restrictions.
    pub fn source_member_callable_name(&self, name: SymbolId) -> Option<bool> {
        match self.member_callable_names.get(&name).copied().unwrap_or(0) {
            flags if flags & 3 != 0 => Some(true),
            0 if self.inventory.hierarchy_certified => Some(false),
            _ => None,
        }
    }
}
