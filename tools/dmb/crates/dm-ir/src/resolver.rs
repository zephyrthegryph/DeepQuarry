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
        search_context: crate::PackedU128,
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
    /// Exact authored source chain, excluding uncaptured engine procedures.
    /// Missing certifies source absence only. Consumers still need the pinned
    /// engine's builtin contract before interpreting that absence as a builtin.
    SourceDeclarationChain {
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
    },
    /// Whether the captured engine declares this callable on the receiver or
    /// an ancestor, independently of any authored override or shadow. Positive
    /// captured rows are definitive; absence requires a complete inventory.
    IntrinsicCallable {
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
    },
    /// Whether any non-global engine proc or verb has this name. Source
    /// procedures never count, and root global builtins are not methods.
    IntrinsicCallableName(SymbolId),
    /// Fixed checker-DSL provenance, distinct from runtime intrinsic inventory.
    /// A mismatched/incompatible profile is Unsupported, never negative proof.
    CheckerIntrinsicCallable {
        profile: crate::PackedU128,
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
    },
    CheckerBuiltinVar {
        profile: crate::PackedU128,
        owner: SymbolId,
        name: SymbolId,
    },
    CheckerBuiltinProc {
        profile: crate::PackedU128,
        owner: SymbolId,
        name: SymbolId,
        verb: bool,
    },
    /// Captured authored formal variable declaration, excluding runtime-only
    /// fields and default-value overrides. Missing says SOURCE absence only.
    SourceVarDeclaration {
        owner: SymbolId,
        name: SymbolId,
    },
    /// Append-only wire identity. This is NOT ordinary Type/Parent/Ancestry;
    /// its answer requires the original tree's sealed complete hierarchy view.
    CertifiedHierarchy {
        kind: HierarchyQuestion,
        path: SymbolId,
    },
    /// Whether the type itself declares (or overrides) at least one procedure, or verb when `verb`, in source. `/T/proc` and `/T/verb`
    /// are type paths only then: DreamMaker rejects `typesof(/mob/living/carbon/verb)` as an undefined type path when nothing
    /// is declared under it, whatever the ancestors or subtypes declare.
    HasNamespaceMembers {
        owner: SymbolId,
        verb: bool,
    },
}

/// Qualified ORIGINAL hierarchy question. Member inventory completeness is a
/// different contract and cannot turn a certified hierarchy's absence unknown.
#[derive(
    Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd, Hash, serde::Serialize, serde::Deserialize,
)]
pub enum HierarchyQuestion {
    Type,
    Parent,
    Ancestry,
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
            // Intrinsic presence, hierarchy and inventory completeness are all
            // part of the tree's engine-qualified answer world. Do not reuse a
            // source-only owner certificate for these provenance questions.
            Self::IntrinsicCallable { .. }
            | Self::IntrinsicCallableName(_)
            | Self::CheckerIntrinsicCallable { .. }
            | Self::CheckerBuiltinVar { .. }
            | Self::CheckerBuiltinProc { .. }
            | Self::SourceVarDeclaration { .. } => ReadDomain::Tree,
            Self::SourceDeclarationChain { .. }
            | Self::MemberCallableVerbName(_)
            | Self::MemberCallableName(_) => ReadDomain::OwnerCallable(self),
            Self::ProcedureStatic { procedure, .. } => ReadDomain::OwnerProcedureStatic(procedure),
            Self::Resource(_) | Self::ResourceIn { .. } => ReadDomain::ResourceSearch,
            Self::Type(owner)
            | Self::Parent(owner)
            | Self::Ancestry(owner)
            | Self::CertifiedHierarchy { path: owner, .. } => ReadDomain::OwnerHierarchy(owner),
            Self::HasMemberVar { .. }
            | Self::DeclaredVarType { .. }
            | Self::VarStorage { .. }
            | Self::StaticVar { .. }
            | Self::UniqueStaticVar(_) => ReadDomain::OwnerVariable(self),
            Self::GlobalProc(_)
            | Self::Signature(_)
            | Self::HasMemberProc { .. }
            | Self::HasNamespaceMembers { .. }
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
        engine_identity: crate::PackedU128,
        wire_proc: u32,
    },
    Member {
        owner: SymbolId,
        name: SymbolId,
        fingerprint: crate::PackedU128,
        data: Arc<DeclarationMeaning>,
    },
    Resource {
        path: SymbolId,
        content: crate::PackedU128,
    },
    /// Exact source structural answer; occurrence and predecessor are symbolic,
    /// never dense arena/output indices. Executable content is intentionally absent.
    Declaration {
        identity: crate::ProcedureIdentity,
        definition: ProcedureDefinition,
        previous: Option<Box<crate::ProcedureIdentity>>,
        data: Arc<DeclarationMeaning>,
    },
}

