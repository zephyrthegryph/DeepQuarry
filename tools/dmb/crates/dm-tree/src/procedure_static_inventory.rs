//! Immutable captured static declarations shared by all startup consumers.
use super::*;
/// Issued from exact plans; read-only users cannot replace declarations or keys.
pub struct StaticInventory {
    pub(super) procedures: HashSet<ProcedureIdentity>,
    certificates: std::collections::BTreeMap<ProcedureIdentity, Arc<StaticLayout>>,
    pub(super) declarations:
        std::collections::BTreeMap<ProcedureStaticIdentity, Arc<ProcedureStaticDeclaration>>,
}
impl StaticInventory {
    pub fn from_plans<'p>(plans:impl IntoIterator<Item=(ProcedureIdentity,&'p StaticPlan)>)->Result<Self,String>{
        Self::from_rows(plans.into_iter().map(|(procedure,plan)|(procedure,plan,move||Ok(plan.declarations.iter().cloned().map(Arc::new)))),|_,_|Ok(()))
    }
    /// Use the SAME canonical declaration objects already issued by the static
    /// producer. This constructor is a semantic inventory, not a current-source
    /// receipt; source consumers still require the private issued-plan binding.
    pub fn from_issued_plans<'p>(plans:impl IntoIterator<Item=(ProcedureIdentity,&'p StaticPlan,Option<&'p Arc<crate::frontend::IssuedStaticPlan>>)>)->Result<Self,String>{
        Self::from_rows(plans.into_iter().map(|(procedure,plan,issued)|(procedure,plan,move||{
            let owner=match issued{
                Some(issued)=>{if !std::ptr::eq(plan,issued.plan()){return Err("canonical static inventory differs from issued plan".into());}Some(issued.canonical_declarations()?)},
                None=>{if !plan.declarations.is_empty()||!plan.origins.is_empty(){return Err("canonical static inventory requires original producer".into());}None},
            };
            Ok(CanonicalRows{owner,index:0})
        })),Self::validate_canonical_rows)
    }
    pub fn from_canonical_declarations<'p>(plans:impl IntoIterator<Item=(ProcedureIdentity,&'p StaticPlan,Option<&'p Arc<[Arc<ProcedureStaticDeclaration>]>>)>)->Result<Self,String>{
        Self::from_rows(plans.into_iter().map(|(procedure,plan,owner)|(procedure,plan,move||{
            if owner.is_none()&&(!plan.declarations.is_empty()||!plan.origins.is_empty()){return Err("canonical static declaration owner unavailable".into());}
            Ok(CanonicalRows{owner:owner.map(Arc::clone),index:0})
        })),Self::validate_canonical_rows)
    }
    /// Read the original inventory map; no side question/value index is built.
    pub fn declaration(&self,identity:ProcedureStaticIdentity)->Option<&Arc<ProcedureStaticDeclaration>>{self.declarations.get(&identity)}
    /// Layouts have already been checked against the actual plans by the
    /// original artifact producer. Share their objects rather than cloning a
    /// second metadata roster; validate against the SAME final inventory map.
    pub fn from_canonical_layouts<'p>(plans:impl IntoIterator<Item=(ProcedureIdentity,&'p StaticPlan,&'p Arc<StaticLayout>)>)->Result<Self,String>{
        Self::from_rows(plans.into_iter().map(|(procedure,plan,layout)|(procedure,plan,move||Ok(CanonicalRows{owner:Some(Arc::clone(layout.declarations())),index:0}))),Self::validate_canonical_rows)
    }
    fn validate_canonical_rows(plan:&StaticPlan,declarations:&std::collections::BTreeMap<ProcedureStaticIdentity,Arc<ProcedureStaticDeclaration>>)->Result<(),String>{
        for declaration in &plan.declarations{
            if declarations.get(&declaration.identity).map(|row|row.as_ref())!=Some(declaration){return Err("canonical static inventory differs from original declarations".into());}
        }
        Ok(())
    }
    fn from_rows<'p,D,F,V>(plans:impl IntoIterator<Item=(ProcedureIdentity,&'p StaticPlan,F)>,validate:V)->Result<Self,String>
    where D:IntoIterator<Item=Arc<ProcedureStaticDeclaration>>,F:FnOnce()->Result<D,String>,V:Fn(&StaticPlan,&std::collections::BTreeMap<ProcedureStaticIdentity,Arc<ProcedureStaticDeclaration>>)->Result<(),String>{
        let mut procedures=HashSet::new();let mut declarations=std::collections::BTreeMap::new();
        for (procedure,plan,produce) in plans{
            if plan.procedure!=procedure{return Err("procedure static inventory context mismatch".into());}
            if !procedures.insert(procedure){return Err("duplicate procedure static inventory".into());}
            let mut count=0usize;
            for declaration in produce()?{
                if declaration.identity.procedure!=procedure{return Err("static declaration belongs to another procedure".into());}
                if declarations.insert(declaration.identity,declaration).is_some(){return Err("duplicate structural static declaration".into());}
                count=count.checked_add(1).ok_or("static inventory declaration count overflow")?;
            }
            if count!=plan.declarations.len(){return Err("canonical static inventory declaration count differs".into());}
            validate(plan,&declarations)?;
        }
        Ok(Self{procedures,declarations,certificates:Default::default()})
    }
    /// Revalidate any returned owner against this exact current captured roster.
    /// An absent/incorrect receipt only disables scoped certification.
    pub fn certify(
        &mut self,
        mut admit: impl FnMut(
            ProcedureIdentity,
            Arc<[Arc<ProcedureStaticDeclaration>]>,
        ) -> Option<Arc<StaticLayout>>,
    ) {
        self.certificates.clear();
        let mut rosters = std::collections::BTreeMap::<
            ProcedureIdentity,
            Vec<Arc<ProcedureStaticDeclaration>>,
        >::new();
        for &procedure in &self.procedures {
            rosters.insert(procedure, Vec::new());
        }
        for declaration in self.declarations.values() {
            rosters
                .get_mut(&declaration.identity.procedure)
                .expect("validated static procedure")
                .push(Arc::clone(declaration));
        }
        for (procedure, declarations) in rosters {
            let declarations: Arc<[_]> = declarations.into();
            if let Some(layout) = admit(procedure, Arc::clone(&declarations)) {
                if layout.matches(procedure, &declarations) {
                    self.certificates.insert(procedure, layout);
                }
            }
        }
    }
    pub fn certificates(&self) -> impl Iterator<Item = &Arc<StaticLayout>> {
        self.certificates.values()
    }
    pub fn certificate_count(&self) -> usize {
        self.certificates.len()
    }
    pub fn procedure_storage(&self) -> (usize, usize) {
        (self.procedures.len(), self.procedures.capacity())
    }
    pub fn declarations(&self) -> impl Iterator<Item = &Arc<ProcedureStaticDeclaration>> {
        self.declarations.values()
    }
}

/// An owned iterator over an existing canonical slice. Empty procedures create
/// no Arc allocation and no temporary declaration Vec.
struct CanonicalRows{owner:Option<Arc<[Arc<ProcedureStaticDeclaration>]>>,index:usize}
impl Iterator for CanonicalRows{
    type Item=Arc<ProcedureStaticDeclaration>;
    fn next(&mut self)->Option<Self::Item>{let value=self.owner.as_ref()?.get(self.index).map(Arc::clone)?;self.index+=1;Some(value)}
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
        fn answer_world(&self) -> Option<u128> {
            Some(9)
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
            one.answer_world(),
            compatibility.answer_world()
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
