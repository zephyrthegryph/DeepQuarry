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
    let parent = table.visit_local_spelling_texts(|_, s| longest = longest.max(s.len()));
    if let Some(parent) = parent {
        longest = longest.max(maximum_spelling(parent));
    }
    longest
}
fn maximum_spelling_using<E>(table:&dm_ir::SymbolTable,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<usize,E>{checkpoint()?;let mut longest=0;let mut failure=None;let parent=table.visit_local_spelling_texts(|_,word|{if failure.is_none(){match checkpoint(){Ok(())=>longest=longest.max(word.len()),Err(actual)=>failure=Some(actual)}}});if let Some(actual)=failure{return Err(actual)}if let Some(parent)=parent{longest=longest.max(maximum_spelling_using(parent,checkpoint)?);}Ok(longest)}

/// Scalar census over ORIGINAL issued header spans and provider path widths.
/// No source spelling allocation, second parser, or retained declaration table.
fn maximum_policy_temporary_width(
    archive: &dm_tree::frontend::BodyArchive,
    inputs: &PolicyInputs,
    root: &Path,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<usize, Unsupported> {
    maximum_policy_temporary_width_using(archive,inputs,root,&mut||checkpoint().map_err(Unsupported),false)
}
fn maximum_policy_temporary_width_using<E:From<Unsupported>>(archive:&dm_tree::frontend::BodyArchive,inputs:&PolicyInputs,root:&Path,checkpoint:impl FnMut()->Result<(),E>,checked:bool)->Result<usize,E>{
    maximum_policy_temporary_width_for_paths_using(archive,std::iter::once(root).chain(inputs.files().map(|f|f.path().as_path())),checkpoint,checked)
}
pub(super) fn maximum_policy_temporary_width_for_paths_using<'a,E:From<Unsupported>>(archive:&dm_tree::frontend::BodyArchive,paths:impl IntoIterator<Item=&'a Path>,mut checkpoint:impl FnMut()->Result<(),E>,checked:bool)->Result<usize,E>{
    fn header_width<E:From<Unsupported>>(
        item: dm_tree::frontend::ItemView<'_>,
        depth: usize,
        ancestor_width: usize,
        checkpoint: &mut dyn FnMut() -> Result<(), E>,checked:bool,
    ) -> Result<usize, E> {
        checkpoint()?;
        if !checked&&depth > 128 {
            return Err(Unsupported(
                "stored original header census exceeds bounded nesting admission".into(),
            ).into());
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
                widest = widest.max(header_width(child,depth+1,current_width,checkpoint,checked)?);
            }
        }
        Ok(widest)
    }
    let mut widest = maximum_spelling_using(archive.tree().symbols(),&mut checkpoint)?;
    // OsStr::len is its encoded platform width. UTF8-lossy replacement can
    // expand an invalid byte to three bytes; reserve that without formatting.
    for path in paths {
        checkpoint()?;
        widest = widest.max(
            path.as_os_str()
                .len()
                .checked_mul(3)
                .ok_or_else(|| Unsupported("stored provider path expansion overflow".into()))?,
        );
    }
    let mut headers: Result<usize, E> = Ok(0usize);
    archive.visit_storage(|_, syntax, _| {
        if headers.is_err(){return;}
        headers = syntax.items().try_fold(0usize, |wide, item| {
            Ok(wide.max(header_width(item,0,0,&mut checkpoint,checked)?))
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
    ancestry_using(tree,profile,path,&mut||Ok::<(),Unsupported>(()))
}
fn ancestry_using<E:From<Unsupported>+From<String>>(tree:&SemanticTree,profile:PackedU128,path:&str,poll:&mut impl FnMut()->Result<(),E>)->Result<std::sync::Arc<[SymbolId]>,E>{
    poll()?;
    if !tree
        .checker_source_type_presence(profile, path)
        .map_err(|e| Unsupported(format!("{e:?}")))?
    {
        return Ok(std::sync::Arc::from([]));
    }
    poll()?;match Resolver::resolve(tree, Q::Ancestry(SymbolId::of(path))) {
        M::Symbols(xs) => Ok(xs),
        _ => Err(Unsupported(
            "stored-reference original ancestry unavailable".into(),
        ).into()),
    }
}
fn subtype(
    tree: &SemanticTree,
    profile: PackedU128,
    child: &str,
    parent: &str,
) -> Result<bool, Unsupported> {
    subtype_using(tree,profile,child,parent,&mut||Ok::<(),Unsupported>(()))
}
fn subtype_using<E:From<Unsupported>+From<String>>(tree:&SemanticTree,profile:PackedU128,child:&str,parent:&str,poll:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
    poll()?;
    if child == parent {
        return Ok(true);
    }
    Ok(ancestry_using(tree,profile,child,poll)?.contains(&SymbolId::of(parent)))
}
fn compatible(
    tree: &SemanticTree,
    profile: PackedU128,
    a: &str,
    b: &str,
) -> Result<bool, Unsupported> {
    compatible_using(tree,profile,a,b,&mut||Ok::<(),Unsupported>(()))
}
fn compatible_using<E:From<Unsupported>+From<String>>(tree:&SemanticTree,profile:PackedU128,a:&str,b:&str,poll:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
    Ok(a == b || subtype_using(tree,profile,a,b,poll)? || subtype_using(tree,profile,b,a,poll)?)
}
fn holder_exempt(
    tree: &SemanticTree,
    profile: PackedU128,
    p: &StoredPolicy<'_>,
    owner: &str,
) -> Result<bool, Unsupported> {
    holder_exempt_using(tree,profile,p,owner,&mut||Ok::<(),Unsupported>(()))
}
fn holder_exempt_using<E:From<Unsupported>+From<String>>(tree:&SemanticTree,profile:PackedU128,p:&StoredPolicy<'_>,owner:&str,poll:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
    if owner != "/datum/pooled" && subtype_using(tree,profile,owner,"/datum/pooled",poll)? {
        return Ok(true);
    }
    for ty in p.transient_types {poll()?;
        if subtype_using(tree,profile,owner,ty,poll)? {
            return Ok(true);
        }
    }
    Ok(false)
}
/// The scope lists exact `owner::name` places, never type families.
fn work_queue_using<E>(
    p: &StoredPolicy<'_>,
    owner: &str,
    name: &str,
    poll: &mut impl FnMut() -> Result<(), E>,
) -> Result<bool, E> {
    for row in p.work_queues {
        poll()?;
        if row.strip_prefix(owner).and_then(|tail| tail.strip_prefix("::")) == Some(name) {
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
    related_using(tree,profile,p,owner,name,&mut||Ok::<(),Unsupported>(()))
}
fn related_using<E:From<Unsupported>+From<String>>(tree:&SemanticTree,profile:PackedU128,p:&StoredPolicy<'_>,owner:&str,name:&str,poll:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
    if let Some(types) = p.relations.get(name) {
        for ty in types {poll()?;
            if compatible_using(tree,profile,owner,ty,poll)? {
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
pub(super) fn is_collection_type(ty: &str) -> bool {
    ty == "/list" || ty.starts_with("/list/") || ty == "/alist" || ty.starts_with("/alist/")
}

fn literal(e: &Expr) -> Option<&[Expr]> {
    let ExprKind::Call { callee, args } = &node(e).kind else {
        return None;
    };
    matches!(&callee.kind,ExprKind::Ident(n) if matches!(n.as_str(), "list" | "alist")).then_some(args.as_ref())
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
    stored_ref_using(w,e,&mut||Ok::<(),Unsupported>(()))
}
fn stored_ref_using<E:From<Unsupported>+From<String>>(w:&Walker<'_,SemanticTree>,e:&Expr,poll:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
    poll()?;if let Some(args)=literal_using(e,poll)?{
        for arg in args {poll()?;
            if let ExprKind::Binary { op, lhs, rhs } = &ungroup_using(arg,poll)?.kind {
                if op == "=" {
                    if stored_ref_using(w,lhs,poll)? || stored_ref_using(w,rhs,poll)? {
                        return Ok(true);
                    }
                    continue;
                }
            }
            if stored_ref_using(w,arg,poll)? {
                return Ok(true);
            }
        }
        return Ok(false);
    }
    match w.player_link_receiver_type_using(e,poll)? {
        Some(t) => w.is_ref_using(&t,poll),
        None => Ok(false),
    }
}
fn member_place(
    w: &Walker<'_, SemanticTree>,
    owner: &str,
    name: &str,
) -> Result<Option<Place>, Unsupported> {
    member_place_using(w,owner,name,&mut||Ok::<(),Unsupported>(()))
}
fn member_place_using<E:From<Unsupported>+From<String>>(w:&Walker<'_,SemanticTree>,owner:&str,name:&str,poll:&mut impl FnMut()->Result<(),E>)->Result<Option<Place>,E>{
    poll()?;
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
    Ok(crate::checker_variable_facts::variable_using(
        w.tree,
        w.tree,
        profile,
        SymbolId::of(owner),
        SymbolId::of(name),poll,
    )?
    .map(|v| text(w.tree,v.owner).map(|o|Place::Member(o.into(),name.into())).map_err(E::from))
    .transpose()?)
}
fn place_of(
    sc: &stored_refs_scope::StoredScope<'_>,
    root: &Path,
    rel: &str,
    e: &Expr,
    inputs: &PolicyInputs,
) -> Result<Option<Place>, Unsupported> {
    place_of_using(sc,root,rel,e,inputs,&mut||Ok::<(),Unsupported>(()))
}
fn place_of_using<E:From<Unsupported>+From<String>>(sc:&stored_refs_scope::StoredScope<'_>,root:&Path,rel:&str,e:&Expr,inputs:&PolicyInputs,poll:&mut impl FnMut()->Result<(),E>)->Result<Option<Place>,E>{
    poll()?;
    let w = &sc.walker;
    // Shape-only expression lookup. Static-list origins below come from SAME
    // current SourceLocalView declaration facts, not this Expr's coordinates.
    match &ungroup_using(e,poll)?.kind {
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
            member_place_using(w,text(w.tree,w.owner)?,n,poll)
        }
        ExprKind::Member {
            object, selector, ..
        }
        | ExprKind::SafeMember {
            object, selector, ..
        } => match w.player_link_receiver_type_using(object,poll)? {
            Some(t) => member_place_using(w,&t,selector,poll),
            None => Ok(None),
        },
        _ => Ok(None),
    }
}
// The legacy indexed-write path peels the uninterrupted trailing index chain.
// A grouped intermediate expression remains a separate base.
fn container_place_using<E: From<Unsupported> + From<String>>(
    sc: &stored_refs_scope::StoredScope<'_>,
    root: &Path,
    rel: &str,
    e: &Expr,
    inputs: &PolicyInputs,
    poll: &mut impl FnMut() -> Result<(), E>,
) -> Result<Option<Place>, E> {
    let mut base = ungroup_using(e, poll)?;
    loop {
        poll()?;
        match &base.kind {
            ExprKind::Index { object, .. } | ExprKind::SafeIndex { object, .. } => {
                base = object;
            }
            _ => return place_of_using(sc, root, rel, base, inputs, poll),
        }
    }
}

fn list_place(w: &Walker<'_, SemanticTree>, p: &Place) -> Result<bool, Unsupported> {
    list_place_using(w,p,&mut||Ok::<(),Unsupported>(()))
}
fn list_place_using<E:From<Unsupported>+From<String>>(w:&Walker<'_,SemanticTree>,p:&Place,poll:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
    poll()?;
    let Place::Member(owner, name) = p else {
        return Ok(true);
    };
    let profile = w
        .tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("stored list profile unavailable".into()))?;
    let Some(fact) = crate::checker_variable_facts::variable_using(
        w.tree,
        w.tree,
        profile,
        SymbolId::of(owner),
        SymbolId::of(name),poll,
    )?
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
            .is_none_or(is_collection_type));
    }
    Ok(fact.metadata.declared_type().is_none()
        || fact.metadata.declared_type() == Some(SymbolId::of("/list"))
        || fact.metadata.declared_type() == Some(SymbolId::of("/alist")))
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
fn literal_using<'a,E>(e:&'a Expr,poll:&mut impl FnMut()->Result<(),E>)->Result<Option<&'a[Expr]>,E>{let ExprKind::Call{callee,args}=&ungroup_using(e,poll)?.kind else{return Ok(None)};Ok(matches!(&callee.kind,ExprKind::Ident(n)if matches!(n.as_str(), "list" | "alist")).then_some(args.as_ref()))}
fn method_chain_using<'a,W:crate::policy_body_demand::WorkspaceWork>(e:&'a Expr,out:&mut Vec<(&'a Expr,&'a Expr,&'a str,&'a[Expr])>,work:&mut W)->Result<(),W::Error>{work.checkpoint()?;match &e.kind{ExprKind::Call{callee,args}=>match &callee.kind{ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..}=>{method_chain_using(object,out,work)?;if W::CHECKED{work.retain(256)?;out.try_reserve(1).map_err(|_|work.allocation_failed())?;}out.push((e,object,selector,args));},_=>()},ExprKind::Member{object,..}|ExprKind::SafeMember{object,..}|ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>method_chain_using(object,out,work)?,_=>()}Ok(())}
fn charge_using<W:crate::policy_body_demand::WorkspaceWork>(remaining:&mut usize,n:usize,work:&mut W)->Result<(),W::Error>{work.checkpoint()?;if W::CHECKED{work.retain(n)}else{charge(remaining,n).map_err(W::Error::from)}}
fn strings_charge_using<W:crate::policy_body_demand::WorkspaceWork>(parts:&[&str],remaining:&mut usize,work:&mut W)->Result<(),W::Error>{let n=parts.iter().try_fold(512usize,|n,p|n.checked_add(p.len().checked_mul(8)?)).ok_or_else(||work.overflow())?;charge_using(remaining,n,work)}
struct ExistingStoredDemand<'a,D:crate::policy_body_demand::Demand>{poll:&'a mut dyn FnMut()->Result<(),String>,d:std::marker::PhantomData<D>}
impl<D:crate::policy_body_demand::Demand> crate::policy_body_demand::WorkspaceWork for ExistingStoredDemand<'_,D>{type Error=D::Error;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),D::Error>{(self.poll)().map_err(|e|Unsupported(e).into())}fn retain(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn temporary(&mut self,_:usize)->Result<(),D::Error>{Ok(())}fn overflow(&mut self)->D::Error{Unsupported("stored-reference geometry overflow".into()).into()}fn allocation_failed(&mut self)->D::Error{Unsupported("stored-reference allocation refused".into()).into()}fn body<'a>(&mut self,a:&'a dm_tree::frontend::BodyArchive,n:usize)->Result<ArchivedBody<'a>,D::Error>{D::parse(a,n)}}

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
    stored_findings_with::<crate::policy_body_demand::Compatibility>(
        inputs, root, p, exempt, remaining, checkpoint,
    )
}
pub fn stored_findings_checked(
    inputs: &PolicyInputs,
    root: &Path,
    p: &StoredPolicy<'_>,
    exempt: impl Fn(&str) -> bool,
    remaining: &mut usize,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<StoredFinding>, crate::policy_body_demand::PolicyFailure> {
    stored_findings_with::<crate::policy_body_demand::Checked>(
        inputs, root, p, exempt, remaining, checkpoint,
    )
}
pub fn stored_findings_with<D: crate::policy_body_demand::Demand>(
    inputs: &PolicyInputs,
    root: &Path,
    p: &StoredPolicy<'_>,
    exempt: impl Fn(&str) -> bool,
    remaining: &mut usize,
    checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<StoredFinding>, D::Error> {
    let mut checkpoint=checkpoint;let mut work=ExistingStoredDemand::<D>{poll:&mut checkpoint,d:std::marker::PhantomData};stored_findings_workspace_using(inputs,root,p,exempt,remaining,&mut work,&mut|owner,name,_|Ok((p.has_schema)(owner,name)))
}
pub fn stored_findings_workspace_using<W:crate::policy_body_demand::WorkspaceWork>(inputs:&PolicyInputs,root:&Path,p:&StoredPolicy<'_>,exempt:impl Fn(&str)->bool,remaining:&mut usize,work:&mut W,has_schema:&mut impl FnMut(&str,&str,&mut W)->Result<bool,W::Error>)->Result<Vec<StoredFinding>,W::Error>{
    let work=std::cell::RefCell::new(work);let checkpoint=std::cell::RefCell::new(||work.borrow_mut().checkpoint());
    (checkpoint.borrow_mut())()?;
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("stored references need original checker hierarchy".into()))?;
    // Serial field/return-property projection may transiently normalize original
    // symbol spellings. Reserve its peak before the first such helper call;
    // the original shared symbol owners themselves are not copied or recharged.
    let property_temporary =
        maximum_policy_temporary_width_using(archive,inputs,root,||work.borrow_mut().checkpoint(),W::CHECKED)?
            .checked_mul(64)
            .and_then(|n| n.checked_add(4096))
            .ok_or_else(|| Unsupported("stored property temporary accounting overflow".into()))?;
    if W::CHECKED{work.borrow_mut().temporary(property_temporary)?;}else{charge(remaining,property_temporary)?;}
    let mut excluded = Vec::new();
    for t in p.exempt_types.iter().chain(p.registry) {
        strings_charge_using(&[t],remaining,&mut **work.borrow_mut())?;
        excluded.push(t.clone());
    }
    // Own formal variables, retaining the ORIGINAL first name encounter order.
    let mut seen = HashSet::new();
    let mut vars = Vec::new();
    let mut seeds = Vec::new();
    charge_using(
        remaining,
        tree.members()
            .len()
            .checked_mul(64)
            .ok_or_else(|| Unsupported("stored declaration-order accounting overflow".into()))?,&mut **work.borrow_mut(),
    )?;
    let mut declarations = tree
        .members()
        .iter()
        .enumerate()
        .filter(|(_, m)| m.kind == MemberKind::Var && m.definition == DefinitionMode::Declare)
        .collect::<Vec<_>>();
    crate::checker_order::sort_source_order(&mut declarations,&mut|a,b|->Result<std::cmp::Ordering,W::Error>{work.borrow_mut().checkpoint()?;Ok((a.1.owner.index(),a.0).cmp(&(b.1.owner.index(),b.0)))})?;
    for (_, m) in declarations {
        (checkpoint.borrow_mut())()?;
        let owner = tree
            .type_node(m.owner)
            .ok_or_else(|| Unsupported("stored own owner missing".into()))?
            .path;
        if !seen.contains(&(owner, m.name)) {
            charge_using(remaining,128,&mut **work.borrow_mut())?;
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
        let origin = archive.member_declaration_diagnostic_line(formal).map_err(Unsupported)?;
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
            if dummy.is_ref_using(element,&mut||work.borrow_mut().checkpoint())? {
                strings_charge_using(&[owner, name, &rel],remaining,&mut **work.borrow_mut())?;
                seeds.push((Place::Member(owner.into(), name.into()), rel, line));
            }
            continue;
        }
        if dummy.is_ref_using(declared,&mut||work.borrow_mut().checkpoint())? {
            strings_charge_using(&[owner, name, declared, &rel],remaining,&mut **work.borrow_mut())?;
            let encounter=vars.len();vars.push((
                owner.to_owned(),
                name.to_owned(),
                declared.to_owned(),
                rel,
                line,encounter,
            ));
        }
    }
    crate::checker_order::sort_source_order(&mut vars,&mut|a,b|->Result<std::cmp::Ordering,W::Error>{work.borrow_mut().checkpoint()?;Ok((&a.3,a.4,a.5).cmp(&(&b.3,b.4,b.5)))})?;
    let mut rows = Vec::new();
    for (owner,name,declared,rel,line,_)in vars {
        (checkpoint.borrow_mut())()?;
        if holder_exempt_using(tree, profile, p, &owner, &mut || work.borrow_mut().checkpoint())?
            || work_queue_using(p, &owner, &name, &mut || work.borrow_mut().checkpoint())?
        {
            continue;
        }
        let mut init = false;
        for (t, v) in p.init_only {work.borrow_mut().checkpoint()?;
            if v == &name && compatible_using(tree,profile,&owner,t,&mut||work.borrow_mut().checkpoint())? {
                init = true;
                break;
            }
        }
        if init || related_using(tree, profile, p, &owner, &name, &mut || work.borrow_mut().checkpoint())? {
            continue;
        }
        strings_charge_using(&[&owner, &name, &declared, &rel],remaining,&mut **work.borrow_mut())?;
        if !W::CHECKED&&rows.len() >= 10000 {
            return Err(Unsupported("stored finding limit exceeded".into()).into());
        }
        if W::CHECKED{rows.try_reserve(1).map_err(|_|work.borrow_mut().allocation_failed())?;}
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
    let order_temporary=archive.len().checked_mul(128).and_then(|n|n.checked_add(property_temporary)).ok_or_else(||work.borrow_mut().overflow())?;if W::CHECKED{work.borrow_mut().temporary(order_temporary)?;}
    let mut found = BTreeMap::new();
    for (ordinal, occurrence) in crate::untyped_native::ordered_bodies_using(tree,archive.occurrences(),&mut||work.borrow_mut().checkpoint())?
    {
        (checkpoint.borrow_mut())()?;
        let rel = dm_preprocess::regions::relative_filesystem_path(&occurrence.source.path, root)
            .ok_or_else(|| Unsupported("stored procedure outside root".into()))?
            .to_string_lossy()
            .replace('\\', "/");
        if exempt(&rel) {
            continue;
        }
        let body = work.borrow_mut().body(archive,ordinal)?;if !body.belongs_to(archive)||!std::ptr::eq(body.occurrence(),occurrence){return Err(Unsupported("stored host returned foreign original body loan".into()).into())}
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
        if W::CHECKED{let bytes=transient.checked_add(order_temporary).ok_or_else(||work.borrow_mut().overflow())?;work.borrow_mut().temporary(bytes)?;}else{charge(remaining,transient)?;}
        let sc = stored_refs_scope::archived_stored_scope_using(&body,&excluded,local_source,&mut **work.borrow_mut())?;
        let observed_calls = std::cell::RefCell::new(HashSet::new());
        let writes = std::cell::RefCell::new(Vec::new());
        let retain = std::cell::RefCell::new(|place: Place, at: Span| -> Result<(), W::Error> {
            let (owner, name) = match &place {
                Place::Member(owner, name) => (owner.as_str(), name.as_str()),
                Place::Static(path, _) => (path.as_str(), ""),
            };
            strings_charge_using(&[&rel, owner, name],remaining,&mut **work.borrow_mut())?;
            if !W::CHECKED&&writes.borrow().len() >= 10000 {
                return Err(Unsupported("stored write-coordinate limit exceeded".into()).into());
            }
            if W::CHECKED{writes.borrow_mut().try_reserve(1).map_err(|_|work.borrow_mut().allocation_failed())?;}
            writes.borrow_mut().push((place, at));
            Ok(())
        });
        let observed=crate::untyped_order::try_stored_events_current(
            body.statement_body().view(),&mut(),&mut|_|work.borrow_mut().checkpoint(),
            &mut |_,observed, at| {
                let e = observed.original();
                work.borrow_mut().checkpoint()?;
                let r = (|| -> Result<(), W::Error> {
                    let mut chain = Vec::new();
                    method_chain_using(e,&mut chain,&mut **work.borrow_mut())?;
                    for (call, object, selector, args) in chain {work.borrow_mut().checkpoint()?;if W::CHECKED{work.borrow_mut().retain(256)?;observed_calls.borrow_mut().try_reserve(1).map_err(|_|work.borrow_mut().allocation_failed())?;}
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
                        for a in args.iter().skip(skip) {work.borrow_mut().checkpoint()?;
                            if stored_ref_using(&sc.walker,a,&mut||work.borrow_mut().checkpoint())? {
                                stores = true;
                                break;
                            }
                        }
                        if stores {
                            if let Some(place) = place_of_using(&sc,root,&rel,object,inputs,&mut||work.borrow_mut().checkpoint())? {
                                if list_place_using(&sc.walker,&place,&mut||work.borrow_mut().checkpoint())? {
                                    (retain.borrow_mut())(place, at)?
                                }
                            }
                        }
                    }
                    Ok(())
                })();
                r
            },
            &mut |_,lhs, op, rhs, at| {
                work.borrow_mut().checkpoint()?;
                let r = (|| -> Result<(), W::Error> {
                    if let ExprKind::Index { object, index, .. }
                    | ExprKind::SafeIndex { object, index, .. } = &ungroup_using(lhs,&mut||work.borrow_mut().checkpoint())?.kind
                    {
                        if op == "="
                            && (stored_ref_using(&sc.walker, index, &mut || work.borrow_mut().checkpoint())?
                                || stored_ref_using(&sc.walker, rhs, &mut || work.borrow_mut().checkpoint())?)
                        {
                            if let Some(place) = container_place_using(
                                &sc, root, &rel, object, inputs, &mut || work.borrow_mut().checkpoint(),
                            )? {
                                (retain.borrow_mut())(place, at)?;
                            }
                        } else if matches!(op, "+=" | "|=" | "||=")
                            && stored_ref_using(&sc.walker, rhs, &mut || work.borrow_mut().checkpoint())?
                        {
                            if let Some(place) = container_place_using(
                                &sc, root, &rel, lhs, inputs, &mut || work.borrow_mut().checkpoint(),
                            )? {
                                if list_place_using(&sc.walker, &place, &mut || work.borrow_mut().checkpoint())? {
                                    (retain.borrow_mut())(place, at)?;
                                }
                            }
                        }
                        return Ok(());
                    }
                    if (matches!(op, "+=" | "|=" | "||=") || (op == "=" && literal_using(rhs,&mut||work.borrow_mut().checkpoint())?.is_some()))
                        && stored_ref_using(&sc.walker,rhs,&mut||work.borrow_mut().checkpoint())?
                    {
                        if let Some(place) = place_of_using(&sc,root,&rel,lhs,inputs,&mut||work.borrow_mut().checkpoint())? {
                            if list_place_using(&sc.walker,&place,&mut||work.borrow_mut().checkpoint())? {
                                (retain.borrow_mut())(place, at)?
                            }
                        }
                    }
                    Ok(())
                })();
                r
            },
        );drop(retain);match observed{Ok(())=>(),Err(crate::untyped_order::PolicyVisitFailure::Callback(actual))=>return Err(actual),Err(crate::untyped_order::PolicyVisitFailure::Unsupported(message))=>return Err(Unsupported(message.into()).into())}
        for (place, at) in writes.into_inner() {
            (checkpoint.borrow_mut())()?;
            if found.contains_key(&place) {
                continue;
            }
            let origin = archive
                .original_policy_line(at.start)
                .map_err(Unsupported)?;
            if origin.path != occurrence.source.path {
                return Err(Unsupported(
                    "stored cross-file statement policy projection unavailable".into(),
                )
                .into());
            }
            let (wrel, line) = point(inputs, root, &origin.path, origin.line)?;
            strings_charge_using(&[&wrel],remaining,&mut **work.borrow_mut())?;
            if !W::CHECKED&&found.len() >= 10000 {
                return Err(Unsupported("stored list-place limit exceeded".into()).into());
            }
            found.insert(place, (wrel, line));
        }
        if !W::CHECKED{*remaining=remaining.checked_add(transient).ok_or_else(||Unsupported("stored scope refund overflow".into()))?;}
    }
    for (place, rel, line) in seeds {
        (checkpoint.borrow_mut())()?;
        if !found.contains_key(&place) && !W::CHECKED&&found.len() >= 10000 {
            return Err(Unsupported("stored list-place limit exceeded".into()).into());
        }
        found.entry(place).or_insert((rel, line));
    }
    let mut lists = Vec::new();
    for (place, (wrel, wline)) in found {
        (checkpoint.borrow_mut())()?;
        match place {
            Place::Member(owner, name) => {
                let mut schema = false;
                for ancestor in ancestry_using(tree,profile,&owner,&mut||work.borrow_mut().checkpoint())?.iter().copied().take(65) {work.borrow_mut().checkpoint()?;
                    if has_schema(text(tree,ancestor)?,&name,&mut **work.borrow_mut())? {
                        schema = true;
                        break;
                    }
                }
                if schema
                    || holder_exempt_using(tree, profile, p, &owner, &mut || work.borrow_mut().checkpoint())?
                    || work_queue_using(p, &owner, &name, &mut || work.borrow_mut().checkpoint())?
                    || related_using(tree, profile, p, &owner, &name, &mut || work.borrow_mut().checkpoint())?
                {
                    continue;
                }
                let Some(fact) = crate::checker_variable_facts::variable_using(
                    tree,
                    tree,
                    profile,
                    SymbolId::of(&owner),
                    SymbolId::of(&name),&mut||work.borrow_mut().checkpoint(),
                )?
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
                let origin = archive.member_declaration_diagnostic_line(formal).map_err(Unsupported)?;
                let (rel, line) = point(inputs, root, &origin.path, origin.line)?;
                strings_charge_using(&[&rel, &owner, &name, &wrel],remaining,&mut **work.borrow_mut())?;
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
                strings_charge_using(&[&rel, &wrel],remaining,&mut **work.borrow_mut())?;
                lists.push((
                    rel,
                    line,
                    format!("a proc's static list stores atoms/datums (e.g. {wrel}:{wline})"),
                    String::new(),
                ));
            }
        }
    }
    crate::checker_order::sort_source_order(&mut lists,&mut|a,b|->Result<std::cmp::Ordering,W::Error>{work.borrow_mut().checkpoint()?;Ok(a.cmp(b))})?;
    for (rel, line, message, ident) in lists {
        (checkpoint.borrow_mut())()?;
        if !W::CHECKED&&rows.len() >= 10000 {
            return Err(Unsupported("stored finding limit exceeded".into()).into());
        }
        if W::CHECKED{rows.try_reserve(1).map_err(|_|work.borrow_mut().allocation_failed())?;}
        rows.push(StoredFinding {
            rule: "list",
            rel,
            line,
            message,
            ident,
        });
    }
    (checkpoint.borrow_mut())()?;
    Ok(rows)
}

#[cfg(test)]
#[path = "untyped_stored_refs_tests.rs"]
mod tests;
