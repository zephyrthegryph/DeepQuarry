    pub fn get(sem: &Sem, decls: &Decls) -> Annotations {
        let mut a = Annotations::default();
        for m in decls.markers_named("READS_AS") {
            let Some(first) = m.args.first() else { continue };
            let key = m.args.get(1).cloned().unwrap_or_default();
            let via = m.args.iter().skip(2).find_map(|x| {
                let x = x.replace(' ', "");
                x.strip_prefix("via=nameof(").and_then(|r| r.strip_suffix(')')).map(|s| s.to_string())
            });
            let mut owners: Vec<(String, String)> = Vec::new();
            if first.starts_with('/') {
                // /type/proc/name or /type/name
                let (ty, name) = first.rsplit_once('/').unwrap();
                let ty = ty.strip_suffix("/proc").unwrap_or(ty);
                owners.push((if ty.is_empty() { "/".to_string() } else { ty.to_string() }, name.to_string()));
            } else {
                for c in sem.owner_candidates(&m.rel, m.line) {
                    owners.push((c, first.clone()));
                }
            }
            for (ty, name) in owners {
                if sem.ty(&ty).map(|t| t.get().procs.contains_key(&name)).unwrap_or(false) {
                    a.reads_as.insert((ty, name), (key.clone(), via.clone()));
                    break;
                }
            }
        }
        for m in decls.markers_named("PROC_SUMMARY") {
            let Some(first) = m.args.first() else { continue };
            let Some((ty, name)) = first.rsplit_once('/') else { continue };
            let ty = ty.strip_suffix("/proc").unwrap_or(ty);
            let ty = if ty.is_empty() { "/".to_string() } else { ty.to_string() };
            let list = |key: &str| -> Vec<String> {
                m.args
                    .iter()
                    .skip(1)
                    .find_map(|a| a.split_once('=').filter(|(k, _)| k.trim() == key).map(|(_, v)| v.trim().to_string()))
                    .and_then(|v| v.strip_prefix("list(").and_then(|r| r.strip_suffix(')')).map(|r| r.to_string()))
                    .map(|inner| {
                        split_args(&inner).into_iter().map(|x| x.trim().trim_start_matches("nameof(").trim_end_matches(')').trim().to_string()).filter(|x| !x.is_empty()).collect()
                    })
                    .unwrap_or_default()
            };
            a.summaries.insert((ty, name.to_string()), ProcSummary { reads: list("reads"), writes: list("writes") });
        }
        for m in decls.markers_named("READ_LOOKUP") {
            let Some(path) = m.args.first() else { continue };
            let Some(name) = path.strip_prefix("/proc/") else { continue };
            let named = |name: &str| m.args.iter().skip(1).find_map(|a| a.split_once('=').filter(|(k, _)| k.trim() == name).map(|(_, v)| v.trim().to_string()));
            let proc_name = |value: Option<String>| value.and_then(|v| v.strip_prefix("GLOBAL_PROC_REF(").and_then(|x| x.strip_suffix(')')).map(|x| x.trim().to_string()));
            let (Some(registry), Some(identity_key), Some(result)) = (proc_name(named("registry")), proc_name(named("key")), named("result")) else { continue };
            let argument = named("argument").and_then(|s| s.parse::<usize>().ok()).unwrap_or(1);
            if argument == 0 || !result.starts_with('/') { continue; }
            a.lookups.insert(name.to_string(), LookupDeclaration { registry, identity_key, argument: argument - 1, result });
        }
        let mut cap_names: HashMap<String, String> = HashMap::new();
        for m in decls.markers_named("CAPABILITY_TYPE").chain(decls.markers_named("CAPABILITY_DEF")) {
            if let (Some(name), Some(id)) = (m.args.first(), m.args.get(1)) {
                cap_names.insert(id.clone(), name.clone());
            }
        }
        for m in decls.markers_named("cap_keys") {
            let Some(cap_id) = m.args.first() else { continue };
            let Some(cap_name) = cap_names.get(cap_id) else { continue };
            for arg in m.args.iter().skip(1) {
                let key = arg.split('=').next().unwrap_or("").trim().to_string();
                if key.is_empty() {
                    continue;
                }
                a.capkey_accessors.insert(format!("{}_{}", cap_name, key.to_lowercase()), format!("{}_{}", cap_name.to_uppercase(), key));
            }
        }
        for m in decls.markers_named("SYSTEM_ACCESSOR") {
            if let (Some(sys), Some(name), Some(key)) = (m.args.first(), m.args.get(1), m.args.get(2)) {
                let var = key.trim().strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')).unwrap_or(key).trim().to_string();
                a.accessors.insert(name.clone(), (sys.clone(), var));
            }
        }
        // relations() declares rel_one/rel_many vars; ownership() declares owns(nameof(v), ...) vars. Both are written only through the
        // ownership accessors (rel_set/rel_add/own_take/move_into), whose own_field_changed() publishes the var's name to its readers.
        for (proc_name, calls) in [("relations", &["rel_one", "rel_many"][..]), ("ownership", &["owns", "rel_one", "rel_many"][..])] {
        for ty in sem.objtree.iter_types() {
            let Some(tp) = ty.get().procs.get(proc_name) else { continue };
            let path = if ty.get().path.is_empty() { "/".to_string() } else { ty.get().path.clone() };
            for value in &tp.value {
                let Some(code) = &*value.code else { continue };
                super::ast::walk_block(code, &mut |e, _| {
                    if let Some((n, args)) = super::ast::as_call(e) {
                        if calls.contains(&n) {
                            if let Some(Expression::Base { term, .. }) = args.first() {
                                if let Term::Call(f, inner) = &term.elem {
                                    if f.as_str() == "nameof" {
                                        if let Some(id) = inner.first().and_then(as_ident) {
                                            a.relations.entry(path.clone()).or_default().insert(id.to_string());
                                        }
                                    }
                                }
                            }
                        }
                    }
                });
            }
        }
        }
        for m in decls.markers_named("READS_FROM") {
            if let Some((owner, name)) = sem.def_at(&m.rel, m.line) {
                let params = m.args.iter().filter(|x| !x.is_empty()).cloned().collect();
                if owner == "/" {
                    a.reads_from.insert(name, params);
                }
            }
        }
        a
    }
