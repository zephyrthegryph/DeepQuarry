//! Explicit raw-policy capture through the compiler request's existing ledger.
//! Unwired integration helper: this does not crawl or certify a workspace. Its
//! directory/absence facts cover only requested paths and search folders.
use crate::input_snapshot::{
    InputSnapshot, RecordedSourceOriginal, RecordingInputs, SnapshotProvider,
    recorded_source_original,
};
use dm_analysis::policy_inputs::{HostCapture, PolicyInputs, PolicyRole};
use dm_preprocess::{regions::canonical_path, SourceText};
use dm_resources::capture::CaptureProvider;
use dm_tree::frontend::ColdFrontend;
use std::{
    collections::BTreeMap,
    io,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

#[derive(Clone)]
pub(crate) struct RequestedPolicyFile {
    pub path: PathBuf,
    pub role: PolicyRole,
    /// Missing optional files still become negative facts in the same ledger.
    pub required: bool,
}

/// Retains content views beside their recorded file/directory/absence proof.
/// `PolicyInputs::revision()` fingerprints text only; consumers must bind these
/// complete captured facts as well when caching decisions about missing files.
pub(crate) struct CapturedPolicyInputs {
    analysis_subject:Option<Arc<crate::input_snapshot::OriginalAnalysisSubject>>,
    semantic_sources: Arc<crate::input_snapshot::SemanticSourceEvidence>,
    source_aliases: BTreeMap<PathBuf, Arc<crate::input_snapshot::AcquiredSourceAlias>>,
    policy: PolicyInputs,
    joined_header_charge: Option<Arc<JoinedStorageCharge>>,
    facts: InputSnapshot,
    missing: Vec<PathBuf>,
    explicit_search_folders: Vec<PathBuf>,
    policy_revision: Option<u128>,
    configuration_bytes: BTreeMap<PathBuf, Option<dm_resources::SharedBytes>>,
    // Only explicitly requested noncompiled root-manifest reads/negative facts.
    manifest_originals: BTreeMap<PathBuf, Option<dm_resources::SharedBytes>>,
    // Issuance owners only. Derived values stay exclusively in Kind5.
    untyped_inputs: Mutex<BTreeMap<(bool, Vec<String>), Arc<dm_analysis::value_query::ArchiveValueInput>>>,
}
/// Retention admission for this bounded migration capture, not a process-RSS
/// or peak-read-allocation guarantee. SourceText owners can be shared, so the
/// storage payload charge deduplicates immutable owners by identity, never by
/// equal bytes. Metadata remains a conservative admission estimate.
pub(crate) const MAX_POLICY_CAPTURE_CHARGE: usize = 64 * 1024 * 1024;
/// Resource witnesses issued only for the exact joined archive and mapping.
pub(crate) struct JoinedHeaderCharge {
    archive: Arc<dm_tree::frontend::BodyArchive>,
    mapping: Arc<dm_tree::frontend::SourceExportMapping>,
    storage: Arc<JoinedStorageCharge>,
}

struct JoinedStorageCharge {
    loans: Vec<usize>,
    // The mapping retains the actual acquisitions; these addresses remain live.
    source_texts: Vec<(usize, bool, bool)>,
    syntax_counter: Arc<dm_syntax::SettingChargeCounter>,
}

impl JoinedStorageCharge {
    fn charge(&self) -> usize {
        (std::mem::size_of::<Self>() + 2 * std::mem::size_of::<usize>())
            .saturating_add(self.loans.capacity().saturating_mul(std::mem::size_of::<usize>()))
            .saturating_add(self.source_texts.capacity().saturating_mul(std::mem::size_of::<(usize, bool, bool)>()))
    }

    fn source_text_funding(&self, address: usize) -> (bool, bool) {
        self.source_texts.binary_search_by_key(&address, |row| row.0)
            .ok().map_or((false, false), |index| {
                let (_, control, payload) = self.source_texts[index];
                (control, payload)
            })
    }
}
impl JoinedHeaderCharge {
    pub(crate) fn capture(
        frontend: &dm_tree::frontend::DiagnosticSourceView<'_>,
        queries: &crate::query_db::QueryDb,
    ) -> io::Result<Self> {
        use dm_tree::frontend::DiagnosticPreparationPurpose::OriginalSharedComplete;
        let archive = frontend.archive();
        if frontend.preparation_purpose() != OriginalSharedComplete || !archive.uses_body_queries(queries) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined header charge requires the exact complete Original archive and QueryDb"));
        }
        #[cfg(debug_assertions)]
        let trace = std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some();
        #[cfg(debug_assertions)]
        let (mut excluded, mut excluded_result) = (owner_charge::Owners::default(), Ok(()));
        let mut loans = queries.with_funded_origin_policy_pages(|funded| {
            let mut loans = Vec::new();
            let mut visited = 0usize;
            archive.try_visit_original_header_token_backing_owners(|owner| {
                if visited % 64 == 0 {
                    crate::daemon::control::checkpoint()?;
                }
                visited += 1;
                if funded(owner) {
                    loans.try_reserve(1).map_err(io::Error::other)?;
                    loans.push(origin_loan_address(owner));
                    #[cfg(debug_assertions)]
                    if trace {
                        dm_preprocess::regions::visit_physical_original_token_page_storage(owner, &mut |address, _, capacity| {
                            if excluded_result.is_ok() {
                                excluded_result = excluded.original_header_storage(address, capacity);
                            }
                        });
                    }
                }
                Ok(())
            })?;
            crate::daemon::control::checkpoint()?;
            Ok(loans)
        })?;
        loans.sort_unstable();
        loans.dedup();
        #[cfg(debug_assertions)]
        if trace {
            let excluded = excluded_result.and_then(|_| excluded.totals().charge());
            eprintln!("ORIGINAL_POLICY_HEADER_BACKINGS excluded_source_ledger={excluded:?} loans={}", loans.len());
        }
        let mapping = frontend.mapping();
        let mut source_texts = queries.with_funded_policy_source_text(|funded| {
            let mut rows = Vec::new();
            for (index, (_, acquisition)) in mapping.source_acquisitions().enumerate() {
                if index % 64 == 0 { crate::daemon::control::checkpoint()?; }
                let Some(acquisition) = acquisition else { continue };
                let source = acquisition.source_text();
                let (control, payload) = funded(source);
                if control || payload {
                    rows.try_reserve(1).map_err(io::Error::other)?;
                    source.visit_storage(|address, _, _| rows.push((address, control, payload)));
                }
            }
            Ok(rows)
        })?;
        source_texts.sort_unstable_by_key(|row| row.0);
        source_texts.dedup_by(|next, kept| {
            if next.0 != kept.0 { return false; }
            kept.1 |= next.1;
            kept.2 |= next.2;
            true
        });
        Ok(Self {
            archive: Arc::clone(archive),
            mapping: Arc::clone(mapping),
            storage: Arc::new(JoinedStorageCharge { loans, source_texts, syntax_counter: queries.policy_syntax_counter() }),
        })
    }

    fn require(&self, policy: &PolicyInputs) -> io::Result<Arc<JoinedStorageCharge>> {
        if !Arc::ptr_eq(&self.archive, policy.archive()) || !Arc::ptr_eq(&self.mapping, policy.mapping()) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined storage charge belongs to another archive or source mapping"));
        }
        Ok(Arc::clone(&self.storage))
    }
}

