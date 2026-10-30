//! Full static-member receiver policy, borrowing original native declarations
//! and primary AST. Return-type/value inference intentionally never participates.
use crate::{
    checker_variable_facts,
    policy_inputs::PolicyInputs,
    untyped::{self, Unsupported},
};
use dm_ir::{PackedU128, SymbolId};
use dm_syntax::{Expr, ExprKind};
use dm_tree::{DefinitionMode, MemberKind, SemanticTree};
use std::collections::{BTreeMap, BTreeSet};
#[derive(Debug, Eq, PartialEq)]
pub struct Finding {
    pub rel: String,
    pub line: u32,
    pub name: String,
}
fn spelling<'a>(
    tree: &'a SemanticTree,
    profile: PackedU128,
    symbol: SymbolId,
) -> Result<&'a str, Unsupported> {
    tree.symbols()
        .text(symbol)
        .or_else(|| tree.checker_builtin_spelling(profile, symbol))
        .ok_or_else(|| Unsupported("static-member declaration spelling unavailable".into()))
}
fn static_names(tree: &SemanticTree, profile: PackedU128) -> Result<BTreeSet<String>, Unsupported> {
    let catalog =
        dm_tree::checker_builtins::pinned_catalog().map_err(|e| Unsupported(format!("{e:?}")))?;
    tree.validate_checker_builtin_profile(profile)
        .map_err(|e| Unsupported(format!("{e:?}")))?;
    let mut declared = BTreeMap::new();
    for row in catalog
        .declarations
        .iter()
        .filter(|r| r.kind == MemberKind::Var && r.definition == DefinitionMode::Declare)
    {
        declared.insert((row.owner, row.name), row.metadata.flags & (1 | 8) != 0);
    }
    for member in tree
        .members()
        .iter()
        .filter(|m| m.kind == MemberKind::Var && m.definition == DefinitionMode::Declare)
    {
        if member.metadata.inherited_opaque.is_some() {
            return Err(Unsupported("static-name flags are incomplete".into()));
        }
        let owner = tree
            .type_node(member.owner)
            .ok_or_else(|| Unsupported("static-name owner missing".into()))?
            .path;
        // Same-owner authored declaration replaces its builtin declaration;
        // subtype overrides do not manufacture declarations or erase a base.
        declared.insert((owner, member.name), member.metadata.flags & (1 | 8) != 0);
    }
    declared
        .into_iter()
        .filter(|(_, yes)| *yes)
        .map(|((_, name), _)| spelling(tree, profile, name).map(str::to_owned))
        .collect()
}
struct Receiver<'a> {
    archive: &'a dm_tree::frontend::BodyArchive,
    tree: &'a SemanticTree,
    profile: PackedU128,
    owner: SymbolId,
    locals: &'a std::collections::HashMap<String, String>,
}
impl Receiver<'_> {
    fn declared(&self, owner: SymbolId, name: &str) -> Result<Option<Option<String>>, Unsupported> {
        let fact = checker_variable_facts::variable(
            self.tree,
            self.tree,
            self.profile,
            owner,
            SymbolId::of(name),
        )
        .map_err(Unsupported)?;
        let Some(fact) = fact else { return Ok(None) };
        if let Some(formal) = fact.formal {
            let qualified = fact
                .metadata
                .declared_type
                .into_iter()
                .chain(fact.metadata.list_element_type)
                .any(|symbol| {
                    spelling(self.tree, self.profile, symbol)
                        .is_ok_and(dm_syntax::has_checker_qualifiers)
                });
            if qualified {
                let properties = self
                    .archive
                    .checker_variable_properties(formal, self.profile)
                    .map_err(Unsupported)?;
                return Ok(Some(properties.declared_hint().map(str::to_owned)));
            }
        }
        let Some(ty) = fact.metadata.declared_type else {
            return Ok(Some(None));
        };
        let mut ty = spelling(self.tree, self.profile, ty)?.to_owned();
        if ty == "/list" {
            if let Some(element) = fact.metadata.list_element_type {
                ty.push_str(spelling(self.tree, self.profile, element)?);
            }
        }
        if dm_syntax::has_checker_qualifiers(&ty) {
            return Err(Unsupported(
                "receiver declaration needs native checker qualifier facts".into(),
            ));
        }
        Ok(Some(Some(ty)))
    }
    fn of(&self, node: &Expr) -> Result<Option<String>, Unsupported> {
        Ok(match &node.kind {
            ExprKind::Ident(name) => match name.as_str() {
                "src" => (self.owner != SymbolId::of("/"))
                    .then(|| spelling(self.tree, self.profile, self.owner).map(str::to_owned))
                    .transpose()?,
                "usr" => Some("/mob".into()),
                "world" => Some("/world".into()),
                "global" => Some("/".into()),
                _ => {
                    if let Some(local) = self.locals.get(name) {
                        if dm_syntax::has_checker_qualifiers(local) {
                            return Err(Unsupported(
                                "local receiver needs native checker qualifier facts".into(),
                            ));
                        }
                        (!local.is_empty()).then(|| local.clone())
                    } else if self.owner != SymbolId::of("/") {
                        match self.declared(self.owner, name)? {
                            Some(found) => found,
                            None => self.declared(SymbolId::of("/"), name)?.flatten(),
                        }
                    } else {
                        self.declared(SymbolId::of("/"), name)?.flatten()
                    }
                }
            },
            ExprKind::Group(inner) => self.of(inner)?,
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => match self.of(object)? {
                Some(owner) => self.declared(SymbolId::of(&owner), selector)?.flatten(),
                None => None,
            },
            ExprKind::Unary { op, .. } if op == "new" => {
                match dm_syntax::native_special_forms::constructor(node)
                    .map_err(|e| Unsupported(e.into()))?
                {
                    Some(dm_syntax::native_special_forms::Constructor::Static { path, .. }) => {
                        Some(path.into())
                    }
                    _ => None,
                }
            }
            // Pinned Follow::StaticField/ProcReference erase the receiver
            // declaration type; the value is not typed from its target.
            ExprKind::StaticMember { .. } => None,
            // A call result, index or value expression is NEVER typed from
            // RETURN_TYPE, an assignment, a constant, or a value proof here.
            _ => None,
        })
    }
}
pub fn findings(
    inputs: &PolicyInputs,
    root: &std::path::Path,
    exempt: impl Fn(&str) -> bool,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, Unsupported> {
    findings_with::<crate::policy_body_demand::Compatibility>(inputs, root, exempt, checkpoint)
}
pub fn findings_checked(
    inputs: &PolicyInputs,
    root: &std::path::Path,
    exempt: impl Fn(&str) -> bool,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, crate::policy_body_demand::PolicyFailure> {
    findings_with::<crate::policy_body_demand::Checked>(inputs, root, exempt, checkpoint)
}
pub fn findings_with<D: crate::policy_body_demand::Demand>(
    inputs: &PolicyInputs,
    root: &std::path::Path,
    exempt: impl Fn(&str) -> bool,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Finding>, D::Error> {
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree.checker_builtin_profile().ok_or_else(|| {
        Unsupported("static-member name universe needs fixed builtin hierarchy/profile".into())
    })?;
    let statics = static_names(tree, profile)?;
    let mut rows = BTreeSet::new();
    for ordinal in 0..archive.len() {
        checkpoint().map_err(Unsupported)?;
        let occurrence = &archive.occurrences()[ordinal];
        let rel = dm_preprocess::regions::relative_filesystem_path(&occurrence.source.path, root)
            .as_deref()
            .unwrap_or(occurrence.source.path.as_path())
            .to_string_lossy()
            .replace('\\', "/");
        if !rel.starts_with("code/") || exempt(&rel) {
            continue;
        }
        let body = D::parse(archive, ordinal)?;
        let scope = untyped::archived_scope(&body, tree, &[])?;
        let receiver = Receiver {
            archive,
            tree,
            profile,
            owner: scope.owner,
            locals: &scope.locals,
        };
        let mut error = None;
        crate::untyped_order::expressions_current(body.statement_body().view(), &mut |observed, at| {
                let expr = observed.original();
            if error.is_some() {
                return;
            }
            let result = (|| -> Result<(), Unsupported> {
                if let ExprKind::Literal(text) = &expr.kind {
                    if let Some(parts) = text.parts().map_err(|e| Unsupported(e.into()))? {
                        parts.lexical.map_err(|e| Unsupported(format!("{e:?}")))?;
                    }
                }
                let (ExprKind::Member {
                    object, selector, ..
                }
                | ExprKind::SafeMember {
                    object, selector, ..
                }) = &expr.kind
                else {
                    return Ok(());
                };
                if statics.contains(selector) && receiver.of(object)?.is_none() {
                    let source = archive
                        .original_policy_line(at.start)
                        .map_err(Unsupported)?;
                    let captured = inputs
                        .file(&source.path)
                        .ok_or_else(|| Unsupported("member origin is not captured".into()))?;
                    if !captured.is_compiled()
                        || captured.role() != crate::policy_inputs::PolicyRole::DmSource
                    {
                        return Err(
                            Unsupported("member origin is not compiled DM source".into()).into(),
                        );
                    }
                    let line = captured
                        .analyze_display_line(source.line)
                        .map_err(|e| Unsupported(e.to_string()))?;
                    let rel = dm_preprocess::regions::relative_filesystem_path(&source.path, root)
                        .as_deref()
                        .unwrap_or(source.path.as_path())
                        .to_string_lossy()
                        .replace('\\', "/");
                    rows.insert((
                        rel,
                        u32::try_from(line)
                            .map_err(|_| Unsupported("member line overflow".into()))?,
                        selector.clone(),
                    ));
                }
                Ok(())
            })();
            if let Err(e) = result {
                error = Some(e);
            }
        })
        .map_err(|e| Unsupported(e.into()))?;
        if let Some(error) = error {
            return Err(error.into());
        }
    }
    Ok(rows
        .into_iter()
        .map(|(rel, line, name)| Finding { rel, line, name })
        .collect())
}

#[cfg(test)]
#[path = "untyped_member_native_tests.rs"]
mod tests;
