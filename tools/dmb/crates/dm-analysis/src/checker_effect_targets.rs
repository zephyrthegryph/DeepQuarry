//! Exact target identities for ONE source/builtin effect call plan.
use super::*;
use dm_tree::{checker_builtins::CheckerBuiltinProcedureIdentity, SemanticTree};
#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub(crate) enum EffectTarget {
    Source(ProcedureIdentity),
    Builtin(CheckerBuiltinProcedureIdentity),
}
pub(crate) fn callable_target(
    tree: &SemanticTree,
    profile: PackedU128,
    fact: &crate::checker_call_facts::CallableFact,
) -> Result<EffectTarget, String> {
    use crate::checker_call_facts::CallableFact;
    match fact {
        CallableFact::Source { identity, .. } => Ok(EffectTarget::Source(*identity)),
        CallableFact::CheckerBuiltin {
            declaring_owner,
            name,
            metadata,
        } => {
            for verb in [false, true] {
                if let Ok(id) = tree.checker_builtin_procedure_identity(
                    profile,
                    *declaring_owner,
                    *name,
                    verb,
                    metadata,
                ) {
                    return Ok(EffectTarget::Builtin(id));
                }
            }
            Err("effect builtin identity is not original selected native catalog metadata".into())
        }
        CallableFact::Missing => Err("missing callable cannot issue an effect target".into()),
    }
}
pub(crate) fn target_owner(input: &EffectInput, target: EffectTarget) -> Result<SymbolId, String> {
    match target {
        EffectTarget::Source(p) => Ok(p.owner),
        EffectTarget::Builtin(p) => input
            .archive
            .tree()
            .with_checker_builtin_procedure(p, |row| row.owner)
            .map_err(|e| format!("{e:?}")),
    }
}
pub(crate) fn display_target(
    input: &EffectInput,
    target: EffectTarget,
    budget: &ReportBudget,
) -> Result<String, String> {
    match target {
        EffectTarget::Source(p) => display(input, p, &budget),
        EffectTarget::Builtin(p) => input
            .archive
            .tree()
            .with_checker_builtin_procedure(p, |row| {
                let owner = input
                    .archive
                    .tree()
                    .checker_builtin_spelling(p.profile(), row.owner)
                    .ok_or("builtin owner spelling unavailable")?;
                let name = input
                    .archive
                    .tree()
                    .checker_builtin_spelling(p.profile(), row.name)
                    .ok_or("builtin name spelling unavailable")?;
                budget.format(format_args!(
                    "{}/proc/{name}",
                    if owner == "/" { "" } else { owner }
                ))
            })
            .map_err(|e| {
                budget
                    .format(format_args!("{e:?}"))
                    .unwrap_or_else(|budget_error| budget_error)
            })?,
    }
}
/// Called ONLY after the exact original source-parent projection has exhausted
/// source ancestors, including the old global fallback/unified namespace.
/// Raw native previous=None alone is NOT proof that no source parent exists.
pub(crate) fn builtin_parent_after_sources(
    archive: &BodyArchive,
    profile: PackedU128,
    resolver: &(impl Resolver + ?Sized),
    source: ProcedureIdentity,
) -> Result<Option<EffectTarget>, String> {
    let tree = archive.tree();
    if resolver.source_owner() != Resolver::source_owner(tree) {
        return Err("builtin parent resolver is foreign".into());
    }
    let q = Q::Ancestry(source.owner);
    let expected = Resolver::resolve(tree, q);
    if resolver.resolve(q) != expected {
        return Err("builtin parent ancestry differs from original".into());
    }
    let M::Symbols(ancestors) = expected else {
        return Err("builtin parent ancestry unissued".into());
    };
    let mut result: Option<(usize, CheckerBuiltinProcedureIdentity)> = None;
    for verb in [false, true] {
        let q = Q::CheckerBuiltinProc {
            profile,
            owner: source.owner,
            name: source.name,
            verb,
        };
        let expected = Resolver::resolve(tree, q);
        if resolver.resolve(q) != expected {
            return Err("builtin parent dependency differs from original".into());
        }
        match expected {
            M::Missing => (),
            M::Member {
                owner, name, data, ..
            } => {
                if owner == source.owner {
                    return Err("same-owner builtin/source implementation chronology needs native occurrence proof".into());
                }
                let depth = ancestors
                    .iter()
                    .position(|p| *p == owner)
                    .ok_or("builtin parent outside original ancestry")?;
                let id = tree
                    .checker_builtin_procedure_identity(profile, owner, name, verb, &data)
                    .map_err(|e| format!("{e:?}"))?;
                if let Some((old, _)) = result {
                    if old == depth {
                        return Err(
                            "builtin parent requires original same-owner proc/verb chronology"
                                .into(),
                        );
                    }
                    if old < depth {
                        continue;
                    }
                }
                result = Some((depth, id));
            }
            _ => return Err("builtin parent requires certified original profile metadata".into()),
        }
    }
    Ok(result.map(|(_, id)| EffectTarget::Builtin(id)))
}

