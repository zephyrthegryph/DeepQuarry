//! Current-receiver assembled semantic payloads. Current source binding remains
//! the caller's mandatory admission before lookup; no origins are retained.
use crate::modified_initializers::ExpressionRecipe;
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_ir::{Resolver, SymRef, SymbolTable};
use std::sync::atomic::{AtomicU64, Ordering};

pub(super) fn current_keys(
    classified: &crate::initializer_policy::ClassifiedInitializers,
    fragments: &std::collections::HashMap<usize, Vec<u8>>,
) -> Result<Vec<Vec<u8>>, String> {
    classified
        .groups
        .iter()
        .map(|group| {
            let mut key = b"dmbc-initializer-assembly-v1-current-token-roster\0".to_vec();
            match group.receiver {
                Some(receiver) => {
                    key.push(1);
                    key.extend_from_slice(&receiver.bits().to_le_bytes());
                }
                None => key.push(0),
            }
            key.extend_from_slice(&(group.writes.len() as u64).to_le_bytes());
            for &index in &group.writes {
                let write = classified
                    .writes
                    .get(index)
                    .ok_or("initializer assembly write missing")?;
                let fragment = fragments
                    .get(&write.source_ordinal)
                    .ok_or("initializer assembly fragment key missing")?;
                key.extend_from_slice(&(fragment.len() as u64).to_le_bytes());
                key.extend_from_slice(fragment);
                match &write.default {
                    crate::initializer_policy::DefaultValue::Transform(_) => {
                        return Err("folded transform unexpectedly has runtime assembly".into())
                    }
                    crate::initializer_policy::DefaultValue::Scalar(value) => {
                        key.push(0);
                        let bytes = value.canonical_bytes();
                        key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
                        key.extend_from_slice(&bytes);
                    }
                    crate::initializer_policy::DefaultValue::InitializerExpression {
                        token,
                        canonical,
                    } => {
                        key.push(1);
                        key.extend_from_slice(&token.to_le_bytes());
                        key.extend_from_slice(&(canonical.len() as u64).to_le_bytes());
                        key.extend_from_slice(canonical);
                    }
                }
            }
            Ok(key)
        })
        .collect()
}

pub struct InitializerAssemblies {
    values: dm_session::ArtifactStore<RetainedAssembly>,
    pub hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub declined: AtomicU64,
}
pub(crate) struct RetainedAssembly {
    code: ResolverProc,
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
        &ResolverProc,
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
            values: dm_session::ArtifactStore::current_revision(),
            hits: AtomicU64::new(0),
            recomputed: AtomicU64::new(0),
            declined: AtomicU64::new(0),
        }
    }
}
impl InitializerAssemblies {
    pub(crate) fn visit_storage(
        &self,
        visitor: impl FnMut(dm_session::ArtifactStorageView<'_, RetainedAssembly>),
    ) {
        self.values.visit_storage(visitor);
    }
    pub(super) fn retain_keys(&self, keys: &[Vec<u8>]) {
        self.values
            .retain_current_keys(keys.iter().map(Vec::as_slice));
    }
    #[cfg(test)]
    pub(super) fn lookup<R: Resolver>(
        &self,
        key: &[u8],
        roots: &[dm_codegen_byond::initializer::AssignmentView<'_>],
        symbols: &SymbolTable,
        host: &R,
    ) -> Option<ResolverProc> {
        self.lookup_with_encoding(key, roots, symbols, host)
            .map(|(code, _)| code)
    }
    #[cfg(test)]
    pub(super) fn lookup_with_encoding<R: Resolver>(
        &self,
        key: &[u8],
        roots: &[dm_codegen_byond::initializer::AssignmentView<'_>],
        symbols: &SymbolTable,
        host: &R,
    ) -> Option<(
        ResolverProc,
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
    pub(super) fn lookup_with_current_roots<'expr, R: Resolver>(
        &self,
        key: &[u8],
        root_count: usize,
        mut root: impl FnMut(usize) -> Option<std::borrow::Cow<'expr, dm_syntax::Expr>>,
        symbols: &SymbolTable,
        host: &R,
    ) -> Option<(
        ResolverProc,
        std::sync::Arc<crate::symbolic::InitializerEncoding>,
    )> {
        let payload = self.values.lookup(key, host)?;
        if root_count != payload.root_count || payload.recipes.len() != payload.root_indexes.len() {
            return None;
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
            .collect::<Option<std::collections::BTreeMap<_, _>>>()?;
        if captured
            .keys()
            .copied()
            .ne(payload.references.iter().copied())
        {
            self.declined.fetch_add(1, Ordering::Relaxed);
            return None;
        }
        let mut code = payload.code.clone();
        code.modified_instances = captured;
        self.hits.fetch_add(1, Ordering::Relaxed);
        Some((code, std::sync::Arc::clone(&payload.encoding)))
    }
    pub(super) fn remember(
        &self,
        key: &[u8],
        code: &ResolverProc,
        roots: &[dm_codegen_byond::initializer::AssignmentView<'_>],
        recorder: &crate::lowering_memo::RecordingResolver<'_, impl Resolver>,
    ) -> Option<std::sync::Arc<crate::symbolic::InitializerEncoding>> {
        self.recomputed.fetch_add(1, Ordering::Relaxed);
        let mut recipes = Vec::new();
        let mut root_indexes = Vec::new();
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
        let references = code.modified_instances.keys().copied().collect();
        let mut stripped = code.clone();
        stripped.modified_instances.clear();
        let reads = recorder.reads();
        let versions = recorder.domain_receipts();
        // This store retains the current roster without a byte admission budget.
        // Full resident ownership is measured only by the opt-in census.
        let weight = std::mem::size_of::<RetainedAssembly>();
        let encoding = std::sync::Arc::new(crate::symbolic::InitializerEncoding::default());
        self.values
            .insert_with(key.into(), reads, versions, weight, || RetainedAssembly {
                code: stripped,
                recipes,
                root_indexes,
                references,
                root_count: roots.len(),
                encoding: std::sync::Arc::clone(&encoding),
            });
        Some(encoding)
    }
}
#[cfg(test)]
#[path = "initializer_assemblies_tests.rs"]
mod tests;
