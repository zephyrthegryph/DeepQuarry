//! Owned raw policy views/facts, observed without making another model.
use super::*;
impl HeapCensus {
    pub(crate) fn policy_capture(
        &mut self,
        capture: &Arc<crate::runner_host::policy_capture::CapturedPolicyInputs>,
    ) {
        if !self.arc_object("query_snapshot.policy_inputs", capture) {
            return;
        }
        if let Some(subject)=capture.original_analysis_subject(){subject.census(self);}
        let folders = capture.explicit_search_folders();
        self.slice(
            "query_snapshot.policy_inputs.explicit_search_folders",
            folders,
            false,
        );
        for folder in folders {
            self.path(
                "query_snapshot.policy_inputs.explicit_search_folders",
                folder,
            );
        }
        self.unknown("query_snapshot.policy_inputs.source_aliases","BTreeMap node capacity not exposed; acquired alias records and path payloads visited below");
        capture.visit_source_aliases(|path, alias| {
            let owner = "query_snapshot.policy_inputs.source_aliases";
            self.path(owner, path);
            if self.arc_object(owner, alias) {
                alias.visit_challenge(|address, bytes| {
                    self.buffer(owner, address, bytes, bytes);
                });
                alias.visit_metadata(|path| {
                    self.path(owner, path);
                });
                self.source_acquisition(alias.lease());
            }
        });
        self.semantic_source_evidence(capture.semantic_source_evidence());
        self.policy_directory_facts(capture.facts());
        let policy = capture.policy();
        self.body_archive(policy.archive());
        self.source_export_mapping(policy.mapping());
        let count = policy.files().count();
        self.observe_items("query_snapshot.policy_inputs.files", count);
        self.unknown("query_snapshot.policy_inputs.files", "BTreeMap node backing is not exposed; retention charge is an estimate, not allocated-byte accounting");
        for file in policy.files() {
            self.arc_path("query_snapshot.policy_inputs.paths", file.path());
            for (_, text) in file.views() {
                self.source_text("query_snapshot.policy_inputs.text", text);
            }
        }
        self.unknown(
            "query_snapshot.policy_inputs.configuration_bytes",
            "BTreeMap node backing is not exposed; raw payload owners are deduplicated below",
        );
        capture.visit_configuration_bytes(|path, bytes| {
            let owner = "query_snapshot.policy_inputs.configuration_bytes";
            self.path(owner, path);
            if let Some(bytes) = bytes {
                if self.shared_bytes_owner(owner, bytes) {
                    self.vec_payload(owner, bytes.shared_owner().bytes());
                }
            }
        });
        self.unknown(
            "query_snapshot.policy_inputs.manifest_originals",
            "BTreeMap nodes not exposed; exact payload owners deduplicated below",
        );
        capture.visit_manifest_originals(|path, bytes| {
            let owner = "query_snapshot.policy_inputs.manifest_originals";
            self.path(owner, path);
            if let Some(bytes) = bytes {
                if self.shared_bytes_owner(owner, bytes) {
                    self.vec_payload(owner, bytes.shared_owner().bytes());
                }
            }
        });
        self.unknown(
            "query_snapshot.policy_inputs.untyped_inputs",
            "Bounded issuance registry nodes not exposed; no derived values cached here",
        );
        capture.visit_untyped_inputs(|key, input| {
            let owner = "query_snapshot.policy_inputs.untyped_inputs";
            self.slice(owner, key, false);
            for text in key {
                self.string(owner, text);
            }
            if self.arc_object(owner, input) {
                self.body_archive(input.archive());
                self.slice(owner, input.exempt_types(), false);
                for text in input.exempt_types() {
                    self.string(owner, text);
                }
            }
        });
        capture.facts().visit_original_open_storage(|address,logical,capacity|{self.exposed_buffer("query_snapshot.policy_inputs.original_open",address,logical,capacity);});
        capture
            .facts()
            .visit_recorded_storage(|files, folders, negative, generated| {
                self.collection_entries::<(PathBuf, crate::input_snapshot::FileInput)>(
                    "query_snapshot.policy_inputs.facts.files",
                    files as *const _ as usize,
                    files.len(),
                );
                for (path, file) in files {
                    self.path("query_snapshot.policy_inputs.facts.files", path);
                    self.path("query_snapshot.policy_inputs.facts.files", &file.path);
                }
                self.collection_entries::<(PathBuf, crate::input_snapshot::FolderListing)>(
                    "query_snapshot.policy_inputs.facts.folders",
                    folders as *const _ as usize,
                    folders.len(),
                );
                for (path, listing) in folders {
                    self.path("query_snapshot.policy_inputs.facts.folders", path);
                    if let crate::input_snapshot::FolderListing::Present(names) = listing {
                        self.vec_payload("query_snapshot.policy_inputs.facts.folders", names);
                        for name in names {
                            self.string("query_snapshot.policy_inputs.facts.folders", name);
                        }
                    }
                }
                for (label, paths) in [
                    ("query_snapshot.policy_inputs.facts.negative", negative),
                    ("query_snapshot.policy_inputs.facts.generated", generated),
                ] {
                    self.collection_entries::<PathBuf>(
                        label,
                        paths as *const _ as usize,
                        paths.len(),
                    );
                    for path in paths {
                        self.path(label, path);
                    }
                }
            });
        self.observe_items(
            "query_snapshot.policy_inputs.missing",
            capture.missing_paths().len(),
        );
        for path in capture.missing_paths() {
            self.path("query_snapshot.policy_inputs.missing", path);
        }
    }
}

impl HeapCensus {
    pub(crate) fn policy_directory_facts(&mut self, facts: &crate::input_snapshot::InputSnapshot) {
        let owner = "policy_input.typed_directory_metadata";
        facts.visit_policy_directory_accounting(|address, count| {
            self.collection_entries::<(
                usize,
                std::sync::Weak<Vec<crate::input_snapshot::PolicyDirectoryEntry>>,
            )>("policy_input.typed_directory_accounting", address, count);
        });
        self.collection_entries::<(PathBuf, crate::input_snapshot::PolicyDirectoryObservation)>(
            owner,
            facts.policy_directories() as *const _ as usize,
            facts.policy_directories().len(),
        );
        self.unknown(owner,"BTreeMap node allocator overhead excluded; Arc control headers accounted conservatively in admission, not RSS");
        for (path, observation) in facts.policy_directories() {
            self.path(owner, path);
            if let crate::input_snapshot::PolicyDirectoryListing::Present(entries) =
                &observation.listing
            {
                entries.visit_storage(|storage| match storage {
                    crate::input_snapshot::PolicyDirectoryStorage::Owner { address, bytes } => {
                        self.buffer(owner, address, bytes, bytes);
                    }
                    crate::input_snapshot::PolicyDirectoryStorage::Buffer {
                        address,
                        logical,
                        capacity,
                    } => {
                        self.buffer(owner, address, logical, capacity);
                    }
                    crate::input_snapshot::PolicyDirectoryStorage::Name(name) => {
                        self.string(owner, name)
                    }
                });
            }
        }
    }
}
