//! Representation observations, separate from retained-owner byte accounting.
use dm_ir::{SymRef, SymbolicCode};
use serde::Serialize;
use std::{collections::BTreeSet, mem::size_of};

#[derive(Serialize)]
pub struct RelocationMetrics {
    pub unique_code_objects: u64,
    pub relocation_sites: u64,
    pub source_inline_sites: u64,
    pub non_source_sites: u64,
    /// Sum of per-code distinct non-source references, not global distinct IDs.
    pub sum_unique_non_source_references_per_code: u64,
    pub words_len: u64,
    pub words_capacity: u64,
    pub relocations_capacity: u64,
    pub relocation_size_bytes: usize,
    pub sym_ref_size_bytes: usize,
}
impl Default for RelocationMetrics {
    fn default() -> Self {
        Self {
            unique_code_objects: 0,
            relocation_sites: 0,
            source_inline_sites: 0,
            non_source_sites: 0,
            sum_unique_non_source_references_per_code: 0,
            words_len: 0,
            words_capacity: 0,
            relocations_capacity: 0,
            relocation_size_bytes: size_of::<dm_ir::Relocation>(),
            sym_ref_size_bytes: size_of::<SymRef>(),
        }
    }
}
impl RelocationMetrics {
    /// The parent Arc ownership guard calls this once per retained code object.
    pub(super) fn observe(&mut self, code: &SymbolicCode) {
        self.unique_code_objects += 1;
        self.relocation_sites += code.relocations().len() as u64;
        let mut distinct = BTreeSet::new();
        for relocation in code.relocations() {
            match relocation.reference {
                SymRef::SourceFile(_) | SymRef::SourceLine(_) | SymRef::LineDelta(_) => {
                    self.source_inline_sites += 1;
                }
                reference => {
                    self.non_source_sites += 1;
                    distinct.insert(reference);
                }
            }
        }
        self.sum_unique_non_source_references_per_code += distinct.len() as u64;
        let (words, relocations) = code.storage_capacities();
        self.words_len += code.words().len() as u64;
        self.words_capacity += words as u64;
        self.relocations_capacity += relocations as u64;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{Relocation, RelocationEncoding, SymbolId};
    #[test]
    fn counts_sources_and_per_code_unique_references_separately() {
        let references = [
            SymRef::SourceFile(0),
            SymRef::SourceLine(1),
            SymRef::String(SymbolId::of("repeat")),
            SymRef::String(SymbolId::of("repeat")),
        ];
        let code = SymbolicCode::new(
            vec![0; 4],
            references
                .into_iter()
                .enumerate()
                .map(|(index, reference)| Relocation {
                    offset: index as u32,
                    reference,
                    encoding: RelocationEncoding::Direct,
                })
                .collect(),
        )
        .unwrap();
        let mut metrics = RelocationMetrics::default();
        metrics.observe(&code);
        metrics.observe(&code);
        assert_eq!(metrics.relocation_sites, 8);
        assert_eq!(metrics.source_inline_sites, 4);
        assert_eq!(metrics.non_source_sites, 4);
        assert_eq!(metrics.sum_unique_non_source_references_per_code, 2);
        assert_eq!(
            metrics.relocations_capacity,
            code.storage_capacities().1 as u64 * 2
        );
    }
}
