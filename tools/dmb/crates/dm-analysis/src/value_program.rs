//! Whole-program value proofs extracted from compiler-issued bodies and the
//! compiler's source declaration queries. All equations are solved together;
//! no member of a recursive group recursively fetches another blocking query.
use crate::{
    native_program::{BodyDemand, CheckedBodyDemand, CompatibilityBodyDemand, Origin},
    untyped::{self, Unsupported, Walker},
    value_equations::{self, Equation, Solution},
    value_expressions::{self, ValueHost},
};
use dm_ir::{
    Parameter, ProcedureIdentity, ProcedureMetadata, ResolveQuery as Q, ResolvedMeaning as M,
    Resolver, SemanticValue, SymbolId, SymbolicExpression,
};
use dm_syntax::{
    Expr, ExprKind, ForControl, ForInitializer, NodeStep, Statement, StatementKind, TypedVisitor,
    VisitDecision,
};
use dm_tree::{
    frontend::{ArchivedBody, BodyArchive, BodyArena, ColdFrontend, ParsedBody},
    DefinitionMode, MemberId, MemberKind, SemanticTree,
};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

#[path = "value_builtin_contracts.rs"]
mod builtins;

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum Key {
    Return(ProcedureIdentity),
    Parameter(ProcedureIdentity, usize),
    Local(ProcedureIdentity, SymbolId),
    Field(SymbolId, SymbolId),
}
type Proof = Equation<Key>;
fn yes(value: bool) -> Proof {
    Proof {
        admissible: value,
        requires: BTreeSet::new(),
    }
}
fn depends(key: Key) -> Proof {
    Proof {
        admissible: true,
        requires: BTreeSet::from([key]),
    }
}
fn merge(into: &mut Proof, other: Proof) {
    into.admissible &= other.admissible;
    into.requires.extend(other.requires);
}
fn node(mut node: &Expr) -> &Expr {
    while let ExprKind::Group(inner) = &node.kind {
        node = inner;
    }
    node
}
fn target_name(expression: &Expr) -> Option<&str> {
    match &node(expression).kind {
        ExprKind::Ident(name) => Some(name),
        ExprKind::Member { selector, .. } | ExprKind::SafeMember { selector, .. } => Some(selector),
        _ => None,
    }
}
fn literal_text(expression: &Expr) -> Option<String> {
    let ExprKind::Literal(text) = &node(expression).kind else {
        return None;
    };
    if let Some(value)=text.original_value(){return match value{dm_syntax::OriginalTokenValue::String(value)=>Some(value.to_owned()),_=>None}}
    let parts = text.parts().ok()??;
    if !parts.expressions.is_empty() {
        return None;
    }
    String::from_utf8(parts.template.clone()).ok()
}
fn symbolic_text(tree: &SemanticTree, value: &SymbolicExpression) -> Option<String> {
    let [token] = value.tokens.as_ref() else {
        return None;
    };
    if token.kind != dm_syntax::TokenKind::String {
        return None;
    }
    let text = dm_syntax::LiteralText::from(tree.symbols().text(token.text)?);
    let parts = text.parts().ok()??;
    if !parts.expressions.is_empty() {
        return None;
    }
    String::from_utf8(parts.template.clone()).ok()
}

fn preserves_rhs(op: &str) -> bool {
    matches!(op, "=" | ":=" | "&&=" | "||=")
}

struct Procedure {
    member: MemberId,
    parent: Option<ProcedureIdentity>,
    metadata: Arc<ProcedureMetadata>,
    scalar_return: bool,
}
struct Index<'a> {
    origin: Origin<'a>,
    tree: &'a SemanticTree,
    procedures: BTreeMap<ProcedureIdentity, Procedure>,
    names: BTreeMap<SymbolId, Vec<ProcedureIdentity>>,
    fields: BTreeMap<(SymbolId, SymbolId), bool>,
    field_names: BTreeMap<SymbolId, Vec<(SymbolId, SymbolId)>>,
    config_writers: BTreeSet<SymbolId>,
}

/// This result contains inference-only equations and summaries, not an AST or
/// copied object tree. The caller owns policy, schemas, findings and baselines.
#[derive(Default)]
struct CallOrigins {
    calls: Vec<Proof>,
    aliases: BTreeSet<SymbolId>,
}

/// Whether the legacy policy regards this expression as a call result, rather
/// than a constructor, pick/input/locate expression or an explicit parent call.
pub(crate) fn is_call_result(expression: &Expr) -> bool {
    let ExprKind::Call { callee, .. } = &node(expression).kind else {
        return false;
    };
    match &node(callee).kind {
        ExprKind::Ident(name) => !matches!(
            name.as_str(),
            "." | ".." | "list" | "pick" | "input" | "locate" | "new"
        ),
        ExprKind::Member { .. } | ExprKind::SafeMember { .. } => true,
        _ => false,
    }
}

/// Owned inference output, with no source, AST or semantic model copy. Policy
/// views share this exact result; rebuilding a view never solves another SCC.
pub struct ValueProof {
    pub equations: BTreeMap<Key, Proof>,
    pub solution: Solution<Key>,
    call_origins: BTreeMap<(ProcedureIdentity, SymbolId), CallOrigins>,
    config_writers: BTreeSet<SymbolId>,
}

pub struct Values<'a> {
    index: Index<'a>,
    resolver: &'a dyn Resolver,
    exempt_types: &'a [String],
    proof: Arc<ValueProof>,
}
impl std::ops::Deref for Values<'_> {
    type Target = ValueProof;
    fn deref(&self) -> &Self::Target {
        &self.proof
    }
}
impl ValueProof {
    pub(crate) fn budget_charge(&self) -> usize {
        // Admission estimate for owned summaries, not a claim of process RSS.
        let equations = self.equations.values().fold(0usize, |bytes, equation| {
            bytes
                .saturating_add(128)
                .saturating_add(equation.requires.len().saturating_mul(64))
        });
        let origins = self.call_origins.values().fold(0usize, |bytes, origin| {
            let calls = origin.calls.iter().fold(0usize, |bytes, proof| {
                bytes
                    .saturating_add(64)
                    .saturating_add(proof.requires.len().saturating_mul(64))
            });
            bytes
                .saturating_add(96)
                .saturating_add(calls)
                .saturating_add(origin.aliases.len().saturating_mul(32))
        });
        equations
            .saturating_add(origins)
            .saturating_add(self.solution.values.len().saturating_mul(96))
            .saturating_add(
                self.solution
                    .components
                    .iter()
                    .map(Vec::len)
                    .sum::<usize>()
                    .saturating_mul(64),
            )
            .saturating_add(self.config_writers.len().saturating_mul(32))
            .saturating_add(4096)
    }
}

fn scalar_annotation(tree: &SemanticTree, value: Option<&SymbolicExpression>) -> bool {
    let Some(value) = value else { return false };
    let Some(text) = value.source_text(tree.symbols()) else {
        return false;
    };
    let mut any = false;
    for token in text
        .split(|c: char| c == '|' || c.is_whitespace())
        .filter(|token| !token.is_empty())
    {
        any = true;
        if !matches!(
            token,
            "text" | "num" | "null" | "message" | "password" | "command_text" | "color" | "key"
        ) {
            return false;
        }
    }
    any
}
fn literal_default(tree: &SemanticTree, value: Option<&SymbolicExpression>) -> bool {
    let Some(value) = value else { return true };
    let [token] = value.tokens.as_ref() else {
        return false;
    };
    match token.kind {
        dm_syntax::TokenKind::Number => true,
        dm_syntax::TokenKind::String => {
            let Some(raw) = tree.symbols().text(token.text) else {
                return false;
            };
            let literal = dm_syntax::LiteralText::from(raw);
            literal
                .parts()
                .is_ok_and(|parts| parts.is_some_and(|parts| parts.expressions.is_empty()))
        }
        _ => tree.symbols().text(token.text) == Some("null"),
    }
}
fn parameter_candidate(tree: &SemanticTree, parameter: &Parameter, source_untyped: bool) -> bool {
    source_untyped
        && parameter.source_expression.is_none()
        && parameter
            .input_annotation
            .as_ref()
            .is_none_or(|annotation| scalar_annotation(tree, Some(annotation)))
        && literal_default(tree, parameter.default.as_ref())
}

