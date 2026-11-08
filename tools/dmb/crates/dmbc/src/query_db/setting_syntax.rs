//! SETTINGS-ONLY direct admission on the existing session QueryDb. No graph
//! query, revision, family gate or counter reset is introduced here.
use super::*;
use dm_tree::frontend::{BodySyntaxFailure, SettingExpressionInput, SettingExpressionQueries};
pub(super) fn with_setting_admission<T>(
    charged: &Arc<dm_syntax::SettingChargeCounter>,
    operation: impl FnOnce(&dm_syntax::SettingAdmission<'_>) -> Result<T, BodySyntaxFailure>,
) -> Result<T, BodySyntaxFailure> {
    with_admission_stack(charged,dm_exec::COMPILER_STACK_BYTES/16,operation)
}
fn with_admission_stack<T>(charged:&Arc<dm_syntax::SettingChargeCounter>,stack_allowance:usize,operation:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
    with_admission_checkpoint(charged,stack_allowance,&setting_checkpoint,false,operation)
}
fn with_admission_checkpoint<T>(
    charged:&Arc<dm_syntax::SettingChargeCounter>,
    stack_allowance:usize,
    checkpoint:&dyn Fn()->std::io::Result<()>,
    bounded_static_lookup_checkpoints:bool,
    operation:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,BodySyntaxFailure>,
)->Result<T,BodySyntaxFailure>{
    // Explicit worker-work allowance; not syntax meaning or a qualified
    // SourceScope allocation role. BodySyntax postparse charge stays SOFT.
    let admission = dm_syntax::SettingAdmission::with_stack_allowance(
        charged,
        body_syntax::BUDGET,
        stack_allowance,
        checkpoint,
    );
    let admission = if bounded_static_lookup_checkpoints {
        admission.with_bounded_static_lookup_checkpoints().with_bounded_physical_scan_checkpoints()
    } else {
        admission
    };
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
fn with_primary_admission<T>(charged:&Arc<dm_syntax::SettingChargeCounter>,operation:impl FnOnce(&dm_syntax::SettingAdmission<'_>)->Result<T,BodySyntaxFailure>)->Result<T,BodySyntaxFailure>{
 dm_exec::with_current_compiler_worker_stack(|scope|match scope{
  Some(scope)=>scope.with_primary_allowance(|allowance|with_admission_stack(charged,allowance,operation)).map_err(BodySyntaxFailure::Operational)?,
  None=>with_setting_admission(charged,operation), // existing conservative non-worker fallback; never called worker proof
 })
}
impl QueryDb {
    pub(crate) fn policy_syntax_counter(&self) -> Arc<dm_syntax::SettingChargeCounter> {
        Arc::clone(&self.body_charge)
    }

    pub(super) fn with_setting_admission<T>(
        &self,
        operation: impl FnOnce(&dm_syntax::SettingAdmission<'_>) -> Result<T, BodySyntaxFailure>,
    ) -> Result<T, BodySyntaxFailure> {
        with_setting_admission(&self.body_charge, operation)
    }
}

impl SettingExpressionQueries for QueryDb {
    fn original_source_work(&self)->Result<&dyn dm_preprocess::source_arena_credit::SourceArenaWork,BodySyntaxFailure>{Ok(self)}

    fn retain_original_signature_aliases(&self,row:Arc<dm_tree::frontend::OriginalSignatureAliasGroup>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{self.original_signature_aliases.lock().map_err(|_|BodySyntaxFailure::Operational(std::io::Error::other("original signature resource census poisoned")))?.retain(row,a).map_err(BodySyntaxFailure::Operational)}

    fn with_declaration_admission(
        &self,
        operation: &mut dyn FnMut(
            &dm_syntax::SettingAdmission<'_>,
        ) -> Result<(), BodySyntaxFailure>,
    ) -> Result<(), BodySyntaxFailure> {
        with_primary_admission(&self.body_charge,|admission| {
            self.original_signature_aliases.lock().map_err(|_|BodySyntaxFailure::Operational(std::io::Error::other("original signature resource census poisoned")))?.prune(admission).map_err(BodySyntaxFailure::Operational)?;
            admission
                .checkpoint()
                .map_err(BodySyntaxFailure::Operational)?;
            operation(admission)
        })
    }

    fn with_original_header_admission(
        &self,
        operation: &mut dyn FnMut(&dm_syntax::SettingAdmission<'_>) -> Result<(), BodySyntaxFailure>,
    ) -> Result<(), BodySyntaxFailure> {
        self.with_setting_admission(operation)
    }

    fn with_original_batch_producer_admission(
        &self,
        operation: &mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>,
    )->Result<(),BodySyntaxFailure>{
        dm_exec::with_current_compiler_worker_stack(|scope| {
            let Some((scope, context)) = scope.zip(crate::daemon::control::WorkerContext::capture_for_checkpoints()) else {
                return self.with_declaration_admission(operation);
            };
            // The synchronous producer cannot begin request publication.
            // Retain the real worker stack, counter, first failure and all polls.
            let checkpoint = || {
                #[cfg(test)]
                setting_test_checkpoint();
                context.checkpoint()
            };
            scope.with_primary_allowance(|allowance| {
                with_admission_checkpoint(&self.body_charge,allowance,&checkpoint,cfg!(not(test)),|admission| {
                    self.original_signature_aliases.lock().map_err(|_|BodySyntaxFailure::Operational(std::io::Error::other("original signature resource census poisoned")))?.prune(admission).map_err(BodySyntaxFailure::Operational)?;
                    admission.checkpoint().map_err(BodySyntaxFailure::Operational)?;
                    operation(admission)
                })
            }).map_err(BodySyntaxFailure::Operational)?
        })
    }

    fn initializer<'source>(
        &self,
        input: &dm_tree::frontend::OriginalInitializerExpressionInput<'source>,
    ) -> Result<dm_tree::frontend::OriginalInitializerExpression<'source>, BodySyntaxFailure> {
        self.with_setting_admission(|a| input.prepare(a))
    }

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
    setting_test_checkpoint();
    crate::daemon::control::checkpoint()
}
#[cfg(test)]
fn setting_test_checkpoint(){
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

#[cfg(test)]
mod initializer_recipe_tests {
    use super::*;
    #[test]
    fn original_initializer_recipe_warm_reborrow_preserves_native_cancel_and_recovers_same_root() {
        struct Source;
        impl dm_preprocess::SourceProvider for Source {
            fn read(&self, _: &std::path::Path) -> Result<String, String> {
                Ok("var/static/value=1+2\n".into())
            }
        }
        let db = Arc::new(QueryDb::default());
        let host = Arc::clone(&db) as Arc<dyn dm_tree::frontend::SettingExpressionQueries>;
        let front = dm_tree::frontend::build(
            std::path::Path::new("initializer-recipe-cancel.dme"),
            &Source,
            &Default::default(),
            1,
        )
        .unwrap()
        .with_setting_expression_queries(&host)
        .unwrap();
        let plan =
            dm_tree::initializers::capture_declaration_plan(&front.snapshot, &front.emission_order)
                .unwrap();
        let input = front.original_initializer_input(&plan, 0).unwrap();
        let original = input.expression().unwrap();
        let pointer = original.ast() as *const dm_syntax::Expr;
        let recipe = original.into_recipe();
        let token = crate::daemon::control::Cancellation::default();
        let binding = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(300),
        );
        let schedule = db.cancel_settings_after_checkpoints_for_test(0, token);
        let error = recipe
            .reborrow(&input)
            .err()
            .expect("warm current cancellation");
        let BodySyntaxFailure::Operational(actual) = error else {
            panic!("IO cannot be syntax/cache miss")
        };
        assert_eq!(actual.kind(), std::io::ErrorKind::Interrupted);
        drop(schedule);
        drop(binding);
        let recovered = recipe
            .reborrow(&input)
            .unwrap()
            .expect("same current source retries");
        assert_eq!(recovered.ast() as *const dm_syntax::Expr, pointer);
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 0);
    }
}

#[cfg(test)]
mod declaration_admission_tests {
    use super::*;
    #[test]
    fn early_declaration_callback_uses_exact_existing_counter_and_checks_cancelled_empty_and_late_work(
    ) {
        let db = QueryDb::default();
        let mut lease = None;
        SettingExpressionQueries::with_declaration_admission(&db, &mut |a| {
            lease = Some(a.reserve(1024).map_err(BodySyntaxFailure::Operational)?);
            Ok(())
        })
        .unwrap();
        assert_eq!(
            db.body_charge.load(std::sync::atomic::Ordering::Acquire),
            1024
        );
        drop(lease.take());
        assert_eq!(db.body_charge.load(std::sync::atomic::Ordering::Acquire), dm_syntax::SettingChargeCounter::root_allocation_bytes());
        let token = crate::daemon::control::Cancellation::default();
        let binding = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(300),
        );
        token.cancel();
        let mut called = false;
        let error = SettingExpressionQueries::with_declaration_admission(&db, &mut |_| {
            called = true;
            Ok(())
        })
        .err()
        .expect("cancelled early admission does not call original producer");
        assert!(
            matches!(error,BodySyntaxFailure::Operational(ref actual)if actual.kind()==std::io::ErrorKind::Interrupted)
        );
        assert!(!called);
        drop(binding);
        let token = crate::daemon::control::Cancellation::default();
        let binding = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(300),
        );
        let error = SettingExpressionQueries::with_declaration_admission(&db, &mut |_| {
            token.cancel();
            Ok(())
        })
        .err()
        .expect("late cancel cannot return completed declaration work");
        assert!(
            matches!(error,BodySyntaxFailure::Operational(ref actual)if actual.kind()==std::io::ErrorKind::Interrupted)
        );
        drop(binding);
        SettingExpressionQueries::with_declaration_admission(&db, &mut |_| Ok(())).unwrap();
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 0);
    }
    #[test]
    fn early_declaration_callback_preserves_first_real_io_cause_without_body_or_semantic_cache() {
        let db = QueryDb::default();
        let error = SettingExpressionQueries::with_declaration_admission(&db, &mut |_| {
            Err(BodySyntaxFailure::Operational(
                std::io::Error::from_raw_os_error(1450),
            ))
        })
        .err()
        .unwrap();
        assert!(
            matches!(error,BodySyntaxFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450))
        );
        SettingExpressionQueries::with_declaration_admission(&db, &mut |_| Ok(())).unwrap();
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 0);
    }
}

