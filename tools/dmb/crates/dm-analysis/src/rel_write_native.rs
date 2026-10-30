//! Complete typed rel_write_undeclared observation over the original body graph.
use crate::{
    policy_inputs::{PolicyInputs, PolicyRole},
    untyped::{self, Unsupported},
};
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId};
use dm_syntax::{Expr, ExprKind, Span};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    path::Path,
};
#[derive(Debug, Eq, PartialEq)]
pub struct Finding {
    pub rel: String,
    pub line: usize,
    pub var: String,
    pub message: String,
}
fn under(tree: &dm_tree::SemanticTree, child: &str, parent: &str) -> Result<bool, Unsupported> {
    if child == parent {
        return Ok(true);
    }
    let profile = tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("relation ancestry needs checker profile".into()))?;
    if !tree
        .checker_source_type_presence(profile, child)
        .map_err(|e| Unsupported(format!("{e:?}")))?
        || !tree
            .checker_source_type_presence(profile, parent)
            .map_err(|e| Unsupported(format!("{e:?}")))?
    {
        return Ok(false);
    }
    match Resolver::resolve(tree, Q::Ancestry(SymbolId::of(child))) {
        M::Symbols(xs) => Ok(xs.contains(&SymbolId::of(parent))),
        other => Err(Unsupported(format!(
            "relation ancestry unavailable: {other:?}"
        ))),
    }
}
pub fn declared(
    tree: &dm_tree::SemanticTree,
    rels: &HashMap<String, Vec<String>>,
    ty: Option<&str>,
    var: &str,
) -> Result<bool, Unsupported> {
    let Some(types) = rels.get(var) else {
        return Ok(false);
    };
    let Some(ty) = ty else { return Ok(true) };
    for d in types {
        if d == ty || under(tree, ty, d)? || under(tree, d, ty)? {
            return Ok(true);
        }
    }
    Ok(false)
}
fn node(mut e: &Expr) -> &Expr {
    while let ExprKind::Group(inner) = &e.kind {
        e = inner
    }
    e
}
fn nameof(e: &Expr) -> Option<(Option<&Expr>, &str)> {
    let ExprKind::Call { callee, args } = &node(e).kind else {
        return None;
    };
    if !matches!(&callee.kind,ExprKind::Ident(n) if n=="nameof") || args.len() != 1 {
        return None;
    }
    match &node(&args[0]).kind {
        ExprKind::Ident(var) => Some((None, var)),
        ExprKind::Member {
            object, selector, ..
        }
        | ExprKind::SafeMember {
            object, selector, ..
        } => Some((Some(object), selector)),
        _ => None,
    }
}
fn pairs(name: &str) -> &'static [(usize, usize)] {
    match name {
        "rel_set" | "rel_add" | "rel_remove" | "rel_clear" | "rel_take" | "rel_take_all"
        | "rel_private" | "rel_is_private" => &[(0, 1)],
        "rel_move" => &[(0, 1), (2, 3)],
        _ => &[],
    }
}
/// Formal metadata comes from the original source/checker owner, not a copied
/// variable table or inferred values. Unknown authored types remain unknown.
pub fn detail(
    inputs: &PolicyInputs,
    root: &Path,
    holder: Option<&str>,
    var: &str,
    verb: &str,
    keyed: bool,
    remaining: &mut usize,
) -> Result<String, Unsupported> {
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("relation variable lookup needs checker profile".into()))?;
    let mut owner = String::new();
    let mut file = String::new();
    let mut list = false;
    if let Some(holder) = holder {
        if tree
            .checker_source_type_presence(profile, holder)
            .map_err(|e| Unsupported(format!("{e:?}")))?
        {
            if let Some(fact) = crate::checker_variable_facts::variable(
                tree,
                tree,
                profile,
                SymbolId::of(holder),
                SymbolId::of(var),
            )
            .map_err(Unsupported)?
            {
                owner = tree
                    .symbols()
                    .text(fact.owner)
                    .ok_or_else(|| {
                        Unsupported("relation declaration owner spelling unavailable".into())
                    })?
                    .to_owned();
                if let Some(formal) = fact.formal {
                    let property = archive
                        .checker_variable_properties(formal, profile)
                        .map_err(Unsupported)?;
                    list = property
                        .declared_hint()
                        .is_some_and(|p| p == "/list" || p.starts_with("/list/"));
                    let point = archive
                        .checker_variable_definition_point(formal, profile)
                        .map_err(Unsupported)?;
                    file = dm_preprocess::regions::relative_filesystem_path(&point.path, root)
                        .ok_or_else(|| {
                            Unsupported(
                                "relation formal declaration lies outside captured root".into(),
                            )
                        })?
                        .to_string_lossy()
                        .replace('\\', "/");
                } else {
                    list = fact.metadata.declared_type == Some(SymbolId::of("/list"));
                }
            }
        }
    }
    list |= matches!(verb, "rel_add" | "rel_remove" | "rel_take_all");
    let bound = verb
        .len()
        .checked_add(var.len().saturating_mul(2))
        .and_then(|n| n.checked_add(holder.unwrap_or("an untyped holder").len()))
        .and_then(|n| n.checked_add(owner.len()))
        .and_then(|n| n.checked_add(file.len()))
        .and_then(|n| n.checked_add(512))
        .and_then(|n| n.checked_mul(2))
        .ok_or_else(|| Unsupported("relation finding size overflow".into()))?;
    *remaining = remaining.checked_sub(bound).ok_or_else(|| {
        Unsupported("relation finding budget exceeded before message retention".into())
    })?;
    Ok(format!(
        "{} writes `{}` of {}, which no relation declares [decl {}::{} many={} keyed={} at={}]",
        verb,
        var,
        holder.unwrap_or("an untyped holder"),
        owner,
        var,
        list as u8,
        keyed as u8,
        file
    ))
}
pub fn findings(
    inputs: &PolicyInputs,
    root: &Path,
    rels: &HashMap<String, Vec<String>>,
    exempt: impl Fn(&str) -> bool,
    remaining: &mut usize,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, Unsupported> {
    checkpoint().map_err(Unsupported)?;
    let archive = inputs.archive();
    let tree = archive.tree();
    tree.checker_builtin_profile()
        .ok_or_else(|| Unsupported("relation typing needs certified native hierarchy".into()))?;
    let mut found = BTreeMap::new();
    for (ordinal, occurrence) in crate::untyped_native::ordered_bodies(tree, archive.occurrences())?
    {
        checkpoint().map_err(Unsupported)?;
        let rel = dm_preprocess::regions::relative_filesystem_path(&occurrence.source.path, root)
            .ok_or_else(|| Unsupported("relation procedure outside root".into()))?
            .to_string_lossy()
            .replace('\\', "/");
        if exempt(&rel) {
            continue;
        }
        let body = archive.parse(ordinal).map_err(|e| Unsupported(e.message))?;
        let scope = untyped::archived_scope(&body, tree, &[])?.with_archive(archive)?;
        let mut prefixes = HashSet::new();
        let mut error = None;
        crate::untyped_order::expressions(body.statement_body().view(), &mut |e, at: Span| {
            if error.is_some() {
                return;
            }
            if let ExprKind::Literal(text) = &e.kind {
                let valid = (|| -> Result<(), Unsupported> {
                    if let Some(parts) = text.parts().map_err(|e| Unsupported(e.into()))? {
                        parts.lexical.map_err(|e| Unsupported(format!("{e:?}")))?;
                    }
                    Ok(())
                })();
                if let Err(e) = valid {
                    error = Some(e);
                    return;
                }
            }
            // A native child prefix is an original Base's Follow chain, not another
            // bare Term::Call. Its argument subexpressions still get visited normally.
            let prefix = match &e.kind {
                ExprKind::Member { object, .. }
                | ExprKind::StaticMember { object, .. }
                | ExprKind::SafeMember { object, .. }
                | ExprKind::Index { object, .. }
                | ExprKind::SafeIndex { object, .. } => {
                    Some(object.as_ref() as *const Expr as usize)
                }
                ExprKind::Call { callee, .. } => Some(callee.as_ref() as *const Expr as usize),
                _ => None,
            };
            if let Some(pointer) = prefix {
                if !prefixes.contains(&pointer) {
                    let Some(next) = remaining.checked_sub(64) else {
                        error = Some(Unsupported(
                            "relation prefix-coordinate budget exceeded".into(),
                        ));
                        return;
                    };
                    *remaining = next;
                    prefixes.insert(pointer);
                }
            }
            if prefixes.contains(&(e as *const Expr as usize)) {
                return;
            }
            let ExprKind::Call { callee, args } = &e.kind else {
                return;
            };
            let ExprKind::Ident(verb) = &callee.kind else {
                return;
            };
            let attempt = (|| -> Result<(), Unsupported> {
                for &(hi, vi) in pairs(verb) {
                    let (Some(holder), Some(var)) = (args.get(hi), args.get(vi)) else {
                        continue;
                    };
                    let Some((receiver, var)) = nameof(var) else {
                        continue;
                    };
                    let receiver_ty = match receiver {
                        Some(r) => scope.player_link_receiver_type(r)?,
                        None => None,
                    };
                    let ty = match receiver_ty {
                        some @ Some(_) => some,
                        None => scope.player_link_receiver_type(holder)?,
                    }
                    .filter(|t| !t.is_empty() && t != "/");
                    if declared(tree, rels, ty.as_deref(), var)? {
                        continue;
                    }
                    let origin = archive
                        .original_policy_line(at.start)
                        .map_err(Unsupported)?;
                    if origin.path != occurrence.source.path {
                        return Err(Unsupported(
                            "relation cross-file statement requires original old-policy projection"
                                .into(),
                        ));
                    }
                    let source = inputs.file(&origin.path).ok_or_else(|| {
                        Unsupported("relation statement source not captured".into())
                    })?;
                    if !source.is_compiled() || source.role() != PolicyRole::DmSource {
                        return Err(Unsupported("relation statement not compiled DM".into()));
                    }
                    let line = source
                        .analyze_display_line(origin.line)
                        .map_err(|e| Unsupported(e.to_string()))?;
                    let coordinate = rel
                        .len()
                        .checked_add(var.len())
                        .and_then(|n| n.checked_mul(4))
                        .and_then(|n| n.checked_add(256))
                        .ok_or_else(|| {
                            Unsupported("relation finding coordinate overflow".into())
                        })?;
                    *remaining = remaining.checked_sub(coordinate).ok_or_else(|| {
                        Unsupported(
                            "relation finding coordinate budget exceeded before retention".into(),
                        )
                    })?;
                    let key = (rel.clone(), line, var.to_owned());
                    if !found.contains_key(&key) {
                        if found.len() >= 10000 {
                            return Err(Unsupported("relation finding admission exceeded".into()));
                        }
                        let message = detail(
                            inputs,
                            root,
                            ty.as_deref(),
                            var,
                            verb,
                            verb == "rel_add" && args.len() > 3,
                            remaining,
                        )?;
                        found.insert(key, message);
                    }
                }
                Ok(())
            })();
            if let Err(e) = attempt {
                error = Some(e)
            }
        })
        .map_err(|e| Unsupported(e.into()))?;
        if let Some(e) = error {
            return Err(e);
        }
    }
    checkpoint().map_err(Unsupported)?;
    let mut rows = found
        .into_iter()
        .map(|((rel, line, var), message)| Finding {
            rel,
            line,
            var,
            message,
        })
        .collect::<Vec<_>>();
    rows.sort_by(|a, b| (&a.rel, a.line, &a.message).cmp(&(&b.rel, b.line, &b.message)));
    Ok(rows)
}
#[cfg(test)]
#[path = "rel_write_native_tests.rs"]
mod tests;