impl<'a> Index<'a> {
    fn new(origin: Origin<'a>, resolver: &impl Resolver) -> Result<Self, Unsupported> {
        Self::new_using(origin,resolver,&mut NoopValueWork)
    }
    fn new_using<W:crate::policy_body_demand::WorkspaceWork>(origin:Origin<'a>,resolver:&impl Resolver,work:&mut W)->Result<Self,W::Error>{
        work.checkpoint()?;
        let tree = origin.tree();
        let roster = origin.roster()?;
        let mut procedures = BTreeMap::new();
        let mut names: BTreeMap<_, Vec<_>> = BTreeMap::new();
        for (ordinal, &member) in roster.members().iter().enumerate() {
            work.checkpoint()?;if W::CHECKED{work.retain(4096)?;}
            let identity = roster
                .identity(ordinal)
                .ok_or_else(|| Unsupported("missing issued procedure identity".into()))?;
            let data = tree
                .member(member)
                .ok_or_else(|| Unsupported("missing issued member".into()))?;
            let metadata = data
                .metadata
                .procedure
                .as_ref()
                .ok_or_else(|| Unsupported("missing procedure metadata".into()))?
                .clone();
            let parent = data
                .previous
                .and_then(|member| roster.identity_for_member(member));
            let mut declaration = Some(member);
            let mut scalar_return = false;
            while let Some(id) = declaration {
                work.checkpoint()?;
                let row = tree.member(id).unwrap();
                if row.definition == DefinitionMode::Declare || row.previous.is_none() {
                    scalar_return = row.metadata.procedure.as_ref().is_some_and(|p| {
                        scalar_annotation(tree, p.signature.return_annotation.as_ref())
                    });
                    break;
                }
                declaration = row.previous;
            }
            names.entry(identity.name).or_default().push(identity);
            procedures.insert(
                identity,
                Procedure {
                    member,
                    parent,
                    metadata,
                    scalar_return,
                },
            );
        }
        let mut fields = BTreeMap::new();
        for data in tree
            .members()
            .iter()
            .filter(|member| member.kind == MemberKind::Var)
        {
            work.checkpoint()?;if W::CHECKED{work.retain(4096)?;}
            let owner = tree.type_node(data.owner).unwrap().path;
            let storage = resolve_value_using(resolver,Q::VarStorage {
                owner,
                name: data.name,
            },&mut||work.checkpoint())?;
            let owner = match storage {
                M::Slot { owner, .. } => owner,
                M::InstanceField {
                    declaring_owner, ..
                } => declaring_owner,
                _ => {
                    return Err(Unsupported(
                        "variable storage coverage is incomplete".into(),
                    ).into())
                }
            };
            let init_ok = match (&data.metadata.resolved_constant, &data.metadata.initializer) {
                (
                    Some(
                        SemanticValue::Null
                        | SemanticValue::NumberBits(_)
                        | SemanticValue::Text(_)
                        | SemanticValue::Resource(_),
                    ),
                    _,
                ) => true,
                (None, None) => true,
                (None, Some(value)) => literal_default(tree, Some(value)),
                _ => false,
            };
            let archive = match origin {
                Origin::Archive(archive) => Some(archive),
                Origin::Live(_) => None,
            };
            let untyped = data.metadata.inherited_opaque.is_none()
                && untyped::field_declared_hint_using(
                    tree,
                    resolver,
                    archive,
                    owner,
                    data.name,
                    &data.metadata,&mut||work.checkpoint(),
                )?
                .is_none();
            let candidate = untyped && init_ok && data.metadata.inherited_opaque.is_none();
            *fields.entry((owner, data.name)).or_insert(true) &= candidate;
        }
        let mut field_names: BTreeMap<_, Vec<_>> = BTreeMap::new();
        for &key in fields.keys() {
            work.checkpoint()?;if W::CHECKED{work.retain(256)?;}
            field_names.entry(key.1).or_default().push(key);
        }
        Ok(Self {
            origin,
            tree,
            procedures,
            names,
            fields,
            field_names,
            config_writers: BTreeSet::new(),
        })
    }
    fn subtype(
        &self,
        resolver: &(impl Resolver + ?Sized),
        child: SymbolId,
        parent: SymbolId,
    ) -> Result<bool, Unsupported> {
        self.subtype_using(resolver,child,parent,&mut||Ok::<(),Unsupported>(()))
    }
    fn subtype_using<E:From<Unsupported>+From<String>>(&self,resolver:&(impl Resolver+?Sized),child:SymbolId,parent:SymbolId,poll:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
        poll()?;
        let query = Q::Ancestry(child);
        match resolve_value_using(resolver,query,poll)? {
            M::Symbols(ancestors) => Ok(ancestors.contains(&parent)),
            _ => Err(Unsupported(format!(
                "native value ancestry is incomplete: {query:?}"
            )).into()),
        }
    }
    fn up_chain(&self, id: ProcedureIdentity) -> Vec<ProcedureIdentity> {
        let mut out = Vec::new();
        let mut current = Some(id);
        while let Some(id) = current {
            if out.contains(&id) {
                break;
            }
            out.push(id);
            current = self.procedures.get(&id).and_then(|p| p.parent);
        }
        out
    }
    fn targets(
        &self,
        resolver: &(impl Resolver + ?Sized),
        owner: SymbolId,
        name: SymbolId,
    ) -> Result<Vec<ProcedureIdentity>, Unsupported> {
        self.targets_using(resolver,owner,name,&mut||Ok::<(),Unsupported>(()),&mut|_|Ok(()))
    }
    fn targets_using<E:From<Unsupported>+From<String>>(&self,resolver:&(impl Resolver+?Sized),owner:SymbolId,name:SymbolId,poll:&mut impl FnMut()->Result<(),E>,reserve:&mut impl FnMut(usize)->Result<(),E>)->Result<Vec<ProcedureIdentity>,E>{
        poll()?;
        let mut verb = false;
        let mut query = Q::SourceDeclarationChain { owner, name, verb };
        let mut answer = resolve_value_using(resolver,query,poll)?;
        if matches!(answer, M::Missing) {
            verb = true;
            query = Q::SourceDeclarationChain { owner, name, verb };
            answer = resolve_value_using(resolver,query,poll)?;
        }
        match answer {
            M::Missing => Ok(Vec::new()),
            M::Members(rows) => {
                let Some(M::Declaration { identity, .. }) = rows.first() else {
                    return Err(Unsupported(
                        "native source chain has no selected declaration".into(),
                    ).into());
                };
                reserve(256)?;let mut defs = vec![*identity];
                if owner != SymbolId::of("/") && identity.owner != SymbolId::of("/") {
                    for &id in self.names.get(&name).map_or(&[][..], Vec::as_slice) {
                        poll()?;
                        let procedure = &self.procedures[&id];
                        let data = self.tree.member(procedure.member).unwrap();
                        if id.verb == verb
                            && id.owner != identity.owner
                            && self.subtype_using(resolver,id.owner,owner,poll)?
                            && self.tree.resolve(
                                data.owner,
                                name,
                                if verb {
                                    MemberKind::Verb
                                } else {
                                    MemberKind::Proc
                                },
                            ) == Some(procedure.member)
                        {
                            reserve(256)?;defs.try_reserve(1).map_err(|_|E::from("value definition allocation refused".to_owned()))?;defs.push(id);
                        }
                    }
                }
                crate::checker_order::sort_source_order(&mut defs,&mut|a,b|->Result<std::cmp::Ordering,E>{poll()?;Ok(a.cmp(b))})?;
                defs.dedup();
                Ok(defs)
            }
            _ => Err(Unsupported(format!(
                "native source selection is incomplete: {query:?}"
            )).into()),
        }
    }
}