#[cfg(test)]
mod early_initializer_actual_caller_tests {
    use super::*;
    use dm_tree::frontend::{
        ColdFrontend, FrontendBuildFailure, FrontendConfig, RetainedSemanticTree,
    };
    struct Source(dm_preprocess::AcquiredSource);
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Err("original byte acquisition required".into())
        }
        fn acquired_source(
            &self,
            _: &std::path::Path,
        ) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
            Ok(Some(self.0.clone()))
        }
        fn source_acquisition(
            &self,
            _: &std::path::Path,
            text: &dm_preprocess::SourceText,
        ) -> Option<dm_preprocess::AcquiredSource> {
            self.0
                .lease()
                .source_text()
                .same_view(text)
                .then(|| self.0.clone())
        }
    }
    fn source(text: &str) -> Source {
        Source(dm_preprocess::AcquiredSource::from_original_bytes(
            text.as_bytes().to_vec(),
            (),
        ))
    }
    fn build(
        src: &Source,
        state: &mut RetainedSemanticTree,
        executor: &dm_exec::BuildExecutor,
        host: &Arc<dyn SettingExpressionQueries>,
    ) -> Result<ColdFrontend, FrontendBuildFailure> {
        dm_tree::frontend::build_with_executor_and_semantic_state_for_policy_checked(
            std::path::Path::new("actual-early-initializer.dme"),
            src,
            &Default::default(),
            FrontendConfig {
                workers: executor.workers(),
                engine: None,
                observer: None,
            },
            None,
            executor,
            Some(state),
            true,
            host,
        )
    }
    fn roots(front: &ColdFrontend) -> Vec<*const dm_syntax::Expr> {
        let archive = front.body_archive().expect("actual original archive");
        let mut roots = Vec::new();
        archive.visit_storage(|_, syntax, _| {
            for chunk in syntax.chunks().iter() {
                chunk.shared_relative().visit_setting_roots(|root| {
                    roots.push(root.original_expression() as *const dm_syntax::Expr)
                });
            }
        });
        roots
    }
    #[test]
    fn actual_querydb_early_builder_publishes_original_const_roots_before_later_input_and_preserves_old_metadata_and_lazy_nonconst(
    ) {
        let src=source("var/const/first=1+2\nvar/const/unfurled=list(1)\nvar/static/runtime=list(2)\n/proc/p()\n    return 1\n");
        let executor = dm_exec::BuildExecutor::new(2).unwrap();
        let db = Arc::new(QueryDb::default());
        let host = Arc::clone(&db) as Arc<dyn SettingExpressionQueries>;
        let mut state = RetainedSemanticTree::default();
        let old = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
            std::path::Path::new("actual-early-initializer.dme"),
            &src,
            &Default::default(),
            FrontendConfig {
                workers: 2,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            Some(&mut state),
            true,
        )
        .unwrap();
        let current = build(&src, &mut state, &executor, &host).unwrap();
        let early = roots(&current);
        assert_eq!(
            early.len(),
            2,
            "only old eager const parsing demands roots; nonconst stays lazy"
        );
        let old_plan =
            dm_tree::initializers::capture_declaration_plan(&old.snapshot, &old.emission_order)
                .unwrap();
        let plan = dm_tree::initializers::capture_declaration_plan(
            &current.snapshot,
            &current.emission_order,
        )
        .unwrap();
        assert_eq!(old_plan.plan().writes.as_ref(), plan.plan().writes.as_ref());
        assert_eq!(
            old.snapshot.tree.identity(),
            current.snapshot.tree.identity(),
            "source originalization changes no semantic metadata"
        );
        for ordinal in [0, 1] {
            let root = current
                .original_initializer_input(&plan, ordinal)
                .unwrap()
                .expression()
                .unwrap();
            assert!(
                early.contains(&(root.ast() as *const dm_syntax::Expr)),
                "later input borrows already issued original const AST"
            );
        }
        let lazy = current
            .original_initializer_input(&plan, 2)
            .unwrap()
            .expression()
            .unwrap();
        assert!(!early.contains(&(lazy.ast() as *const dm_syntax::Expr)));
        assert_eq!(roots(&current).len(), 3);
        let warm = build(&src, &mut state, &executor, &host).unwrap();
        let warm_plan =
            dm_tree::initializers::capture_declaration_plan(&warm.snapshot, &warm.emission_order)
                .unwrap();
        let warm_root = warm
            .original_initializer_input(&warm_plan, 2)
            .unwrap()
            .expression()
            .unwrap();
        assert!(lazy.same_root(&warm_root));
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 0);
    }
    struct MidWorker {
        db: Arc<QueryDb>,
        token: crate::daemon::control::Cancellation,
        coordinator: std::thread::ThreadId,
        armed: std::sync::atomic::AtomicBool,
    }
    impl std::fmt::Debug for MidWorker {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.write_str("MidWorker")
        }
    }
    impl SettingExpressionQueries for MidWorker {
        fn expression(
            &self,
            input: &SettingExpressionInput<'_>,
        ) -> Result<dm_syntax::SettingExpression, BodySyntaxFailure> {
            SettingExpressionQueries::expression(&*self.db, input)
        }
        fn initializer<'source>(
            &self,
            input: &dm_tree::frontend::OriginalInitializerExpressionInput<'source>,
        ) -> Result<dm_tree::frontend::OriginalInitializerExpression<'source>, BodySyntaxFailure>
        {
            SettingExpressionQueries::initializer(&*self.db, input)
        }
        fn with_declaration_admission(
            &self,
            operation: &mut dyn FnMut(
                &dm_syntax::SettingAdmission<'_>,
            ) -> Result<(), BodySyntaxFailure>,
        ) -> Result<(), BodySyntaxFailure> {
            SettingExpressionQueries::with_declaration_admission(&*self.db, &mut |a| {
                // Schedule the REAL native checkpoint on the worker running the
                // real checked producer, never at coordinator entry alone.
                let schedule = (std::thread::current().id() != self.coordinator
                    && !self.armed.swap(true, std::sync::atomic::Ordering::AcqRel))
                .then(|| {
                    self.db
                        .cancel_settings_after_checkpoints_for_test(500, self.token.clone())
                });
                let result = operation(a);
                drop(schedule);
                result
            })
        }
    }
    #[test]
    fn actual_querydb_early_builder_worker_context_midparse_cancellation_returns_no_frontend_and_same_source_recovers(
    ) {
        fn balanced(leaves: usize) -> String {
            if leaves == 1 { "1".to_owned() } else {
                format!("({}+{})", balanced(leaves / 2), balanced(leaves - leaves / 2))
            }
        }
        let rhs = balanced(128);
        let src = source(&format!("var/const/value={rhs}\n/proc/p()\n    return 1\n"));
        let db = Arc::new(QueryDb::default());
        let token = crate::daemon::control::Cancellation::default();
        let actual = Arc::new(MidWorker {
            db: Arc::clone(&db),
            token: token.clone(),
            coordinator: std::thread::current().id(),
            armed: std::sync::atomic::AtomicBool::new(false),
        });
        let host = actual.clone() as Arc<dyn SettingExpressionQueries>;
        let mut executor = dm_exec::BuildExecutor::new(2).unwrap();
        let mut state = RetainedSemanticTree::default();
        let binding = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(300),
        );
        let context = crate::daemon::control::WorkerContext::capture().unwrap();
        let result = executor
            .with_request_context(
                None,
                || Ok::<_, String>(context.enter()),
                |worker| build(&src, &mut state, worker, &host),
            )
            .unwrap();
        let FrontendBuildFailure::Operational(actual_io) = result
            .err()
            .expect("actual worker control returns no completed frontend")
        else {
            panic!("worker cancellation is not source syntax")
        };
        assert_eq!(actual_io.kind(), std::io::ErrorKind::Interrupted);
        assert!(actual.armed.load(std::sync::atomic::Ordering::Acquire));
        assert!(token.is_cancelled());
        drop(binding);
        let fresh = crate::daemon::control::bind_with_deadline(
            crate::daemon::control::Cancellation::default(),
            std::time::Instant::now() + std::time::Duration::from_secs(300),
        );
        let context = crate::daemon::control::WorkerContext::capture().unwrap();
        let recovered = executor
            .with_request_context(
                None,
                || Ok::<_, String>(context.enter()),
                |worker| build(&src, &mut state, worker, &host),
            )
            .unwrap()
            .unwrap();
        drop(fresh);
        let tree = &recovered.snapshot.tree;
        let member = tree.resolve(tree.lookup_type(dm_ir::SymbolId::of("/")).unwrap(), dm_ir::SymbolId::of("value"), dm_tree::MemberKind::Var).unwrap();
        assert_eq!(tree.member(member).unwrap().metadata.resolved_constant, Some(dm_ir::SemanticValue::NumberBits(128.0_f32.to_bits())), "balanced fixture preserves all 128 literal operands and actual eager-fold sum");
        let early = roots(&recovered);
        assert_eq!(early.len(), 1);
        let plan = dm_tree::initializers::capture_declaration_plan(
            &recovered.snapshot,
            &recovered.emission_order,
        )
        .unwrap();
        let root = recovered
            .original_initializer_input(&plan, 0)
            .unwrap()
            .expression()
            .unwrap();
        assert_eq!(root.ast() as *const dm_syntax::Expr, early[0]);
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed, 0);
    }
    #[test]
    fn actual_querydb_selected_constant_uses_early_root_and_admitted_original_index_then_cancels_and_recovers_warm() {
        let src=source("var/const/value=unknown+1\n/proc/p()\n    return 1\n");
        let executor=dm_exec::BuildExecutor::new(2).unwrap();
        let db=Arc::new(QueryDb::default());let host=Arc::clone(&db) as Arc<dyn SettingExpressionQueries>;
        let mut state=RetainedSemanticTree::default();let front=build(&src,&mut state,&executor,&host).unwrap();
        let early=roots(&front);assert_eq!(early.len(),1);
        let tree=&front.snapshot.tree;let owner=dm_ir::SymbolId::of("/");let name=dm_ir::SymbolId::of("value");
        let member=tree.resolve(tree.lookup_type(owner).unwrap(),name,dm_tree::MemberKind::Var).unwrap();
        let metadata=&tree.member(member).unwrap().metadata;
        let context=front.original_declaration_expression_context().unwrap();
        let input=context.selected(owner,name,metadata).unwrap();let root=input.expression().unwrap();
        assert_eq!(root.ast() as *const dm_syntax::Expr,early[0],"selected constant never reparses early adapter syntax");
        let recipe=root.into_recipe();let warm=recipe.reborrow_declaration(&input).unwrap().unwrap();assert!(std::ptr::eq(recipe.ast(),warm.ast()));
        let token=crate::daemon::control::Cancellation::default();
        let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(300));
        let schedule=db.cancel_settings_after_checkpoints_for_test(0,token);
        let failure=context.selected(owner,name,metadata).err().expect("warm index cannot bypass actual cancellation");
        let BodySyntaxFailure::Operational(actual)=failure else{panic!("cancellation is not captured syntax")};
        assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);drop(schedule);drop(binding);
        let recovered=context.selected(owner,name,metadata).unwrap().expression().unwrap();assert!(warm.same_root(&recovered));
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0,"transitive scalar source cannot demand procedure bodies");
    }

    #[test]
    fn actual_healthy_left_deep_initializer_refusal_is_cleanup_shape_not_cancellation_leak() {
        let rhs=std::iter::repeat("1").take(128).collect::<Vec<_>>().join("+");
        let src=source(&format!("var/const/value={rhs}\n/proc/p()\n    return 1\n"));
        let db=Arc::new(QueryDb::default());let host=Arc::clone(&db) as Arc<dyn SettingExpressionQueries>;
        let mut executor=dm_exec::BuildExecutor::new(2).unwrap();let mut state=RetainedSemanticTree::default();
        let token=crate::daemon::control::Cancellation::default();
        let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(300));
        let context=crate::daemon::control::WorkerContext::capture().unwrap();
        let result=executor.with_request_context(None,||Ok::<_,String>(context.enter()),|worker|build(&src,&mut state,worker,&host)).unwrap();
        let FrontendBuildFailure::Operational(actual)=result.err().expect("fresh healthy left fold still reaches the existing cleanup resource boundary")else{panic!("cleanup resource denial is not source syntax")};
        assert_eq!(actual.kind(),std::io::ErrorKind::OutOfMemory);
        assert_eq!(actual.to_string(),"setting AST cleanup stack-work allowance exhausted");
        assert!(!token.is_cancelled(),"fresh token and fresh Db exclude leaked cancellation state");
        assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);drop(binding);
    }

}

#[cfg(test)]mod actual_primary_worker_stack_tests{
 use super::*;
 #[test]fn real_existing_worker_primary_admission_handles_deep_executable_indentation_without_a_grammar_cutoff(){
  let db=Arc::new(QueryDb::default());let executor=dm_exec::BuildExecutor::new(1).unwrap();executor.install(move||{
   let mut source=String::from("/proc/deep()\n");for depth in 1..80{source.push_str(&" ".repeat(depth*4));source.push_str("if(1)\n");}source.push_str(&" ".repeat(80*4));source.push_str("set name=\"actual\"\n");
   SettingExpressionQueries::with_declaration_admission(&*db,&mut|a|{let result=dm_syntax::parse_original_declaration_skeleton_using(&source,a).map_err(BodySyntaxFailure::Operational)?;assert!(result.fatal().is_none());assert!(result.syntax().diagnostics.is_empty());let mut children=&result.syntax().items[0].children;let mut depth=0;while let Some(item)=children.first(){depth+=1;children=&item.children;}assert_eq!(depth,80,"real accepted native primary chain retained, not flattened or skipped");Ok(())}).unwrap();
   assert_eq!(db.body_charge.load(std::sync::atomic::Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
  });
 }
}
