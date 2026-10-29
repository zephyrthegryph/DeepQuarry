//! Only the active SourceSnapshot can issue this borrowed original-source scope.
use super::SourceSnapshot;
use dm_tree::frontend::SourceExportMapping;
use std::{
    io,
    sync::{Arc, Weak},
};
pub(crate) struct NativeReadGuard<'a> {
    mapping: &'a Arc<SourceExportMapping>,
    revision: u128,
    queries: &'a Arc<crate::query_db::QueryDb>,
    workspace: Option<&'a Arc<crate::runner_host::workspace_capture::WorkspaceCapture>>,
    policy_revision: Option<u128>,
}
impl SourceSnapshot {
    pub(crate) fn workspace_native_read(&self) -> io::Result<NativeReadGuard<'_>> {
        if self
            .native_workspace
            .as_ref()
            .is_none_or(|capture| self.policy_revision != Some(capture.policy_revision()))
        {
            return Err(io::Error::other(
                "workspace policy frame has not passed successful preparation/publication",
            ));
        }
        Ok(NativeReadGuard {
            workspace: self.native_workspace.as_ref(),
            policy_revision: self.policy_revision,
            mapping: self
                .source_mapping
                .as_ref()
                .ok_or_else(|| io::Error::other("native workspace mapping unavailable"))?,
            revision: self.source_revision,
            queries: self
                .native_raw_queries
                .as_ref()
                .ok_or_else(|| io::Error::other("current compiler query graph unavailable"))?,
        })
    }
}
impl NativeReadGuard<'_> {
    pub(crate) fn matches_capture(
        &self,
        capture: &crate::runner_host::workspace_capture::WorkspaceCapture,
        origin: &Weak<SourceExportMapping>,
        revision: u128,
        policy: u128,
    ) -> bool {
        self.matches(origin, revision)
            && self.policy_revision == Some(policy)
            && self
                .workspace
                .is_some_and(|registered| std::ptr::eq(registered.as_ref(), capture))
    }
    pub(crate) fn uses_queries(&self, queries: &crate::query_db::QueryDb) -> bool {
        std::ptr::eq(self.queries.as_ref(), queries)
    }
    pub(crate) fn matches(&self, origin: &Weak<SourceExportMapping>, revision: u128) -> bool {
        revision == self.revision && Weak::ptr_eq(origin, &Arc::downgrade(self.mapping))
    }
    pub(crate) fn original_identity(
        &self,
        index: usize,
        identity: &dm_preprocess::SourceAcquisitionIdentity,
    ) -> io::Result<dm_preprocess::source_acquisition::OriginalAcquisitionIdentity> {
        let lease = self
            .mapping
            .source_acquisition(index)
            .filter(|lease| identity.matches(lease))
            .ok_or_else(|| io::Error::other("stale/foreign workspace original token"))?;
        Ok(lease.original_identity())
    }
    pub(crate) fn original<'a>(
        &'a self,
        index: usize,
        identity: &dm_preprocess::SourceAcquisitionIdentity,
    ) -> io::Result<crate::input_snapshot::RecordedSourceOriginal<'a>> {
        let lease = self
            .mapping
            .source_acquisition(index)
            .filter(|lease| identity.matches(lease))
            .ok_or_else(|| io::Error::other("stale or foreign native workspace acquisition"))?;
        crate::input_snapshot::recorded_source_original(lease)
    }
}
