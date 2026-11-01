//! Pinned `proc_has_no_parent` semantic prerequisite and a bounded exact cohort.
//!
//! Policy adapted from SpacemanDMM dreamchecker 0290db5c752fa292f9824521515b603a2afd11dc
//! lib.rs visit_term(ParentCall), GPL-3.0. No second parser or copied object tree.
//! This is NOT full-family coverage: control-bearing bodies and calls whose
//! argument visitation depends on unresolved call/type analysis fail explicitly.
//! A future shared pinned visited-expression contract must extend the cohort.
use crate::checks::{BodyView, Diagnostic, Severity};
use dm_ir::{PackedU128, ProcedureIdentity, ResolveQuery as Q, ResolvedMeaning as M, Resolver};
use dm_syntax::{Expr, ExprKind, StatementKind};
use dm_tree::{
    frontend::{ColdFrontend, ParsedBody},
    MemberId, MemberKind, SemanticTree,
};
use std::sync::Arc;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ParentFact {
    pub identity: ProcedureIdentity,
    pub has_parent: bool,
    /// Exact pinned refusal ProcRef display when `has_parent` is false.
    /// Engine-positive cases need no diagnostic and do not claim engine-list indices.
    pub display: String,
}

/// Ask the native immutable resolver for the exact source predecessor, then
/// engine callable provenance if no source predecessor exists. A partial engine
/// inventory cannot certify a missing parent. Source overrides never mask an
/// intrinsic inherited implementation. Positive source facts need no complete
/// engine inventory. The resolver is the caller's compiler/query host.
pub fn parent_fact(
    tree: &SemanticTree,
    member_id: MemberId,
    resolver: &(impl Resolver + ?Sized),
) -> Result<ParentFact, String> {
    parent_fact_in_profile(tree, member_id, resolver, None)
}
/// An explicit checker profile uses the same native resolver's fixed-DSL
/// builtin namespace. It never interprets runtime inventory as checker parity.
fn parent_fact_in_profile_native(
    tree: &SemanticTree,
    member_id: MemberId,
    resolver: &(impl Resolver + ?Sized),
    profile: Option<PackedU128>,
) -> Result<ParentFact, String> {
    let member = tree
        .member(member_id)
        .ok_or("parent fact lacks current member")?;
    if !matches!(member.kind, MemberKind::Proc | MemberKind::Verb) {
        return Err("parent fact requires callable member".into());
    }
    let owner = tree
        .type_node(member.owner)
        .ok_or("parent fact lacks current owner")?
        .path;
    let identity = ProcedureIdentity {
        owner,
        name: member.name,
        verb: member.kind == MemberKind::Verb,
        occurrence: tree
            .member_occurrence(member_id)
            .ok_or("parent fact lacks current occurrence")?,
    };
    let query = Q::SourceDeclarationChain {
        owner,
        name: member.name,
        verb: identity.verb,
    };
    let resolved = resolver.resolve(query);
    // The host may add a checker profile, not substitute a different source
    // chain or receiver ancestry behind this issued body. Compare meanings,
    // never forge source authority by resetting a decorated tree's identity.
    if resolved != Resolver::resolve(tree, query) {
        return Err("parent query host differs from issued source declaration chain".into());
    }
    let ancestry = Q::Ancestry(owner);
    if resolver.resolve(ancestry) != Resolver::resolve(tree, ancestry) {
        return Err("parent query host differs from issued receiver ancestry".into());
    }
    let M::Members(rows) = resolved else {
        return Err("parent fact needs exact source declaration chain".into());
    };
    let mut selected = None;
    let mut same_owner_count = 0;
    for row in rows.iter() {
        let M::Declaration {
            identity: current,
            previous,
            ..
        } = row
        else {
            return Err("malformed source declaration chain".into());
        };
        if current.owner == owner {
            same_owner_count += 1;
        }
        if current == &identity {
            if selected.replace(previous.is_some()).is_some() {
                return Err("duplicate current declaration identity".into());
            }
        }
    }
    let mut source_parent = selected.ok_or("source chain omits current declaration")?;
    if profile.is_some() {
        // The pinned checker has one proc/verb name map. Native runtime keeps
        // them distinct. An opposite-kind inherited source callable is still
        // a parent; mixed same-owner occurrences require additional ordering
        // facts and must not be silently reinterpreted.
        let other = Q::SourceDeclarationChain {
            owner,
            name: member.name,
            verb: !identity.verb,
        };
        let answer = resolver.resolve(other);
        if answer != Resolver::resolve(tree, other) {
            return Err("parent query host differs from issued opposite-kind source chain".into());
        }
        match answer {
            M::Members(rows) => {
                let Some(M::Declaration {
                    identity: other, ..
                }) = rows.first()
                else {
                    return Err("checker parent opposite-kind chain malformed".into());
                };
                if other.owner == owner {
                    return Err(
                        "checker parent needs unified same-owner proc/verb occurrence ordering"
                            .into(),
                    );
                }
                source_parent = true;
            }
            M::Missing => (),
            _ => {
                return Err("checker parent needs exact opposite-kind source callable facts".into())
            }
        }
    }
    if !source_parent && profile.is_some() && owner != dm_ir::SymbolId::of("/") {
        // Pinned ProcRef::parent_proc continues through root/global source
        // procs. Native runtime source lookup intentionally does not, so this
        // is an explicit additional query in the checker-qualified context.
        let root = Q::SourceDeclarationChain {
            owner: dm_ir::SymbolId::of("/"),
            name: member.name,
            verb: identity.verb,
        };
        let answer = resolver.resolve(root);
        if answer != Resolver::resolve(tree, root) {
            return Err("parent query host differs from issued global source chain".into());
        }
        source_parent = match answer {
            M::Members(rows) if !rows.is_empty() => true,
            M::Missing => false,
            _ => return Err("checker parent needs exact global source callable facts".into()),
        };
        if !source_parent {
            let other = Q::SourceDeclarationChain {
                owner: dm_ir::SymbolId::of("/"),
                name: member.name,
                verb: !identity.verb,
            };
            let answer = resolver.resolve(other);
            if answer != Resolver::resolve(tree, other) {
                return Err(
                    "parent query host differs from issued opposite-kind global source chain"
                        .into(),
                );
            }
            source_parent = match answer {
                M::Members(rows) if !rows.is_empty() => true,
                M::Missing => false,
                _ => {
                    return Err(
                        "checker parent global opposite-kind source facts unsupported".into(),
                    )
                }
            };
        }
    }
    let has_parent = if source_parent {
        true
    } else {
        let query = match profile {
            Some(profile) => Q::CheckerIntrinsicCallable {
                profile,
                owner,
                name: member.name,
                verb: identity.verb,
            },
            None => Q::IntrinsicCallable {
                owner,
                name: member.name,
                verb: identity.verb,
            },
        };
        match resolver.resolve(query) {
            M::Presence(false) if profile.is_some() => {
                match resolver.resolve(Q::CheckerIntrinsicCallable {
                    profile: profile.unwrap(),
                    owner,
                    name: member.name,
                    verb: !identity.verb,
                }) {
                    M::Presence(value) => value,
                    _ => {
                        return Err("checker parent opposite-kind builtin facts unsupported".into())
                    }
                }
            }
            M::Presence(value) => value,
            _ => {
                return Err(
                    "parent absence needs authoritative complete intrinsic inventory".into(),
                )
            }
        }
    };
    let owner_text = tree
        .symbols()
        .text(owner)
        .ok_or("parent fact lacks owner spelling")?;
    let name = tree
        .symbols()
        .text(member.name)
        .ok_or("parent fact lacks callable spelling")?;
    // Pinned ProcRef::Display spells verbs with /proc/ too.
    let mut display = format!(
        "{}/proc/{name}",
        if owner_text == "/" { "" } else { owner_text }
    );
    if same_owner_count > 1 {
        display.push_str(&format!("[{}/{}]", identity.occurrence, same_owner_count));
    }
    Ok(ParentFact {
        identity,
        has_parent,
        display,
    })
}

