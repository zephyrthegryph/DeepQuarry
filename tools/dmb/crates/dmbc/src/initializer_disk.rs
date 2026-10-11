//! Optional transport into the SAME observed fragment/assembly stores.
//! Current classification/source inputs are reissued before this adapter runs.
//! Uncovered recipes and failures execute the same shared producer.
use super::{disk_recipe, receipts};
use crate::runner_disk::LazyDisk;
use dm_ir::Resolver;
use std::{
    cell::RefCell,
    sync::{Arc, OnceLock},
};
pub(super) const LIMIT: usize = crate::lowering_memo_wire::initializer::LIMIT;
struct Policy {
    bytes: Arc<[u8]>,
    engine: Option<(u128, bool, u128)>,
    engine_record: Option<dm_cache::Record>,
}
pub(crate) struct Transport {
    disk: Arc<LazyDisk>,
    engine: Option<Arc<crate::runner_host::EnginePayload>>,
    memo_policy: u128,
    writable: bool,
    policy: OnceLock<Option<Policy>>,
    engine_admitted: OnceLock<bool>,
    engine_staged: OnceLock<()>,
}
impl Transport {
    pub(crate) fn new(
        disk: Arc<LazyDisk>,
        engine: Option<Arc<crate::runner_host::EnginePayload>>,
        memo_policy: u128,
        writable: bool,
    ) -> Arc<Self> {
        Arc::new(Self {
            disk,
            engine,
            memo_policy,
            writable,
            policy: OnceLock::new(),
            engine_admitted: OnceLock::new(),
            engine_staged: OnceLock::new(),
        })
    }
    pub(super) fn configure(
        &self,
        current: Option<crate::initializer_policy::ParallelEvaluator<'_>>,
    ) {
        self.policy.get_or_init(|| {
            let current = current?;
            let bytes = current
                .factory
                .immutable_initializer_policy_bytes_for_engine(current.engine)?;
            let (engine, engine_record) = match (&self.engine, current.engine) {
                (None, None) => (None, None),
                (Some(owner), Some(snapshot)) if std::ptr::eq(&owner.snapshot, snapshot) => {
                    let (_, schema, bootstrap, compiler) = owner.disk_abi_authority();
                    let record = crate::driver_facts::initializer_engine_record(
                        owner,
                        self.memo_policy,
                        &bytes,
                    )?;
                    (Some((schema, bootstrap, compiler)), Some(record))
                }
                _ => return None,
            };
            Some(Policy {
                bytes,
                engine,
                engine_record,
            })
        });
    }
    fn recipe(
        &self,
        key: &receipts::Binding,
        roots: &[&dm_syntax::Expr],
        modified_policy: Option<&[u8]>,
    ) -> Option<disk_recipe::Recipe> {
        let policy = self.policy.get()?.as_ref()?;
        let mut recipe = disk_recipe::capture_with_modified_policy(
            key,
            &policy.bytes,
            policy.engine,
            roots,
            modified_policy,
        )?;
        // Caller semantic policy remains a partition, in addition to the exact
        // portable factory/engine proof. It never licenses admission alone.
        let mut bytes = b"initializer-transport-policy-v1".to_vec();
        bytes.extend_from_slice(&self.memo_policy.to_le_bytes());
        bytes.extend_from_slice(&recipe.bytes);
        recipe.bytes = bytes;
        Some(recipe)
    }
    fn engine_matches(&self) -> bool {
        *self.engine_admitted.get_or_init(|| {
            let Some(policy) = self.policy.get().and_then(Option::as_ref) else {
                return false;
            };
            let Some(record) = &policy.engine_record else {
                return true;
            };
            self.disk
                .snapshot()
                .and_then(|snapshot| {
                    snapshot.get_candidate(record.key, |bytes, symbols| {
                        if !symbols.is_empty() {
                            return Err("initializer engine spelling sidecar".into());
                        }
                        crate::driver_facts::admit_initializer_engine_bucket(bytes, &record.payload)
                    })
                })
                .is_some()
        })
    }
    fn key(recipe: &disk_recipe::Recipe) -> dm_cache::RecordKey {
        dm_cache::RecordKey {
            stage: if recipe.assembly { 12 } else { 11 },
            version: 4,
            content: xxhash_rust::xxh3::xxh3_128(&recipe.bytes),
        }
    }
    pub(super) fn lookup<R: Resolver>(
        &self,
        key: &receipts::Binding,
        roots: &[&dm_syntax::Expr],
        host: &R,
        symbols: &dm_ir::SymbolTable,
    ) -> Option<(
        dm_codegen_byond::lower_resolver::ResolverProc,
        Vec<dm_session::ResolverRead>,
        Vec<(usize, crate::modified_initializers::ExpressionRecipe)>,
    )> {
        self.lookup_with_modified_policy(key, roots, host, symbols, None)
    }
    pub(super) fn lookup_with_modified_policy<R: Resolver>(
        &self,
        key: &receipts::Binding,
        roots: &[&dm_syntax::Expr],
        host: &R,
        symbols: &dm_ir::SymbolTable,
        modified_policy: Option<&[u8]>,
    ) -> Option<(
        dm_codegen_byond::lower_resolver::ResolverProc,
        Vec<dm_session::ResolverRead>,
        Vec<(usize, crate::modified_initializers::ExpressionRecipe)>,
    )> {
        let recipe = self.recipe(key, roots, modified_policy)?;
        if !self.engine_matches() {
            return None;
        }
        let snapshot = self.disk.snapshot()?;
        let accepted = RefCell::new(None);
        snapshot.get_candidate(Self::key(&recipe), |bytes, spelling_sidecar| {
            if !spelling_sidecar.is_empty() {
                return Err("initializer unexpected spelling sidecar".into());
            }
            let candidates = Self::current_candidates(bytes, &recipe)?;
            // All matching rows must select a current issued typed node before
            // even the first semantic query/factory callback can run.
            for candidate in &candidates {
                if candidate.recipe == recipe.bytes
                    && candidate.modified.iter().any(|(index, recipe)| {
                        roots
                            .get(*index)
                            .is_none_or(|root| !recipe.accepts_current_path(root))
                    })
                {
                    return Err("initializer modified path differs from current issued AST".into());
                }
            }
            for candidate in candidates.into_iter().rev() {
                if candidate.recipe != recipe.bytes {
                    continue;
                }
                let recorder = crate::lowering_memo::RecordingResolver::new(host);
                if !candidate.reads.iter().all(|(query, expected)| {
                    let value = recorder.resolve(*query);
                    crate::lowering_memo_wire::initializer::portable(&value)
                        && value.canonical_bytes() == *expected
                }) {
                    continue;
                }
                if candidate.modified.iter().any(|(index, recipe)| {
                    roots
                        .get(*index)
                        .and_then(|root| recipe.reissue(root, &recorder, symbols))
                        .is_none()
                }) {
                    continue;
                }
                *accepted.borrow_mut() =
                    Some((candidate.code, recorder.reads(), candidate.modified));
                return Ok(true);
            }
            Ok(false)
        })?;
        accepted.into_inner()
    }
    fn current_candidates(
        bytes: &[u8],
        recipe: &disk_recipe::Recipe,
    ) -> Result<Vec<crate::lowering_memo_wire::initializer::Candidate>, String> {
        let candidates = crate::lowering_memo_wire::initializer::decode_bucket(bytes)?;
        // Mandatory current queries are derived from the real issued write,
        // never accepted from a disk-provided list. Validate before callbacks.
        for candidate in &candidates {
            if candidate.recipe == recipe.bytes
                && (candidate.mandatory != recipe.mandatory
                    || candidate.assembly != recipe.assembly
                    || candidate.modified_only != recipe.modified_only
                    || candidate.roots != recipe.roots)
            {
                return Err("initializer mandatory current receipt/placement missing".into());
            }
        }
        Ok(candidates)
    }
    pub(super) fn stage(
        &self,
        key: &receipts::Binding,
        roots: &[&dm_syntax::Expr],
        reads: &[dm_session::ResolverRead],
        code: &dm_codegen_byond::lower_resolver::ResolverProc,
    ) {
        self.stage_with_modified_policy(key, roots, reads, code, None);
    }
    pub(super) fn stage_with_modified_policy(
        &self,
        key: &receipts::Binding,
        roots: &[&dm_syntax::Expr],
        reads: &[dm_session::ResolverRead],
        code: &dm_codegen_byond::lower_resolver::ResolverProc,
        modified_policy: Option<&[u8]>,
    ) {
        if !self.writable {
            return;
        }
        let Some(recipe) = self.recipe(key, roots, modified_policy) else {
            return;
        };
        let mut modified = Vec::new();
        for (reference, captured) in &code.modified_instances {
            if captured.descriptor.resource_context().is_some()
                || captured.descriptor.requires_captured_resources()
            {
                return;
            }
            let Some(origin) = captured.origin else {
                return;
            };
            let Some(index) = (origin as usize).checked_sub(usize::from(recipe.modified_only))
            else {
                return;
            };
            let Some(root) = roots.get(index) else {
                return;
            };
            let Some(evidence) = crate::modified_initializers::ExpressionRecipe::from_capture(
                *reference, captured, root,
            )
            .and_then(|recipe| recipe.disk_evidence()) else {
                return;
            };
            modified.push((index, evidence));
        }
        let mut stripped = code.clone();
        stripped.modified_instances.clear();
        let Some(bytes) = crate::lowering_memo_wire::initializer::encode_current_program(
            recipe.bytes.clone(),
            recipe.assembly,
            recipe.roots,
            recipe.mandatory.clone(),
            reads,
            &stripped,
            modified,
            recipe.modified_only,
        ) else {
            return;
        };
        // The same cache spool and terminal request publication own every record.
        if let Some(record) = self
            .policy
            .get()
            .and_then(Option::as_ref)
            .and_then(|p| p.engine_record.as_ref())
        {
            self.engine_staged
                .get_or_init(|| self.append(vec![record.clone()]));
        }
        self.append(vec![dm_cache::Record {
            key: Self::key(&recipe),
            symbols: Vec::new(),
            payload: bytes.into(),
        }]);
    }
    fn append(&self, records: Vec<dm_cache::Record>) {
        let records = records
            .into_iter()
            .map(|mut record| {
                record.payload = dm_cache::encode_variants(&[record.payload.to_vec()])?.into();
                Ok(record)
            })
            .collect::<Result<Vec<_>, String>>();
        if let Err(error) = records.and_then(|records| self.disk.append_records(records)) {
            crate::daemon_eprintln!(
                "native initializer cache staging unavailable: {error}; using current result"
            );
        }
    }
    /// Inline/accessible buffers only; shared engine/LazyDisk owners have existing
    /// census routes. Arc control blocks and OnceLock internals remain unknown.
    pub(super) fn visit_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        visit(
            self as *const Self as usize,
            std::mem::size_of::<Self>(),
            std::mem::size_of::<Self>(),
        );
        if let Some(policy) = self.policy.get().and_then(Option::as_ref) {
            visit(
                policy.bytes.as_ptr() as usize,
                policy.bytes.len(),
                policy.bytes.len(),
            );
            if let Some(record) = &policy.engine_record {
                visit(
                    record.payload.as_ptr() as usize,
                    record.payload.len(),
                    record.payload.len(),
                );
            }
        }
    }
}

#[cfg(test)]
#[path = "initializer_disk_tests.rs"]
mod tests;
