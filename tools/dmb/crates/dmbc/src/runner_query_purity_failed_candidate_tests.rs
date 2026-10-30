//! A failed candidate has REALLY revised the compiler Db, while the previously
//! admitted SourceSnapshot remains published. Never mix those two source owners.
use super::*;
#[test]
fn failed_candidate_new_changed_and_removed_program_inputs_refuse_old_cached_purity_before_read() {
    for mode in ["changed", "added", "removed"] {
        let source = include_str!("../../../fixtures/unified_checks/purity/parameter/probe.dme");
        let (snapshot, _) = fixture(source, None);
        let db = snapshot.native_raw_queries.as_ref().unwrap().clone();
        let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
        snapshot
            .native_purity_report(&input, &env(), None, &snapshot.tree)
            .unwrap();
        let before = (17..=21)
            .map(|k| db.db().stats(dm_query::Kind(k)).computed)
            .collect::<Vec<_>>();
        let old_owner = dm_ir::Resolver::source_owner(snapshot.tree.as_ref());
        let old_revision = snapshot.source_revision;
        let state = Arc::new(Mutex::new(
            crate::runner_host::query_snapshot::QueryState::default(),
        ));
        state.lock().unwrap().snapshot = Some(snapshot);
        let attempt =
            crate::runner_host::query_snapshot::QueryAttempt::new(Arc::clone(&state), true);
        let candidate_env = if mode == "removed" {
            env().with_file_name("candidate.dme")
        } else {
            env()
        };
        let mut files = BTreeMap::from([(candidate_env.clone(), b"/proc/malformed(\n".to_vec())]);
        if mode == "added" {
            files.insert(
                env().with_file_name("added.dm"),
                b"/datum/candidate_extra\n".to_vec(),
            );
        }
        let paths = files.keys().cloned().collect::<Vec<_>>();
        let inputs = RecordingInputs::new(
            Memory {
                files: Arc::new(files),
                reads: Arc::new(AtomicUsize::new(0)),
            },
            2,
        )
        .with_prepared_sources(Some(Arc::new(Default::default())));
        let originals = paths
            .iter()
            .map(|path| {
                (
                    path.clone(),
                    dm_preprocess::SourceProvider::prepared_source(&inputs, path).unwrap(),
                )
            })
            .collect::<Vec<_>>();
        let prepared =
            dm_preprocess::regions::prepared_source::PreparedSources::from_prepared(originals)
                .unwrap();
        let revision = db.revise(&prepared, 456).unwrap();
        assert!(revision.changed > 0 || revision.removed > 0);
        // Real original compiler builder fails before staging a candidate policy.
        // Its already-prepared input keys/owners nevertheless changed the SAME Db.
        let mut host = crate::runner_host::BuildHost::one_shot();
        let engine = host
            .engine(
                candidate_env.clone(),
                Default::default(),
                true,
                include_bytes!("../../../fixtures/native_template.bin").to_vec(),
            )
            .unwrap();
        let executor = dm_exec::BuildExecutor::new(1).unwrap();
        let candidate = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
            &candidate_env,
            &inputs,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(engine.frontend_seed()),
                observer: None,
            },
            None,
            &executor,
            None,
            true,
        );
        assert!(
            candidate.is_err(),
            "malformed original candidate must not be published"
        );
        drop(attempt);
        let current = state.lock().unwrap();
        let old = current
            .snapshot
            .as_ref()
            .expect("failed preparation preserves previous admitted source frame");
        assert_eq!(old.source_revision, old_revision);
        assert_eq!(dm_ir::Resolver::source_owner(old.tree.as_ref()), old_owner);
        let error = old
            .native_purity_report(&input, &env(), None, &old.tree)
            .unwrap_err();
        assert!(
            error.to_string().contains("roster") || error.to_string().contains("owner"),
            "{mode}: {error}"
        );
        assert_eq!(
            before,
            (17..=21)
                .map(|k| db.db().stats(dm_query::Kind(k)).computed)
                .collect::<Vec<_>>(),
            "{mode}: refuse before every cached effect/resolver result access"
        );
    }
}
