//! Source-neutral modified programs use the same observation store and recipes.
use super::*;
use crate::modified_initializers::ExpressionRecipe;
use dm_codegen_byond::lower_resolver::ResolverProc;

impl InitializerFragments {
    #[cfg(test)]
    pub(crate) fn modified<R: Resolver>(
        &self,
        key: &receipts::Binding,
        symbols: &dm_ir::SymbolTable,
        host: &R,
        root: impl FnMut(usize) -> Option<Arc<dm_syntax::Expr>>,
    ) -> Option<(
        crate::InitializerCode,
        Arc<crate::symbolic::InitializerEncoding>,
    )> {
        self.modified_verified(key, symbols, host, root, None)
            .ok()
            .flatten()
    }
    #[allow(clippy::type_complexity)]
    pub(crate) fn modified_verified<R: Resolver>(
        &self,
        key: &receipts::Binding,
        symbols: &dm_ir::SymbolTable,
        host: &R,
        root: impl FnMut(usize) -> Option<Arc<dm_syntax::Expr>>,
        verify: Option<
            &mut dyn FnMut(
                &verify::Receipt,
                &crate::InitializerCode,
            ) -> Result<(), InitializerError>,
        >,
    ) -> Result<
        Option<(
            crate::InitializerCode,
            Arc<crate::symbolic::InitializerEncoding>,
        )>,
        InitializerError,
    > {
        self.modified_verified_with_disk(key, symbols, host, root, verify, 0, None)
    }
    #[allow(clippy::too_many_arguments, clippy::type_complexity)]
    pub(crate) fn modified_verified_with_disk<R: Resolver>(
        &self,
        key: &receipts::Binding,
        symbols: &dm_ir::SymbolTable,
        host: &R,
        root: impl FnMut(usize) -> Option<Arc<dm_syntax::Expr>>,
        verify: Option<
            &mut dyn FnMut(
                &verify::Receipt,
                &crate::InitializerCode,
            ) -> Result<(), InitializerError>,
        >,
        root_count: usize,
        modified_policy: Option<&[u8]>,
    ) -> Result<
        Option<(
            crate::InitializerCode,
            Arc<crate::symbolic::InitializerEncoding>,
        )>,
        InitializerError,
    > {
        self.modified_verified_with_attempt(
            key,
            symbols,
            host,
            root,
            verify,
            root_count,
            modified_policy,
            &mut crate::initializer_lowering::disk::TransportAttempt::default(),
        )
    }
    #[allow(clippy::too_many_arguments, clippy::type_complexity)]
    pub(crate) fn modified_verified_with_attempt<R: Resolver>(
        &self,
        key: &receipts::Binding,
        symbols: &dm_ir::SymbolTable,
        host: &R,
        mut root: impl FnMut(usize) -> Option<Arc<dm_syntax::Expr>>,
        mut verify: Option<
            &mut dyn FnMut(
                &verify::Receipt,
                &crate::InitializerCode,
            ) -> Result<(), InitializerError>,
        >,
        root_count: usize,
        modified_policy: Option<&[u8]>,
        disk_attempt: &mut crate::initializer_lowering::disk::TransportAttempt,
    ) -> Result<
        Option<(
            crate::InitializerCode,
            Arc<crate::symbolic::InitializerEncoding>,
        )>,
        InitializerError,
    > {
        let admission_host = receipts::Host {
            binding: key,
            resolver: host,
        };
        let mut accepted = verify
            .as_ref()
            .and_then(|_| self.values.lookup_accepted(&key.key, &admission_host));
        let mut candidate = if verify.is_some() {
            accepted.as_ref().map(|value| Arc::clone(&value.value))
        } else {
            self.values.lookup(&key.key, &admission_host)
        };
        if candidate.is_none() && modified_policy.is_some() {
            if let Some(disk) = &self.disk {
                let roots = (0..root_count).map(&mut root).collect::<Option<Vec<_>>>();
                if let Some(roots) = roots {
                    let refs = roots.iter().map(|r| r.as_ref()).collect::<Vec<_>>();
                    if let Some((code, reads, modified)) = disk.lookup_attempt(
                        key,
                        &refs,
                        host,
                        symbols,
                        modified_policy,
                        disk_attempt,
                    ) {
                        let (root_indexes, recipes): (Vec<_>, Vec<_>) =
                            modified.into_iter().unzip();
                        let references = recipes.iter().map(|r| r.reference()).collect();
                        let code = Arc::new(code);
                        let encoding = Arc::new(crate::symbolic::InitializerEncoding::new(&code));
                        self.values.insert_with(
                            Arc::clone(&key.key),
                            receipts::reads(key, reads),
                            Vec::new(),
                            std::mem::size_of::<RetainedFragment>(),
                            || RetainedFragment {
                                code: RetainedCode::Modified { code, encoding },
                                recipes,
                                references,
                                root_indexes,
                            },
                        );
                        // Transport never returns directly: current Input and all
                        // canonical semantic reads enter the SAME admission path.
                        if verify.is_some() {
                            accepted = self.values.lookup_accepted(&key.key, &admission_host);
                            candidate = accepted.as_ref().map(|a| Arc::clone(&a.value));
                        } else {
                            candidate = self.values.lookup(&key.key, &admission_host);
                        }
                    }
                }
            }
        }
        let Some(value) = candidate else {
            return Ok(None);
        };
        let RetainedCode::Modified { code, encoding } = &value.code else {
            return Ok(None);
        };
        if value.recipes.len() != value.root_indexes.len() {
            return Ok(None);
        }
        let recorder = crate::lowering_memo::RecordingResolver::new(host);
        let captured = value
            .recipes
            .iter()
            .zip(&value.root_indexes)
            .map(|(recipe, index)| {
                let current = root(*index)?;
                recipe.reissue(&current, &recorder, symbols)
            })
            .collect::<Option<std::collections::BTreeMap<_, _>>>();
        let Some(captured) = captured else {
            return Ok(None);
        };
        if captured
            .keys()
            .copied()
            .ne(value.references.iter().copied())
        {
            return Ok(None);
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
        if let (Some(verify), Some(accepted)) = (verify.as_mut(), accepted.as_ref()) {
            self.modified_verification_checked
                .fetch_add(1, Ordering::Relaxed);
            if let Err(error) = verify(&accepted.reads, &current) {
                self.modified_verification_mismatches
                    .fetch_add(1, Ordering::Relaxed);
                return Err(error);
            }
        }
        self.hits.fetch_add(1, Ordering::Relaxed);
        Ok(Some((current, Arc::clone(encoding))))
    }

    pub(crate) fn remember_modified(
        &self,
        key: &receipts::Binding,
        recorder: &crate::lowering_memo::RecordingResolver<'_, impl Resolver>,
        code: &Arc<ResolverProc>,
        fields: &[(String, dm_syntax::Expr)],
    ) -> Option<Arc<crate::symbolic::InitializerEncoding>> {
        self.remember_modified_with_disk(key, recorder, code, fields, None)
    }
    pub(crate) fn remember_modified_with_disk(
        &self,
        key: &receipts::Binding,
        recorder: &crate::lowering_memo::RecordingResolver<'_, impl Resolver>,
        code: &Arc<ResolverProc>,
        fields: &[(String, dm_syntax::Expr)],
        modified_policy: Option<&[u8]>,
    ) -> Option<Arc<crate::symbolic::InitializerEncoding>> {
        self.remember_modified_with_attempt(
            key,
            recorder,
            code,
            fields,
            modified_policy,
            &mut crate::initializer_lowering::disk::TransportAttempt::default(),
        )
    }
    pub(crate) fn remember_modified_with_attempt(
        &self,
        key: &receipts::Binding,
        recorder: &crate::lowering_memo::RecordingResolver<'_, impl Resolver>,
        code: &Arc<ResolverProc>,
        fields: &[(String, dm_syntax::Expr)],
        modified_policy: Option<&[u8]>,
        disk_attempt: &mut crate::initializer_lowering::disk::TransportAttempt,
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
        if modified_policy.is_some() {
            if let Some(disk) = &self.disk {
                let roots = fields.iter().map(|(_, root)| root).collect::<Vec<_>>();
                disk.stage_attempt(
                    key,
                    &roots,
                    &recorder.reads(),
                    code,
                    modified_policy,
                    disk_attempt,
                );
            }
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
