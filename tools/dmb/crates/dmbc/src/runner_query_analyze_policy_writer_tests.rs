use super::*;
use crate::input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp};
use crate::policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole};
use crate::runner_host::policy_capture;
use std::{collections::BTreeMap, path::PathBuf, sync::Mutex};
#[derive(Clone)]
struct Memory(BTreeMap<PathBuf, Vec<u8>>);
impl SnapshotProvider for Memory {
    fn stamp(&self, path: &Path) -> io::Result<Stamp> {
        let b = self
            .0
            .get(&dm_preprocess::regions::canonical_path(path))
            .ok_or(io::ErrorKind::NotFound)?;
        Ok(Stamp {
            size: b.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, path: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        Ok((
            self.stamp(path)?,
            self.0[&dm_preprocess::regions::canonical_path(path)].clone(),
        ))
    }
    fn list(&self, path: &Path) -> io::Result<FolderListing> {
        Ok(FolderListing::Present(
            self.0
                .keys()
                .filter(|p| p.parent() == Some(path))
                .filter_map(|p| p.file_name().map(|n| n.to_string_lossy().into_owned()))
                .collect(),
        ))
    }
}
fn root() -> PathBuf {
    std::env::current_dir()
        .unwrap()
        .join("borrowed-pool-writer-provider")
}
fn snapshot(checker: Option<&[u8]>) -> SourceSnapshot {
    snapshot_with_scopes(
        checker,
        b"[lint.base_vars.lists]\nrecord_accessor_prefixes=['get_']\n",
    )
}
fn snapshot_with_scopes(checker: Option<&[u8]>, scopes: &[u8]) -> SourceSnapshot {
    let root = root();
    let mut files=BTreeMap::from([
        (root.join("project.dme"),b"#include \"code/compiled.dm\"\n".to_vec()),
        (root.join("code/compiled.dm"),b"/datum/probe\n#if 0\nPOOL_DECLARE(/datum/pooled_probe)\n/proc/run()\n\tvar/value = new /datum/pooled_probe\n#endif\n".to_vec()),
        (root.join("scopes.toml"), scopes.to_vec()),
    ]);
    if let Some(checker) = checker {
        files.insert(root.join("SpacemanDMM.toml"), checker.to_vec());
    }
    let inputs = RecordingInputs::new(Memory(files), 1);
    let db = Arc::new(crate::query_db::QueryDb::default());
    let frontend =
        dm_tree::frontend::build(&root.join("project.dme"), &inputs, &Default::default(), 1)
            .unwrap()
            .with_body_queries(db.clone());
    let intent = PolicyInputRequest {workspace_generators:Vec::new(),
        workspace: None,
        files: vec![
            PolicyInputFile {
                path: root.join("scopes.toml"),
                role: PolicyInputRole::Configuration,
                required: true,
            },
            PolicyInputFile {
                path: root.join("SpacemanDMM.toml"),
                role: PolicyInputRole::Configuration,
                required: false,
            },
        ],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let captured = Arc::new(
        policy_capture::capture(&frontend, &inputs, &intent.capture_files(), &[])
            .unwrap()
            .bind_request(&intent)
            .unwrap(),
    );
    let state = Arc::new(Mutex::new(
        crate::runner_host::query_snapshot::QueryState::default(),
    ));
    let mut attempt = crate::runner_host::query_snapshot::QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_queries(&frontend, db, Some(captured))
        .unwrap();
    let snapshot = state.lock().unwrap().snapshot.take().unwrap();
    snapshot
}

fn render(snapshot: &SourceSnapshot, lints: &[String]) -> io::Result<Vec<u8>> {
    let mut out = Vec::new();
    snapshot.write_native_analyze_policy_fixture(
        &root(),
        &root().join("scopes.toml"),
        lints,
        &snapshot.tree,
        &mut out,
    )?;
    Ok(out)
}
#[test]
fn borrowed_public_pool_preserves_exact_fixture_envelope_and_warm_bytes() {
    let snapshot = snapshot_with_scopes(None, b"");
    let names = vec!["pool".to_owned()];
    let bytes = render(&snapshot, &names).unwrap();
    let row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(row["scope"], "explicit_captured_files");
    assert_eq!(row["full_policy_parity"], false);
    assert_eq!(row["baseline_applied"], false);
    assert_eq!(row["admission"], "native_semantic_findings");
    assert_eq!(row["results"][0]["name"], "pool");
    assert_eq!(row["results"][0]["sites"].as_array().unwrap().len(), 1);
    assert_eq!(row["results"][0]["sites"][0]["rule"], "new_pooled");
    assert_eq!(row["results"][0]["sites"][0]["line"], 5);
    assert_eq!(
        row["results"][0]["notes"],
        serde_json::json!(["pool_lint: 1 problem(s)"])
    );
    // The old Value-backed serializer sorted every map lexically. Exact bytes,
    // including nested Sites/Allows, are unchanged; no Value is used in production.
    assert_eq!(
        bytes,
        [serde_json::to_vec(&row).unwrap(), b"\n".to_vec()].concat()
    );
    assert_eq!(bytes, render(&snapshot, &names).unwrap());
    let ordinary = render(&snapshot, &["decl".into(), "init".into()]).unwrap();
    let ordinary: serde_json::Value = serde_json::from_slice(&ordinary).unwrap();
    assert_eq!(ordinary["results"][0]["name"], "init");
    assert_eq!(ordinary["results"][1]["name"], "decl");
}
#[test]
fn borrowed_public_output_denial_writes_nothing_then_same_owner_succeeds() {
    let snapshot = snapshot_with_scopes(None, b"");
    let config = root().join("scopes.toml");
    let q = snapshot.native_raw_queries.as_ref().unwrap();
    let capture = snapshot.native_policy_inputs.as_ref().unwrap();
    let cohort = q.raw_cohort(capture.clone(), &root(), &config).unwrap();
    let names = vec!["pool".into()];
    q.with_analyze_fixture_findings(&cohort, &names, |runs| {
        let report = Report {
            snapshot: &snapshot,
            tree: &snapshot.tree,
            root: &root(),
            configuration: &config,
            lints: &names,
            pin: snapshot.policy_revision.unwrap(),
            configuration_present: true,
            runs,
        };
        let mut out = Vec::new();
        let error = write_report(&report, &mut out, 32).unwrap_err();
        assert!(error.to_string().contains("bounded query output"));
        assert!(out.is_empty());
        let mut sufficient = Vec::new();
        write_report(&report, &mut sufficient, crate::daemon::query::MAX_OUTPUT).unwrap();
        assert!(!sufficient.is_empty());
        Ok(())
    })
    .unwrap();
    assert!(!render(&snapshot, &names).unwrap().is_empty());
}
#[test]
fn borrowed_nested_serialization_matches_original_value_order_and_bytes() {
    let run = RawRun {
        name: "pool".into(),
        run: dq_analyze::lint::Run {
            sites: vec![dq_analyze::lint::Site {
                rule: "new_pooled".into(),
                rel: "code/a.dm".into(),
                line: 7,
                msg: "quotes \" and \n Unicode é".into(),
                key: "k".into(),
                ident: "i".into(),
            }],
            notes: vec!["note".into()],
        },
        allow_used: vec![dq_analyze::lint::AllowUse {
            rel: "code/a.dm".into(),
            line: 3,
            name: "pool".into(),
            code: "why".into(),
        }],
    };
    let expected = serde_json::json!({"name":run.name,"sites":run.run.sites,"notes":run.run.notes,"allow_used":run.allow_used});
    assert_eq!(
        serde_json::to_vec(&Run(&run)).unwrap(),
        serde_json::to_vec(&expected).unwrap()
    );
}

#[test]
fn borrowed_count_cancellation_preserves_interrupted_and_same_findings_retry() {
    struct CancelDuringCount<'a> {
        report: &'a Report<'a>,
        token: crate::daemon::control::Cancellation,
        progress: &'a std::cell::Cell<bool>,
    }
    impl Serialize for CancelDuringCount<'_> {
        fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
            let mut m = s.serialize_map(Some(2))?;
            m.serialize_entry("prefix", "count has consumed actual bytes")?;
            self.progress.set(true);
            self.token.cancel();
            m.serialize_entry("report", self.report)?;
            m.end()
        }
    }
    let snapshot = snapshot_with_scopes(None, b"");
    let root = root();
    let config = root.join("scopes.toml");
    let q = snapshot.native_raw_queries.as_ref().unwrap();
    let capture = snapshot.native_policy_inputs.as_ref().unwrap();
    let cohort = q.raw_cohort(capture.clone(), &root, &config).unwrap();
    let names = vec!["pool".into()];
    let mut pointer = 0usize;
    q.with_analyze_fixture_findings(&cohort, &names, |runs| {
        pointer = runs.as_ptr() as usize;
        let report = Report {
            snapshot: &snapshot,
            tree: &snapshot.tree,
            root: &root,
            configuration: &config,
            lints: &names,
            pin: snapshot.policy_revision.unwrap(),
            configuration_present: true,
            runs,
        };
        let token = crate::daemon::control::Cancellation::default();
        let binding = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(60),
        );
        let progress = std::cell::Cell::new(false);
        let mut out = Vec::new();
        let error = write_report(
            &CancelDuringCount {
                report: &report,
                token: token.clone(),
                progress: &progress,
            },
            &mut out,
            crate::daemon::query::MAX_OUTPUT,
        )
        .unwrap_err();
        assert!(progress.get());
        assert!(token.is_cancelled());
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert!(out.is_empty());
        drop(binding);
        write_report(&report, &mut out, crate::daemon::query::MAX_OUTPUT)?;
        assert!(!out.is_empty());
        struct RefusingOutput;
        impl io::Write for RefusingOutput {
            fn write(&mut self, _: &[u8]) -> io::Result<usize> {
                Err(io::Error::new(
                    io::ErrorKind::OutOfMemory,
                    "test output refusal",
                ))
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let output_error = write_report(
            &report,
            &mut RefusingOutput,
            crate::daemon::query::MAX_OUTPUT,
        )
        .unwrap_err();
        assert_eq!(output_error.kind(), io::ErrorKind::OutOfMemory);
        Ok(())
    })
    .unwrap();
    q.with_analyze_fixture_findings(&cohort, &names, |runs| {
        assert_eq!(pointer, runs.as_ptr() as usize);
        Ok(())
    })
    .unwrap();
}

#[test]
fn report_emission_never_retries_interrupted_and_cancelled_partial_write_never_succeeds() {
    struct Refuse {
        calls: usize,
    }
    impl io::Write for Refuse {
        fn write(&mut self, _: &[u8]) -> io::Result<usize> {
            self.calls += 1;
            Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "actual report output interrupted",
            ))
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }
    let mut refuse = Refuse { calls: 0 };
    let error = write_report(&Limits, &mut refuse, 1024).unwrap_err();
    assert_eq!(refuse.calls, 1);
    assert_eq!(error.kind(), io::ErrorKind::Interrupted);
    assert_eq!(error.to_string(), "actual report output interrupted");
    struct Partial {
        token: crate::daemon::control::Cancellation,
        bytes: Vec<u8>,
        calls: usize,
    }
    impl io::Write for Partial {
        fn write(&mut self, b: &[u8]) -> io::Result<usize> {
            self.calls += 1;
            self.bytes.extend_from_slice(&b[..1]);
            self.token.cancel();
            Ok(1)
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }
    let token = crate::daemon::control::Cancellation::default();
    let bound = crate::daemon::control::bind_with_deadline(
        token.clone(),
        std::time::Instant::now() + std::time::Duration::from_secs(60),
    );
    let mut partial = Partial {
        token,
        bytes: Vec::new(),
        calls: 0,
    };
    let error = write_report(&Limits, &mut partial, 1024).unwrap_err();
    assert_eq!(error.kind(), io::ErrorKind::Interrupted);
    assert_eq!(partial.calls, 1);
    assert_eq!(partial.bytes.len(), 1);
    assert!(!partial.bytes.ends_with(b"\n"));
    drop(bound);
    let mut okay = Vec::new();
    write_report(&Limits, &mut okay, 1024).unwrap();
    assert!(okay.ends_with(b"\n"));
}