/// Allocation identity for the exact Box retained by this immutable archive,
/// not a stable key and never exchanged between archive instances.
fn origin_loan_address(owner: &dyn std::any::Any) -> usize {
    std::ptr::from_ref(owner).cast::<()>() as usize
}

impl CapturedPolicyInputs {
    pub(crate) fn original_analysis_subject(&self)->Option<&Arc<crate::input_snapshot::OriginalAnalysisSubject>>{self.analysis_subject.as_ref()}
    pub(crate) fn untyped_manifest(
        &self,
        root: &Path,
    ) -> io::Result<dq_analyze::captured_untyped::ManifestRead<'_>> {
        use crate::input_snapshot::{recorded_source_original, RecordedSourceOriginal};
        use dq_analyze::captured_untyped::ManifestRead;
        if self.policy_revision.is_none() {
            return Err(io::Error::other("manifest needs bound intent"));
        }
        self.semantic_sources.check(self.policy.mapping())?;
        if let Some(subject)=&self.analysis_subject{return subject.manifest_originals(root,self.policy.mapping())}
        let path = canonical_path(&root.join("deepquarry.dme"));
        let mut compiled: Option<&[u8]> = None;
        for (candidate, lease) in self.policy.mapping().source_acquisitions() {
            if dm_preprocess::regions::relative_filesystem_path(candidate, root).as_deref()
                == Some(Path::new("deepquarry.dme"))
                && canonical_path(candidate) != path
            {
                return Err(io::Error::other(
                    "manifest alias is not an exact root provider key",
                ));
            }
            if canonical_path(candidate) != path {
                continue;
            }
            let lease = lease.ok_or_else(|| io::Error::other("manifest acquisition absent"))?;
            let bytes = match recorded_source_original(lease)? {
                RecordedSourceOriginal::Utf8(text) => text.as_bytes(),
                RecordedSourceOriginal::Bytes(bytes) => bytes.as_slice(),
            };
            if compiled.is_some_and(|prior| prior != bytes) {
                return Err(io::Error::other("manifest acquisitions contradict"));
            }
            compiled = Some(bytes);
        }
        if let Some(bytes) = compiled {
            return Ok(ManifestRead::CompiledOriginalBytes(bytes));
        }
        match self.manifest_originals.get(&path) {
            Some(Some(bytes))
                if self
                    .policy
                    .file(&path)
                    .is_some_and(|f| f.role() == PolicyRole::DmSource && !f.is_compiled()) =>
            {
                let hash = xxhash_rust::xxh3::xxh3_128(bytes.as_slice());
                if !self
                    .facts
                    .files()
                    .any(|f| f.path == path && f.content == hash)
                {
                    return Err(io::Error::other(
                        "manifest original lacks exact recorded content fact",
                    ));
                }
                Ok(ManifestRead::OriginalBytes(bytes.as_slice()))
            }
            Some(None) if self.missing.contains(&path) && self.policy.file(&path).is_none() => {
                let mut negative = false;
                self.facts
                    .visit_recorded_storage(|_, _, missing, _| negative = missing.contains(&path));
                if !negative {
                    return Err(io::Error::other("manifest absence is not recorded"));
                }
                Ok(ManifestRead::ProvenUnavailable)
            }
            _ => Err(io::Error::other(
                "root manifest requires an explicit optional DmSource request",
            )),
        }
    }
    /// Original compiled membership, including ONLY aliases certified at capture.
    /// Never infer identity from prefix spelling or perform filesystem IO at query time.
    pub(crate) fn compiled_source_file(
        &self,
        requested: &Path,
    ) -> Option<&dm_analysis::policy_inputs::PolicyFile> {
        let requested = canonical_path(requested);
        let primary = self
            .source_aliases
            .get(&requested)
            .map(|proof| proof.primary_path())
            .unwrap_or(requested.as_path());
        self.policy
            .file(primary)
            .filter(|file| file.is_compiled() && file.role() == PolicyRole::DmSource)
    }
    pub(crate) fn untyped_input(
        &self,
        exemptions: &[String],
    ) -> io::Result<Arc<dm_analysis::value_query::ArchiveValueInput>> {
        self.untyped_input_mode(exemptions, false)
    }
    pub(crate) fn untyped_input_mode(
        &self,
        exemptions: &[String],
        canonical: bool,
    ) -> io::Result<Arc<dm_analysis::value_query::ArchiveValueInput>> {
        if self.policy_revision.is_none() {
            return Err(io::Error::other("value input needs bound intent"));
        }
        // Bound the small issuance registry before canonical-key allocation.
        let bytes = exemptions
            .iter()
            .try_fold(0usize, |n, s| n.checked_add(s.len() + 64))
            .ok_or_else(|| io::Error::other("exemption metadata overflow"))?;
        if bytes > 64 * 1024 || exemptions.len() > 4096 {
            return Err(io::Error::other(
                "untyped exemption metadata exceeds admission",
            ));
        }
        let mut types = exemptions.to_vec();
        types.sort();
        types.dedup();
        let key = (canonical, types);
        let mut registry = self
            .untyped_inputs
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if let Some(input) = registry.get(&key) {
            return Ok(Arc::clone(input));
        }
        if registry.len() >= 16 {
            return Err(io::Error::other("untyped issuance registry is full"));
        }
        // Each retained entry owns two bounded canonical lists plus metadata.
        // Admission is checked under the registry lock before creating its owner.
        let retained = registry.iter().fold(0usize, |n, (key, input)| {
            n.saturating_add(untyped_owner_charge(&key.1, input))
        });
        let planned = key.1
            .capacity()
            .saturating_mul(std::mem::size_of::<String>())
            .saturating_add(key.1.iter().map(|s| s.capacity()).sum::<usize>())
            .saturating_mul(2)
            .saturating_add(512);
        let base = self.budget_charge_base().saturating_add(retained);
        admit_capture_charge(base.saturating_add(planned))?;
        let archive = Arc::clone(self.policy.archive());
        let input = if canonical {
            dm_analysis::value_query::ArchiveValueInput::new_canonical(archive, &key.1)
        } else {
            dm_analysis::value_query::ArchiveValueInput::new(archive, &key.1)
        };
        admit_capture_charge(base.saturating_add(untyped_owner_charge(&key.1, &input)))?;
        registry.insert(key, Arc::clone(&input));
        Ok(input)
    }
    pub(crate) fn visit_untyped_inputs(
        &self,
        mut visit: impl FnMut(&[String], &Arc<dm_analysis::value_query::ArchiveValueInput>),
    ) {
        for (key, input) in self
            .untyped_inputs
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
        {
            visit(&key.1, input);
        }
    }
    pub(crate) fn visit_manifest_originals(
        &self,
        mut visit: impl FnMut(&PathBuf, Option<&dm_resources::SharedBytes>),
    ) {
        for (path, bytes) in &self.manifest_originals {
            visit(path, bytes.as_ref());
        }
    }
    pub(crate) fn semantic_source_evidence(
        &self,
    ) -> &Arc<crate::input_snapshot::SemanticSourceEvidence> {
        &self.semantic_sources
    }
    pub(crate) fn bind_request(
        mut self,
        request: &crate::policy_request::AdmittedPolicyRequest,
    ) -> io::Result<Self> {
        if request.workspace().is_some() {
            return Err(io::Error::other(
                "workspace intent requires its native workspace producer",
            ));
        }
        if request.search_folders() != self.explicit_search_folders.as_slice() {
            return Err(io::Error::other(
                "captured explicit search scope differs from policy request",
            ));
        }
        // Existing present bytes prove either optional or required admission.
        // Missing paths remain optional-only and retain their exact role below.
        for file in request.files() {
            let role = match file.role {
                crate::policy_request::PolicyInputRole::DmSource => PolicyRole::DmSource,
                crate::policy_request::PolicyInputRole::Configuration => PolicyRole::Configuration,
            };
            let resolved = self
                .source_aliases
                .get(&file.path)
                .map(|alias| alias.primary_path())
                .unwrap_or(file.path.as_path());
            match self.policy.file(resolved) {
                Some(captured) if captured.role() == role => (),
                None if !file.required
                    && self.missing.contains(&file.path)
                    && match role {
                        PolicyRole::Configuration => self
                            .configuration_bytes
                            .get(&file.path)
                            .is_some_and(|bytes| bytes.is_none()),
                        PolicyRole::DmSource => !self.configuration_bytes.contains_key(&file.path),
                    } =>
                {
                    ()
                }
                _ => {
                    return Err(io::Error::other(
                        "policy request is not proven by captured inputs",
                    ))
                }
            }
        }
        // The request must explain the entire explicit scope, not merely a
        // subset of a more permissive capture. Compiler members are implicit;
        // noncompiled files and missing paths need exact admitted intent.
        for file in self.policy.files().filter(|file| !file.is_compiled()) {
            if !request.files().iter().any(|wanted| {
                wanted.path.as_path() == file.path().as_path()
                    && match wanted.role {
                        crate::policy_request::PolicyInputRole::DmSource => {
                            file.role() == PolicyRole::DmSource
                        }
                        crate::policy_request::PolicyInputRole::Configuration => {
                            file.role() == PolicyRole::Configuration
                        }
                    }
            }) {
                return Err(io::Error::other(
                    "captured noncompiled policy file is not requested",
                ));
            }
        }
        for (path, alias) in &self.source_aliases {
            if alias.requested_path() != path
                || !request.files().iter().any(|wanted| {
                    wanted.path == *path
                        && wanted.role == crate::policy_request::PolicyInputRole::DmSource
                })
            {
                return Err(io::Error::other(
                    "acquired source alias is outside admitted request",
                ));
            }
        }
        for path in &self.missing {
            if !request
                .files()
                .iter()
                .any(|wanted| wanted.path == *path && !wanted.required)
            {
                return Err(io::Error::other(
                    "captured missing policy path is not requested",
                ));
            }
        }
        if request
            .search_folders()
            .iter()
            .any(|folder| !self.facts.folders().contains_key(folder))
        {
            return Err(io::Error::other("policy search folder is not recorded"));
        }
        self.policy_revision = Some(crate::policy_request::captured_revision(
            self.policy.revision().policy_inputs,
            &self.facts,
            request,
        )?);
        if !self.source_aliases.is_empty() {
            let aliases = self
                .source_aliases
                .iter()
                .map(|(path, alias)| (path, alias.primary_path()))
                .collect::<Vec<_>>();
            let bytes =
                serde_json::to_vec(&("acquired-source-alias-v1", self.policy_revision, &aliases))
                    .map_err(io::Error::other)?;
            self.policy_revision = Some(xxhash_rust::xxh3::xxh3_128(&bytes));
        }
        Ok(self)
    }
    pub(crate) fn bind_diagnostic_profile(mut self) -> io::Result<Self> {
        let pin = self.policy_revision.ok_or_else(|| {
            io::Error::other("diagnostic profile requires exact bound policy intent")
        })?;
        let mut identity = b"native-diagnostic-inherited-variable-v1\0".to_vec();
        identity.extend_from_slice(&pin.to_le_bytes());
        self.policy_revision = Some(xxhash_rust::xxh3::xxh3_128(&identity));
        Ok(self)
    }
    pub(crate) fn policy_revision(&self) -> Option<u128> {
        self.policy_revision
    }

    pub fn policy(&self) -> &PolicyInputs {
        &self.policy
    }
    pub fn facts(&self) -> &InputSnapshot {
        &self.facts
    }
    pub(crate) fn explicit_search_folders(&self) -> &[PathBuf] {
        &self.explicit_search_folders
    }
    pub fn missing_paths(&self) -> &[PathBuf] {
        &self.missing
    }
    /// Exact authenticated configuration payload. Missing is returned ONLY for
    /// a requested optional Configuration path whose absence was recorded.
    /// Unrequested/wrong-role paths are errors, never permission to default.
    pub fn configuration_bytes(&self, path: &Path) -> io::Result<Option<&[u8]>> {
        let path = canonical_path(path);
        match self.configuration_bytes.get(&path) {
            Some(Some(bytes))
                if self
                    .policy
                    .file(&path)
                    .is_some_and(|file| file.role() == PolicyRole::Configuration) =>
            {
                Ok(Some(bytes.as_slice()))
            }
            Some(None) if self.missing.contains(&path) => Ok(None),
            _ => Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "configuration path is not admitted with a captured configuration role/absence",
            )),
        }
    }
    /// Clone the SAME admitted raw-byte owner, or retain exact optional absence.
    pub(crate) fn configuration_owner(
        &self,
        path: &Path,
    ) -> io::Result<Option<dm_resources::SharedBytes>> {
        self.configuration_bytes(path)?; // role/absence admission before lookup
        Ok(self
            .configuration_bytes
            .get(&canonical_path(path))
            .expect("validated config roster")
            .clone())
    }
    pub(crate) fn visit_source_aliases(
        &self,
        mut visit: impl FnMut(&PathBuf, &Arc<crate::input_snapshot::AcquiredSourceAlias>),
    ) {
        for (path, alias) in &self.source_aliases {
            visit(path, alias);
        }
    }
    pub(crate) fn visit_configuration_bytes(
        &self,
        mut visit: impl FnMut(&PathBuf, Option<&dm_resources::SharedBytes>),
    ) {
        for (path, bytes) in &self.configuration_bytes {
            visit(path, bytes.as_ref());
        }
    }
    /// Later resource reads can extend the same request ledger. Replay admits
    /// only a full ledger that already contains every captured policy fact.
    pub fn is_recorded_in(&self, complete: &InputSnapshot) -> bool {
        let mut combined = complete.clone();
        combined.merge(&self.facts).is_ok() && combined.same_recorded_facts(complete)
    }
    pub fn budget_charge(&self) -> usize {
        self.budget_charge_base().saturating_add(
            self.untyped_inputs
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .iter()
                .fold(0usize, |n, (key, input)| {
                    n.saturating_add(untyped_owner_charge(&key.1, input))
                }),
        )
    }
    fn budget_charge_base(&self) -> usize {
        let mut owners = owner_charge::Owners::default();
        let subject = self.analysis_subject.as_ref().map_or(0, |subject| subject.charge());
        let mut header_owners = owner_charge::Owners::default();
        let mut header_result = Ok(());
        #[cfg(debug_assertions)]
        let trace = std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some();
        #[cfg(debug_assertions)]
        let (mut funded_literals, mut funded_result) = (owner_charge::Owners::default(), Ok(()));
        let mut visit_header = |address, _, capacity, funded: bool| {
            if !funded && header_result.is_ok() {
                header_result = header_owners.original_header_storage(address, capacity);
            }
            #[cfg(debug_assertions)]
            if funded && trace && funded_result.is_ok() {
                funded_result = funded_literals.original_header_storage(address, capacity);
            }
        };
        let archive = self.policy.archive();
        if let Some(storage) = &self.joined_header_charge {
            // Read-only identity check against the existing native counter.
            // This view grants no new allocation or stack work allowance.
            let domain = dm_syntax::SettingAdmission::with_stack_allowance(&storage.syntax_counter, 0, 0, &|| Ok(()));
            archive.visit_original_header_storage_classified(&domain, &mut visit_header,
                &mut |owner| storage.loans.binary_search(&origin_loan_address(owner)).is_ok());
        } else {
            archive.visit_original_header_storage(|address, logical, capacity| visit_header(address, logical, capacity, false));
        }
        let header = header_result.and_then(|_| header_owners.totals().charge()).unwrap_or(usize::MAX);
        let roster = self.joined_header_charge.as_ref().map_or(0, |storage| storage.charge());
        let mut charge = 4096usize.saturating_add(subject).saturating_add(header).saturating_add(roster);
        charge = charge.saturating_add(
            self.explicit_search_folders
                .capacity()
                .saturating_mul(std::mem::size_of::<PathBuf>()),
        );
        for folder in &self.explicit_search_folders {
            charge = charge.saturating_add(folder.as_os_str().as_encoded_bytes().len());
        }
        for file in self.policy.files() {
            charge = charge
                .saturating_add(256)
                .saturating_add(file.path().as_os_str().as_encoded_bytes().len());
            for (_, text) in file.views() {
                charge = charge.saturating_add(64);
                let text_charge = match &self.joined_header_charge {
                    Some(storage) => owners.text_with_funding(text, |address| storage.source_text_funding(address)),
                    None => owners.text(text),
                };
                if text_charge.is_err() {
                    return usize::MAX;
                }
            }
        }
        for (path, bytes) in self
            .configuration_bytes
            .iter()
            .chain(self.manifest_originals.iter())
        {
            charge = charge
                .saturating_add(128)
                .saturating_add(path.as_os_str().as_encoded_bytes().len());
            if let Some(bytes) = bytes {
                if owners.bytes(bytes).is_err() {
                    return usize::MAX;
                }
            }
        }
        let _capture_local = charge.saturating_sub(subject).saturating_sub(header);
        let before_facts = charge;
        self.facts
            .visit_recorded_storage(|files, folders, negative, generated| {
                for file in files.values() {
                    charge = charge.saturating_add(192).saturating_add(
                        file.path
                            .as_os_str()
                            .as_encoded_bytes()
                            .len()
                            .saturating_mul(2),
                    );
                }
                for (path, listing) in folders {
                    charge = charge
                        .saturating_add(128)
                        .saturating_add(path.as_os_str().as_encoded_bytes().len());
                    if let crate::input_snapshot::FolderListing::Present(names) = listing {
                        for name in names {
                            charge = charge.saturating_add(32).saturating_add(name.len());
                        }
                    }
                }
                for path in negative.iter().chain(generated.iter()) {
                    charge = charge
                        .saturating_add(96)
                        .saturating_add(path.as_os_str().as_encoded_bytes().len());
                }
            });
        let _facts = charge.saturating_sub(before_facts);
        let before_aliases = charge;
        for path in &self.missing {
            charge = charge
                .saturating_add(32)
                .saturating_add(path.as_os_str().as_encoded_bytes().len());
        }
        for (path, alias) in &self.source_aliases {
            charge = charge
                .saturating_add(128)
                .saturating_add(path.capacity())
                .saturating_add(alias.metadata_charge());
        }
        let _aliases = charge.saturating_sub(before_aliases);
        let evidence = self.semantic_sources.budget_charge();
        let directories = self.facts.policy_directory_accounting_retained_charge();
        let owned = owners.totals();
        let total = charge.saturating_add(evidence).saturating_add(directories)
            .saturating_add(owned.charge().unwrap_or(usize::MAX));
        #[cfg(debug_assertions)]
        if trace {
            let funded_literals = funded_result.and_then(|_| funded_literals.totals().charge());
            let funded_texts = self.joined_header_charge.as_ref().map_or(0, |storage| storage.source_texts.len());
            eprintln!("ORIGINAL_POLICY_CAPTURE_STORAGE total={total} header={header} funded_literals={funded_literals:?} funded_texts={funded_texts} backing_roster={roster} capture_local={_capture_local} facts={_facts} aliases={_aliases} evidence={evidence} directories={directories} subject={subject} owned={owned:?}");
        }
        total
    }
}