enum Targets {
    Source(Vec<ProcedureIdentity>),
    Builtin(String, bool),
    Unknown(SymbolId),
}
struct Host<'a, 'b, R: ?Sized> {
    index: &'b Index<'a>,
    scope: &'b Walker<'a, R>,
    resolver: &'a R,
    current: ProcedureIdentity,
    /// Internal inference knows value-local equations. The reference lint's
    /// call-source classification intentionally starts with no value locals.
    local_values: bool,
}
impl<R: Resolver + ?Sized> Host<'_, '_, R> {
    fn targets(&self, call: &Expr) -> Result<Targets, Unsupported> {
        self.targets_using(call,&mut||Ok::<(),Unsupported>(()),&mut|_|Ok(()))
    }
    fn targets_using<E:From<Unsupported>+From<String>>(&self,call:&Expr,poll:&mut impl FnMut()->Result<(),E>,reserve:&mut impl FnMut(usize)->Result<(),E>)->Result<Targets,E>{
        poll()?;
        let ExprKind::Call { callee, .. } = &untyped::ungroup_using(call,poll)?.kind else {
            return Err(Unsupported("expected native call".into()).into());
        };
        let (owner, name, bare): (SymbolId, &str, bool) = match &untyped::ungroup_using(callee,poll)?.kind {
            ExprKind::Ident(name) if name == "." => return Ok(Targets::Source(vec![self.current])),
            ExprKind::Ident(name) if name == ".." => {
                return Ok(Targets::Source(
                    self.index.procedures[&self.current]
                        .parent
                        .into_iter()
                        .collect(),
                ))
            }
            ExprKind::Ident(name) => (self.scope.owner, name, true),
            ExprKind::Unary { op, .. } if op == "::" => {
                match dm_syntax::call_target(untyped::ungroup_using(callee,poll)?) {
                    dm_syntax::CallTarget::GlobalNamed(name) => (SymbolId::of("/"), name, true),
                    _ => return Err(Unsupported("invalid explicit global call target".into()).into()),
                }
            }
            ExprKind::Member {
                object,
                selector,
                via_colon,
            }
            | ExprKind::SafeMember {
                object,
                selector,
                via_colon,
            } => {
                if *via_colon {
                    return Ok(Targets::Unknown(SymbolId::of(selector)));
                }
                let Some(ty) = self.scope.type_of_using(object,poll)? else {
                    return Ok(Targets::Unknown(SymbolId::of(selector)));
                };
                if ty.is_empty() {
                    return Ok(Targets::Unknown(SymbolId::of(selector)));
                }
                (SymbolId::of(&ty), selector, false)
            }
            ExprKind::Unary { op, .. } if op == "new" => return Ok(Targets::Source(Vec::new())),
            _ => return Ok(Targets::Unknown(SymbolId::of("@dynamic-call"))),
        };
        let mut targets = self
            .index
            .targets_using(self.resolver,owner,SymbolId::of(name),poll,reserve)?;
        if targets.is_empty() && bare && owner != SymbolId::of("/") {
            targets = self
                .index
                .targets_using(self.resolver,SymbolId::of("/"),SymbolId::of(name),poll,reserve)?;
        }
        if targets.is_empty() {
            Ok(Targets::Builtin(
                name.to_owned(),
                bare || owner == SymbolId::of("/"),
            ))
        } else {
            Ok(Targets::Source(targets))
        }
    }
    fn call_defs(&self, call: &Expr) -> Result<Vec<ProcedureIdentity>, Unsupported> {
        let ExprKind::Call { callee, .. } = &node(call).kind else {
            return Ok(Vec::new());
        };
        if matches!(&node(callee).kind, ExprKind::Ident(name) if name == ".") {
            // `.()` returns this definition's result, but an explicit argument
            // list narrows the runtime-selected same-name implementations.
            return self
                .index
                .targets(self.resolver, self.current.owner, self.current.name);
        }
        Ok(match self.targets(call)? {
            Targets::Source(defs) => defs,
            Targets::Builtin(_, _) => Vec::new(),
            Targets::Unknown(name) => self.index.names.get(&name).cloned().unwrap_or_default(),
        })
    }
    fn proof_for_defs(&self, definitions: Vec<ProcedureIdentity>) -> Proof {
        Proof {
            admissible: !definitions.is_empty(),
            requires: definitions.into_iter().map(Key::Return).collect(),
        }
    }
    fn source_field(&self, expression: &Expr) -> Result<Option<(SymbolId, SymbolId)>, Unsupported> {
        self.source_field_using(expression,&mut||Ok::<(),Unsupported>(()))
    }
    fn source_field_using<E:From<Unsupported>+From<String>>(&self,expression:&Expr,poll:&mut impl FnMut()->Result<(),E>)->Result<Option<(SymbolId,SymbolId)>,E>{
        let (receiver, name, bare) = match &untyped::ungroup_using(expression,poll)?.kind {
            ExprKind::Ident(name) => (Some(self.scope.owner), name, true),
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => (
                self.scope
                    .type_of_using(object,poll)?
                    .filter(|path| !path.is_empty())
                    .map(|path| SymbolId::of(&path)),
                selector,
                false,
            ),
            _ => return Ok(None),
        };
        let Some(owner) = receiver else {
            return Ok(None);
        };
        let query = Q::VarStorage {
            owner,
            name: SymbolId::of(name),
        };
        let slot = match resolve_value_using(self.resolver,query,poll)? {
            M::Slot { owner, name, .. }
            | M::InstanceField {
                declaring_owner: owner,
                name,
            } => Some((owner, name)),
            // No value proof is supplied by an incomplete storage answer. Writes
            // with that receiver conservatively reach every field of the name.
            M::Missing | M::Unsupported(_) => None,
            _ => return Err(Unsupported("invalid native storage answer".into()).into()),
        };
        if slot.is_some() || owner == SymbolId::of("/") || !bare {
            return Ok(slot);
        }
        Ok(
            match resolve_value_using(self.resolver,Q::VarStorage {
                owner: SymbolId::of("/"),
                name: SymbolId::of(name),
            },poll)? {
                M::Slot { owner, name, .. } => Some((owner, name)),
                M::Missing | M::Unsupported(_) => None,
                _ => return Err(Unsupported("invalid global storage answer".into()).into()),
            },
        )
    }
}
impl<R: Resolver + ?Sized> Host<'_, '_, R> {
    fn pick(&self, args: &[Expr], list_form: bool) -> Result<Proof, Unsupported> {
        self.pick_using(args,list_form,&mut||Ok::<(),Unsupported>(()),&mut|_|Ok(()))
    }
    fn pick_using<E:From<Unsupported>+From<String>>(&self,args:&[Expr],list_form:bool,poll:&mut impl FnMut()->Result<(),E>,reserve:&mut impl FnMut(usize)->Result<(),E>)->Result<Proof,E>{
        poll()?;
        let items = match args {
            [one] if list_form => match &untyped::ungroup_using(one,poll)?.kind {
                ExprKind::Call { callee, args } if matches!(&untyped::ungroup_using(callee,poll)?.kind, ExprKind::Ident(name) if name == "list") => {
                    args.as_slice()
                }
                _ => return Ok(yes(false)),
            },
            _ => args,
        };
        // The reserved `pick` grammar accepts a literal arm directly, including
        // a single arm. Only pickweight's callable form expands a list literal.
        let mut proof = yes(!list_form || !items.is_empty() || args.len() == 1);
        for item in items {
            poll()?;
            if let ExprKind::Binary { op, lhs, rhs } = &untyped::ungroup_using(item,poll)?.kind {
                if op == ";" || list_form && op == "=" {
                    reserve(4096)?;merge(&mut proof, controlled_expression(lhs,self,poll,reserve)?);
                    reserve(4096)?;merge(&mut proof, controlled_expression(rhs,self,poll,reserve)?);
                    continue;
                }
            }
            reserve(4096)?;merge(&mut proof, controlled_expression(item,self,poll,reserve)?);
        }
        Ok(proof)
    }
    fn config_get(&self, receiver: &Expr, args: &[Expr]) -> Result<bool, Unsupported> {
        self.config_get_using(receiver,args,&mut||Ok::<(),Unsupported>(()))
    }
    fn config_get_using<E:From<Unsupported>+From<String>>(&self,receiver:&Expr,args:&[Expr],poll:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
        poll()?;
        let [arg] = args else {
            return Ok(false);
        };
        let ExprKind::TypePath(path) = &untyped::ungroup_using(arg,poll)?.kind else {
            return Ok(false);
        };
        if self.scope.type_of_using(receiver,poll)?.as_deref() != Some("/datum/controller/configuration") {
            return Ok(false);
        }
        let Some(class) = [
            "/datum/config_entry/number",
            "/datum/config_entry/flag",
            "/datum/config_entry/string",
        ]
        .into_iter()
        .find(|class| path == class || path.starts_with(&format!("{class}/"))) else {
            return Ok(false);
        };
        let tree = self.index.tree;
        let mut ty = tree.lookup_type(SymbolId::of(path));
        while let Some(id) = ty {
            poll()?;
            let data = tree
                .type_node(id)
                .ok_or_else(|| Unsupported("missing config type".into()))?;
            if data.path == SymbolId::of(class) {
                return Ok(true);
            }
            if self.index.config_writers.contains(&data.path) {
                return Ok(false);
            }
            ty = data.parent;
        }
        Ok(false)
    }
}

