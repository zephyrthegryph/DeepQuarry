//! Program-state boundary for lowering. No tree arena or output index crosses it.

use crate::{DeclarationMeaning, SemanticValue, SymbolId};
use std::sync::Arc;

#[derive(
    Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
pub enum ReadDomain {
    Tree,
    ResourceSearch,
    /// Exact current type/parent/ancestor roster for this known owner.
    /// Member, scalar and global namespace queries require other domains.
    OwnerHierarchy(SymbolId),
    /// Query-qualified callable owner certificate; fallback answers may decline.
    OwnerCallable(ResolveQuery),
    /// Current source declaration/storage query; scalar values use OwnerScalar.
    OwnerVariable(ResolveQuery),
    /// Exact admitted scalar result; process-local and never a disk receipt.
    OwnerScalar(ResolveQuery),
    /// Exact admitted procedure static declaration roster, process-local only.
    OwnerProcedureStatic(crate::ProcedureIdentity),
    /// Exact immutable compiler constant catalog, process-local only.
    PredefinedCatalog(SymbolId),
    /// Exact alias catalog and, only on fallback, current source hierarchy.
    RuntimeCatalog(SymbolId),
}

impl ReadDomain {
    /// Process-local issuer receipts must never authorize a disk artifact.
    pub const fn persistent_version(self) -> bool {
        !matches!(
            self,
            Self::OwnerHierarchy(_)
                | Self::OwnerCallable(_)
                | Self::OwnerVariable(_)
                | Self::OwnerScalar(_)
                | Self::OwnerProcedureStatic(_)
                | Self::PredefinedCatalog(_)
                | Self::RuntimeCatalog(_)
        )
    }
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
    // Append new variants: persisted serde enum indices must remain stable.
    /// Runtime method dispatch anchors to the nearest inherited source formal,
    /// which may belong to an ancestor of the selected receiver declaration.
    /// Unlike a literal path, this does not require an own formal declaration.
    MethodProcedureValue {
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
    },
    /// Ordered source declaration identities and metadata, excluding executable bodies.
    DeclarationChain {
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
    },
    /// Name availability for explicit dynamic member dispatch, excluding global procs.
    MemberCallableName(SymbolId),
    /// Dynamic selector namespace: procedures take priority over verbs by name.
    MemberCallableVerbName(SymbolId),
}

/// Source declaration form is independent of its executable implementation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProcedureDefinition {
    Declare,
    Override,
    Reopen,
    Implicit,
}

impl ResolveQuery {
    pub const fn domain(self) -> ReadDomain {
        match self {
            Self::MemberCallableVerbName(_) | Self::MemberCallableName(_) => {
                ReadDomain::OwnerCallable(self)
            }
            Self::ProcedureStatic { procedure, .. } => ReadDomain::OwnerProcedureStatic(procedure),
            Self::Resource(_) | Self::ResourceIn { .. } => ReadDomain::ResourceSearch,
            Self::Type(owner) | Self::Parent(owner) | Self::Ancestry(owner) => {
                ReadDomain::OwnerHierarchy(owner)
            }
            Self::HasMemberVar { .. }
            | Self::DeclaredVarType { .. }
            | Self::VarStorage { .. }
            | Self::StaticVar { .. }
            | Self::UniqueStaticVar(_) => ReadDomain::OwnerVariable(self),
            Self::GlobalProc(_)
            | Self::Signature(_)
            | Self::HasMemberProc { .. }
            | Self::Proc { .. }
            | Self::ProcedureValue { .. }
            | Self::MethodProcedureValue { .. }
            | Self::OverrideChain { .. }
            | Self::DeclarationChain { .. } => ReadDomain::OwnerCallable(self),
            Self::Var { .. } | Self::GlobalVar(_) | Self::Constant { .. } => {
                ReadDomain::OwnerScalar(self)
            }
            Self::PredefinedConstant(name) => ReadDomain::PredefinedCatalog(name),
            Self::RuntimeType(path) => ReadDomain::RuntimeCatalog(path),
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
    Symbols(Arc<[SymbolId]>),
    Members(Arc<[ResolvedMeaning]>),
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
    /// Exact source structural answer; occurrence and predecessor are symbolic,
    /// never dense arena/output indices. Executable content is intentionally absent.
    Declaration {
        identity: crate::ProcedureIdentity,
        definition: ProcedureDefinition,
        previous: Option<crate::ProcedureIdentity>,
        data: Arc<DeclarationMeaning>,
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
                for value in values.iter() {
                    symbol(&mut out, *value);
                }
            }
            Self::Members(values) => {
                out.push(9);
                out.extend_from_slice(&(values.len() as u64).to_le_bytes());
                for value in values.iter() {
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
            Self::Declaration {
                identity,
                definition,
                previous,
                data,
            } => {
                out.push(15);
                out.push(u8::from(previous.is_some()));
                let mut declaration = |identity: &crate::ProcedureIdentity| {
                    symbol(&mut out, identity.owner);
                    symbol(&mut out, identity.name);
                    out.push(u8::from(identity.verb));
                    out.extend_from_slice(&identity.occurrence.to_le_bytes());
                };
                declaration(identity);
                if let Some(previous) = previous {
                    declaration(previous);
                }
                out.push(match definition {
                    ProcedureDefinition::Declare => 0,
                    ProcedureDefinition::Override => 1,
                    ProcedureDefinition::Reopen => 2,
                    ProcedureDefinition::Implicit => 3,
                });
                frame(&mut out, &data.canonical_bytes());
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
    /// True unless this immutable host has no dependency/semantic read observer.
    /// Exact replay may bypass resolve only when false. Internal memo counters
    /// and issuer storage are not observers; custom wrappers
    /// conservatively retain ordinary resolve calls unless explicitly delegated.
    fn observes_reads(&self) -> bool {
        true
    }

    /// Default-declining transparent instrumentation. Unlike observes_reads,
    /// this preserves delivery of admitted reads; semantic interceptors must
    /// not expose an inner provider that answers different queries/meanings.
    fn transparent_receipt_observer(&self) -> Option<crate::TransparentReceiptObserver<'_>> {
        None
    }

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
            ResolvedMeaning::Symbols(vec![owner, name].into()).canonical_bytes(),
            ResolvedMeaning::Symbols(vec![name, owner].into()).canonical_bytes()
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
            ReadDomain::OwnerVariable(ResolveQuery::UniqueStaticVar(SymbolId::of("counter")))
        );
        assert_eq!(
            ResolveQuery::PredefinedConstant(SymbolId::of("UNIX")).domain(),
            ReadDomain::PredefinedCatalog(SymbolId::of("UNIX"))
        );
    }
}

#[cfg(test)]
#[path = "resolver_sequence_tests.rs"]
mod sequence_tests;