#[path = "policy_owner_charge.rs"]
mod owner_charge;

/// Call before completing the request's InputSnapshot, using the SAME
/// RecordingInputs that supplied the compiler frontend. This reads bytes but
/// never parses more DM or manufactures compiled membership. Callers explicitly
/// request policy-only DM/config and search folders; no recursive coverage claim.
pub(crate) fn capture<P: SnapshotProvider>(
    frontend: &ColdFrontend,
    inputs: &RecordingInputs<P>,
    requested: &[RequestedPolicyFile],
    search_folders: &[PathBuf],
) -> io::Result<CapturedPolicyInputs> {
    capture_source(
        CaptureSource::Compiled(frontend),
        inputs,
        requested,
        search_folders,
        CompiledViews::AllRaw, None, None,
    )
}
pub(crate) fn capture_diagnostic<P: SnapshotProvider>(
    frontend: &dm_tree::frontend::DiagnosticSourceView<'_>,
    inputs: &RecordingInputs<P>,
    requested: &[RequestedPolicyFile],
    search_folders: &[PathBuf],
) -> io::Result<CapturedPolicyInputs> {
    capture_diagnostic_using(frontend, inputs, requested, search_folders, CompiledViews::AllRaw, None)
}

/// The ephemeral Checker sibling issues only original compiled source and
/// its selected configuration. Analyze raw policy uses the separate workspace
/// capture; this owner is never exposed as a general named-policy snapshot.
pub(crate) fn capture_joined_checker<P: SnapshotProvider>(
    frontend: &dm_tree::frontend::DiagnosticSourceView<'_>,
    inputs: &RecordingInputs<P>,
    requested: &[RequestedPolicyFile],
    search_folders: &[PathBuf],
    joined: Option<&JoinedHeaderCharge>,
) -> io::Result<CapturedPolicyInputs> {
    use dm_tree::frontend::DiagnosticPreparationPurpose::OriginalSharedComplete;
    if frontend.preparation_purpose() != OriginalSharedComplete
        || requested.len() != 1
        || requested[0].role != PolicyRole::Configuration
        || !search_folders.is_empty()
    {
        return Err(io::Error::new(io::ErrorKind::InvalidInput,
            "joined Checker requires its complete Original source and exact configuration-only scope"));
    }
    capture_diagnostic_using(
        frontend, inputs, requested, search_folders, CompiledViews::CheckerDecoded, joined,
    )
}