impl<R:Resolver+?Sized> ValueHost<Key> for Host<'_,'_,R>{type Error=Unsupported;fn read(&self,expression:&Expr)->Result<Proof,Unsupported>{self.read_using(expression,&mut||Ok::<(),Unsupported>(()),&mut|_|Ok(()))}fn call(&self,expression:&Expr)->Result<Proof,Unsupported>{self.call_using(expression,&mut||Ok::<(),Unsupported>(()),&mut|_|Ok(()))}}
impl<R:Resolver+?Sized> Host<'_,'_,R>{
    fn read_using<E:From<Unsupported>+From<String>>(&self,expression:&Expr,poll:&mut impl FnMut()->Result<(),E>,reserve:&mut impl FnMut(usize)->Result<(),E>)->Result<Proof,E>{
        match &untyped::ungroup_using(expression,poll)?.kind {
            ExprKind::Ident(name) if self.scope.locals.contains_key(name) => {
                Ok(if self.local_values {
                    depends(Key::Local(self.current, SymbolId::of(name)))
                } else {
                    yes(false)
                })
            }
            ExprKind::Ident(name)
                if matches!(name.as_str(), "src" | "usr" | "world" | "global") =>
            {
                Ok(yes(false))
            }
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } if matches!(&object.kind, ExprKind::Ident(name) if name == "world") => {
                Ok(yes(builtins::WORLD_VALUE_VARS.contains(&selector.as_str())))
            }
            ExprKind::ObjectInitializer { object, .. }
                if matches!(&object.kind, ExprKind::TypePath(_)) =>
            {
                Ok(yes(true))
            }
            ExprKind::Ident(_) | ExprKind::Member { .. } | ExprKind::SafeMember { .. } => {
                let Some((owner, name)) = self.source_field_using(expression,poll)? else {
                    return Ok(yes(false));
                };
                Ok(if self.index.fields.contains_key(&(owner, name)) {
                    depends(Key::Field(owner, name))
                } else {
                    yes(false)
                })
            }
            _ => Ok(yes(false)),
        }
    }
    fn call_using<E:From<Unsupported>+From<String>>(&self,expression:&Expr,poll:&mut impl FnMut()->Result<(),E>,reserve:&mut impl FnMut(usize)->Result<(),E>)->Result<Proof,E>{
        poll()?;
        let ExprKind::Call { callee, args } = &untyped::ungroup_using(expression,poll)?.kind else {
            return Err(Unsupported("expected call".into()).into());
        };
        if matches!(&untyped::ungroup_using(callee,poll)?.kind, ExprKind::Call { callee, .. } if matches!(&untyped::ungroup_using(callee,poll)?.kind, ExprKind::Ident(name) if name == "call_ext"))
        {
            return Ok(yes(true));
        }
        if let ExprKind::Member {
            object, selector, ..
        }
        | ExprKind::SafeMember {
            object, selector, ..
        } = &untyped::ungroup_using(callee,poll)?.kind
        {
            if selector == "Get" && self.config_get_using(object,args,poll)? {
                return Ok(yes(true));
            }
            if matches!(selector.as_str(), "Find" | "Replace")
                && self.scope.type_of_using(object,poll)?.as_deref() == Some("/regex")
                && self
                    .index
                    .targets_using(
                        self.resolver,
                        SymbolId::of("/regex"),
                        SymbolId::of(selector),poll,reserve,
                    )?
                    .is_empty()
            {
                return Ok(yes(true));
            }
        }
        if let Targets::Builtin(name, true) = self.targets_using(expression,poll,reserve)? {
            if matches!(name.as_str(), "pick" | "pickweight") {
                return self.pick_using(args,name=="pickweight",poll,reserve);
            }
        }

        Ok(match self.targets_using(expression,poll,reserve)? {
            Targets::Source(defs) => self.proof_for_defs_using(defs,poll,reserve)?,
            Targets::Builtin(name, bare) => yes(bare
                && builtins::BUILTIN_VALUE_CALLS.contains(&name.as_str())
                || matches!(name.as_str(), "Find" | "Join" | "Replace")
                    && !self.index.names.contains_key(&SymbolId::of(&name))),
            Targets::Unknown(name) => {
                let spelling = self.index.tree.symbols().text(name).unwrap_or("");
                if matches!(spelling, "Find" | "Join" | "Replace")
                    && !self.index.names.contains_key(&name)
                {
                    yes(true)
                } else if dm_ir::builtin_names::is_builtin_proc(spelling) {
                    yes(false)
                } else {
                    {let values=self.index.names.get(&name);reserve(values.map_or(0,|v|v.len()).checked_mul(256).ok_or_else(||E::from("value definitions geometry overflow".to_owned()))?)?;self.proof_for_defs_using(values.cloned().unwrap_or_default(),poll,reserve)?}
                }
            }
        })
    }
 fn proof_for_defs_using<E:From<Unsupported>+From<String>>(&self,definitions:Vec<ProcedureIdentity>,poll:&mut impl FnMut()->Result<(),E>,reserve:&mut impl FnMut(usize)->Result<(),E>)->Result<Proof,E>{let mut proof=Proof{admissible:!definitions.is_empty(),requires:BTreeSet::new()};for definition in definitions{poll()?;reserve(2048)?;proof.requires.insert(Key::Return(definition));}Ok(proof)}
}

// Callback types must be stable across pick -> expression -> host.call -> pick.
// Only the callback vtables are erased: E, first actual IO, order and policy remain unchanged.
struct ControlledValueHost<'a,'b,'p,'r,R:?Sized,E>{host:&'b Host<'a,'b,R>,poll:std::cell::RefCell<&'p mut dyn FnMut()->Result<(),E>>,reserve:std::cell::RefCell<&'r mut dyn FnMut(usize)->Result<(),E>>,error:std::marker::PhantomData<fn()->E>}
impl<R:Resolver+?Sized,E:From<Unsupported>+From<String>> ValueHost<Key> for ControlledValueHost<'_,'_,'_,'_,R,E>{type Error=E;fn checkpoint(&self)->Result<(),E>{(self.poll.borrow_mut())()}fn admit_entries(&self,n:usize)->Result<(),E>{let bytes=n.checked_mul(2048).ok_or_else(||E::from("value requirement geometry overflow".to_owned()))?;(self.reserve.borrow_mut())(bytes)}fn read(&self,e:&Expr)->Result<Proof,E>{self.host.read_using(e,&mut||(self.poll.borrow_mut())(),&mut|n|(self.reserve.borrow_mut())(n))}fn call(&self,e:&Expr)->Result<Proof,E>{self.host.call_using(e,&mut||(self.poll.borrow_mut())(),&mut|n|(self.reserve.borrow_mut())(n))}}
fn controlled_expression<R:Resolver+?Sized,E:From<Unsupported>+From<String>>(expression:&Expr,host:&Host<'_,'_,R>,poll:&mut dyn FnMut()->Result<(),E>,reserve:&mut dyn FnMut(usize)->Result<(),E>)->Result<Proof,E>{let current=ControlledValueHost{host,poll:std::cell::RefCell::new(poll),reserve:std::cell::RefCell::new(reserve),error:std::marker::PhantomData};value_expressions::expression(expression,&current)}
fn resolve_value_using<R:Resolver+?Sized,E>(resolver:&R,query:Q,poll:&mut impl FnMut()->Result<(),E>)->Result<M,E>{poll()?;Ok(resolver.resolve(query))}
struct NoopValueWork;impl crate::policy_body_demand::WorkspaceWork for NoopValueWork{type Error=Unsupported;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),Unsupported>{Ok(())}fn retain(&mut self,_:usize)->Result<(),Unsupported>{Ok(())}fn temporary(&mut self,_:usize)->Result<(),Unsupported>{Ok(())}fn overflow(&mut self)->Unsupported{Unsupported("value geometry overflow".into())}fn allocation_failed(&mut self)->Unsupported{Unsupported("value allocation refused".into())}fn body<'a>(&mut self,a:&'a BodyArchive,n:usize)->Result<ArchivedBody<'a>,Unsupported>{a.parse(n).map_err(|e|Unsupported(e.message))}}

