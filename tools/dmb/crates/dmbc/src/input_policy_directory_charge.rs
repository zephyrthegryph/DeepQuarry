//! Incremental RESOURCE accounting for immutable typed directory facts.
//! No source/model/findings cache and no serialized/equality policy input.
use super::*;
use std::sync::{Mutex, MutexGuard, Weak};
const INDEX_COORD: usize = 128 + std::mem::size_of::<(usize, Weak<Vec<PolicyDirectoryEntry>>)>();
#[derive(Debug)]
pub(crate) struct DirectoryChargeMemo(Mutex<State>, std::sync::OnceLock<Arc<()>>);
#[derive(Debug)]
pub(super) struct State {
    initialized: bool,
    denied: bool,
    total: usize,
    owners: BTreeMap<usize, Weak<Vec<PolicyDirectoryEntry>>>,
    #[cfg(test)]
    name_visits: usize,
    #[cfg(test)]
    owner_lookups: usize,
}
impl Default for DirectoryChargeMemo {
    fn default() -> Self {
        Self(Mutex::new(State {
            initialized: false,
            denied: false,
            total: 0,
            owners: BTreeMap::new(),
            #[cfg(test)]
            name_visits: 0,
            #[cfg(test)]
            owner_lookups: 0,
        }), Default::default())
    }
}
// Snapshot clones have their OWN path capacities. Rebuild once lazily, while
// preserving a failed resource admission; never clone a pointer cache blindly.
impl Clone for DirectoryChargeMemo {
    fn clone(&self) -> Self {
        let result = Self::default();
        if self.0.lock().unwrap_or_else(|e| e.into_inner()).denied {
            result.0.lock().unwrap_or_else(|e| e.into_inner()).denied = true;
        }
        result
    }
}
impl PartialEq for DirectoryChargeMemo {
    fn eq(&self, _: &Self) -> bool {
        true
    }
}
impl Eq for DirectoryChargeMemo {}
impl DirectoryChargeMemo {
    pub(super) fn metadata_owner(
        &self, budget: Option<&dq_analyze::captured_generator_budget::Budget>,
    ) -> io::Result<Arc<()>> {
        if let Some(owner) = self.1.get() {
            return Ok(Arc::clone(owner));
        }
        let budget = budget.ok_or_else(|| invalid("actual recorder metadata owner absent"))?;
        // Called under the actual snapshot lock. A clone or deserialization
        // starts without this resource identity; moving the maps preserves it.
        budget.charge(2 * std::mem::size_of::<usize>())
            .map_err(|message| io::Error::new(io::ErrorKind::OutOfMemory, message))?;
        Ok(Arc::clone(self.1.get_or_init(|| Arc::new(()))))
    }