fn capture_diagnostic_using<P: SnapshotProvider>(
    frontend: &dm_tree::frontend::DiagnosticSourceView<'_>,
    inputs: &RecordingInputs<P>,
    requested: &[RequestedPolicyFile],
    search_folders: &[PathBuf],
    compiled_views: CompiledViews,
    joined: Option<&JoinedHeaderCharge>,
) -> io::Result<CapturedPolicyInputs> {
    if frontend.preparation_purpose().is_structural(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"handlers structural source cannot occupy the checker policy capture"))}
    if !frontend.receipt().authenticates(frontend.tree())
        || !frontend.archive().matches_tree(frontend.tree())
    {
        return Err(io::Error::other("diagnostic policy original graph differs"));
    }
    capture_source(
        CaptureSource::Diagnostic(frontend),
        inputs,
        requested,
        search_folders,
        compiled_views, joined, None,
    )
}
/// Configuration-only child for the genuine workspace generator endpoint.
/// Compiled declarations stay the original CompilerDecoded PolicyFiles; raw
/// policy is borrowed from completed workspace pages, except the original DME
/// whose AnalyzeRaw view is required by the existing generator manifest gate.
pub(crate) fn capture_workspace_generator<P: SnapshotProvider>(
    frontend: &ColdFrontend, inputs: &RecordingInputs<P>, configuration: &Path,
) -> io::Result<CapturedPolicyInputs> {
    capture_workspace_child(CaptureSource::Compiled(frontend),inputs,configuration,None,None)
}
/// A separately selected semantic child over the genuine diagnostic source owner.
/// This does not grant a workspace role; the snapshot issuer joins actual intent,
/// current workspace capture, archive, and configuration before exposing it.
pub(crate) fn capture_analysis_semantic_with_joined_headers<P:SnapshotProvider>(
    frontend:&dm_tree::frontend::DiagnosticSourceView<'_>,inputs:&RecordingInputs<P>,configuration:&Path,
    joined:Option<&JoinedHeaderCharge>,
)->io::Result<CapturedPolicyInputs>{
 if frontend.preparation_purpose().is_structural(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"handlers partial source cannot occupy a full workspace semantic/generation child"))}
    if frontend.mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290 || !frontend.receipt().authenticates(frontend.tree()) {return Err(io::Error::new(io::ErrorKind::InvalidInput,"analysis semantic child requires its genuine original owner"))}
    // The same full Original Analyze subject owns the root manifest. Keep its
    // private binding instead of falling back to a path-spelling approximation.
    let subject=inputs.original_analysis_subject();
    if let Some(subject)=subject{subject.require_bound_mapping(frontend.mapping())?;}
    capture_workspace_child(CaptureSource::Diagnostic(frontend),inputs,configuration,joined,subject)
}
/// Complete diagnostic source data for the separately admitted generation child.
/// The caller must still bind actual selected names and the retired input closure.
pub(crate) fn capture_analysis_generator<P:SnapshotProvider>(frontend:&dm_tree::frontend::DiagnosticSourceView<'_>,inputs:&RecordingInputs<P>,configuration:&Path)->io::Result<CapturedPolicyInputs>{
 if frontend.preparation_purpose().is_structural(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"handlers partial source cannot occupy a full workspace semantic/generation child"))}
 frontend.require_original_analysis_seed().map_err(io::Error::other)?;
 if !frontend.receipt().is_clean(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original generation requires clean actual source declarations"))}
 if frontend.mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290||!frontend.original_plan().defines().is_empty(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"generation analysis child lacks actual default context"))}
 let subject=inputs.original_analysis_subject().ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"generation requires actual full Analyze subject"))?;subject.require_bound_mapping(frontend.mapping())?;
 capture_workspace_child(CaptureSource::Diagnostic(frontend),inputs,configuration,None,Some(subject))
}
fn capture_workspace_child<P:SnapshotProvider>(
    source: CaptureSource<'_, '_>,
    inputs: &RecordingInputs<P>,
    configuration: &Path,
    joined: Option<&JoinedHeaderCharge>,
    subject: Option<&Arc<crate::input_snapshot::OriginalAnalysisSubject>>,
) -> io::Result<CapturedPolicyInputs> {
    let intent = crate::policy_request::PolicyInputRequest {analysis_context:None,workspace_auxiliary:Vec::new(),workspace_generators:Vec::new(),
        workspace: None,
        files: vec![crate::policy_request::PolicyInputFile {
            path: configuration.to_owned(),
            role: crate::policy_request::PolicyInputRole::Configuration,
            required: false,
        }],
        search_folders: Vec::new(),
    }.admit()?;
    capture_source(source, inputs,
        &intent.capture_files(), &[], CompiledViews::GeneratorManifest, joined, subject)?
        .bind_request(&intent)
}
#[derive(Clone, Copy)]
enum CompiledViews { AllRaw, GeneratorManifest, CheckerDecoded }
// Only original issued handles are dispatched; the capture loop remains ONE.
enum CaptureSource<'a, 'b> {
    Compiled(&'a ColdFrontend),
    Diagnostic(&'a dm_tree::frontend::DiagnosticSourceView<'b>),
}
impl CaptureSource<'_, '_> {
    fn files(&self) -> &[dm_tree::frontend::SourceFile] {
        match self {
            Self::Compiled(f) => &f.files,
            Self::Diagnostic(f) => f.files(),
        }
    }
    fn capture_policy(
        &self,
        extra: Vec<HostCapture>,
    ) -> Result<PolicyInputs, dm_analysis::policy_inputs::CaptureError> {
        match self {
            Self::Compiled(f) => PolicyInputs::capture(f, extra),
            Self::Diagnostic(f) => PolicyInputs::capture_diagnostic(f, extra),
        }
    }
    fn evidence<P: SnapshotProvider>(
        &self,
        inputs: &RecordingInputs<P>,
        compiled_views: CompiledViews,
    ) -> io::Result<Arc<crate::input_snapshot::SemanticSourceEvidence>> {
        match self {
            Self::Compiled(f) => inputs.semantic_source_evidence(f),
            Self::Diagnostic(f) if matches!(compiled_views, CompiledViews::CheckerDecoded) =>
                inputs.diagnostic_source_evidence_using(f, false),
            Self::Diagnostic(f) => inputs.diagnostic_source_evidence(f),
        }
    }
}
struct MappedOriginal<'a> {
    mapping: &'a dm_tree::frontend::SourceExportMapping,
    occurrence: usize,
    path: &'a Path,
    bytes: RecordedSourceOriginal<'a>,
}

