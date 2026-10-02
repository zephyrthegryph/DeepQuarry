//! Generated initializer queries use the same semantic graph and section materializer.
use super::*;

#[derive(Clone,serde::Serialize,serde::Deserialize)]
pub(super) struct InitializerRecipe {
    pub key:crate::ProcKey,
    pub descriptor:crate::ProcDescriptor,
    pub source:Arc<str>,
}
pub(super) fn recipes(groups:&[(Option<u32>,Vec<PendingDynamic>)],dmb:&Dmb,strings:&StringIndex,attach:bool)->Vec<InitializerRecipe> {
    groups.iter().map(|(owner,assignments)| {
        let mut assignments:Vec<_>=assignments.iter().collect();
        if owner.is_none() {assignments.sort_by_key(|assignment|!assignment.sized_array&&!literal_initializer(&assignment.expression,dmb,strings));}
        let mut source=String::from("/proc/__initializer()\n");
        for assignment in assignments {source.push_str(&format!("    {} = {}\n",assignment.name,assignment.expression));}
        let owner_path=owner.and_then(|id|dmb.string(dmb.classes[id as usize].path_string_id())).map(|path|String::from_utf8_lossy(path)).unwrap_or_default();
        let digest=crate::incremental::digest(source.as_bytes());
        InitializerRecipe {key:crate::ProcKey {path:format!("@initializer|{owner_path}|{attach}|{digest}"),occurrence:0},
            descriptor:crate::ProcDescriptor {body_digest:digest,frame_digest:"initializer-invocation-v2".into()},source:Arc::from(source)}
    }).collect()
}
pub(super) fn group_assignments(pending:Vec<PendingDynamic>)->Vec<(Option<u32>,Vec<PendingDynamic>)> {
    let mut groups=Vec::<(Option<u32>,Vec<PendingDynamic>)>::new();let mut indices=HashMap::new();
    for assignment in pending {
        let index=*indices.entry(assignment.owner).or_insert_with(||{let index=groups.len();groups.push((assignment.owner,Vec::new()));index});
        groups[index].1.push(assignment);
    }
    groups
}

/// Derive generated-query identities before graph witness refresh, in exactly
/// the same owner/assignment order as physical initializer publication.
pub(super) fn query_keys(pending:&[PendingDynamic],dmb:&Dmb,strings:&StringIndex,attach:bool)->Vec<crate::ProcKey> {
    let mut groups:Vec<(Option<u32>,Vec<&PendingDynamic>)>=Vec::new();
    let mut indices=HashMap::new();
    for assignment in pending {
        let index=*indices.entry(assignment.owner).or_insert_with(||{let index=groups.len();groups.push((assignment.owner,Vec::new()));index});
        groups[index].1.push(assignment);
    }
    group_keys(groups.into_iter().map(|(owner,assignments)|(owner,assignments)).collect(),dmb,strings,attach)
}
fn group_keys(groups:Vec<(Option<u32>,Vec<&PendingDynamic>)>,dmb:&Dmb,strings:&StringIndex,attach:bool)->Vec<crate::ProcKey> {
    groups.into_iter().map(|(owner,mut assignments)| {
        if owner.is_none() {assignments.sort_by_key(|assignment|!assignment.sized_array&&!literal_initializer(&assignment.expression,dmb,strings));}
        let mut source=String::from("/proc/__initializer()\n");
        for assignment in assignments {source.push_str(&format!("    {} = {}\n",assignment.name,assignment.expression));}
        let owner_path=owner.and_then(|id|dmb.string(dmb.classes[id as usize].path_string_id()))
            .map(|path|String::from_utf8_lossy(path)).unwrap_or_default();
        crate::ProcKey {path:format!("@initializer|{owner_path}|{attach}|{}",crate::incremental::digest(source.as_bytes())),occurrence:0}
    }).collect()
}