pub(crate) fn original_target_parent(
    archive: &BodyArchive,
    profile: PackedU128,
    resolver: &(impl Resolver + ?Sized),
    target: EffectTarget,
) -> Result<Option<EffectTarget>, String> {
    match target {
        EffectTarget::Source(id) => {
            let mut member = None;
            for (ordinal, body) in archive.occurrences().iter().enumerate() {
                if identity(archive, ordinal)? == id {
                    if member.replace(body.member).is_some() {
                        return Err(
                            "source effect identity has multiple original body occurrences".into(),
                        );
                    }
                }
            }
            source_parent(
                archive,
                resolver,
                profile,
                member.ok_or("source parent has no original body occurrence")?,
                id,
            )
        }
        EffectTarget::Builtin(id) => {
            let tree = archive.tree();
            if resolver.source_owner() != Resolver::source_owner(tree) {
                return Err("builtin continuation resolver foreign".into());
            }
            let (owner, name) = tree
                .with_checker_builtin_procedure(id, |row| (row.owner, row.name))
                .map_err(|e| format!("{e:?}"))?;
            let q = Q::Ancestry(owner);
            let expected = Resolver::resolve(tree, q);
            if resolver.resolve(q) != expected {
                return Err("builtin continuation ancestry differs from original".into());
            }
            let M::Symbols(ancestors) = expected else {
                return Err("builtin continuation ancestry unissued".into());
            };
            if ancestors.first() != Some(&owner) {
                return Err("builtin continuation ancestry omits declaration owner".into());
            }
            let Some(parent) = ancestors.get(1) else {
                return Ok(None);
            };
            let fact =
                crate::checker_call_facts::callable_any(tree, resolver, profile, *parent, name)?;
            if matches!(fact, crate::checker_call_facts::CallableFact::Missing) {
                Ok(None)
            } else {
                callable_target(tree, profile, &fact).map(Some)
            }
        }
    }
}
pub(crate) fn target_parent_parts(
    input: &EffectInput,
    resolver: &(impl Resolver + ?Sized),
    target: EffectTarget,
    bodies: &[Arc<BodyEffects>],
    index: &BTreeMap<ProcedureIdentity, usize>,
) -> Result<Option<EffectTarget>, String> {
    match target {
        EffectTarget::Source(p) => Ok(bodies[*index
            .get(&p)
            .ok_or("effect source parent contribution absent")?]
        .parent),
        EffectTarget::Builtin(_) => {
            original_target_parent(&input.archive, input.profile, resolver, target)
        }
    }
}
pub(crate) fn source_child_overrides_target(
    plan: &EffectPlan,
    input: &EffectInput,
    resolver: &(impl Resolver + ?Sized),
    child: &BodyEffects,
    target: EffectTarget,
    budget: &ReportBudget,
) -> Result<bool, String> {
    let mut at = child.parent;
    let mut seen = BTreeSet::new();
    while let Some(parent) = at {
        if !budget.insert(&mut seen, parent)? {
            return Err("effect target predecessor cycle".into());
        }
        if parent == target {
            return Ok(true);
        }
        at = target_parent_parts(input, resolver, parent, &plan.bodies, &plan.index)?;
    }
    Ok(false)
}