pub fn parent_fact_in_profile(tree:&SemanticTree,member:MemberId,resolver:&(impl Resolver+?Sized),profile:Option<PackedU128>)->Result<ParentFact,String>{parent_fact_in_profile_using(tree,member,resolver,profile,&mut||Ok(()))}
pub(crate) fn parent_fact_in_profile_using<E:From<String>+From<&'static str>>(tree:&SemanticTree,member:MemberId,resolver:&(impl Resolver+?Sized),profile:Option<PackedU128>,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<ParentFact,E>{checkpoint()?;if let Some(profile)=profile{let node=tree.member(member).ok_or("original parent member absent")?;if !matches!(node.kind,MemberKind::Proc|MemberKind::Verb){return Err("original parent member is not callable".into())}let owner=tree.type_node(node.owner).ok_or("original parent owner absent")?.path;if crate::checker_original_group::Group::mixed(tree,owner,node.name)?{let identity=ProcedureIdentity{owner,name:node.name,verb:node.kind==MemberKind::Verb,occurrence:tree.member_occurrence(member).ok_or("original parent source ordinal absent")?};let target=crate::checker_effects::EffectTarget::Source(identity);let group=crate::checker_original_group::Group::for_target_using(tree,profile,target,checkpoint)?.ok_or("original mixed parent group absent")?;let has_parent=group.parent_using(target,resolver,checkpoint)?.is_some();let display=crate::checker_callable_display::original(tree,identity,|_|Ok::<(),E>(()),&mut *checkpoint)?.to_string();checkpoint()?;return Ok(ParentFact{identity,has_parent,display})}}Ok(parent_fact_in_profile_native(tree,member,resolver,profile)?)}