fn capture_source<P: SnapshotProvider>(
    frontend: CaptureSource<'_, '_>,
    inputs: &RecordingInputs<P>,
    requested: &[RequestedPolicyFile],
    search_folders: &[PathBuf],
    compiled_views: CompiledViews,
    joined: Option<&JoinedHeaderCharge>,
    subject: Option<&Arc<crate::input_snapshot::OriginalAnalysisSubject>>,
) -> io::Result<CapturedPolicyInputs> {
    let checker_decoded = matches!(compiled_views, CompiledViews::CheckerDecoded);
    let original = match &frontend {
        CaptureSource::Diagnostic(view) if view.original_plan().is_original_diagnostic() => Some(*view),
        _ => None,
    };
    // Raw Original opens intentionally live outside the ordinary prepared
    // file ledger. Keep exact provider path/occurrence and their current
    // acquisitions, including leaves untouched by Native's eager pre-scan.
    let mut original_occurrences = BTreeMap::new();
    if let Some(view) = original {
        for (occurrence, path) in view.semantic_includes() {
            original_occurrences.entry(path.as_path()).or_insert(occurrence);
        }
    }
    let initial = original.is_none().then(|| inputs.snapshot()).transpose()?;
    let raw_digests: BTreeMap<_, _> = initial
        .iter()
        .flat_map(InputSnapshot::files)
        .map(|file| (file.path.as_path(), file.content))
        .collect();
    let mut sources = BTreeMap::new();
    let mut requests = BTreeMap::new();
    for file in frontend.files().iter().filter(|file| file.captured) {
        if checker_decoded { crate::daemon::control::checkpoint()?; }
        // Only the exact privately issued root header lacks a physical source fact.
        // PolicyInputs still retains its genuine frontend CompilerDecoded view;
        // no AnalyzeRaw/recorded-file authority is minted for generated bytes.
        if inputs.is_generated_analysis_header(file.path.as_ref(),&file.text){continue}
        let path = canonical_path(file.path.as_ref());
        let (content, mapped) = if let Some(view) = original {
            let actual_path = file.path.as_path();
            let occurrence = *original_occurrences.get(actual_path)
                .ok_or_else(|| io::Error::other("policy source has no actual Original occurrence"))?;
            let mapping = view.mapping().as_ref();
            let fact = match inputs.mapped_recorded_source_fact(mapping, occurrence, actual_path) {
                Ok(fact) => fact,
                Err(error) => {
                    if std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some() {
                        let planned = view.original_plan().occurrences().get(occurrence);
                        eprintln!("ORIGINAL_POLICY_SOURCE_RECEIPT_FAILED occurrence={occurrence} actual={actual_path:?} planned_path={:?} non_text={:?} plan_acquired={} error={error}",
                            planned.map(|row| row.path.as_path()), planned.and_then(|row| row.non_text_kind()),
                            view.original_plan().source_acquisitions().get(&occurrence).is_some());
                    }
                    return Err(error);
                }
            };
            let lease = mapping.source_acquisition(occurrence)
                .filter(|lease| lease.source_text().same_view(&file.text))
                .ok_or_else(|| io::Error::other("policy source differs from its actual Original acquisition"))?;
            (fact.content, Some(MappedOriginal {
                mapping, occurrence, path: actual_path, bytes: recorded_source_original(lease)?,
            }))
        } else {
            let content = raw_digests.get(path.as_path()).copied().ok_or_else(|| {
                io::Error::other("policy capture lacks compiler's recorded source fact")
            })?;
            (content, None)
        };
        sources.insert(path.clone(), (&file.text, content, mapped));
        requests.insert(
            path.clone(),
            RequestedPolicyFile {
                path,
                role: PolicyRole::DmSource,
                required: true,
            },
        );
    }
    for request in requested {
        if checker_decoded { crate::daemon::control::checkpoint()?; }
        let path = canonical_path(&request.path);
        if let Some(previous) = requests.get_mut(&path) {
            if previous.role != request.role {
                return Err(io::Error::other("policy path has contradictory roles"));
            }
            previous.required |= request.required;
        } else {
            requests.insert(
                path.clone(),
                RequestedPolicyFile {
                    path,
                    ..request.clone()
                },
            );
        }
    }
    if checker_decoded {
        dm_profile::request_mark("joined.checker_roster_checked");
    }
    let explicit_search_folders = search_folders
        .iter()
        .map(|folder| canonical_path(folder))
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    for folder in &explicit_search_folders {
        if checker_decoded { crate::daemon::control::checkpoint()?; }
        inputs.record_search_folder(folder)?;
    }
    let mut extra = Vec::new();
    let mut missing = Vec::new();
    let mut configuration_bytes = BTreeMap::new();
    let mut manifest_originals = BTreeMap::new();
    let mut source_aliases = BTreeMap::new();
    for (path, request) in requests {
        if checker_decoded { crate::daemon::control::checkpoint()?; }
        let mut primary = path.clone();
        if request.role == PolicyRole::DmSource && !sources.contains_key(&path) {
            let candidates = sources
                .iter()
                .filter(|(key, _)| {
                    dm_preprocess::regions::relative_filesystem_path(key, &path)
                        .is_some_and(|rel| rel.as_os_str().is_empty())
                })
                .collect::<Vec<_>>();
            if candidates.len() > 1 {
                return Err(io::Error::other(
                    "source alias has ambiguous acquired primaries",
                ));
            }
            if let Some((key, (text, _, original))) = candidates.first() {
                let alias = match original {
                    Some(source) => inputs.acquire_mapped_source_alias(
                        &path, source.path, source.mapping, source.occurrence,
                    )?,
                    None => inputs.acquire_source_alias(&path, key, text)?,
                };
                if let Some(alias) = alias {
                    primary = (*key).clone();
                    source_aliases.insert(path.clone(), alias);
                } else {
                    return Err(io::Error::other(
                        "provider cannot certify requested alias of acquired compiler source",
                    ));
                }
            }
        }
        if let Some((compiled, raw_content, original)) = sources.get(&primary) {
            // PolicyInputs::capture already installs the exact original
            // CompilerDecoded file. The workspace generator never uses raw
            // compiled DM text: its raw questions require separate page proof.
            if matches!(compiled_views, CompiledViews::GeneratorManifest)
                && !primary.file_name().is_some_and(|name| name == "deepquarry.dme")
            {
                continue;
            }
            if matches!(compiled_views, CompiledViews::CheckerDecoded) {
                // Keep the existing input closure, including the parent
                // listing. The compiled file is installed by PolicyInputs
                // from the exact frontend view, not the recorder's raw bytes.
                let parent = path.parent().ok_or_else(|| io::Error::other("compiled policy source has no parent"))?;
                inputs.record_search_folder(parent)?;
                continue;
            }
            let raw = if let Some(source) = original {
                match &source.bytes {
                    RecordedSourceOriginal::Utf8(text) if !text.as_bytes().contains(&b'\r') => SourceText::clone(text),
                    RecordedSourceOriginal::Utf8(text) => analyze_raw(text.as_bytes()),
                    RecordedSourceOriginal::Bytes(bytes) => analyze_raw(bytes.as_slice()),
                }
            } else if compiled.span_fingerprint(0..compiled.len()) == Some(*raw_content) {
                if compiled.as_bytes().contains(&b'\r') {
                    analyze_raw(compiled.as_bytes())
                } else {
                    SourceText::clone(compiled)
                }
            } else {
                let original = inputs.exceptional_source_bytes(&primary)?.ok_or_else(|| {
                    io::Error::other(
                        "compiled source original byte view was not retained at acquisition",
                    )
                })?;
                if xxhash_rust::xxh3::xxh3_128(original.as_slice()) != *raw_content
                    || dm_preprocess::decode_source_bytes(original.as_slice()) != compiled.as_str()
                {
                    return Err(io::Error::other(
                        "exceptional original source contradicts compiler capture",
                    ));
                }
                analyze_raw(original.as_slice())
            };
            let parent = path
                .parent()
                .ok_or_else(|| io::Error::other("compiled policy source has no parent"))?;
            inputs.record_search_folder(parent)?;
            let path = Arc::new(primary);
            extra.push(HostCapture::compiler_decoded(
                Arc::clone(&path),
                SourceText::clone(compiled),
            ));
            extra.push(HostCapture::analyze_raw(path, PolicyRole::DmSource, raw));
            continue;
        }
        // Existing resource capture already records the parent listing AND a
        // negative lookup on NotFound, including for optional configuration.
        let Some(bytes) = inputs.read_candidate(&path)? else {
            if request.required {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("required policy input missing: {}", path.display()),
                ));
            }
            if request.role == PolicyRole::Configuration {
                configuration_bytes.insert(path.clone(), None);
            }
            if request.role == PolicyRole::DmSource
                && path.file_name().is_some_and(|n| n == "deepquarry.dme")
            {
                manifest_originals.insert(path.clone(), None);
            }
            missing.push(path);
            continue;
        };
        if request.role == PolicyRole::DmSource
            && path.file_name().is_some_and(|n| n == "deepquarry.dme")
        {
            manifest_originals.insert(path.clone(), Some(bytes.clone()));
        }
        let path = Arc::new(path);
        let native = if request.role == PolicyRole::DmSource {
            let text = SourceText::from(dm_preprocess::decode_source_bytes(bytes.as_slice()));
            extra.push(HostCapture::compiler_decoded(
                Arc::clone(&path),
                text.clone(),
            ));
            Some(text)
        } else {
            None
        };
        // Analyze reads UTF-8-lossy and universal newlines. In particular, its
        // raw view retains a UTF-8 BOM, unlike the compiler's decoded original.
        let raw = if let Some(native) = native.filter(|native| {
            native.as_str().as_bytes() == bytes.as_slice() && !bytes.as_slice().contains(&b'\r')
        }) {
            native
        } else {
            analyze_raw(bytes.as_slice())
        };
        if request.role == PolicyRole::Configuration {
            configuration_bytes.insert(path.as_ref().clone(), Some(bytes));
        }
        extra.push(HostCapture::analyze_raw(path, request.role, raw));
    }
    if checker_decoded {
        dm_profile::request_mark("joined.checker_requests_captured");
        crate::daemon::control::checkpoint()?;
        dm_profile::request_mark("joined.checker_policy_capture_started");
    }
    let policy = frontend.capture_policy(extra).map_err(io::Error::other)?;
    if checker_decoded {
        dm_profile::request_mark("joined.checker_policy_captured");
        crate::daemon::control::checkpoint()?;
    }
    let facts = inputs.snapshot()?;
    if checker_decoded {
        dm_profile::request_mark("joined.checker_facts_captured");
        crate::daemon::control::checkpoint()?;
    }
    let captured = CapturedPolicyInputs {
        analysis_subject: subject.cloned(),
        semantic_sources: frontend.evidence(inputs, compiled_views)?,
        joined_header_charge: joined.map(|proof| proof.require(&policy)).transpose()?,
        source_aliases,
        policy,
        facts,
        missing,
        explicit_search_folders,
        policy_revision: None,
        configuration_bytes,
        manifest_originals,
        untyped_inputs: Mutex::new(BTreeMap::new()),
    };
    admit_capture_charge(captured.budget_charge())?;
    if checker_decoded {
        dm_profile::request_mark("joined.checker_capture_charged");
    }
    Ok(captured)
}
fn untyped_owner_charge(
    key: &Vec<String>,
    input: &dm_analysis::value_query::ArchiveValueInput,
) -> usize {
    // Registry coordinates + input Arc/header only. The shared archive is
    // already counted by capture, and Kind5 owns the derived proof separately.
    let mut bytes = 256usize
        .saturating_add(std::mem::size_of_val(input))
        .saturating_add(key.capacity().saturating_mul(std::mem::size_of::<String>()))
        .saturating_add(std::mem::size_of_val(input.exempt_types()));
    for text in key.iter().chain(input.exempt_types()) {
        bytes = bytes.saturating_add(text.capacity());
    }
    bytes
}
fn admit_capture_charge(charge: usize) -> io::Result<()> {
    if charge > MAX_POLICY_CAPTURE_CHARGE {
        Err(io::Error::other(
            "raw policy capture exceeds bounded migration retention admission",
        ))
    } else {
        Ok(())
    }
}
fn analyze_raw(bytes: &[u8]) -> SourceText {
    String::from_utf8_lossy(bytes)
        .replace("\r\n", "\n")
        .replace('\r', "\n")
        .into()
}

