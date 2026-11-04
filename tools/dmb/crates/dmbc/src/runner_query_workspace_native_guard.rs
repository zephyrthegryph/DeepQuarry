//! Only the active SourceSnapshot can issue this borrowed original-source scope.
use super::SourceSnapshot;
use dm_tree::frontend::SourceExportMapping;
use std::{
    io,
    sync::{Arc, Weak},
};
pub(crate) struct NativeReadGuard<'a> {
    model_preparation:Option<dm_tree::frontend::DiagnosticPreparationPurpose>,
    mapping: Option<&'a Arc<SourceExportMapping>>,
    raw_source:Option<&'a Arc<crate::runner_host::workspace_capture::RawSourceIdentity>>,
    revision: u128,
    queries: &'a Arc<crate::query_db::QueryDb>,
    workspace: Option<&'a Arc<crate::runner_host::workspace_capture::WorkspaceCapture>>,
    policy_revision: Option<u128>,
}
/// Transport for a query registered after its issuing endpoint returns.
/// This carries only weak identities, never a SourceSnapshot, tree or text.
/// It is not a completed workspace-read witness or an independent issuer.
pub(crate) struct WorkspaceQueryScope {
    model_preparation:Option<dm_tree::frontend::DiagnosticPreparationPurpose>,
    mapping: Weak<SourceExportMapping>,
    queries: Weak<crate::query_db::QueryDb>,
    workspace: Weak<crate::runner_host::workspace_capture::WorkspaceCapture>,
    revision: u128,
    policy_revision: u128,
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
            model_preparation:self.model_preparation,
            workspace: self.native_workspace.as_ref(),
            policy_revision: self.policy_revision,
            raw_source:None,
            mapping: Some(self
                .source_mapping
                .as_ref()
                .ok_or_else(|| io::Error::other("native workspace mapping unavailable"))?),
            revision: self.source_revision,
            queries: self
                .native_raw_queries
                .as_ref()
                .ok_or_else(|| io::Error::other("current compiler query graph unavailable"))?,
        })
    }
}
impl NativeReadGuard<'_> {
    pub(crate) fn uses_query_owner(&self,owner:&crate::query_db::NativeQueryOwnerIdentity)->bool{owner.matches(self.queries)}
    pub(crate) fn model_preparation(&self)->Option<dm_tree::frontend::DiagnosticPreparationPurpose>{self.model_preparation}
    pub(crate) fn query_receipt(
        &self,
        admit: &mut dyn FnMut(usize) -> io::Result<()>,
    ) -> io::Result<WorkspaceQueryScope> {
        crate::daemon::control::checkpoint()?;
        let mapping=self.mapping.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"raw source scope cannot issue a semantic query receipt"))?;
        let workspace = self.workspace.ok_or_else(|| {
            io::Error::other("workspace query scope needs the actual registered capture")
        })?;
        workspace.require_scope(self)?;
        let policy_revision = self.policy_revision.ok_or_else(|| {
            io::Error::other("workspace query scope has no published policy revision")
        })?;
        // Weak references keep their allocation headers/inline object storage
        // alive after the last strong owner. Fund that backing BEFORE downgrade.
        admit(WorkspaceQueryScope::retained_charge().ok_or_else(|| {
            io::Error::new(io::ErrorKind::OutOfMemory, "workspace query scope charge overflow")
        })?)?;
        crate::daemon::control::checkpoint()?;
        Ok(WorkspaceQueryScope {
            model_preparation:self.model_preparation,
            mapping: Arc::downgrade(mapping),
            queries: Arc::downgrade(self.queries),
            workspace: Arc::downgrade(workspace),
            revision: self.revision,
            policy_revision,
        })
    }
    pub(crate) fn matches_capture(
        &self,
        capture: &crate::runner_host::workspace_capture::WorkspaceCapture,
        origin: &Weak<SourceExportMapping>,
        raw_origin:Option<&Weak<crate::runner_host::workspace_capture::RawSourceIdentity>>,
        revision: u128,
        policy: u128,
    ) -> bool {
        (match(self.raw_source,raw_origin){(None,None)=>self.matches(origin,revision),(Some(owner),Some(origin))=>revision==self.revision&&owner.revision()==revision&&Weak::ptr_eq(origin,&Arc::downgrade(owner)),_=>false})
            && self.policy_revision == Some(policy)
            && self
                .workspace
                .is_some_and(|registered| std::ptr::eq(registered.as_ref(), capture))
    }
    pub(crate) fn uses_queries(&self, queries: &crate::query_db::QueryDb) -> bool {
        std::ptr::eq(self.queries.as_ref(), queries)
    }
    pub(crate) fn matches(&self, origin: &Weak<SourceExportMapping>, revision: u128) -> bool {
        revision == self.revision && self.mapping.is_some_and(|mapping|Weak::ptr_eq(origin,&Arc::downgrade(mapping)))
    }
    pub(crate) fn original_identity(
        &self,
        index: usize,
        identity: &dm_preprocess::SourceAcquisitionIdentity,
    ) -> io::Result<dm_preprocess::source_acquisition::OriginalAcquisitionIdentity> {
        let lease = self
            .mapping.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"raw source scope has no compiled acquisition index"))?
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
            .mapping.ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"raw source scope has no compiled acquisition index"))?
            .source_acquisition(index)
            .filter(|lease| identity.matches(lease))
            .ok_or_else(|| io::Error::other("stale or foreign native workspace acquisition"))?;
        crate::input_snapshot::recorded_source_original(lease)
    }
}

