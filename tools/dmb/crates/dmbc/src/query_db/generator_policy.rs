//! Explicit captured-source generators in the SAME native compiler Db.
//! No file installation, filesystem IO, public producer or workspace claim.
use super::*;
use dq_analyze::{
    captured_actions::BorrowedActions, captured_declare::BorrowedDeclare,
    captured_declare_ids::BorrowedDeclareIds, captured_generator_budget::Budget,
    captured_sparse_slots::BorrowedSparseSlots, captured_stats::BorrowedStats,
    captured_system_accessors::BorrowedSystemAccessors, captured_ui_types::BorrowedUiTypes,
};
pub(super) const GENERATOR_RESULT: Kind = Kind(11);
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, serde::Serialize)]
pub enum GeneratorName {
    SparseSlots,
    SystemAccessors,
    Stats,
    Actions,
    DeclareIds,
    Declare,
    UiTypes,
    TrackedLists,
    Deps,
    AutoTracked,
    Reads,
    DerivedReads,
    Plans,
}
impl GeneratorName {
    pub(crate) fn name(self) -> &'static str {
        match self {
            Self::Deps => "deps",
            Self::Plans => "plans",
            Self::AutoTracked => "auto_tracked",
            Self::Reads => "reads",
            Self::DerivedReads => "derived_reads",
            Self::TrackedLists => "tracked_lists",
            Self::SparseSlots => "sparse_slots",
            Self::SystemAccessors => "system_accessors",
            Self::Stats => "stats",
            Self::Actions => "actions",
            Self::DeclareIds => "declare_ids",
            Self::Declare => "declare",
            Self::UiTypes => "ui_types",
        }
    }
    pub(crate) fn path(self) -> &'static str {
        match self {
            Self::Deps => "code/engine/_generated/deps.dm",
            Self::Plans => "code/engine/_generated/plans.dm",
            Self::AutoTracked => "code/engine/_generated/auto_tracked.dm",
            Self::Reads => "code/engine/_generated/reads.dm",
            Self::TrackedLists => "code/engine/_generated/tracked_lists.dm",
            Self::SparseSlots => "code/engine/_generated/sparse_slots.dm",
            Self::SystemAccessors => "code/engine/_generated/system_accessors.dm",
            Self::Stats => "code/engine/_generated/stats.dm",
            Self::Actions => "code/engine/_generated/actions.dm",
            Self::DeclareIds => "code/engine/_generated/ids.dm",
            Self::Declare => "code/engine/_generated/declare.dm",
            Self::UiTypes | Self::DerivedReads => panic!("multifile generator has no single path"),
        }
    }
}
pub(crate) struct Artifact {
    pub(super) name: GeneratorName,
    pub(super) text: String,
    pub(super) files: Vec<(String, String)>,
    pub(super) diags: Vec<dq_analyze::sparse_slots_policy::Diagnostic>,
}
impl Artifact {
    pub(crate) fn name(&self) -> &'static str {
        self.name.name()
    }
    pub(crate) fn single(&self) -> io::Result<(&'static str, &str)> {
        if self.name == GeneratorName::DerivedReads {return Err(invalid("derived_reads is a multifile artifact, not a single output"));}
        if self.name == GeneratorName::UiTypes || !self.files.is_empty() {
            return Err(invalid(
                "ui_types is a multifile artifact, not a single output",
            ));
        }
        Ok((self.name.path(), &self.text))
    }
    pub(crate) fn path(&self) -> &'static str {
        self.single()
            .expect("single generator consumer admission")
            .0
    }
    pub(crate) fn text(&self) -> &str {
        self.single()
            .expect("single generator consumer admission")
            .1
    }
    pub(crate) fn diagnostics(&self) -> &[dq_analyze::sparse_slots_policy::Diagnostic] {
        &self.diags
    }
    pub(super) fn charge(&self) -> usize {
        std::mem::size_of::<Result<Self, String>>()
            .saturating_add(2 * std::mem::size_of::<usize>())
            .saturating_add(self.text.capacity())
            .saturating_add(
                self.files
                    .capacity()
                    .saturating_mul(std::mem::size_of::<(String, String)>()),
            )
            .saturating_add(self.files.iter().fold(0usize, |n, (p, t)| {
                n.saturating_add(p.capacity()).saturating_add(t.capacity())
            }))
            .saturating_add(self.diags.capacity().saturating_mul(std::mem::size_of::<
                dq_analyze::sparse_slots_policy::Diagnostic,
            >()))
            .saturating_add(self.diags.iter().fold(0usize, |n, d| {
                n.saturating_add(d.rel.capacity())
                    .saturating_add(d.msg.capacity())
            }))
    }
    pub(super) fn fingerprint(&self) -> u128 {
        let mut h = xxhash_rust::xxh3::Xxh3::new();
        if matches!(self.name,GeneratorName::UiTypes|GeneratorName::DerivedReads) {
            h.update(b"native-source-generator-files-v1\0");
            h.update(&(self.files.len() as u64).to_le_bytes());
            for (p, t) in &self.files {
                h.update(&(p.len() as u64).to_le_bytes());
                h.update(p.as_bytes());
                h.update(&(t.len() as u64).to_le_bytes());
                h.update(t.as_bytes());
            }
        } else {
            h.update(b"native-source-generator-v1\0");
        }
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
pub(crate) struct GeneratorFiles<'a> {
    artifact: &'a Artifact,
}
impl GeneratorFiles<'_> {
    pub(crate) fn name(&self) -> &'static str {
        self.artifact.name()
    }
    pub(crate) fn files(&self) -> &[(String, String)] {
        &self.artifact.files
    }
    pub(crate) fn diagnostics(&self) -> &[dq_analyze::sparse_slots_policy::Diagnostic] {
        &self.artifact.diags
    }
    pub(crate) fn fingerprint(&self) -> u128 {
        self.artifact.fingerprint()
    }
    pub(crate) fn retained_charge(&self) -> usize {
        self.artifact.charge()
    }
}
pub(in crate::query_db) fn validate_ui_output_path(root: &Path, rel: &str) -> Result<(), String> {
    let path = Path::new(rel);
    let absolute = root.join(path);
    let normalized = dm_preprocess::regions::relative_filesystem_path(&absolute, root)
        .ok_or("ui output path is outside admitted root")?;
    if normalized != path
        || path.parent() != Some(Path::new(dq_analyze::ui_types_policy::UI_TYPES_OUT))
        || !rel.ends_with(".d.ts")
    {
        return Err("ui output path is outside declared UI file family".into());
    }
    Ok(())
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
/// Physical manifest membership requires the SAME current acquisition and an
/// actual AnalyzeRaw view. A private generated header has no such authority.
fn physical_manifest(capture:&CapturedPolicyInputs,path:&Path,lease:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{
 let file=capture.policy().file_exact(path).ok_or_else(||invalid("actual generator root has no exact captured manifest"))?;
 let decoded=file.view(TextView::CompilerDecoded).map_err(|error|invalid(error.to_string()))?;
 if !file.is_compiled()||file.role()!=dm_analysis::policy_inputs::PolicyRole::DmSource||!decoded.same_view(lease.source_text()){return Err(invalid("generator captured manifest differs from the actual root acquisition"))}
 file.view(TextView::AnalyzeRaw).map_err(|error|invalid(error.to_string()))?;Ok(())
}
pub(super) fn manifest(capture:&CapturedPolicyInputs,root:&Path)->io::Result<()>{
 use dq_analyze::captured_untyped::ManifestRead;
 if let Some(subject)=capture.original_analysis_subject(){
  // Authored spelling controls output placement. The complete subject, SAME
  // mapping and actual issued root lease alone select the fixed-manifest fact.
  let mapping=capture.policy().mapping();subject.require_bound_mapping(mapping)?;
  enum Stop{Source(&'static str),Operational(io::Error)}
  impl From<&'static str> for Stop{fn from(message:&'static str)->Self{Self::Source(message)}}
  let(_,entry,path,lease)=mapping.original_root_acquisition_using(&mut||crate::daemon::control::checkpoint().map_err(Stop::Operational)).map_err(|failure|match failure{Stop::Source(message)=>invalid(message),Stop::Operational(actual)=>actual})?;
  if subject.generation_workspace_root(entry,lease)?!=root{return Err(invalid("generator authored root differs from its actual Original subject"))}
  // Keep the captured intent/evidence preflight. It lends the SAME subject's
  // fixed original bytes or exact absence; no filesystem reopen is permitted.
  let captured=capture.untyped_manifest(root)?;let actual=subject.generation_manifest(root,entry,lease)?;
  if subject.synthetic(){
   if path!=entry||!subject.authenticates_header(entry,lease){return Err(invalid("generator synthetic root lacks its actual private header receipt"))}
   return match(actual,captured){
    (ManifestRead::ProvenUnavailable,ManifestRead::ProvenUnavailable)=>Ok(()),
    (ManifestRead::OriginalBytes(expected),ManifestRead::OriginalBytes(current))if std::ptr::eq(expected,current)=>Ok(()),
    _=>Err(invalid("generator synthetic subject cannot mint physical compiled-manifest authority")),
   }
  }
  if !matches!((actual,captured),(ManifestRead::CompiledOriginalBytes(expected),ManifestRead::CompiledOriginalBytes(current))if std::ptr::eq(expected,current)){return Err(invalid("generator requires original compiled manifest acquisition"))}
  return physical_manifest(capture,path,lease)
 }
 // Existing bounded/non-Original contract is unchanged: absence or a fixed
 // noncompiled file never grants permission for a compiler-manifest request.
 if !matches!(capture.untyped_manifest(root)?,ManifestRead::CompiledOriginalBytes(_)){return Err(invalid("generator requires original compiled manifest acquisition"))}
 let path=root.join("deepquarry.dme");let file=capture.policy().file(&path).ok_or_else(||invalid("generator manifest requires explicit current AnalyzeRaw capture"))?;
 file.view(TextView::AnalyzeRaw).map_err(|error|invalid(error.to_string()))?;Ok(())
}
pub(super) fn register(db: &Db, charge: Arc<AtomicUsize>, admission: Arc<Admission>) {
    db.define(
        GENERATOR_RESULT,
        "native-source-generator",
        move |ctx, params| {
            if let Some(full)=params.downcast_ref::<super::reactive_workspace_policy::Params>(){return super::reactive_workspace_policy::compute(ctx,full,&charge,&admission)}
            let p = params.downcast_ref::<Params>().expect("generator params");
            admission.abort.before_outcome(p.result)?;
            let capture = p.capture.upgrade().ok_or(QueryError::Missing(p.result))?;
            let config = ctx.input::<ConfigData>(p.configuration)?;
            let available = admission
                .limit
                .load(Ordering::Relaxed)
                .saturating_sub(charge.load(Ordering::Relaxed));
            let budget = Budget::new(available).map_err(|message| {
                admission.denied.store(true, Ordering::Relaxed);
                if p.name==GeneratorName::Plans{QueryError::operational(p.result,io::Error::new(io::ErrorKind::OutOfMemory,message))}else{QueryError::Missing(p.result)}
            })?;
            if let Err(message) = budget
                .charge(
                    p.files
                        .len()
                        .saturating_mul(std::mem::size_of::<Arc<FileData>>())
                        .saturating_add(4096),
                )
            {
                admission.denied.store(true, Ordering::Relaxed);
                return Err(if p.name==GeneratorName::Plans{QueryError::operational(p.result,io::Error::new(io::ErrorKind::OutOfMemory,message))}else{QueryError::Missing(p.result)});
            }
            let sources = p
                .files
                .iter()
                .map(|k| ctx.input::<FileData>(*k))
                .collect::<Result<Vec<_>, _>>()?;
            // Dependency generation is a real Kind11→Kind12 edge under this
            // caller's current context and parent-funded nested admission.
            // Actual child IO exits before any Artifact/Outcome publication.
            let dependency = if matches!(p.name,GeneratorName::Deps|GeneratorName::AutoTracked|GeneratorName::Plans) {
                let produced=super::reactive_read_policy::with_dependencies(ctx,&capture,p.configuration,&p.configuration_path,&p.root,&p.files,&budget,&charge,&admission,|value|{
                    let out=if p.name==GeneratorName::Deps{value.render_deps(capture.policy(),&budget,&crate::daemon::control::checkpoint)?}else{
                        let bytes=sources.len().checked_mul(4*std::mem::size_of::<Arc<File>>()).and_then(|n|n.checked_add(4096)).ok_or_else(||{budget.deny();dq_analyze::captured_reactive_reads::Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"AutoTracked source coordination overflow"))})?;budget.charge(bytes)?;
                        let mut files=Vec::new();files.try_reserve_exact(sources.len()).map_err(|actual|{budget.deny();dq_analyze::captured_reactive_reads::Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual))})?;if files.capacity().checked_mul(std::mem::size_of::<Arc<File>>()).is_none_or(|n|n>bytes){budget.deny();return Err(dq_analyze::captured_reactive_reads::Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"AutoTracked source allocator exceeds admission")))}for source in &sources{files.push(Arc::clone(&source.file));}
                        let raw=dq_analyze::captured_raw_policy::CapturedRawPolicy::from_shared_files(&p.root,capture.policy(),&config.config,&files)?;
                        if p.name==GeneratorName::Plans{value.render_plans(&raw,capture.policy(),&budget,&crate::daemon::control::checkpoint)?}else{value.render_auto_tracked(&raw,capture.policy(),&p.configuration_path,&budget,&crate::daemon::control::checkpoint)?}
                    };
                    let output=match p.name{GeneratorName::Deps=>"deps.dm",GeneratorName::Plans=>"plans.dm",_=>"auto_tracked.dm"};let text=out.captured_named_file_text(p.name.name(),output,&budget)?;
                    Ok(Artifact{name:p.name,text,files:Vec::new(),diags:out.diags})
                });
                Some(match produced{Ok(value)=>value,Err(dq_analyze::captured_reactive_reads::Failure::Operational(actual))=>return Err(QueryError::operational(p.result,actual)),Err(dq_analyze::captured_reactive_reads::Failure::Unsupported(message))=>return Err(QueryError::operational(p.result,io::Error::new(io::ErrorKind::Unsupported,message)))})
            } else if matches!(p.name,GeneratorName::Reads|GeneratorName::DerivedReads) {Some(match reactive_reads::produce(ctx,p,&capture,&config,&sources,&budget,&charge,&admission){Ok(value)=>value,Err(dq_analyze::captured_reactive_reads::Failure::Operational(actual))=>return Err(QueryError::operational(p.result,actual)),Err(dq_analyze::captured_reactive_reads::Failure::Unsupported(message))=>return Err(QueryError::operational(p.result,io::Error::new(io::ErrorKind::Unsupported,message)))})} else {None};
            let result = if let Some(value)=dependency {Ok(value)} else {(|| -> Result<Artifact, String> {
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
                    GeneratorName::Deps | GeneratorName::AutoTracked | GeneratorName::Plans | GeneratorName::Reads | GeneratorName::DerivedReads => unreachable!("typed reactive generator branch handled above"),
                    GeneratorName::SparseSlots => {
                        let out =
                            BorrowedSparseSlots::capture(&raw, capture.policy(), budget.clone())?
                                .generate(checkpoint)?;
                        let text = out.captured_file_text(&budget)?;
                        Ok(Artifact {
                            name: p.name,
                            text,
                            files: Vec::new(),
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
                            files: Vec::new(),
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
                            files: Vec::new(),
                            diags: out.diags,
                        })
                    }
                    GeneratorName::Declare => {
                        let out = BorrowedDeclare::capture(&raw, capture.policy(), budget.clone())?
                            .generate(checkpoint)?;
                        let text =
                            out.captured_named_file_text("declare", "declare.dm", &budget)?;
                        Ok(Artifact {
                            name: p.name,
                            text,
                            files: Vec::new(),
                            diags: out.diags,
                        })
                    }
                    GeneratorName::TrackedLists => {
                        let out=dq_analyze::captured_tracked_lists::BorrowedTrackedLists::capture(&raw,capture.policy(),budget.clone())?.generate(checkpoint)?;
                        let text=out.captured_named_file_text("tracked_lists","tracked_lists.dm",&budget)?;
                        Ok(Artifact{name:p.name,text,files:Vec::new(),diags:out.diags})
                    }
                    GeneratorName::Stats => {
                        let out = BorrowedStats::capture(&raw, capture.policy(), budget.clone())?
                            .generate(checkpoint)?;
                        let text = out.captured_named_file_text("stats", "stats.dm", &budget)?;
                        Ok(Artifact {
                            name: p.name,
                            text,
                            files: Vec::new(),
                            diags: out.diags,
                        })
                    }
                    GeneratorName::UiTypes => {
                        let out = BorrowedUiTypes::capture(&raw, capture.policy(), budget.clone())?
                            .generate(checkpoint)?;
                        for (path, _) in &out.files {
                            budget.charge(
                                path.len()
                                    .checked_add(p.root.as_os_str().len())
                                    .and_then(|n| n.checked_mul(16))
                                    .and_then(|n| n.checked_add(4096))
                                    .ok_or("ui output path admission overflow")?,
                            )?;
                            validate_ui_output_path(&p.root, path)?;
                        }
                        Ok(Artifact {
                            name: p.name,
                            text: String::new(),
                            files: out.files,
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
                            files: Vec::new(),
                            diags: out.diags,
                        })
                    }
                }
            })()};
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
            .admission.leases
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
        if matches!(name,GeneratorName::UiTypes|GeneratorName::DerivedReads) {
            return Err(invalid(
                "multifile generator requires checked file-set consumer",
            ));
        }
        self.with_generator_fixture_limit(cohort, name, None, consume)
    }
    pub(crate) fn with_generator_files_fixture<T>(
        &self,
        cohort: &Arc<Cohort>,
        name: GeneratorName,
        consume: impl FnOnce(&GeneratorFiles<'_>) -> io::Result<T>,
    ) -> io::Result<T> {
        if !matches!(name,GeneratorName::UiTypes|GeneratorName::DerivedReads) {
            return Err(invalid("single generator requires single-output consumer"));
        }
        self.with_generator_fixture_limit(cohort, name, None, |a| {
            if a.name != name || !a.text.is_empty() {
                return Err(invalid("invalid multifile generator payload mode"));
            }
            consume(&GeneratorFiles { artifact: a })
        })
    }
    #[cfg(test)]
    pub(crate) fn with_generator_limit_for_test<T>(&self,cohort:&Arc<Cohort>,name:GeneratorName,limit:usize,consume:impl FnOnce(&Artifact)->io::Result<T>)->io::Result<T>{self.with_generator_fixture_limit(cohort,name,Some(limit),consume)}
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
                        .admission.leases
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

#[cfg(test)]
#[path="generator_policy_tracked_tests.rs"]mod tracked_tests;

#[path="generator_reactive_reads.rs"]mod reactive_reads;

// Bootstrap path membership is the SAME actual generator registry, never a
// directory-prefix exception for arbitrary missing source. Multifile UI has no
// DM include; DerivedReads owns its one historical generated DM path.
impl QueryDb {
    pub(crate) fn generation_dm_outputs()->impl Iterator<Item=&'static str>{
        [GeneratorName::SparseSlots,GeneratorName::SystemAccessors,GeneratorName::Stats,GeneratorName::Actions,GeneratorName::DeclareIds,GeneratorName::Declare,GeneratorName::TrackedLists,GeneratorName::Deps,GeneratorName::AutoTracked,GeneratorName::Reads,GeneratorName::Plans].into_iter().map(GeneratorName::path).chain(["code/_generated/reads.dm"])
    }
}