pub(super) fn emit_dynamic_initializers_with_pool(
    dmb: &mut Dmb,
    pending: Vec<PendingDynamic>,
    strings: &mut StringIndex,
    classes: &HashMap<String, u32>,
    resources: &HashMap<String, u32>,
    globals: &HashMap<String, u32>,
    global_procs: &HashMap<String, u32>,
    project_bindings: &Arc<SharedLowerBindings>,
    prepared_member_globals: &PreparedMemberGlobals,
    lowering_cache: &mut crate::lower_cache::ProcLoweringCache,
    attach: bool,
    pool: Option<&mut procedure_pipeline::LoweringPool>,
    session: Option<&mut canonical::CanonicalSession>,
) -> Result<Vec<u32>, String> {
    let groups=group_assignments(pending);
    emit_initializer_groups_with_pool(dmb, groups, strings, classes, resources, globals, global_procs, project_bindings, prepared_member_globals, lowering_cache, attach, pool, session, None)
}

pub(super) fn emit_initializer_groups_with_pool(
    dmb: &mut Dmb,
    groups: Vec<(Option<u32>,Vec<PendingDynamic>)>,
    strings: &mut StringIndex,
    classes: &HashMap<String, u32>,
    resources: &HashMap<String, u32>,
    globals: &HashMap<String, u32>,
    global_procs: &HashMap<String, u32>,
    project_bindings: &Arc<SharedLowerBindings>,
    prepared_member_globals: &PreparedMemberGlobals,
    lowering_cache: &mut crate::lower_cache::ProcLoweringCache,
    attach: bool,
    mut pool: Option<&mut procedure_pipeline::LoweringPool>,
    mut session: Option<&mut canonical::CanonicalSession>,
    cached_recipes:Option<&[InitializerRecipe]>,
) -> Result<Vec<u32>, String> {
    let mut generated = Vec::new();
    let phase_started = std::time::Instant::now();
    let mut parse_time = std::time::Duration::ZERO;
    let mut binding_time = std::time::Duration::ZERO;
    let mut lowering_time = std::time::Duration::ZERO;
    let mut linking_time = std::time::Duration::ZERO;
    let mut prepared_hits = 0;
    let mut lowered_groups = 0;
    let shared = Arc::clone(project_bindings);
    let derived;
    let plans=if let Some(plans)=cached_recipes {plans} else {
        derived=recipes(&groups,dmb,strings,attach);&derived
    };
    if plans.len()!=groups.len() {return Err("initializer recipe inventory mismatch".into());}
    if let Some(session) = session.as_deref_mut() {
        // Headers were restored before declaration fact refresh. Fetch payloads
        // only for this requested group set; no stale helper inventory scan.
        let keys:Vec<_>=plans.iter().map(|plan|plan.key.clone()).collect();
        for chunk in keys.chunks(1024) {
            let _ = session.graph.prefetch(chunk);
        }
    }
    let mut groups = groups.into_iter().enumerate().peekable();
    while groups.peek().is_some() {
        let mut prepared = Vec::with_capacity(procedure_pipeline::LOWERING_WINDOW);
        let mut serial_results = Vec::with_capacity(procedure_pipeline::LOWERING_WINDOW);
        let mut submitted = 0;
        for _ in 0..procedure_pipeline::LOWERING_WINDOW {
            let Some((ordinal, (owner, assignments))) = groups.next() else {
                break;
            };
            let plan=&plans[ordinal];
            let source=&plan.source;
            let key=plan.key.clone();
            let descriptor=plan.descriptor.clone();
            let cached_envelope = session.as_deref_mut().and_then(|session| {
                session.active_keys.insert(key.clone());
                match session.graph.probe(&key, &descriptor) {
                    crate::ProcedureProbe::Resident(crate::ProcedureArtifact::Prepared(
                        envelope,
                    )) => Some(envelope),
                    _ => None,
                }
            });
            if let Some(envelope) = &cached_envelope {
                // Materialization only needs relative metadata and relocations.
                // A hit neither constructs an owner frame nor parses the body.
                serial_results.push(procedure_pipeline::LoweringResult {
                    ordinal,
                    bindings: LowerBindings::default(),
                    compiled: Ok(envelope.metadata.clone()),
                    memo: None,
                    lowering_cache_hit: false,
                    body_base: None,
                    source_error: None,
                    internal_panic: None,
                });
                prepared.push((
                    ordinal,
                    owner,
                    assignments,
                    key,
                    descriptor,
                    cached_envelope,
                ));
                prepared_hits += 1;
                continue;
            }
            lowered_groups += 1;
            let parse_started = std::time::Instant::now();
            let mut ast = parse(&source);
            if !ast.diagnostics.is_empty() {
                return Err(format!("dynamic initializer syntax: {:?}", ast.diagnostics));
            }
            parse_time += parse_started.elapsed();
            let bindings_started = std::time::Instant::now();
            let referenced_globals=referenced_initializer_globals(&source,globals);
            let mut bindings = LowerBindings {
                globals: referenced_globals,
                shared: Some(Arc::clone(&shared)),
                prepared_member_globals: prepared_member_globals.clone(),
                ..LowerBindings::default()
            };
            if let Some(mut class_id) = owner {
                loop {
                    if let Some(path) = dmb.string(dmb.classes[class_id as usize].path_string_id())
                    {
                        let path = String::from_utf8_lossy(path);
                        seed_builtin_fields(&path, &mut bindings);
                        if let Some(fields) = shared.member_types.get(path.as_ref()) {
                            for (name, ty) in fields {
                                bindings
                                    .field_types
                                    .entry(name.clone())
                                    .or_insert_with(|| ty.clone());
                            }
                        }
                    }
                    if let Some(declarations) = dmb.class_variable_declarations(class_id as usize) {
                        for (id, _) in declarations {
                            if let Some(name) = dmb.string(dmb.variables[id as usize].name) {
                                bindings
                                    .fields
                                    .insert(String::from_utf8_lossy(name).into_owned());
                            }
                        }
                    }
                    let parent = dmb.classes[class_id as usize].parent_class_id();
                    if parent == 0xffff {
                        break;
                    }
                    class_id = parent;
                }
            }
            binding_time += bindings_started.elapsed();
            let lowering_started = std::time::Instant::now();
            let body = std::mem::take(&mut ast.items[0].children);
            if let Some(pool) = pool.as_deref_mut() {
                pool.submit_for_phase(
                    procedure_pipeline::LoweringPhase::Initializer,
                    ordinal,
                    body,
                    bindings,
                );
                submitted += 1;
            } else {
                let hits_before = lowering_cache.hits_count();
                let memo = lowering_cache.compile_memo(&body, &bindings).map(Arc::new);
                let lowering_cache_hit = lowering_cache.hits_count() > hits_before;
                let compiled = memo
                    .as_ref()
                    .map(|memo| memo.procedure.clone())
                    .map_err(Clone::clone);
                serial_results.push(procedure_pipeline::LoweringResult {
                    ordinal,
                    bindings,
                    compiled,
                    memo: memo.ok(),
                    lowering_cache_hit,
                    body_base: None,
                    source_error: None,
                    internal_panic: None,
                });
            }
            lowering_time += lowering_started.elapsed();
            prepared.push((
                ordinal,
                owner,
                assignments,
                key,
                descriptor,
                cached_envelope,
            ));
        }
        let lowering_started = std::time::Instant::now();
        if let Some(pool) = pool.as_deref_mut() {
            serial_results.extend(pool.receive_batch(submitted));
        }
        serial_results.sort_by_key(|result| result.ordinal);
        let results = serial_results;
        lowering_time += lowering_started.elapsed();
        for ((ordinal, owner, assignments, key, descriptor, cached_envelope), result) in
            prepared.into_iter().zip(results)
        {
            assert_eq!(ordinal, result.ordinal, "initializer lowering order");
            let mut simple = result
                .compiled
                .map_err(|errors| format!("dynamic initializer: {errors:?}"))?;
            if let Some(session) = session.as_deref_mut() {
                if cached_envelope.is_some() {
                    session.emission_stats.generated_prepared_reused += 1;
                } else if result.lowering_cache_hit {
                    session.emission_stats.generated_cache_reused += 1;
                } else {
                    session.emission_stats.generated_lowered += 1;
                }
            }
            let linking_started = std::time::Instant::now();
            if cached_envelope.is_none() {
                for item in &mut simple.code.items {
                    if let CodeItem::Instruction(instruction) = item {
                        if owner.is_some() && instruction.opcode == opcode::SET_VAR {
                            if let [Word::Variable(VariableWord::Field(field))] =
                                instruction.operands.as_slice()
                            {
                                instruction.operands =
                                    vec![Word::Variable(VariableWord::SetCache(
                                        Box::new(VariableWord::Src),
                                        Box::new(VariableWord::SetCache(
                                            Box::new(VariableWord::Src),
                                            Box::new(VariableWord::Field(field.clone())),
                                        )),
                                    ))];
                            }
                        }
                    }
                }
                // Initializers finish with End, without a value-return epilogue.
                let code = &mut simple.code.items;
                if code.len() >= 3
                    && matches!(&code[code.len() - 3], CodeItem::Instruction(ins) if ins.opcode == opcode::PUSH_VAL && ins.operands == [Word::Value(ValueWord::Null)])
                    && matches!(&code[code.len() - 2], CodeItem::Instruction(ins) if ins.opcode == opcode::RET)
                    && matches!(&code[code.len() - 1], CodeItem::Instruction(ins) if ins.opcode == opcode::END)
                {
                    code.truncate(code.len() - 3);
                    code.push(CodeItem::Instruction(CodeInstruction {
                        opcode: opcode::END,
                        operands: vec![],
                    }));
                } else if !matches!(
                    code.last(),
                    Some(CodeItem::Instruction(CodeInstruction {
                        opcode: opcode::END,
                        ..
                    }))
                ) {
                    return Err("dynamic initializer contains an unsupported return path".into());
                }
            }
            let envelope = if let Some(envelope) = cached_envelope {
                envelope
            } else {
                // Initializer-specific instructions and End-only epilogue are
                // semantic output, so cache the section after those transforms.
                let envelope = Arc::new(
                    dm_codegen_byond::prepared_cache::PreparedProcedureEnvelope::prepare(&simple)
                        .map_err(|error| {
                        format!("dynamic initializer {owner:?}: prepare code section: {error}")
                    })?,
                );
                if let (Some(session), Some(memo)) = (session.as_deref_mut(), result.memo.as_ref())
                {
                    session.graph.install_prepared(
                        key,
                        descriptor,
                        Arc::clone(&envelope),
                        memo.dependencies.clone().into(),
                        None,
                    );
                }
                envelope
            };
            let mut ledger = Ledger::default();
            bind_builtin_global_vars(dmb, strings, &mut ledger)?;
            for key in &simple.strings {
                ledger
                    .bind(
                        Symbol::new(Table::String, key),
                        strings.intern_bytes(dmb, simple.string_bytes(key)),
                    )
                    .map_err(|error| error.to_string())?;
            }
            for path in &simple.class_paths {
                let id = class_link_id(dmb, classes, path)
                    .ok_or_else(|| format!("unresolved initializer type: {path}"))?;
                bind_class_link(&mut ledger, path, id)?;
            }
            for path in &simple.resources {
                let id = *resources
                    .get(path)
                    .ok_or_else(|| format!("unresolved initializer resource: {path}"))?;
                ledger
                    .bind_alias(Symbol::new(Table::Resource, path), id)
                    .map_err(|error| {
                        format!("dynamic initializer {owner:?}, resource {path}: {error}")
                    })?;
            }
            bind_prepared_references(
                &envelope.section,
                &strings,
                &mut ledger,
                globals,
                None,
                global_procs,
            )?;
            if let Some(session) = session.as_deref_mut() {
                envelope.section.attach_projection_cache(Arc::clone(&session.output_projections));
            }
            let words = envelope.section.materialize(&ledger).map_err(|error| {
                format!(
                    "dynamic initializer {owner:?} ({} of {} assignments): {error}",
                    assignments
                        .iter()
                        .take(3)
                        .map(|assignment| assignment.name.as_str())
                        .collect::<Vec<_>>()
                        .join(", "),
                    assignments.len()
                )
            })?;
            let code_id = append_list(dmb, words);
            let local_ids = simple
                .local_names
                .iter()
                .map(|name| append_null_variable(dmb, strings, name))
                .collect();
            let local_id = append_list(dmb, local_ids);
            let empty_args = append_list(dmb, vec![]);
            crate::reserve_proc_sentinel(dmb);
            let proc_id = dmb.procs.len() as u32;
            dmb.procs.push(Proc {
                strings: [0xffff; 4],
                source_parameter: 255,
                source_kind: 0,
                // Native initializers wait for yielding callees before creation continues.
                flags: 4,
                extended_flags: None,
                code_locals_args: [code_id, local_id, empty_args],
            });
            generated.push(proc_id);
            linking_time += linking_started.elapsed();
            if !attach {
                continue;
            }
            if let Some(class_id) = owner {
                if dmb.classes[class_id as usize].initializer_proc_id() != 0xffff {
                    return Err(format!(
                        "class {class_id} already has an initializer procedure"
                    ));
                }
                dmb.classes[class_id as usize].lists_and_procs[2] = proc_id;
            } else {
                if dmb.world.global_initializer_proc_id() != 0xffff {
                    return Err("world already has a global initializer procedure".into());
                }
                dmb.world.ids[4] = proc_id;
            }
        }
    }
    if attach && std::env::var_os("DM_BUILD_TRACE").is_some() {
        eprintln!("DM_BUILD_TRACE dynamic initializer phases: {} groups ({} prepared hits, {} lowered), parse {:.3}s, bindings {:.3}s, lowering/cache {:.3}s, linking/emission {:.3}s, total {:.3}s", generated.len(), prepared_hits, lowered_groups, parse_time.as_secs_f64(), binding_time.as_secs_f64(), lowering_time.as_secs_f64(), linking_time.as_secs_f64(), phase_started.elapsed().as_secs_f64());
    }
    Ok(generated)
}

