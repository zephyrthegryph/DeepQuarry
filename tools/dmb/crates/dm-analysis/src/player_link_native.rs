//! Complete player_link match policy over the ORIGINAL issued native body graph.
//! It observes statement-root simple assignments, not nested named arguments;
//! declared type hints, never inferred values, decide whether a receiver is mob.
use crate::{
    policy_inputs::{PolicyInputs, PolicyRole},
    untyped::{self, Unsupported},
};
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId};
use dm_syntax::{ExprKind, Span};
use std::{collections::BTreeSet, path::Path};
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Finding {
    pub rel: String,
    pub line: usize,
}
fn is_mob(tree: &dm_tree::SemanticTree, ty: &str) -> Result<bool, Unsupported> {
    if ty == "/mob" {
        return Ok(true);
    }
    if ty.is_empty() {
        return Ok(false);
    }
    match Resolver::resolve(tree, Q::Ancestry(SymbolId::of(ty))) {
        M::Symbols(rows) => Ok(rows.contains(&SymbolId::of("/mob"))),
        M::Missing => Ok(false),
        _ => Err(Unsupported(
            "player-link receiver ancestry is unavailable".into(),
        )),
    }
}
pub fn findings(
    inputs: &PolicyInputs,
    root: &Path,
    exempt: impl Fn(&str) -> bool,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, Unsupported> {
    let archive = inputs.archive();
    let tree = archive.tree();
    tree.checker_builtin_profile()
        .ok_or_else(|| Unsupported("player-link needs certified native builtin ancestry".into()))?;
    let mut found = BTreeSet::new();
    for ordinal in 0..archive.len() {
        checkpoint().map_err(Unsupported)?;
        let occurrence = &archive.occurrences()[ordinal];
        let rel = dm_preprocess::regions::relative_filesystem_path(&occurrence.source.path, root)
            .ok_or_else(|| Unsupported("player-link procedure lies outside root".into()))?
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
            .ok_or_else(|| Unsupported("player-link owner spelling unavailable".into()))?;
        let owner_is_mob = is_mob(tree, owner)?;
        let mut error = None;
        crate::untyped_order::statement_assignments(
            &body.statement_body().parsed().statements,
            &mut |target, _, at: Span| {
                if error.is_some() {
                    return;
                }
                let hit = (|| -> Result<bool, Unsupported> {
                    match &target.kind {
                        ExprKind::Ident(name) => Ok(owner_is_mob
                            && matches!(name.as_str(), "key" | "ckey")
                            && !scope.locals.contains_key(name)),
                        ExprKind::Member {
                            object, selector, ..
                        }
                        | ExprKind::SafeMember {
                            object, selector, ..
                        } if matches!(selector.as_str(), "key" | "ckey") => {
                            match scope.player_link_receiver_type(object)? {
                                Some(ty) => is_mob(tree, &ty),
                                None => Ok(false),
                            }
                        }
                        _ => Ok(false),
                    }
                })();
                match hit {
                    Err(e) => error = Some(e),
                    Ok(false) => (),
                    Ok(true) => {
                        let result = (|| -> Result<usize, Unsupported> {
                            let point = archive
                                .original_policy_line(at.start)
                                .map_err(Unsupported)?;
                            if point.path != occurrence.source.path {
                                return Err(Unsupported("player-link cross-file statement location needs an issued old-policy projection".into()));
                            }
                            let source = inputs.file(&point.path).ok_or_else(|| {
                                Unsupported("player-link statement source not captured".into())
                            })?;
                            if !source.is_compiled() || source.role() != PolicyRole::DmSource {
                                return Err(Unsupported(
                                    "player-link statement not compiled DM".into(),
                                ));
                            }
                            source
                                .analyze_display_line(point.line)
                                .map_err(|e| Unsupported(e.to_string()))
                        })();
                        match result {
                            Ok(line) => {
                                found.insert((rel.clone(), line));
                            }
                            Err(e) => error = Some(e),
                        }
                    }
                }
            },
        );
        if let Some(error) = error {
            return Err(error);
        }
    }
    Ok(found
        .into_iter()
        .map(|(rel, line)| Finding { rel, line })
        .collect())
}
#[cfg(test)]
#[path = "player_link_native_tests.rs"]
mod tests;