#[cfg(test)]
#[path = "policy_capture_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "policy_capture_alias_tests.rs"]
mod acquired_alias_tests;

/// Parser-report sibling over its actual borrowed source and the SAME exact
/// standalone Checker source/configuration intent (admission sorts paths). This syntax-only source
/// cannot satisfy the complete joined Checker capture guard.
fn require_parser_report_scope(requested:&[RequestedPolicyFile],search_folders:&[PathBuf])->io::Result<()>{
 let invalid=||io::Error::new(io::ErrorKind::InvalidInput,"parser-report requires the actual standalone source and optional configuration scope");
 let(source,configuration)=match requested{[source,configuration]if source.role==PolicyRole::DmSource&&configuration.role==PolicyRole::Configuration=>(source,configuration),[configuration,source]if source.role==PolicyRole::DmSource&&configuration.role==PolicyRole::Configuration=>(source,configuration),_=>return Err(invalid())};
 if source.role!=PolicyRole::DmSource||!source.required||!source.path.is_absolute()||configuration.role!=PolicyRole::Configuration||configuration.required||!configuration.path.is_absolute()||!search_folders.is_empty(){return Err(invalid())}Ok(())
}
pub(crate) fn capture_parser_report<P:SnapshotProvider>(source:&dm_tree::frontend::ParseOnlySyntaxSource<'_>,inputs:&RecordingInputs<P>,requested:&[RequestedPolicyFile],search_folders:&[PathBuf])->io::Result<CapturedPolicyInputs>{
 require_parser_report_scope(requested,search_folders)?;let view=source.source_view()?;capture_diagnostic_using(&view,inputs,requested,search_folders,CompiledViews::CheckerDecoded,None)
}