#[cfg(test)]
mod tests {
    use super::*;

    const BUILTINS: &[u8] = include_bytes!("../../../fixtures/native_template.bin");

    fn fixture(padding: bool) -> (Dmb, StringIndex, HashMap<String, u32>, HashMap<String, u32>) {
        let mut dmb = Dmb::from_bytes(BUILTINS).unwrap();
        let mut strings = StringIndex::new(&dmb);
        let classes = strings.3.clone();
        if padding {
            append_null_variable(&mut dmb, &mut strings, "padding");
        }
        let target = append_null_variable(&mut dmb, &mut strings, "target");
        (
            dmb,
            strings,
            classes,
            HashMap::from([("target".into(), target)]),
        )
    }

    fn emit(
        padding: bool,
        owner: bool,
        expression: &str,
        shared: Arc<SharedLowerBindings>,
        session: Option<&mut canonical::CanonicalSession>,
    ) -> Dmb {
        let (mut dmb, mut strings, classes, globals) = fixture(padding);
        let owner_id = owner.then(|| *classes.get("/datum").unwrap());
        let index = PreparedMemberGlobals::new(Arc::clone(&shared));
        emit_dynamic_initializers_with_pool(
            &mut dmb,
            vec![PendingDynamic {
                owner: owner_id,
                name: if owner { "tag" } else { "target" }.into(),
                expression: expression.into(),
                sized_array: false,
            }],
            &mut strings,
            &classes,
            &HashMap::new(),
            &globals,
            &HashMap::new(),
            &shared,
            &index,
            &mut crate::lower_cache::ProcLoweringCache::disabled(),
            true,
            None,
            session,
        )
        .unwrap();
        dmb
    }

