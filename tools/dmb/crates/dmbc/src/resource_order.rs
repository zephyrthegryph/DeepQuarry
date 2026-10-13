//! Native import-phase ordering over pre-normalization grammar facts.
//! Draft: must pass the distinguishing native corpus before production admission.
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SymbolId, SymbolTable};
use dm_tree::allocation_ledger::{AllocationKind, AllocationLedger, NamespaceKind};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;
#[derive(Clone, Debug)]
pub struct ResourceUse {
    pub event: usize,
    pub alias: Arc<str>,
}
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
enum GroupKey {
    Owner(SymbolId),
    Vars(SymbolId),
    Procs(SymbolId),
    Verbs(SymbolId),
    Method(SymbolId, SymbolId),
    Declaration(usize),
    Override(usize),
}
struct Group {
    key: GroupKey,
    owner: SymbolId,
    ordinal: usize,
    authored_at_creation: bool,
    first_resource: usize,
    children: Vec<usize>,
}
fn spelling(symbols: &SymbolTable, id: SymbolId) -> Result<&str, String> {
    symbols
        .text(id)
        .ok_or_else(|| "resource group symbol spelling absent".into())
}
fn lexical_parent(path: &str) -> &str {
    match path.rfind('/') {
        Some(index) if index > 0 => &path[..index],
        _ => "/",
    }
}
fn ensure_owner(
    owner: SymbolId,
    ordinal: usize,
    symbols: &SymbolTable,
    groups: &mut Vec<Group>,
    indexes: &mut BTreeMap<GroupKey, usize>,
    roots: &mut Vec<usize>,
) -> Result<usize, String> {
    if let Some(index) = indexes.get(&GroupKey::Owner(owner)) {
        return Ok(*index);
    }
    let path = spelling(symbols, owner)?;
    let mut ancestors = Vec::new();
    if path == "/" {
        ancestors.push("/");
    } else {
        for (index, byte) in path.bytes().enumerate().skip(1) {
            if byte == b'/' {
                ancestors.push(&path[..index]);
            }
        }
        ancestors.push(path);
    }
    let mut parent: Option<usize> = None;
    for ancestor in ancestors {
        let id = SymbolId::of(ancestor);
        let key = GroupKey::Owner(id);
        let index = if let Some(index) = indexes.get(&key) {
            *index
        } else {
            let index = groups.len();
            groups.push(Group {
                key: key.clone(),
                owner: id,
                ordinal,
                authored_at_creation: ancestor == path,
                first_resource: usize::MAX,
                children: Vec::new(),
            });
            indexes.insert(key, index);
            if let Some(parent) = parent {
                groups[parent].children.push(index);
            } else {
                roots.push(index);
            }
            index
        };
        parent = Some(index);
    }
    parent.ok_or_else(|| "resource owner is not a path".into())
}
fn visit(index: usize, groups: &[Group], out: &mut Vec<usize>) {
    let group = &groups[index];
    if group.owner == SymbolId::of("/") && matches!(group.key, GroupKey::Owner(_)) {
        if group.authored_at_creation {
            out.push(index);
        }
        for child in &group.children {
            visit(*child, groups, out);
        }
        if !group.authored_at_creation {
            out.push(index);
        }
        return;
    }
    let mut own = false;
    for child in &group.children {
        if !own && group.first_resource < groups[*child].ordinal {
            out.push(index);
            own = true;
        }
        visit(*child, groups, out);
    }
    if !own {
        out.push(index);
    }
}
/// Literal uses must have exact parser/AST encounter ordering and archive aliases
/// from captured resource resolution. Prefix imports are verified DMS/interface
/// imports; map-only uses are supplied as suffix imports after code groups.
/// Everything `collect` reads, without source positions: each ledger event's
/// kind and symbols (positions only locate events), the text of explicit
/// parent values (which decide the resolver's parent answers), the resource
/// uses by event, roots and imports. Equal keys give equal phase orders, so a
/// body edit that moves code but keeps these reuses the last order.
fn collect_key(
    ledger: &AllocationLedger,
    text: &str,
    uses: &[ResourceUse],
    known_roots: &BTreeSet<SymbolId>,
    prefix_imports: &[Arc<str>],
    suffix_imports: &[Arc<str>],
) -> u128 {
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    hash.update(b"dmb-resource-phase-order-v1\0");
    let id = |hash: &mut xxhash_rust::xxh3::Xxh3, value: SymbolId| {
        hash.update(&value.bits().to_le_bytes());
    };
    for event in ledger.events.iter() {
        hash.update(&(event.encounter_order as u64).to_le_bytes());
        match event.kind {
            AllocationKind::Type {
                path,
                lexical_owner,
                absolute,
            } => {
                hash.update(&[0, u8::from(absolute)]);
                id(&mut hash, path);
                id(&mut hash, lexical_owner);
            }
            AllocationKind::Namespace {
                owner,
                kind,
                absolute,
            } => {
                hash.update(&[1, kind as u8, u8::from(absolute)]);
                id(&mut hash, owner);
            }
            AllocationKind::Field {
                owner,
                name,
                formal,
                var_namespace,
                ..
            } => {
                hash.update(&[2, u8::from(formal), u8::from(var_namespace)]);
                id(&mut hash, owner);
                id(&mut hash, name);
            }
            AllocationKind::Procedure {
                owner,
                formal,
                verb,
                name,
                ..
            } => {
                hash.update(&[3, u8::from(formal), u8::from(verb)]);
                id(&mut hash, owner);
                id(&mut hash, name);
            }
            AllocationKind::Parent { owner, value } => {
                hash.update(&[4]);
                id(&mut hash, owner);
                let value = text.get(value.range()).unwrap_or("\u{0}<outside>");
                hash.update(&(value.len() as u64).to_le_bytes());
                hash.update(value.as_bytes());
            }
        }
    }
    hash.update(&(uses.len() as u64).to_le_bytes());
    for usage in uses {
        hash.update(&(usage.event as u64).to_le_bytes());
        hash.update(usage.alias.as_bytes());
        hash.update(b"\0");
    }
    for root in known_roots {
        id(&mut hash, *root);
    }
    for (marker, imports) in [(b"<", prefix_imports), (b">", suffix_imports)] {
        hash.update(marker);
        for import in imports {
            hash.update(import.as_bytes());
            hash.update(b"\0");
        }
    }
    hash.digest128()
}

