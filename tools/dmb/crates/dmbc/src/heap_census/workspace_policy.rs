//! Borrowed policy ledger census; never a cloned model or aggregate byte guess.
use super::*;
impl HeapCensus {
    pub(crate) fn workspace_policy_facts(&mut self, facts: &crate::input_snapshot::InputSnapshot) {
        let owner = "query_snapshot.workspace.facts";
        facts.visit_original_open_storage(|address,logical,capacity|{self.exposed_buffer("query_snapshot.workspace.original_open",address,logical,capacity);});
        facts.visit_recorded_storage(|files, folders, negative, generated| {
            self.collection_entries::<(PathBuf, crate::input_snapshot::FileInput)>(
                owner,
                files as *const _ as usize,
                files.len(),
            );
            for (path, file) in files {
                self.path(owner, path);
                self.path(owner, &file.path);
            }
            self.collection_entries::<(PathBuf, crate::input_snapshot::FolderListing)>(
                owner,
                folders as *const _ as usize,
                folders.len(),
            );
            for (path, listing) in folders {
                self.path(owner, path);
                if let crate::input_snapshot::FolderListing::Present(names) = listing {
                    self.vec_payload(owner, names);
                    for name in names {
                        self.string(owner, name);
                    }
                }
            }
            for paths in [negative, generated] {
                self.collection_entries::<PathBuf>(owner, paths as *const _ as usize, paths.len());
                for path in paths {
                    self.path(owner, path);
                }
            }
        });
        facts.visit_policy_directory_accounting(|address, count| {
            self.collection_entries::<(
                usize,
                std::sync::Weak<Vec<crate::input_snapshot::PolicyDirectoryEntry>>,
            )>(
                "query_snapshot.workspace.directory_accounting",
                address,
                count,
            );
        });
        let dirs = facts.policy_directories();
        self.collection_entries::<(PathBuf, crate::input_snapshot::PolicyDirectoryObservation)>(
            owner,
            dirs as *const _ as usize,
            dirs.len(),
        );
        for (path, fact) in dirs {
            self.path(owner, path);
            if let crate::input_snapshot::PolicyDirectoryListing::Present(entries) = &fact.listing {
                entries.visit_storage(|storage| match storage {
                    crate::input_snapshot::PolicyDirectoryStorage::Owner { address, bytes } => {
                        self.exposed_buffer(owner, address, bytes, bytes);
                    }
                    crate::input_snapshot::PolicyDirectoryStorage::Buffer {
                        address,
                        logical,
                        capacity,
                    } => {
                        self.exposed_buffer(owner, address, logical, capacity);
                    }
                    crate::input_snapshot::PolicyDirectoryStorage::Name(name) => {
                        self.string(owner, name)
                    }
                });
            }
        }
    }
}
