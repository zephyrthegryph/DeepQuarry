//! Current-receiver assembled semantic payloads. Current source binding remains
//! the caller's mandatory admission before lookup; no origins are retained.
use super::receipts;
use crate::modified_initializers::ExpressionRecipe;
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_ir::{Resolver, SymRef, SymbolTable};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

pub(super) fn current_keys(
    classified: &crate::initializer_policy::ClassifiedInitializers,
    fragments: &std::collections::HashMap<usize, receipts::Binding>,
) -> Result<Vec<receipts::Binding>, String> {
    let mut duplicates = std::collections::HashMap::<Option<dm_ir::SymbolId>, usize>::new();
    classified
        .groups
        .iter()
        .map(|group| {
            let writes = group
                .writes
                .iter()
                .map(|&index| {
                    let write = classified
                        .writes
                        .get(index)
                        .ok_or("initializer assembly write missing")?;
                    if matches!(
                        write.default,
                        crate::initializer_policy::DefaultValue::Transform(_)
                    ) {
                        return Err("folded transform unexpectedly has runtime assembly".into());
                    }
                    let fragment = fragments
                        .get(&write.source_ordinal)
                        .ok_or("initializer assembly fragment key missing")?;
                    Ok(receipts::GroupWrite {
                        fragment: std::sync::Arc::clone(&fragment.inputs),
                        default: write.default.clone(),
                    })
                })
                .collect::<Result<Vec<_>, String>>()?;
            let duplicate = duplicates.entry(group.receiver).or_default();
            let binding = receipts::Binding::assembly(group.receiver, *duplicate, writes);
            *duplicate += 1;
            Ok(binding)
        })
        .collect()
}

pub struct InitializerAssemblies {
    disk: Option<Arc<super::disk::Transport>>,
    values: receipts::Store<RetainedAssembly>,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub declined: AtomicU64,
    verification_checked: AtomicU64,
    verification_mismatches: AtomicU64,
}
pub(crate) struct RetainedAssembly {
    code: std::sync::Arc<ResolverProc>,
    recipes: Vec<ExpressionRecipe>,
    root_indexes: Vec<usize>,
    references: Vec<SymRef>,
    root_count: usize,
    encoding: std::sync::Arc<crate::symbolic::InitializerEncoding>,
}
impl RetainedAssembly {
    pub(crate) fn encoding(&self) -> &std::sync::Arc<crate::symbolic::InitializerEncoding> {
        &self.encoding
    }