#[path="generator_policy_wire.rs"]mod wire;

impl<'de> serde::Deserialize<'de> for GeneratorName{fn deserialize<D:serde::Deserializer<'de>>(decoder:D)->Result<Self,D::Error>{let name=<String as serde::Deserialize>::deserialize(decoder)?;match name.as_str(){"sparse_slots"=>Ok(Self::SparseSlots),"system_accessors"=>Ok(Self::SystemAccessors),"stats"=>Ok(Self::Stats),"actions"=>Ok(Self::Actions),"declare_ids"=>Ok(Self::DeclareIds),"declare"=>Ok(Self::Declare),"ui_types"=>Ok(Self::UiTypes),"tracked_lists"=>Ok(Self::TrackedLists),"deps"=>Ok(Self::Deps),"auto_tracked"=>Ok(Self::AutoTracked),"reads"=>Ok(Self::Reads),"derived_reads"=>Ok(Self::DerivedReads),"plans"=>Ok(Self::Plans),_=>Err(serde::de::Error::custom("unknown canonical generator name"))}}}

#[path="generator_files.rs"]mod generated_files;
impl super::QueryDb {
 /// Generation staging uses the same exact output family as the native host.
 /// A file path/encoded hash never grants permission to read source inputs.
 pub(crate) fn validate_generation_output(root:&std::path::Path,name:GeneratorName,path:&str)->Result<(),String>{
  if name==GeneratorName::UiTypes{return validate_ui_output_path(root,path)}
  let expected=if name==GeneratorName::DerivedReads{"code/_generated/reads.dm"}else{name.path()};
  if path!=expected{return Err("generator output path differs from its declared family".into())}
  Ok(())
 }
}

#[cfg(test)]impl QueryDb{pub(crate) fn require_actual_generator_manifest_for_test(capture:&CapturedPolicyInputs,root:&Path)->io::Result<()>{manifest(capture,root)}}

#[cfg(test)]impl QueryDb{pub(crate) fn require_physical_generator_manifest_for_test(capture:&CapturedPolicyInputs,path:&Path,lease:&dm_preprocess::SourceAcquisitionLease)->io::Result<()>{physical_manifest(capture,path,lease)}}
