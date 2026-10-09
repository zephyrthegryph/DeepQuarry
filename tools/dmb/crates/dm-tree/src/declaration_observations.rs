//! Exact source-domain observations used before semantic member normalization.
//! These answers never impersonate queries against an already resolved tree.
use crate::{
    declaration_contributions::{DeclarationKey, KeyedDeclarations, TypeContribution},
    MemberKind, SemanticTree,
};
use dm_ir::{OpaqueFieldBase, SymbolId};
use std::sync::Arc;
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum SourceQuery {
    Owner {
        owner: SymbolId,
    },
    SelectedPredecessor {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
    },
    Parent {
        path: SymbolId,
    },
    Family {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
    },
    CallableAnchor {
        owner: SymbolId,
        name: SymbolId,
    },
    OpaqueField {
        owner: SymbolId,
        name: SymbolId,
    },
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum SourceDomain {
    ParentGraph,
    AuthoredDeclarations,
    CallableNamespace,
    EngineDeclarations,
}
impl SourceQuery {
    pub fn domain(self) -> SourceDomain {
        match self {
            Self::Parent { .. } => SourceDomain::ParentGraph,
            Self::Owner { .. } | Self::Family { .. } | Self::SelectedPredecessor { .. } => {
                SourceDomain::AuthoredDeclarations
            }
            Self::CallableAnchor { .. } => SourceDomain::CallableNamespace,
            Self::OpaqueField { .. } => SourceDomain::EngineDeclarations,
        }
    }
}
#[derive(Clone, Debug)]
pub struct FamilyAnswer {
    owner: Option<Arc<TypeContribution>>,
    rows: Arc<[usize]>,
}
impl FamilyAnswer {
    /// Borrow exact retained owner/index backing without materializing rows.
    pub fn retained_parts(&self) -> (Option<&Arc<TypeContribution>>, &Arc<[usize]>) {
        (self.owner.as_ref(), &self.rows)
    }
    pub fn rows(
        &self,
    ) -> impl ExactSizeIterator<Item = &crate::declaration_contributions::DeclarationRow>
           + DoubleEndedIterator
           + '_ {
        self.rows.iter().map(|&index| {
            &self
                .owner
                .as_ref()
                .expect("nonempty family has its owner")
                .rows()[index]
        })
    }
}
impl PartialEq for FamilyAnswer {
    fn eq(&self, other: &Self) -> bool {
        self.rows.len() == other.rows.len() && self.rows().eq(other.rows())
    }
}
impl Eq for FamilyAnswer {}
#[derive(Clone, Debug)]
pub struct OwnerAnswer(pub Option<Arc<TypeContribution>>);
impl PartialEq for OwnerAnswer {
    fn eq(&self, other: &Self) -> bool {
        match (&self.0, &other.0) {
            (None, None) => true,
            (Some(a), Some(b)) => a.owner() == b.owner() && a.rows() == b.rows(),
            _ => false,
        }
    }
}
impl Eq for OwnerAnswer {}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SourceAnswer {
    Owner(OwnerAnswer),
    SelectedPredecessor(Option<DeclarationKey>),
    /// Outer None means no such type; Some(None) means the graph root.
    Parent(Option<Option<SymbolId>>),
    Family(FamilyAnswer),
    CallableAnchor(Option<MemberKind>),
    OpaqueField(Option<OpaqueFieldBase>),
}
/// Borrowed current authority. Only the exact immutable answers may outlive it.
pub(crate) struct DeclarationHost<'a> {
    pub declarations: &'a KeyedDeclarations,
    pub tree: &'a SemanticTree,
    pub member_keys: &'a [DeclarationKey],
    pub callable_kinds: &'a crate::callable_namespace::CallableKinds,
}
impl DeclarationHost<'_> {
    pub fn answer(&self, query: SourceQuery) -> SourceAnswer {
        match query {
            SourceQuery::Owner { owner } => {
                SourceAnswer::Owner(OwnerAnswer(self.declarations.owner(owner).cloned()))
            }
            SourceQuery::SelectedPredecessor { owner, name, kind } => {
                SourceAnswer::SelectedPredecessor(
                    self.tree
                        .lookup_type(owner)
                        .and_then(|id| self.tree.direct.get(&(id, name, kind)))
                        .and_then(|id| self.member_keys.get(id.index()))
                        .copied(),
                )
            }
            SourceQuery::Parent { path } => {
                SourceAnswer::Parent(self.tree.lookup_type(path).map(|id| {
                    self.tree
                        .parent(id)
                        .map(|parent| self.tree.types()[parent.index()].path)
                }))
            }
            SourceQuery::Family { owner, name, kind } => {
                let contribution = self.declarations.owner(owner).cloned();
                let rows = contribution
                    .as_ref()
                    .map(|owner| {
                        owner
                            .rows()
                            .iter()
                            .enumerate()
                            .filter_map(|(index, row)| match &row.skeleton {
                                crate::Skeleton::Member {
                                    name: actual,
                                    kind: actual_kind,
                                    ..
                                } if *actual == name && *actual_kind == kind => Some(index),
                                _ => None,
                            })
                            .collect::<Vec<_>>()
                    })
                    .unwrap_or_default();
                SourceAnswer::Family(FamilyAnswer {
                    owner: contribution,
                    rows: rows.into(),
                })
            }
            SourceQuery::CallableAnchor { owner, name } => {
                SourceAnswer::CallableAnchor(self.callable_kinds.get(&(owner, name)).copied())
            }
            SourceQuery::OpaqueField { owner, name } => {
                SourceAnswer::OpaqueField(self.tree.intrinsic_fields.get(&(owner, name)).cloned())
            }
        }
    }
}

impl dm_session::observations::ObservationHost<SourceQuery, SourceAnswer, SourceDomain>
    for DeclarationHost<'_>
{
    fn answer(&self, query: &SourceQuery) -> SourceAnswer {
        self.answer(*query)
    }
}
