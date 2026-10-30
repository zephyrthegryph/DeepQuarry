//! Borrowed ORIGINAL hierarchy authority, separate from member completeness.
//! No copied index/model, source re-read, secondary parser or negative guesses.
use super::*;
use dm_ir::{HierarchyQuestion, ResolvedMeaning as M};
use std::io;
pub struct HierarchyView<'a> {
    tree: &'a SemanticTree,
}
impl SemanticTree {
    pub fn certified_hierarchy(&self) -> Option<HierarchyView<'_>> {
        self.inventory
            .hierarchy_certified
            .then_some(HierarchyView { tree: self })
    }
}
enum AnswerSource<'a> {
    Missing,
    Symbol(SymbolId),
    Cached(&'a Arc<[SymbolId]>),
    Walk {
        tree: &'a SemanticTree,
        first: TypeId,
    },
}
/// Stack-only borrowed answer from the SAME certified native lookup/parent/cache.
/// Private variants prevent caller-created source authority.
pub struct HierarchyAnswer<'a> {
    source: AnswerSource<'a>,
    nodes: usize,
}
impl<'a> HierarchyView<'a> {
    pub fn require_tree(&self, tree: &SemanticTree) -> bool {
        std::ptr::eq(self.tree, tree)
    }
    pub fn node_bound(&self) -> usize {
        self.tree.types.len()
    }
    pub fn borrowed_answer(&self, kind: HierarchyQuestion, path: SymbolId) -> HierarchyAnswer<'a> {
        let source = match kind {
            HierarchyQuestion::Type => self
                .tree
                .lookup_type(path)
                .map(|_| AnswerSource::Symbol(path))
                .unwrap_or(AnswerSource::Missing),
            HierarchyQuestion::Parent => self
                .tree
                .lookup_type(path)
                .and_then(|id| self.tree.parent(id))
                .map(|id| AnswerSource::Symbol(self.tree.types[id.index()].path))
                .unwrap_or(AnswerSource::Missing),
            HierarchyQuestion::Ancestry => {
                if let Some(paths) = self.tree.owner_ancestry.get(&path) {
                    AnswerSource::Cached(paths)
                } else if let Some(first) = self.tree.lookup_type(path) {
                    AnswerSource::Walk {
                        tree: self.tree,
                        first,
                    }
                } else {
                    AnswerSource::Missing
                }
            }
        };
        HierarchyAnswer {
            source,
            nodes: self.tree.types.len(),
        }
    }
    /// Ordinary native answer still materializes its original owned result.
    pub fn answer(&self, kind: HierarchyQuestion, path: SymbolId) -> M {
        self.borrowed_answer(kind, path).to_owned()
    }
}
impl HierarchyAnswer<'_> {
    pub fn positive(&self) -> bool {
        !matches!(&self.source, AnswerSource::Missing)
    }
    pub fn to_owned(&self) -> M {
        match &self.source {
            AnswerSource::Missing => M::Missing,
            AnswerSource::Symbol(path) => M::Symbol(*path),
            AnswerSource::Cached(paths) => M::Symbols(Arc::clone(paths)),
            AnswerSource::Walk { tree, first } => {
                let mut paths = Vec::new();
                let mut current = Some(*first);
                while let Some(id) = current {
                    paths.push(tree.types[id.index()].path);
                    current = tree.parent(id);
                }
                M::Symbols(paths.into())
            }
        }
    }
    /// No ancestry Vec/Arc or canonical Vec is allocated. The external work
    /// counter and checkpoint cover BOTH fallback count and emit walks. Cached
    /// paths use the same budget, and malformed/cyclic sources refuse explicitly.
    pub fn write_canonical(
        &self,
        remaining: &mut usize,
        mut checkpoint: impl FnMut() -> io::Result<()>,
        sink: impl FnMut(&[u8]) -> io::Result<()>,
    ) -> io::Result<()> {
        fn step(
            left: &mut usize,
            checkpoint: &mut impl FnMut() -> io::Result<()>,
        ) -> io::Result<()> {
            if *left == 0 {
                return Err(io::Error::other(
                    "native hierarchy answer work budget exceeded",
                ));
            }
            *left -= 1;
            checkpoint()
        }
        step(remaining, &mut checkpoint)?;
        let mut out = dm_ir::hierarchy_canonical::Writer::new(sink);
        match &self.source {
            AnswerSource::Missing => out.missing(),
            AnswerSource::Symbol(path) => out.symbol(*path),
            AnswerSource::Cached(paths) => {
                if paths.len() > self.nodes {
                    return Err(io::Error::other(
                        "original hierarchy cache exceeds certified node roster",
                    ));
                }
                out.symbols_start(paths.len())?;
                for path in paths.iter() {
                    step(remaining, &mut checkpoint)?;
                    out.symbol_item(*path)?;
                }
                Ok(())
            }
            AnswerSource::Walk { tree, first } => {
                let mut count = 0usize;
                let mut current = Some(*first);
                while let Some(id) = current {
                    step(remaining, &mut checkpoint)?;
                    count += 1;
                    if count > self.nodes {
                        return Err(io::Error::other(
                            "original certified hierarchy parent cycle",
                        ));
                    }
                    current = tree.parent(id);
                }
                out.symbols_start(count)?;
                current = Some(*first);
                for _ in 0..count {
                    step(remaining, &mut checkpoint)?;
                    let id = current.ok_or_else(|| {
                        io::Error::other("original hierarchy changed during immutable visit")
                    })?;
                    out.symbol_item(tree.types[id.index()].path)?;
                    current = tree.parent(id);
                }
                Ok(())
            }
        }
    }
}
#[cfg(test)]
#[path = "certified_hierarchy_tests.rs"]
mod tests;
