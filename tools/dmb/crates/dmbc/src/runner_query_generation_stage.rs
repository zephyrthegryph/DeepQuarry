//! Concrete source-to-staging seam for the serialized daemon host.
//! This consumes the actual snapshot; no read/source authority escapes.
use super::*;
use std::{fs::File, io};
pub(crate) struct ClosedGeneration {
    pub(crate) journal: crate::generation_journal::SealedJournal,
    pub(crate) inputs: crate::request_runner::runner_freshness::GenerationInputClosure,
}
impl SourceSnapshot {
    pub(crate) fn stage_generation(self, spool: File) -> io::Result<ClosedGeneration> {
        let selection = self.workspace_generator_selection.ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "generation selection unavailable",
            )
        })?;
        if self.policy_role != SnapshotPolicyRole::WorkspaceGeneratorChild
            || self
                .generation_inputs
                .as_ref()
                .is_none_or(|inputs| !inputs.matches_names(&selection.names))
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "snapshot has no complete current generation admission",
            ));
        }
        let mut journal = crate::generation_journal::StagedJournal::new(spool)?;
        {
            let guard = self.workspace_native_read()?;
            let workspace = self
                .native_workspace
                .as_ref()
                .ok_or_else(|| io::Error::other("generation workspace unavailable"))?;
            let db = self
                .native_raw_queries
                .as_ref()
                .ok_or_else(|| io::Error::other("generation query graph unavailable"))?;
            for (ordinal, name) in selection.names.iter().flatten().copied().enumerate() {
                let child = self.workspace_generator_inputs(name)?;
                db.with_workspace_generator_guard_budget(
                    workspace,
                    &guard,
                    child,
                    name,
                    |artifact, budget| {
                        // Fixed journal/stack control overlaps the existing source operation; no
                        // heap owner, borrowed view or Budget escapes the source callback.
                        budget
                            .charge(std::mem::size_of::<crate::generation_journal::StagedJournal>())
                            .map_err(|reason| io::Error::new(io::ErrorKind::OutOfMemory, reason))?;
                        if artifact.name() != name.name() {
                            return Err(io::Error::new(
                                io::ErrorKind::InvalidData,
                                "generation artifact role changed",
                            ));
                        }
                        journal.append_generator(ordinal as u32, name.name())?;
                        if name == crate::GeneratorName::UiTypes {
                            let max = artifact
                                .generated_files()
                                .map(|(path, _)| path.len())
                                .max()
                                .unwrap_or(0);
                            // Each validation's joined/normalized paths die before the next call.
                            // Reserve the actual maximum simultaneous path peak once, including warm
                            // artifacts whose producer's earlier operation control has already died.
                            let peak = workspace
                                .root()
                                .as_os_str()
                                .len()
                                .checked_add(max)
                                .and_then(|n| n.checked_mul(8))
                                .and_then(|n| n.checked_add(1024))
                                .ok_or_else(|| {
                                    io::Error::new(
                                        io::ErrorKind::OutOfMemory,
                                        "generation output path admission overflow",
                                    )
                                })?;
                            budget.charge(peak).map_err(|reason| {
                                io::Error::new(io::ErrorKind::OutOfMemory, reason)
                            })?;
                        }
                        for (path, text) in artifact.generated_files() {
                            crate::query_db::QueryDb::validate_generation_output(
                                workspace.root(),
                                name,
                                path,
                            )
                            .map_err(|reason| io::Error::new(io::ErrorKind::InvalidData, reason))?;
                            crate::daemon::control::checkpoint()?;
                            journal.append_file(path, text)?;
                        }
                        for row in artifact.diagnostics() {
                            crate::daemon::control::checkpoint()?;
                            journal.append_diagnostic(&row.rel, row.line, &row.msg)?;
                        }
                        budget
                            .require()
                            .map_err(|reason| io::Error::new(io::ErrorKind::OutOfMemory, reason))?;
                        workspace.require_scope(&guard)
                    },
                )?;
            }
            workspace.require_scope(&guard)?;
        }
        let journal = journal.seal()?;
        let inputs = self.retire_for_generation()?;
        Ok(ClosedGeneration { journal, inputs })
    }
}
