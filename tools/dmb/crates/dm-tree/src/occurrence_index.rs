//! Immutable target grouping; source provenance always belongs to this request.
use super::*;

pub(crate) struct TargetOccurrenceIndex {
    targets: Arc<[Target]>,
    /// Built on first lookup. Native selected-declaration reads explicitly
    /// admit this SAME grouping; compatibility target reads keep their policy.
    groups: [std::sync::OnceLock<Vec<OccurrenceId>>; 2],
    // LAST: actual grouping buffers/control blocks release before lease credit.
    native_admission: std::sync::Mutex<[Option<dm_syntax::SettingRootLease>; 2]>,
}
impl std::fmt::Debug for TargetOccurrenceIndex {
    fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result {
        f.debug_struct("TargetOccurrenceIndex").field("targets",&self.targets.len()).field("grouped",&self.groups.iter().filter(|part|part.get().is_some()).count()).finish_non_exhaustive()
    }
}
impl TargetOccurrenceIndex {
    fn capture(tree: &SemanticTree) -> Arc<Self> {
        Arc::new(Self {
            targets: Arc::clone(&tree.declaration_targets),
            groups: [std::sync::OnceLock::new(), std::sync::OnceLock::new()],
            native_admission: std::sync::Mutex::new([None,None]),
        })
    }
    fn kind(target:Target)->usize{match target{Target::Type(_)=>0,Target::Member(_)=>1}}
    fn group_len(&self,kind:usize,mut poll:impl FnMut()->std::io::Result<()>)->std::io::Result<usize>{
        let mut len=0;for target in self.targets.iter(){poll()?;if Self::kind(*target)==kind{len+=1;}}Ok(len)
    }
    fn target_key(target: Target) -> (u8, usize) {
        match target {
            Target::Type(id) => (0, id.index()),
            Target::Member(id) => (1, id.index()),
        }
    }
    fn target_ids<'a>(&self, groups: &'a [OccurrenceId], target: Target) -> &'a [OccurrenceId] {
        let wanted = Self::target_key(target);
        let key = |id: &OccurrenceId| Self::target_key(self.targets[id.0 as usize]);
        let first = groups.partition_point(|id| key(id) < wanted);
        let count = groups[first..].partition_point(|id| key(id) == wanted);
        &groups[first..first + count]
    }
    fn build_grouped(&self,kind:usize,len:usize,mut poll: impl FnMut() -> std::io::Result<()>) -> std::io::Result<Vec<OccurrenceId>> {
        let mut grouped = Vec::new();
        grouped.try_reserve_exact(len).map_err(|e| std::io::Error::new(std::io::ErrorKind::OutOfMemory, e))?;
        if grouped.capacity() != len {
            return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory, "target grouping allocation differs from admitted capacity"));
        }
        for (ordinal,target) in self.targets.iter().enumerate() {
            poll()?;if Self::kind(*target)!=kind{continue;}
            grouped.push(OccurrenceId(u32::try_from(ordinal).map_err(|_| {
                std::io::Error::new(std::io::ErrorKind::OutOfMemory, "target occurrence ordinal overflow")
            })?));
        }

        // In-place heap sort needs no second buffer, and each bounded sift can
        // be preceded by a fallible checkpoint. Ordinal breaks equal-target
        // ties, preserving each target's original source order.
        let key = |id: OccurrenceId| (Self::target_key(self.targets[id.0 as usize]), id.0);
        fn sift(values: &mut [OccurrenceId], mut root: usize, key: &impl Fn(OccurrenceId) -> ((u8, usize), u32)) {
            while root < values.len() / 2 {
                let mut child = root * 2 + 1;
                if child + 1 < values.len() && key(values[child]) < key(values[child + 1]) {
                    child += 1;
                }
                if key(values[root]) >= key(values[child]) {
                    return;
                }
                values.swap(root, child);
                root = child;
            }
        }
        for root in (0..len / 2).rev() {
            poll()?;
            sift(&mut grouped, root, &key);
        }
        for end in (1..len).rev() {
            poll()?;
            grouped.swap(0, end);
            sift(&mut grouped[..end], 0, &key);
        }
        Ok(grouped)
    }
    fn groups(&self,target:Target) -> &[OccurrenceId] {
        // Serialize legacy and admitted construction on the SAME original index.
        // No query/cache family lock or callback is entered while held.
        let _construction = self.native_admission.lock().unwrap_or_else(|e| e.into_inner());
        let kind=Self::kind(target);
        self.groups[kind].get_or_init(||{let len=self.group_len(kind,||Ok(())).expect("target occurrence count");self.build_grouped(kind,len,|| Ok(())).expect("target occurrence grouping")})
    }
    /// Adopt/build the SAME existing immutable target grouping under native body
    /// work admission. No second index, copied source, or semantic projection.
    fn admitted_groups(&self,target:Target,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<&[OccurrenceId]> {
        self.admitted_kind(Self::kind(target),a)
    }
    fn admitted_kind(&self,kind:usize,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<&[OccurrenceId]>{
        let pending=(||{
            a.checkpoint()?;
            let mut owners=self.native_admission.lock().map_err(|_|std::io::Error::other("target grouping admission poisoned"))?;
            if owners.iter().flatten().any(|lease|!a.matches_lease_domain(lease)){
                return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"target grouping belongs to foreign body budget"));
            }
            // Legacy lookup retains its existing unbounded resource policy.
            // EVERY native boundary first adopts all THEN-existing buffers.
            // Pending leases precede detached storage so failure drops actual
            // storage before its funding, with no partial ownership publication.
            let mut new_owners:[Option<dm_syntax::SettingRootLease>;2]=[None,None];
            let mut detached=None;
            for part in 0..2{
                if owners[part].is_none(){if let Some(existing)=self.groups[part].get(){
                    let bytes=existing.capacity().checked_mul(std::mem::size_of::<OccurrenceId>()).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"existing target grouping admission overflow"))?;
                    new_owners[part]=Some(a.reserve(bytes)?);
                }}
            }
            if owners[kind].is_none()&&new_owners[kind].is_none(){
                let len=self.group_len(kind,||a.checkpoint())?;
                let bytes=len.checked_mul(std::mem::size_of::<OccurrenceId>()).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"target grouping admission overflow"))?;
                if std::env::var_os("DMB_ORIGINAL_TRACE_TARGET_GROUPING").is_some(){eprintln!("ORIGINAL_TARGET_GROUPING kind={} total={} selected={} other={} bytes={}",if kind==0{"type"}else{"member"},self.targets.len(),len,self.targets.len()-len,bytes);}
                new_owners[kind]=Some(a.reserve(bytes)?);
                detached=Some(self.build_grouped(kind,len,||a.checkpoint())?);
            }
            a.checkpoint()?;
            if let Some(grouped)=detached{let _=self.groups[kind].set(grouped);}
            for part in 0..2{if let Some(lease)=new_owners[part].take(){owners[part]=Some(lease);}}
            Ok(self.groups[kind].get().expect("original target grouping installed").as_slice())
        })();
        if let Some(actual)=a.take_operational_error(){return Err(actual)}pending
    }
    fn admits(&self, tree: &SemanticTree) -> bool {
        // The same immutable roster is exact; other rosters require value equality.
        // A semantic hash or tree identity is insufficient for admission.
        Arc::ptr_eq(&self.targets, &tree.declaration_targets)
            || self.targets.as_ref() == tree.declarations()
    }
    pub(crate) fn visit_storage(index: &Arc<Self>, visit: &mut dyn FnMut(usize, usize, usize)) {
        visit(Arc::as_ptr(index) as usize, 1, std::mem::size_of::<Self>());
        visit(
            index.targets.as_ptr() as usize,
            index.targets.len(),
            std::mem::size_of_val(index.targets.as_ref()),
        );
        let mut counter_storage=None;
        {let owners=index.native_admission.lock().unwrap_or_else(|e|e.into_inner());if let Some(lease)=owners.iter().flatten().next(){lease.visit_counter_storage(|pointer,bytes|counter_storage=Some((pointer,bytes)));}}
        if let Some((pointer,bytes))=counter_storage{visit(pointer,1,bytes); }
        for part in &index.groups{if let Some(ids)=part.get().filter(|ids|!ids.is_empty()){
            visit(ids.as_ptr()as usize,ids.len(),ids.capacity()*std::mem::size_of::<OccurrenceId>());
        }}
    }
}
impl OccurrenceTable {
    pub fn build(
        tree: &SemanticTree,
        origins: Vec<Provenance>,
    ) -> Result<Self, OccurrenceCountMismatch> {
        Self::build_with_index(tree, origins, None)
    }
    pub(crate) fn build_with_index(
        tree: &SemanticTree,
        origins: Vec<Provenance>,
        prior: Option<&Arc<TargetOccurrenceIndex>>,
    ) -> Result<Self, OccurrenceCountMismatch> {
        if origins.len() != tree.declarations().len() {
            return Err(OccurrenceCountMismatch {
                declarations: tree.declarations().len(),
                origins: origins.len(),
            });
        }
        let index = prior
            .filter(|index| index.admits(tree))
            .map_or_else(|| TargetOccurrenceIndex::capture(tree), Arc::clone);
        let occurrences = tree
            .declarations()
            .iter()
            .copied()
            .zip(origins)
            .map(|(target, provenance)| Occurrence { target, provenance })
            .collect::<Vec<_>>();
        Ok(Self {
            tree_identity: tree.identity(),
            occurrences: occurrences.into(),
            index,
        })
    }
    pub(crate) fn target_index(&self) -> Arc<TargetOccurrenceIndex> {
        Arc::clone(&self.index)
    }
    /// Actual shared allocations, including the compact sorted ordinal buffer.
    /// Same native grouping owner already held by this occurrence table.
    /// Resource overlap only; it grants no original source/declaration role.
    pub(crate) fn first_native_target(&self,target:Target)->Result<Option<OccurrenceId>,&'static str>{
        if self.index.targets.is_empty(){return Ok(None)}
        let owner=self.index.native_admission.lock().unwrap_or_else(|e|e.into_inner());if owner[TargetOccurrenceIndex::kind(target)].is_none(){return Err("original target grouping has not been admitted on the native owner")}
        if self.index.groups.iter().enumerate().any(|(kind,part)|part.get().is_some()&&owner[kind].is_none()){return Err("legacy target grouping growth needs native re-admission")}
        let groups = self.index.groups[TargetOccurrenceIndex::kind(target)].get().ok_or("admitted original target grouping is absent")?;
        Ok(self.index.target_ids(groups, target).first().copied())
    }
    pub(crate) fn last_native_target(&self,target:Target)->Result<Option<OccurrenceId>,&'static str>{
        if self.index.targets.is_empty(){return Ok(None)}
        let owner=self.index.native_admission.lock().unwrap_or_else(|e|e.into_inner());if owner[TargetOccurrenceIndex::kind(target)].is_none(){return Err("original target grouping has not been admitted on the native owner")}
        if self.index.groups.iter().enumerate().any(|(kind,part)|part.get().is_some()&&owner[kind].is_none()){return Err("legacy target grouping growth needs native re-admission")}
        let groups = self.index.groups[TargetOccurrenceIndex::kind(target)].get().ok_or("admitted original target grouping is absent")?;
        Ok(self.index.target_ids(groups, target).last().copied())
    }
    /// Leased native parts only. Compatibility may allocate another part under
    /// its existing policy; native access refuses until an admitted boundary
    /// adopts that actual buffer. This is not a universal heap-size census.
    pub(crate) fn native_target_index_charge(&self)->usize{self.index.native_admission.lock().unwrap_or_else(|e|e.into_inner()).iter().flatten().map(dm_syntax::SettingRootLease::bytes).sum()}
    pub fn visit_target_index_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        TargetOccurrenceIndex::visit_storage(&self.index, &mut visit);
    }
    pub fn tree_identity(&self) -> u128 {
        self.tree_identity
    }
    pub fn source_order(&self) -> &[Occurrence] {
        &self.occurrences
    }
    pub fn get(&self, id: OccurrenceId) -> Option<&Occurrence> {
        self.occurrences.get(id.0 as usize)
    }
    pub(crate) fn for_target_admitted(&self,target:Target,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<&[OccurrenceId]>{
        Ok(self.index.target_ids(self.index.admitted_groups(target,a)?, target))
    }
    pub(crate)fn prepare_member_groups_admitted(&self,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{self.index.admitted_kind(1,a).map(|_|())}
    pub fn for_target(&self, target: Target) -> &[OccurrenceId] {
        self.index.target_ids(self.index.groups(target), target)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn tree() -> SemanticTree {
        let mut symbols = dm_ir::SymbolTable::default();
        symbols.intern("/").unwrap();
        let a = symbols.intern("/a").unwrap();
        let b = symbols.intern("/b").unwrap();
        crate::build(
            symbols,
            &[
                Skeleton::Type {
                    path: a,
                    explicit_parent: None,
                },
                Skeleton::Type {
                    path: a,
                    explicit_parent: None,
                },
                Skeleton::Type {
                    path: b,
                    explicit_parent: None,
                },
            ],
        )
        .unwrap()
    }
    fn origins(tree: &SemanticTree, shift: u32) -> Vec<Provenance> {
        (0..tree.declarations().len())
            .map(|i| Provenance {
                span: dm_ir::Span {
                    file: dm_ir::FileId(shift),
                    start: shift + i as u32,
                    end: shift + i as u32 + 1,
                },
                include_occurrence: shift,
                region: shift as u128,
                expansion_stack: Arc::from([]),
            })
            .collect()
    }
    #[test]
    fn unchanged_targets_share_index_but_issue_fresh_provenance() {
        let tree = tree();
        let first = OccurrenceTable::build(&tree, origins(&tree, 0)).unwrap();
        let current =
            OccurrenceTable::build_with_index(&tree, origins(&tree, 80), Some(&first.index))
                .unwrap();
        assert!(Arc::ptr_eq(&first.index, &current.index));
        assert!(!Arc::ptr_eq(&first.occurrences, &current.occurrences));
        let target = tree.declarations()[0];
        assert_eq!(
            current.for_target(target),
            &[OccurrenceId(0), OccurrenceId(1)]
        );
        assert_eq!(first.get(OccurrenceId(0)).unwrap().provenance.span.start, 0);
        assert_eq!(
            current.get(OccurrenceId(0)).unwrap().provenance.span.start,
            80
        );
        assert_eq!(
            current
                .get(OccurrenceId(0))
                .unwrap()
                .provenance
                .include_occurrence,
            80
        );
        assert!(OccurrenceTable::build_with_index(&tree, Vec::new(), Some(&first.index)).is_err());
    }
    #[test]
    fn changed_target_roster_rebuilds_exact_grouping_even_with_same_tree_identity() {
        let tree = tree();
        let first = OccurrenceTable::build(&tree, origins(&tree, 0)).unwrap();
        let mut changed = tree.clone();
        let mut targets = changed.declarations().to_vec();
        targets.reverse();
        changed.declaration_targets = targets.into();
        let current =
            OccurrenceTable::build_with_index(&changed, origins(&changed, 1), Some(&first.index))
                .unwrap();
        assert!(!Arc::ptr_eq(&first.index, &current.index));
        let expected = OccurrenceTable::build(&changed, origins(&changed, 1)).unwrap();
        for target in changed.declarations() {
            assert_eq!(current.for_target(*target), expected.for_target(*target));
        }
    }
    #[test]
    fn native_target_grouping_quota_retry_domain_and_physical_owner_release(){
        use std::sync::atomic::{Ordering};
        let tree=tree();let table=OccurrenceTable::build(&tree,origins(&tree,0)).unwrap();let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());
        let denied=dm_syntax::SettingAdmission::new(&counter,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&poll);let error=table.for_target_admitted(Target::Type(TypeId(0)),&denied).err().unwrap();assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert!(table.index.groups.iter().all(|part|part.get().is_none()));
        let bytes=tree.declarations().len()*std::mem::size_of::<OccurrenceId>();
        let admitted=dm_syntax::SettingAdmission::new(&counter,dm_syntax::SettingChargeCounter::root_allocation_bytes()+bytes,&poll);
        for target in tree.declarations(){assert_eq!(table.for_target_admitted(*target,&admitted).unwrap(),table.for_target(*target));}
        let retained=counter.load(Ordering::Acquire);assert_eq!(retained,dm_syntax::SettingChargeCounter::root_allocation_bytes()+bytes);
        assert!(table.for_target_admitted(Target::Type(TypeId(0)),&admitted).is_ok());assert_eq!(counter.load(Ordering::Acquire),retained);
        let foreign_counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let foreign=dm_syntax::SettingAdmission::new(&foreign_counter,1024*1024,&poll);assert_eq!(table.for_target_admitted(Target::Type(TypeId(0)),&foreign).err().unwrap().kind(),std::io::ErrorKind::InvalidInput);assert_eq!(foreign_counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
        drop(table);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes(),"index buffers physically drop before native lease credit");
    }
    #[test]
    fn compact_target_grouping_adopts_same_storage_and_keeps_interleaved_order() {
        use std::sync::atomic::Ordering;

        let mut tree = tree();
        let first = tree.declarations()[0];
        let last = tree.declarations()[2];
        let member = Target::Member(MemberId(1));
        tree.declaration_targets = Arc::from([last, first, member, last, first, member, first]);
        let table = OccurrenceTable::build(&tree, origins(&tree, 0)).unwrap();
        assert!(table.first_native_target(first).is_err());
        let old = table.for_target(first);
        assert_eq!(old, &[OccurrenceId(1), OccurrenceId(4), OccurrenceId(6)]);
        let root = dm_syntax::SettingChargeCounter::root_allocation_bytes();
        let counter = dm_syntax::SettingChargeCounter::try_new(root).unwrap();
        let bytes = tree.declarations().len() * std::mem::size_of::<OccurrenceId>();
        let admission = dm_syntax::SettingAdmission::new(&counter, root + bytes, &|| Ok(()));
        assert!(std::ptr::eq(old, table.for_target_admitted(first, &admission).unwrap()));
        assert_eq!(table.for_target_admitted(last, &admission).unwrap(), &[OccurrenceId(0), OccurrenceId(3)]);
        assert_eq!(table.for_target_admitted(member, &admission).unwrap(), &[OccurrenceId(2), OccurrenceId(5)]);
        assert!(table.for_target_admitted(Target::Member(MemberId(2)), &admission).unwrap().is_empty());
        assert_eq!(table.first_native_target(first).unwrap(), Some(OccurrenceId(1)));
        assert_eq!(counter.load(Ordering::Acquire), root + bytes);
    }

    #[test]
    fn native_target_grouping_midwork_actual_io_leaves_no_index_or_lease_and_retries(){
        use std::sync::atomic::{Ordering};
        let tree=tree();let table=OccurrenceTable::build(&tree,origins(&tree,0)).unwrap();let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let calls=std::cell::Cell::new(0);
        let failure=||{calls.set(calls.get()+1);if calls.get()==4{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};
        let failed=dm_syntax::SettingAdmission::new(&counter,1024*1024,&failure);let actual=table.for_target_admitted(Target::Type(TypeId(0)),&failed).err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert!(table.index.groups.iter().all(|part|part.get().is_none()));assert!(table.index.native_admission.lock().unwrap().iter().all(Option::is_none));
        let poll=||Ok(());let fresh=dm_syntax::SettingAdmission::new(&counter,1024*1024,&poll);assert!(table.for_target_admitted(Target::Type(TypeId(0)),&fresh).is_ok());
    }

    #[test]
    fn member_grouping_never_allocates_unrequested_type_ordinals_and_later_type_adoption_is_exact(){
        use std::sync::atomic::Ordering;
        let mut tree=tree();let ty=tree.declarations()[0];let member=Target::Member(MemberId(1));
        let mut targets=vec![ty;4096];targets[7]=member;targets[4001]=member;tree.declaration_targets=targets.into();
        let table=OccurrenceTable::build(&tree,origins(&tree,0)).unwrap();let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();let poll=||Ok(());
        let member_only=dm_syntax::SettingAdmission::new(&counter,root+2*std::mem::size_of::<OccurrenceId>(),&poll);
        table.prepare_member_groups_admitted(&member_only).unwrap();assert_eq!(table.for_target_admitted(member,&member_only).unwrap(),&[OccurrenceId(7),OccurrenceId(4001)]);
        assert!(table.index.groups[0].get().is_none());assert_eq!(table.index.groups[1].get().unwrap().capacity(),2);assert_eq!(counter.load(Ordering::Acquire),root+8);
        let denied=dm_syntax::SettingAdmission::new(&counter,root+8,&poll);assert!(table.for_target_admitted(ty,&denied).is_err());assert!(table.index.groups[0].get().is_none());assert_eq!(counter.load(Ordering::Acquire),root+8,"failed type reservation cannot publish or uncharge live members");
        let foreign_counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();let foreign=dm_syntax::SettingAdmission::new(&foreign_counter,root+32768,&poll);assert_eq!(table.for_target_admitted(ty,&foreign).unwrap_err().kind(),std::io::ErrorKind::InvalidInput,"an empty secondpart cannot borrow a foreign budget");
        let all=dm_syntax::SettingAdmission::new(&counter,root+4096*4,&poll);let ids=table.for_target_admitted(ty,&all).unwrap();assert_eq!(ids.len(),4094);assert_eq!(ids[0],OccurrenceId(0));assert_eq!(ids.last(),Some(&OccurrenceId(4095)));assert_eq!(counter.load(Ordering::Acquire),root+4096*4);assert_eq!(table.native_target_index_charge(),4096*4);
        assert_eq!(table.for_target_admitted(member,&all).unwrap(),&[OccurrenceId(7),OccurrenceId(4001)]);drop(table);assert_eq!(counter.load(Ordering::Acquire),root);
    }
    #[test]
    fn member_partition_initialization_checkpoint_keeps_actual_first_io_and_no_detached_storage(){
        use std::sync::atomic::Ordering;
        let mut tree=tree();tree.declaration_targets=Arc::from([Target::Type(TypeId(1)),Target::Member(MemberId(2)),Target::Type(TypeId(1)),Target::Member(MemberId(1))]);
        let table=OccurrenceTable::build(&tree,origins(&tree,0)).unwrap();let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();let calls=std::cell::Cell::new(0);let fail=||{calls.set(calls.get()+1);if calls.get()==7{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};
        let admission=dm_syntax::SettingAdmission::new(&counter,root+16,&fail);assert_eq!(table.prepare_member_groups_admitted(&admission).unwrap_err().raw_os_error(),Some(1450));assert!(table.index.groups.iter().all(|part|part.get().is_none()));assert_eq!(counter.load(Ordering::Acquire),root);
        let poll=||Ok(());let fresh=dm_syntax::SettingAdmission::new(&counter,root+8,&poll);table.prepare_member_groups_admitted(&fresh).unwrap();assert_eq!(table.for_target_admitted(Target::Member(MemberId(1)),&fresh).unwrap(),&[OccurrenceId(3)]);assert_eq!(table.for_target_admitted(Target::Member(MemberId(2)),&fresh).unwrap(),&[OccurrenceId(1)]);
    }

    #[test]
    fn native_member_adoption_also_funds_existing_legacy_type_storage_without_copying_it(){
        use std::sync::atomic::Ordering;
        let mut tree=tree();let ty=tree.declarations()[0];let member=Target::Member(MemberId(1));tree.declaration_targets=Arc::from([ty,member,ty,ty]);let table=OccurrenceTable::build(&tree,origins(&tree,0)).unwrap();let legacy=table.for_target(ty);let pointer=legacy.as_ptr();assert_eq!(legacy,&[OccurrenceId(0),OccurrenceId(2),OccurrenceId(3)]);
        let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();let poll=||Ok(());let low=dm_syntax::SettingAdmission::new(&counter,root+4,&poll);assert!(table.prepare_member_groups_admitted(&low).is_err());assert!(table.index.groups[1].get().is_none());assert_eq!(counter.load(Ordering::Acquire),root);
        let enough=dm_syntax::SettingAdmission::new(&counter,root+16,&poll);table.prepare_member_groups_admitted(&enough).unwrap();assert_eq!(table.for_target_admitted(ty,&enough).unwrap().as_ptr(),pointer);assert_eq!(table.for_target_admitted(member,&enough).unwrap(),&[OccurrenceId(1)]);assert_eq!(counter.load(Ordering::Acquire),root+16);drop(table);assert_eq!(counter.load(Ordering::Acquire),root);
    }

    #[test]
    fn legacy_type_growth_after_native_members_requires_exact_atomic_native_readoption(){
        use std::sync::atomic::Ordering;
        let mut tree=tree();let ty=tree.declarations()[0];let member=Target::Member(MemberId(1));tree.declaration_targets=Arc::from([ty,member,ty,ty]);let table=OccurrenceTable::build(&tree,origins(&tree,0)).unwrap();let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();let poll=||Ok(());
        let first=dm_syntax::SettingAdmission::new(&counter,root+4,&poll);table.prepare_member_groups_admitted(&first).unwrap();let member_pointer=table.for_target_admitted(member,&first).unwrap().as_ptr();assert_eq!(table.native_target_index_charge(),4);
        let type_pointer=table.for_target(ty).as_ptr();assert_eq!(counter.load(Ordering::Acquire),root+4,"legacy allocation retains existing compatibility resource policy");assert_eq!(table.native_target_index_charge(),4,"leased bytes are not a universal heap census");assert!(table.first_native_target(member).is_err());
        let tight=dm_syntax::SettingAdmission::new(&counter,root+4,&poll);assert!(table.for_target_admitted(member,&tight).is_err());assert_eq!(counter.load(Ordering::Acquire),root+4);assert_eq!(table.native_target_index_charge(),4);assert!(table.index.native_admission.lock().unwrap()[0].is_none());
        let enough=dm_syntax::SettingAdmission::new(&counter,root+16,&poll);assert_eq!(table.for_target_admitted(member,&enough).unwrap().as_ptr(),member_pointer);assert_eq!(table.for_target_admitted(ty,&enough).unwrap().as_ptr(),type_pointer);assert_eq!(counter.load(Ordering::Acquire),root+16);assert_eq!(table.native_target_index_charge(),16);assert_eq!(table.first_native_target(member).unwrap(),Some(OccurrenceId(1)));drop(table);assert_eq!(counter.load(Ordering::Acquire),root);
    }

}
