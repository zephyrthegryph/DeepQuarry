pub fn system_types(system: &str) -> Vec<String> {
    vec![
        format!("/datum/world_service/{}", system),
        format!("/datum/system/{}", system),
    ]
}

/// The vars a system declares: `(some candidate type exists, its vars)`. Reads only the files that name the
/// system's type, not the whole tree.
pub fn system_vars(tree: &Tree, system: &str) -> (bool, std::collections::HashSet<String>) {
    // A pure function of the tree and the system name, asked once per accessor: one answer per system.
    type Answers = std::sync::Mutex<
        std::collections::HashMap<String, (bool, std::collections::HashSet<String>)>,
    >;
    let answers: Arc<Answers> = tree.memo("sem/system_vars", || Answers::default());
    if let Some(known) = answers.lock().unwrap().get(system) {
        return known.clone();
    }
    let computed = system_vars_uncached(tree, system);
    answers
        .lock()
        .unwrap()
        .insert(system.to_string(), computed.clone());
    computed
}

fn system_vars_uncached(tree: &Tree, system: &str) -> (bool, std::collections::HashSet<String>) {
    let types = system_types(system);
    // Which files mention `/datum/world_service/<system>` or `/datum/system/<system>` (as a substring of the
    // comment-stripped text, like `contains`): per-file facts, read once per content change.
    let mentions: Arc<Vec<(String, Vec<(u8, String)>)>> = tree.memo("sem/system_mentions", || {
        let all = tree.select(&crate::tree::CODE_DM);
        let facts: Vec<Vec<(u8, String)>> = crate::incr::facts("system-type-mentions", &all, |f| {
            let text = &f.code().text;
            let mut out: Vec<(u8, String)> = Vec::new();
            for (k, prefix) in ["/datum/world_service/", "/datum/system/"]
                .iter()
                .enumerate()
            {
                let mut from = 0;
                while let Some(i) = text[from..].find(prefix) {
                    let start = from + i + prefix.len();
                    let run: String = text[start..]
                        .chars()
                        .take_while(|c| c.is_alphanumeric() || *c == '_')
                        .collect();
                    out.push((k as u8, run));
                    from = start;
                }
            }
            out.sort();
            out.dedup();
            out
        });
        all.iter()
            .zip(facts)
            .map(|(f, m)| (f.rel.clone(), m))
            .collect()
    });
    let plain = !system.is_empty() && system.chars().all(|c| c.is_alphanumeric() || c == '_');
    let files: Vec<&crate::tree::SourceFile> = if plain {
        mentions
            .iter()
            .filter(|(_, m)| m.iter().any(|(_, run)| run.starts_with(system)))
            .filter_map(|(rel, _)| tree.get(rel))
            .collect()
    } else {
        tree.select(&crate::tree::CODE_DM)
            .into_iter()
            .filter(|f| types.iter().any(|t| f.code().text.contains(t.as_str())))
            .collect()
    };
    let table = crate::dm::dx::type_vars_in(tree, &files);
    let mut vars = std::collections::HashSet::new();
    let mut known = false;
    for t in &types {
        if let Some(v) = table.get(t) {
            known = true;
            vars.extend(v.iter().cloned());
        } else if files
            .iter()
            .any(|f| f.code().text.lines().any(|l| l.trim_end() == t.as_str()))
        {
            known = true;
        }
    }
    (known, vars)
}