pub fn collect<R: Resolver>(
    ledger: &AllocationLedger,
    uses: &[ResourceUse],
    symbols: &SymbolTable,
    resolver: &R,
    known_roots: &BTreeSet<SymbolId>,
    prefix_imports: &[Arc<str>],
    suffix_imports: &[Arc<str>],
) -> Result<Vec<Arc<str>>, String> {
    let mut groups = Vec::new();
    let mut indexes = BTreeMap::new();
    let mut roots = Vec::new();
    let mut event_groups = vec![None; ledger.events.len()];
    let mut global = BTreeSet::new();
    let mut reparented = BTreeSet::new();
    for (event_index, event) in ledger.events.iter().enumerate() {
        if event.encounter_order != event_index {
            return Err("resource allocation ledger encounter order mismatch".into());
        }
        let owner = match event.kind {
            AllocationKind::Type { path, .. } => path,
            AllocationKind::Namespace { owner, .. }
            | AllocationKind::Field { owner, .. }
            | AllocationKind::Procedure { owner, .. }
            | AllocationKind::Parent { owner, .. } => owner,
        };
        if matches!(event.kind, AllocationKind::Field { .. }) && owner == SymbolId::of("/") {
            global.insert(event_index);
            continue;
        }
        let parent = ensure_owner(
            owner,
            event_index,
            symbols,
            &mut groups,
            &mut indexes,
            &mut roots,
        )?;
        let phase = match event.kind {
            AllocationKind::Namespace {
                kind: NamespaceKind::Var,
                ..
            } => Some(GroupKey::Vars(owner)),
            AllocationKind::Namespace {
                kind: NamespaceKind::Proc,
                ..
            } => Some(GroupKey::Procs(owner)),
            AllocationKind::Namespace {
                kind: NamespaceKind::Verb,
                ..
            } => Some(GroupKey::Verbs(owner)),
            AllocationKind::Field {
                formal: true,
                var_namespace: true,
                ..
            } => Some(GroupKey::Vars(owner)),
            AllocationKind::Field { formal: true, .. } => Some(GroupKey::Declaration(event_index)),
            AllocationKind::Field { formal: false, .. } => Some(GroupKey::Override(event_index)),
            AllocationKind::Procedure {
                formal: false,
                name,
                ..
            } => Some(GroupKey::Method(owner, name)),
            AllocationKind::Procedure { verb: true, .. } => Some(GroupKey::Verbs(owner)),
            AllocationKind::Procedure { .. } => Some(GroupKey::Procs(owner)),
            AllocationKind::Parent { .. } => {
                reparented.insert(owner);
                Some(GroupKey::Override(event_index))
            }
            _ => None,
        };
        let group = if let Some(key) = phase {
            if let Some(index) = indexes.get(&key) {
                *index
            } else {
                let index = groups.len();
                groups.push(Group {
                    key: key.clone(),
                    owner,
                    ordinal: event_index,
                    authored_at_creation: true,
                    first_resource: event_index,
                    children: Vec::new(),
                });
                indexes.insert(key, index);
                groups[parent].children.push(index);
                index
            }
        } else {
            parent
        };
        event_groups[event_index] = Some(group);
    }
    for usage in uses {
        if usage.event >= ledger.events.len() {
            return Err("resource use allocation event absent".into());
        }
        if let Some(group) = event_groups[usage.event] {
            groups[group].first_resource = groups[group].first_resource.min(usage.event);
        }
    }
    roots.sort_by_key(|index| {
        (
            !known_roots.contains(&groups[*index].owner),
            groups[*index].ordinal,
        )
    });
    let mut pending = Vec::new();
    for root in roots {
        visit(root, &groups, &mut pending);
    }
    let mut ranks = BTreeMap::new();
    // Every phase group for one owner has the same explicit-parent blockers.
    // Compute those once; retain the existing ordered deferred-pass scheduler.
    let mut owner_blockers: BTreeMap<SymbolId, Vec<SymbolId>> = BTreeMap::new();
    while !pending.is_empty() {
        let mut deferred = Vec::new();
        for index in &pending {
            let owner = groups[*index].owner;
            if let std::collections::btree_map::Entry::Vacant(entry) = owner_blockers.entry(owner) {
                let mut ancestor = spelling(symbols, owner)?;
                let mut blockers = Vec::new();
                while ancestor != "/" {
                    let ancestor_id = SymbolId::of(ancestor);
                    if reparented.contains(&ancestor_id) {
                        let parent = match resolver.resolve(ResolveQuery::Parent(ancestor_id)) {
                            ResolvedMeaning::Symbol(parent) => Some(parent),
                            ResolvedMeaning::Missing => None,
                            ResolvedMeaning::Unsupported(_) => {
                                return Err("resource phase parent is unsupported".into())
                            }
                            _ => return Err("resource phase parent answer is inconsistent".into()),
                        };
                        if let Some(parent) = parent {
                            if parent != SymbolId::of(lexical_parent(ancestor))
                                && indexes.contains_key(&GroupKey::Owner(parent))
                            {
                                blockers.push(parent);
                            }
                        }
                    }
                    ancestor = lexical_parent(ancestor);
                }
                entry.insert(blockers);
            }
            let blocked = owner_blockers[&owner]
                .iter()
                .any(|parent| !ranks.contains_key(&GroupKey::Owner(*parent)));
            if blocked {
                deferred.push(*index);
            } else {
                let rank = ranks.len();
                ranks.insert(groups[*index].key.clone(), rank);
            }
        }
        if deferred.len() == pending.len() {
            return Err("resource phase dependencies make no progress".into());
        }
        pending = deferred;
    }
    let mut ordered = uses.iter().enumerate().collect::<Vec<_>>();
    ordered.sort_by_key(|(encounter, usage)| {
        (
            if global.contains(&usage.event) { 0 } else { 1 },
            event_groups[usage.event]
                .and_then(|group| ranks.get(&groups[group].key).copied())
                .unwrap_or(usize::MAX),
            *encounter,
        )
    });
    let mut result = Vec::new();
    let mut aliases = BTreeSet::new();
    for alias in prefix_imports
        .iter()
        .chain(ordered.into_iter().map(|(_, usage)| &usage.alias))
        .chain(suffix_imports)
    {
        if aliases.insert(alias.clone()) {
            result.push(alias.clone());
        }
    }
    Ok(result)
}

