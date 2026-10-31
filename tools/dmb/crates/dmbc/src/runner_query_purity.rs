//! Internal prepared-snapshot authority for the incremental purity producer.
//! There is intentionally no CLI/public cutover until all effect categories
//! have independent old-checker coverage. Never reconstruct a policy from disk.
use super::SourceSnapshot;
use dm_analysis::{
    check_policy::{CheckerPolicy, WarningLevel},
    checker_effects::{EffectInput, Produced},
};
use std::{path::Path, sync::Arc};
pub(crate) struct PurityScope<'a> {
    snapshot: &'a SourceSnapshot,
    tree: &'a dm_tree::SemanticTree,
    policy: &'a CheckerPolicy,
    policy_key: u128,
}
impl PurityScope<'_> {
    pub(crate) fn validate(
        &self,
        db: &crate::query_db::QueryDb,
        input: &Arc<EffectInput>,
    ) -> Result<(), String> {
        let capture = self
            .snapshot
            .named_policy_capture(self.tree)
            .map_err(|e| e.to_string())?;
        if !Arc::ptr_eq(capture.policy().archive(), input.archive())
            || !self.snapshot.matches_tree(self.tree)
            || !self
                .snapshot
                .native_raw_queries
                .as_ref()
                .is_some_and(|q| std::ptr::eq(q.as_ref(), db))
        {
            return Err(
                "purity scope is not the exact current published archive/Db/policy frame".into(),
            );
        }
        input.validate_current(capture.policy().archive(), db)?;
        // A None config is still a captured, revision-qualified selection. Never
        // skip the frame/owner checks on that path or on a cached report.
        if self.snapshot.policy_revision.is_none() {
            return Err("purity policy frame unissued".into());
        }
        Ok(())
    }
    pub(crate) fn policy(&self) -> &CheckerPolicy {
        self.policy
    }
    pub(crate) fn policy_key(&self) -> u128 {
        self.policy_key
    }
}
fn hash_policy(policy: &CheckerPolicy, frame: u128, configuration: &Path) -> u128 {
    fn level(x: WarningLevel) -> u8 {
        match x {
            WarningLevel::Error => 0,
            WarningLevel::Warning => 1,
            WarningLevel::Info => 2,
            WarningLevel::Hint => 3,
            WarningLevel::Disabled => 4,
            WarningLevel::Unset => 5,
        }
    }
    let mut h = xxhash_rust::xxh3::Xxh3::new();
    h.update(b"native-purity-config-v1\0");
    h.update(&frame.to_le_bytes());
    h.update(configuration.as_os_str().as_encoded_bytes());
    h.update(&[level(policy.display_error_level)]);
    for (name, value) in &policy.diagnostics {
        h.update(&(name.len() as u64).to_le_bytes());
        h.update(name.as_bytes());
        h.update(&[level(*value)]);
    }
    h.digest128()
}
impl SourceSnapshot {
    /// Caller may retain the immutable input between queries; all subsequent
    /// accesses must supply this exact current snapshot again, never a cached
    /// owner token alone. Strong source ownership remains the original archive.
    pub(crate) fn native_purity_input(
        &self,
        tree: &dm_tree::SemanticTree,
    ) -> Result<Arc<EffectInput>, String> {
        let c = self.named_policy_capture(tree).map_err(|e| e.to_string())?;
        EffectInput::new(
            Arc::clone(c.policy().archive()),
            tree.checker_builtin_profile()
                .ok_or("purity builtin profile unavailable")?,
        )
    }
    pub(crate) fn native_purity_report(
        &self,
        input: &Arc<EffectInput>,
        environment: &Path,
        explicit: Option<&Path>,
        tree: &dm_tree::SemanticTree,
    ) -> std::io::Result<Arc<Vec<Produced>>> {
        self.native_effect_report(input, environment, explicit, tree, false)
    }
    pub(crate) fn native_sleep_report(
        &self,
        input: &Arc<EffectInput>,
        environment: &Path,
        explicit: Option<&Path>,
        tree: &dm_tree::SemanticTree,
    ) -> std::io::Result<Arc<Vec<Produced>>> {
        self.native_effect_report(input, environment, explicit, tree, true)
    }
    fn native_effect_report(&self,input:&Arc<EffectInput>,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree,sleeping:bool)->std::io::Result<Arc<Vec<Produced>>>{
        self.with_effect_scope(input,environment,explicit,tree,|db,scope|if sleeping{db.native_sleep_report(input,scope)}else{db.native_purity_report(input,scope)})
    }
    /// Additive original page input; ordinary bounded whole-report input stays.
    pub(crate) fn native_effect_source_input(&self,tree:&dm_tree::SemanticTree)->Result<Arc<EffectInput>,String>{let capture=self.named_policy_capture(tree).map_err(|e|e.to_string())?;EffectInput::source_pages(Arc::clone(capture.policy().archive()),tree.checker_builtin_profile().ok_or("effect source builtin profile unavailable")?)}
    pub(crate) fn native_effect_source_page(&self,input:&Arc<EffectInput>,start:usize,width:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree)->std::io::Result<Arc<dm_analysis::checker_effects::EffectPageFacts>>{
        self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.native_effect_source_page(input,scope,start,width))
    }
    pub(crate) fn native_effect_source_graph(&self,input:&Arc<EffectInput>,width:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree)->std::io::Result<Arc<crate::query_db::NativeEffectGraph>>{self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.native_effect_source_graph(input,scope,width))}
    pub(crate) fn native_effect_source_summary(&self,input:&Arc<EffectInput>,width:usize,environment:&Path,explicit:Option<&Path>,tree:&dm_tree::SemanticTree)->std::io::Result<Arc<crate::query_db::NativeEffectSummary>>{self.with_effect_scope(input,environment,explicit,tree,|db,scope|db.native_effect_source_summary(input,scope,width))}
    fn with_effect_scope<T>(
        &self,
        input: &Arc<EffectInput>,
        environment: &Path,
        explicit: Option<&Path>,
        tree: &dm_tree::SemanticTree,
        operation: impl FnOnce(&crate::query_db::QueryDb,&PurityScope<'_>)->std::io::Result<T>,
    ) -> std::io::Result<T> {
        crate::daemon::control::checkpoint()?;
        let capture = self.named_policy_capture(tree)?;
        if !environment.is_absolute()
            || capture
                .compiled_source_file(environment)
                .is_none_or(|file| file.role() != dm_analysis::policy_inputs::PolicyRole::DmSource)
        {
            return Err(std::io::Error::other(
                "purity environment is not an original compiled source",
            ));
        }
        let loaded = super::named_policy::configuration(capture, environment, explicit)?;
        let frame = self
            .policy_revision
            .ok_or_else(|| std::io::Error::other("purity frame unissued"))?;
        let scope = PurityScope {
            snapshot: self,
            tree,
            policy: &loaded.policy,
            policy_key: hash_policy(&loaded.policy, frame, &loaded.selected.path),
        };
        let db = self.native_raw_queries.as_ref().ok_or_else(|| {
            std::io::Error::other("purity current compiler query database unavailable")
        })?;
        scope.validate(db, input).map_err(std::io::Error::other)?;
        operation(db,&scope)
    }
}

#[cfg(test)]
#[path = "runner_query_purity_tests.rs"]
mod tests;