struct Updates {
    call_origins: BTreeMap<SymbolId, CallOrigins>,
    equations: Vec<(Key, Proof)>,
    texts: Vec<(SymbolId, String)>,
    dynamic_vars: BTreeSet<SymbolId>,
    escaped_names: BTreeSet<SymbolId>,
    references: Vec<(SymbolId, SymbolId)>,
}
impl Updates {
    fn new() -> Self {
        Self {
            call_origins: BTreeMap::new(),
            equations: Vec::new(),
            texts: Vec::new(),
            dynamic_vars: BTreeSet::new(),
            escaped_names: BTreeSet::new(),
            references: Vec::new(),
        }
    }
    fn text(&mut self, target: &Expr, value: &Expr) {
        if let (Some(name), Some(text)) = (target_name(target), literal_text(value)) {
            self.texts.push((SymbolId::of(name), text));
        }
    }
}

struct BodyScan<'a, 'b, 'h, 's, R: ?Sized> {
    host: &'h Host<'a, 'b, R>,
    updates: Updates,
    error: Option<Unsupported>,
    local_source: dm_tree::frontend::SourceLocalView<'s>,
}
impl<R: Resolver + ?Sized> BodyScan<'_, '_, '_, '_, R> {
    fn add(&mut self, key: Key, proof: Proof) {
        self.updates.equations.push((key, proof));
    }
    fn rhs(&self, value: &Expr) -> Result<Proof, Unsupported> {
        value_expressions::expression(value, self.host)
    }
    fn call_origin(&mut self, name: SymbolId, rhs: &Expr) -> Result<(), Unsupported> {
        if let ExprKind::Ident(alias) = &node(rhs).kind {
            if self.host.scope.locals.contains_key(alias) {
                self.updates
                    .call_origins
                    .entry(name)
                    .or_default()
                    .aliases
                    .insert(SymbolId::of(alias));
                return Ok(());
            }
        }
        if is_call_result(rhs) {
            let external = Host {
                index: self.host.index,
                scope: self.host.scope,
                resolver: self.host.resolver,
                current: self.host.current,
                local_values: false,
            };
            let proof = value_expressions::expression(rhs, &external)?;
            self.updates
                .call_origins
                .entry(name)
                .or_default()
                .calls
                .push(proof);
        }
        Ok(())
    }
    fn local(
        &mut self,
        header: dm_syntax::Span,
        initializer: Option<&Expr>,
    ) -> Result<(), Unsupported> {
        let fact = crate::untyped::original_local_in_header(&self.local_source, header)?
            .ok_or_else(|| Unsupported("original local value declaration missing".into()))?;
        let name = self.local_source.name(fact).map_err(Unsupported)?;
        let ty = self
            .local_source
            .type_path(fact)
            .map_err(Unsupported)?
            .unwrap_or_default();
        let mut proof = yes(!self.host.scope.is_ref(&ty)?);
        // Exact old NewPrefab/list initializer is not a value. No written
        // expression is forged to represent this grammar-issued constructor.
        if fact.implicit_list_initializer().is_some() {
            merge(&mut proof, yes(false));
        }
        if let Some(value) = initializer {
            merge(&mut proof, self.rhs(value)?);
        }
        self.add(Key::Local(self.host.current, SymbolId::of(name)), proof);
        if let Some(value) = initializer {
            self.call_origin(SymbolId::of(name), value)?;
        }
        if let Some(text) = initializer.and_then(literal_text) {
            self.updates.texts.push((SymbolId::of(name), text));
        }
        Ok(())
    }
    fn assignment(&mut self, target: &Expr, op: &str, value: &Expr) -> Result<(), Unsupported> {
        self.updates.text(target, value);
        if let ExprKind::Ident(name) = &node(target).kind {
            if self.host.scope.locals.contains_key(name) {
                if preserves_rhs(op) {
                    self.call_origin(SymbolId::of(name), value)?;
                    self.add(
                        Key::Local(self.host.current, SymbolId::of(name)),
                        self.rhs(value)?,
                    );
                }
                return Ok(());
            }
            if name == "." {
                return Ok(());
            }
        }
        let possible_name = match &node(target).kind {
            ExprKind::Ident(name) => Some(name),
            ExprKind::Member { selector, .. }
            | ExprKind::SafeMember { selector, .. }
            | ExprKind::StaticMember { selector, .. } => Some(selector),
            _ => None,
        };
        if possible_name.is_none_or(|name| {
            !self
                .host
                .index
                .field_names
                .contains_key(&SymbolId::of(name))
        }) {
            return Ok(());
        }
        let (name, owner) = match &node(target).kind {
            ExprKind::Ident(name) => {
                let owner = if self.host.scope.owner == SymbolId::of("/") {
                    None
                } else {
                    self.host
                        .source_field(target)?
                        .map(|(owner, _)| owner)
                        .filter(|owner| *owner != SymbolId::of("/"))
                };
                (SymbolId::of(name), owner)
            }
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => {
                let ty = self.host.scope.type_of(object)?;
                let owner = if ty.as_ref().is_some_and(|t| !t.is_empty() && t != "/") {
                    self.host.source_field(target)?.map(|(owner, _)| owner)
                } else {
                    None
                };
                (SymbolId::of(selector), owner)
            }
            ExprKind::StaticMember { selector, .. } => (SymbolId::of(selector), None),
            _ => return Ok(()),
        };
        let keys = owner.map_or_else(
            || {
                self.host
                    .index
                    .field_names
                    .get(&name)
                    .cloned()
                    .unwrap_or_default()
            },
            |owner| vec![(owner, name)],
        );
        if keys.is_empty() {
            return Ok(());
        }
        let proof = self.rhs(value)?;
        for (owner, name) in keys {
            self.add(Key::Field(owner, name), proof.clone());
        }
        Ok(())
    }
    fn call_site(&mut self, expression: &Expr) -> Result<(), Unsupported> {
        let ExprKind::Call { callee, args } = &node(expression).kind else {
            return Ok(());
        };
        if matches!(&node(callee).kind, ExprKind::Ident(name) if matches!(name.as_str(), ".." | "."))
            && args.is_empty()
        {
            return Ok(());
        }
        let defs = self.host.call_defs(expression)?;
        let spread = args.iter().any(|arg| match &node(arg).kind {
            ExprKind::Binary { op, .. } => {
                op.ends_with('=')
                    && !matches!(op.as_str(), "==" | "!=" | "<=" | ">=" | "~=" | "~!=")
            }
            ExprKind::Call { callee, .. } => {
                matches!(&callee.kind, ExprKind::Ident(name) if name == "arglist")
            }
            _ => false,
        });
        for definition in defs {
            for definition in self.host.index.up_chain(definition) {
                let count = self.host.index.procedures[&definition]
                    .metadata
                    .signature
                    .parameters
                    .len();
                for (i, arg) in args.iter().enumerate().take(count) {
                    self.add(
                        Key::Parameter(definition, i),
                        if spread { yes(false) } else { self.rhs(arg)? },
                    );
                }
                if spread {
                    for i in 0..count {
                        self.add(Key::Parameter(definition, i), yes(false));
                    }
                }
            }
        }
        Ok(())
    }
    fn escape(&mut self, expression: &Expr) {
        if let ExprKind::TypePath(path) = &node(expression).kind {
            if let Some((owner, name)) = path
                .split_once("/proc/")
                .or_else(|| path.split_once(".proc/"))
            {
                let owner = if owner.is_empty() {
                    if path.starts_with('.') {
                        self.host.current.owner
                    } else {
                        SymbolId::of("/")
                    }
                } else {
                    SymbolId::of(owner)
                };
                self.updates.references.push((owner, SymbolId::of(name)));
            }
        }
        if let ExprKind::Call { callee, args } = &node(expression).kind {
            // `receiver::proc()` is the native syntax for a procedure
            // reference, not an invocation. Its future caller is unobserved.
            // The pinned policy bars every definition of this selector name.
            if let ExprKind::StaticMember { selector, .. } = &node(callee).kind {
                self.updates.escaped_names.insert(SymbolId::of(selector));
            }
            if matches!(&node(callee).kind, ExprKind::Ident(name) if name == "call" || name == "hascall")
            {
                for arg in args {
                    if let Some(text) = literal_text(arg) {
                        self.updates.escaped_names.insert(SymbolId::of(&text));
                    } else if let Some(name) = target_name(arg) {
                        self.updates.dynamic_vars.insert(SymbolId::of(name));
                    }
                }
            }
        }
    }
}
impl<R: Resolver + ?Sized> TypedVisitor for BodyScan<'_, '_, '_, '_, R> {
    fn projected_expression(
        &mut self,
        view: dm_syntax::ProjectedExprView<'_>,
        path: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        // These equation/call/escape helpers inspect syntax shape and names;
        // they do not read expression spans or slice current source text.
        // Declaration-local source receipts remain the statement's own ledger.
        self.expression(view.original(), path)
    }

