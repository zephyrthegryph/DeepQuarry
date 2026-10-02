//! Semantic input deltas feed the graph reverse index before any procedure
//! payload restoration. Allocation IDs and default wire values are excluded.
use super::*;
use dm_codegen_byond::BindingFact as F;
pub(crate) struct DeclarationInputs {
    revision:String,
    shared:Arc<SharedLowerBindings>,
    overlays:BTreeMap<crate::ProcKey,Arc<InvocationOverlay>>,
    initializer_names:BTreeSet<String>,
}
fn changed_set<T:Ord+Clone>(old:&BTreeSet<T>,new:&BTreeSet<T>)->BTreeSet<T> {old.symmetric_difference(new).cloned().collect()}
fn changed_map<T:PartialEq>(old:&HashMap<String,T>,new:&HashMap<String,T>)->BTreeSet<String> {
    old.keys().chain(new.keys()).filter(|key|old.get(*key)!=new.get(*key)).cloned().collect()
}
fn changed_members<T:PartialEq>(old:&HashMap<String,HashMap<String,T>>,new:&HashMap<String,HashMap<String,T>>)->BTreeSet<String> {
    let owners:BTreeSet<_>=old.keys().chain(new.keys()).collect();let mut names=BTreeSet::new();
    for owner in owners {
        match (old.get(owner),new.get(owner)) {
            (Some(old),Some(new))=>names.extend(changed_map(old,new)),
            (Some(members),None)|(None,Some(members))=>names.extend(members.keys().cloned()),
            _=>{}
        }
    }
    names
}
fn changed_inventories(old:&HashMap<String,BTreeSet<String>>,new:&HashMap<String,BTreeSet<String>>)->BTreeSet<String> {
    let owners:BTreeSet<_>=old.keys().chain(new.keys()).collect();let mut names=BTreeSet::new();
    for owner in owners {
        match (old.get(owner),new.get(owner)) {
            (Some(old),Some(new))=>names.extend(changed_set(old,new)),
            (Some(names_here),None)|(None,Some(names_here))=>names.extend(names_here.iter().cloned()),
            _=>{}
        }
    }
    names
}
impl DeclarationInputs {
    pub(crate) fn snapshot(revision:&str,shared:Arc<SharedLowerBindings>,keys:&[crate::ProcKey],plans:&[InvocationPlan],initializers:&HashMap<String,u32>)->Self {
        Self {revision:revision.to_owned(),shared,overlays:keys.iter().cloned().zip(plans.iter().map(|plan|Arc::clone(&plan.bindings))).collect(),initializer_names:initializers.keys().cloned().collect()}
    }
    pub(crate) fn changes<'a>(&self,revision:&str,current:&Arc<SharedLowerBindings>,keys:&[crate::ProcKey],plans:&[InvocationPlan],initializers:&HashMap<String,u32>,observed:impl Iterator<Item=&'a F>)->BTreeSet<F> {
        if self.revision==revision {return BTreeSet::new();}
        let old=&self.shared;
        let mut fields=changed_set(&old.fields,&current.fields);
        fields.extend(changed_inventories(&old.known_member_fields,&current.known_member_fields));
        let mut field_types=changed_map(&old.field_types,&current.field_types);
        let member_types=changed_members(&old.member_types,&current.member_types);field_types.extend(member_types.iter().cloned());
        let member_globals=changed_members(&old.member_globals,&current.member_globals);
        let member_procs=changed_members(&old.member_procs,&current.member_procs);
        let declared_procs=changed_inventories(&old.known_member_procs,&current.known_member_procs);
        let return_types=changed_members(&old.member_proc_return_types,&current.member_proc_return_types);
        let mut globals=changed_set(&old.globals,&current.globals);
        let names:BTreeSet<_>=initializers.keys().cloned().collect();globals.extend(changed_set(&self.initializer_names,&names));
        let mut global_types=changed_map(&old.global_types,&current.global_types);
        let mut global_procs=changed_set(&old.global_procs,&current.global_procs);
        let edges=changed_map(&old.parent_types,&current.parent_types);
        let aliases=changed_map(&old.modified_instances,&current.modified_instances);
        let mut ancestry_field_change=false;
        for (key,plan) in keys.iter().zip(plans) {
            let Some(previous)=self.overlays.get(key) else {continue;};
            let overlay=&plan.bindings;
            if previous.as_ref()==overlay.as_ref() {continue;}
            fields.extend(previous.fields.iter().chain(overlay.fields.iter()).cloned());
            fields.extend(previous.hidden_owner_fields.iter().chain(overlay.hidden_owner_fields.iter()).cloned());
            field_types.extend(previous.field_types.iter().chain(overlay.field_types.iter()).map(|(name,_)|name.clone()));
            globals.extend(previous.globals.iter().chain(overlay.globals.iter()).cloned());
            global_types.extend(previous.global_types.iter().chain(overlay.global_types.iter()).map(|(name,_)|name.clone()));
            global_procs.extend(previous.global_procs.iter().chain(overlay.global_procs.iter()).cloned());
            ancestry_field_change|=previous.current_type_path!=overlay.current_type_path;
        }
        let affected_owner=|owner:&str| {
            if aliases.contains(owner) {return true;}
            for shared in [old.as_ref(),current.as_ref()] {
                let mut owner=shared.modified_instances.get(owner).map(String::as_str).unwrap_or(owner);
                for _ in 0..64 {
                    if edges.contains(owner) {return true;}
                    let Some(parent)=shared.parent_types.get(owner) else {break};owner=parent;
                }
            }
            false
        };
        let old_frame=LowerBindings {shared:Some(Arc::clone(old)),prepared_member_globals:PreparedMemberGlobals::new(Arc::clone(old)),..Default::default()};
        let new_frame=LowerBindings {shared:Some(Arc::clone(current)),prepared_member_globals:PreparedMemberGlobals::new(Arc::clone(current)),..Default::default()};
        observed.filter(|fact|match fact {
            F::Field(name)=>fields.contains(name)||ancestry_field_change||!edges.is_empty(),
            F::FieldType(name)=>field_types.contains(name)||ancestry_field_change||!edges.is_empty(),
            F::Global(name)=>globals.contains(name),F::GlobalType(name)=>global_types.contains(name),F::GlobalProc(name)=>global_procs.contains(name),
            F::MemberType(owner,name)=>member_types.contains(name)||affected_owner(owner),
            F::MemberGlobal(owner,name)=>member_globals.contains(name)||affected_owner(owner),
            F::UniqueMemberGlobal(name)=>member_globals.contains(name)||fields.contains(name)||!edges.is_empty(),
            F::MemberProc(owner,name)=>member_procs.contains(name)||affected_owner(owner),
            F::DeclaredMemberProc(owner,name)=>declared_procs.contains(name)||affected_owner(owner),
            F::MemberProcReturnType(owner,name)|F::ParentProcReturnType(owner,name)=>return_types.contains(name)||affected_owner(owner),
            F::GlobalProcReturnType(name)=>old.global_proc_return_types.get(name)!=current.global_proc_return_types.get(name),
            F::NumericConstant(name)=>old.numeric_constants.get(name)!=current.numeric_constants.get(name),
            F::StringConstant(name)=>old.string_constants.get(name)!=current.string_constants.get(name),
            F::ModifiedInstance(name)=>aliases.contains(name),F::SharedPresence=>false,
        }).filter(|fact|!fact.is_shared()||old_frame.binding_fact(fact)!=new_frame.binding_fact(fact)).cloned().collect()
    }
    pub(crate) fn has_revision(&self,revision:&str)->bool {self.revision==revision}
    pub(crate) fn resident_bytes(&self)->usize {
        // Shared payloads remain one allocation even when the physical snapshot
        // has been evicted; only this compact pointer/key index is duplicated.
        self.revision.capacity()+self.overlays.iter().map(|(key,_)|key.path.capacity()+96).sum::<usize>()
            +self.initializer_names.iter().map(|name|name.capacity()+48).sum::<usize>()
    }
}