impl WorkspaceQueryScope {
    /// Registered computations have the actual Ctx, not an independently owned
    /// QueryDb. Recover its existing weak owner only for this stack callback.
    pub(crate) fn with_context<'db, R, S>(
        &self,
        context: &mut dm_query::Ctx<'db>,
        capture: &Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,
        inputs: &dm_analysis::policy_inputs::PolicyInputs,
        consume: impl for<'loan> FnOnce(
            &crate::query_db::QueryDb,
            &NativeReadGuard<'loan>,
            &mut dm_query::Ctx<'db>,
        ) -> io::Result<Result<R, S>>,
    ) -> io::Result<Result<R, S>> {
        crate::daemon::control::checkpoint()?;
        let queries = self.queries.upgrade().ok_or_else(|| {
            io::Error::new(io::ErrorKind::NotFound, "workspace query scope graph expired")
        })?;
        if !context.is_database(queries.db()) {
            return Err(io::Error::other("workspace query scope/executing context differs"));
        }
        self.with_guard(queries.as_ref(), capture, inputs,
            |guard| consume(queries.as_ref(), guard, context))
    }

    pub(crate) fn retained_charge() -> Option<usize> {
        std::mem::size_of::<Self>()
            .checked_add(std::mem::size_of::<SourceExportMapping>())?
            .checked_add(std::mem::size_of::<crate::query_db::QueryDb>())?
            .checked_add(std::mem::size_of::<crate::runner_host::workspace_capture::WorkspaceCapture>())?
            .checked_add(6 * std::mem::size_of::<usize>())
    }

    pub(crate) fn visit_storage(&self, mut visit: impl FnMut(&'static str, usize, usize)) {
        let header = 2 * std::mem::size_of::<usize>();
        visit("workspace.query_scope.mapping", self.mapping.as_ptr() as usize,
            std::mem::size_of::<SourceExportMapping>() + header);
        visit("workspace.query_scope.queries", self.queries.as_ptr() as usize,
            std::mem::size_of::<crate::query_db::QueryDb>() + header);
        visit("workspace.query_scope.capture", self.workspace.as_ptr() as usize,
            std::mem::size_of::<crate::runner_host::workspace_capture::WorkspaceCapture>() + header);
    }

    /// Reborrow only the SAME live owners under a caller's actual Db, capture
    /// and compiler input frame. No strong owner or guard loan can escape.
    pub(crate) fn with_guard<R, S>(
        &self,
        expected: &crate::query_db::QueryDb,
        capture: &Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,
        inputs: &dm_analysis::policy_inputs::PolicyInputs,
        consume: impl for<'loan> FnOnce(&NativeReadGuard<'loan>) -> io::Result<Result<R, S>>,
    ) -> io::Result<Result<R, S>> {
        crate::daemon::control::checkpoint()?;
        let missing = || io::Error::new(io::ErrorKind::NotFound, "workspace query scope owner expired");
        let mapping = self.mapping.upgrade().ok_or_else(missing)?;
        let queries = self.queries.upgrade().ok_or_else(missing)?;
        let workspace = self.workspace.upgrade().ok_or_else(missing)?;
        if !std::ptr::eq(queries.as_ref(), expected) || !Arc::ptr_eq(&workspace, capture) {
            return Err(io::Error::other("workspace query scope belongs to another graph/capture"));
        }
        let guard = NativeReadGuard {
            model_preparation:self.model_preparation,
            mapping: Some(&mapping),raw_source:None,
            queries: &queries,
            workspace: Some(&workspace),
            revision: self.revision,
            policy_revision: Some(self.policy_revision),
        };
        let require = || -> io::Result<()> {
            crate::daemon::control::checkpoint()?;
            capture.require_scope(&guard)?;
            if !capture.matches_source(inputs.mapping(), inputs.revision().compiler_source) {
                return Err(io::Error::other("workspace query scope/compiler input frame differs"));
            }
            Ok(())
        };
        require()?;
        // Operational errors keep first-error precedence. A semantic refusal
        // remains an inner result and MUST pass the same final current/cancel
        // checks as a successful value.
        let value = consume(&guard)?;
        require()?;
        Ok(value)
    }
}

impl<'a> NativeReadGuard<'a>{
 pub(crate) fn raw_owned(capture:&'a Arc<crate::runner_host::workspace_capture::WorkspaceCapture>,owner:&'a Arc<crate::runner_host::workspace_capture::RawSourceIdentity>,queries:&'a Arc<crate::query_db::QueryDb>)->io::Result<Self>{
  if !capture.matches_raw_source(owner,owner.revision())||!owner.uses_queries(queries.as_ref()){return Err(io::Error::new(io::ErrorKind::InvalidInput,"raw source guard owner/capture/QueryDb differs"))}
  let guard=Self{model_preparation:None,mapping:None,raw_source:Some(owner),revision:owner.revision(),queries,workspace:Some(capture),policy_revision:Some(capture.policy_revision())};capture.require_scope(&guard)?;Ok(guard)
 }
}

impl NativeReadGuard<'_>{
 /// Narrow control loan for the already-issued UI raw purpose. No model scope.
 pub(crate) fn ui_raw_operation_owner(&self,capture:&Arc<crate::runner_host::workspace_capture::WorkspaceCapture>)->io::Result<(Arc<crate::runner_host::workspace_capture::RawSourceIdentity>,Arc<crate::query_db::QueryDb>)>{
  capture.require_scope(self)?;let owner=self.raw_source.filter(|owner|owner.purpose()==crate::runner_host::workspace_capture::RawSourcePurpose::UiActions).ok_or_else(||io::Error::new(io::ErrorKind::InvalidInput,"UI operation needs its actual raw source identity"))?;
  if !capture.matches_raw_source(owner,owner.revision())||!owner.uses_queries(self.queries){return Err(io::Error::new(io::ErrorKind::InvalidInput,"UI raw control differs from active source/capture/Db"))}Ok((Arc::clone(owner),Arc::clone(self.queries)))
 }
}
