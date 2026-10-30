//! Original stored_refs policy over original declarations and borrowed bodies.
//! No inferred value table, second parser, copied model, or lexical type guesses.
use super::*;
use crate::policy_inputs::{PolicyInputs, PolicyRole};
use dm_ir::PackedU128;
use dm_tree::{DefinitionMode, MemberKind, SemanticTree};
use std::{collections::HashSet, path::Path};
pub struct StoredPolicy<'a> {
    pub exempt_types: &'a [String],
    pub registry: &'a [String],
    pub transient_types: &'a [String],
    pub work_queues: &'a [String],
    pub relations: &'a HashMap<String, Vec<String>>,
    pub init_only: &'a [(String, String)],
    pub has_schema: &'a dyn Fn(&str, &str) -> bool,
}
#[derive(Debug, Eq, PartialEq)]
pub struct StoredFinding {
    pub rule: &'static str,
    pub rel: String,
    pub line: usize,
    pub message: String,
    pub ident: String,
}
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
enum Place {
    Member(String, String),
    Static(String, usize),
}
fn charge(remaining: &mut usize, n: usize) -> Result<(), Unsupported> {
    *remaining = remaining.checked_sub(n).ok_or_else(|| {
        Unsupported("stored-reference admission exceeded before allocation".into())
    })?;
    Ok(())
}
fn strings_charge(parts: &[&str], remaining: &mut usize) -> Result<(), Unsupported> {
    let n = parts
        .iter()
        .try_fold(512usize, |n, p| n.checked_add(p.len().checked_mul(8)?))
        .ok_or_else(|| Unsupported("stored-reference accounting overflow".into()))?;
    charge(remaining, n)
}
fn maximum_spelling(table: &dm_ir::SymbolTable) -> usize {
    let mut longest = 0;
    let storage = table.visit_storage(|_, s| longest = longest.max(s.len()));
    if let Some(parent) = storage.parent {
        longest = longest.max(maximum_spelling(parent));
    }
    longest
}
/// Scalar census over ORIGINAL issued header spans and provider path widths.
/// No source spelling allocation, second parser, or retained declaration table.
fn maximum_policy_temporary_width(
    archive: &dm_tree::frontend::BodyArchive,
    inputs: &PolicyInputs,
    root: &Path,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<usize, Unsupported> {
    fn header_width(
        item: dm_tree::frontend::ItemView<'_>,
        depth: usize,
        ancestor_width: usize,
        checkpoint: &mut dyn FnMut() -> Result<(), String>,
    ) -> Result<usize, Unsupported> {
        checkpoint().map_err(Unsupported)?;
        if depth > 128 {
            return Err(Unsupported(
                "stored original header census exceeds bounded nesting admission".into(),
            ));
        }
        let span = item.header_span();
        let own_width = span
            .end
            .checked_sub(span.start)
            .ok_or_else(|| Unsupported("stored original header span is reversed".into()))?;
        // Grouped type/var headers concatenate into one effective declaration
        // path. Reserve cumulative ancestors plus separators, not just a max
        // individual header (normalization can erase every qualifier).
        let current_width = ancestor_width
            .checked_add(own_width)
            .and_then(|n| n.checked_add(1))
            .ok_or_else(|| {
                Unsupported("stored cumulative original header width overflow".into())
            })?;
        let mut widest = current_width;
        // Procedure children are executable syntax, not declaration properties.
        if !matches!(
            item.kind(),
            dm_syntax::ItemKind::Proc | dm_syntax::ItemKind::Verb
        ) {
            for child in item.children() {
                widest = widest.max(header_width(child, depth + 1, current_width, checkpoint)?);
            }
        }
        Ok(widest)
    }
    let mut widest = maximum_spelling(archive.tree().symbols());
    // OsStr::len is its encoded platform width. UTF8-lossy replacement can
    // expand an invalid byte to three bytes; reserve that without formatting.
    for path in std::iter::once(root).chain(inputs.files().map(|f| f.path().as_path())) {
        checkpoint().map_err(Unsupported)?;
        widest = widest.max(
            path.as_os_str()
                .len()
                .checked_mul(3)
                .ok_or_else(|| Unsupported("stored provider path expansion overflow".into()))?,
        );
    }
    let mut headers: Result<usize, Unsupported> = Ok(0usize);
    archive.visit_storage(|_, syntax, _| {
        headers = syntax.items().try_fold(0usize, |wide, item| {
            Ok(wide.max(header_width(item, 0, 0, &mut checkpoint)?))
        });
    });
    Ok(widest.max(headers?))
}

fn text(tree: &SemanticTree, id: SymbolId) -> Result<&str, Unsupported> {
    tree.symbols()
        .text(id)
        .ok_or_else(|| Unsupported("stored-reference original spelling missing".into()))
}
fn ancestry(
    tree: &SemanticTree,
    profile: PackedU128,
    path: &str,
) -> Result<std::sync::Arc<[SymbolId]>, Unsupported> {
    if !tree
        .checker_source_type_presence(profile, path)
        .map_err(|e| Unsupported(format!("{e:?}")))?
    {
        return Ok(std::sync::Arc::from([]));
    }
    match Resolver::resolve(tree, Q::Ancestry(SymbolId::of(path))) {
        M::Symbols(xs) => Ok(xs),
        _ => Err(Unsupported(
            "stored-reference original ancestry unavailable".into(),
        )),
    }
}
fn subtype(
    tree: &SemanticTree,
    profile: PackedU128,
    child: &str,
    parent: &str,
) -> Result<bool, Unsupported> {
    if child == parent {
        return Ok(true);
    }
    Ok(ancestry(tree, profile, child)?.contains(&SymbolId::of(parent)))
}
fn compatible(
    tree: &SemanticTree,
    profile: PackedU128,
    a: &str,
    b: &str,
) -> Result<bool, Unsupported> {
    Ok(a == b || subtype(tree, profile, a, b)? || subtype(tree, profile, b, a)?)
}
fn holder_exempt(
    tree: &SemanticTree,
    profile: PackedU128,
    p: &StoredPolicy<'_>,
    owner: &str,
) -> Result<bool, Unsupported> {
    if owner != "/datum/pooled" && subtype(tree, profile, owner, "/datum/pooled")? {
        return Ok(true);
    }
    for ty in p.transient_types {
        if subtype(tree, profile, owner, ty)? {
            return Ok(true);
        }
    }
    Ok(false)
}
fn related(
    tree: &SemanticTree,
    profile: PackedU128,
    p: &StoredPolicy<'_>,
    owner: &str,
    name: &str,
) -> Result<bool, Unsupported> {
    if let Some(types) = p.relations.get(name) {
        for ty in types {
            if compatible(tree, profile, owner, ty)? {
                return Ok(true);
            }
        }
    }
    Ok(false)
}
fn node(mut e: &Expr) -> &Expr {
    while let ExprKind::Group(i) = &e.kind {
        e = i
    }
    e
}
fn literal(e: &Expr) -> Option<&[Expr]> {
    let ExprKind::Call { callee, args } = &node(e).kind else {
        return None;
    };
    matches!(&callee.kind,ExprKind::Ident(n) if n=="list").then_some(args.as_ref())
}
// Old Base follow chains observe calls root-first, before argument children.
// A Group is a separate Base and intentionally terminates this chain.
fn method_chain<'a>(e: &'a Expr, out: &mut Vec<(&'a Expr, &'a Expr, &'a str, &'a [Expr])>) {
    match &e.kind {
        ExprKind::Call { callee, args } => match &callee.kind {
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => {
                method_chain(object, out);
                out.push((e, object, selector, args));
            }
            _ => (),
        },
        ExprKind::Member { object, .. }
        | ExprKind::SafeMember { object, .. }
        | ExprKind::Index { object, .. }
        | ExprKind::SafeIndex { object, .. } => method_chain(object, out),
        _ => (),
    }
}
fn stored_ref(w: &Walker<'_, SemanticTree>, e: &Expr) -> Result<bool, Unsupported> {
    if let Some(args) = literal(e) {
        for arg in args {
            if let ExprKind::Binary { op, lhs, rhs } = &node(arg).kind {
                if op == "=" {
                    if stored_ref(w, lhs)? || stored_ref(w, rhs)? {
                        return Ok(true);
                    }
                    continue;
                }
            }
            if stored_ref(w, arg)? {
                return Ok(true);
            }
        }
        return Ok(false);
    }
    match w.player_link_receiver_type(e)? {
        Some(t) => w.is_ref(&t),
        None => Ok(false),
    }
}
fn member_place(
    w: &Walker<'_, SemanticTree>,
    owner: &str,
    name: &str,
) -> Result<Option<Place>, Unsupported> {
    if owner.is_empty() {
        return Ok(None);
    }
    let profile = w
        .tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("stored place needs checker profile".into()))?;
    if !w
        .tree
        .checker_source_type_presence(profile, owner)
        .map_err(|e| Unsupported(format!("{e:?}")))?
    {
        return Ok(None);
    }
    Ok(crate::checker_variable_facts::variable(
        w.tree,
        w.tree,
        profile,
        SymbolId::of(owner),
        SymbolId::of(name),
    )
    .map_err(Unsupported)?
    .map(|v| text(w.tree, v.owner).map(|o| Place::Member(o.into(), name.into())))
    .transpose()?)
}
fn place_of(
    sc: &stored_refs_scope::StoredScope<'_>,
    root: &Path,
    rel: &str,
    e: &Expr,
    inputs: &PolicyInputs,
) -> Result<Option<Place>, Unsupported> {
    let w = &sc.walker;
    match &node(e).kind {
        ExprKind::Ident(n) => {
            if w.locals.contains_key(n) {
                return sc
                    .static_lists
                    .get(n)
                    .map(|at| {
                        let source = inputs
                            .archive()
                            .original_policy_line(at.start)
                            .map_err(Unsupported)?;
                        let (_, line) = point(inputs, root, &source.path, source.line)?;
                        Ok(Place::Static(rel.into(), line))
                    })
                    .transpose();
            }
            member_place(w, text(w.tree, w.owner)?, n)
        }
        ExprKind::Member {
            object, selector, ..
        }
        | ExprKind::SafeMember {
            object, selector, ..
        } => match w.player_link_receiver_type(object)? {
            Some(t) => member_place(w, &t, selector),
            None => Ok(None),
        },
        _ => Ok(None),
    }
}
fn list_place(w: &Walker<'_, SemanticTree>, p: &Place) -> Result<bool, Unsupported> {
    let Place::Member(owner, name) = p else {
        return Ok(true);
    };
    let profile = w
        .tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("stored list profile unavailable".into()))?;
    let Some(fact) = crate::checker_variable_facts::variable(
        w.tree,
        w.tree,
        profile,
        SymbolId::of(owner),
        SymbolId::of(name),
    )
    .map_err(Unsupported)?
    else {
        return Ok(false);
    };
    if let Some(formal) = fact.formal {
        let property = w
            .archive
            .ok_or_else(|| Unsupported("stored list archive missing".into()))?
            .checker_variable_properties(formal, profile)
            .map_err(Unsupported)?;
        return Ok(property
            .declared_hint()
            .is_none_or(|t| t == "/list" || t.starts_with("/list/")));
    }
    Ok(fact.metadata.declared_type.is_none()
        || fact.metadata.declared_type == Some(SymbolId::of("/list")))
}
fn point(
    inputs: &PolicyInputs,
    root: &Path,
    path: &Path,
    line: usize,
) -> Result<(String, usize), Unsupported> {
    let f = inputs
        .file(path)
        .ok_or_else(|| Unsupported("stored source was not captured".into()))?;
    if !f.is_compiled() || f.role() != PolicyRole::DmSource {
        return Err(Unsupported(
            "stored source is not original compiled DM".into(),
        ));
    }
    let rel = dm_preprocess::regions::relative_filesystem_path(path, root)
        .ok_or_else(|| Unsupported("stored source is outside root".into()))?
        .to_string_lossy()
        .replace('\\', "/");
    Ok((
        rel,
        f.analyze_display_line(line)
            .map_err(|e| Unsupported(e.to_string()))?,
    ))
}
/// Complete legacy observations on supported ORIGINAL primary domains. Qualified
/// parameter receipts are mandatory; unissued local-array traversal REFUSES.
pub fn stored_findings(
    inputs: &PolicyInputs,
    root: &Path,
    p: &StoredPolicy<'_>,
    exempt: impl Fn(&str) -> bool,
    remaining: &mut usize,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<StoredFinding>, Unsupported> {
    let checkpoint = std::cell::RefCell::new(checkpoint);
    (checkpoint.borrow_mut())().map_err(Unsupported)?;
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("stored references need original checker hierarchy".into()))?;
    // Serial field/return-property projection may transiently normalize original
    // symbol spellings. Reserve its peak before the first such helper call;
    // the original shared symbol owners themselves are not copied or recharged.
    let property_temporary =
        maximum_policy_temporary_width(archive, inputs, root, || (checkpoint.borrow_mut())())?
            .checked_mul(64)
            .and_then(|n| n.checked_add(4096))
            .ok_or_else(|| Unsupported("stored property temporary accounting overflow".into()))?;
    charge(remaining, property_temporary)?;
    let mut excluded = Vec::new();
    for t in p.exempt_types.iter().chain(p.registry) {
        strings_charge(&[t], remaining)?;
        excluded.push(t.clone());
    }
    // Own formal variables, retaining the ORIGINAL first name encounter order.
    let mut seen = HashSet::new();
    let mut vars = Vec::new();
    let mut seeds = Vec::new();
    charge(
        remaining,
        tree.members()
            .len()
            .checked_mul(64)
            .ok_or_else(|| Unsupported("stored declaration-order accounting overflow".into()))?,
    )?;
    let mut declarations = tree
        .members()
        .iter()
        .enumerate()
        .filter(|(_, m)| m.kind == MemberKind::Var && m.definition == DefinitionMode::Declare)
        .collect::<Vec<_>>();
    declarations.sort_by_key(|(index, m)| (m.owner.index(), *index));
    for (_, m) in declarations {
        (checkpoint.borrow_mut())().map_err(Unsupported)?;
        let owner = tree
            .type_node(m.owner)
            .ok_or_else(|| Unsupported("stored own owner missing".into()))?
            .path;
        if !seen.contains(&(owner, m.name)) {
            charge(remaining, 128)?;
            seen.insert((owner, m.name));
        } else {
            continue;
        }
        let Some(formal) = tree
            .source_formal_variable_member(owner, m.name)
            .map_err(|e| Unsupported(e.into()))?
        else {
            continue;
        };
        let property = archive
            .checker_variable_properties(formal, profile)
            .map_err(Unsupported)?;
        if property.metadata.flags & CONST_FLAG != 0 {
            continue;
        }
        let declared = property.declared_hint().unwrap_or("");
        let owner = text(tree, owner)?;
        let name = text(tree, m.name)?;
        let origin = archive.member_policy_line(formal).map_err(Unsupported)?;
        let (rel, line) = point(inputs, root, &origin.path, origin.line)?;
        let dummy = Walker {
            tree,
            archive: Some(archive),
            resolver: tree,
            owner: property.owner,
            locals: HashMap::new(),
            exempt_types: &excluded,
            found: BTreeMap::new(),
            error: None,
        };
        if declared == "/list" {
            continue;
        }
        if let Some(element) = declared
            .strip_prefix("/list")
            .filter(|t| t.starts_with('/'))
        {
            if dummy.is_ref(element)? {
                strings_charge(&[owner, name, &rel], remaining)?;
                seeds.push((Place::Member(owner.into(), name.into()), rel, line));
            }
            continue;
        }
        if dummy.is_ref(declared)? {
            strings_charge(&[owner, name, declared, &rel], remaining)?;
            vars.push((
                owner.to_owned(),
                name.to_owned(),
                declared.to_owned(),
                rel,
                line,
            ));
        }
    }
    vars.sort_by(|a, b| (&a.3, a.4).cmp(&(&b.3, b.4)));
    let mut rows = Vec::new();
    for (owner, name, declared, rel, line) in vars {
        (checkpoint.borrow_mut())().map_err(Unsupported)?;
        if holder_exempt(tree, profile, p, &owner)? || related(tree, profile, p, &owner, &name)? {
            continue;
        }
        let mut init = false;
        for (t, v) in p.init_only {
            if v == &name && compatible(tree, profile, &owner, t)? {
                init = true;
                break;
            }
        }
        if init {
            continue;
        }
        strings_charge(&[&owner, &name, &declared, &rel], remaining)?;
        if rows.len() >= 10000 {
            return Err(Unsupported("stored finding limit exceeded".into()));
        }
        rows.push(StoredFinding {
            rule: "var",
            rel,
            line,
            message: format!(
                "{}/var/{} holds a {} outside a declared relation",
                if owner == "/" { "" } else { &owner },
                name,
                declared
            ),
            ident: format!("{owner}::{name}"),
        });
    }
    let mut found = BTreeMap::new();
    for (ordinal, occurrence) in crate::untyped_native::ordered_bodies(tree, archive.occurrences())?
    {
        (checkpoint.borrow_mut())().map_err(Unsupported)?;
        let rel = dm_preprocess::regions::relative_filesystem_path(&occurrence.source.path, root)
            .ok_or_else(|| Unsupported("stored procedure outside root".into()))?
            .to_string_lossy()
            .replace('\\', "/");
        if exempt(&rel) {
            continue;
        }
        let body = archive.parse(ordinal).map_err(|e| Unsupported(e.message))?;
        // Primary local scope allocations get conservative pre-admission, and
        // expire with this body; findings remain charged independently below.
        let transient = body
            .statement_body()
            .parsed()
            .statements
            .iter()
            .try_fold(4096usize, |n, s| {
                n.checked_add((s.span.end - s.span.start).checked_mul(32)?)
            })
            .ok_or_else(|| Unsupported("stored scope budget overflow".into()))?;
        let local_source = body.source_locals().map_err(Unsupported)?;
        let transient = transient.max(local_source.scope_admission().map_err(Unsupported)?);
        let signature = body.checker_parameters(profile).map_err(Unsupported)?;
        let transient = signature
            .entries()
            .map_err(|e| Unsupported(e.into()))?
            .iter()
            .try_fold(transient, |n, p| {
                let name = signature.name(p).ok()?;
                let ty = p
                    .type_components()
                    .iter()
                    .try_fold(0usize, |n, s| n.checked_add(s.end.checked_sub(s.start)?))?;
                n.checked_add(
                    name.len()
                        .checked_add(ty)?
                        .checked_add(8)?
                        .checked_mul(16)?
                        .checked_add(1024)?,
                )
            })
            .ok_or_else(|| {
                Unsupported("stored original parameter scope admission overflow".into())
            })?;
        charge(remaining, transient)?;
        let sc = archived_stored_scope(&body, &excluded, local_source)?;
        let observed_calls = std::cell::RefCell::new(HashSet::new());
        let error = std::cell::RefCell::new(None);
        let writes = std::cell::RefCell::new(Vec::new());
        let retain = std::cell::RefCell::new(|place: Place, at: Span| -> Result<(), Unsupported> {
            let (owner, name) = match &place {
                Place::Member(owner, name) => (owner.as_str(), name.as_str()),
                Place::Static(path, _) => (path.as_str(), ""),
            };
            strings_charge(&[&rel, owner, name], remaining)?;
            if writes.borrow().len() >= 10000 {
                return Err(Unsupported("stored write-coordinate limit exceeded".into()));
            }
            writes.borrow_mut().push((place, at));
            Ok(())
        });
        crate::untyped_order::stored_events(
            body.statement_body().view(),
            &mut |e, at| {
                if error.borrow().is_some() {
                    return;
                }
                if let Err(cancelled) = (checkpoint.borrow_mut())() {
                    *error.borrow_mut() = Some(Unsupported(cancelled));
                    return;
                }
                let r = (|| -> Result<(), Unsupported> {
                    let mut chain = Vec::new();
                    method_chain(e, &mut chain);
                    for (call, object, selector, args) in chain {
                        if !observed_calls
                            .borrow_mut()
                            .insert(call as *const Expr as usize)
                        {
                            continue;
                        }
                        let skip = match selector {
                            "Add" => 0,
                            "Insert" => 1,
                            _ => continue,
                        };
                        let mut stores = false;
                        for a in args.iter().skip(skip) {
                            if stored_ref(&sc.walker, a)? {
                                stores = true;
                                break;
                            }
                        }
                        if stores {
                            if let Some(place) = place_of(&sc, root, &rel, object, inputs)? {
                                if list_place(&sc.walker, &place)? {
                                    (retain.borrow_mut())(place, at)?
                                }
                            }
                        }
                    }
                    Ok(())
                })();
                if let Err(e) = r {
                    *error.borrow_mut() = Some(e)
                }
            },
            &mut |lhs, op, rhs, at| {
                if error.borrow().is_some() {
                    return;
                }
                if let Err(cancelled) = (checkpoint.borrow_mut())() {
                    *error.borrow_mut() = Some(Unsupported(cancelled));
                    return;
                }
                let r = (|| -> Result<(), Unsupported> {
                    if let ExprKind::Index { object, index, .. }
                    | ExprKind::SafeIndex { object, index, .. } = &node(lhs).kind
                    {
                        if op == "="
                            && (stored_ref(&sc.walker, index)? || stored_ref(&sc.walker, rhs)?)
                        {
                            if let Some(place) = place_of(&sc, root, &rel, object, inputs)? {
                                (retain.borrow_mut())(place, at)?
                            }
                        }
                        return Ok(());
                    }
                    if (matches!(op, "+=" | "|=" | "||=") || (op == "=" && literal(rhs).is_some()))
                        && stored_ref(&sc.walker, rhs)?
                    {
                        if let Some(place) = place_of(&sc, root, &rel, lhs, inputs)? {
                            if list_place(&sc.walker, &place)? {
                                (retain.borrow_mut())(place, at)?
                            }
                        }
                    }
                    Ok(())
                })();
                if let Err(e) = r {
                    *error.borrow_mut() = Some(e)
                }
            },
        )
        .map_err(|e| Unsupported(e.into()))?;
        drop(retain);
        if let Some(e) = error.into_inner() {
            return Err(e);
        }
        for (place, at) in writes.into_inner() {
            (checkpoint.borrow_mut())().map_err(Unsupported)?;
            if found.contains_key(&place) {
                continue;
            }
            let origin = archive
                .original_policy_line(at.start)
                .map_err(Unsupported)?;
            if origin.path != occurrence.source.path {
                return Err(Unsupported(
                    "stored cross-file statement policy projection unavailable".into(),
                ));
            }
            let (wrel, line) = point(inputs, root, &origin.path, origin.line)?;
            strings_charge(&[&wrel], remaining)?;
            if found.len() >= 10000 {
                return Err(Unsupported("stored list-place limit exceeded".into()));
            }
            found.insert(place, (wrel, line));
        }
        *remaining = remaining
            .checked_add(transient)
            .ok_or_else(|| Unsupported("stored scope refund overflow".into()))?;
    }
    for (place, rel, line) in seeds {
        (checkpoint.borrow_mut())().map_err(Unsupported)?;
        if !found.contains_key(&place) && found.len() >= 10000 {
            return Err(Unsupported("stored list-place limit exceeded".into()));
        }
        found.entry(place).or_insert((rel, line));
    }
    let mut lists = Vec::new();
    for (place, (wrel, wline)) in found {
        (checkpoint.borrow_mut())().map_err(Unsupported)?;
        match place {
            Place::Member(owner, name) => {
                let mut schema = false;
                for ancestor in ancestry(tree, profile, &owner)?.iter().copied().take(65) {
                    if (p.has_schema)(text(tree, ancestor)?, &name) {
                        schema = true;
                        break;
                    }
                }
                if schema
                    || holder_exempt(tree, profile, p, &owner)?
                    || related(tree, profile, p, &owner, &name)?
                    || p.work_queues
                        .iter()
                        .any(|q| q == &format!("{owner}::{name}"))
                {
                    continue;
                }
                let Some(fact) = crate::checker_variable_facts::variable(
                    tree,
                    tree,
                    profile,
                    SymbolId::of(&owner),
                    SymbolId::of(&name),
                )
                .map_err(Unsupported)?
                else {
                    continue;
                };
                let Some(formal) = fact.formal else { continue };
                let property = archive
                    .checker_variable_properties(formal, profile)
                    .map_err(Unsupported)?;
                if property.metadata.flags & CONST_FLAG != 0 {
                    continue;
                }
                let origin = archive.member_policy_line(formal).map_err(Unsupported)?;
                let (rel, line) = point(inputs, root, &origin.path, origin.line)?;
                strings_charge(&[&rel, &owner, &name, &wrel], remaining)?;
                lists.push((
                    rel,
                    line,
                    format!(
                        "{}/var/{} stores atoms/datums (e.g. {}:{})",
                        if owner == "/" { "" } else { &owner },
                        name,
                        wrel,
                        wline
                    ),
                    format!("{owner}::{name}"),
                ));
            }
            Place::Static(rel, line) => {
                strings_charge(&[&rel, &wrel], remaining)?;
                lists.push((
                    rel,
                    line,
                    format!("a proc's static list stores atoms/datums (e.g. {wrel}:{wline})"),
                    String::new(),
                ));
            }
        }
    }
    lists.sort();
    for (rel, line, message, ident) in lists {
        (checkpoint.borrow_mut())().map_err(Unsupported)?;
        if rows.len() >= 10000 {
            return Err(Unsupported("stored finding limit exceeded".into()));
        }
        rows.push(StoredFinding {
            rule: "list",
            rel,
            line,
            message,
            ident,
        });
    }
    (checkpoint.borrow_mut())().map_err(Unsupported)?;
    Ok(rows)
}

#[cfg(test)]
#[path = "untyped_stored_refs_tests.rs"]
mod tests;
