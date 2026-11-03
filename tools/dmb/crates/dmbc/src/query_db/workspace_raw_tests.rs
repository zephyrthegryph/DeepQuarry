//! Mechanism tests use private page constructors, not public host authority.
//! Host authenticity/absence/typed-discovery tests remain a separate cohort.
use super::*;
use dm_resources::SharedBytes;
fn empty_live() -> Weak<Mutex<Owners>> {
    static EMPTY: std::sync::OnceLock<Arc<Mutex<Owners>>> = std::sync::OnceLock::new();
    Arc::downgrade(EMPTY.get_or_init(|| Arc::new(Mutex::new(Owners::default()))))
}
fn root() -> PathBuf {
    std::env::current_dir().unwrap().join("workspace-page-test")
}
fn policy(bytes: Option<&[u8]>) -> Arc<Scope> {
    Arc::new(
        Config::capture(match bytes {
            Some(b) => Configuration::Captured(b),
            None => Configuration::ProvenMissing,
        })
        .unwrap()
        .scope("scheduler")
        .unwrap(),
    )
}
fn originals(count: usize) -> Vec<SharedBytes> {
    (0..count)
        .map(|_| SharedBytes::from(b"/proc/p()\n    sleep(1)\n".to_vec()))
        .collect()
}
fn current(owners: &[SharedBytes], range: std::ops::Range<usize>) -> Vec<CurrentFile> {
    range
        .map(|i| {
            let text: SourceText = String::from_utf8(owners[i].as_slice().to_vec())
                .unwrap()
                .into();
            let mut storage = BTreeMap::new();
            captured_raw_file::visit_source_storage(&text, |key, bytes| {
                storage
                    .entry(key)
                    .and_modify(|n: &mut usize| *n = (*n).max(bytes))
                    .or_insert(bytes);
            });
            CurrentFile {
                path: root().join(format!("code/{i:04}.dm")),
                text: Some(text),
                proof: SourceProof::Owned(Arc::downgrade(owners[i].shared_owner())),
                charge: storage.values().sum(),
            }
        })
        .collect()
}
fn page(
    db: &Db,
    page: usize,
    owners: &[SharedBytes],
    scope: Arc<Scope>,
    scans: Arc<AtomicUsize>,
    graph: u64,
    epoch: u128,
) -> Arc<PageResult> {
    let input = Key::new(PAGE_INPUT, page as u128);
    let result = Key::new(PAGE_RESULT, page as u128);
    let old = db.retained_value::<Result<Arc<PageResult>, String>>(result);
    let start = page * PAGE_FILES;
    let end = (start + PAGE_FILES).min(owners.len());
    db.set_input(
        input,
        PageInput {
            graph,
            root: root(),
            configuration: root().join("scopes.toml"),
            scopes: vec![scope],
            names: vec!["scheduler"],
            files: current(owners, start..end),
            previous: old.as_ref().map_or_else(Weak::new, Arc::downgrade),
            scans,
            result_budget: RESULT_BOUND,
            input_budget: INPUT_BOUND,
            live: empty_live(),
            remaining_sites: MAX_SITES,
        },
        epoch,
    );
    let _release = PageInputLease { db, key: input };
    db.get::<Result<Arc<PageResult>, String>>(result, Arc::new(Params { input }))
        .unwrap()
        .as_ref()
        .as_ref()
        .unwrap()
        .clone()
}
#[test]
fn three_pages_257_files_measure_cold_warm_one_edit_and_eviction() {
    let db = Db::new();
    register(&db);
    let scans = Arc::new(AtomicUsize::new(0));
    let mut owners = originals(257);
    let scope = policy(None);
    for p in 0..3 {
        assert_eq!(
            page(&db, p, &owners, scope.clone(), scans.clone(), 1, 1)
                .files
                .len(),
            if p == 2 { 1 } else { 128 }
        );
    }
    assert_eq!(scans.load(Ordering::Relaxed), 257);
    for p in 0..3 {
        page(&db, p, &owners, scope.clone(), scans.clone(), 1, 2);
    }
    assert_eq!(
        scans.load(Ordering::Relaxed),
        257,
        "warm page revalidation must not rescan files"
    );
    owners[129] = SharedBytes::from(b"/proc/p()\n    sleep(2)\n".to_vec());
    for p in 0..3 {
        page(&db, p, &owners, scope.clone(), scans.clone(), 1, 3);
    }
    assert_eq!(
        scans.load(Ordering::Relaxed),
        258,
        "one physical original edit rescans exactly one file"
    );
    assert_eq!(db.len(), 6, "no per-file/per-lint graph-node explosion");
    for p in 0..3 {
        assert!(db
            .retained_value::<PageInput>(Key::new(PAGE_INPUT, p))
            .is_none());
    }
    db.evict_values(&[PAGE_RESULT]);
    for p in 0..3 {
        page(&db, p, &owners, scope.clone(), scans.clone(), 1, 4);
    }
    assert_eq!(
        scans.load(Ordering::Relaxed),
        515,
        "eviction recomputes from retained exact originals without frontend parse"
    );
}
#[test]
fn exact_scope_early_cutoff_and_foreign_graph_do_not_reuse_findings() {
    let db = Db::new();
    register(&db);
    let scans = Arc::new(AtomicUsize::new(0));
    let owners = originals(3);
    page(&db, 0, &owners, policy(None), scans.clone(), 1, 1);
    page(
        &db,
        0,
        &owners,
        policy(Some(b"# unrelated comment\n")),
        scans.clone(),
        1,
        2,
    );
    assert_eq!(scans.load(Ordering::Relaxed), 3);
    page(
        &db,
        0,
        &owners,
        policy(Some(b"[lint.scheduler]\nexempt_files=['code/0000.dm']\n")),
        scans.clone(),
        1,
        3,
    );
    assert_eq!(
        scans.load(Ordering::Relaxed),
        5,
        "one newly exempt source avoids its builder"
    );
    page(&db, 0, &owners, policy(None), scans.clone(), 2, 4);
    assert_eq!(
        scans.load(Ordering::Relaxed),
        8,
        "foreign graph cannot reuse compact contributions"
    );
}
#[test]
fn independently_equal_owned_bytes_do_not_authorize_original_reuse() {
    let db = Db::new();
    register(&db);
    let scans = Arc::new(AtomicUsize::new(0));
    let a = originals(2);
    let b = originals(2);
    page(&db, 0, &a, policy(None), scans.clone(), 1, 1);
    page(&db, 0, &b, policy(None), scans.clone(), 1, 2);
    assert_eq!(scans.load(Ordering::Relaxed), 4);
}
#[test]
fn page_error_drops_input_payload_and_publishes_no_clean_result() {
    let db = Db::new();
    register(&db);
    let scans = Arc::new(AtomicUsize::new(0));
    let owners = originals(1);
    let input = Key::new(PAGE_INPUT, 0);
    let result = Key::new(PAGE_RESULT, 0);
    let mut files = current(&owners, 0..1);
    files[0].path = root().parent().unwrap().join("foreign.dm");
    db.set_input(
        input,
        PageInput {
            graph: 1,
            root: root(),
            configuration: root().join("scopes.toml"),
            scopes: vec![policy(None)],
            names: vec!["scheduler"],
            files,
            previous: Weak::new(),
            scans,
            result_budget: RESULT_BOUND,
            input_budget: INPUT_BOUND,
            live: empty_live(),
            remaining_sites: MAX_SITES,
        },
        1,
    );
    {
        let _release = PageInputLease {
            db: &db,
            key: input,
        };
        assert!(db
            .get::<Result<Arc<PageResult>, String>>(result, Arc::new(Params { input }))
            .unwrap()
            .is_err());
    }
    assert!(db.retained_value::<PageInput>(input).is_none());
}

