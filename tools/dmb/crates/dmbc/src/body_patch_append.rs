//! Stable-numbering append patch (doc/structural_change_set.md, addendum).
//!
//! When the frontend's change-set splice proves that an edit only added procs
//! or verbs to existing types, relative to exactly the patch base's tree, the
//! new procedures are appended to the retained composed model with fresh
//! indices (procedure, code list, frame variables, strings), existing bodies
//! that moved or changed are relinked as body patches are, and each owner's
//! proc/verb list is rebuilt in fresh-build order. Numbering differs from a
//! fresh build; the program is semantically equivalent (checked by
//! `dmb-inspect semantic-equal` until `dmb-equiv` lands).
//!
//! Declines (full path) when: a name is a header callback or appears outside
//! its own declaration; a new unit has warnings, helpers, modified instances,
//! required types, shared slots or header-affecting bytecode features; a link
//! key outside the String and Procedure tables would be added; a shifted line
//! falls where the insertion point is ambiguous; the retained model no longer
//! describes the published image; or the owner's list cannot be reproduced.
use super::*;
use crate::lowering::Namespace;
use dm_ir::SymbolId;

/// Old-to-new line mapping per file from aligned body starts and inserted
/// bodies. `None` where an inserted body lies between the neighbours.
struct InsertionLines {
    /// Per file, (old start, new start) of aligned bodies, sorted by old start.
    aligned: HashMap<Arc<str>, Vec<(usize, usize)>>,
    /// Per file, new start lines of inserted bodies, sorted.
    inserted: HashMap<Arc<str>, Vec<usize>>,
}
impl InsertionLines {
    fn map(&self, path: &str, line: usize) -> Option<usize> {
        let pairs = self.aligned.get(path).map(Vec::as_slice).unwrap_or_default();
        let inserted = self.inserted.get(path).map(Vec::as_slice).unwrap_or_default();
        let after = pairs.partition_point(|(old, _)| *old <= line);
        let previous = after.checked_sub(1).map(|index| pairs[index]);
        let next = pairs.get(after).copied();
        let delta = |(old, new): (usize, usize)| new as isize - old as isize;
        let between = |low: usize, high: usize| inserted.iter().any(|&at| at >= low && at <= high);
        let shifted = match (previous, next) {
            (Some(p), Some(n)) => {
                if delta(p) != delta(n) || between(p.1, n.1) {
                    return None;
                }
                delta(p)
            }
            (Some(p), None) => {
                if inserted.iter().any(|&at| at >= p.1) {
                    return None;
                }
                delta(p)
            }
            (None, Some(n)) => {
                if inserted.iter().any(|&at| at <= n.1) {
                    return None;
                }
                delta(n)
            }
            (None, None) => {
                if !inserted.is_empty() {
                    return None;
                }
                0
            }
        };
        usize::try_from(line as isize + shifted).ok()
    }
}

fn mentions(text: &[u8], name: &[u8]) -> usize {
    text.windows(name.len())
        .enumerate()
        .filter(|(at, window)| *window == name && word_at(text, *at, name))
        .count()
}