pub fn check(
    frontend: &ColdFrontend,
    body: &ParsedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    check_in_profile(frontend, body, resolver, None, severity)
}
pub fn check_in_profile(
    frontend: &ColdFrontend,
    body: &ParsedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: Option<PackedU128>,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
    let view = BodyView::new(frontend, body)?;
    check_issued_statement_body(
        &frontend.snapshot.tree,
        body.occurrence().member,
        view.syntax(),
        resolver,
        profile,
        severity,
    )
}

/// Caller authenticates primary issuance before entering this common borrowed
/// visitor; live and retained archive paths execute the exact same policy.
pub(crate) fn check_issued_statement_body(
    tree: &SemanticTree,
    member: MemberId,
    syntax: &dm_tree::frontend::StatementBody,
    resolver: &(impl Resolver + ?Sized),
    profile: Option<PackedU128>,
    severity: Severity,
) -> Result<Vec<Diagnostic>, String> {
check_issued_statement_body_using(tree,member,syntax,resolver,profile,severity,&mut||Ok(()))}
pub(crate) fn check_issued_statement_body_using<E:From<String>+From<&'static str>>(
    tree: &SemanticTree,
    member: MemberId,
    syntax: &dm_tree::frontend::StatementBody,
    resolver: &(impl Resolver + ?Sized),
    profile: Option<PackedU128>,
    severity: Severity,
    checkpoint:&mut impl FnMut()->Result<(),E>,
) -> Result<Vec<Diagnostic>, E> {
    checkpoint()?;
    if !syntax.syntax_complete() {
        return Err("checker body contains unsupported primary syntax".into());
    }
    if severity == Severity::Disabled {
        return Ok(Vec::new());
    }
    let mut out = Vec::new();
    let mut fact = None;
    for statement in &syntax.parsed().statements {checkpoint()?;
        let mut expression = |expression: &Expr| -> Result<(), E> {
            if !contains_parent(expression)? {
                return Ok(());
            }
            if fact.is_none() {
                fact = Some(parent_fact_in_profile_using(tree,member,resolver,profile,checkpoint)?);
            }
            let fact = fact.as_ref().unwrap();
            // Every parent call in this body has the same availability. Once a
            // parent exists this family has no refusal, regardless of argument
            // visitation. No other family is being certified here.
            if !fact.has_parent {
                missing_calls(expression, fact, severity, &mut out)?;
            }
            Ok(())
        };
        match &statement.kind {
            StatementKind::Set { .. } | StatementKind::ProjectedSet { .. } => (), // settings are not evaluated
            StatementKind::Var { value, .. } => {
                if let Some(value) = value {
                    expression(value)?;
                }
            }
            StatementKind::Assign { target, value, .. } => {
                expression(target)?;
                expression(value)?;
            }
            StatementKind::Call(value) | StatementKind::Expression(value) => {
                // Pinned statement-level << impurity analysis visits lhs once
                // before the ordinary expression visitor visits it again.
                if let ExprKind::Binary { op, lhs, .. } = &value.kind {
                    if op == "<<" {
                        expression(lhs)?;
                    }
                }
                expression(value)?;
                if matches!(&value.kind, ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(name) if name == "CRASH"))
                {
                    break;
                }
            }
            StatementKind::Return(value) => {
                if let Some(value) = value {
                    expression(value)?;
                }
                break;
            }
            StatementKind::Throw(value) => expression(value)?,
            StatementKind::Goto(_) => (), // pinned checker does not terminate
            _ => {
                return Err(
                    "parent-call policy needs shared pinned visited-expression/control contract"
                        .into(),
                )
            }
        }
    }
    Ok(out)
}

