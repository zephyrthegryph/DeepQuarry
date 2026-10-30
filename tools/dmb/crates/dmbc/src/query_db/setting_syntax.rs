//! SETTINGS-ONLY direct admission on the existing session QueryDb. No graph
//! query, revision, family gate or counter reset is introduced here.
use super::*;
use dm_tree::frontend::{BodySyntaxFailure, SettingExpressionInput, SettingExpressionQueries};
pub(super) fn with_setting_admission<T>(
    charged: &Arc<std::sync::atomic::AtomicUsize>,
    operation: impl FnOnce(&dm_syntax::SettingAdmission<'_>) -> Result<T, BodySyntaxFailure>,
) -> Result<T, BodySyntaxFailure> {
    let checkpoint = || setting_checkpoint();
    // Explicit worker-work allowance; not syntax meaning or a qualified
    // SourceScope allocation role. BodySyntax postparse charge stays SOFT.
    let admission = dm_syntax::SettingAdmission::with_stack_allowance(
        charged,
        body_syntax::BUDGET,
        dm_exec::COMPILER_STACK_BYTES / 16,
        &checkpoint,
    );
    let result = operation(&admission);
    // A prior actual operational failure wins over any later checkpoint.
    // The input may already have extracted that first actual IO for its
    // public typed boundary; do not replace it with a sticky status proxy.
    if matches!(&result, Err(BodySyntaxFailure::Operational(_))) {
        return match admission.take_operational_error() {
            Some(actual) => Err(BodySyntaxFailure::Operational(actual)),
            None => result,
        };
    }
    let final_status = admission.checkpoint();
    if let Some(actual) = admission.take_operational_error() {
        return Err(BodySyntaxFailure::Operational(actual));
    }
    final_status.map_err(BodySyntaxFailure::Operational)?;
    result
}
impl QueryDb {
    pub(super) fn with_setting_admission<T>(
        &self,
        operation: impl FnOnce(&dm_syntax::SettingAdmission<'_>) -> Result<T, BodySyntaxFailure>,
    ) -> Result<T, BodySyntaxFailure> {
        with_setting_admission(&self.body_charge, operation)
    }
}

impl SettingExpressionQueries for QueryDb {
    fn return_annotation(
        &self,
        input: &dm_tree::frontend::ReturnAnnotationInput<'_>,
    ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
        self.with_setting_admission(|admission| input.prepare(admission))
    }

    fn statements(
        &self,
        input: &mut dm_tree::frontend::SettingStatementsInput<'_, '_>,
    ) -> Result<Arc<dm_tree::frontend::StatementBody>, BodySyntaxFailure> {
        self.with_setting_admission(|a| input.prepare(a))
    }

    fn expression(
        &self,
        input: &SettingExpressionInput<'_>,
    ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
        self.with_setting_admission(|admission| input.prepare(admission))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    fn fixture(source: &str) -> dm_tree::frontend::ColdFrontend {
        struct Source(String);
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &Path) -> Result<String, String> {
                Ok(self.0.clone())
            }
        }
        dm_tree::frontend::build(
            Path::new("setting-direct.dme"),
            &Source(source.into()),
            &Default::default(),
            1,
        )
        .unwrap()
    }
    fn request(
        front: &dm_tree::frontend::ColdFrontend,
    ) -> (
        &dm_tree::frontend::BodyOccurrence,
        &dm_ir::ProcedureMetadata,
        &dm_ir::SymbolicExpression,
    ) {
        let body = &front.bodies[0];
        let metadata = front
            .snapshot
            .tree
            .member(body.member)
            .unwrap()
            .metadata
            .procedure
            .as_deref()
            .unwrap();
        let dm_ir::ProcedureSettingNode::Setting(setting) = &metadata.settings[0] else {
            panic!("original setting")
        };
        (body, metadata, &setting.value)
    }
    #[test]
    fn settings_only_native_provider_uses_same_db_without_body_query_or_retaining_manager() {
        let db = Arc::new(QueryDb::default());
        let weak = Arc::downgrade(&db);
        let host = Arc::clone(&db) as Arc<dyn SettingExpressionQueries>;
        let front = fixture("/proc/p()\n    set name = \"first\"\n    return 1\n")
            .with_setting_expression_queries(&host)
            .unwrap();
        let (body, metadata, value) = request(&front);
        let first = front.setting_expression(body, metadata, value).unwrap();
        let warm = front.setting_expression(body, metadata, value).unwrap();
        assert!(first.same_root(&warm));
        assert!(
            db.body_inputs.lock().unwrap().is_empty(),
            "ABI-first settings cannot demand whole BodySyntax"
        );
        assert_eq!(
            &front.expanded.text[first.current_span().range()],
            "\"first\""
        );
        let counter = Arc::clone(&db.body_charge);
        drop(host);
        drop(db);
        assert!(
            weak.upgrade().is_none(),
            "root/front must not own another Db"
        );
        drop(front);
        drop(first);
        assert!(counter.load(std::sync::atomic::Ordering::Acquire) > 0);
        drop(warm);
        assert_eq!(counter.load(std::sync::atomic::Ordering::Acquire), 0);
    }
    #[test]
    fn native_setting_provider_missing_or_foreign_never_uses_compatibility_fallback() {
        let bare = fixture("/proc/p()\n    set waitfor = 0\n    return 1\n");
        let (body, metadata, value) = request(&bare);
        assert!(
            matches!(bare.setting_expression(body,metadata,value),Err(BodySyntaxFailure::Operational(ref e))
            if e.kind()==std::io::ErrorKind::NotConnected)
        );
        let db = Arc::new(QueryDb::default());
        let host = Arc::clone(&db) as Arc<dyn SettingExpressionQueries>;
        let front = bare.with_setting_expression_queries(&host).unwrap();
        let other = Arc::new(QueryDb::default()) as Arc<dyn SettingExpressionQueries>;
        assert!(front
            .clone()
            .with_setting_expression_queries(&other)
            .is_err());
        let (body, metadata, value) = request(&front);
        assert!(front.setting_expression(body, metadata, value).is_ok());
        let copied = metadata.clone();
        assert!(matches!(
            front.setting_expression(body, &copied, value),
            Err(BodySyntaxFailure::Syntax(_))
        ));
    }
    #[derive(Debug)]
    struct WrongProjection(Arc<QueryDb>);
    impl SettingExpressionQueries for WrongProjection {
        fn expression(
            &self,
            input: &SettingExpressionInput<'_>,
        ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
            let root = self.0.with_setting_admission(|a| input.prepare(a))?;
            let extent = root.original_expression().span.end;
            let offset = root.current_offset() + 1;
            root.project_current(offset, extent)
                .map_err(BodySyntaxFailure::Operational)
        }
    }
    #[test]
    fn original_source_factory_rejects_host_returned_wrong_current_projection() {
        let host = Arc::new(WrongProjection(Arc::new(QueryDb::default())))
            as Arc<dyn SettingExpressionQueries>;
        let front = fixture("/proc/p()\n    set waitfor = 0\n    return 1\n")
            .with_setting_expression_queries(&host)
            .unwrap();
        let (body, metadata, value) = request(&front);
        assert!(
            matches!(front.setting_expression(body,metadata,value),Err(BodySyntaxFailure::Operational(ref e))
            if e.kind()==std::io::ErrorKind::InvalidData)
        );
    }
    struct CancelAfterRoot {
        db: Arc<QueryDb>,
        token: crate::daemon::control::Cancellation,
        first: std::sync::atomic::AtomicBool,
        original: Mutex<Option<dm_syntax::SettingExpression>>,
    }
    impl std::fmt::Debug for CancelAfterRoot {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.write_str("CancelAfterRoot")
        }
    }
    impl SettingExpressionQueries for CancelAfterRoot {
        fn expression(
            &self,
            input: &SettingExpressionInput<'_>,
        ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
            self.db.with_setting_admission(|admission| {
                let root = input.prepare(admission)?;
                if self.first.swap(false, std::sync::atomic::Ordering::Relaxed) {
                    *self.original.lock().unwrap() = Some(root.clone());
                    // Genuine leaf is complete and published BEFORE parent
                    // cancellation. It can survive as reusable immutable work.
                    self.token.cancel();
                } else {
                    assert!(self
                        .original
                        .lock()
                        .unwrap()
                        .as_ref()
                        .unwrap()
                        .same_root(&root));
                }
                Ok(root)
            })
        }
    }
    #[test]
    fn setting_provider_late_cancel_preserves_actual_error_and_reuses_completed_root_on_retry() {
        let token = crate::daemon::control::Cancellation::default();
        let host = Arc::new(CancelAfterRoot {
            db: Arc::new(QueryDb::default()),
            token: token.clone(),
            first: std::sync::atomic::AtomicBool::new(true),
            original: Mutex::new(None),
        }) as Arc<dyn SettingExpressionQueries>;
        let front = fixture("/proc/p()\n    set name = \"original\"\n    return 1\n")
            .with_setting_expression_queries(&host)
            .unwrap();
        let (body, metadata, value) = request(&front);
        let binding = crate::daemon::control::bind_with_deadline(
            token,
            std::time::Instant::now() + std::time::Duration::from_secs(300),
        );
        let error = front
            .setting_expression(body, metadata, value)
            .err()
            .expect("no completed parent after cancellation");
        let BodySyntaxFailure::Operational(error) = error else {
            panic!("cancellation is not parser meaning")
        };
        assert_eq!(error.kind(), std::io::ErrorKind::Interrupted);
        assert_eq!(error.to_string(), "build superseded before publication");
        drop(binding);
        let fresh = crate::daemon::control::bind_with_deadline(
            crate::daemon::control::Cancellation::default(),
            std::time::Instant::now() + std::time::Duration::from_secs(300),
        );
        assert!(front.setting_expression(body, metadata, value).is_ok());
        drop(fresh);
    }
}