impl ResolvedMeaning {
    /// Stable dependency evidence: complete semantic values, no debug formatting
    /// or transient tree arena indexes. Stage versions qualify this encoding.
    pub fn canonical_bytes(&self) -> Vec<u8> {
        self.canonical_bytes_using(&mut crate::canonical_encoding::Unmetered)
            .expect("unmetered native canonical allocation failed")
    }
    /// SAME byte encoder; transient allocations are funded before growth.
    pub fn canonical_bytes_using(&self, work: &mut dyn crate::CanonicalWork) -> std::io::Result<Vec<u8>> {
        crate::canonical_encoding::encode(crate::canonical_encoding::Root::Meaning(self), work)
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
    /// Exact compiler-issued semantic owner, when this implementation can prove
    /// it. This opaque address is valid only during the immutable resolver
    /// borrow: compare it, never dereference, persist, serialize or hash it.
    /// It is neither answer equality nor an answer-world/cache-version token.
    /// An unproven wrapper declines; only transparent original-owner delegates
    /// may forward the provenance of their retained source owner.
    fn source_owner(&self) -> Option<*const ()> {
        None
    }

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

    /// The identity of every answer this immutable resolver gives except resource searches (which read the file
    /// system): its declarations, procedure statics, catalogs and every precedence/overlay input. Two resolvers with
    /// equal worlds give equal answers to every other query, so an answer proven under one is carried to the other
    /// without resolving (`QueryDb::begin_answers`) and the dependency index keys records on it. `None`: unnamed.
    fn answer_world(&self) -> Option<u128> {
        None
    }

    /// The canonical bytes belong to this exact resolved answer. Defaults keep
    /// ordinary callbacks; pure delegates may forward this capability unchanged.
    fn resolve_with_canonical(&self, query: ResolveQuery) -> crate::CanonicalResolvedAnswer {
        crate::CanonicalResolvedAnswer::new(self.resolve(query))
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
        let retained = |wire_proc, engine_identity: u128| ResolvedMeaning::RetainedProc {
            declaring_owner: owner,
            name,
            verb: false,
            engine_identity: engine_identity.into(),
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
            search_context: 1.into(),
        };
        let second = ResolveQuery::ResourceIn {
            path,
            search_context: 2.into(),
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

#[cfg(test)]
mod hierarchy_wire_tests {
    use super::*;
    #[test]
    fn qualified_hierarchy_wire_tag_is_distinct_and_old_query_json_stays_exact() {
        let path = SymbolId::of("/datum/wire");
        let ordinary = serde_json::to_value(ResolveQuery::Type(path)).unwrap();
        assert_eq!(ordinary, serde_json::json!({"Type":path}));
        for kind in [
            HierarchyQuestion::Type,
            HierarchyQuestion::Parent,
            HierarchyQuestion::Ancestry,
        ] {
            let question = ResolveQuery::CertifiedHierarchy { kind, path };
            let wire = serde_json::to_value(question).unwrap();
            assert_eq!(
                wire,
                serde_json::json!({"CertifiedHierarchy":{"kind":kind,"path":path}})
            );
            assert_ne!(wire, ordinary);
            assert_eq!(
                serde_json::from_value::<ResolveQuery>(wire).unwrap(),
                question
            );
            assert_eq!(question.domain(), ReadDomain::OwnerHierarchy(path));
        }
    }
}
