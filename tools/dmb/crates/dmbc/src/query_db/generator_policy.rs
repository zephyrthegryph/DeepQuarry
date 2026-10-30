//! Explicit captured-source generators in the SAME native compiler Db.
//! No file installation, filesystem IO, public producer or workspace claim.
use super::*;
use dq_analyze::{
    captured_actions::BorrowedActions, captured_declare_ids::BorrowedDeclareIds,
    captured_generator_budget::Budget, captured_sparse_slots::BorrowedSparseSlots,
    captured_stats::BorrowedStats, captured_system_accessors::BorrowedSystemAccessors,
};
pub(super) const GENERATOR_RESULT: Kind = Kind(11);
#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize)]
pub(crate) enum GeneratorName {
    SparseSlots,
    SystemAccessors,
    Stats,
    Actions,
    DeclareIds,
}
impl GeneratorName {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Self::SparseSlots => "sparse_slots",
            Self::SystemAccessors => "system_accessors",
            Self::Stats => "stats",
            Self::Actions => "actions",
            Self::DeclareIds => "declare_ids",
        }
    }
    pub(crate) fn path(self) -> &'static str {
        match self {
            Self::SparseSlots => "code/engine/_generated/sparse_slots.dm",
            Self::SystemAccessors => "code/engine/_generated/system_accessors.dm",
            Self::Stats => "code/engine/_generated/stats.dm",
            Self::Actions => "code/engine/_generated/actions.dm",
            Self::DeclareIds => "code/engine/_generated/ids.dm",
        }
    }
}
pub(crate) struct Artifact {
    name: GeneratorName,
    text: String,
    diags: Vec<dq_analyze::sparse_slots_policy::Diagnostic>,
}
impl Artifact {
    pub(crate) fn name(&self) -> &'static str {
        self.name.name()
    }
    pub(crate) fn path(&self) -> &'static str {
        self.name.path()
    }
    pub(crate) fn text(&self) -> &str {
        &self.text
    }
    pub(crate) fn diagnostics(&self) -> &[dq_analyze::sparse_slots_policy::Diagnostic] {
        &self.diags
    }
    fn charge(&self) -> usize {
        std::mem::size_of::<Result<Self, String>>()
            .saturating_add(2 * std::mem::size_of::<usize>())
            .saturating_add(self.text.capacity())
            .saturating_add(self.diags.capacity().saturating_mul(std::mem::size_of::<
                dq_analyze::sparse_slots_policy::Diagnostic,
            >()))
            .saturating_add(self.diags.iter().fold(0usize, |n, d| {
                n.saturating_add(d.rel.capacity())
                    .saturating_add(d.msg.capacity())
            }))
    }
    fn fingerprint(&self) -> u128 {
        let mut h = xxhash_rust::xxh3::Xxh3::new();
        h.update(b"native-source-generator-v1\0");
        h.update(&(self.name().len() as u64).to_le_bytes());
        h.update(self.name().as_bytes());
        h.update(&(self.text.len() as u64).to_le_bytes());
        h.update(self.text.as_bytes());
        h.update(&(self.diags.len() as u64).to_le_bytes());
        for d in &self.diags {
            h.update(&(d.rel.len() as u64).to_le_bytes());
            h.update(d.rel.as_bytes());
            h.update(&d.line.to_le_bytes());
            h.update(&(d.msg.len() as u64).to_le_bytes());
            h.update(d.msg.as_bytes());
        }
        h.digest128()
    }
}
#[derive(Clone)]
struct Params {
    capture: Weak<CapturedPolicyInputs>,
    evidence: u64,
    configuration: Key,
    configuration_path: PathBuf,
    files: Vec<Key>,
    root: PathBuf,
    name: GeneratorName,
    result: Key,
}
fn manifest(capture: &CapturedPolicyInputs, root: &Path) -> io::Result<()> {
    if !matches!(
        capture.untyped_manifest(root)?,
        dq_analyze::captured_untyped::ManifestRead::CompiledOriginalBytes(_)
    ) {
        return Err(invalid(
            "generator requires original compiled manifest acquisition",
        ));
    }
    let path = root.join("deepquarry.dme");
    let file = capture.policy().file(&path).ok_or_else(|| {
        invalid("generator manifest requires explicit current AnalyzeRaw capture")
    })?;
    file.view(TextView::AnalyzeRaw)
        .map_err(|e| invalid(e.to_string()))?;
    Ok(())
}
pub(super) fn register(db: &Db, charge: Arc<AtomicUsize>, admission: Arc<Admission>) {
    db.define(
        GENERATOR_RESULT,
        "native-source-generator",
        move |ctx, params| {
            let p = params.downcast_ref::<Params>().expect("generator params");
            admission.abort.before_outcome(p.result)?;
            let capture = p.capture.upgrade().ok_or(QueryError::Missing(p.result))?;
            let config = ctx.input::<ConfigData>(p.configuration)?;
            let available = admission
                .limit
                .load(Ordering::Relaxed)
                .saturating_sub(charge.load(Ordering::Relaxed));
            let budget = Budget::new(available).map_err(|_| {
                admission.denied.store(true, Ordering::Relaxed);
                QueryError::Missing(p.result)
            })?;
            if budget
                .charge(
                    p.files
                        .len()
                        .saturating_mul(std::mem::size_of::<Arc<FileData>>())
                        .saturating_add(4096),
                )
                .is_err()
            {
                admission.denied.store(true, Ordering::Relaxed);
                return Err(QueryError::Missing(p.result));
            }
            let sources = p
                .files
                .iter()
                .map(|k| ctx.input::<FileData>(*k))
                .collect::<Result<Vec<_>, _>>()?;
            let result = (|| -> Result<Artifact, String> {
                if capture.semantic_source_evidence().key() != p.evidence {
                    return Err("generator semantic evidence issuance differs".into());
                }
                capture
                    .semantic_source_evidence()
                    .check(capture.policy().mapping())
                    .map_err(|e| e.to_string())?;
                manifest(&capture, &p.root).map_err(|e| e.to_string())?;
                config
                    .require_original(
                        capture
                            .configuration_bytes(&p.configuration_path)
                            .map_err(|e| e.to_string())?,
                    )
                    .map_err(|e| e.to_string())?;
                budget.charge(
                    sources
                        .iter()
                        .try_fold(4096usize, |n, s| {
                            n.checked_add(
                                s.file
                                    .path()
                                    .as_os_str()
                                    .as_encoded_bytes()
                                    .len()
                                    .saturating_mul(16)
                                    .saturating_add(512),
                            )
                        })
                        .ok_or("generator source metadata overflow")?,
                )?;
                let files = sources
                    .iter()
                    .map(|s| Arc::clone(&s.file))
                    .collect::<Vec<_>>();
                let raw = dq_analyze::captured_raw_policy::CapturedRawPolicy::from_shared_files(
                    &p.root,
                    capture.policy(),
                    &config.config,
                    &files,
                )?;
                let checkpoint = || admission.abort.scan_checkpoint();
                match p.name {
                    GeneratorName::SparseSlots => {
                        let out =
                            BorrowedSparseSlots::capture(&raw, capture.policy(), budget.clone())?
                                .generate(checkpoint)?;
                        let text = out.captured_file_text(&budget)?;
                        Ok(Artifact {
                            name: p.name,
                            text,
                            diags: out.diags,
                        })
                    }
                    GeneratorName::Actions => {
                        let out = BorrowedActions::capture(&raw, capture.policy(), budget.clone())?
                            .generate(checkpoint)?;
                        let text =
                            out.captured_named_file_text("actions", "actions.dm", &budget)?;
                        Ok(Artifact {
                            name: p.name,
                            text,
                            diags: out.diags,
                        })
                    }
                    GeneratorName::DeclareIds => {
                        let out =
                            BorrowedDeclareIds::capture(&raw, capture.policy(), budget.clone())?
                                .generate(checkpoint)?;
                        let text =
                            out.captured_named_file_text("declare_ids", "ids.dm", &budget)?;
                        Ok(Artifact {
                            name: p.name,
                            text,
                            diags: out.diags,
                        })
                    }
                    GeneratorName::Stats => {
                        let out = BorrowedStats::capture(&raw, capture.policy(), budget.clone())?
                            .generate(checkpoint)?;
                        let text = out.captured_named_file_text("stats", "stats.dm", &budget)?;
                        Ok(Artifact {
                            name: p.name,
                            text,
                            diags: out.diags,
                        })
                    }
                    GeneratorName::SystemAccessors => {
                        let out = BorrowedSystemAccessors::capture(
                            &raw,
                            capture.policy(),
                            budget.clone(),
                        )?
                        .generate(checkpoint)?;
                        let text = out.captured_file_text(&budget)?;
                        Ok(Artifact {
                            name: p.name,
                            text,
                            diags: out.diags,
                        })
                    }
                }
            })();
            // Record poisoned inputs even if cancellation wins at the final
            // checkpoint, so the next actual capture can rebuild them.
            let view_denied = sources
                .iter()
                .any(|s| s.file.require_view_budget().is_err());
            if view_denied {
                admission.view_denied.store(true, Ordering::Relaxed);
                admission.denied.store(true, Ordering::Relaxed);
            }
            admission.abort.before_outcome(p.result)?;
            if view_denied {
                return Err(QueryError::Missing(p.result));
            }
            if budget.denied() {
                admission.denied.store(true, Ordering::Relaxed);
                return Err(QueryError::Missing(p.result));
            }
            let (hash, bytes) = match &result {
                Ok(v) => (v.fingerprint(), v.charge()),
                Err(e) => (error_hash(e), result_error_charge::<Artifact>(e)),
            };
            retain_derived(&charge, bytes, &admission, p.result)?;
            admission.abort.before_outcome(p.result)?;
            Ok(Outcome::new(result, hash, bytes))
        },
    );
}
impl QueryDb {
    pub(super) fn discard_poisoned_generator_files_locked(&self, cohort: &Cohort) {
        let mut leases = self
            .raw_policy
            .leases
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        for path in &cohort.files {
            let file = key(RAW_FILE, &(&cohort.root, path));
            if self
                .db
                .input::<FileData>(file)
                .is_some_and(|value| value.file.require_view_budget().is_err())
            {
                self.db.remove(file);
                leases.remove(&file);
            }
        }
    }
    /// Borrow under the SAME family gate; no payload Arc can escape eviction/census.
    /// The callback must not re-enter this family's query API.
    pub(crate) fn with_generator_fixture<T>(
        &self,
        cohort: &Arc<Cohort>,
        name: GeneratorName,
        consume: impl FnOnce(&Artifact) -> io::Result<T>,
    ) -> io::Result<T> {
        self.with_generator_fixture_limit(cohort, name, None, consume)
    }
    fn with_generator_fixture_limit<T>(
        &self,
        cohort: &Arc<Cohort>,
        name: GeneratorName,
        limit: Option<usize>,
        consume: impl FnOnce(&Artifact) -> io::Result<T>,
    ) -> io::Result<T> {
        crate::daemon::control::checkpoint()?;
        if cohort.issuer != self.id || !cohort.capture.policy().archive().uses_body_queries(self) {
            return Err(invalid("foreign generator cohort"));
        }
        let evidence = cohort.capture.semantic_source_evidence();
        evidence.check(cohort.capture.policy().mapping())?;
        manifest(&cohort.capture, &cohort.root)?;
        let _gate = self
            .raw_policy
            .gate
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let now = Instant::now();
        self.raw_prune_locked(now);
        let prepared = match self.raw_prepare_locked(cohort, &[], now) {
            Ok(value) => value,
            Err(error) => {
                self.discard_poisoned_generator_files_locked(cohort);
                return Err(error);
            }
        };
        let result_key = key(
            GENERATOR_RESULT,
            &(
                self.id,
                evidence.key(),
                cohort.capture.policy_revision(),
                &cohort.root,
                &cohort.configuration,
                name,
            ),
        );
        let params_charge = std::mem::size_of::<Params>()
            .saturating_add(256)
            .saturating_add(
                (cohort.root.as_os_str().len() + cohort.configuration.as_os_str().len())
                    .saturating_mul(4),
            )
            .saturating_add(
                prepared
                    .sources
                    .len()
                    .saturating_mul(std::mem::size_of::<Key>()),
            );
        self.raw_admit_locked(cohort, &BTreeMap::from([(result_key, params_charge)]), now)?;
        self.begin_result_admission_locked()?;
        if let Some(limit) = limit {
            self.raw_policy
                .admission
                .limit
                .fetch_min(limit, Ordering::Relaxed);
        }
        let result = self.db.get::<Result<Artifact, String>>(
            result_key,
            Arc::new(Params {
                capture: Arc::downgrade(&cohort.capture),
                evidence: evidence.key(),
                configuration: prepared.configuration,
                configuration_path: cohort.configuration.clone(),
                files: prepared.sources.iter().map(|(k, _, _)| *k).collect(),
                root: cohort.root.clone(),
                name,
                result: result_key,
            }),
        );
        let result = match result {
            Ok(value) => value,
            Err(error) => {
                if self
                    .raw_policy
                    .admission
                    .view_denied
                    .load(Ordering::Relaxed)
                {
                    self.discard_poisoned_generator_files_locked(cohort);
                    let mut leases = self
                        .raw_policy
                        .leases
                        .lock()
                        .unwrap_or_else(|e| e.into_inner());
                    let bytes = self.db.value_bytes_at(result_key);
                    self.db.remove(result_key);
                    leases.remove(&result_key);
                    self.raw_policy
                        .charge
                        .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| {
                            Some(n.saturating_sub(bytes))
                        })
                        .ok();
                }
                return Err(self.derived_query_error("native generator query", error));
            }
        };
        if self.raw_retained_view_bytes_locked()? > INPUT_BUDGET
            || self.raw_policy.charge.load(Ordering::Relaxed) > RESULT_BUDGET
        {
            self.db.remove(result_key);
            self.raw_prune_locked(now);
            return Err(invalid("generator storage exceeds shared admission"));
        }
        let value = result
            .as_ref()
            .as_ref()
            .map_err(|e| io::Error::other(e.clone()))?;
        crate::daemon::control::checkpoint()?;
        let out = consume(value)?;
        crate::daemon::control::checkpoint()?;
        Ok(out)
    }
}

#[cfg(test)]
#[path = "generator_policy_tests.rs"]
mod tests;
