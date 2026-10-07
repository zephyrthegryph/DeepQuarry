//! Program-state boundary for lowering. No tree arena or output index crosses it.

use crate::{DeclarationMeaning, SemanticValue, SymbolId};
use std::sync::Arc;

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
pub enum ReadDomain {
    Tree,
    ResourceSearch,
}

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
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
    /// A callable literal selects an exact source formal or effective body.
    ProcedureValue {
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
        formal: bool,
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
    /// Pinned engine receiver method selected dynamically by name. This is
    /// positive presence, not a source procedure image or an invented ABI.
    IntrinsicProc {
        declaring_owner: SymbolId,
        name: SymbolId,
    },
    /// Exact named procedure in an immutable engine table prefix. Its bytecode
    /// and ABI remain in that captured image; no source signature is invented.
    RetainedProc {
        declaring_owner: SymbolId,
        name: SymbolId,
        verb: bool,
        engine_identity: u128,
        wire_proc: u32,
    },
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

impl ResolvedMeaning {
    /// Stable dependency evidence: complete semantic values, no debug formatting
    /// or transient tree arena indexes. Stage versions qualify this encoding.
    pub fn canonical_bytes(&self) -> Vec<u8> {
        fn frame(out: &mut Vec<u8>, bytes: &[u8]) {
            out.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
            out.extend_from_slice(bytes);
        }
        fn symbol(out: &mut Vec<u8>, value: SymbolId) {
            out.extend_from_slice(&value.bits().to_le_bytes());
        }
        let mut out = b"dm-resolved-meaning-v1\0".to_vec();
        match self {
            Self::Missing => out.push(0),
            Self::Unsupported(query) => {
                out.push(1);
                frame(
                    &mut out,
                    &serde_json::to_vec(query).expect("query serialization is infallible"),
                );
            }
            Self::Presence(value) => {
                out.extend_from_slice(&[2, u8::from(*value)]);
            }
            Self::DeclaredType(value) => {
                out.extend_from_slice(&[3, u8::from(value.is_some())]);
                if let Some(value) = value {
                    symbol(&mut out, *value);
                }
            }
            Self::InstanceField {
                declaring_owner,
                name,
            } => {
                out.push(4);
                symbol(&mut out, *declaring_owner);
                symbol(&mut out, *name);
            }
            Self::Value(value) => {
                out.push(5);
                frame(&mut out, &value.canonical_bytes());
            }
            Self::Slot {
                symbol: slot,
                owner,
                name,
            } => {
                out.push(6);
                symbol(&mut out, *slot);
                symbol(&mut out, *owner);
                symbol(&mut out, *name);
            }
            Self::Symbol(value) => {
                out.push(7);
                symbol(&mut out, *value);
            }
            Self::Symbols(values) => {
                out.push(8);
                out.extend_from_slice(&(values.len() as u64).to_le_bytes());
                for value in values {
                    symbol(&mut out, *value);
                }
            }
            Self::Members(values) => {
                out.push(9);
                out.extend_from_slice(&(values.len() as u64).to_le_bytes());
                for value in values {
                    frame(&mut out, &value.canonical_bytes());
                }
            }
            Self::IntrinsicProc {
                declaring_owner,
                name,
            } => {
                out.push(10);
                symbol(&mut out, *declaring_owner);
                symbol(&mut out, *name);
            }
            Self::RetainedProc {
                declaring_owner,
                name,
                verb,
                engine_identity,
                ..
            } => {
                out.push(11);
                symbol(&mut out, *declaring_owner);
                symbol(&mut out, *name);
                out.push(u8::from(*verb));
                out.extend_from_slice(&engine_identity.to_le_bytes());
                // The immutable engine identity qualifies its named callable;
                // its physical procedure-table index is not semantic evidence.
            }
            Self::Member {
                owner, name, data, ..
            } => {
                out.push(12);
                symbol(&mut out, *owner);
                symbol(&mut out, *name);
                frame(&mut out, &data.canonical_bytes());
            }
            Self::Resource { path, content } => {
                out.push(13);
                symbol(&mut out, *path);
                out.extend_from_slice(&content.to_le_bytes());
            }
            Self::ProcedureStatic(value) => {
                out.push(14);
                frame(&mut out, &value.canonical_bytes());
            }
        }
        out
    }
}

/// Grammar-shaped explicit callable path; authority comes only from resolution.
pub fn procedure_value_query(path: &str) -> Option<ResolveQuery> {
    let (owner, name, verb) = if let Some((owner, name)) = path.rsplit_once("/proc/") {
        (owner, name, false)
    } else if let Some((owner, name)) = path.rsplit_once("/verb/") {
        (owner, name, true)
    } else {
        return None;
    };
    if name.is_empty() || name.contains('/') {
        return None;
    }
    Some(ResolveQuery::ProcedureValue {
        owner: SymbolId::of(if owner.is_empty() { "/" } else { owner }),
        name: SymbolId::of(name),
        verb,
        formal: true,
    })
}

/// The sole view of other declarations and resource search available to lowering.
/// Implementations must answer from one immutable build snapshot.
pub trait Resolver: Sync {
    /// Certifies every answer (including negatives and Unsupported) in this
    /// domain for this immutable issuer. Custom/mutable hosts remain uncertified.
    /// Include resolver schema and every precedence/overlay input; compute once.
    fn domain_version(&self, _domain: ReadDomain) -> Option<u128> {
        None
    }

    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning;
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dependency_wire_preserves_negative_and_ordered_meaning() {
        let owner = SymbolId::of("/obj/probe");
        let name = SymbolId::of("work");
        let query = ResolveQuery::ProcedureValue {
            owner,
            name,
            verb: false,
            formal: true,
        };
        assert_eq!(
            serde_json::from_slice::<ResolveQuery>(&serde_json::to_vec(&query).unwrap()).unwrap(),
            query
        );
        assert_ne!(
            ResolvedMeaning::Missing.canonical_bytes(),
            ResolvedMeaning::Presence(false).canonical_bytes()
        );
        assert_ne!(
            ResolvedMeaning::DeclaredType(None).canonical_bytes(),
            ResolvedMeaning::Unsupported(query).canonical_bytes()
        );
        assert_ne!(
            ResolvedMeaning::Symbols(vec![owner, name]).canonical_bytes(),
            ResolvedMeaning::Symbols(vec![name, owner]).canonical_bytes()
        );
        let retained = |wire_proc, engine_identity| ResolvedMeaning::RetainedProc {
            declaring_owner: owner,
            name,
            verb: false,
            engine_identity,
            wire_proc,
        };
        assert_eq!(
            retained(1, 9).canonical_bytes(),
            retained(8, 9).canonical_bytes()
        );
        assert_ne!(
            retained(1, 9).canonical_bytes(),
            retained(1, 10).canonical_bytes()
        );
    }
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
