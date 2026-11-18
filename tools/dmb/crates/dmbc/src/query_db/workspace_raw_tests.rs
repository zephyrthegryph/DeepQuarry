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
                proof: SourceProof::Owned(owners[i].downgrade()),
                charge: storage.values().sum(),
                raw_selection: None,
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
        PageInput { scoped_patterns:false,
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
        PageInput { scoped_patterns:false,
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
    let first = PageInput { scoped_patterns:false,
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
    let next = PageInput { scoped_patterns:false,
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
    q.workspace_admit_page(input, result, false).unwrap();
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
    q.workspace_admit_page(input, result, false).unwrap();
    q.db.set_input(RAW_TERMINAL_KEY, RawTerminalBody {
        witness: Mutex::new(Weak::new()),
        bytes: vec![1],
        hash: 0,
        clean: true,
    }, 1);
    assert_eq!(q.bulk_raw_terminal_nodes_locked(), 1);
    q.workspace_trim_locked(0, RESULT_BOUND);
    assert_eq!(q.bulk_raw_terminal_nodes_locked(), 0);
    assert_eq!(q.workspace_counts_locked(), (0, 0));
    assert!(q
        .db
        .retained_value::<Result<Arc<PageResult>, String>>(result)
        .is_none());
    page(&q.db, 0, &owners, policy(None), scans, q.id, 2);
    q.workspace_admit_page(input, result, false).unwrap();
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
    let make = |scopes: Vec<Arc<Scope>>, names: Vec<&'static str>| PageInput { scoped_patterns:false,
        graph: 1,
        root: root(),
        configuration: root().join("scopes.toml"),
        scopes,
        names,
        files: vec![CurrentFile {
            path: root().join("code/0000.dm"),
            text: None,
            proof: SourceProof::Owned(bytes[0].downgrade()),
            charge: 0,
                raw_selection: None,
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
    let p = PageInput { scoped_patterns:false,
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
            PageInput { scoped_patterns:false,
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
        q.workspace_admit_page(input, result, false).unwrap();
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
        PageInput { scoped_patterns:false,
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
        PageInput { scoped_patterns:false,
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
            .insert(key, (input, std::time::Instant::now(), false));
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
            .insert(key, (input, std::time::Instant::now(), false));
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
            PageInput { scoped_patterns:false,
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

#[test]
fn bulk_raw_trim_retains_pinned_and_unrelated_results_and_keeps_query_coordinates() {
    let q = QueryDb::default();
    let originals = originals(PAGE_FILES * 3 + 1);
    let scope = policy(None);
    let scans = Arc::new(AtomicUsize::new(0));
    let now = std::time::Instant::now();
    for n in 0..4 {
        let input = Key::new(PAGE_INPUT, n);
        let key = Key::new(PAGE_RESULT, n);
        q.raw_policy.workspace.pages.lock().unwrap()
            .insert(key, (input, now + std::time::Duration::from_millis(n as u64), n != 3));
        drop(page(&q.db, n as usize, &originals, scope.clone(), scans.clone(), q.id, 1));
    }
    let first = Key::new(PAGE_RESULT, 0);
    let pinned = Key::new(PAGE_RESULT, 1);
    let recent = Key::new(PAGE_RESULT, 2);
    let unrelated = Key::new(PAGE_RESULT, 3);
    let value = q.db.retained_value::<Result<Arc<PageResult>, String>>(pinned).unwrap();
    let pinned_page = value.as_ref().as_ref().unwrap().clone();
    drop(value);
    let target = q.db.value_bytes_at(pinned) + q.db.value_bytes_at(recent);
    q.trim_bulk_raw_values_locked(target);
    assert_eq!(q.db.value_bytes_at(first), 0);
    assert!(q.db.value_bytes_at(pinned) != 0);
    assert!(q.db.value_bytes_at(recent) != 0);
    assert!(q.db.value_bytes_at(unrelated) != 0);
    assert!(q.raw_policy.workspace.pages.lock().unwrap().contains_key(&first));
    q.trim_bulk_raw_values_locked(0);
    assert!(q.db.value_bytes_at(pinned) != 0);
    assert_eq!(q.db.value_bytes_at(recent), 0);
    assert!(q.db.value_bytes_at(unrelated) != 0);
    drop(pinned_page);
    q.trim_bulk_raw_values_locked(0);
    assert_eq!(q.db.value_bytes_at(pinned), 0);
    let prior_scans = scans.load(Ordering::Relaxed);
    drop(page(&q.db, 0, &originals, scope, scans.clone(), q.id, 2));
    assert_eq!(scans.load(Ordering::Relaxed) - prior_scans, PAGE_FILES);
}

#[test]
fn terminal_coordinate_retirement_prefers_empty_bulk_page_and_respects_pins() {
    let q = QueryDb::default();
    let originals = originals(PAGE_FILES * 3 + 1);
    let scope = policy(None);
    let scans = Arc::new(AtomicUsize::new(0));
    let now = std::time::Instant::now();
    let mut pinned = None;
    for n in 0..4 {
        let input = Key::new(PAGE_INPUT,n);
        let key = Key::new(PAGE_RESULT,n);
        q.raw_policy.workspace.pages.lock().unwrap().insert(
            key,(input,now + std::time::Duration::from_millis(n as u64),n!=3));
        let value = page(&q.db,n as usize,&originals,scope.clone(),scans.clone(),q.id,1);
        if n==0 { pinned=Some(value); }
    }
    let key = |n| Key::new(PAGE_RESULT,n);
    q.db.evict_value_at(key(2));
    assert!(q.retire_bulk_page_coordinate_locked());
    assert!(!q.raw_policy.workspace.pages.lock().unwrap().contains_key(&key(2)));
    assert!(q.db.value_bytes_at(key(1))>0);
    assert!(q.retire_bulk_page_coordinate_locked());
    assert!(!q.raw_policy.workspace.pages.lock().unwrap().contains_key(&key(1)));
    assert!(!q.retire_bulk_page_coordinate_locked());
    assert!(q.db.value_bytes_at(key(0))>0 && q.db.value_bytes_at(key(3))>0);
    drop(pinned);
}


#[test]
fn actual_scoped_source_scan_uses_same_db_held_ledger_and_existing_policy_output(){
 let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let db=QueryDb::default();let budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();
 let mut ledger=raw_input_credits::Ledger::default();let root=root();
 let file=File::capture_budgeted(&root,&root.join("code/actor.dm"),"/proc/a()\n\tattack_ai()\n".into(),INPUT_BOUND).unwrap();
 let scope=Config::capture(Configuration::ProvenMissing).unwrap().scope("actor_forwarding").unwrap();
 let expected=file.scan(&scope).unwrap();
 source_arena::with_held_source_work(&db,&mut ledger,&budget,|work|{
  let provider=crate::query_db::PatternProvider::new(&db,work);
  let actual=file.scan_with_pattern_resources(&scope,10000,RESULT_BOUND,false,&budget,&provider,&crate::daemon::control::checkpoint).map_err(|error|match error{captured_raw_file::ScanFailure::Operational(actual)=>actual,other=>invalid(other.into_message())})?;
  assert_eq!(actual.fingerprint(),expected.fingerprint());assert_eq!(actual.run.sites.len(),1);Ok(())
 }).unwrap();
}
#[test]
fn actual_scoped_source_scan_retains_compile_1450_before_later_cancel_then_recovers(){
 use dm_preprocess::source_arena_credit::{SourceArenaCredit,SourceArenaWork};
 struct Stop<'a>{actual:&'a dyn SourceArenaWork}
 impl SourceArenaWork for Stop<'_>{
  fn checkpoint(&self)->io::Result<()>{self.actual.checkpoint()}
  fn reserve(&self,n:usize)->io::Result<SourceArenaCredit>{self.actual.reserve(n)}
  fn grow(&self,_:&mut SourceArenaCredit,_:usize)->io::Result<()>{Err(io::Error::from_raw_os_error(1450))}
  fn shrink(&self,credit:&mut SourceArenaCredit,n:usize)->io::Result<()>{self.actual.shrink(credit,n)}
 }
 let cancel=crate::daemon::control::Cancellation::default();
 let _binding=crate::daemon::control::bind_with_deadline(cancel.clone(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let db=QueryDb::default();let budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();let mut ledger=raw_input_credits::Ledger::default();let root=root();
 let file=File::capture_budgeted(&root,&root.join("code/actor.dm"),"/proc/a()\n\tattack_ai()\n".into(),INPUT_BOUND).unwrap();let scope=Config::capture(Configuration::ProvenMissing).unwrap().scope("actor_forwarding").unwrap();
 source_arena::with_held_source_work(&db,&mut ledger,&budget,|work|{
  let stopped=Stop{actual:work};let provider=crate::query_db::PatternProvider::new(&db,&stopped);
  let error=file.scan_with_pattern_resources(&scope,10000,RESULT_BOUND,false,&budget,&provider,&crate::daemon::control::checkpoint).unwrap_err();
  cancel.cancel();assert!(matches!(error,captured_raw_file::ScanFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));Ok(())
 }).unwrap();drop(_binding);
 let _recovery=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 source_arena::with_held_source_work(&db,&mut ledger,&budget,|work|{
  let provider=crate::query_db::PatternProvider::new(&db,work);let actual=file.scan_with_pattern_resources(&scope,10000,RESULT_BOUND,false,&budget,&provider,&crate::daemon::control::checkpoint).map_err(|error|invalid(error.into_message()))?;assert_eq!(actual.run.sites.len(),1);Ok(())
 }).unwrap();
}

#[test]
fn scoped_page_input_refuses_registered_unadmitted_fallback_before_empty_policy_result(){
 let db=QueryDb::default();let input=Key::new(PAGE_INPUT,918273);let result=Key::new(PAGE_RESULT,918273);let live=Arc::new(Mutex::new(Owners::default()));
 db.db.set_input(input,PageInput{scoped_patterns:true,graph:db.id,root:root(),configuration:root().join("scopes.toml"),scopes:vec![],names:vec![],files:vec![],previous:Weak::new(),scans:Arc::new(AtomicUsize::new(0)),result_budget:RESULT_BOUND,input_budget:INPUT_BOUND,live:Arc::downgrade(&live),remaining_sites:MAX_SITES},1);
 let error=db.db.get::<Result<Arc<PageResult>,String>>(result,Arc::new(Params{input})).err().expect("scoped input must refuse unadmitted fallback");
 let actual=error.into_operational().unwrap().into_io();assert_eq!(actual.kind(),io::ErrorKind::NotConnected);assert_eq!(db.db.value_bytes_at(result),0);
}


#[test]
fn actual_native_static_owner_policies_use_scoped_program_queries_and_match_original_rows(){
 let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let db=QueryDb::default();let budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();let mut ledger=raw_input_credits::Ledger::default();let root=root();
 for(name,text)in [
  ("breakpoint","/obj/probe/atom_break()\n\tstat |= BROKEN\n"),
  ("door_gates","CAPABILITIES(/obj/probe)\n\twhen(COVER_OPEN)\n"),
  ("entity_ids","/proc/p()\n\tnext_id++\n"),
  ("scheduler","/proc/p()\n\tsleep(1)\n"),
  ("containment","/proc/p()\n\tloc = destination\n"),
  ("sys/grants","/proc/p()\n\tverbs += /mob/proc/foo\n"),
  ("saved_handle","/proc/p()\n\tS[1] << handle_of(src)\n"),
  ("ref_text","/proc/p()\n\tstored = REF(src)\n"),
  ("silent_catch","/proc/p()\n\ttry\n\t\tthrow 1\n\tcatch(var/exception/e)\n\t\treturn\n"),
 ]{
  let file=File::capture_budgeted(&root,&root.join("code/owner.dm"),text.into(),INPUT_BOUND).unwrap();let scope=Config::capture(Configuration::ProvenMissing).unwrap().scope(name).unwrap();
  let expected=file.scan(&scope).unwrap();assert!(!expected.run.sites.is_empty(),"actual reference must exercise {name}");
  let before=db.db.stats(super::super::native_patterns::NATIVE_PATTERN).computed;
  source_arena::with_held_source_work(&db,&mut ledger,&budget,|work|{
   let provider=crate::query_db::PatternProvider::new(&db,work);let actual=file.scan_with_pattern_resources(&scope,10000,RESULT_BOUND,false,&budget,&provider,&crate::daemon::control::checkpoint).map_err(|error|match error{captured_raw_file::ScanFailure::Operational(actual)=>actual,other=>invalid(other.into_message())})?;
   assert_eq!(actual.fingerprint(),expected.fingerprint(),"actual source policy {name}");Ok(())
  }).unwrap();
  assert!(db.db.stats(super::super::native_patterns::NATIVE_PATTERN).computed>before,"{name} must use actual admitted query program, not the compatibility constructor");
 }
}


#[test]
fn actual_scoped_pattern_scratch_returns_same_zero_slot_and_refunds_only_disposed_payload(){
 use dq_analyze::native_pattern::{Provider as _,Spec,Mode};
 let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let db=QueryDb::default();let budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();let mut ledger=raw_input_credits::Ledger::default();
 let spec=Spec{pattern:r"([A-Z]+)=(\d+)",mode:Mode::Search};
 source_arena::with_held_pattern_work(&db,&mut ledger,&budget,|work,scratch|{
  let provider=crate::query_db::PatternProvider::scoped(&db,work,scratch);assert_eq!(provider.capture_len(spec)?,3);
  let before=budget.used();let fixed=std::mem::size_of::<dq_analyze::captured_generator_budget::Budget>()+2*std::mem::size_of::<usize>();
  for turn in 1..=3{
   let mut visited=false;assert!(provider.capture(spec,"KEY=42",0,&mut|groups|{visited=true;assert_eq!(groups[0],Some((0,6)));Ok(())})?);assert!(visited);
   assert_eq!(budget.used(),before+turn*fixed,"actual child payload and execution buffers must refund; existing fixed child metadata policy remains");
  }
  assert_eq!(db.db.stats(super::super::native_patterns::NATIVE_PATTERN).computed,1);Ok(())
 }).unwrap();
}
#[test]
fn actual_scoped_pattern_visitor_1450_precedes_cancel_and_new_real_frame_recovers(){
 use dq_analyze::native_pattern::{Provider as _,Spec,Mode};
 let cancel=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(cancel.clone(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let db=QueryDb::default();let budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();let mut ledger=raw_input_credits::Ledger::default();let spec=Spec{pattern:"KEY",mode:Mode::Search};
 let error=source_arena::with_held_pattern_work(&db,&mut ledger,&budget,|work,scratch|{
  let provider=crate::query_db::PatternProvider::scoped(&db,work,scratch);
  provider.find(spec,"KEY",0,&mut|_|{cancel.cancel();Err(io::Error::from_raw_os_error(1450))}).map(|_|())
 }).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));drop(binding);
 let _retry=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 source_arena::with_held_pattern_work(&db,&mut ledger,&budget,|work,scratch|{
  let provider=crate::query_db::PatternProvider::scoped(&db,work,scratch);assert!(provider.find(spec,"KEY",0,&mut|_|Ok(()))?);Ok(())
 }).unwrap();
}
#[test]
fn actual_scoped_pattern_one_byte_short_child_metadata_denies_before_search_then_reprepares(){
 use dq_analyze::native_pattern::{Provider as _,Spec,Mode};
 let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let db=QueryDb::default();let mut ledger=raw_input_credits::Ledger::default();let spec=Spec{pattern:"KEY",mode:Mode::Search};
 let denied=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();let called=std::cell::Cell::new(false);
 let error=source_arena::with_held_pattern_work(&db,&mut ledger,&denied,|work,scratch|{
  let provider=crate::query_db::PatternProvider::scoped(&db,work,scratch);provider.capture_len(spec)?;
  let fixed=std::mem::size_of::<dq_analyze::captured_generator_budget::Budget>()+2*std::mem::size_of::<usize>();
  denied.charge(denied.remaining()-(fixed-1)).map_err(invalid)?;
  provider.find(spec,"KEY",0,&mut|_|{called.set(true);Ok(())}).map(|_|())
 }).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);assert!(!called.get());assert!(denied.denied());
 let recovered=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();
 source_arena::with_held_pattern_work(&db,&mut ledger,&recovered,|work,scratch|{
  let provider=crate::query_db::PatternProvider::scoped(&db,work,scratch);assert!(provider.find(spec,"KEY",0,&mut|_|Ok(()))?);Ok(())
 }).unwrap();
}

#[test]
fn actual_native_dynamic_helper_policies_match_legacy_rows_and_reuse_same_db_programs(){
 let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let db=QueryDb::default();let budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();let mut ledger=raw_input_credits::Ledger::default();let root=root();
 for(name,text)in [
  ("sys/messages","/mob/proc/a(mob/actor)\n\tactor.visible_message(\"[actor.name] waves\")\n"),
  ("sys/damage_reactions","/obj/probe/bullet_act(obj/projectile/P, def_zone)\n\treturn FALSE\n/obj/probe/ex_act(severity)\n\tseverity++\n/obj/probe/hitby(atom/movable/AM)\n\treturn AM.redirect(AM.starting)\n"),
 ]{
  let file=File::capture_budgeted(&root,&root.join("code/dynamic.dm"),text.into(),INPUT_BOUND).unwrap();let scope=Config::capture(Configuration::ProvenMissing).unwrap().scope(name).unwrap();let expected=file.scan(&scope).unwrap();
  assert!(!expected.run.sites.is_empty(),"actual reference must exercise {name}");let mut computed=None;
  for turn in 0..2{source_arena::with_held_pattern_work(&db,&mut ledger,&budget,|work,scratch|{
   let provider=crate::query_db::PatternProvider::scoped(&db,work,scratch);let actual=file.scan_with_pattern_resources(&scope,10000,RESULT_BOUND,false,&budget,&provider,&crate::daemon::control::checkpoint).map_err(|error|match error{captured_raw_file::ScanFailure::Operational(actual)=>actual,other=>invalid(other.into_message())})?;
   assert_eq!(actual.fingerprint(),expected.fingerprint(),"actual dynamic helper policy {name}");Ok(())
  }).unwrap();let now=db.db.stats(super::super::native_patterns::NATIVE_PATTERN).computed;if turn==0{assert!(now>0);computed=Some(now)}else{assert_eq!(Some(now),computed,"warm real helper programs must share the same Db values")}}
 }
}

#[test]
fn actual_funded_ownership_event_scanner_uses_same_db_programs_and_exact_legacy_order(){
 use dq_analyze::{key_policy_control::Control,raw_ownership_policy as ownership};
 struct Work<'a>{budget:&'a dq_analyze::captured_generator_budget::Budget,patterns:&'a dyn dq_analyze::native_pattern::Provider,peak:usize}
 impl Control for Work<'_>{
  type Error=io::Error;const CHECKED:bool=true;
  fn native_patterns(&self)->Option<&dyn dq_analyze::native_pattern::Provider>{Some(self.patterns)}
  fn native_pattern_failed(&mut self,actual:io::Error)->io::Error{actual}
  fn checkpoint(&mut self)->io::Result<()>{crate::daemon::control::checkpoint()}
  fn reserve(&mut self,bytes:usize)->io::Result<()>{self.budget.charge(bytes).map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))}
  fn temporary(&mut self,_slot:usize,bytes:usize)->io::Result<()>{if bytes>self.peak{self.reserve(bytes-self.peak)?;self.peak=bytes}Ok(())}
  fn overflow(&mut self)->io::Error{self.budget.deny();io::ErrorKind::OutOfMemory.into()}
  fn allocation_failed(&mut self)->io::Error{self.budget.deny();io::ErrorKind::OutOfMemory.into()}
 }
 let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let db=QueryDb::default();let budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();let mut ledger=raw_input_credits::Ledger::default();
 // Literal legacy declaration DATA exercises the unchanged extraction algorithm;
 // this control grants no complete Original source or runtime declaration role.
 let file=dq_analyze::tree::SourceFile::from_text("code/events.dm","REGISTRY_TYPE(/datum/registry, x)\nGLOBAL_DATUM(holder, /datum)\n/datum/holder\n    var/static/list/datum/refs\n/datum/holder/relations()\n    . += owns(nameof(annotation))\n    . += rel_one(nameof(owned), kind = RELK_OWNED)\n    . += owns(nameof(copy), policy = OWN_PRIVATE_COPY)\nSYSTEM_DEF(grid)\n    var/tick\n");
 let expected=ownership::file_events(&file.rel,file.raw(),file.code());assert_eq!(expected.len(),7);let mut computed=None;
 for turn in 0..2{source_arena::with_held_pattern_work(&db,&mut ledger,&budget,|actual,scratch|{
  let provider=crate::query_db::PatternProvider::scoped(&db,actual,scratch);let mut work=Work{budget:&budget,patterns:&provider,peak:0};let mut rows=Vec::new();
  ownership::try_visit_file_events_funded(&file.rel,file.raw(),file.code(),&mut work,|event|{rows.push(event);Ok(())})?;assert_eq!(rows,expected);Ok(())
 }).unwrap();let now=db.db.stats(super::super::native_patterns::NATIVE_PATTERN).computed;if turn==0{assert!(now>=10);computed=Some(now)}else{assert_eq!(Some(now),computed)}}
}

#[test]
fn actual_native_annotation_query_matches_legacy_and_reuses_same_admitted_programs(){
 let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let db=QueryDb::default();let budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();let mut ledger=raw_input_credits::Ledger::default();let root=root();
 let text="/proc/p()\n\tsleep(1) // ALLOW(scheduler): the original blocking external operation\n";
 let file=File::capture_budgeted(&root,&root.join("code/annotation.dm"),text.into(),INPUT_BOUND).unwrap();let scope=Config::capture(Configuration::ProvenMissing).unwrap().scope("scheduler").unwrap();let expected=file.scan(&scope).unwrap();assert_eq!(expected.run.sites.len(),0);let mut computed=None;
 for turn in 0..2{source_arena::with_held_pattern_work(&db,&mut ledger,&budget,|work,scratch|{
  let provider=crate::query_db::PatternProvider::scoped(&db,work,scratch);let actual=file.scan_with_pattern_resources(&scope,10000,RESULT_BOUND,false,&budget,&provider,&crate::daemon::control::checkpoint).map_err(|error|match error{captured_raw_file::ScanFailure::Operational(actual)=>actual,other=>invalid(other.into_message())})?;
  assert_eq!(actual.fingerprint(),expected.fingerprint());assert_eq!(actual.allow_used.len(),1);Ok(())
 }).unwrap();let now=db.db.stats(super::super::native_patterns::NATIVE_PATTERN).computed;if turn==0{assert!(now>0);computed=Some(now)}else{assert_eq!(Some(now),computed)}}
}

#[test]
fn actual_native_dispatcher_preparation_uses_same_db_programs_and_rejects_real_bad_pattern_then_recovers(){
 let _binding=crate::daemon::control::bind_with_deadline(Default::default(),std::time::Instant::now()+std::time::Duration::from_secs(120));
 let db=QueryDb::default();let budget=dq_analyze::captured_generator_budget::Budget::new(64*1024*1024).unwrap();let mut ledger=raw_input_credits::Ledger::default();let text=dq_analyze::ui_selftest_policy::DISPATCHER_FIXTURE;
 let expected=dq_analyze::ui_actions_policy::prepare_dispatcher(Some(text),&budget,&crate::daemon::control::checkpoint).unwrap();assert!(expected.needs_sources());let mut computed=None;
 for turn in 0..2{source_arena::with_held_pattern_work(&db,&mut ledger,&budget,|work,scratch|{
  let provider=crate::query_db::PatternProvider::scoped(&db,work,scratch);let actual=dq_analyze::ui_actions_policy::prepare_dispatcher_with_patterns(Some(text),&budget,&crate::daemon::control::checkpoint,&provider).map_err(|failure|match failure{dq_analyze::captured_reactive_reads::Failure::Operational(actual)=>actual,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>invalid(message)})?;
  assert_eq!(actual.needs_sources(),expected.needs_sources());assert_eq!(actual.first_source_line(),expected.first_source_line());Ok(())
 }).unwrap();let now=db.db.stats(super::super::native_patterns::NATIVE_PATTERN).computed;if turn==0{assert!(now>=9);computed=Some(now)}else{assert_eq!(Some(now),computed)}}
 let broken=text.replace("^[A-Za-z0-9_-]+$","(");assert_ne!(broken,text);
 source_arena::with_held_pattern_work(&db,&mut ledger,&budget,|work,scratch|{
  let provider=crate::query_db::PatternProvider::scoped(&db,work,scratch);assert!(matches!(dq_analyze::ui_actions_policy::prepare_dispatcher_with_patterns(Some(&broken),&budget,&crate::daemon::control::checkpoint,&provider),Err(dq_analyze::captured_reactive_reads::Failure::Unsupported(_))));
  assert!(dq_analyze::ui_actions_policy::prepare_dispatcher_with_patterns(Some(text),&budget,&crate::daemon::control::checkpoint,&provider).map_err(|_|invalid("actual good dispatcher must recover after real syntax refusal"))?.needs_sources());Ok(())
 }).unwrap();
}