    pub(super) fn lock<'a>(
        &'a self,
        rows: &BTreeMap<PathBuf, PolicyDirectoryObservation>,
    ) -> io::Result<MutexGuard<'a, State>> {
        let mut state = self
            .0
            .lock()
            .map_err(|_| invalid("typed directory accounting mutex poisoned"))?;
        if state.denied {
            return Err(invalid(
                "typed directory metadata admission previously failed",
            ));
        }
        if !state.initialized {
            state.total = std::mem::size_of_val(rows) + std::mem::size_of::<Self>();
            // Every entry goes through the same capacity check and Weak owner
            // dedup as a new insertion. Deserialized snapshots get no credit.
            for (path, row) in rows {
                state.admit(path, &row.listing)?;
            }
            state.initialized = true;
        }
        Ok(state)
    }
    pub(super) fn retained_index_charge(&self) -> usize {
        self.0
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .owners
            .len()
            .saturating_mul(INDEX_COORD)
    }
    pub(super) fn visit(&self, visit: impl FnOnce(usize, usize)) {
        let state = self.0.lock().unwrap_or_else(|e| e.into_inner());
        visit(&state.owners as *const _ as usize, state.owners.len());
    }
}
impl State {
    pub(super) fn total(&self) -> usize {
        self.total
    }
    fn fail<T>(&mut self, message: &str) -> io::Result<T> {
        self.denied = true;
        Err(invalid(message))
    }
    fn path_charge(&mut self, capacity: usize) -> io::Result<usize> {
        match 128usize.checked_add(capacity) {
            Some(bytes) => Ok(bytes),
            None => self.fail("typed directory path charge overflow"),
        }
    }
    pub(super) fn admit(
        &mut self,
        path: &PathBuf,
        listing: &PolicyDirectoryListing,
    ) -> io::Result<()> {
        if self.denied {
            return Err(invalid(
                "typed directory metadata admission previously failed",
            ));
        }
        let mut extra = self.path_charge(path.capacity())?;
        let mut new_owner = None;
        if let PolicyDirectoryListing::Present(entries) = listing {
            #[cfg(test)]
            {
                self.owner_lookups += 1;
            }
            let key = Arc::as_ptr(&entries.0) as usize;
            match self.owners.get(&key) {
                Some(weak) => {
                    if weak
                        .upgrade()
                        .is_none_or(|old| !Arc::ptr_eq(&old, &entries.0))
                    {
                        return self.fail("typed directory accounting owner identity expired");
                    }
                }
                None => {
                    // The unchanged full-capacity helper walks names only once
                    // per unique retained owner, not on every budget check.
                    let payload = match listing.storage(&mut BTreeSet::new()) {
                        Ok(v) => v,
                        Err(_) => return self.fail("typed directory payload charge overflow"),
                    };
                    #[cfg(test)]
                    {
                        self.name_visits += entries.len();
                    }
                    extra = match extra
                        .checked_add(payload)
                        .and_then(|n| n.checked_add(INDEX_COORD))
                    {
                        Some(v) => v,
                        None => return self.fail("typed directory owner charge overflow"),
                    };
                    new_owner = Some((key, Arc::downgrade(&entries.0)));
                }
            }
        }
        let next = match self
            .total
            .checked_add(extra)
            .filter(|n| *n <= METADATA_BOUND)
        {
            Some(v) => v,
            None => return self.fail("typed policy metadata exceeds existing64MiB bound"),
        };
        // Capacity is accepted BEFORE growing the owner index. BTree node
        // coordinates are conservatively charged; no allocator/RSS claim.
        if let Some((key, owner)) = new_owner {
            self.owners.insert(key, owner);
        }
        self.total = next;
        Ok(())
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn listing(count: usize) -> PolicyDirectoryListing {
        PolicyDirectoryListing::Present(
            (0..count)
                .map(|n| PolicyDirectoryEntry {
                    name: format!("f{n:05}.dm"),
                    kind: PolicyEntryKind::File,
                })
                .collect::<Vec<_>>()
                .into(),
        )
    }
    fn reference(rows: &BTreeMap<PathBuf, PolicyDirectoryObservation>) -> usize {
        let mut seen = BTreeSet::new();
        let mut total = std::mem::size_of_val(rows);
        for (path, row) in rows {
            total += 128 + path.capacity() + row.listing.storage(&mut seen).unwrap();
        }
        total
    }
    #[test]
    fn incremental_directory_charge_matches_full_capacity_census_and_shared_owner_dedup() {
        let mut snapshot = InputSnapshot::new(1);
        let shared = listing(7);
        for n in 0..30 {
            snapshot
                .record_policy_directory(
                    Path::new(&format!("root/d{n}")),
                    false,
                    if n % 2 == 0 {
                        shared.clone()
                    } else {
                        listing(n)
                    },
                )
                .unwrap();
        }
        let state = snapshot
            .policy_directory_accounting
            .lock(&snapshot.policy_directories)
            .unwrap();
        assert_eq!(
            state.total(),
            reference(&snapshot.policy_directories)
                + std::mem::size_of::<DirectoryChargeMemo>()
                + state.owners.len() * INDEX_COORD
        );
        assert_eq!(state.owners.len(), 16);
        assert_eq!(
            state.name_visits,
            7 + (0..30).filter(|n| n % 2 != 0).sum::<usize>()
        );
    }
    #[test]
    fn thousands_of_budget_checks_do_not_rewalk_directory_payloads() {
        let mut snapshot = InputSnapshot::new(1);
        for n in 0..256 {
            snapshot
                .record_policy_directory(Path::new(&format!("root/d{n}")), false, listing(4))
                .unwrap();
            for _ in 0..32 {
                snapshot.policy_directory_charge().unwrap();
            }
        }
        let state = snapshot
            .policy_directory_accounting
            .lock(&snapshot.policy_directories)
            .unwrap();
        assert_eq!(state.name_visits, 256 * 4);
        assert_eq!(state.owner_lookups, 256);
        assert_eq!(state.owners.len(), 256);
    }
    #[test]
    fn cloned_or_deserialized_directory_ledgers_rebuild_once_without_changing_facts() {
        let mut snapshot = InputSnapshot::new(1);
        snapshot
            .record_policy_directory(Path::new("root/a"), false, listing(3))
            .unwrap();
        let cloned = snapshot.clone();
        assert_eq!(cloned, snapshot);
        cloned.policy_directory_charge().unwrap();
        cloned.policy_directory_charge().unwrap();
        assert_eq!(
            cloned
                .policy_directory_accounting
                .lock(&cloned.policy_directories)
                .unwrap()
                .name_visits,
            3
        );
        let decoded: InputSnapshot =
            serde_json::from_slice(&serde_json::to_vec(&snapshot).unwrap()).unwrap();
        assert_eq!(decoded, snapshot);
        let actual = decoded.policy_directory_charge().unwrap();
        let state = decoded
            .policy_directory_accounting
            .lock(&decoded.policy_directories)
            .unwrap();
        assert_eq!(
            actual,
            reference(&decoded.policy_directories)
                + std::mem::size_of::<DirectoryChargeMemo>()
                + state.owners.len() * INDEX_COORD
        );
    }
    #[test]
    fn directory_capacity_failure_is_sticky_and_never_installs_the_rejected_fact() {
        let mut snapshot = InputSnapshot::new(1);
        snapshot
            .record_policy_directory(Path::new("root/a"), false, listing(1))
            .unwrap();
        {
            let mut state = snapshot
                .policy_directory_accounting
                .lock(&snapshot.policy_directories)
                .unwrap();
            state.total = METADATA_BOUND;
        }
        assert!(snapshot
            .record_policy_directory(Path::new("root/b"), false, listing(1))
            .is_err());
        assert!(!snapshot
            .policy_directories
            .contains_key(Path::new("root/b")));
        assert!(snapshot.policy_directory_charge().is_err());
        assert!(snapshot.clone().policy_directory_charge().is_err());
    }
    #[test]
    fn directory_accounting_merge_updates_once_and_never_changes_recorded_facts() {
        let shared = listing(5);
        let mut a = InputSnapshot::new(1);
        let mut b = InputSnapshot::new(1);
        a.record_policy_directory(Path::new("root/a"), false, shared.clone())
            .unwrap();
        b.record_policy_directory(Path::new("root/b"), false, shared)
            .unwrap();
        a.merge(&b).unwrap();
        let bytes = a.policy_directory_charge().unwrap();
        a.merge(&b).unwrap();
        assert_eq!(a.policy_directory_charge().unwrap(), bytes);
        let state = a
            .policy_directory_accounting
            .lock(&a.policy_directories)
            .unwrap();
        assert_eq!(state.name_visits, 5);
        assert_eq!(state.owners.len(), 1);
        assert_eq!(
            bytes,
            reference(&a.policy_directories)
                + std::mem::size_of::<DirectoryChargeMemo>()
                + INDEX_COORD
        );
    }
    #[test]
    fn expired_weak_directory_coordinate_is_not_accepted_as_live_owner_credit() {
        let shared = listing(2);
        let mut snapshot = InputSnapshot::new(1);
        snapshot
            .record_policy_directory(Path::new("root/a"), false, shared.clone())
            .unwrap();
        {
            let mut state = snapshot
                .policy_directory_accounting
                .lock(&snapshot.policy_directories)
                .unwrap();
            let key = *state.owners.keys().next().unwrap();
            state.owners.insert(key, Weak::new());
        }
        assert!(snapshot
            .record_policy_directory(Path::new("root/b"), false, shared)
            .is_err());
        assert!(!snapshot
            .policy_directories
            .contains_key(Path::new("root/b")));
        assert!(snapshot.policy_directory_charge().is_err());
    }
    #[test]
    fn path_charge_overflow_latches_denial_before_any_allocation() {
        let snapshot = InputSnapshot::new(1);
        let mut state = snapshot
            .policy_directory_accounting
            .lock(&snapshot.policy_directories)
            .unwrap();
        assert!(state.path_charge(usize::MAX).is_err());
        assert!(state.denied);
        assert!(state
            .admit(&PathBuf::from("root/a"), &PolicyDirectoryListing::Missing)
            .is_err());
    }
}