/// Private config-free semantic child on the actual Analyze subject. It uses
/// the SAME source capture loop, with NO interpreted configuration request.
pub(crate) fn capture_semantic_utility<P:SnapshotProvider>(frontend:&dm_tree::frontend::DiagnosticSourceView<'_>,inputs:&RecordingInputs<P>,subject:&Arc<crate::input_snapshot::OriginalAnalysisSubject>)->io::Result<CapturedPolicyInputs>{
 if frontend.original_analysis_completeness().is_none()||inputs.original_analysis_subject().is_none_or(|actual|!Arc::ptr_eq(actual,subject)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"semantic-only capture lacks actual complete/prefix Analyze subject"))}
 frontend.require_original_analysis_seed().map_err(io::Error::other)?;subject.bind_frontend(frontend)?;
 capture_source(CaptureSource::Diagnostic(frontend),inputs,&[],&[],CompiledViews::AllRaw,None,Some(subject))
}

#[cfg(test)]mod parser_report_scope_controls{
 use super::*;
 #[test]fn parser_report_accepts_exact_standalone_pair_and_refuses_partial_or_wider_roles(){
  let root=PathBuf::from(if cfg!(windows){"E:/actual/parser"}else{"/actual/parser"});let source=RequestedPolicyFile{path:root.join("project.dme"),role:PolicyRole::DmSource,required:true};let config=RequestedPolicyFile{path:root.join("SpacemanDMM.toml"),role:PolicyRole::Configuration,required:false};let pair=[source,config];
  require_parser_report_scope(&pair,&[]).unwrap();let reversed=[pair[1].clone(),pair[0].clone()];require_parser_report_scope(&reversed,&[]).unwrap();
  assert!(require_parser_report_scope(&pair[1..],&[]).is_err());assert!(require_parser_report_scope(&pair[..1],&[]).is_err());assert!(require_parser_report_scope(&pair,&[root.clone()]).is_err());
  for case in 0..6{let mut changed=pair.clone();match case{0=>changed[0].role=PolicyRole::Configuration,1=>changed[0].required=false,2=>changed[1].role=PolicyRole::DmSource,3=>changed[1].required=true,4=>changed[0].path=PathBuf::from("relative.dme"),5=>changed[1].path=PathBuf::from("relative.toml"),_=>unreachable!()};assert!(require_parser_report_scope(&changed,&[]).is_err());}
 }

 #[test]fn parser_report_scope_accepts_actual_admitted_path_sorted_request(){
  use crate::policy_request::{PolicyInputRequest,PolicyInputFile,PolicyInputRole,AnalysisContext};
  let root=PathBuf::from(if cfg!(windows){"E:/actual/parser"}else{"/actual/parser"});let request=PolicyInputRequest{analysis_context:Some(AnalysisContext::OriginalChecker0290),files:vec![PolicyInputFile{path:root.join("project.dme"),role:PolicyInputRole::DmSource,required:true},PolicyInputFile{path:root.join("SpacemanDMM.toml"),role:PolicyInputRole::Configuration,required:false}],..Default::default()};
  let admitted=request.admit().unwrap();let requested=admitted.capture_files();assert_eq!(requested.len(),2);require_parser_report_scope(&requested,admitted.search_folders()).unwrap();
 }
}