    fn shared() -> Arc<SharedLowerBindings> {
        Arc::new(SharedLowerBindings {
            globals: BTreeSet::from(["target".into()]),
            ..SharedLowerBindings::default()
        })
    }

    #[test]
    fn prepared_initializer_rebinds_current_output_ids_without_lowering() {
        let shared = shared();
        let mut session = canonical::CanonicalSession::default();
        emit(
            false,
            false,
            "list(1)",
            Arc::clone(&shared),
            Some(&mut session),
        );
        let installs = session.graph.stats().installs;
        let cached = emit(
            true,
            false,
            "list(1)",
            Arc::clone(&shared),
            Some(&mut session),
        );
        let fresh = emit(true, false, "list(1)", shared, None);
        assert_eq!(cached.to_bytes().unwrap(), fresh.to_bytes().unwrap());
        assert_eq!(session.graph.stats().installs, installs);
        assert_eq!(session.graph.stats().resident_hits, 1);
        assert!(session
            .active_keys
            .iter()
            .all(|key| key.path.starts_with("@initializer||true|")));
    }

    #[test]
    fn prepared_initializer_preserves_owner_store_and_end_epilogue() {
        let shared = shared();
        let mut session = canonical::CanonicalSession::default();
        let first = emit(
            false,
            true,
            "list(1)",
            Arc::clone(&shared),
            Some(&mut session),
        );
        let cached = emit(
            false,
            true,
            "list(1)",
            Arc::clone(&shared),
            Some(&mut session),
        );
        let fresh = emit(false, true, "list(1)", shared, None);
        assert_eq!(first.to_bytes().unwrap(), cached.to_bytes().unwrap());
        assert_eq!(cached.to_bytes().unwrap(), fresh.to_bytes().unwrap());
        let class = cached
            .classes
            .iter()
            .find(|class| cached.string(class.path_string_id()) == Some(b"/datum"))
            .unwrap();
        let words = cached
            .proc_code_words(class.initializer_proc_id() as usize)
            .unwrap();
        let code = byond_dmb::bytecode::decode(words).unwrap();
        assert_eq!(code.last().unwrap().opcode, opcode::END);
        assert!(!code
            .iter()
            .any(|instruction| instruction.opcode == opcode::RET));
        let store = code
            .iter()
            .find(|instruction| instruction.opcode == opcode::SET_VAR)
            .unwrap();
        // Builtin and authored fields can have different cache depths. Both
        // must address the owning src rather than a global or temporary slot.
        use byond_dmb::operands::Variable;
        let (mut variable, used) = Variable::decode(&store.operands).unwrap();
        assert_eq!(used, store.operands.len());
        let mut owner_layers = 0;
        loop {
            match variable {
                Variable::SetCache(owner, field) => {
                    assert_eq!(*owner, Variable::Src);
                    owner_layers += 1;
                    variable = *field;
                }
                Variable::Field(name) => {
                    assert_eq!(cached.string(name), Some(b"tag".as_slice()));
                    break;
                }
                other => panic!("initializer wrote a non-owner field: {other:?}"),
            }
        }
        assert!(owner_layers > 0);
        assert_eq!(session.graph.stats().resident_hits, 1);
    }

