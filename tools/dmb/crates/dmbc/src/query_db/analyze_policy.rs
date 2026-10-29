//! Native policies over the original captured owner and the same compiler Db.
//! Explicit fixture admission, without workspace discovery or baseline mutation.
use super::*;
use dq_analyze::{
    captured_base_vars_policy::BorrowedBaseVarsPolicy, captured_decl_policy::BorrowedDeclPolicy,
    captured_init_policy::BorrowedInitPolicy, captured_raw_policy::CapturedRawPolicy,
};
pub(super) const ANALYZE_FINDINGS: Kind = Kind(10);
pub(crate) const ANALYZE_FIXTURE_LINTS: &[&str] = dq_analyze::captured_policy_metadata::LINTS;
#[derive(Clone)]
struct Params {
    capture: Weak<CapturedPolicyInputs>,
    evidence_key: u64,
    configuration: Key,
    configuration_path: PathBuf,
    files: Vec<Key>,
    root: PathBuf,
    ordered: Vec<String>,
    result: Key,
}
struct Runs {
    runs: Vec<RawRun>,
}
fn ordered_names(names: &[String]) -> io::Result<Vec<String>> {
    if names.is_empty()
        || names.len() > ANALYZE_FIXTURE_LINTS.len()
        || names
            .iter()
            .any(|name| !ANALYZE_FIXTURE_LINTS.contains(&name.as_str()))
        || names.iter().collect::<BTreeSet<_>>().len() != names.len()
    {
        return Err(invalid(
            "typed policy requires unique explicit admitted names",
        ));
    }
    Ok(ANALYZE_FIXTURE_LINTS
        .iter()
        .filter(|name| names.iter().any(|n| n == **name))
        .map(|name| name.to_string())
        .collect())
}
pub(super) fn register_analyze(db: &Db, charge: Arc<AtomicUsize>) {
    db.define(
        ANALYZE_FINDINGS,
        "native-analyze-cross-file-policy",
        move |ctx, params| {
            let p = params
                .downcast_ref::<Params>()
                .expect("typed policy params");
            // Issuance is checked on BOTH a cache hit at entry and actual execution.
            let capture = p.capture.upgrade().ok_or(QueryError::Missing(p.result))?;
            let evidence = capture.semantic_source_evidence();
            let admission = if evidence.key() != p.evidence_key {
                Err("semantic evidence issuance changed".to_string())
            } else {
                evidence
                    .check(capture.policy().mapping())
                    .map_err(|e| e.to_string())
            };
            // Always establish existing shared RAW_FILE/CONFIG dependencies before
            // execution; there is no second parser/model or side-map of payloads.
            let config = ctx.input::<ConfigData>(p.configuration)?;
            let sources = p
                .files
                .iter()
                .map(|key| ctx.input::<FileData>(*key))
                .collect::<Result<Vec<_>, _>>()?;
            let result = (|| -> Result<Vec<RawRun>, String> {
                admission?;
                config
                    .require_original(
                        capture
                            .configuration_bytes(&p.configuration_path)
                            .map_err(|e| e.to_string())?,
                    )
                    .map_err(|e| e.to_string())?;
                crate::daemon::control::checkpoint().map_err(|e| e.to_string())?;
                let files = sources
                    .iter()
                    .map(|source| Arc::clone(&source.file))
                    .collect::<Vec<_>>();
                let raw = CapturedRawPolicy::from_shared_files(
                    &p.root,
                    capture.policy(),
                    &config.config,
                    &files,
                )?;
                let mut runs = Vec::new();
                let mut sites = 0usize;
                for name in &p.ordered {
                    let checkpoint =
                        || crate::daemon::control::checkpoint().map_err(|e| e.to_string());
                    let run =
                        match name.as_str() {
                            "init" => BorrowedInitPolicy::capture(&raw, capture.policy())?
                                .scan(checkpoint)?,
                            "decl" => BorrowedDeclPolicy::capture(&raw, capture.policy())?
                                .scan(checkpoint)?,
                            "base_vars" => BorrowedBaseVarsPolicy::capture(&raw, capture.policy())?
                                .scan(checkpoint)?,
                            _ => return Err("typed policy whitelist differs".into()),
                        };
                    sites = sites
                        .checked_add(run.run.sites.len())
                        .filter(|n| *n <= MAX_FIXTURE_SITES)
                        .ok_or("typed fixture exceeds finding admission")?;
                    runs.push(run);
                }
                // Census ACTUAL currently retained code/clean/marker capacities,
                // pointer-deduplicated across source and transient wrapper owners.
                // No claim of allocator/RSS cap. Shared raw source arena is charged
                // by native capture's existing <=64MiB retained budget separately.
                let mut storage = BTreeMap::new();
                for source in &sources {
                    source.file.visit_policy_storage(|id, bytes| {
                        storage
                            .entry(id)
                            .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                            .or_insert(bytes);
                    });
                }
                raw.visit_policy_storage(|id, bytes| {
                    storage
                        .entry(id)
                        .and_modify(|old| *old = (*old).max(bytes))
                        .or_insert(bytes);
                });
                let actual = storage
                    .values()
                    .try_fold(0usize, |a, b| a.checked_add(*b))
                    .ok_or("typed storage census overflow")?;
                if actual > INPUT_BUDGET {
                    return Err("typed source views exceed retained view admission".into());
                }
                crate::daemon::control::checkpoint().map_err(|e| e.to_string())?;
                Ok(runs)
            })();
            let (hash, bytes) = match &result {
                Ok(runs) => {
                    let mut fingerprint = Vec::new();
                    let mut bytes = 0usize;
                    for run in runs {
                        let rows = Findings {
                            name: run.name.clone(),
                            run: run.run.clone(),
                            allow_used: run.allow_used.clone(),
                        };
                        fingerprint.extend_from_slice(&rows.fingerprint().to_le_bytes());
                        bytes = bytes.saturating_add(rows.budget_charge());
                    }
                    (dm_query::hash_bytes(&fingerprint), bytes)
                }
                Err(error) => (error_hash(error), 1024),
            };
            charge.fetch_add(bytes, Ordering::Relaxed);
            Ok(Outcome::new(result, hash, bytes))
        },
    );
}
impl QueryDb {
    pub(crate) fn analyze_fixture_findings(
        &self,
        cohort: &Arc<Cohort>,
        names: &[String],
    ) -> io::Result<Results> {
        if cohort.issuer != self.id || !cohort.capture.policy().archive().uses_body_queries(self) {
            return Err(invalid("foreign typed cohort"));
        }
        let evidence = cohort.capture.semantic_source_evidence();
        evidence.check(cohort.capture.policy().mapping())?; // BEFORE ANY CACHE LOOKUP
        let ordered = ordered_names(names)?;
        let _gate = self
            .raw_policy
            .gate
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let now = Instant::now();
        self.raw_prune_locked(now);
        // An empty raw-lint list requests no
        // raw findings/scope nodes, only the existing file/config nodes.
        let prepared = self.raw_prepare_locked(cohort, &[], now)?;
        let result_key = key(
            ANALYZE_FINDINGS,
            &(
                self.id,
                evidence.key(),
                cohort.capture.policy_revision(),
                &cohort.root,
                &cohort.configuration,
                &ordered,
            ),
        );
        let planned = BTreeMap::from([(result_key, 1024)]);
        self.raw_admit_locked(cohort, &planned, now)?;
        let result = self
            .db
            .get::<Result<Vec<RawRun>, String>>(
                result_key,
                Arc::new(Params {
                    capture: Arc::downgrade(&cohort.capture),
                    evidence_key: evidence.key(),
                    configuration: prepared.configuration,
                    configuration_path: cohort.configuration.clone(),
                    files: prepared.sources.iter().map(|(key, _, _)| *key).collect(),
                    root: cohort.root.clone(),
                    ordered,
                    result: result_key,
                }),
            )
            .map_err(|error| io::Error::other(format!("native typed policy query: {error:?}")))?;
        if self.raw_retained_view_bytes_locked()? > INPUT_BUDGET
            || self.raw_policy.charge.load(Ordering::Relaxed) > RESULT_BUDGET
        {
            self.raw_clear_locked();
            return Err(invalid(
                "typed policy retained storage exceeds admission; complete result discarded",
            ));
        }
        let rows = result
            .as_ref()
            .as_ref()
            .map_err(|error| io::Error::other(error.clone()))?;
        // Nothing is serialized until complete success; clone compact findings
        // only, never compiler or raw-source models. Drop transient owners here.
        let runs = rows
            .iter()
            .map(|row| RawRun {
                name: row.name.clone(),
                run: row.run.clone(),
                allow_used: row.allow_used.clone(),
            })
            .collect();
        crate::daemon::control::checkpoint()?;
        Ok(Results {
            input: Arc::downgrade(cohort),
            runs,
        })
    }
}
