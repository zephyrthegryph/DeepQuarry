//! Pressure charging omits diagnostic indexes and refuses oversized walks early.
use super::*;
pub(super) struct Budget {
    limit: usize,
    charged: usize,
    pub(super) declined: bool,
    allocations: Option<Vec<dm_session::PressureAllocation>>,
}
impl HeapCensus {
    pub(crate) fn compact_symbolic_charge(limit: usize) -> Self {
        let mut census = Self::new("compact_symbolic_charge");
        census.compact_charge = Some(Budget {
            limit,
            charged: 0,
            declined: false,
            allocations: None,
        });
        census
    }
    pub(crate) fn compact_pressure_allocations(limit: usize) -> Self {
        let mut census = Self::compact_symbolic_charge(limit);
        census.compact_charge.as_mut().unwrap().allocations = Some(Vec::new());
        census
    }
    pub(crate) fn finish_compact_pressure_allocations(
        mut self,
    ) -> Option<Vec<dm_session::PressureAllocation>> {
        let allocations = self.compact_charge.as_mut()?.allocations.take()?;
        let charge = self.finish_compact_symbolic_charge()?;
        let total = allocations
            .iter()
            .try_fold(0usize, |sum, item| sum.checked_add(item.bytes))?;
        (total == charge).then_some(allocations)
    }
    pub(super) fn admit_compact_buffer(&mut self, pointer: usize, capacity: usize) -> bool {
        let Some(budget) = &mut self.compact_charge else {
            return true;
        };
        if budget.declined {
            return false;
        }
        if capacity == 0 || self.allocations.contains(&pointer) {
            return true;
        }
        let charged = budget
            .charged
            .checked_add(capacity)
            .and_then(|n| n.checked_add(64));
        match charged.filter(|n| *n <= budget.limit) {
            Some(charged) => {
                budget.charged = charged;
                if let Some(allocations) = &mut budget.allocations {
                    allocations.push(dm_session::PressureAllocation {
                        address: pointer,
                        bytes: capacity.checked_add(64).unwrap(),
                    });
                }
                true
            }
            None => {
                budget.declined = true;
                false
            }
        }
    }
    pub(super) fn reject_compact_unknown(&mut self, owner: &str, reason: &str) {
        if owner == "procedure_metadata.recipe"
            && reason == "Arc control block and allocator overhead are unavailable"
        {
            return;
        }
        if let Some(budget) = &mut self.compact_charge {
            budget.declined = true;
        }
    }
    pub(super) fn reject_compact_collection(&mut self) -> bool {
        if let Some(budget) = &mut self.compact_charge {
            budget.declined = true;
            true
        } else {
            false
        }
    }
    pub(super) fn symbolic_code(&mut self, code: &Arc<dm_ir::SymbolicCode>) {
        if self.arc_object("frozen_code", code) {
            if self.compact_charge.is_none() {
                self.frozen_code_metrics.observe(code);
            }
            self.owner("frozen_code").observed_items +=
                (code.words().len() + code.relocations().len()) as u64;
            code.visit_storage(|address, length, capacity| {
                self.buffer("frozen_code", address, length, capacity);
            });
        }
    }
    /// Logical payload charge only. A per-exposed-allocation allocator/control
    /// allowance is not measured private memory; the shared core charges its
    /// own bucket, claim, lease and incidence bookkeeping separately.
    pub(crate) fn finish_compact_symbolic_charge(mut self) -> Option<usize> {
        if self
            .compact_charge
            .as_ref()
            .is_some_and(|budget| budget.declined)
        {
            return None;
        }
        self.owner("procedure_metadata.recipe")
            .unknown
            .remove("Arc control block and allocator overhead are unavailable");
        let mut capacity = 0usize;
        for owner in self.owners.values() {
            if owner.unknown_capacity_payload_bytes != 0 || !owner.unknown.is_empty() {
                return None;
            }
            capacity =
                capacity.checked_add(usize::try_from(owner.unique_known_capacity_bytes).ok()?)?;
        }
        capacity.checked_add(self.allocations.len().checked_mul(64)?)
    }
    pub(super) fn frozen_code(&mut self, code: &Arc<dm_codegen_byond::FrozenProc>) {
        if !self.arc_object("frozen_code", code) {
            return;
        }
        self.symbolic_code(&code.shared_code());
        self.exposed_buffer(
            "frozen_code",
            code.labels().as_ptr() as usize,
            std::mem::size_of_val(code.labels()),
            code.label_storage_capacity()
                .saturating_mul(size_of::<Option<u32>>()),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pressure_scratch_declines_without_collecting_relocations_or_addresses() {
        let code = Arc::new(
            dm_ir::SymbolicCode::new(
                vec![0; 2],
                vec![
                    dm_ir::Relocation {
                        offset: 0,
                        reference: dm_ir::SymRef::String(dm_ir::SymbolId::of("a")),
                        encoding: dm_ir::RelocationEncoding::Direct,
                    },
                    dm_ir::Relocation {
                        offset: 1,
                        reference: dm_ir::SymRef::String(dm_ir::SymbolId::of("b")),
                        encoding: dm_ir::RelocationEncoding::Direct,
                    },
                ],
            )
            .unwrap(),
        );
        let mut diagnostic = HeapCensus::new("diagnostic");
        diagnostic.symbolic_code(&code);
        assert_eq!(
            diagnostic
                .frozen_code_metrics
                .sum_unique_non_source_references_per_code,
            2
        );
        let mut compact = HeapCensus::compact_symbolic_charge(usize::MAX);
        compact.symbolic_code(&code);
        assert_eq!(compact.frozen_code_metrics.unique_code_objects, 0);
        assert!(compact.finish_compact_symbolic_charge().is_some());
        let mut rejected = HeapCensus::compact_symbolic_charge(64);
        assert!(!rejected.exposed_buffer("large", 1, 1024, 1024));
        for pointer in 2..10000 {
            rejected.exposed_buffer("later", pointer, 1, 1);
        }
        assert!(rejected.allocations.is_empty());
        assert!(rejected.finish_compact_symbolic_charge().is_none());
    }
    #[test]
    fn pressure_footprints_deduplicate_actual_buffers_and_decline_unknown_capacity() {
        let bytes: Arc<[u8]> = Arc::from([1u8, 2, 3]);
        let mut census = HeapCensus::compact_pressure_allocations(1024);
        census.slice("first", &bytes, true);
        census.slice("second", &bytes, true);
        let footprint = census.finish_compact_pressure_allocations().unwrap();
        assert_eq!(footprint.len(), 1);
        assert_eq!(footprint[0].address, bytes.as_ptr() as usize);
        assert_eq!(footprint[0].bytes, bytes.len() + 64);
        let mut unknown = HeapCensus::compact_pressure_allocations(1024);
        unknown.slice("unknown_capacity", &bytes, false);
        assert!(unknown.finish_compact_pressure_allocations().is_none());
    }
}
