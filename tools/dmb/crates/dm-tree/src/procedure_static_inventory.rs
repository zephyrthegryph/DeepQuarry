//! Immutable captured static declarations shared by all startup consumers.
use super::*;
/// Issued from exact plans; read-only users cannot replace declarations or keys.
pub struct StaticInventory {
    pub(super) procedures: HashSet<ProcedureIdentity>,
    pub(super) declarations:
        std::collections::BTreeMap<ProcedureStaticIdentity, Arc<ProcedureStaticDeclaration>>,
}
impl StaticInventory {
    pub fn from_plans<'p>(
        plans: impl IntoIterator<Item = (ProcedureIdentity, &'p StaticPlan)>,
    ) -> Result<Self, String> {
        let mut procedures = HashSet::new();
        let mut declarations = std::collections::BTreeMap::new();
        for (procedure, plan) in plans {
            if plan.procedure != procedure {
                return Err("procedure static inventory context mismatch".into());
            }
            if !procedures.insert(procedure) {
                return Err("duplicate procedure static inventory".into());
            }
            for declaration in &plan.declarations {
                if declaration.identity.procedure != procedure {
                    return Err("static declaration belongs to another procedure".into());
                }
                if declarations
                    .insert(declaration.identity, Arc::new(declaration.clone()))
                    .is_some()
                {
                    return Err("duplicate structural static declaration".into());
                }
            }
        }
        Ok(Self {
            procedures,
            declarations,
        })
    }
    pub fn procedure_storage(&self) -> (usize, usize) {
        (self.procedures.len(), self.procedures.capacity())
    }
    pub fn declarations(&self) -> impl Iterator<Item = &Arc<ProcedureStaticDeclaration>> {
        self.declarations.values()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Unsupported(query)
        }
        fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
            (domain == ReadDomain::Tree).then_some(9)
        }
    }
    fn identity(name: &str) -> ProcedureIdentity {
        ProcedureIdentity {
            owner: dm_ir::SymbolId::of("/datum/a"),
            name: dm_ir::SymbolId::of(name),
            verb: false,
            occurrence: 0,
        }
    }
    #[test]
    fn shared_inventory_preserves_meanings_negative_reads_and_order_independent_domain_bytes() {
        let a = identity("a");
        let b = identity("b");
        let syntax = dm_syntax::parse("var/static/value = 1\n");
        let first = capture(a, &syntax.items).unwrap();
        let second = capture(b, &[]).unwrap();
        let inventory = Arc::new(StaticInventory::from_plans([(a, &first), (b, &second)]).unwrap());
        let one = StaticResolver::from_inventory(&Host, Arc::clone(&inventory)).unwrap();
        let two = StaticResolver::from_inventory(&Host, Arc::clone(&inventory)).unwrap();
        assert!(Arc::ptr_eq(&one.inventory, &two.inventory));
        let compatibility = StaticResolver::from_plans(&Host, [(b, &second), (a, &first)]).unwrap();
        assert_eq!(
            one.domain_version(ReadDomain::Tree),
            compatibility.domain_version(ReadDomain::Tree)
        );
        for (procedure, name) in [(a, "value"), (a, "missing"), (identity("outside"), "value")] {
            let query = ResolveQuery::ProcedureStatic {
                procedure,
                name: dm_ir::SymbolId::of(name),
            };
            assert_eq!(one.resolve(query), compatibility.resolve(query));
        }
        let weak = Arc::downgrade(&inventory);
        drop(inventory);
        drop(one);
        assert!(weak.upgrade().is_some());
        drop(two);
        assert!(weak.upgrade().is_none());
    }
    #[test]
    fn inventory_rejects_duplicate_context_in_exact_input_order() {
        let a = identity("a");
        let plan = capture(a, &[]).unwrap();
        assert_eq!(
            StaticInventory::from_plans([(a, &plan), (a, &plan)])
                .err()
                .unwrap(),
            "duplicate procedure static inventory"
        );
        assert_eq!(
            StaticInventory::from_plans([(identity("wrong"), &plan)])
                .err()
                .unwrap(),
            "procedure static inventory context mismatch"
        );
    }
}
