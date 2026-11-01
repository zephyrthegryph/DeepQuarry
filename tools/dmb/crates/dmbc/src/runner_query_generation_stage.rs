//! Concrete source-to-staging seam for the serialized daemon host.
//! This consumes the actual snapshot; no read/source authority escapes.
use super::*;
use std::{fs::File, io};
pub(crate) struct ClosedGeneration {
    pub(crate) journal: crate::generation_journal::SealedJournal,
    pub(crate) inputs: crate::request_runner::runner_freshness::GenerationInputClosure,
    pub(crate) included: [bool;13],
}
impl ClosedGeneration { pub(crate) fn included(&self)->[bool;13]{self.included} }
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
        let mut included=[true;13];
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
                        // Presentation metadata is issued inside THIS actual original-source
                        // loan. No source text or permission escapes in the journal.
                        let max_original_path=child.policy().mapping().source_acquisitions().map(|(path,_)|path.as_os_str().len()).max().unwrap_or(0);
                        let manifest_path_peak=workspace.root().as_os_str().len().checked_add(max_original_path).and_then(|n|n.checked_add("deepquarry.dme".len())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(1024)).ok_or_else(||io::Error::new(io::ErrorKind::OutOfMemory,"generation manifest path projection overflow"))?;
                        // Two joined/canonical path views with geometric replacement
                        // overlap; strings drop before leaving this source callback.
                        budget.charge(manifest_path_peak).map_err(|reason|io::Error::new(io::ErrorKind::OutOfMemory,reason))?;
                        included[ordinal]=original_manifest_includes(child.untyped_manifest(workspace.root())?,name)?;
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
        Ok(ClosedGeneration { journal, inputs, included })
    }
}

pub(crate) fn original_manifest_includes(manifest:dq_analyze::captured_untyped::ManifestRead<'_>,name:crate::GeneratorName)->io::Result<bool>{
 use dq_analyze::captured_untyped::ManifestRead;let bytes=match manifest{ManifestRead::CompiledOriginalBytes(bytes)|ManifestRead::OriginalBytes(bytes)=>bytes,ManifestRead::ProvenUnavailable=>return Ok(true),ManifestRead::Compiled=>return Err(io::Error::other("generator presentation requires actual original manifest bytes"))};
 // Old read_to_string(...).unwrap_or_default() treats invalid UTF8 as empty.
 let text=std::str::from_utf8(bytes).unwrap_or("");if !text.contains("#include")||name==crate::GeneratorName::UiTypes{return Ok(true)}let path=if name==crate::GeneratorName::DerivedReads{"code/_generated/reads.dm"}else{name.path()};let needle=path.as_bytes();let mut matched=0;for raw in text.bytes(){let byte=if raw==b'\\'{b'/'}else{raw};while matched>0&&needle[matched]!=byte{let mut next=matched-1;while next>0&&needle[..next]!=needle[matched-next..matched]{next-=1}matched=next;}if needle[matched]==byte{matched+=1;if matched==needle.len(){return Ok(true)}}}Ok(false)
}

#[cfg(test)]mod presentation_tests{use super::*;use dq_analyze::captured_untyped::ManifestRead;#[test]fn generation_manifest_presentation_keeps_exact_old_raw_utf8_and_separator_policy(){for bytes in [b"#include \"code\\engine\\_generated\\deps.dm\"\r\n".as_slice(),b"#include \"code/engine/_generated/deps.dm\"\n".as_slice()]{assert!(original_manifest_includes(ManifestRead::CompiledOriginalBytes(bytes),crate::GeneratorName::Deps).unwrap());}assert!(!original_manifest_includes(ManifestRead::OriginalBytes(b"#include \"code/probe.dm\""),crate::GeneratorName::Deps).unwrap());assert!(original_manifest_includes(ManifestRead::ProvenUnavailable,crate::GeneratorName::Deps).unwrap());assert!(original_manifest_includes(ManifestRead::OriginalBytes(b"\xff#include bad"),crate::GeneratorName::Deps).unwrap());assert!(original_manifest_includes(ManifestRead::Compiled,crate::GeneratorName::Deps).is_err());}}