fn contains_parent(expression: &Expr) -> Result<bool, String> {
    if let ExprKind::Call { callee, .. } = &expression.kind {
        if matches!(&callee.kind, ExprKind::Ident(name) if name == "..") {
            return Ok(true);
        }
    }
    if let ExprKind::Literal(text) = &expression.kind {
        if let Some(parts) = text.parts().map_err(str::to_owned)? {
            parts
                .lexical
                .map_err(|e| format!("parent-call literal lexical context unsupported: {e:?}"))?;
        }
    }
    let mut found = false;
    let mut error = None;
    dm_syntax::for_each_expression_child(expression, |_, child| match contains_parent(child) {
        Ok(value) => found |= value,
        Err(value) => error = Some(value),
    });
    if let Some(error) = error {
        Err(error)
    } else {
        Ok(found)
    }
}

fn missing_calls(
    expression: &Expr,
    fact: &ParentFact,
    severity: Severity,
    out: &mut Vec<Diagnostic>,
) -> Result<(), String> {
    if !contains_parent(expression)? {
        return Ok(());
    }
    match &expression.kind {
        ExprKind::Call { callee, args } => match &callee.kind {
            ExprKind::Ident(name) if name == ".." => {
                out.push(Diagnostic {
                    family: "proc_has_no_parent",
                    severity,
                    span: callee.span,
                    expression_span: expression.span,
                    message: format!("proc has no parent: {}", fact.display),
                    notes: Vec::new(),
                });
                // Exact pinned missing-parent branch does NOT visit its args.
            }
            ExprKind::Ident(name) if matches!(name.as_str(), "list" | "alist" | "CRASH") => {
                for arg in args {
                    missing_calls(arg, fact, severity, out)?;
                }
            }
            _ => return Err(
                "parent calls inside call arguments need resolved pinned call-argument visitation"
                    .into(),
            ),
        },
        ExprKind::Group(_)
        | ExprKind::Binary { .. }
        | ExprKind::Conditional { .. }
        | ExprKind::Literal(_) => {
            let mut result = Ok(());
            dm_syntax::for_each_expression_child(expression, |_, child| {
                if result.is_ok() {
                    result = missing_calls(child, fact, severity, out);
                }
            });
            result?;
        }
        // Prefix operators can move the pinned term-origin anchor; don't
        // silently use the nested callee span until that origin is issued.
        _ => {
            return Err(
                "parent-call policy needs exact pinned term/follow origin and visitation".into(),
            )
        }
    }
    Ok(())
}
#[cfg(test)]
#[path = "checks_parent_call_context_tests.rs"]
mod context_tests;
#[cfg(test)]
#[path = "checks_parent_call_tests.rs"]
mod tests;