/// Derive code literal phases from the captured expanded grammar, resolving
/// aliases only through the already captured lookup ledger. Non-code imports
/// remain explicit until their DMS/skin/map phase contracts are admitted.
pub fn captured_archive_order<R: Resolver>(
    frontend: &dm_tree::frontend::ColdFrontend,
    captured: &dm_resources::capture::CapturedResources,
    resolver: &R,
    known_roots: &BTreeSet<SymbolId>,
    prefix_imports: &[Arc<str>],
    suffix_imports: &[Arc<str>],
) -> Result<Vec<usize>, String> {
    let aliases = captured
        .resources
        .inputs
        .iter()
        .map(|input| input.archive_name.as_str())
        .collect::<Vec<_>>();
    let source_literals = captured
        .literals
        .get(..captured.source_literal_count)
        .ok_or("resource source literal prefix outside capture")?;
    archive_order(
        frontend,
        &aliases,
        &captured.lookups,
        source_literals,
        resolver,
        known_roots,
        prefix_imports,
        suffix_imports,
    )
}
#[allow(clippy::too_many_arguments)] // Existing resource-order boundary over payload-free facts.
pub fn metadata_archive_order<R: Resolver>(
    frontend: &dm_tree::frontend::ColdFrontend,
    catalog: &dm_resources::catalog::ResourceCatalog,
    demand: &dm_resources::capture::ResourceDemand,
    resolver: &R,
    known_roots: &BTreeSet<SymbolId>,
    prefix: &[Arc<str>],
    suffix: &[Arc<str>],
) -> Result<Vec<usize>, String> {
    let aliases = catalog
        .record()
        .aliases
        .iter()
        .map(|alias| alias.name.as_str())
        .collect::<Vec<_>>();
    let literals = demand
        .literals
        .get(..demand.source_literal_count)
        .ok_or("resource literal prefix outside demand")?;
    archive_order(
        frontend,
        &aliases,
        &catalog.record().lookups,
        literals,
        resolver,
        known_roots,
        prefix,
        suffix,
    )
}
#[allow(clippy::too_many_arguments)] // Same shared grammar traversal for cold and retained archives.
fn archive_order<R: Resolver>(
    frontend: &dm_tree::frontend::ColdFrontend,
    aliases: &[&str],
    captured_lookups: &[dm_resources::native_resolver::CapturedResourceLookup],
    source_literals: &[dm_resources::capture::LiteralRequest],
    resolver: &R,
    known_roots: &BTreeSet<SymbolId>,
    prefix_imports: &[Arc<str>],
    suffix_imports: &[Arc<str>],
) -> Result<Vec<usize>, String> {
    use dm_resources::native_resolver::CapturedResourceOutcome;
    let mut lookups = BTreeMap::new();
    for lookup in captured_lookups {
        if lookups
            .insert(lookup.path.as_str(), lookup.outcome)
            .is_some()
        {
            return Err("duplicate captured resource lookup path".into());
        }
    }
    let _events_timer = dm_profile::detail_timer("resources.order.event_literals");
    let mut uses = Vec::new();
    for (event, literal) in indexed_event_literals(
        &frontend.allocation_ledger,
        &frontend.expanded.text,
        source_literals,
    )? {
        match lookups.get(literal.path.as_str()) {
            Some(CapturedResourceOutcome::Found(ordinal)) => {
                let alias = aliases
                    .get(*ordinal)
                    .ok_or("captured resource lookup ordinal outside resources")?;
                uses.push(ResourceUse {
                    event,
                    alias: (*alias).into(),
                });
            }
            Some(CapturedResourceOutcome::Missing) => {}
            Some(CapturedResourceOutcome::Unsupported) => {
                return Err("resource phase requires unsupported captured literal".into())
            }
            None => {
                return Err(format!(
                    "resource phase literal has no captured lookup: {}",
                    literal.path
                ))
            }
        }
    }
    drop(_events_timer);
    let _collect_timer = dm_profile::detail_timer("resources.order.collect");
    let key = collect_key(
        &frontend.allocation_ledger,
        frontend.expanded.text.as_str(),
        &uses,
        known_roots,
        prefix_imports,
        suffix_imports,
    );
    static LAST: std::sync::Mutex<Option<(u128, Arc<Vec<Arc<str>>>)>> =
        std::sync::Mutex::new(None);
    let cached = LAST
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .filter(|(last, _)| *last == key)
        .map(|(_, order)| Arc::clone(order));
    let ordered_aliases = match cached {
        Some(order) => order.as_ref().clone(),
        None => {
            let order = collect(
                &frontend.allocation_ledger,
                &uses,
                frontend.snapshot.tree.symbols(),
                resolver,
                known_roots,
                prefix_imports,
                suffix_imports,
            )?;
            *LAST.lock().unwrap_or_else(|e| e.into_inner()) =
                Some((key, Arc::new(order.clone())));
            order
        }
    };
    let mut ordinals = BTreeMap::new();
    for (ordinal, alias) in aliases.iter().enumerate() {
        if ordinals.insert(*alias, ordinal).is_some() {
            return Err("duplicate archive alias in captured resource inputs".into());
        }
    }
    let result = ordered_aliases
        .iter()
        .map(|alias| {
            ordinals
                .get(alias.as_ref())
                .copied()
                .ok_or_else(|| format!("resource phase alias absent from captured input: {alias}"))
        })
        .collect::<Result<Vec<_>, _>>()?;
    if result.len() != aliases.len() {
        return Err("resource phase grammar does not cover every captured archive input".into());
    }
    Ok(result)
}

