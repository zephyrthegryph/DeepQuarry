//! Complete weak_raw_read typed rule over the compiler's ORIGINAL BodyArchive.
//! Raw declaration matching stays with Analyze. Receiver classification reuses
//! the existing stored-reference Walker receiver policy and SAME resolver; no copied model or parser.
use crate::{
    policy_inputs::{PolicyInputs, PolicyRole},
    untyped::{self, Unsupported},
};
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId};
use dm_syntax::{Expr, ExprKind, NodeStep, Span, TypedVisitor, VisitDecision};
use std::{
    collections::{BTreeMap, HashMap, HashSet},
    path::Path,
};
#[derive(Debug, Eq, PartialEq)]
pub struct Finding {
    pub rel: String,
    pub line: usize,
    pub var: String,
    pub holder: String,
}

fn subtype(tree: &dm_tree::SemanticTree, child: &str, parent: &str) -> Result<bool, Unsupported> {
    if child == parent {
        return Ok(true);
    }
    match Resolver::resolve(tree, Q::Ancestry(SymbolId::of(child))) {
        M::Symbols(ancestors) => Ok(ancestors.contains(&SymbolId::of(parent))),
        M::Missing => Ok(false),
        other => Err(Unsupported(format!(
            "weak-relation ancestry is incomplete: {other:?}"
        ))),
    }
}
fn compatible(
    tree: &dm_tree::SemanticTree,
    declarers: &[String],
    holder: &str,
) -> Result<bool, Unsupported> {
    for declaration in declarers {
        if subtype(tree, holder, declaration)? || subtype(tree, declaration, holder)? {
            return Ok(true);
        }
    }
    Ok(false)
}
struct Mark<'a>(&'a mut HashSet<usize>);
impl TypedVisitor for Mark<'_> {
    fn expression(&mut self, e: &Expr, _: &[NodeStep]) -> VisitDecision {
        self.0.insert(e as *const Expr as usize);
        VisitDecision::Descend
    }
}
/// Exclude the exact AST callee head, not its receiver: H.target() is an
/// accessor, but a weak raw receiver in target.child() is still a raw read.
fn mark_callee(e: &Expr, out: &mut HashSet<usize>) {
    // Only an ordinary call's own callee node is an accessor token. A grouped
    // expression used as a dynamic callee still evaluates/reads its contents.
    out.insert(e as *const Expr as usize);
}

pub fn findings(
    inputs: &PolicyInputs,
    root: &Path,
    weak: &HashMap<String, Vec<String>>,
    exempt: impl Fn(&str) -> bool,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, Unsupported> {
    checkpoint().map_err(Unsupported)?;
    if weak.is_empty() {
        return Ok(Vec::new());
    }
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree.checker_builtin_profile().ok_or_else(|| {
        Unsupported("weak-relation typing needs certified native hierarchy".into())
    })?;
    tree.validate_checker_builtin_profile(profile)
        .map_err(|e| Unsupported(format!("{e:?}")))?;
    let mut rows = BTreeMap::new();
    for (ordinal, occurrence) in crate::untyped_native::ordered_bodies(tree, archive.occurrences())?
    {
        checkpoint().map_err(Unsupported)?;
        let rel = dm_preprocess::regions::relative_filesystem_path(&occurrence.source.path, root)
            .ok_or_else(|| Unsupported("weak-relation procedure is outside captured root".into()))?
            .to_string_lossy()
            .replace('\\', "/");
        if exempt(&rel) {
            continue;
        }
        let body = archive.parse(ordinal).map_err(|e| Unsupported(e.message))?;
        let scope = untyped::archived_scope(&body, tree, &[])?.with_archive(archive)?;
        let owner = tree
            .symbols()
            .text(scope.owner)
            .ok_or_else(|| Unsupported("weak-relation owner spelling unavailable".into()))?;
        let mut named = HashSet::new();
        let mut callees = HashSet::new();
        let mut error = None;
        crate::untyped_order::expressions(
            &body.statement_body().parsed().statements,
            &mut |e, at: Span| {
                if error.is_some() {
                    return;
                }
                let result = (|| -> Result<(), Unsupported> {
                    if let ExprKind::Literal(text) = &e.kind {
                        if let Some(parts) = text.parts().map_err(|e| Unsupported(e.into()))? {
                            parts.lexical.map_err(|e| Unsupported(format!("{e:?}")))?;
                        }
                    }
                    // The shared report walker visits an original node before its
                    // children. Mark nameof's ACTUAL argument nodes before they
                    // are observed; strings/comments/spelling cannot mint a skip.
                    if let ExprKind::Call { callee, args } = &e.kind {
                        mark_callee(callee, &mut callees);
                        if matches!(&callee.kind,ExprKind::Ident(n) if n=="nameof") {
                            for argument in args {
                                dm_syntax::visit_expression(argument, &mut Mark(&mut named));
                            }
                        }
                    }
                    let address = e as *const Expr as usize;
                    if named.contains(&address) || callees.contains(&address) {
                        return Ok(());
                    }
                    let hit = match &e.kind {
                        ExprKind::Ident(name)
                            if weak.contains_key(name) && !scope.locals.contains_key(name) =>
                        {
                            Some((name.as_str(), Some(owner.to_owned())))
                        }
                        ExprKind::Member {
                            object, selector, ..
                        }
                        | ExprKind::SafeMember {
                            object, selector, ..
                        } if weak.contains_key(selector) => {
                            Some((selector.as_str(), scope.player_link_receiver_type(object)?))
                        }
                        _ => None,
                    };
                    let Some((var, Some(holder))) = hit else {
                        return Ok(());
                    };
                    if holder.is_empty() || holder == "/" || !compatible(tree, &weak[var], &holder)?
                    {
                        return Ok(());
                    }
                    let origin = archive
                        .original_policy_line(at.start)
                        .map_err(Unsupported)?;
                    if origin.path != occurrence.source.path {
                        return Err(Unsupported("weak-relation cross-file statement requires issued old-policy origin projection".into()));
                    }
                    let source = inputs.file(&origin.path).ok_or_else(|| {
                        Unsupported("weak-relation statement source missing".into())
                    })?;
                    if !source.is_compiled() || source.role() != PolicyRole::DmSource {
                        return Err(Unsupported(
                            "weak-relation statement is not compiled original DM".into(),
                        ));
                    }
                    let line = source
                        .analyze_display_line(origin.line)
                        .map_err(|e| Unsupported(e.to_string()))?;
                    rows.entry((rel.clone(), line, var.to_owned()))
                        .or_insert_with(|| Finding {
                            rel: rel.clone(),
                            line,
                            var: var.to_owned(),
                            holder,
                        });
                    Ok(())
                })();
                if let Err(e) = result {
                    error = Some(e);
                }
            },
        );
        if let Some(error) = error {
            return Err(error);
        }
    }
    checkpoint().map_err(Unsupported)?;
    Ok(rows.into_values().collect())
}
#[cfg(test)]
#[path = "weak_raw_read_native_tests.rs"]
mod tests;
