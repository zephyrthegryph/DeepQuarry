//! Native policies over the original captured owner and the same compiler Db.
//! Explicit fixture admission, without workspace discovery or baseline mutation.
use super::*;
use dq_analyze::{
    captured_base_vars_policy::BorrowedBaseVarsPolicy, captured_decl_policy::BorrowedDeclPolicy,
    captured_generator_budget::Budget, captured_init_policy::BorrowedInitPolicy,
    captured_player_link::BorrowedPlayerLink, captured_pool::BorrowedPool,
    captured_raw_policy::CapturedRawPolicy, captured_rel_write::BorrowedRelWrite,
    captured_requirement_bool::BorrowedRequirementBool, captured_stored_refs::BorrowedStoredRefs,
    captured_untyped::BorrowedUntyped, captured_untyped_member::BorrowedUntypedMember,
    captured_weak_raw_read::BorrowedWeakRawRead,
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
    value_input: Option<Weak<dm_analysis::value_query::ArchiveValueInput>>,
}
// Operation-local error split only: never stored in Outcome/Params.
enum AnalyzeReadFailure {
    Semantic(String),
    Query(QueryError),
    Operational(std::io::Error),
}
impl From<String> for AnalyzeReadFailure {
    fn from(e: String) -> Self {
        Self::Semantic(e)
    }
}
impl From<&str> for AnalyzeReadFailure {
    fn from(e: &str) -> Self {
        Self::Semantic(e.into())
    }
}
impl From<dm_analysis::value_query::ValueQueryFailure> for AnalyzeReadFailure {
    fn from(error: dm_analysis::value_query::ValueQueryFailure) -> Self {
        match error {
            dm_analysis::value_query::ValueQueryFailure::Unsupported(e) => Self::Semantic(e.0),
            dm_analysis::value_query::ValueQueryFailure::Syntax(e) => Self::Semantic(e.message),
            dm_analysis::value_query::ValueQueryFailure::Operational(e) => Self::Operational(e),
        }
    }
}
impl From<dm_analysis::policy_body_demand::PolicyFailure> for AnalyzeReadFailure {
    fn from(error: dm_analysis::policy_body_demand::PolicyFailure) -> Self {
        match error {
            dm_analysis::policy_body_demand::PolicyFailure::Unsupported(error) => {
                Self::Semantic(error.0)
            }
            dm_analysis::policy_body_demand::PolicyFailure::Operational(error) => {
                Self::Operational(error)
            }
        }
    }
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
pub(super) fn register_analyze(db: &Db, charge: Arc<AtomicUsize>, admission: Arc<Admission>) {
    db.define(
        ANALYZE_FINDINGS,
        "native-analyze-cross-file-policy",
        move |ctx, params| {
            let p = params
                .downcast_ref::<Params>()
                .expect("typed policy params");
            admission.abort.before_outcome(p.result)?;
            // Issuance is checked on BOTH a cache hit at entry and actual execution.
            let capture = p.capture.upgrade().ok_or(QueryError::Missing(p.result))?;
            let evidence = capture.semantic_source_evidence();
            let evidence_admission = if evidence.key() != p.evidence_key {
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
            let mut pool_budget = None;
            let result = (|| -> Result<Vec<RawRun>, AnalyzeReadFailure> {
                evidence_admission?;
                config
                    .require_original(
                        capture
                            .configuration_bytes(&p.configuration_path)
                            .map_err(|e| e.to_string())?,
                    )
                    .map_err(|e| e.to_string())?;
                admission.abort.scan_checkpoint()?;
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
                    let checkpoint = || admission.abort.scan_checkpoint();
                    let run = match name.as_str() {
                        "pool" => {
                            // Joint remaining result-family admission includes all
                            // cached outcomes AND prior runs still under construction.
                            let prior = runs
                                .iter()
                                .try_fold(4096usize, |n: usize, run: &RawRun| {
                                    n.checked_add(Findings::budget_charge_parts(
                                        &run.name,
                                        &run.run,
                                        &run.allow_used,
                                    ))
                                })
                                .ok_or("pool prior result accounting overflow")?;
                            let remaining = admission
                                .limit
                                .load(Ordering::Relaxed)
                                .saturating_sub(charge.load(Ordering::Relaxed))
                                .saturating_sub(prior);
                            let budget = Budget::new(remaining).map_err(|e| {
                                admission.denied.store(true, Ordering::Relaxed);
                                e
                            })?;
                            pool_budget = Some(budget.clone());
                            BorrowedPool::capture(&raw, capture.policy())?.scan(
                                budget,
                                MAX_FIXTURE_SITES - sites,
                                checkpoint,
                            )?
                        }
                        "init" => {
                            BorrowedInitPolicy::capture(&raw, capture.policy())?.scan(checkpoint)?
                        }
                        "decl" => {
                            BorrowedDeclPolicy::capture(&raw, capture.policy())?.scan(checkpoint)?
                        }
                        "base_vars" => BorrowedBaseVarsPolicy::capture(&raw, capture.policy())?
                            .scan(checkpoint)?,
                        "requirement_bool" => {
                            BorrowedRequirementBool::capture(&raw, capture.policy())?
                                .scan_checked(checkpoint)?
                        }
                        "untyped_member" => BorrowedUntypedMember::capture(&raw, capture.policy())?
                            .scan_checked(checkpoint)?,
                        "stored_refs" => BorrowedStoredRefs::capture(&raw, capture.policy())?
                            .scan_checked(checkpoint)?,
                        "rel_write_undeclared" => {
                            BorrowedRelWrite::capture(&raw, capture.policy())?
                                .scan_checked(checkpoint)?
                        }
                        "weak_raw_read" => BorrowedWeakRawRead::capture(&raw, capture.policy())?
                            .scan_checked(checkpoint)?,
                        "untyped" => {
                            let input = p
                                .value_input
                                .as_ref()
                                .and_then(Weak::upgrade)
                                .ok_or("untyped input issuance is no longer current")?;
                            if !Arc::ptr_eq(input.archive(), capture.policy().archive()) {
                                return Err("untyped archive issuance differs".into());
                            }
                            let manifest = capture
                                .untyped_manifest(&p.root)
                                .map_err(|e| e.to_string())?;
                            let proof = super::super::value_proofs::observe(ctx, &input)
                                .map_err(AnalyzeReadFailure::Query)??;
                            BorrowedUntyped::capture(&raw, capture.policy())?
                                .scan_checked(
                                    &input,
                                    proof,
                                    manifest,
                                    crate::daemon::control::checkpoint,
                                )
                                .map_err(AnalyzeReadFailure::from)?
                        }
                        "player_link" => {
                            BorrowedPlayerLink::capture(&raw, capture.policy())?.scan_checked(checkpoint)
                                .map_err(|error|match error {
                                    dm_analysis::policy_body_demand::PolicyFailure::Unsupported(error)=>AnalyzeReadFailure::Semantic(error.0),
                                    dm_analysis::policy_body_demand::PolicyFailure::Operational(error)=>AnalyzeReadFailure::Operational(error),
                                })?
                        }
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
                if let Some(budget) = pool_budget.as_ref() {
                    // Two wrappers per original file, each currently visits at
                    // most17 source/view/record keys;64 covers both plus slack.
                    //256/key+4096 bounds original BTree census coordination,
                    // admitted BEFORE any map nodes, not hidden outside quota.
                    budget.charge(
                        sources
                            .len()
                            .checked_mul(64 * 256)
                            .and_then(|n| n.checked_add(4096))
                            .ok_or("pool shared-view census temporary overflow")?,
                    )?;
                }
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
                admission.abort.scan_checkpoint()?;
                Ok(runs)
            })();
            let result = match result {
                Ok(value) => Ok(value),
                Err(AnalyzeReadFailure::Semantic(message)) => Err(message),
                Err(AnalyzeReadFailure::Query(error)) => return Err(error),
                Err(AnalyzeReadFailure::Operational(error)) => {
                    return Err(QueryError::operational(p.result, error))
                }
            };
            if p.ordered.iter().any(|name| name == "pool") {
                let view_denied = sources
                    .iter()
                    .any(|source| source.file.require_view_budget().is_err());
                if view_denied {
                    admission.view_denied.store(true, Ordering::Relaxed);
                    admission.denied.store(true, Ordering::Relaxed);
                }
                admission.abort.before_outcome(p.result)?;
                if view_denied
                    || admission.denied.load(Ordering::Relaxed)
                    || pool_budget
                        .as_ref()
                        .is_some_and(|budget: &Arc<Budget>| budget.denied())
                {
                    admission.denied.store(true, Ordering::Relaxed);
                    return Err(QueryError::Missing(p.result));
                }
            }
            let (hash, bytes) = match &result {
                Ok(runs) => {
                    let mut fingerprint = Vec::new();
                    let mut bytes = 0usize;
                    for run in runs {
                        fingerprint.extend_from_slice(
                            &Findings::fingerprint_parts(&run.name, &run.run, &run.allow_used)
                                .to_le_bytes(),
                        );
                        bytes = bytes.saturating_add(Findings::budget_charge_parts(
                            &run.name,
                            &run.run,
                            &run.allow_used,
                        ));
                    }
                    (dm_query::hash_bytes(&fingerprint), bytes)
                }
                Err(error) => (error_hash(error), result_error_charge::<Vec<RawRun>>(error)),
            };
            retain_derived(&charge, bytes, &admission, p.result)?;
            admission.abort.before_outcome(p.result)?;
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
        if names.iter().any(|name| name == "pool") {
            return Err(invalid(
                "pool findings require the bounded borrowed result callback",
            ));
        }
        self.with_analyze_fixture_findings(cohort, names, |rows| {
            let runs = rows
                .iter()
                .map(|row| RawRun {
                    name: row.name.clone(),
                    run: row.run.clone(),
                    allow_used: row.allow_used.clone(),
                })
                .collect();
            Ok(Results {
                input: Arc::downgrade(cohort),
                runs,
            })
        })
    }
    /// Callback executes under SAME existing family gate. Do not re-enter this
    /// family's query API, retain payload clones or manufacture output owners.
    pub(crate) fn with_analyze_fixture_findings<T>(
        &self,
        cohort: &Arc<Cohort>,
        names: &[String],
        consume: impl FnOnce(&[RawRun]) -> io::Result<T>,
    ) -> io::Result<T> {
        self.with_analyze_fixture_findings_limit(cohort, names, None, consume)
    }
    /// Reserve the complete outer query buffer plus bounded report metadata
    /// while SAME family gate pins the borrowed findings. No result clone or
    /// independently owned JSON tree may be built by this callback.
    pub(crate) fn with_analyze_fixture_output<T>(
        &self,
        cohort: &Arc<Cohort>,
        names: &[String],
        reserve: usize,
        consume: impl FnOnce(&[RawRun]) -> io::Result<T>,
    ) -> io::Result<T> {
        let limit = RESULT_BUDGET
            .checked_sub(reserve)
            .ok_or_else(|| invalid("typed policy output reservation exceeds shared admission"))?;
        self.with_analyze_fixture_findings_limit(cohort, names, Some(limit), |runs| {
            // Also cover an already-cached result: compute's admission limit is
            // not revisited on a cache hit. All backing output remains inside
            // this non-reentrant callback and the family's existing gate.
            if self.raw_policy.charge.load(Ordering::Relaxed) > limit {
                return Err(invalid(
                    "typed policy output exceeds shared retained admission",
                ));
            }
            consume(runs)
        })
    }
    fn with_analyze_fixture_findings_limit<T>(
        &self,
        cohort: &Arc<Cohort>,
        names: &[String],
        limit: Option<usize>,
        consume: impl FnOnce(&[RawRun]) -> io::Result<T>,
    ) -> io::Result<T> {
        crate::daemon::control::checkpoint()?;
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
        let prepared = match self.raw_prepare_locked(cohort, &[], now) {
            Ok(v) => v,
            Err(e) => {
                if ordered.iter().any(|name| name == "pool") {
                    self.discard_poisoned_generator_files_locked(cohort);
                }
                return Err(e);
            }
        };
        let value_input = if ordered.iter().any(|name| name == "untyped") {
            // Manifest role/original/absence authority checked BEFORE cache lookup.
            cohort.capture.untyped_manifest(&cohort.root)?;
            let config = self
                .db
                .input::<ConfigData>(prepared.configuration)
                .ok_or_else(|| invalid("prepared config absent"))?;
            let exemptions = config
                .config
                .typed_policy_list("untyped", "exempt_types")
                .map_err(io::Error::other)?;
            let input = cohort.capture.untyped_input(&exemptions)?;
            self.prepare_value_input(&input)
                .map_err(|e| io::Error::other(e.0))?;
            Some(input)
        } else {
            None
        };
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
        self.begin_result_admission_locked()?;
        if let Some(limit) = limit {
            self.raw_policy
                .admission
                .limit
                .fetch_min(limit, Ordering::Relaxed);
        }
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
                    value_input: value_input.as_ref().map(Arc::downgrade),
                }),
            )
            .map_err(|error| self.derived_query_error("native typed policy query", error));
        let result = match result {
            Ok(v) => v,
            Err(e) => {
                if names.iter().any(|name| name == "pool") {
                    if self
                        .raw_policy
                        .admission
                        .view_denied
                        .load(Ordering::Relaxed)
                    {
                        self.discard_poisoned_generator_files_locked(cohort);
                    }
                    if self.raw_policy.admission.denied.load(Ordering::Relaxed) {
                        let bytes = self.db.value_bytes_at(result_key);
                        self.db.remove(result_key);
                        self.raw_policy
                            .leases
                            .lock()
                            .unwrap_or_else(|e| e.into_inner())
                            .remove(&result_key);
                        self.raw_policy
                            .charge
                            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| {
                                Some(n.saturating_sub(bytes))
                            })
                            .ok();
                    }
                }
                return Err(e);
            }
        };
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
        crate::daemon::control::checkpoint()?;
        let output = consume(rows)?;
        crate::daemon::control::checkpoint()?;
        Ok(output)
    }
}