#[test]
fn one_changed_scope_recomputes_only_that_family() {
    let owners = originals(2);
    let counter = Arc::new(AtomicUsize::new(0));
    let config = Config::capture(Configuration::ProvenMissing).unwrap();
    let a = Arc::new(config.scope("scheduler").unwrap());
    let b = Arc::new(config.scope("qdel_src").unwrap());
    let first = PageInput {
        graph: 1,
        root: root(),
        configuration: root().join("scopes.toml"),
        scopes: vec![a, b.clone()],
        names: vec!["scheduler", "qdel_src"],
        files: current(&owners, 0..2),
        previous: Weak::new(),
        scans: counter.clone(),
        result_budget: RESULT_BOUND,
        input_budget: INPUT_BOUND,
        live: empty_live(),
        remaining_sites: MAX_SITES,
    };
    let old: Arc<Result<Arc<PageResult>, String>> = Arc::new(compute(&first).map(Arc::new));
    assert_eq!(counter.load(Ordering::Relaxed), 4);
    let next = PageInput {
        scopes: vec![
            policy(Some(b"[lint.scheduler]\nexempt_files=['code/0000.dm']\n")),
            b,
        ],
        files: current(&owners, 0..2),
        previous: Arc::downgrade(&old),
        ..first
    };
    assert!(compute(&next).is_ok());
    assert_eq!(
        counter.load(Ordering::Relaxed),
        5,
        "one newly exempt family/source avoids its builder"
    );
}