pub(super) fn try_append_patch<R: dm_ir::Resolver>(
    request: PatchRequest<'_, R>,
    base: &BodyPatchBase,
    link: &crate::composition::PatchLink,
    image: &crate::composition::PatchImage,
) -> Result<Patched, String> {
    let frontend: &dm_tree::frontend::ColdFrontend = request.frontend;
    let tree = &frontend.snapshot.tree;
    let appended = tree
        .appended_callables()
        .ok_or("not an appended-callable edit")?;
    if appended.from_identity != base.shape.tree_identity {
        return Err("appended callables are not relative to the patch base".into());
    }
    if let Some(difference) = request.inputs.non_text_difference(&base.inputs) {
        return Err(format!("non-text input changed: {difference}"));
    }
    if request.archive != base.archive {
        return Err("resource archive changed".into());
    }
    let symbols = tree.symbols();
    let text = frontend.expanded.text.as_str().as_bytes();
    let mut appended_names = std::collections::HashMap::<SymbolId, usize>::new();
    for &(_, name, _) in &appended.members {
        *appended_names.entry(name).or_default() += 1;
    }
    for (&name, &count) in &appended_names {
        let spelling = symbols.text(name).ok_or("appended name has no spelling")?;
        if crate::class_projection::recognizes_callback(name) || spelling.starts_with("Mouse") {
            return Err("appended callable is a header callback".into());
        }
        // Each declaration header names it once; any other mention could be a
        // call or reference whose lowering depends on the new callable.
        if mentions(text, spelling.as_bytes()) != count {
            return Err(format!("{spelling} is referenced outside its declaration"));
        }
    }
    // Split current bodies into aligned (existing) and inserted (appended).
    let shape = request.shape;
    let is_appended = |body: &dm_tree::frontend::BodyOccurrence| -> bool {
        tree.member(body.member).is_some_and(|member| {
            let owner = tree.type_node(member.owner).map(|node| node.path);
            appended
                .members
                .iter()
                .any(|&(o, n, k)| Some(o) == owner && n == member.name && k == member.kind)
        })
    };
    let mut aligned = Vec::with_capacity(base.shape.bodies.len());
    let mut inserted = Vec::new();
    for (index, body) in frontend.bodies.iter().enumerate() {
        if is_appended(body) {
            inserted.push(index);
        } else {
            aligned.push(index);
        }
    }
    if aligned.len() != base.shape.bodies.len() || inserted.len() != appended.members.len() {
        return Err("appended bodies do not align with the patch base".into());
    }
    let mut lines = InsertionLines {
        aligned: HashMap::new(),
        inserted: HashMap::new(),
    };
    for (old, &index) in base.shape.bodies.iter().zip(&aligned) {
        let new = &shape.bodies[index];
        if old.path != new.path {
            return Err("aligned body moved to another file".into());
        }
        lines
            .aligned
            .entry(Arc::clone(&old.path))
            .or_default()
            .push((old.line, new.line));
    }
    for pairs in lines.aligned.values_mut() {
        pairs.sort_unstable();
    }
    for &index in &inserted {
        let new = &shape.bodies[index];
        lines
            .inserted
            .entry(Arc::clone(&new.path))
            .or_default()
            .push(new.line);
    }
    let changed: Vec<usize> = aligned
        .iter()
        .zip(&base.shape.bodies)
        // Dense declaration/member IDs (part of the body digest) shift on
        // insertion; identity is owner/name/occurrence, so compare position
        // and text only.
        .filter(|(&index, old)| {
            let new = &shape.bodies[index];
            new.text != old.text || new.line != old.line || new.path != old.path
        })
        .map(|(&index, _)| index)
        .collect();
    let base_index: HashMap<usize, usize> =
        aligned.iter().enumerate().map(|(old, &new)| (new, old)).collect();
    for &index in &changed {
        let old = &base.shape.bodies[base_index[&index]];
        let new = &shape.bodies[index];
        if new.text != old.text && (new.guarded || old.guarded) {
            return Err("changed body declares a static or global var".into());
        }
    }
    if changed.len() + inserted.len() > PATCH_LIMIT {
        return Err("too many bodies to patch".into());
    }
    if first_root_body(frontend).is_some_and(|root| changed.contains(&root) || inserted.contains(&root)) {
        return Err("first root procedure changed".into());
    }
    dm_profile::request_mark("append.admitted");
    let starts = request
        .generation
        .model_table_starts(base.dmb_hash)
        .ok_or("retained model released or differs from the patch base")?;
    let selected: Vec<_> = changed
        .iter()
        .chain(&inserted)
        .map(|&index| &frontend.bodies[index])
        .collect();
    let lowered = crate::cold::body_patch::lower_selected(
        frontend,
        request.resolver,
        crate::cold::body_patch::LinkFacts {
            engine_bytes: request.engine_bytes,
            engine: request.engine,
            references: request.references,
            spellings: request.spellings,
        },
        request.resource_search_context,
        crate::lowering::LoweringConfig {
            workers: request.workers,
            ..Default::default()
        },
        request.memo,
        Some(request.frontend),
        request.executor,
        &selected,
    )?;
    // Freeze new units on their own and extend the tables append-only.
    let mut existing = Vec::new();
    let mut fresh = Vec::new();
    let mut entries = Vec::new();
    for contribution in lowered.contributions {
        let record = contribution.patch_record();
        let identity = record.record.identity();
        if base.units.contains_key(&identity) {
            existing.push((contribution, record));
            continue;
        }
        if !contribution.current_warnings(symbols).map_err(|error| format!("{error}"))?.is_empty() {
            return Err("appended procedure has warnings".into());
        }
        let (unit, unit_entries) =
            crate::symbolic::freeze_appended(contribution, symbols)?;
        let features = unit.bytecode_features();
        if features.external || features.source_features != Default::default() {
            return Err("appended procedure has header-affecting bytecode features".into());
        }
        entries.extend(unit_entries);
        fresh.push((unit, record));
    }
    let (tables, added) = link
        .tables
        .extended(entries, &starts)
        .map_err(|error| format!("append link: {error:?}"))?;
    dm_profile::request_mark("append.tables_extended");
    let mut new_strings = Vec::new();
    for &(key, index) in &added {
        match key {
            dm_link::Key::String(_) => new_strings.push((
                index,
                tables.content(key).ok_or("appended string content")?.to_vec(),
            )),
            dm_link::Key::Proc { .. } | dm_link::Key::Verb { .. } => {}
            other => return Err(format!("append would add {other:?}")),
        }
    }
    // Existing changed bodies: same admission as body patches.
    let mut rows = Vec::new();
    let mut unit_warnings = BTreeMap::new();
    for (contribution, record) in &existing {
        let identity = record.record.identity();
        let old = &base.units[&identity];
        let source = contribution.current_source();
        let moved_only = changed.iter().any(|&index| {
            let body = &frontend.bodies[index];
            body.source.semantic_path == source.semantic_path
                && body.source.line == source.line
                && shape.bodies[index].text == base.shape.bodies[base_index[&index]].text
        });
        if (record.modified || old.modified) && !moved_only {
            return Err(format!("unit {identity:?} has modified instances"));
        }
        if record.footprint() != old.footprint() {
            return Err(format!("unit {identity:?} link footprint changed"));
        }
        let words = record
            .record
            .link_words(&tables, &link.mobs)
            .map_err(|error| format!("unit {identity:?} link: {error:?}"))?;
        let index = tables
            .index(crate::symbolic::unit_key(identity))
            .ok_or("existing unit has no procedure index")?;
        let code = *image
            .proc_code
            .get(index as usize)
            .ok_or("existing unit has no code row")?;
        if !record.record.helper_words(&tables, &link.mobs).map_err(|error| format!("{error:?}"))?.is_empty() {
            return Err(format!("unit {identity:?} has helpers"));
        }
        rows.push((code as usize, words));
        unit_warnings.insert(
            identity,
            contribution
                .current_warnings(symbols)
                .map_err(|error| format!("unit {identity:?} warnings: {error}"))?,
        );
    }
    // Initializers whose debug lines moved are relinked like body patches.
    let shift_failed = std::cell::Cell::new(false);
    let shift = |path: &str, line: u32| match lines.map(path, line as usize) {
        Some(line) => line as u32,
        None => {
            shift_failed.set(true);
            line
        }
    };
    let mut initializers = Vec::with_capacity(link.initializers.len());
    for code in &link.initializers {
        match code
            .relink_shifted(&tables, &link.mobs, &shift)
            .map_err(|error| format!("{:?} relink: {error:?}", code.key))?
        {
            Some((words, moved)) => {
                let index = tables.index(code.key).ok_or("initializer has no index")?;
                let row = *image
                    .proc_code
                    .get(index as usize)
                    .ok_or("initializer has no code row")?;
                rows.push((row as usize, words));
                initializers.push(moved);
            }
            None => initializers.push(code.clone()),
        }
    }
    if shift_failed.get() {
        return Err("a shifted initializer line lies at an ambiguous insertion point".into());
    }
    let mut warnings = (*base.warnings).clone();
    for warning in &mut warnings.prefix {
        if let Some(line) = warning.location.line.as_mut() {
            *line = lines
                .map(&warning.location.semantic_path, *line)
                .ok_or("a declaration warning lies at an ambiguous insertion point")?;
        }
    }
    for (identity, current) in &mut warnings.units {
        if let Some(rebound) = unit_warnings.remove(identity) {
            *current = rebound;
        }
    }
    let local = crate::local_warnings::capture(frontend)
        .map_err(|error| format!("local warnings: {error:?}"))?;
    let output_warnings = warnings.render(local);
    // Owner list order: fresh membership is undeclared callables in reverse
    // encounter order, then declared ones in reverse encounter order, then the
    // engine's own entries. The old list must be reproduced exactly without
    // the new entries, which validates the rule for this class.
    let mut per_owner: BTreeMap<(SymbolId, bool), Vec<(usize, bool, u32, bool)>> = BTreeMap::new();
    for (position, body) in frontend.bodies.iter().enumerate() {
        let Some(member) = tree.member(body.member) else {
            continue;
        };
        let Some(owner) = tree.type_node(member.owner).map(|node| node.path) else {
            continue;
        };
        if !appended.members.iter().any(|&(o, _, _)| o == owner) {
            continue;
        }
        let identity = crate::lowering::source_unit_identity(frontend, body)?.identity;
        let verb = identity.namespace == Namespace::Verb;
        if !appended.members.iter().any(|&(o, _, k)| {
            o == owner && (k == dm_tree::MemberKind::Verb) == verb
        }) {
            continue;
        }
        let index = tables
            .index(crate::symbolic::unit_key(identity))
            .ok_or("owner callable has no procedure index")?;
        per_owner.entry((owner, verb)).or_default().push((
            position,
            member.definition == dm_tree::DefinitionMode::Declare,
            index,
            inserted.contains(&position),
        ));
    }
    let mut list_updates = Vec::new();
    for ((owner, verb), members) in per_owner {
        let order = |include_new: bool| -> Vec<u32> {
            let mut undeclared: Vec<_> = members.iter().filter(|m| !m.1 && (include_new || !m.3)).collect();
            let mut declared: Vec<_> = members.iter().filter(|m| m.1 && (include_new || !m.3)).collect();
            undeclared.sort_by_key(|m| std::cmp::Reverse(m.0));
            declared.sort_by_key(|m| std::cmp::Reverse(m.0));
            undeclared.into_iter().chain(declared).map(|m| m.2).collect()
        };
        let class = tables
            .index(dm_link::Key::Type(owner))
            .ok_or("owner type has no class index")?;
        list_updates.push((class as usize, verb, order(false), order(true)));
    }
    // New procedure records in key order of their appended indexes.
    let mut procedures = Vec::new();
    for (unit, record) in fresh {
        let identity = record.record.identity();
        let index = tables
            .index(crate::symbolic::unit_key(identity))
            .ok_or("appended unit has no procedure index")?;
        let words = record
            .record
            .link_words(&tables, &link.mobs)
            .map_err(|error| format!("appended unit link: {error:?}"))?;
        let declared = appended.members.iter().any(|&(o, n, _)| o == identity.owner && n == identity.name)
            && tree
                .lookup_type(identity.owner)
                .and_then(|owner| {
                    let kind = if identity.namespace == Namespace::Verb {
                        dm_tree::MemberKind::Verb
                    } else {
                        dm_tree::MemberKind::Proc
                    };
                    tree.resolve(owner, identity.name, kind)
                })
                .and_then(|id| tree.member(id))
                .is_some_and(|member| member.definition == dm_tree::DefinitionMode::Declare);
        procedures.push((index, record, crate::composition::append::NewProcedure {
            unit,
            words,
            index,
            declared,
        }));
    }
    procedures.sort_by_key(|(index, _, _)| *index);
    let mut units = (*base.units).clone();
    let mut new_procedures = Vec::new();
    for (_, record, procedure) in procedures {
        units.insert(record.record.identity(), record);
        new_procedures.push(procedure);
    }
    let next = BodyPatchBase {
        shape: Arc::clone(shape),
        units: Arc::new(units),
        inputs: Arc::new(request.inputs),
        archive: request.archive,
        warnings: Arc::new(warnings),
        dmb_hash: 0,
    };
    dm_profile::request_mark("append.linked");
    let patched_rows = rows.len();
    let appended_count = new_procedures.len();
    let dmb = request.generation.patch_model(
        base.dmb_hash,
        |model| crate::composition::append::append_table_strings(model, &new_strings),
        |model, strings| {
            for (row, words) in &rows {
                *model.lists.get_mut(*row).ok_or_else(|| {
                    crate::composition::CompositionError::NonContiguous("code row".into())
                })? = words.as_ref().clone();
            }
            crate::composition::append::emit_procedures(
                model,
                strings,
                &tables,
                symbols,
                new_procedures,
            )?;
            for (class, verb, old, new) in &list_updates {
                let slot = usize::from(!*verb);
                let current = model.classes[*class].lists_and_procs[slot];
                let words = model.lists.get(current as usize).cloned().unwrap_or_default();
                if words.len() < old.len() || words[..old.len()] != old[..] {
                    return Err(crate::composition::CompositionError::NonContiguous(
                        "owner callable list does not follow fresh membership order".into(),
                    ));
                }
                let mut replacement = new.clone();
                replacement.extend_from_slice(&words[old.len()..]);
                let id = crate::composition::append_list(model, replacement)?;
                model.classes[*class].lists_and_procs[slot] = id;
            }
            Ok(())
        },
        crate::composition::PatchLink {
            tables: tables.clone(),
            mobs: link.mobs.clone(),
            initializers,
        },
        next,
        request.executor,
    )?;
    dm_profile::request_mark("append.model_encoded");
    crate::daemon_eprintln!(
        "native append patch: {appended_count} procedures appended, {patched_rows} rows relinked"
    );
    Ok(Patched {
        dmb,
        warnings: output_warnings,
        query: lowered.query,
        changed_bodies: changed.len() + appended_count,
        shifted_initializers: 0,
        patched_rows,
    })
}