#[cfg(test)]
mod extended_roster_tests {
    use super::*;
    #[test]
    fn original_three_order_is_preserved_and_complete_extended_roster_is_canonical() {
        let old = ["base_vars", "decl", "init"].map(str::to_owned);
        assert_eq!(ordered_names(&old).unwrap(), ["init", "decl", "base_vars"]);
        let all = [
            "player_link",
            "untyped_member",
            "base_vars",
            "requirement_bool",
            "init",
            "decl",
        ]
        .map(str::to_owned);
        assert_eq!(
            ordered_names(&all).unwrap(),
            [
                "init",
                "decl",
                "base_vars",
                "requirement_bool",
                "untyped_member",
                "player_link"
            ]
        );
        assert!(ordered_names(&["rel_write_undeclared".to_owned()]).is_ok());
        assert!(ordered_names(&["pool".to_owned()]).is_ok());
        assert!(
            ordered_names(&["untyped".to_owned()]).is_ok(),
            "full untyped uses host manifest and same-Db value proof admission"
        );
        assert!(
            ordered_names(&["requirement_bool".to_owned(), "requirement_bool".to_owned()]).is_err()
        );
    }
}

#[cfg(test)]
#[path = "analyze_policy_operation_tests.rs"]
mod operation_tests;

#[cfg(test)]
#[path = "analyze_policy_untyped_tests.rs"]
mod untyped_tests;

#[cfg(test)]
#[path = "analyze_policy_rel_write_tests.rs"]
mod rel_write_tests;

#[cfg(test)]
#[path = "analyze_policy_pool_tests.rs"]
mod pool_tests;