#[test]
fn regular_raw_and_workspace_share_node_input_and_result_limits_and_release() {
    let q = QueryDb::default();
    let owners = originals(1);
    let scans = Arc::new(AtomicUsize::new(0));
    page(&q.db, 0, &owners, policy(None), scans.clone(), q.id, 1);
    let input = Key::new(PAGE_INPUT, 0);
    let result = Key::new(PAGE_RESULT, 0);
    q.workspace_admit_page(input, result).unwrap();
    assert_eq!(q.workspace_counts_locked().0, 2);
    assert!(q.workspace_counts_locked().1 > 0);
    assert!(
        q.workspace_remaining_results(result).unwrap() < RESULT_BOUND,
        "current old result stays charged while replacement holds its Arc"
    );
    q.raw_policy.admission.leases.lock().unwrap().insert(
        Key::new(super::super::RAW_FILE, 999),
        super::super::Lease {
            owner: super::super::LeaseOwner::Semantic(Weak::new()),
            bytes: INPUT_BOUND - 1024 - q.workspace_nodes_locked() * 96,
            touched: std::time::Instant::now(),
        },
    );
    assert_eq!(q.workspace_input_headroom_locked(1000).unwrap(), 24);
    assert!(q.workspace_input_headroom_locked(1024).is_err());
    assert!(
        q.workspace_remaining_results(result).is_err(),
        "1024 bytes cannot admit the conservative census coordination root"
    );
    q.release_raw_policy_cache();
    assert_eq!(q.workspace_counts_locked(), (0, 0));
    assert!(q
        .db
        .retained_value::<Result<Arc<PageResult>, String>>(result)
        .is_none());
}
#[test]
fn page_trim_and_age_remove_actual_db_values_not_only_bookkeeping() {
    let q = QueryDb::default();
    let owners = originals(1);
    let scans = Arc::new(AtomicUsize::new(0));
    page(&q.db, 0, &owners, policy(None), scans.clone(), q.id, 1);
    let input = Key::new(PAGE_INPUT, 0);
    let result = Key::new(PAGE_RESULT, 0);
    q.workspace_admit_page(input, result).unwrap();
    q.workspace_trim_locked(0, RESULT_BOUND);
    assert_eq!(q.workspace_counts_locked(), (0, 0));
    assert!(q
        .db
        .retained_value::<Result<Arc<PageResult>, String>>(result)
        .is_none());
    page(&q.db, 0, &owners, policy(None), scans, q.id, 2);
    q.workspace_admit_page(input, result).unwrap();
    q.workspace_prune_expired_locked(
        std::time::Instant::now() + std::time::Duration::from_secs(301),
    );
    assert_eq!(q.workspace_counts_locked(), (0, 0));
    assert!(q
        .db
        .retained_value::<Result<Arc<PageResult>, String>>(result)
        .is_none());
}

#[test]
fn excluded_workspace_sources_need_no_text_but_any_live_scope_requires_real_text() {
    let bytes = originals(1);
    let scans = Arc::new(AtomicUsize::new(0));
    let excluded = policy(Some(b"[lint.scheduler]\nexempt_prefixes=['code/']\n"));
    let make = |scopes: Vec<Arc<Scope>>, names: Vec<&'static str>| PageInput {
        graph: 1,
        root: root(),
        configuration: root().join("scopes.toml"),
        scopes,
        names,
        files: vec![CurrentFile {
            path: root().join("code/0000.dm"),
            text: None,
            proof: SourceProof::Owned(Arc::downgrade(bytes[0].shared_owner())),
            charge: 0,
        }],
        previous: Weak::new(),
        scans: scans.clone(),
        result_budget: RESULT_BOUND,
        input_budget: INPUT_BOUND,
        live: empty_live(),
        remaining_sites: MAX_SITES,
    };
    let empty = compute(&make(vec![excluded.clone()], vec!["scheduler"])).unwrap();
    assert!(empty.files[0].findings[0].run.sites.is_empty());
    assert_eq!(scans.load(Ordering::Relaxed), 0);
    let qdel = Arc::new(
        Config::capture(Configuration::ProvenMissing)
            .unwrap()
            .scope("qdel_src")
            .unwrap(),
    );
    assert!(
        compute(&make(vec![excluded, qdel], vec!["scheduler", "qdel_src"])).is_err(),
        "one nonexempt family must demand actual captured text"
    );
    assert_eq!(scans.load(Ordering::Relaxed), 0);
}