    fn statement(&mut self, statement: &Statement, _: &[NodeStep]) -> VisitDecision {
        let result = match &statement.kind {
            StatementKind::Var { value, .. } => self.local(statement.header_span, value.as_ref()),
            StatementKind::Assign { target, op, value } => self.assignment(target, op, value),
            StatementKind::For { control, .. } => {
                match control {
                    ForControl::All { declaration, .. }
                    | ForControl::Each {
                        binding: declaration,
                        ..
                    }
                    | ForControl::Range {
                        binding: declaration,
                        ..
                    }
                    | ForControl::RangeImplicitArray {
                        binding: declaration,
                        ..
                    } => {
                        let name = dm_syntax::local_name(declaration).unwrap_or(declaration);
                        self.add(
                            Key::Local(self.host.current, SymbolId::of(name)),
                            yes(false),
                        );
                    }
                    ForControl::Pair {
                        key_binding,
                        value_binding,
                        ..
                    } => {
                        for name in [key_binding, value_binding] {
                            self.add(
                                Key::Local(
                                    self.host.current,
                                    SymbolId::of(dm_syntax::local_name(name).unwrap_or(name)),
                                ),
                                yes(false),
                            );
                        }
                    }
                    ForControl::CStyle {
                        initializer: Some(ForInitializer::Declare { value, .. }),
                        ..
                    } => {
                        if let Err(error) = self.local(statement.header_span, value.as_ref()) {
                            self.error = Some(error);
                            return VisitDecision::Stop;
                        }
                    }
                    _ => (),
                }
                Ok(())
            }
            _ => Ok(()),
        };
        if let Err(error) = result {
            self.error = Some(error);
            VisitDecision::Stop
        } else {
            VisitDecision::Descend
        }
    }
    fn expression(&mut self, expression: &Expr, _: &[NodeStep]) -> VisitDecision {
        self.escape(expression);
        let result = match &expression.kind {
            ExprKind::Binary { op, lhs, rhs }
                if op.ends_with('=')
                    && !matches!(op.as_str(), "==" | "!=" | "<=" | ">=" | "~=" | "~!=") =>
            {
                self.assignment(lhs, op, rhs)
            }
            ExprKind::Call { .. } => self.call_site(expression),
            _ => Ok(()),
        };
        if let Err(error) = result {
            self.error = Some(error);
            VisitDecision::Stop
        } else {
            VisitDecision::Descend
        }
    }
}

