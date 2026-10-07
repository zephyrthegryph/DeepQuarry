//! Program-state boundary for lowering. No tree arena or output index crosses it.

use crate::{DeclarationMeaning, SemanticValue, SymbolId};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ReadDomain {
    Tree,
    ResourceSearch,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ResolveQuery {
    ProcedureStatic {
        procedure: crate::ProcedureIdentity,
        name: SymbolId,
    },
    Type(SymbolId),
    Parent(SymbolId),
    Ancestry(SymbolId),
    Var {
        owner: SymbolId,
        name: SymbolId,
    },
    /// Presence independent of inherited defaults/flags/type knowledge.
    HasMemberVar {
        owner: SymbolId,
        name: SymbolId,
    },
    /// Some is a proven type, None is proven untyped; unknown is Unsupported.
    DeclaredVarType {
        owner: SymbolId,
        name: SymbolId,
    },
    /// Instance/shared storage proof, independent of declaration metadata.
    VarStorage {
        owner: SymbolId,
        name: SymbolId,
    },
    Proc {
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
    },
    OverrideChain {
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
    },
    Signature(SymbolId),
    GlobalVar(SymbolId),
    GlobalProc(SymbolId),
    Constant {
        owner: SymbolId,
        name: SymbolId,
    },
    Resource(SymbolId),
    /// The runtime type behind a modified-instance alias used for inference.
    RuntimeType(SymbolId),
    /// Stable shared variable-slot identity, distinct from an instance field.
    StaticVar {
        owner: SymbolId,
        name: SymbolId,
    },
    /// Legacy unknown-receiver selection: one static slot and no instance-field
    /// declaration with the same name anywhere in the semantic inventory.
    UniqueStaticVar(SymbolId),
    /// Declaration presence is distinct from choosing a static call target.
    HasMemberProc {
        owner: SymbolId,
        name: SymbolId,
    },
    /// Queried only after local/parameter/field/global shadow checks.
    PredefinedConstant(SymbolId),
    /// FILE_DIR and source-directory search state qualify relative resources.
    ResourceIn {
        path: SymbolId,
        search_context: u128,
    },
}

impl ResolveQuery {
    pub const fn domain(self) -> ReadDomain {
        match self {
            Self::Resource(_) | Self::ResourceIn { .. } => ReadDomain::ResourceSearch,
            _ => ReadDomain::Tree,
        }
    }
}

/// Owned semantic answer, safe to retain across a resolver call. Negative results
/// are explicit. Ordered sequences preserve ancestry and override-chain meaning.
/// Fingerprints cover complete values/settings/signatures, never arena IDs.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ResolvedMeaning {
    ProcedureStatic(Arc<crate::ProcedureStaticDeclaration>),
    /// An unfinished resolver is never allowed to pretend a declaration is absent.
    Unsupported(ResolveQuery),
    Missing,
    Presence(bool),
    DeclaredType(Option<SymbolId>),
    InstanceField {
        declaring_owner: SymbolId,
        name: SymbolId,
    },
    /// Exact scalar/list semantic value, not an output-table index.
    Value(SemanticValue),
    /// Symbolic variable-slot key. Ordinary slots and global.vars are distinct.
    Slot {
        symbol: SymbolId,
        owner: SymbolId,
        name: SymbolId,
    },
    Symbol(SymbolId),
    Symbols(Vec<SymbolId>),
    Members(Vec<ResolvedMeaning>),
    Member {
        owner: SymbolId,
        name: SymbolId,
        fingerprint: u128,
        data: Arc<DeclarationMeaning>,
    },
    Resource {
        path: SymbolId,
        content: u128,
    },
}

/// The sole view of other declarations and resource search available to lowering.
/// Implementations must answer from one immutable build snapshot.
pub trait Resolver: Sync {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning;
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn filesystem_search_context_is_in_resource_domain() {
        let path = SymbolId::of("icons/probe.dmi");
        let first = ResolveQuery::ResourceIn {
            path,
            search_context: 1,
        };
        let second = ResolveQuery::ResourceIn {
            path,
            search_context: 2,
        };
        assert_eq!(first.domain(), ReadDomain::ResourceSearch);
        assert_ne!(first, second);
        assert_eq!(
            ResolveQuery::UniqueStaticVar(SymbolId::of("counter")).domain(),
            ReadDomain::Tree
        );
        assert_eq!(
            ResolveQuery::PredefinedConstant(SymbolId::of("UNIX")).domain(),
            ReadDomain::Tree
        );
    }
}