#[test]
fn page_scan_respects_remaining_family_bytes_before_retaining_findings() {
    let owners = originals(3);
    let p = PageInput {
        graph: 1,
        root: root(),
        configuration: root().join("scopes.toml"),
        scopes: vec![policy(None)],
        names: vec!["scheduler"],
        files: current(&owners, 0..3),
        previous: Weak::new(),
        scans: Arc::new(AtomicUsize::new(0)),
        result_budget: 1,
        input_budget: INPUT_BOUND,
        live: empty_live(),
        remaining_sites: MAX_SITES,
    };
    assert!(compute(&p).is_err());
    assert_eq!(p.scans.load(Ordering::Relaxed), 0);
    let mut p = p;
    p.result_budget = RESULT_BOUND;
    p.remaining_sites = 0;
    assert!(
        compute(&p).is_err(),
        "a denied site must not publish a clean page"
    );
}

#[test]
fn resource_only_address_receipts_do_not_authorize_dead_owner_reuse() {
    let scope = policy(None);
    let address = Arc::as_ptr(&scope) as usize;
    let mut live = Owners::default();
    live.scope(&scope);
    drop(scope);
    let mut replacement = Owners::default();
    replacement.add_unless(&live, 0, address, 1);
    assert_eq!(
        replacement.bytes, 1,
        "expired weak census owner cannot suppress a new charge"
    );
}

#[test]
fn new_query_frees_incompatible_partial_pages_but_preserves_compatible_contributions() {
    let q = QueryDb::default();
    let owners = originals(1);
    let scans = Arc::new(AtomicUsize::new(0));
    let install = |id: u128, name: &'static str| {
        let input = Key::new(PAGE_INPUT, id);
        let result = Key::new(PAGE_RESULT, id);
        q.db.set_input(
            input,
            PageInput {
                graph: q.id,
                root: root(),
                configuration: root().join("scopes.toml"),
                scopes: vec![policy(None)],
                names: vec![name],
                files: current(&owners, 0..1),
                previous: Weak::new(),
                scans: scans.clone(),
                result_budget: RESULT_BOUND,
                input_budget: INPUT_BOUND,
                live: empty_live(),
                remaining_sites: MAX_SITES,
            },
            id,
        );
        let value =
            q.db.get::<Result<Arc<PageResult>, String>>(result, Arc::new(Params { input }))
                .unwrap();
        let held = Arc::clone(value.as_ref().as_ref().unwrap());
        q.workspace_admit_page(input, result).unwrap();
        held
    };
    let keep = install(701, "scheduler");
    let incompatible = install(702, "qdel_src");
    q.workspace_prepare_query_locked(&root(), &root().join("scopes.toml"), &["scheduler"]);
    assert!(q
        .db
        .retained_value::<Result<Arc<PageResult>, String>>(Key::new(PAGE_RESULT, 701))
        .is_some());
    assert!(q
        .db
        .retained_value::<Result<Arc<PageResult>, String>>(Key::new(PAGE_RESULT, 702))
        .is_none());
    assert!(q.db.input::<PageInput>(Key::new(PAGE_INPUT, 702)).is_none());
    let cached = q.workspace_owners_locked(&[]).unwrap().bytes;
    let with_held = q.workspace_owners_locked(&[incompatible]).unwrap().bytes;
    assert!(
        with_held > cached,
        "evicted-but-borrowed current owners remain charged"
    );
    assert!(Arc::ptr_eq(
        &keep,
        q.db.retained_value::<Result<Arc<PageResult>, String>>(Key::new(PAGE_RESULT, 701))
            .unwrap()
            .as_ref()
            .as_ref()
            .unwrap()
    ));
}