impl<'a> Values<'a> {
    pub fn build(
        frontend: &'a ColdFrontend,
        arena: &BodyArena<'a>,
        resolver: &'a impl Resolver,
        exempt_types: &'a [String],
    ) -> Result<Self, Unsupported> {
        Self::build_from(
            Origin::Live(frontend),
            Some(arena),
            resolver,
            exempt_types,
            CompatibilityBodyDemand,
        )
    }
    /// Analyze the retained compiler archive after its transient frontend is gone.
    /// All semantic/body owners remain the archive's original shared handles.
    pub fn build_archive(
        archive: &'a BodyArchive,
        resolver: &'a impl Resolver,
        exempt_types: &'a [String],
    ) -> Result<Self, Unsupported> {
        Self::build_from(
            Origin::Archive(archive),
            None,
            resolver,
            exempt_types,
            CompatibilityBodyDemand,
        )
    }
    pub fn build_archive_checked(
        archive: &'a BodyArchive,
        resolver: &'a impl Resolver,
        exempt_types: &'a [String],
    ) -> Result<Self, crate::value_query::ValueQueryFailure> {
        Self::build_from(
            Origin::Archive(archive),
            None,
            resolver,
            exempt_types,
            CheckedBodyDemand,
        )
    }
    fn build_from<D: BodyDemand>(
        origin: Origin<'a>,
        arena: Option<&BodyArena<'a>>,
        resolver: &'a impl Resolver,
        exempt_types: &'a [String],
        demand: D,
    ) -> Result<Self, D::Failure> {
        let tree = origin.tree();
        let mut index = Index::new(origin, resolver)?;
        // Unique policy fact, derived from the same borrowed syntax before the
        // equations: config subtype effects may not replace the value payload.
        struct ConfigWrites(bool);
        impl TypedVisitor for ConfigWrites {
            fn projected_expression(
                &mut self,
                view: dm_syntax::ProjectedExprView<'_>,
                path: &[dm_syntax::NodeStep],
            ) -> dm_syntax::VisitDecision {
                // Syntax shape/identity only, no current source lookup.
                self.expression(view.original(), path)
            }

            fn statement(&mut self, st: &Statement, _: &[NodeStep]) -> VisitDecision {
                if let StatementKind::Assign { target, .. } = &st.kind {
                    self.target(target);
                }
                VisitDecision::Descend
            }
            fn expression(&mut self, e: &Expr, _: &[NodeStep]) -> VisitDecision {
                if let ExprKind::Binary { op, lhs, .. } = &e.kind {
                    if op.ends_with('=')
                        && !matches!(op.as_str(), "==" | "!=" | "<=" | ">=" | "~=" | "~!=")
                    {
                        self.target(lhs);
                    }
                }
                VisitDecision::Descend
            }
        }
        impl ConfigWrites {
            fn target(&mut self, expr: &Expr) {
                self.0 |= match &node(expr).kind {
                    ExprKind::Ident(name) => name == "config_entry_value",
                    ExprKind::Member { selector, .. } | ExprKind::SafeMember { selector, .. } => {
                        selector == "config_entry_value"
                    }
                    _ => false,
                };
            }
        }
        for (ordinal, occurrence) in origin.bodies().iter().enumerate() {
            let id = origin
                .roster()?
                .identity_for_member(occurrence.member)
                .ok_or_else(|| Unsupported("missing config body identity".into()))?;
            if !index.subtype(resolver, id.owner, SymbolId::of("/datum/config_entry"))? {
                continue;
            }
            demand.with_body(origin, arena, ordinal, |syntax, _, _, _| {
                let mut writes = ConfigWrites(false);
                crate::untyped_order::visit_value_policy(syntax.view(), &mut writes)
                    .map_err(|e| Unsupported(e.into()))?;
                if writes.0 {
                    index.config_writers.insert(id.owner);
                }
                Ok(())
            })?;
        }
        let mut equations = BTreeMap::new();
        let mut texts = Vec::new();
        for member in tree.members().iter().filter(|m| m.kind == MemberKind::Var) {
            if let Some(SemanticValue::Text(text)) = &member.metadata.resolved_constant {
                if let Ok(text) = String::from_utf8(text.to_vec()) {
                    texts.push((member.name, text));
                }
            } else if let Some(text) = member
                .metadata
                .initializer
                .as_ref()
                .and_then(|value| symbolic_text(tree, value))
            {
                texts.push((member.name, text));
            }
        }
        for procedure in index.procedures.values() {
            for parameter in procedure.metadata.signature.parameters.iter() {
                if let Some(text) = parameter
                    .default
                    .as_ref()
                    .and_then(|value| symbolic_text(tree, value))
                {
                    texts.push((parameter.name, text));
                }
            }
        }
        let mut dynamic = BTreeSet::new();
        let mut escaped_names = BTreeSet::new();
        let mut references = Vec::new();
        let mut call_origins = BTreeMap::new();
        for (&(owner, name), &candidate) in &index.fields {
            equations.insert(Key::Field(owner, name), yes(candidate));
        }
        for (&id, procedure) in &index.procedures {
            equations.insert(Key::Return(id), yes(true));
            let spelling = tree.symbols().text(id.name).unwrap_or("");
            let external = id.verb
                || id.owner != SymbolId::of("/") && dm_ir::builtin_names::is_builtin_proc(spelling);
            for (i, parameter) in procedure.metadata.signature.parameters.iter().enumerate() {
                equations.insert(Key::Parameter(id, i), yes(!external));
                equations.insert(
                    Key::Local(id, parameter.name),
                    depends(Key::Parameter(id, i)),
                );
            }
        }
        for (&id, procedure) in &index.procedures {
            if let Some(parent) = procedure.parent {
                for i in 0..procedure.metadata.signature.parameters.len().min(
                    index.procedures[&parent]
                        .metadata
                        .signature
                        .parameters
                        .len(),
                ) {
                    equations
                        .get_mut(&Key::Parameter(parent, i))
                        .unwrap()
                        .requires
                        .insert(Key::Parameter(id, i));
                }
            }
        }
        for ordinal in 0..origin.bodies().len() {
            demand.with_body(
                origin,
                arena,
                ordinal,
                |syntax, occurrence, parameters, local_source| {
                    let scope = untyped::scope_from_parameters(
                        tree,
                        occurrence,
                        syntax,
                        resolver,
                        exempt_types,
                        Some(parameters),
                        Some(local_source),
                    )?;
                    let scope = match origin {
                        Origin::Archive(archive) => scope.with_archive(archive)?,
                        Origin::Live(_) => scope,
                    };
                    let id = origin
                        .roster()?
                        .identity_for_member(occurrence.member)
                        .ok_or_else(|| Unsupported("missing current procedure".into()))?;
                    // CallableRoster is issued one-to-one from ORIGINAL body
                    // occurrences. Fill type admissibility only from that body's
                    // sealed parameter receipt, preserving prior call constraints.
                    let procedure = &index.procedures[&id];
                    let mut native = procedure.metadata.signature.parameters.iter().enumerate();
                    for entry in parameters
                        .entries()
                        .map_err(Unsupported)?
                        .iter()
                        .filter(|p| !p.variadic())
                    {
                        let (i, parameter) = native.next().ok_or_else(|| {
                            Unsupported("original parameter inference ordinal missing".into())
                        })?;
                        let untyped =
                            entry.type_components().is_empty() && entry.array_brackets().is_empty();
                        merge(
                            equations.get_mut(&Key::Parameter(id, i)).unwrap(),
                            yes(parameter_candidate(tree, parameter, untyped)),
                        );
                    }
                    if native.next().is_some() {
                        return Err(Unsupported(
                            "original parameter inference roster differs".into(),
                        ));
                    }

                    let host = Host {
                        index: &index,
                        scope: &scope,
                        resolver,
                        current: id,
                        local_values: true,
                    };
                    for name in scope.locals.keys() {
                        let key = Key::Local(id, SymbolId::of(name));
                        let shadow = tree
                            .lookup_type(scope.owner)
                            .and_then(|owner| {
                                tree.resolve(owner, SymbolId::of(name), MemberKind::Var)
                            })
                            .is_some()
                            || tree
                                .lookup_type(SymbolId::of("/"))
                                .and_then(|owner| {
                                    tree.resolve(owner, SymbolId::of(name), MemberKind::Var)
                                })
                                .is_some();
                        let entry = equations.entry(key).or_insert_with(|| yes(true));
                        entry.admissible &= !shadow;
                    }
                    let proof = value_expressions::returns(syntax, &host).map_err(|error| {
                        Unsupported(format!("native return proof incomplete: {error:?}"))
                    })?;
                    if !index.procedures[&id].scalar_return {
                        merge(equations.get_mut(&Key::Return(id)).unwrap(), proof);
                    }
                    let mut scan = BodyScan {
                        host: &host,
                        local_source,
                        updates: Updates::new(),
                        error: None,
                    };
                    crate::untyped_order::visit_value_policy(syntax.view(), &mut scan)
                        .map_err(|e| Unsupported(e.into()))?;
                    if let Some(error) = scan.error {
                        return Err(error);
                    }
                    for (key, proof) in scan.updates.equations {
                        merge(equations.entry(key).or_insert_with(|| yes(true)), proof);
                    }
                    for (name, origin) in scan.updates.call_origins {
                        call_origins.insert((id, name), origin);
                    }
                    texts.extend(scan.updates.texts);
                    dynamic.extend(scan.updates.dynamic_vars);
                    escaped_names.extend(scan.updates.escaped_names);
                    references.extend(scan.updates.references);
                    Ok(())
                },
            )?;
        }
        for (variable, value) in texts {
            if dynamic.contains(&variable) {
                escaped_names.insert(SymbolId::of(&value));
            }
        }
        let mut escaped = Vec::new();
        for name in escaped_names {
            escaped.extend(index.names.get(&name).cloned().unwrap_or_default());
        }
        for (owner, name) in references {
            let targets = index.targets(resolver, owner, name)?;
            if targets.is_empty() {
                escaped.extend(index.names.get(&name).cloned().unwrap_or_default());
            } else {
                escaped.extend(targets);
            }
        }
        for id in escaped {
            for id in index.up_chain(id) {
                for i in 0..index.procedures[&id].metadata.signature.parameters.len() {
                    equations
                        .get_mut(&Key::Parameter(id, i))
                        .unwrap()
                        .admissible = false;
                }
            }
        }
        let solution = value_equations::solve(&equations).map_err(|missing| {
            Unsupported(format!("missing native value dependency: {missing:?}"))
        })?;
        let proof = Arc::new(ValueProof {
            equations,
            solution,
            call_origins,
            config_writers: index.config_writers.clone(),
        });
        Ok(Self {
            index,
            resolver,
            exempt_types,
            proof,
        })
    }
    pub(crate) fn into_summary(self) -> Arc<ValueProof> {
        self.proof
    }

