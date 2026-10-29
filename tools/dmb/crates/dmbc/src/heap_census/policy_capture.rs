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
                if self.arc_object(owner, bytes.shared_owner()) {
                    self.vec_payload(owner, bytes.shared_owner().bytes());
                }
            }
        });
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
