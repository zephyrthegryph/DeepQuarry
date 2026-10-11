//! Source-neutral modified programs use the same observation store and recipes.
use super::*;
use crate::modified_initializers::ExpressionRecipe;
use dm_codegen_byond::lower_resolver::ResolverProc;

impl InitializerFragments {
    pub(crate) fn modified<R: Resolver>(
        &self,
        key: &receipts::Binding,
        fields: &[(String, dm_syntax::Expr)],
        symbols: &dm_ir::SymbolTable,
        host: &R,
    ) -> Option<(
        crate::InitializerCode,
        Arc<crate::symbolic::InitializerEncoding>,
    )> {
        let value = self.values.lookup(
            &key.key,
            &receipts::Host {
                binding: key,
                resolver: host,
            },
        )?;
        let RetainedCode::Modified { code, encoding } = &value.code else {
            return None;
        };
        if value.recipes.len() != value.root_indexes.len() {
            return None;
        }
        let recorder = crate::lowering_memo::RecordingResolver::new(host);
        let captured = value
            .recipes
            .iter()
            .zip(&value.root_indexes)
            .map(|(recipe, index)| recipe.reissue(&fields.get(*index)?.1, &recorder, symbols))
            .collect::<Option<std::collections::BTreeMap<_, _>>>()?;
        if captured
            .keys()
            .copied()
            .ne(value.references.iter().copied())
        {
            return None;
        }
        let current = if captured.is_empty() {
            crate::InitializerCode::from_admitted_owner(Arc::clone(code), encoding.type_requests())
        } else {
            // Only current descriptor sidecars differ. The existing carrier
            // requires owned ResolverProc here, as for retained assemblies.
            let mut rebound = code.as_ref().clone();
            rebound.modified_instances = captured;
            crate::InitializerCode::from_admitted(rebound, encoding.type_requests())
        };
        self.hits.fetch_add(1, Ordering::Relaxed);
        Some((current, Arc::clone(encoding)))
    }

    pub(crate) fn remember_modified(
        &self,
        key: &receipts::Binding,
        recorder: &crate::lowering_memo::RecordingResolver<'_, impl Resolver>,
        code: &Arc<ResolverProc>,
        fields: &[(String, dm_syntax::Expr)],
    ) -> Option<Arc<crate::symbolic::InitializerEncoding>> {
        let mut recipes = Vec::new();
        let mut root_indexes = Vec::new();
        for (reference, captured) in &code.modified_instances {
            let mut matches = fields.iter().enumerate().filter_map(|(index, (_, root))| {
                ExpressionRecipe::from_capture(*reference, captured, root)
                    .map(|recipe| (index, recipe))
            });
            let Some((index, recipe)) = matches.next() else {
                self.declined.fetch_add(1, Ordering::Relaxed);
                return None;
            };
            if matches.next().is_some() {
                self.declined.fetch_add(1, Ordering::Relaxed);
                return None;
            }
            root_indexes.push(index);
            recipes.push(recipe);
        }
        let references = code.modified_instances.keys().copied().collect();
        let stripped = if code.modified_instances.is_empty() {
            Arc::clone(code)
        } else {
            let mut stripped = code.as_ref().clone();
            stripped.modified_instances.clear();
            Arc::new(stripped)
        };
        let encoding = Arc::new(crate::symbolic::InitializerEncoding::new(code));
        let retained = self.values.insert_with_owned(
            Arc::clone(&key.key),
            receipts::reads(key, recorder.reads()),
            receipts::versions(recorder.domain_receipts()),
            std::mem::size_of::<RetainedFragment>(),
            || RetainedFragment {
                code: RetainedCode::Modified {
                    code: stripped,
                    encoding: Arc::clone(&encoding),
                },
                recipes,
                root_indexes,
                references,
            },
        );
        self.recomputed.fetch_add(1, Ordering::Relaxed);
        retained.and_then(|value| {
            value
                .modified_owners()
                .map(|(_, encoding, _)| Arc::clone(encoding))
        })
    }
}
