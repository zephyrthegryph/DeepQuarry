//! Shared static plans: actual spelling owners and conservative private-index charge.
use super::*;
impl HeapCensus {
    /// Count exposed shared payload once. The return value is a conservative
    /// hash bucket charge for admission; it is not added to exact census totals.
    pub(super) fn symbol_table_storage(
        &mut self,
        owner: &str,
        table: &dm_ir::SymbolTable,
    ) -> usize {
        let address = table as *const dm_ir::SymbolTable as usize;
        if !self.collections.insert(address) {
            return 0;
        }
        let storage = table.visit_storage(|_, spelling| self.arc_text(owner, spelling));
        self.owner(owner).observed_items += storage.local_len as u64;
        // std HashMap exposes usable capacity, not allocated bucket count. Twice
        // capacity plus one bounds the private power-of-two bucket roster, and
        // includes one control byte per bucket plus alignment padding.
        let mut charge = if storage.local_capacity == 0 {
            0
        } else {
            storage
                .local_capacity
                .saturating_mul(2)
                .saturating_add(1)
                .saturating_mul(size_of::<(dm_ir::SymbolId, Arc<str>)>().saturating_add(1))
                .saturating_add(64)
        };
        if let Some(parent) = storage.parent {
            if self.arc_object(owner, parent) {
                charge = charge.saturating_add(self.symbol_table_storage(owner, parent));
            }
        }
        charge
    }
}
pub(crate) fn weight(
    receipt: &Arc<dm_tree::frontend::RelativeStaticPlan>,
    key: &[u8],
) -> Option<usize> {
    let mut census = HeapCensus::new("resident_startup_admission");
    census.arc_object("resident_startup.receipt", receipt);
    census.arc_text("resident_startup.source", receipt.source());
    let private_indexes = census.static_plan(receipt.plan());
    let encounters = census.buffer_encounters;
    let report = census.finish();
    if report.unknown_capacity_payload_bytes != 0
        || report.owners.iter().any(|owner| !owner.unknown.is_empty())
    {
        return None;
    }
    Some(
        usize::try_from(report.unique_known_capacity_bytes)
            .ok()?
            .saturating_add(private_indexes)
            .saturating_add(encounters.saturating_mul(64))
            .saturating_add(key.len())
            .saturating_add(4096),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/proc/p()\n    var/static/count=1\n    return count\n".into())
        }
    }
    #[test]
    fn issued_static_plan_owners_and_exact_key_length_are_charged() {
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Source,
            &Default::default(),
            1,
        )
        .unwrap();
        let body = &frontend.bodies[0];
        let tree = &frontend.snapshot.tree;
        let member = tree.member(body.member).unwrap();
        let identity = dm_ir::ProcedureIdentity {
            owner: tree.type_node(member.owner).unwrap().path,
            name: member.name,
            verb: false,
            occurrence: tree.member_occurrence(body.member).unwrap(),
        };
        let arena = dm_tree::frontend::BodyArena::new(&frontend);
        arena
            .with_parsed(body, |parsed| {
                let issued = parsed.capture_stored_declarations(identity).unwrap();
                let receipt = issued.relative_payload().unwrap();
                assert_eq!(receipt.plan().declarations.len(), 1);
                let small = weight(&receipt, b"key").unwrap();
                assert!(small > std::mem::size_of::<dm_tree::frontend::RelativeStaticPlan>());
                let large_key = vec![0; 4096];
                let large = weight(&receipt, &large_key).unwrap();
                assert_eq!(large - small, large_key.len() - 3);
            })
            .unwrap();
    }
    #[test]
    fn immutable_symbol_parents_are_counted_once_without_materialized_ordered_rosters() {
        let mut base = dm_ir::SymbolTable::default();
        base.intern("parent spelling").unwrap();
        let base = Arc::new(base);
        let mut left = dm_ir::SymbolTable::overlay(Arc::clone(&base));
        left.intern("left spelling").unwrap();
        let mut right = dm_ir::SymbolTable::overlay(base);
        right.intern("right spelling").unwrap();
        let mut census = HeapCensus::new("symbols");
        let first = census.symbol_table_storage("symbols", &left);
        let second = census.symbol_table_storage("symbols", &right);
        assert!(first > second);
        assert_eq!(census.symbol_table_storage("symbols", &left), 0);
        let report = census.finish();
        assert_eq!(report.owners[0].observed_items, 3);
        assert!(report.unique_known_capacity_bytes >= 3 * "left spelling".len() as u64);
    }
}