    #[test]
    fn prepared_initializer_source_change_is_a_distinct_graph_root() {
        let shared = shared();
        let mut session = canonical::CanonicalSession::default();
        let before = emit(
            false,
            false,
            "list(1)",
            Arc::clone(&shared),
            Some(&mut session),
        );
        let after = emit(
            false,
            false,
            "list(2)",
            Arc::clone(&shared),
            Some(&mut session),
        );
        let fresh = emit(false, false, "list(2)", shared, None);
        assert_ne!(before.to_bytes().unwrap(), after.to_bytes().unwrap());
        assert_eq!(after.to_bytes().unwrap(), fresh.to_bytes().unwrap());
        assert_eq!(session.graph.stats().installs, 2);
        assert_eq!(session.graph.stats().resident_hits, 0);
        assert_eq!(session.active_keys.len(), 2);
    }

    #[test]
    fn prepared_initializer_cold_restore_replays_facts_and_current_ids() {
        let root = std::env::temp_dir().join(format!(
            "dm-initializer-graph-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&root).unwrap();
        let shared = shared();
        {
            let mut session = canonical::CanonicalSession::default();
            session.graph = crate::ProjectProcedureGraph::open(&root, "initializer-probe");
            emit(
                false,
                false,
                "list(target)",
                Arc::clone(&shared),
                Some(&mut session),
            );
            session.graph.flush().unwrap();
        }
        let mut restored = canonical::CanonicalSession::default();
        restored.graph = crate::ProjectProcedureGraph::open(&root, "initializer-probe");
        let frame = LowerBindings {
            globals: BTreeSet::from(["target".into()]),
            shared: Some(Arc::clone(&shared)),
            ..LowerBindings::default()
        };
        restored
            .graph
            .refresh_facts("current-frozen-declarations", |_, fact| {
                frame.binding_fact(fact)
            });
        let cached = emit(
            true,
            false,
            "list(target)",
            Arc::clone(&shared),
            Some(&mut restored),
        );
        let fresh = emit(true, false, "list(target)", shared, None);
        assert_eq!(cached.to_bytes().unwrap(), fresh.to_bytes().unwrap());
        assert_eq!(restored.graph.stats().disk_hits, 1);
        assert_eq!(restored.graph.stats().misses, 0);
        assert!(restored.graph.stats().fact_refreshes > 0);
        drop(restored);
        std::fs::remove_dir_all(root).unwrap();
    }
}