/// Exact SOURCE predecessor in the pinned checker's unified/global namespace.
/// A builtin boundary is deliberately NOT a fabricated builtin identity: only
/// the separate original-catalog producer may issue that target.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SourcePredecessorProjection {
    Source(ProcedureIdentity),
    NoParent,
    BuiltinBoundary,
}
pub fn source_predecessor_in_profile(
    tree: &SemanticTree,
    member: MemberId,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
) -> Result<SourcePredecessorProjection, String> {source_predecessor_mode(tree,member,resolver,profile,false)}
/// SOURCE annotation history only. Builtin records never own private/protected
/// settings; None here makes NO claim that the callable has no builtin parent.
pub(crate) fn source_annotation_predecessor(tree:&SemanticTree,member:MemberId,resolver:&(impl Resolver+?Sized),profile:PackedU128)->Result<Option<ProcedureIdentity>,String>{match source_predecessor_mode(tree,member,resolver,profile,true)?{SourcePredecessorProjection::Source(identity)=>Ok(Some(identity)),SourcePredecessorProjection::NoParent=>Ok(None),SourcePredecessorProjection::BuiltinBoundary=>Err("source-only annotation projection returned a builtin boundary".into())}}
fn source_predecessor_mode(
    tree: &SemanticTree,
    member: MemberId,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    source_annotations_only: bool,
) -> Result<SourcePredecessorProjection, String> {
    tree.validate_checker_builtin_profile(profile)
        .map_err(|e| format!("source-parent checker profile unavailable: {e:?}"))?;
    let presence = parent_fact_in_profile_native(tree, member, resolver, Some(profile))?;
    let expected = parent_fact_in_profile_native(tree, member, tree, Some(profile))?;
    if presence != expected {
        return Err("source-parent resolver differs from original profile-qualified facts".into());
    }
    let id = presence.identity;
    fn chain(
        tree: &SemanticTree,
        resolver: &(impl Resolver + ?Sized),
        owner: dm_ir::SymbolId,
        id: ProcedureIdentity,
        verb: bool,
    ) -> Result<Option<Arc<[M]>>, String> {
        let q = Q::SourceDeclarationChain {
            owner,
            name: id.name,
            verb,
        };
        let answer = resolver.resolve(q);
        if answer != Resolver::resolve(tree, q) {
            return Err("source-parent chain differs from original current owner".into());
        }
        match answer {
            M::Members(rows) if !rows.is_empty() => Ok(Some(rows)),
            M::Missing => Ok(None),
            _ => Err("source-parent source chain is malformed/unissued".into()),
        }
    }
    // The runtime has distinct proc and verb maps. Until original unified
    // chronology is issued, do not select an old parent from those two maps by
    // name, declaration position, or an assumed preferred kind.
    if chain(tree, resolver, id.owner, id, !id.verb)?.is_some() {
        return Err("exact source-parent needs issued unified proc/verb ordering".into());
    }
    let rows = chain(tree, resolver, id.owner, id, id.verb)?
        .ok_or("source-parent original callable chain absent")?;
    let native = rows
        .iter()
        .find_map(|row| match row {
            M::Declaration {
                identity, previous, ..
            } if *identity == id => Some(previous.as_ref().map(|p| **p)),
            _ => None,
        })
        .ok_or("source-parent chain omits original procedure occurrence")?;
    let mut source = native;
    if source.is_none() && id.owner != dm_ir::SymbolId::of("/") {
        let root = dm_ir::SymbolId::of("/");
        if chain(tree, resolver, root, id, !id.verb)?.is_some() {
            return Err(
                "exact global source-parent needs issued unified proc/verb ordering".into(),
            );
        }
        if let Some(rows) = chain(tree, resolver, root, id, id.verb)? {
            let Some(M::Declaration { identity, .. }) = rows.first() else {
                return Err("global source-parent declaration is unissued".into());
            };
            if identity.owner != root || identity.name != id.name || identity.verb != id.verb {
                return Err("global source-parent identity mismatch".into());
            }
            source = Some(*identity);
        }
    }
    if source_annotations_only{return Ok(source.map_or(SourcePredecessorProjection::NoParent,SourcePredecessorProjection::Source))}
    let query = Q::Ancestry(id.owner);
    let ancestry = resolver.resolve(query);
    if ancestry != Resolver::resolve(tree, query) {
        return Err("source-parent ancestry differs from original owner".into());
    }
    let M::Symbols(ancestors) = ancestry else {
        return Err("source-parent ancestry is unissued".into());
    };
    let depth = |owner| {
        ancestors
            .iter()
            .position(|p| *p == owner)
            .ok_or("source/builtin predecessor lies outside original checker ancestry")
    };
    // Native SourceDeclarationChain omits fixed-DSL implementations, so even
    // its positive predecessor can be farther than an intervening builtin.
    // Ask the ORIGINAL profile for both kinds BEFORE selecting any source.
    let mut builtin_depth = None;
    for verb in [false, true] {
        let q = Q::CheckerBuiltinProc {
            profile,
            owner: id.owner,
            name: id.name,
            verb,
        };
        let builtin = resolver.resolve(q);
        if builtin != Resolver::resolve(tree, q) {
            return Err("source-parent builtin dependency differs from original profile".into());
        }
        match builtin {
            M::Missing => (),
            M::Member {
                owner, name, data, ..
            } => {
                if name != id.name || data.procedure.is_none() || data.inherited_opaque.is_some() {
                    return Err("source-parent builtin metadata is unissued".into());
                }
                if owner == id.owner {
                    return Err(
                        "same-owner builtin/source declaration chronology is not issued".into(),
                    );
                }
                let at = depth(owner)?;
                if builtin_depth == Some(at) {
                    return Err("source-parent builtin proc/verb chronology is not issued".into());
                }
                builtin_depth = Some(builtin_depth.map_or(at, |old: usize| old.min(at)));
            }
            _ => {
                return Err(
                    "source-parent requires original profile-qualified builtin facts".into(),
                )
            }
        }
    }
    if let Some(source) = source {
        if !presence.has_parent {
            return Err("original source predecessor contradicts parent presence".into());
        }
        let source_depth = depth(source.owner)?;
        if builtin_depth.is_some_and(|at| at < source_depth) {
            return Ok(SourcePredecessorProjection::BuiltinBoundary);
        }
        return Ok(SourcePredecessorProjection::Source(source));
    }
    if builtin_depth.is_some() && !presence.has_parent {
        return Err("original builtin predecessor contradicts parent presence".into());
    }
    Ok(if presence.has_parent {
        SourcePredecessorProjection::BuiltinBoundary
    } else {
        SourcePredecessorProjection::NoParent
    })
}
#[cfg(test)]
#[path = "checks_parent_source_projection_tests.rs"]
mod source_projection_tests;
