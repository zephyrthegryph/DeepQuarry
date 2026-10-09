//! Relative immutable origin leaves; current source authority is issued later.
use crate::{frontend::Contribution, Provenance};
use std::sync::Arc;

#[derive(Clone)]
pub(crate) enum OriginRoster {
    Owned(Vec<Provenance>),
    Bound(RelativeOriginRoster),
}
#[derive(Clone, Default)]
pub(crate) struct RelativeOriginRoster {
    chunks: Vec<(Arc<Contribution>, usize)>,
    len: usize,
}
pub(crate) struct OriginView<'a> {
    pub span: dm_ir::Span,
    original: &'a Provenance,
}
impl RelativeOriginRoster {
    pub(crate) fn push(&mut self, leaf: Arc<Contribution>, offset: usize) -> Option<()> {
        let len = self.len.checked_add(leaf.relative_origins().len())?;
        let shift = u32::try_from(offset).ok()?;
        leaf.relative_origin_max().checked_add(shift)?;
        self.chunks.push((leaf, offset));
        self.len = len;
        Some(())
    }
}
impl OriginRoster {
    pub(crate) fn len(&self) -> usize {
        match self {
            Self::Owned(v) => v.len(),
            Self::Bound(v) => v.len,
        }
    }
    pub(crate) fn iter(&self) -> impl Iterator<Item = OriginView<'_>> {
        let owned = match self {
            Self::Owned(v) => Some(v.as_slice()),
            Self::Bound(_) => None,
        };
        let bound = match self {
            Self::Bound(v) => Some(v.chunks.as_slice()),
            Self::Owned(_) => None,
        };
        owned
            .into_iter()
            .flatten()
            .map(|original| OriginView {
                span: original.span,
                original,
            })
            .chain(bound.into_iter().flatten().flat_map(|(leaf, offset)| {
                let shift = *offset as u32;
                leaf.relative_origins().iter().map(move |original| {
                    let mut span = original.span;
                    span.start += shift;
                    span.end += shift;
                    OriginView { span, original }
                })
            }))
    }
    pub(crate) fn into_owned(self) -> Vec<Provenance> {
        match self {
            Self::Owned(v) => v,
            Self::Bound(_) => self
                .iter()
                .map(|view| {
                    let mut origin = view.original.clone();
                    origin.span = view.span;
                    origin
                })
                .collect(),
        }
    }
}
impl From<Vec<Provenance>> for OriginRoster {
    fn from(v: Vec<Provenance>) -> Self {
        Self::Owned(v)
    }
}
impl std::fmt::Debug for OriginRoster {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_list()
            .entries(self.iter().map(|view| (view.span, view.original)))
            .finish()
    }
}
impl PartialEq for OriginRoster {
    fn eq(&self, other: &Self) -> bool {
        self.len() == other.len()
            && self.iter().zip(other.iter()).all(|(a, b)| {
                a.span == b.span
                    && a.original.include_occurrence == b.original.include_occurrence
                    && a.original.region == b.original.region
                    && a.original.expansion_stack == b.original.expansion_stack
            })
    }
}
impl PartialEq<Vec<Provenance>> for OriginRoster {
    fn eq(&self, other: &Vec<Provenance>) -> bool {
        self == &Self::Owned(other.clone())
    }
}
impl Eq for OriginRoster {}