    /// Borrow a policy view over one authenticated, reusable source-semantic
    /// proof. The query host owns caching; no second cache is created here.
    pub fn from_archive_input(
        input: &'a Arc<crate::value_query::ArchiveValueInput>,
        proof: Arc<crate::value_query::ArchiveValueProof>,
    ) -> Result<Self, Unsupported> {
        Self::from_archive_input_using(input,proof,&mut NoopValueWork)
    }
    pub fn from_archive_input_using<W:crate::policy_body_demand::WorkspaceWork>(input:&'a Arc<crate::value_query::ArchiveValueInput>,proof:Arc<crate::value_query::ArchiveValueProof>,work:&mut W)->Result<Self,W::Error>{
        work.checkpoint()?;proof.validate_for(input)?;
        let archive = input.archive();
        let resolver = archive.tree();
        let mut index = Index::new_using(Origin::Archive(archive),resolver,work)?;
        let summary = proof.summary();
        if W::CHECKED{let bytes=summary.config_writers.len().checked_mul(2048).ok_or_else(||work.overflow())?;work.retain(bytes)?;}
        index.config_writers = summary.config_writers.clone();
        Ok(Self {
            index,
            resolver,
            exempt_types: input.exempt_types(),
            proof: summary,
        })
    }
    /// Policy entry points validate the exact owner even when no body produces
    /// a finding, so an empty result is not permission to reuse another revision.
    pub(crate) fn validate_live(&self, frontend: &ColdFrontend) -> Result<(), Unsupported> {
        if self.index.origin.is_live(frontend) {
            Ok(())
        } else {
            Err(Unsupported(
                "value summaries belong to another frontend issuance".into(),
            ))
        }
    }
    pub(crate) fn validate_archive(&self, archive: &BodyArchive) -> Result<(), Unsupported> {
        if self.index.origin.is_archive(archive) {
            Ok(())
        } else {
            Err(Unsupported(
                "value summaries belong to another archive issuance".into(),
            ))
        }
    }
    pub(crate) fn validate_exempt_types(&self, candidate: &[String]) -> Result<(), Unsupported> {
        // Exemption order and repeated entries do not change the policy. The
        // borrowed configuration belongs to the same inference issuance, but
        // an independently owned equal configuration remains admissible.
        if self
            .exempt_types
            .iter()
            .all(|value| candidate.contains(value))
            && candidate
                .iter()
                .all(|value| self.exempt_types.contains(value))
        {
            Ok(())
        } else {
            Err(Unsupported(
                "value summaries use another type-exemption configuration".into(),
            ))
        }
    }
    /// One immutable resolver binding supplies both field/type classification
    /// and the call proofs already extracted into these summaries.
    pub(crate) fn resolver(&self) -> &'a dyn Resolver {
        self.resolver
    }
    /// The lint reports authored declarations only. A named argument or a
    /// non-field assignment cannot create a declaration from a selector spelling.
    pub(crate) fn has_field_name(
        &self,
        frontend: &ColdFrontend,
        name: &str,
    ) -> Result<bool, Unsupported> {
        if !self.index.origin.is_live(frontend) {
            return Err(Unsupported(
                "value summaries belong to another frontend issuance".into(),
            ));
        }
        Ok(self.index.field_names.contains_key(&SymbolId::of(name)))
    }
    pub(crate) fn archive_has_field_name(
        &self,
        archive: &BodyArchive,
        name: &str,
    ) -> Result<bool, Unsupported> {
        if !self.index.origin.is_archive(archive) {
            return Err(Unsupported(
                "value summaries belong to another archive issuance".into(),
            ));
        }
        Ok(self.index.field_names.contains_key(&SymbolId::of(name)))
    }
    fn archive_body_identity(
        &self,
        body: &ArchivedBody<'_>,
    ) -> Result<ProcedureIdentity, Unsupported> {
        if !self.index.origin.owns_archive_body(body) {
            return Err(Unsupported(
                "value summaries belong to another archive issuance".into(),
            ));
        }
        if !body.statement_body().syntax_complete() {
            return Err(Unsupported(
                "archive has unsupported or malformed native syntax".into(),
            ));
        }
        self.index
            .origin
            .roster()?
            .identity_for_member(body.occurrence().member)
            .ok_or_else(|| Unsupported("missing archived callable identity".into()))
    }
    pub(crate) fn archive_local_holds_call(
        &self,
        body: &ArchivedBody<'_>,
        name: &str,
    ) -> Result<bool, Unsupported> {
        Ok(self.local_holds_call_for(self.archive_body_identity(body)?, name))
    }
    // Expression queries are crate-private policy helpers. Only the native
    // walker supplies borrowed expressions from the authenticated body; these
    // are not public issued-expression admission APIs for arbitrary callers.
    pub(crate) fn archive_call_is_value(
        &self,
        body: &ArchivedBody<'_>,
        expression: &Expr,
        exempt_types: &[String],
    ) -> Result<bool, Unsupported> {
        self.validate_exempt_types(exempt_types)?;
        let current = self.archive_body_identity(body)?;
        let scope = untyped::archived_scope(body, self.resolver, exempt_types)?;
        let host = Host {
            index: &self.index,
            scope: &scope,
            resolver: self.resolver,
            current,
            local_values: false,
        };
        let proof = value_expressions::expression(expression, &host)?;
        Ok(proof.admissible && proof.requires.iter().all(|key| self.is_value(key)))
    }

 pub(crate) fn archive_call_is_value_using<W:crate::policy_body_demand::WorkspaceWork>(&self,body:&ArchivedBody<'_>,expression:&Expr,exempt_types:&[String],work:&mut W)->Result<bool,W::Error>{work.checkpoint()?;self.validate_exempt_types(exempt_types)?;let current=self.archive_body_identity(body)?;let scope=untyped::archived_scope_using(body,self.resolver,exempt_types,work)?;let host=Host{index:&self.index,scope:&scope,resolver:self.resolver,current,local_values:false};let shared=std::cell::RefCell::new(work);let proof=controlled_expression(expression,&host,&mut||shared.borrow_mut().checkpoint(),&mut|n|shared.borrow_mut().retain(n))?;if !proof.admissible{return Ok(false)}for key in &proof.requires{shared.borrow_mut().checkpoint()?;if !self.is_value(key){return Ok(false)}}Ok(true)}
 pub(crate) fn archive_local_holds_call_using<W:crate::policy_body_demand::WorkspaceWork>(&self,body:&ArchivedBody<'_>,name:&str,work:&mut W)->Result<bool,W::Error>{let id=self.archive_body_identity(body)?;work.checkpoint()?;if W::CHECKED{work.retain(256)?;}let mut todo=vec![SymbolId::of(name)];let mut visited=BTreeSet::new();while let Some(name)=todo.pop(){work.checkpoint()?;if W::CHECKED{work.retain(2048)?;}if !visited.insert(name){continue}if let Some(origin)=self.call_origins.get(&(id,name)){for proof in &origin.calls{work.checkpoint()?;if !proof.admissible{return Ok(true)}for key in &proof.requires{work.checkpoint()?;if !self.is_value(key){return Ok(true)}}}for alias in &origin.aliases{work.checkpoint()?;if W::CHECKED{work.retain(256)?;todo.try_reserve(1).map_err(|_|work.allocation_failed())?;}todo.push(*alias);}}}Ok(false)}
    pub fn is_value(&self, key: &Key) -> bool {
        self.solution.values.get(key).copied().unwrap_or(false)
    }
    pub(crate) fn local_holds_call(
        &self,
        frontend: &ColdFrontend,
        body: &ParsedBody<'_>,
        name: &str,
    ) -> Result<bool, Unsupported> {
        if !self.index.origin.is_live(frontend) {
            return Err(Unsupported(
                "value summaries belong to another frontend issuance".into(),
            ));
        }
        frontend
            .validate_parsed_body(body, body.occurrence())
            .map_err(|error| Unsupported(error.message))?;
        let id = frontend
            .callable_roster()
            .map_err(Unsupported)?
            .identity_for_member(body.occurrence().member)
            .ok_or_else(|| Unsupported("missing callable identity".into()))?;
        Ok(self.local_holds_call_for(id, name))
    }
    fn local_holds_call_for(&self, id: ProcedureIdentity, name: &str) -> bool {
        let mut todo = vec![SymbolId::of(name)];
        let mut visited = BTreeSet::new();
        while let Some(name) = todo.pop() {
            if !visited.insert(name) {
                continue;
            }
            if let Some(origin) = self.call_origins.get(&(id, name)) {
                if origin.calls.iter().any(|proof| {
                    !proof.admissible || proof.requires.iter().any(|key| !self.is_value(key))
                }) {
                    return true;
                }
                todo.extend(origin.aliases.iter().copied());
            }
        }
        false
    }
    pub(crate) fn call_is_value(
        &self,
        frontend: &'a ColdFrontend,
        body: &ParsedBody<'_>,
        expression: &Expr,
        exempt_types: &'a [String],
    ) -> Result<bool, Unsupported> {
        if !self.index.origin.is_live(frontend) {
            return Err(Unsupported(
                "value summaries belong to another frontend issuance".into(),
            ));
        }
        self.validate_exempt_types(exempt_types)?;
        let scope = untyped::scope(frontend, body, self.resolver, exempt_types)?;
        let current = frontend
            .callable_roster()
            .map_err(Unsupported)?
            .identity_for_member(body.occurrence().member)
            .ok_or_else(|| Unsupported("missing current callable".into()))?;
        let host = Host {
            index: &self.index,
            scope: &scope,
            resolver: self.resolver,
            current,
            local_values: false,
        };
        let proof = value_expressions::expression(expression, &host)?;
        Ok(proof.admissible && proof.requires.iter().all(|key| self.is_value(key)))
    }
}

#[cfg(test)]
#[path = "value_program_tests.rs"]
mod tests;