fn indexed_event_literals<'a>(
    ledger: &AllocationLedger,
    source: &str,
    literals: &'a [dm_resources::capture::LiteralRequest],
) -> Result<Vec<(usize, &'a dm_resources::capture::LiteralRequest)>, String> {
    let mut sorted = literals.iter().collect::<Vec<_>>();
    sorted.sort_by_key(|literal| literal.span.start);
    for literal in &sorted {
        let text = source
            .get(literal.span.range())
            .ok_or("resource literal source span outside expanded capture")?;
        if text.as_bytes().first() != Some(&b'\'')
            || text.as_bytes().last() != Some(&b'\'')
            || text.get(1..text.len().saturating_sub(1)) != Some(literal.path.as_str())
        {
            return Err("resource literal path differs from its captured source span".into());
        }
    }
    let mut result = Vec::with_capacity(literals.len());
    for (event, allocation) in ledger.events.iter().enumerate() {
        let span = match allocation.kind {
            AllocationKind::Field { initializer, .. } => initializer,
            AllocationKind::Procedure { body, .. } => Some(body),
            _ => None,
        };
        let Some(span) = span else { continue };
        source
            .get(span.range())
            .ok_or("allocation resource span outside captured expanded source")?;
        let first = sorted.partition_point(|literal| literal.span.start < span.start);
        let last = sorted.partition_point(|literal| literal.span.start < span.end);
        for literal in &sorted[first..last] {
            if literal.span.end > span.end {
                return Err("resource literal crosses allocation grammar boundary".into());
            }
            result.push((event, *literal));
        }
    }
    Ok(result)
}