    pub(crate) fn retained_parts(
        &self,
    ) -> (
        &std::sync::Arc<ResolverProc>,
        &Vec<ExpressionRecipe>,
        &Vec<usize>,
        &Vec<SymRef>,
    ) {
        (
            &self.code,
            &self.recipes,
            &self.root_indexes,
            &self.references,
        )
    }
}
pub(super) struct AssemblyHost<'a, R: Resolver> {
    pub original: &'a R,
    pub recorder: Option<&'a crate::lowering_memo::RecordingResolver<'a, R>>,
}
impl<R: Resolver> Resolver for AssemblyHost<'_, R> {
    fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
        // Nested artifact admission must observe each original dependency in
        // the outer recorder. A certified-domain fast hit would otherwise
        // bypass resolve() and lose transitive reads from the assembled owner.
        if self.recorder.is_some() {
            None
        } else {
            self.original.domain_version(domain)
        }
    }
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        match self.recorder {
            Some(recorder) => recorder.resolve(query),
            None => self.original.resolve(query),
        }
    }
}
impl Default for InitializerAssemblies {
    fn default() -> Self {
        Self {
            disk: None,
            values: receipts::Store::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
            verification_checked: AtomicU64::new(0),
            verification_mismatches: AtomicU64::new(0),
        }
    }
}
impl InitializerAssemblies {
    pub(crate) fn with_disk_transport(mut self, disk: Arc<super::disk::Transport>) -> Self {
        self.disk = Some(disk);
        self
    }
    pub(super) fn configure_disk(
        &self,
        context: Option<crate::initializer_policy::ParallelEvaluator<'_>>,
    ) {
        if let Some(disk) = &self.disk {
            disk.configure(context);
        }
    }
    pub(crate) fn visit_disk_storage(&self, visit: impl FnMut(usize, usize, usize)) {
        if let Some(disk) = &self.disk {
            disk.visit_storage(visit);
        }
    }
    pub(crate) fn for_request(&self, publishable: bool) -> Arc<Self> {
        Arc::new(Self {
            disk: self.disk.clone(),
            values: self.values.for_request(publishable),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
            verification_checked: AtomicU64::new(0),
            verification_mismatches: AtomicU64::new(0),
        })
    }
    /// Request-scoped assembly verification only.
    pub fn assembly_verification_counts(&self) -> (u64, u64) {
        (
            self.verification_checked.load(Ordering::Relaxed),
            self.verification_mismatches.load(Ordering::Relaxed),
        )
    }
    pub(crate) fn publish_successful(&self) -> bool {
        self.values.publish_successful()
    }

    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(receipts::Storage<'_, RetainedAssembly>),
    ) {
        self.values.visit_storage(visitor);
    }
    pub(super) fn retain_keys(&self, keys: &[receipts::Binding]) {
        self.values
            .retain_current_keys(keys.iter().map(|binding| binding.key.as_ref()));
    }
    #[cfg(test)]
    pub(super) fn lookup<R: Resolver>(
        &self,
        key: &receipts::Binding,
        roots: &[dm_codegen_byond::initializer::AssignmentView<'_>],
        symbols: &SymbolTable,
        host: &R,
    ) -> Option<ResolverProc> {
        self.lookup_with_encoding(key, roots, symbols, host)
            .map(|(code, _)| code.as_ref().clone())
    }
    #[cfg(test)]
    pub(super) fn lookup_with_encoding<R: Resolver>(
        &self,
        key: &receipts::Binding,
        roots: &[dm_codegen_byond::initializer::AssignmentView<'_>],
        symbols: &SymbolTable,
        host: &R,
    ) -> Option<(
        crate::InitializerCode,
        std::sync::Arc<crate::symbolic::InitializerEncoding>,
    )> {
        self.lookup_with_current_roots(
            key,
            roots.len(),
            |index| {
                roots
                    .get(index)
                    .map(|root| std::borrow::Cow::Borrowed(root.value))
            },
            symbols,
            host,
        )
    }
    #[cfg(test)]
    pub(super) fn lookup_with_current_roots<'expr, R: Resolver>(
        &self,
        key: &receipts::Binding,
        root_count: usize,
        root: impl FnMut(usize) -> Option<std::borrow::Cow<'expr, dm_syntax::Expr>>,
        symbols: &SymbolTable,
        host: &R,
    ) -> Option<(
        crate::InitializerCode,
        std::sync::Arc<crate::symbolic::InitializerEncoding>,
    )> {
        self.lookup_with_current_roots_verified(key, root_count, root, symbols, host, None)
            .ok()
            .flatten()
    }
    #[allow(clippy::type_complexity)]
    pub(super) fn lookup_with_current_roots_verified<'expr, R: Resolver>(
        &self,
        key: &receipts::Binding,
        root_count: usize,
        mut root: impl FnMut(usize) -> Option<std::borrow::Cow<'expr, dm_syntax::Expr>>,
        symbols: &SymbolTable,
        host: &R,
        mut verify: Option<
            &mut dyn FnMut(
                &super::fragments::verify::Receipt,
                &crate::InitializerCode,
            )
                -> Result<(), dm_codegen_byond::initializer::InitializerError>,
        >,
    ) -> Result<
        Option<(
            crate::InitializerCode,
            Arc<crate::symbolic::InitializerEncoding>,
        )>,
        dm_codegen_byond::initializer::InitializerError,
    > {
        let admission_host = receipts::Host {
            binding: key,
            resolver: host,
        };
        let mut accepted = verify
            .as_ref()
            .and_then(|_| self.values.lookup_accepted(&key.key, &admission_host));
        let mut payload = if verify.is_some() {
            accepted.as_ref().map(|value| Arc::clone(&value.value))
        } else {
            self.values.lookup(&key.key, &admission_host)
        };
        if payload.is_none() {
            if let Some(disk) = &self.disk {
                // Disk-only misses borrow current expressions to authenticate the
                // complete classification recipe. Resident hits remain lazy.
                let roots = (0..root_count).map(&mut root).collect::<Option<Vec<_>>>();
                if let Some(roots) = roots {
                    let refs = roots.iter().map(|r| r.as_ref()).collect::<Vec<_>>();
                    if let Some((code, semantic_reads, modified)) =
                        disk.lookup(key, &refs, host, symbols)
                    {
                        let (root_indexes, recipes): (Vec<_>, Vec<_>) =
                            modified.into_iter().unzip();
                        let references = recipes.iter().map(|recipe| recipe.reference()).collect();
                        let code = Arc::new(code);
                        let encoding = Arc::new(crate::symbolic::InitializerEncoding::new(&code));
                        self.values.insert_with(
                            Arc::clone(&key.key),
                            receipts::reads(key, semantic_reads),
                            Vec::new(),
                            std::mem::size_of::<RetainedAssembly>(),
                            || RetainedAssembly {
                                code,
                                encoding,
                                recipes,
                                root_indexes,
                                references,
                                root_count,
                            },
                        );
                        if verify.is_some() {
                            accepted = self.values.lookup_accepted(&key.key, &admission_host);
                            payload = accepted.as_ref().map(|a| Arc::clone(&a.value));
                        } else {
                            payload = self.values.lookup(&key.key, &admission_host);
                        }
                    }
                }
            }
        }
        let Some(payload) = payload else {
            return Ok(None);
        };
        if root_count != payload.root_count || payload.recipes.len() != payload.root_indexes.len() {
            return Ok(None);
        }
        let recorder = crate::lowering_memo::RecordingResolver::new(host);
        let captured = payload
            .recipes
            .iter()
            .zip(&payload.root_indexes)
            .map(|(recipe, index)| {
                let current = root(*index)?;
                recipe.reissue(current.as_ref(), &recorder, symbols)
            })
            .collect::<Option<std::collections::BTreeMap<_, _>>>();
        let Some(captured) = captured else {
            return Ok(None);
        };
        if captured
            .keys()
            .copied()
            .ne(payload.references.iter().copied())
        {
            self.declined.fetch_add(1, Ordering::Relaxed);
            return Ok(None);
        }
        let code = if captured.is_empty() {
            crate::InitializerCode::from_admitted_owner(
                std::sync::Arc::clone(&payload.code),
                payload.encoding.type_requests(),
            )
        } else {
            let mut code = payload.code.as_ref().clone();
            code.modified_instances = captured;
            crate::InitializerCode::from_admitted(code, payload.encoding.type_requests())
        };
        if let (Some(verify), Some(accepted)) = (verify.as_mut(), accepted.as_ref()) {
            self.verification_checked.fetch_add(1, Ordering::Relaxed);
            if let Err(error) = verify(&accepted.reads, &code) {
                self.verification_mismatches.fetch_add(1, Ordering::Relaxed);
                return Err(error);
            }
        }
        self.hits.fetch_add(1, Ordering::Relaxed);
        Ok(Some((code, std::sync::Arc::clone(&payload.encoding))))
    }
    #[cfg(test)]
    pub(super) fn remember_with_recipes(
        &self,
        key: &receipts::Binding,
        code: &ResolverProc,
        roots: &[dm_codegen_byond::initializer::AssignmentView<'_>],
        recorder: &crate::lowering_memo::RecordingResolver<'_, impl Resolver>,
        admitted: Option<Vec<(usize, ExpressionRecipe)>>,
    ) -> Option<std::sync::Arc<crate::symbolic::InitializerEncoding>> {
        self.remember_shared_with_recipes(
            key,
            &std::sync::Arc::new(code.clone()),
            roots,
            recorder,
            admitted,
        )
    }
    pub(super) fn remember_shared_with_recipes(
        &self,
        key: &receipts::Binding,
        code: &std::sync::Arc<ResolverProc>,
        roots: &[dm_codegen_byond::initializer::AssignmentView<'_>],
        recorder: &crate::lowering_memo::RecordingResolver<'_, impl Resolver>,
        admitted: Option<Vec<(usize, ExpressionRecipe)>>,
    ) -> Option<std::sync::Arc<crate::symbolic::InitializerEncoding>> {
        self.recomputed.fetch_add(1, Ordering::Relaxed);
        let mut recipes = Vec::new();
        let mut root_indexes = Vec::new();
        if let Some(admitted) = admitted {
            if admitted
                .iter()
                .map(|(_, recipe)| recipe.reference())
                .ne(code.modified_instances.keys().copied())
                || admitted.iter().any(|(index, _)| *index >= roots.len())
            {
                self.declined.fetch_add(1, Ordering::Relaxed);
                return None;
            }
            for (index, recipe) in admitted {
                root_indexes.push(index);
                recipes.push(recipe);
            }
        } else {
            for (reference, captured) in &code.modified_instances {
                let matches: Vec<_> = roots
                    .iter()
                    .enumerate()
                    .filter_map(|(index, root)| {
                        ExpressionRecipe::from_capture(*reference, captured, root.value)
                            .map(|recipe| (index, recipe))
                    })
                    .collect();
                if matches.len() != 1 {
                    self.declined.fetch_add(1, Ordering::Relaxed);
                    return None;
                }
                let (index, recipe) = matches.into_iter().next().unwrap();
                root_indexes.push(index);
                recipes.push(recipe);
            }
        }
        let references = code.modified_instances.keys().copied().collect();
        let stripped = if code.modified_instances.is_empty() {
            std::sync::Arc::clone(code)
        } else {
            let mut stripped = code.as_ref().clone();
            stripped.modified_instances.clear();
            std::sync::Arc::new(stripped)
        };
        let semantic_reads = recorder.reads();
        if let Some(disk) = &self.disk {
            let roots = roots.iter().map(|root| root.value).collect::<Vec<_>>();
            disk.stage(key, &roots, &semantic_reads, code);
        }
        let reads = receipts::reads(key, semantic_reads);
        let versions = receipts::versions(recorder.domain_receipts());
        // This store retains the current roster without a byte admission budget.
        // Full resident ownership is measured only by the opt-in census.
        let weight = std::mem::size_of::<RetainedAssembly>();
        let encoding = std::sync::Arc::new(crate::symbolic::InitializerEncoding::new(code));
        self.values.insert_with(
            std::sync::Arc::clone(&key.key),
            reads,
            versions,
            weight,
            || RetainedAssembly {
                code: stripped,
                recipes,
                root_indexes,
                references,
                root_count: roots.len(),
                encoding: std::sync::Arc::clone(&encoding),
            },
        );
        Some(encoding)
    }
}
#[cfg(test)]
#[path = "initializer_assemblies_tests.rs"]
mod tests;