#[test]
fn outcome_census_counts_error_capacity_once_and_carries_a_weak_live_owner_receipt() {
    let mut text = String::with_capacity(64 * 1024);
    text.push('x');
    let error: Arc<Result<Arc<PageResult>, String>> = Arc::new(Err(text));
    let expected = super::super::result_error_charge::<Arc<PageResult>>(
        error.as_ref().as_ref().err().unwrap(),
    );
    let address = Arc::as_ptr(&error) as usize;
    let mut owners = Owners::default();
    owners.outcome(4, &error);
    assert_eq!(owners.bytes, expected);
    owners.outcome(4, &error);
    assert_eq!(owners.bytes, expected);
    assert!(owners.keys[&(4, address)].life.live());
    drop(error);
    assert!(!owners.keys[&(4, address)].life.live());
}

#[test]
fn denied_page_error_envelope_is_not_cached_as_a_small_or_clean_result() {
    let q = QueryDb::default();
    let input = Key::new(PAGE_INPUT, 995);
    let result = Key::new(PAGE_RESULT, 995);
    q.db.set_input(
        input,
        PageInput {
            graph: q.id,
            root: root(),
            configuration: root().join("scopes.toml"),
            scopes: vec![policy(None)],
            names: vec!["scheduler"],
            files: Vec::new(),
            previous: Weak::new(),
            scans: Arc::new(AtomicUsize::new(0)),
            result_budget: 0,
            input_budget: INPUT_BOUND,
            live: empty_live(),
            remaining_sites: MAX_SITES,
        },
        1,
    );
    assert!(q
        .db
        .get::<Result<Arc<PageResult>, String>>(result, Arc::new(Params { input }))
        .is_err());
    assert!(q
        .db
        .retained_value::<Result<Arc<PageResult>, String>>(result)
        .is_none());
}
#[test]
fn workspace_page_cancellation_after_first_scan_never_retains_partial_page() {
    let q = QueryDb::default();
    let owners = originals(3);
    let scans = Arc::new(AtomicUsize::new(0));
    let input = Key::new(PAGE_INPUT, 1188);
    let result = Key::new(PAGE_RESULT, 1188);
    q.db.set_input(
        input,
        PageInput {
            graph: q.id,
            root: root(),
            configuration: root().join("scopes.toml"),
            scopes: vec![policy(None)],
            names: vec!["scheduler"],
            files: current(&owners, 0..3),
            previous: Weak::new(),
            scans: scans.clone(),
            result_budget: RESULT_BOUND,
            input_budget: INPUT_BOUND,
            live: empty_live(),
            remaining_sites: MAX_SITES,
        },
        1,
    );
    let revision = q.db.revision();
    let token = crate::daemon::control::Cancellation::default();
    q.raw_policy.admission.abort.begin();
    q.raw_policy
        .admission
        .abort
        .cancel_on_poll(4, token.clone());
    let binding = crate::daemon::control::bind_with_deadline(
        token,
        std::time::Instant::now() + std::time::Duration::from_secs(60),
    );
    let failure =
        q.db.get::<Result<Arc<PageResult>, String>>(result, Arc::new(Params { input }))
            .err()
            .expect("mid-page cancellation");
    let error = q.derived_query_error("workspace page", failure);
    assert_eq!(error.kind(), io::ErrorKind::Interrupted);
    assert_eq!(
        scans.load(Ordering::Relaxed),
        1,
        "cancel only AFTER first real per-file policy scan"
    );
    assert!(q
        .db
        .retained_value::<Result<Arc<PageResult>, String>>(result)
        .is_none());
    drop(binding);
    q.raw_policy.admission.abort.disarm();
    q.raw_policy.admission.abort.begin();
    let value =
        q.db.get::<Result<Arc<PageResult>, String>>(result, Arc::new(Params { input }))
            .unwrap();
    let page = value.as_ref().as_ref().unwrap();
    assert_eq!(page.files.len(), 3);
    assert_eq!(revision, q.db.revision());
}

