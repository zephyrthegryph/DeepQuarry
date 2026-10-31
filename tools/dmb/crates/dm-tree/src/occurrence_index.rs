//! Immutable target grouping; source provenance always belongs to this request.
use super::*;

pub(crate) struct TargetOccurrenceIndex {
    targets: Arc<[Target]>,
    /// Built on first lookup. Native selected-declaration reads explicitly
    /// admit this SAME grouping; compatibility target reads keep their policy.
    groups: std::sync::OnceLock<HashMap<Target, Arc<[OccurrenceId]>>>,
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
    fn groups(&self) -> &HashMap<Target, Arc<[OccurrenceId]>> {
        // Serialize legacy and admitted construction on the SAME original index.
        // No query/cache family lock or callback is entered while held.
        let _construction=self.native_admission.lock().unwrap_or_else(|e|e.into_inner());
        self.groups.get_or_init(|| {
            let mut groups: HashMap<Target, Vec<OccurrenceId>> = HashMap::new();
            for (ordinal, target) in self.targets.iter().copied().enumerate() {
                groups
                    .entry(target)
                    .or_default()
                    .push(OccurrenceId(ordinal as u32));
            }
            groups
                .into_iter()
                .map(|(target, ids)| (target, ids.into()))
                .collect()
        })
    }
    /// Adopt/build the SAME existing immutable target grouping under native body
    /// work admission. No second index, copied source, or semantic projection.
    fn admitted_groups(&self,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<&HashMap<Target,Arc<[OccurrenceId]>>> {
        let pending=(||{
            a.checkpoint()?;
            let mut owner=self.native_admission.lock().map_err(|_|std::io::Error::other("target grouping admission poisoned"))?;
            if let Some(lease)=owner.as_ref(){
                if !a.matches_lease_domain(lease){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"target grouping belongs to foreign body budget"))}
            } else {
                // Per source row: simultaneous builder/final HashMap buckets,
                // geometric u32 Vec buffers, and Arc slice/control blocks.
                // The SAME mutex serializes legacy/native construction, so no
                // duplicate builder is outside this envelope. 256 is a
                // conservative coordination envelope, NOT allocator-layout
                // qualification or a whole-process/RSS bound.
                let bytes=self.targets.len().checked_mul(256).and_then(|n|n.checked_add(8192)).ok_or_else(||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"target grouping admission overflow"))?;
                let lease=a.reserve(bytes)?;
                if self.groups.get().is_none(){
                    let mut grouped:HashMap<Target,Vec<OccurrenceId>>=HashMap::new();
                    grouped.try_reserve(self.targets.len()).map_err(|e|std::io::Error::new(std::io::ErrorKind::OutOfMemory,e))?;
                    for (ordinal,target) in self.targets.iter().copied().enumerate(){
                        a.checkpoint()?;
                        let ids=grouped.entry(target).or_default();
                        if ids.len()==ids.capacity(){ids.try_reserve(1).map_err(|e|std::io::Error::new(std::io::ErrorKind::OutOfMemory,e))?;}
                        ids.push(OccurrenceId(u32::try_from(ordinal).map_err(|_|std::io::Error::new(std::io::ErrorKind::OutOfMemory,"target occurrence ordinal overflow"))?));
                    }
                    let mut current=HashMap::new();
                    current.try_reserve(grouped.len()).map_err(|e|std::io::Error::new(std::io::ErrorKind::OutOfMemory,e))?;
                    for(target,ids)in grouped{a.checkpoint()?;current.insert(target,Arc::from(ids));}
                    a.checkpoint()?;
                    // Publish the SAME existing grouping; local conversion
                    // scratch has physically dropped before lease retention.
                    let _=self.groups.set(current);
                }
                *owner=Some(lease);
            }
            a.checkpoint()?;
            Ok(self.groups.get().expect("original target grouping installed"))
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
        for ids in index.groups.get().into_iter().flat_map(|groups| groups.values()) {
            visit(
                ids.as_ptr() as usize,
                ids.len(),
                std::mem::size_of_val(ids.as_ref()),
            );
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
    /// Actual shared allocations only; private HashMap bucket backing excluded.
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
        Ok(self.index.admitted_groups(a)?.get(&target).map(AsRef::as_ref).unwrap_or(&[]))
    }
    pub fn for_target(&self, target: Target) -> &[OccurrenceId] {
        self.index
            .groups()
            .get(&target)
            .map(AsRef::as_ref)
            .unwrap_or(&[])
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
        use std::sync::atomic::{AtomicUsize,Ordering};
        let tree=tree();let table=OccurrenceTable::build(&tree,origins(&tree,0)).unwrap();let counter=Arc::new(AtomicUsize::new(0));let poll=||Ok(());
        let denied=dm_syntax::SettingAdmission::new(&counter,0,&poll);let error=table.for_target_admitted(Target::Type(TypeId(0)),&denied).err().unwrap();assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),0);assert!(table.index.groups.get().is_none());
        let admitted=dm_syntax::SettingAdmission::new(&counter,1024*1024,&poll);
        for target in tree.declarations(){assert_eq!(table.for_target_admitted(*target,&admitted).unwrap(),table.for_target(*target));}
        let retained=counter.load(Ordering::Acquire);assert_eq!(retained,tree.declarations().len()*256+8192);
        assert!(table.for_target_admitted(Target::Type(TypeId(0)),&admitted).is_ok());assert_eq!(counter.load(Ordering::Acquire),retained);
        let foreign_counter=Arc::new(AtomicUsize::new(0));let foreign=dm_syntax::SettingAdmission::new(&foreign_counter,1024*1024,&poll);assert_eq!(table.for_target_admitted(Target::Type(TypeId(0)),&foreign).err().unwrap().kind(),std::io::ErrorKind::InvalidInput);assert_eq!(foreign_counter.load(Ordering::Acquire),0);
        drop(table);assert_eq!(counter.load(Ordering::Acquire),0,"index buffers physically drop before native lease credit");
    }
    #[test]
    fn native_target_grouping_midwork_actual_io_leaves_no_index_or_lease_and_retries(){
        use std::sync::atomic::{AtomicUsize,Ordering};
        let tree=tree();let table=OccurrenceTable::build(&tree,origins(&tree,0)).unwrap();let counter=Arc::new(AtomicUsize::new(0));let calls=std::cell::Cell::new(0);
        let failure=||{calls.set(calls.get()+1);if calls.get()==4{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};
        let failed=dm_syntax::SettingAdmission::new(&counter,1024*1024,&failure);let actual=table.for_target_admitted(Target::Type(TypeId(0)),&failed).err().unwrap();assert_eq!(actual.raw_os_error(),Some(1450));assert_eq!(counter.load(Ordering::Acquire),0);assert!(table.index.groups.get().is_none());assert!(table.index.native_admission.lock().unwrap().is_none());
        let poll=||Ok(());let fresh=dm_syntax::SettingAdmission::new(&counter,1024*1024,&poll);assert!(table.for_target_admitted(Target::Type(TypeId(0)),&fresh).is_ok());
    }

}