/// Certified single-DMF imports precede code, with skin assets before the raw
/// DMF. Map literals follow code in captured template/atom/assignment order.
/// Multiple skin import phasing remains unsupported; selection itself is known.
pub type NonTextImports = (Vec<Arc<str>>, Vec<Arc<str>>);
pub fn nontext_imports(
    nontext: &crate::non_text::CapturedNonText,
    captured: &dm_resources::capture::CapturedResources,
) -> Result<NonTextImports, String> {
    let aliases: Vec<&str> = captured
        .resources
        .inputs
        .iter()
        .map(|input| input.archive_name.as_str())
        .collect();
    import_order(nontext, &aliases, &captured.lookups)
}
pub fn metadata_nontext_imports(
    nontext: &crate::non_text::CapturedNonText,
    catalog: &dm_resources::catalog::ResourceCatalog,
) -> Result<NonTextImports, String> {
    let aliases: Vec<&str> = catalog
        .record()
        .aliases
        .iter()
        .map(|input| input.name.as_str())
        .collect();
    import_order(nontext, &aliases, &catalog.record().lookups)
}
fn import_order(
    nontext: &crate::non_text::CapturedNonText,
    aliases: &[&str],
    lookups: &[dm_resources::native_resolver::CapturedResourceLookup],
) -> Result<NonTextImports, String> {
    use dm_resources::native_resolver::CapturedResourceOutcome;
    if nontext.skin.model.interfaces.len() > 1 {
        return Err("multiple DMF resource import phases require a distinguishing contract".into());
    }
    let mut lookup_outcomes = BTreeMap::new();
    let mut normalized_paths = BTreeMap::new();
    for lookup in lookups {
        // Preserve the previous first-encountered spelling for normalized aliases.
        lookup_outcomes
            .entry(lookup.path.as_str())
            .or_insert(lookup.outcome);
        normalized_paths
            .entry(lookup.path.replace('\\', "/"))
            .or_insert(lookup.path.as_str());
    }
    let lookup = |path: &str| -> Result<Option<Arc<str>>, String> {
        let found = lookup_outcomes
            .get(path)
            .ok_or_else(|| format!("nontext resource has no captured lookup: {path}"))?;
        match *found {
            CapturedResourceOutcome::Found(ordinal) => Ok(Some(
                (*aliases
                    .get(ordinal)
                    .ok_or("nontext resource lookup ordinal outside captured aliases")?)
                .into(),
            )),
            CapturedResourceOutcome::Missing => Ok(None),
            CapturedResourceOutcome::Unsupported => {
                Err("nontext resource import is unsupported".into())
            }
        }
    };
    let mut prefix = Vec::new();
    if let Some(skin) = nontext.skin.model.selected() {
        for dependency in skin.resource_dependencies.iter() {
            // Lookups retain authored spelling; normalized dependency spellings
            // are equivalent only when the exact captured request agrees.
            let path = normalized_paths.get(dependency.as_ref()).ok_or_else(|| {
                format!("skin dependency absent from captured lookup: {dependency}")
            })?;
            if let Some(alias) = lookup(path)? {
                prefix.push(alias);
            }
        }
        if !aliases
            .iter()
            .any(|input| *input == skin.archive_alias.as_ref())
        {
            return Err("selected skin raw resource absent from capture".into());
        }
        prefix.push(skin.archive_alias.clone());
    }
    let mut suffix = Vec::new();
    for map in nontext.maps.iter() {
        for template in map.template_origins.iter() {
            for atom in template.atoms.iter() {
                for assignment in atom.assignments.iter() {
                    let source = map
                        .captured
                        .source
                        .get(assignment.value_span.range())
                        .ok_or("map import source span outside capture")?;
                    for literal in dm_resources::capture::discover_literals(source)
                        .map_err(|error| error.to_string())?
                    {
                        if let Some(alias) = lookup(&literal.path)? {
                            suffix.push(alias);
                        }
                    }
                }
            }
        }
    }
    Ok((prefix, suffix))
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Parents(BTreeMap<SymbolId, Option<SymbolId>>);
    impl Resolver for Parents {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            match query {
                ResolveQuery::Parent(owner) => self
                    .0
                    .get(&owner)
                    .and_then(|parent| *parent)
                    .map_or(ResolvedMeaning::Missing, ResolvedMeaning::Symbol),
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    fn fixture(name: &str) -> (AllocationLedger, SymbolTable, Vec<ResourceUse>, Parents) {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/translation/resource_archive_order");
        let source = std::fs::read_to_string(root.join(format!("{name}.dm"))).unwrap();
        let ast = dm_syntax::parse(&source);
        assert!(ast.diagnostics.is_empty(), "{name}");
        let mut symbols = SymbolTable::default();
        let ledger = dm_tree::allocation_ledger::capture(&ast.items, "/", &mut symbols).unwrap();
        let mut uses = Vec::new();
        let mut parents = BTreeMap::new();
        for (event_index, event) in ledger.events.iter().enumerate() {
            let span = match event.kind {
                AllocationKind::Field { initializer, .. } => initializer,
                AllocationKind::Procedure { body, .. } => Some(body),
                AllocationKind::Parent { owner, value } => {
                    let parsed = dm_syntax::parse_expression(source[value.range()].trim());
                    assert!(parsed.diagnostics.is_empty());
                    let parent = match parsed.expr.unwrap().kind {
                        dm_syntax::ExprKind::TypePath(path) => Some(symbols.intern(&path).unwrap()),
                        dm_syntax::ExprKind::Literal(null) if null == "null" => None,
                        _ => panic!("parent fixture expression unsupported"),
                    };
                    parents.insert(owner, parent);
                    None
                }
                _ => None,
            };
            if let Some(span) = span {
                for literal in
                    dm_resources::capture::discover_literals(&source[span.range()]).unwrap()
                {
                    uses.push(ResourceUse {
                        event: event_index,
                        alias: literal.path.replace('\\', "/").into(),
                    });
                }
            }
        }
        let captured = dm_resources::capture::discover_literals(&source).unwrap();
        let indexed = indexed_event_literals(&ledger, &source, &captured).unwrap();
        assert_eq!(
            indexed
                .iter()
                .map(|(event, literal)| (*event, literal.path.replace('\\', "/")))
                .collect::<Vec<_>>(),
            uses.iter()
                .map(|resource| (resource.event, resource.alias.to_string()))
                .collect::<Vec<_>>(),
            "{name}"
        );
        (ledger, symbols, uses, Parents(parents))
    }
    #[test]
    fn distinguishing_native_phase_archives_match_exact_alias_order() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../fixtures/translation/resource_archive_order");
        let known = [
            "/",
            "/datum",
            "/obj",
            "/mob",
            "/turf",
            "/area",
            "/client",
            "/world",
            "/atom",
            "/image",
            "/mutable_appearance",
        ]
        .map(SymbolId::of)
        .into_iter()
        .collect();
        for name in [
            "reparent_next_pass",
            "reparented_descendants",
            "first_resource_body",
            "procedure_group_first",
            "field_group_first",
            "client_procedure_namespaces",
            "bare_method_empty_phase",
            "field_override_sequence",
            "empty_variable_namespace",
            "relative_variable_phase",
            "relative_typed_variable_phase",
            "ast_containers",
            "cross_native_roots",
            "ancestor_subtrees",
            "const_static_procstatic",
            "siblings_reopen",
            "explicit_lexical_parent",
            "explicit_root",
            "late_explicit_root",
            "global_new_forward",
            "global_proc_after_class",
            "implicit_parent_middle",
            "parent_early_siblings",
            "parent_late_siblings",
            "parent_late",
            "reparent_parent_late",
            "reparented_procedure_group",
            "empty_block_var",
            "empty_decl_var",
            "empty_block_proc",
            "empty_decl_proc",
        ] {
            let (ledger, symbols, uses, parents) = fixture(name);
            let actual = collect(&ledger, &uses, &symbols, &parents, &known, &[], &[]).unwrap();
            let raw = std::fs::read(root.join(format!("{name}.native.rsc.bin"))).unwrap();
            let mut cursor = std::io::Cursor::new(raw);
            let mut expected = Vec::new();
            while let Some(entry) = byond_dmb::rsc::read_entry(&mut cursor).unwrap() {
                if let byond_dmb::rsc::Entry::Named(record) = entry {
                    expected.push(String::from_utf8(record.name).unwrap());
                }
            }
            assert_eq!(
                actual.iter().map(|name| name.as_ref()).collect::<Vec<_>>(),
                expected.iter().map(String::as_str).collect::<Vec<_>>(),
                "{name}"
            );
        }
    }
}