#[test]
fn incremental_inventory_has_exact_full_census_charge_and_linear_unique_page_visits() {
    let q = QueryDb::default();
    let originals = originals(PAGE_FILES * 24);
    let scope = policy(None);
    let scans = Arc::new(AtomicUsize::new(0));
    let inventory = q.workspace_resource_inventory_locked().unwrap();
    let mut held = Vec::new();
    for index in 0..24 {
        let p = page(
            &q.db,
            index,
            &originals,
            scope.clone(),
            scans.clone(),
            q.id,
            1,
        );
        let input = Key::new(PAGE_INPUT, index as u128);
        let key = Key::new(PAGE_RESULT, index as u128);
        q.raw_policy
            .workspace
            .pages
            .lock()
            .unwrap()
            .insert(key, (input, std::time::Instant::now()));
        let result =
            q.db.retained_value::<Result<Arc<PageResult>, String>>(key)
                .unwrap();
        inventory.add_page_result(&result).unwrap();
        held.push(p);
        // The independent full-census path rescans all currently retained values.
        // This tests actual capacities/shared Arcs, not a copied byte estimate.
        assert_eq!(
            inventory.bytes(),
            q.workspace_owners_locked(&held).unwrap().bytes
        );
        assert!(
            inventory.coordination_charge(0).unwrap()
                >= inventory.owners.lock().unwrap().keys.len() * 256
        );
    }
    assert_eq!(
        inventory.owners.lock().unwrap().page_walks,
        24,
        "each unique immutable page is traversed once across the whole operation"
    );
    for p in &held {
        inventory.owners.lock().unwrap().page(p);
    }
    assert_eq!(
        inventory.owners.lock().unwrap().page_walks,
        24,
        "reencountering a page through held/aggregate ownership must be O(1)"
    );
}

#[test]
fn operation_pins_and_weak_input_inventory_drop_after_success_error_and_abort() {
    for disposition in ["success", "error", "abort"] {
        let q = QueryDb::default();
        let source = originals(1);
        let scope = policy(None);
        let p = page(
            &q.db,
            0,
            &source,
            scope.clone(),
            Arc::new(AtomicUsize::new(0)),
            q.id,
            1,
        );
        let input = Key::new(PAGE_INPUT, 0);
        let key = Key::new(PAGE_RESULT, 0);
        q.raw_policy
            .workspace
            .pages
            .lock()
            .unwrap()
            .insert(key, (input, std::time::Instant::now()));
        let outcome =
            q.db.retained_value::<Result<Arc<PageResult>, String>>(key)
                .unwrap();
        let outcome_weak = Arc::downgrade(&outcome);
        let page_weak = Arc::downgrade(&p);
        drop(outcome);
        drop(p);
        let inventory = q.workspace_resource_inventory_locked().unwrap();
        let inventory_weak = Arc::downgrade(&inventory.owners);
        // Retain an actual input after dropping its result. The input's Weak
        // inventory token cannot retain operation pins or any derived payload.
        q.db.set_input(
            input,
            PageInput {
                graph: q.id,
                root: root(),
                configuration: root().join("scopes.toml"),
                scopes: vec![scope],
                names: vec!["scheduler"],
                files: vec![],
                previous: Weak::new(),
                scans: Arc::new(AtomicUsize::new(0)),
                result_budget: RESULT_BOUND,
                input_budget: INPUT_BOUND,
                live: inventory_weak.clone(),
                remaining_sites: MAX_SITES,
            },
            2,
        );
        q.db.evict_value_at(key);
        assert!(
            outcome_weak.upgrade().is_some(),
            "{disposition}: live operation pin"
        );
        let cancellation = crate::daemon::control::Cancellation::default();
        let _control = crate::daemon::control::bind_with_deadline(
            cancellation.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(10),
        );
        if disposition == "abort" {
            cancellation.cancel();
        }
        let operation: io::Result<()> = (|| {
            let _inventory = inventory;
            crate::daemon::control::checkpoint()?;
            if disposition == "error" {
                return Err(invalid(disposition));
            }
            Ok(())
        })();
        if disposition == "abort" {
            assert_eq!(
                operation.as_ref().unwrap_err().kind(),
                io::ErrorKind::Interrupted
            );
        }
        assert_eq!(operation.is_ok(), disposition == "success");
        assert!(
            inventory_weak.upgrade().is_none(),
            "{disposition}: no inventory leak"
        );
        assert!(
            outcome_weak.upgrade().is_none(),
            "{disposition}: no Outcome leak"
        );
        assert!(page_weak.upgrade().is_none(), "{disposition}: no page leak");
    }
}
