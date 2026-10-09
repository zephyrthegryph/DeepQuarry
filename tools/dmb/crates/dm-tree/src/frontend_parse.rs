use super::*;

pub(super) struct ParsedDeclarations {
    pub(super) syntax: DeclarationSyntax,
    pub(super) diagnostics: Vec<(usize, dm_syntax::Diagnostic)>,
    pub(super) adapted: crate::SharedAdaptedDeclarations,
    pub(super) allocation_ledger: crate::allocation_ledger::AllocationLedger,
    pub(super) declaration_errors: Vec<crate::AdapterError>,
    pub(super) reuse_stats: DeclarationReuseStats,
}

/// Grammar-safe descriptor discovery is serial; lexing/parsing is bounded by
/// worker count and two descriptors per worker in each joined batch. Workers
/// discard executable AST children before returning their compact declarations.
#[cfg(test)]
pub(super) fn parse_declarations(
    expanded: &ExpandedRegions,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
) -> Result<ParsedDeclarations, Vec<Diagnostic>> {
    let executor = dm_exec::BuildExecutor::new(config.workers).map_err(|error| {
        vec![internal(&format!(
            "declaration executor creation failed: {error}"
        ))]
    })?;
    parse_declarations_with_executor(expanded, config, memo, &executor)
}

#[cfg(test)]
pub(super) fn parse_declarations_with_executor(
    expanded: &ExpandedRegions,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
    executor: &dm_exec::BuildExecutor,
) -> Result<ParsedDeclarations, Vec<Diagnostic>> {
    parse_declarations_with_state(expanded, config, memo, executor, None)
}

