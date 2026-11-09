//! Immutable target grouping; source provenance always belongs to this request.
use super::*;

pub(crate) struct TargetOccurrenceIndex {
    targets: Arc<[Target]>,
    /// Built on first lookup. Native selected-declaration reads explicitly
    /// admit this SAME grouping; compatibility target reads keep their policy.
    groups: std::sync::OnceLock<Vec<OccurrenceId>>,
    // LAST: actual grouping buffers/control blocks release before lease credit.
    native_admission: std::sync::Mutex<Option<dm_syntax::SettingRootLease>>,
}
impl std::fmt::Debug for TargetOccurrenceIndex {
    fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result {
        f.debug_struct("TargetOccurrenceIndex").field("targets",&self.targets.len()).field("grouped",&self.groups.get().is_some()).finish_non_exhaustive()
    }
}
impl TargetOccurrenceIndex {
    fn capture(tree: &SemanticTree) -> Arc<Self> {
        Arc::new(Self {
            targets: Arc::clone(&tree.declaration_targets),
            groups: std::sync::OnceLock::new(),
            native_admission: std::sync::Mutex::new(None),
        })
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
    fn build_grouped(&self, mut poll: impl FnMut() -> std::io::Result<()>) -> std::io::Result<Vec<OccurrenceId>> {
        let len = self.targets.len();
        let mut grouped = Vec::new();
        grouped.try_reserve_exact(len).map_err(|e| std::io::Error::new(std::io::ErrorKind::OutOfMemory, e))?;
        if grouped.capacity() != len {
            return Err(std::io::Error::new(std::io::ErrorKind::OutOfMemory, "target grouping allocation differs from admitted capacity"));
        }
        for ordinal in 0..len {
            poll()?;
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
    fn groups(&self) -> &[OccurrenceId] {
        // Serialize legacy and admitted construction on the SAME original index.
        // No query/cache family lock or callback is entered while held.
        let _construction = self.native_admission.lock().unwrap_or_else(|e| e.into_inner());
        self.groups.get_or_init(|| self.build_grouped(|| Ok(())).expect("target occurrence grouping"))
    }
    /// Adopt/build the SAME existing immutable target grouping under native body
    /// work admission. No second index, copied source, or semantic projection.
    fn admitted_groups(&self,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<&[OccurrenceId]> {
        let pending=(||{
            a.checkpoint()?;
            let mut owner=self.native_admission.lock().map_err(|_|std::io::Error::other("target grouping admission poisoned"))?;
            if let Some(lease)=owner.as_ref(){
                if !a.matches_lease_domain(lease){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"target grouping belongs to foreign body budget"))}
            } else {
                let bytes = self.targets.len().checked_mul(std::mem::size_of::<OccurrenceId>())
                    .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::OutOfMemory, "target grouping admission overflow"))?;
                let lease = a.reserve(bytes)?;
                if self.groups.get().is_none() {
                    let grouped = self.build_grouped(|| a.checkpoint())?;
                    a.checkpoint()?;
                    // The same mutex serializes compatibility and native construction.
                    let _ = self.groups.set(grouped);
                }
                *owner=Some(lease);
            }
            a.checkpoint()?;
            Ok(self.groups.get().expect("original target grouping installed").as_slice())
        })();
        if let Some(actual)=a.take_operational_error(){return Err(actual)}
        pending
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
        {let owner=index.native_admission.lock().unwrap_or_else(|e|e.into_inner());if let Some(lease)=owner.as_ref(){lease.visit_counter_storage(|pointer,bytes|counter_storage=Some((pointer,bytes)));}}
        if let Some((pointer,bytes))=counter_storage{visit(pointer,1,bytes); }
        if let Some(ids) = index.groups.get().filter(|ids| !ids.is_empty()) {
            visit(ids.as_ptr() as usize, ids.len(), ids.capacity() * std::mem::size_of::<OccurrenceId>());
        }
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
        let owner=self.index.native_admission.lock().unwrap_or_else(|e|e.into_inner());if owner.is_none(){return Err("original target grouping has not been admitted on the native owner")}
        let groups = self.index.groups.get().ok_or("admitted original target grouping is absent")?;
        Ok(self.index.target_ids(groups, target).first().copied())
    }
    pub(crate) fn native_target_index_charge(&self)->usize{self.index.native_admission.lock().unwrap_or_else(|e|e.into_inner()).as_ref().map_or(0,dm_syntax::SettingRootLease::bytes)}
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
        Ok(self.index.target_ids(self.index.admitted_groups(a)?, target))
    }
    pub fn for_target(&self, target: Target) -> &[OccurrenceId] {
        self.index.target_ids(self.index.groups(), target)
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
        let denied=dm_syntax::SettingAdmission::new(&counter,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&poll);let error=table.for_target_admitted(Target::Type(TypeId(0)),&denied).err().unwrap();assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert!(table.index.groups.get().is_none());
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
        let failed=dm_syntax::SettingAdmission::new(&counter,1024*1024,&failure);let actual=table.for_target_admitted(Target::Type(TypeId(0)),&failed).err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());assert!(table.index.groups.get().is_none());assert!(table.index.native_admission.lock().unwrap().is_none());
        let poll=||Ok(());let fresh=dm_syntax::SettingAdmission::new(&counter,1024*1024,&poll);assert!(table.for_target_admitted(Target::Type(TypeId(0)),&fresh).is_ok());
    }

}