fn setting_checkpoint() -> std::io::Result<()> {
    #[cfg(test)]
    SETTING_CANCEL.with(|pending| {
        let mut pending = pending.borrow_mut();
        if let Some((left, token)) = pending.as_mut() {
            if *left == 0 {
                token.cancel();
            } else {
                *left -= 1;
            }
        }
    });
    crate::daemon::control::checkpoint()
}
#[cfg(test)]
thread_local! {static SETTING_CANCEL:std::cell::RefCell<Option<(usize,crate::daemon::control::Cancellation)>>=const{std::cell::RefCell::new(None)};}
#[cfg(test)]
pub(crate) struct SettingCancelSchedule;
#[cfg(test)]
impl Drop for SettingCancelSchedule {
    fn drop(&mut self) {
        SETTING_CANCEL.with(|s| *s.borrow_mut() = None);
    }
}
#[cfg(test)]
impl QueryDb {
    pub(crate) fn cancel_settings_after_checkpoints_for_test(
        &self,
        left: usize,
        token: crate::daemon::control::Cancellation,
    ) -> SettingCancelSchedule {
        SETTING_CANCEL.with(|s| {
            assert!(s.borrow().is_none());
            *s.borrow_mut() = Some((left, token));
        });
        SettingCancelSchedule
    }
}