pub(super) fn parse_declarations_with_state(
    expanded: &ExpandedRegions,
    config: FrontendConfig<'_>,
    memo: Option<&dyn dm_preprocess::regions::ExpansionMemo>,
    executor: &dm_exec::BuildExecutor,
    retained: Option<&super::declaration_state::RetainedDeclarations>,
) -> Result<ParsedDeclarations, Vec<Diagnostic>> {
    let source = expanded.text.as_ref();
    let parse_start = Instant::now();
    let profile_scan = dm_profile::stage("frontend.grammar_scan");
    let retained_descriptors = retained
        .map(|state| state.grammar.discover(expanded))
        .transpose()
        .map_err(|message| vec![internal(message)])?;
    let mut fresh_chunks = Vec::new();
    if retained_descriptors.is_none() {
        let report = dm_syntax::for_each_stable_source_chunk(
            source,
            source.len().max(1),
            32,
            |text, offset| fresh_chunks.push((offset, text.len())),
        );
        if report.skipped_declarations != 0 {
            return Err(vec![internal("grammar chunker omitted a declaration")]);
        }
    }
    let chunks = retained_descriptors
        .as_ref()
        .map_or(fresh_chunks.as_slice(), |roster| roster.spans().as_slice());
    let descriptor_scan = parse_start.elapsed();
    drop(profile_scan);
    let retained_keys = retained.map(|state| {
        let keys: Vec<_> = chunks
            .iter()
            .map(|&(offset, len)| {
                super::declaration_state::RetainedDeclarations::key(&source[offset..offset + len])
            })
            .collect();
        state.retain(&keys);
        keys
    });
    let region_hits = std::sync::atomic::AtomicUsize::new(0);
    let independent_hits = std::sync::atomic::AtomicUsize::new(0);
    let facts_hits = std::sync::atomic::AtomicUsize::new(0);
    let parsed_chunks = std::sync::atomic::AtomicUsize::new(0);
    let lookup_ns = std::sync::atomic::AtomicU64::new(0);
    let facts_ns = std::sync::atomic::AtomicU64::new(0);
    let worker_count = executor.workers().min(chunks.len().max(1));
    let mut syntax_chunks = Vec::new();
    let mut diagnostics = Vec::new();
    // One bounded pool for the complete capture. Workers claim whole grammar-
    // safe descriptors; completion order never determines declaration identity.
    let next = std::sync::atomic::AtomicUsize::new(0);
    let parse = || {
        executor.scope(|scope| {
        let (sender, receiver) = std::sync::mpsc::sync_channel(worker_count * 2);
        for _ in 0..worker_count {
                    let sender = sender.clone();
                    let chunks = &chunks;
                    let retained_keys = &retained_keys;
                    let next = &next;
                    let (
                        region_hits,
                        independent_hits,
                        facts_hits,
                        parsed_chunks,
                        lookup_ns,
                        facts_ns,
                    ) = (
                        &region_hits,
                        &independent_hits,
                        &facts_hits,
                        &parsed_chunks,
                        &lookup_ns,
                        &facts_ns,
                    );
                    scope.spawn(move |_| {
                        let _profile_worker = dm_profile::stage("frontend.declaration_parsing");
                        loop {
                            let index = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                            let Some(&(offset, len)) = chunks.get(index) else {
                                break;
                            };
                            let text = &source[offset..offset + len];
                            if let Some(current) = retained.zip(retained_keys.as_ref())
                                .and_then(|(state, keys)| state.get_shared(&keys[index], text, offset)) {
                                facts_hits.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                                if sender.send((index, offset, Vec::new(), None, Ok(current))).is_err() { break; }
                                continue;
                            }
                            let lookup_start = Instant::now();
                            let profile_lookup =
                                dm_profile::item("frontend.fragment_lookup_decode_parse");
                            let receipt_index = expanded
                                .receipts
                                .partition_point(|receipt| receipt.output_span().end <= offset);
                            let receipt = expanded.receipts.get(receipt_index).filter(|receipt| {
                                receipt.output_span().start <= offset
                                    && offset + len <= receipt.output_span().end
                            });
                            let relative = receipt.map(|receipt| {
                                dm_syntax::Span::new(
                                    offset - receipt.output_span().start,
                                    offset + len - receipt.output_span().start,
                                )
                            });
                            let cached = receipt
                                .zip(relative)
                                .and_then(|(receipt, span)| {
                                    receipt.record().fragment(parserwire::VERSION, span)
                                })
                                .and_then(|bytes| parserwire::decode_with_facts(bytes, text));
                            if cached.is_some() {
                                region_hits.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                            }
                            let independent = if cached.is_none() {
                                memo.and_then(|memo| {
                                    let key = dm_preprocess::regions::FragmentRecord::lookup_key(
                                        parserwire::VERSION,
                                        text,
                                    );
                                    let mut accepted = None;
                                    memo.visit_fragment_candidates(key, &mut |record| {
                                        if !record.matches(parserwire::VERSION, text) { return false; }
                                        accepted = parserwire::decode_with_facts(record.payload(), text);
                                        accepted.is_some()
                                    });
                                    accepted
                                })
                            } else {
                                None
                            };
                            let independent_hit = independent.is_some();
                            if independent_hit {
                                independent_hits.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                            }
                            let cached = cached.or(independent);
                            let cached_fragment_hit = cached.is_some();
                            let (mut parsed, errors, cached_facts) = match cached {
                                Some((items, errors, facts)) => (items, errors, facts),
                                None => {
                                    parsed_chunks
                                        .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                                    let ast = dm_syntax::parse_declaration_skeleton(text);
                                    // Without an issued contained-region receipt, preserve
                                    // the original one-pass cold compaction/rebase path.
                                    let items = compact_declarations(
                                        ast.items,
                                        if receipt.is_some() || independent_hit {
                                            0
                                        } else {
                                            offset
                                        },
                                    );
                                    (items, ast.diagnostics, None)
                                }
                            };
                            if receipt.is_some() || independent_hit {
                                shift_items(&mut parsed, offset);
                            }
                            // Grammar-safe chunks are complete root-context units,
                            // including any declaration continued across include regions.
                            // Facts use a small local spelling table, never a cloned tree.
                            let ast = AstFile {
                                items: parsed,
                                ..AstFile::default()
                            };
                            let admitted_facts = cached_facts
                                .as_deref()
                                .and_then(|bytes| chunkfacts::decode(bytes, text, offset));
                            let has_cached_facts = admitted_facts.is_some();
                            drop(profile_lookup);
                            lookup_ns.fetch_add(
                                lookup_start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
                                std::sync::atomic::Ordering::Relaxed,
                            );
                            if has_cached_facts {
                                facts_hits.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                            }
                            let facts_start = Instant::now();
                            let profile_facts =
                                dm_profile::item("frontend.fresh_declaration_facts");
                            let mut facts = if let Some(facts) = admitted_facts {
                                Ok(facts)
                            } else if errors.is_empty() {
                                crate::from_ast(&ast, SymbolTable::default(), FileId(0), 0, 0)
                                    .and_then(|mut adapted| {
                                        crate::allocation_ledger::capture(
                                            &ast.items,
                                            "/",
                                            &mut adapted.symbols,
                                        )
                                        .map(|ledger| (adapted, ledger))
                                        .map_err(|error| {
                                            vec![crate::AdapterError {
                                                span: dm_ir::Span {
                                                    file: FileId(0),
                                                    start: error.span.start as u32,
                                                    end: error.span.end as u32,
                                                },
                                                message: error.message,
                                            }]
                                        })
                                    })
                            } else {
                                Err(Vec::new())
                            };
                            let parsed = ast.items;
                            drop(profile_facts);
                            facts_ns.fetch_add(
                                facts_start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
                                std::sync::atomic::Ordering::Relaxed,
                            );
                            let produced_payload =
                                if memo.is_some() && (!cached_fragment_hit || !has_cached_facts) {
                                    let payload = facts
                                        .as_ref()
                                        .map_or(Ok(None), |(facts, ledger)| {
                                            chunkfacts::encode(facts, ledger, offset).map(Some)
                                        })
                                        .and_then(|facts_bytes| {
                                            parserwire::encode_with_facts(
                                                &parsed,
                                                &errors,
                                                offset,
                                                facts_bytes,
                                            )
                                        });
                                    match payload {
                                        Ok(bytes) => Some(bytes),
                                        Err(message) => {
                                            facts = Err(vec![crate::AdapterError {
                                                span: dm_ir::Span {
                                                    file: FileId(0),
                                                    start: offset as u32,
                                                    end: offset as u32,
                                                },
                                                message: format!(
                                                    "cache population encoding failed: {message}"
                                                ),
                                            }]);
                                            None
                                        }
                                    }
                                } else {
                                    None
                                };
                            if !cached_fragment_hit {
                                if let Some(memo) = memo {
                                    if let Some(bytes) = &produced_payload {
                                        if let Some(record) =
                                            dm_preprocess::regions::FragmentRecord::new(
                                                parserwire::VERSION,
                                                text,
                                                Arc::from(bytes.as_slice()),
                                            )
                                        {
                                            memo.insert_fragment(Arc::new(record));
                                        }
                                    }
                                }
                            }
                            let fragment = if has_cached_facts {
                                None
                            } else {
                                receipt.zip(relative).and_then(|(_, span)| {
                                    produced_payload.map(|bytes| (receipt_index, span, bytes))
                                })
                            };
                            let current = facts.and_then(|(facts,ledger)| {
                                let current = if let (Some(state),Some(keys))=(retained,retained_keys.as_ref()) {
                                    state.capture(&keys[index],text,offset,parsed,facts,ledger)
                                } else {
                                    super::declaration_state::CurrentContribution::fresh(text,offset,parsed,facts,ledger)
                                };
                                current.ok_or_else(||vec![crate::AdapterError{span:dm_ir::Span{file:FileId(0),start:offset as u32,end:offset as u32},message:"relative declaration binding failed".into()}])
                            });
                            if sender
                                .send((index, offset, errors, fragment, current))
                                .is_err()
                            {
                                break;
                            }
                        }
                    });
                }
        drop(sender);
        let mut ordered = Vec::with_capacity(chunks.len());
        for result in receiver {
            ordered.push(result);
            if ordered.len() % (worker_count * 2) == 0 || ordered.len() == chunks.len() {
                observe(
                    config,
                    FrontendStage::DeclarationParsing,
                    ProgressKind::Advanced,
                    parse_start.elapsed(),
                    ordered.len(),
                    chunks.len(),
                );
            }
        }
        ordered
    })
    };
    let mut ordered = std::panic::catch_unwind(std::panic::AssertUnwindSafe(parse))
        .map_err(|_| vec![internal("declaration parsing worker panicked")])?;
    ordered.sort_by_key(|(index, _, _, _, _)| *index);
    let merge_start = Instant::now();
    let _profile_merge = dm_profile::stage("frontend.ordered_declaration_merge");
    let mut updated = std::collections::BTreeMap::new();
    let mut adapted = crate::SharedAdaptedDeclarations {
        symbols: config
            .engine
            .map_or_else(SymbolTable::default, |engine| engine.symbols.clone()),
        skeletons: crate::skeleton_roster::SkeletonRoster::default(),
        origins: Vec::new().into(),
    };
    let mut allocation_leaves = Vec::new();
    let mut origin_leaves = crate::relative_origins::RelativeOriginRoster::default();
    let mut declaration_errors = Vec::new();
    let mut current_contributions = Vec::new();
    for (_, offset, errors, fragment, facts) in ordered {
        match facts {
            Ok(current) => {
                if retained.is_none() {
                    adapted
                        .symbols
                        .merge_from(current.symbols())
                        .map_err(|error| vec![internal(&error.to_string())])?;
                }
                current_contributions.push(Arc::clone(&current.value));
                adapted.skeletons.push_leaf(current.skeletons());
                let (origin_leaf, origin_offset) = current.origin_leaf();
                origin_leaves
                    .push(origin_leaf, origin_offset)
                    .ok_or_else(|| {
                        vec![internal("relative declaration origin binding overflow")]
                    })?;
                allocation_leaves.push(current.event_leaf());
                syntax_chunks.push(current.syntax);
            }
            Err(errors) => declaration_errors.extend(errors),
        }
        if let Some((index, span, bytes)) = fragment {
            let record = updated
                .entry(index)
                .or_insert_with(|| expanded.receipts[index].record().as_ref().clone());
            record.append_fragment(parserwire::VERSION, span, bytes.into());
        }
        diagnostics.extend(errors.into_iter().map(|error| (offset, error)));
    }
    adapted.origins = crate::relative_origins::OriginRoster::Bound(origin_leaves);
    if let Some(state) = retained {
        let symbols = state
            .current_symbols(&current_contributions)
            .map_err(|error| vec![internal(&error.to_string())])?;
        adapted
            .symbols
            .merge_from(&symbols)
            .map_err(|error| vec![internal(&error.to_string())])?;
    }
    if let Some(memo) = memo {
        for record in updated.into_values() {
            memo.insert(Arc::new(record));
        }
    }
    Ok(ParsedDeclarations {
        syntax: DeclarationSyntax::new(syntax_chunks)
            .map_err(|error| vec![internal(&format!("relative syntax roster: {error:?}"))])?,
        diagnostics,
        adapted,
        allocation_ledger: crate::allocation_ledger::AllocationLedger {
            events: crate::allocation_ledger::AllocationEvents::bind_leaves(allocation_leaves)
                .map_err(|error| {
                    vec![internal(&format!(
                        "allocation ledger binding failed: {error:?}"
                    ))]
                })?,
        },
        declaration_errors,
        reuse_stats: DeclarationReuseStats {
            chunks: chunks.len(),
            region_hits: region_hits.load(std::sync::atomic::Ordering::Relaxed),
            independent_hits: independent_hits.load(std::sync::atomic::Ordering::Relaxed),
            facts_hits: facts_hits.load(std::sync::atomic::Ordering::Relaxed),
            parsed_chunks: parsed_chunks.load(std::sync::atomic::Ordering::Relaxed),
            descriptor_scan,
            worker_lookup_decode_and_parse: Duration::from_nanos(
                lookup_ns.load(std::sync::atomic::Ordering::Relaxed),
            ),
            worker_fresh_facts: Duration::from_nanos(
                facts_ns.load(std::sync::atomic::Ordering::Relaxed),
            ),
            ordered_merge: merge_start.elapsed(),
        },
    })
}
