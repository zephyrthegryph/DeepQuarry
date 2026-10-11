//! Negative semantic namespaces under the admitted pinned bootstrap interpretation.
//! This is independent of runtime alias/operand completeness. Every native type
//! path must be present in the current source seed before the policy is licensed.
//! Catalog-only native names are exclusions; opaque hosts never enter this path.
use super::*;
impl<R: Resolver + Send> EngineResolverHost<R> {
    pub(super) fn pinned_namespace_absence(&self, query: Q) -> Option<M> {
        let coverage = self.variable_absence.as_ref()?;
        if !coverage.payload.namespace_seeded
            || !coverage.source.intrinsic_hierarchy_certified()
            || !coverage
                .payload
                .native_types
                .iter()
                .all(|path| coverage.source.lookup_type(*path).is_some())
        {
            return None;
        }
        if let Q::Type(path) = query {
            if coverage.payload.native_types.contains(&path)
                || coverage.source.lookup_type(path).is_some()
            {
                return None;
            }
            // No fine-grained negative hierarchy token is manufactured. This
            // answer remains subject to ordinary exact semantic replay.
            return Some(M::Missing);
        }
        let (owner, name, verb, presence) = match query {
            Q::ProcedureValue {
                owner, name, verb, ..
            }
            | Q::MethodProcedureValue { owner, name, verb }
            | Q::Proc { owner, name, verb } => (owner, name, verb, false),
            Q::GlobalProc(name) => (SymbolId::of("/"), name, false, false),
            Q::HasMemberProc { owner, name } => (owner, name, false, true),
            _ => return None,
        };
        if coverage.payload.native_callable_names.contains(&name) {
            return None;
        }
        let owner = coverage.source.lookup_type(owner)?;
        let kind = if verb {
            dm_tree::MemberKind::Verb
        } else {
            dm_tree::MemberKind::Proc
        };
        if coverage.source.resolve(owner, name, kind).is_some() {
            return None;
        }
        Some(if presence {
            M::Presence(false)
        } else {
            M::Missing
        })
    }
}
