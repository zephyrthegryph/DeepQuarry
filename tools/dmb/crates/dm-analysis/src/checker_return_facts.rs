//! Static return hints from native source declarations and exact checker SDK
//! provenance, not executable-body inference or builtin-name availability.
//! Policy: SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc,
//! dreamchecker/lib.rs SHA256 dd17edc32409c5f9a8c2ca31b55386b6bcfdd309d9c0455627c667b0d9f45fdd (GPL-3.0).
use crate::checker_call_facts::{self, CallableFact};
use dm_ir::{
    PackedU128, ProcedureDefinition, ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId,
};
use dm_tree::SemanticTree;
use crate::checker_prefix_demand::Demand as PrefixDemand;
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ReturnHint {
    pub declared_type: Option<SymbolId>,
    pub list_element_type: Option<SymbolId>,
}
impl ReturnHint {
    fn none() -> Self {
        Self {
            declared_type: None,
            list_element_type: None,
        }
    }
    fn direct(path: &str) -> Self {
        Self {
            declared_type: Some(SymbolId::of(path)),
            list_element_type: None,
        }
    }
    fn list(element: Option<&str>) -> Self {
        Self {
            declared_type: Some(SymbolId::of("/list")),
            list_element_type: element.map(SymbolId::of),
        }
    }
}
pub fn return_hint(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
) -> Result<ReturnHint, String> {
    return_hint_with_prefix(tree, resolver, profile, receiver, name, None)
}
pub fn return_hint_with_prefix(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive>,
) -> Result<ReturnHint, String> {
    return_hint_mode(tree, resolver, profile, receiver, name, archive, None)
}
pub fn return_hint_with_prefix_for_purity(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    permit: &PuritySettingsPermit<'_>,
) -> Result<ReturnHint, String> {
    permit.require(tree, archive, profile, permit.identity)?;
    return_hint_mode(
        tree,
        resolver,
        profile,
        receiver,
        name,
        archive,
        Some(permit),
    )
}
fn return_hint_mode(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    permit: Option<&PuritySettingsPermit<'_>>,
) -> Result<ReturnHint, String> {
    return_hint_mode_using(tree,resolver,profile,receiver,name,archive,permit, &crate::checker_prefix_demand::Compatibility::<String>::new())
}
fn return_hint_mode_using<D:PrefixDemand>(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    permit: Option<&PuritySettingsPermit<'_>> , demand:&D
) -> Result<ReturnHint , D::Error> {
    return_hint_mode_controlled_using(tree,resolver,profile,receiver,name,archive,permit,demand,false)
}
pub(crate) fn return_hint_without_return_prefix_using<D:PrefixDemand>(tree:&SemanticTree,resolver:&(impl Resolver+?Sized),profile:PackedU128,receiver:SymbolId,name:SymbolId,archive:Option<&dm_tree::frontend::BodyArchive>,permit:Option<&PuritySettingsPermit<'_>>,demand:&D)->Result<ReturnHint,D::Error>{return_hint_mode_controlled_using(tree,resolver,profile,receiver,name,archive,permit,demand,true)}
fn return_hint_mode_controlled_using<D:PrefixDemand>(tree:&SemanticTree,resolver:&(impl Resolver+?Sized),profile:PackedU128,receiver:SymbolId,name:SymbolId,archive:Option<&dm_tree::frontend::BodyArchive>,permit:Option<&PuritySettingsPermit<'_>>,demand:&D,skip_return_prefix:bool)->Result<ReturnHint,D::Error>{
    if resolver.source_owner() != Resolver::source_owner(tree) {
        return Err("return context lacks original compiled owner provenance".into());
    }
    demand.validate_profile(tree,profile)
        .map_err(|e| format!("return checker profile unavailable: {e:?}"))?;
    let fact = checker_call_facts::callable_any_using(tree,resolver,profile,receiver,name,&mut||demand.checkpoint())?;
    match fact {
        CallableFact::Missing => Err("return hint requires a positively resolved callable".into()),
        CallableFact::CheckerBuiltin {
            declaring_owner, ..
        } => {
            if permit.is_some() {
                return Err("purity source permit cannot certify a builtin callable".into());
            }
            // Gate every name by genuine hash-qualified declaration provenance;
            // this table never proves callable presence or runtime ABI metadata.
            if declaring_owner != SymbolId::of("/") {
                return Ok(ReturnHint::none());
            }
            Ok(match name {
                x if ["block"].iter().any(|s| x == SymbolId::of(s)) => {
                    ReturnHint::list(Some("/turf"))
                }
                x if ["bounds", "obounds", "orange", "oview", "range", "view"]
                    .iter()
                    .any(|s| x == SymbolId::of(s)) =>
                {
                    ReturnHint::list(Some("/atom"))
                }
                x if ["hearers", "ohearers", "oviewers", "viewers"]
                    .iter()
                    .any(|s| x == SymbolId::of(s)) =>
                {
                    ReturnHint::list(Some("/mob"))
                }
                // Preserve pinned unreachable "argslist" spelling. The fixed
                // SDK declares arglist, not argslist, so real resolver facts
                // cannot admit this branch for an invented builtin.
                x if ["argslist", "flist", "icon_states", "splittext", "typesof"]
                    .iter()
                    .any(|s| x == SymbolId::of(s)) =>
                {
                    ReturnHint::list(None)
                }
                x if x == SymbolId::of("get_step") => ReturnHint::direct("/turf"),
                x if x == SymbolId::of("icon") => ReturnHint::direct("/icon"),
                x if x == SymbolId::of("matrix") => ReturnHint::direct("/matrix"),
                x if x == SymbolId::of("regex") => ReturnHint::direct("/regex"),
                _ => ReturnHint::none(),
            })
        }
        CallableFact::Source { identity, metadata } => {
            if let Some(permit) = permit {
                permit.require(tree, archive, profile, identity)?;
            }
            if identity.owner == SymbolId::of("/") && identity.name == SymbolId::of("astype") {
                return Err("pinned astype needs shared argument typepath/value facts".into());
            }
            let prefix = if metadata
                .procedure
                .as_ref()
                .ok_or("source signature absent")?
                .settings
                .is_empty()
            {
                None
            } else {
                validate_source_directives_mode_using(tree, archive, identity, permit, demand)?;
                if skip_return_prefix{None}else{prefix_return_override_mode_using(tree, archive, identity, permit, demand)?}
            };
            let query = Q::SourceDeclarationChain {
                owner: identity.owner,
                name: identity.name,
                verb: identity.verb,
            };
            let answer = resolver.resolve(query);
            if answer != Resolver::resolve(tree, query) {
                return Err("return header host differs from source declaration chain".into());
            }
            let M::Members(rows) = answer else {
                return Err("return header source chain unavailable".into());
            };
            let mut annotation = None;
            let mut formal_seen = false;
            for row in rows.iter() {
                let M::Declaration {
                    definition, data, ..
                } = row
                else {
                    return Err("return header malformed source chain".into());
                };
                if *definition == ProcedureDefinition::Declare {
                    formal_seen = true;
                    annotation = data
                        .procedure
                        .as_ref()
                        .ok_or("formal signature absent")?
                        .signature
                        .return_annotation
                        .as_ref();
                    break;
                }
            }
            if !formal_seen
                && metadata
                    .procedure
                    .as_ref()
                    .unwrap()
                    .signature
                    .return_annotation
                    .is_some()
            {
                return Err(
                    "implicit callable return annotation lacks native formal-selection proof"
                        .into(),
                );
            }
            if let Some(annotation) = annotation {
                let path = annotation.absolute_type_path(tree.symbols()).ok_or(
                    "source return annotation requires native input-union/type-expression facts",
                )?;
                let projected = dm_syntax::project_declaration_type(&path);
                let header = ReturnHint {
                    declared_type: Some(SymbolId::of(projected.runtime_path)),
                    list_element_type: projected
                        .list_element_path
                        .map(|p| SymbolId::of(&format!("/{p}"))),
                };
                return Ok(prefix.unwrap_or(header));
            }
            if let Some(prefix) = prefix {
                return Ok(prefix);
            }
            if identity.owner == SymbolId::of("/") && identity.name == SymbolId::of("get_step") {
                return Err("source override of pinned get_step seed requires exact settings-stage selection proof".into());
            }
            Ok(ReturnHint::none())
        }
    }
}

#[cfg(test)]
#[path = "checker_return_facts_tests.rs"]
mod tests;

/// Narrow source-setting admission for the effect producer only. Fields are
/// sealed and borrow the ORIGINAL archive (therefore its tree, mapping and
/// BodySyntax host). A permit cannot authorize an equal-but-foreign revision.
pub struct PuritySettingsPermit<'a> {
    archive: &'a dm_tree::frontend::BodyArchive,
    profile: PackedU128,
    identity: dm_ir::ProcedureIdentity,
    own_pure: Option<dm_syntax::Span>,
    own_no_sleep: Option<dm_syntax::Span>,
    own_sleep_exempt: Option<dm_syntax::Span>,
    validated_profile:Option<dm_tree::checker_builtins::ValidatedCheckerProfile<'a>>,
}
impl<'a> PuritySettingsPermit<'a> {
    pub fn issue(
        archive: &'a dm_tree::frontend::BodyArchive,
        profile: PackedU128,
        identity: dm_ir::ProcedureIdentity,
    ) -> Result<Self, String> {Self::issue_using(archive,profile,identity,&crate::checker_prefix_demand::Compatibility::<String>::new())}
pub(crate) fn issue_using<D:PrefixDemand>(
        archive: &'a dm_tree::frontend::BodyArchive,
        profile: PackedU128,
        identity: dm_ir::ProcedureIdentity , demand:&D
) -> Result<Self , D::Error> {
        let tree = archive.tree();
        demand.validate_profile(tree,profile)
            .map_err(|e| format!("purity settings profile unavailable: {e:?}"))?;
        let (own_pure, own_no_sleep, own_sleep_exempt) = if demand.owns_directive_binding(){
            // The complete checker owns the same insertion policy, including
            // invalid/unknown/duplicate warnings. Only accepted flags affect
            // effects; their diagnostic rows remain in the actual BODY prelude.
            let accepted=crate::checks_directive_binding::accepted_own_using(archive,identity,demand)?;
            let own=|name:&str|->Result<Option<dm_syntax::Span>,D::Error>{
                let index=crate::checks_unknown_linter_setting::KNOWN.iter().position(|known|*known==name).ok_or("actual effect directive index absent")?;
                let Some(value)=accepted[index].filter(|value|value.enabled)else{return Ok(None)};
                let end=value.at.start.checked_add(3).ok_or("purity accepted set span overflow")?;if end>value.at.end{return Err("purity accepted set token absent".into())}Ok(Some(dm_syntax::Span::new(value.at.start,end)))
            };
            (own("SpacemanDMM_should_be_pure")?,own("SpacemanDMM_should_not_sleep")?,own("SpacemanDMM_allowed_to_sleep")?)
        }else{demand.prefix(archive,identity, |prefix| -> Result<_, String> {
                let mut pure = None;
                let mut no_sleep = None;
                let mut exempt = None;
                for statement in prefix.settings() {
                    let setting = statement.setting().expect("issued initial setting prefix");
                    let attribute = setting.attribute;
                    let value = setting.value.original();
                    if !attribute.starts_with("SpacemanDMM_")
                        || attribute == "SpacemanDMM_return_type"
                    {
                        continue;
                    }
                    if !matches!(
                        attribute,
                        "SpacemanDMM_should_be_pure"
                            | "SpacemanDMM_should_not_sleep"
                            | "SpacemanDMM_allowed_to_sleep"
                    ) {
                        return Err(
                            "effect mode has no exact policy for this source directive".into()
                        );
                    }
                    let entry = match attribute {
                        "SpacemanDMM_should_be_pure" => &mut pure,
                        "SpacemanDMM_should_not_sleep" => &mut no_sleep,
                        _ => &mut exempt,
                    };
                    if entry.is_some() {
                        return Err(
                            "duplicate effect directive needs the pinned warning contribution"
                                .into(),
                        );
                    }
                    // Pinned directive_value_to_truthy accepts a SINGLE Int1 or
                    // TRUE term. False cannot disable this directive; invalid and
                    // grouped/nonliteral forms need their separate warning policy.
                    let enabled = matches!(&value.kind,dm_syntax::ExprKind::Literal(s) if match s.original_value(){Some(value)=>matches!(value,dm_syntax::OriginalTokenValue::Int(1)),None=>s=="1"})
                        || matches!(&value.kind,dm_syntax::ExprKind::Ident(s) if s=="TRUE");
                    if !enabled {
                        return Err(
                            "purity prefix value is disabled or lacks admitted exact literal truth"
                                .into(),
                        );
                    }
                    let end = statement
                        .header_span
                        .start
                        .checked_add(3)
                        .ok_or("purity set span overflow")?;
                    if end > statement.header_span.end {
                        return Err("purity set token span unavailable".into());
                    }
                    *entry = Some(dm_syntax::Span {
                        start: statement.header_span.start,
                        end,
                    });
                }
                Ok((pure, no_sleep, exempt))
            })??};
        if own_pure.is_some() || own_no_sleep.is_some() || own_sleep_exempt.is_some() {
            // Pinned set_at_definition=true: a formal declaration, when present,
            // must name this exact implementation occurrence. An inherited or
            // later override may not quietly acquire its own annotation.
            let chain = Resolver::resolve(
                tree,
                Q::SourceDeclarationChain {
                    owner: identity.owner,
                    name: identity.name,
                    verb: identity.verb,
                },
            );
            let M::Members(rows) = chain else {
                return Err("purity initial declaration chain unavailable".into());
            };
            for row in rows.iter() {
                let M::Declaration {
                    identity: decl,
                    definition,
                    ..
                } = row
                else {
                    return Err("purity declaration chain malformed".into());
                };
                if *definition == ProcedureDefinition::Declare {
                    if *decl != identity {
                        return Err(
                            "purity annotation outside initial formal definition is not admitted"
                                .into(),
                        );
                    }
                    break;
                }
            }
        }
        let permit = Self {
            archive,
            profile,
            identity,
            own_pure,
            own_no_sleep,
            own_sleep_exempt,
            validated_profile:demand.profile().map(|proof|proof.reborrow(tree,profile)).transpose().map_err(|e|format!("purity settings profile unavailable: {e:?}"))?,
        };
        // Ordinary effects and selected wrappers retain their exact static
        // return-prefix guard. Only the authenticated complete Original BODY
        // owns return-expression compile diagnostics and the dynamic binding
        // consumer, so it must not be rejected by that narrower old guard.
        if !demand.owns_return_expression_binding(){prefix_return_override_mode_using(tree,Some(archive),identity,Some(&permit),demand)?;}
        Ok(permit)
    }
    pub fn own_pure(&self) -> Option<dm_syntax::Span> {
        self.own_pure
    }
    pub fn own_no_sleep(&self) -> Option<dm_syntax::Span> {
        self.own_no_sleep
    }
    pub fn own_sleep_exempt(&self) -> Option<dm_syntax::Span> {
        self.own_sleep_exempt
    }
    pub fn identity(&self) -> dm_ir::ProcedureIdentity {
        self.identity
    }
    fn require(
        &self,
        tree: &SemanticTree,
        archive: Option<&dm_tree::frontend::BodyArchive>,
        profile: PackedU128,
        identity: dm_ir::ProcedureIdentity,
    ) -> Result<(), String> {
        if !std::ptr::eq(tree, self.archive.tree())
            || archive.is_none_or(|a| !std::ptr::eq(a, self.archive))
            || self.profile != profile
            || self.identity != identity
        {
            return Err(
                "purity setting permit belongs to another archive/profile/callable issuance".into(),
            );
        }
        match self.validated_profile{Some(proof)=>proof.require(tree,profile),None=>tree.validate_checker_builtin_profile(profile)}
            .map_err(|e| format!("purity setting profile changed: {e:?}"))?;
        Ok(())
    }
}

fn require_prefix<'a>(
    tree: &SemanticTree,
    archive: Option<&'a dm_tree::frontend::BodyArchive>,
) -> Result<&'a dm_tree::frontend::BodyArchive, String> {
    let archive=archive.ok_or("source settings require a primary contiguous-prefix proof from the original retained BodySyntax owner")?;
    if !std::ptr::eq(tree, archive.tree()) {
        return Err("setting prefix archive belongs to another compiled source owner".into());
    }
    Ok(archive)
}
pub fn validate_source_directives(
    tree: &SemanticTree,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    identity: dm_ir::ProcedureIdentity,
) -> Result<(), String> {
    validate_source_directives_mode(tree, archive, identity, None)
}
pub fn validate_source_directives_for_purity(
    tree: &SemanticTree,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    identity: dm_ir::ProcedureIdentity,
    permit: &PuritySettingsPermit<'_>,
) -> Result<(), String> {
    permit.require(tree, archive, permit.profile, identity)?;
    validate_source_directives_mode(tree, archive, identity, Some(permit))
}
fn validate_source_directives_mode(
    tree: &SemanticTree,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    identity: dm_ir::ProcedureIdentity,
    permit: Option<&PuritySettingsPermit<'_>>,
) -> Result<(), String> {
    validate_source_directives_mode_using(tree,archive,identity,permit, &crate::checker_prefix_demand::Compatibility::<String>::new())
}
fn validate_source_directives_mode_using<D:PrefixDemand>(
    tree: &SemanticTree,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    identity: dm_ir::ProcedureIdentity,
    permit: Option<&PuritySettingsPermit<'_>> , demand:&D
) -> Result<() , D::Error> {
    demand.prefix(require_prefix(tree, archive)?,
        identity,
        |prefix| -> Result<(), String> {
            for statement in prefix.settings() {
                let setting = statement.setting().expect("issued initial setting prefix");
                let attribute = setting.attribute;
                if attribute.starts_with("SpacemanDMM_")
                    && attribute != "SpacemanDMM_return_type"
                    && !demand.owns_directive_binding()
                    && !(matches!(
                        attribute,
                        "SpacemanDMM_should_be_pure"
                            | "SpacemanDMM_should_not_sleep"
                            | "SpacemanDMM_allowed_to_sleep"
                    ) && permit.is_some())
                {
                    return Err(
                        "source directive prefix is issued but its exact policy is not implemented"
                            .into(),
                    );
                }
            }
            Ok(())
        },
    )?.map_err(D::Error::from)
}
fn prefix_return_override_mode(
    tree: &SemanticTree,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    identity: dm_ir::ProcedureIdentity,
    permit: Option<&PuritySettingsPermit<'_>>,
) -> Result<Option<ReturnHint>, String> {
    prefix_return_override_mode_using(tree,archive,identity,permit, &crate::checker_prefix_demand::Compatibility::<String>::new())
}
fn prefix_return_override_mode_using<D:PrefixDemand>(
    tree: &SemanticTree,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    identity: dm_ir::ProcedureIdentity,
    permit: Option<&PuritySettingsPermit<'_>> , demand:&D
) -> Result<Option<ReturnHint> , D::Error> {
    if let Some(permit) = permit {
        permit.require(tree, archive, permit.profile, identity)?;
    }
    let archive = require_prefix(tree, archive)?;
    demand.prefix(archive,
        identity,
        |prefix| -> Result<Option<ReturnHint>, String> {
            let mut result = None;
            for statement in prefix.settings() {
                let setting = statement.setting().expect("issued initial setting prefix");
                let attribute = setting.attribute;
                let value = setting.value.original();
                if attribute.starts_with("SpacemanDMM_")
                    && attribute != "SpacemanDMM_return_type"
                    && !demand.owns_directive_binding()
                    && !(matches!(
                        attribute,
                        "SpacemanDMM_should_be_pure"
                            | "SpacemanDMM_should_not_sleep"
                            | "SpacemanDMM_allowed_to_sleep"
                    ) && permit.is_some())
                {
                    return Err(
                        "source directive prefix requires an unimplemented exact policy".into(),
                    );
                }
                if attribute != "SpacemanDMM_return_type" {
                    continue;
                }
                let mut value = value;
                while let dm_syntax::ExprKind::Group(inner) = &value.kind {
                    value = inner;
                }
                result = Some(match &value.kind {
                    dm_syntax::ExprKind::TypePath(path) if path.starts_with('/') => {
                        let projected = dm_syntax::project_declaration_type(path);
                        ReturnHint {
                            declared_type: Some(SymbolId::of(projected.runtime_path)),
                            list_element_type: projected
                                .list_element_path
                                .map(|p| SymbolId::of(&format!("/{p}"))),
                        }
                    }
                    dm_syntax::ExprKind::Ident(name) if name == "null" => ReturnHint::none(),
                    dm_syntax::ExprKind::Literal(text) if text.original_value().is_none() && text == "null" => ReturnHint::none(),
                    _ => {
                        return Err(
                            "return prefix TypeExpr requires shared argument value/type facts"
                                .into(),
                        )
                    }
                });
            }
            Ok(result)
        },
    )?.map_err(D::Error::from)
}

/// Pinned fix-hint provenance, not a second inference/model. Absolute body
/// source positions are retained only in the evaluated-expression fact.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ReturnFixHint {
    UnannotatedSource(dm_ir::ProcedureIdentity),
    EvaluatedNone,
    None,
    UnissuedBuiltin,
}
pub fn return_fix_hint(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive>,
) -> Result<ReturnFixHint, String> {
    return_fix_hint_mode(tree, resolver, profile, receiver, name, archive, None)
}
pub fn return_fix_hint_for_purity(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    permit: &PuritySettingsPermit<'_>,
) -> Result<ReturnFixHint, String> {
    permit.require(tree, archive, profile, permit.identity)?;
    return_fix_hint_mode(
        tree,
        resolver,
        profile,
        receiver,
        name,
        archive,
        Some(permit),
    )
}
fn return_fix_hint_mode(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    permit: Option<&PuritySettingsPermit<'_>>,
) -> Result<ReturnFixHint, String> {
    return_fix_hint_mode_using(tree,resolver,profile,receiver,name,archive,permit, &crate::checker_prefix_demand::Compatibility::<String>::new())
}
fn return_fix_hint_mode_using<D:PrefixDemand>(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    permit: Option<&PuritySettingsPermit<'_>> , demand:&D
) -> Result<ReturnFixHint , D::Error> {
    let hint = return_hint_mode_using(tree, resolver, profile, receiver, name, archive, permit, demand)?;
    if hint.declared_type.is_some() {
        return Ok(ReturnFixHint::None);
    }
    match checker_call_facts::callable_any_using(tree,resolver,profile,receiver,name,&mut||demand.checkpoint())? {
        CallableFact::Source { identity, metadata } => {
            if !metadata
                .procedure
                .as_ref()
                .ok_or("return hint source signature unavailable")?
                .settings
                .is_empty()
                && prefix_return_override_mode_using(tree, archive, identity, permit, demand)?.is_some()
            {
                return Ok(ReturnFixHint::EvaluatedNone);
            }
            // With an admitted absolute header hint the declared_type is Some;
            // arbitrary scalar/union headers already declined above. Therefore
            // None here is the genuine old unannotated source-return branch.
            Ok(ReturnFixHint::UnannotatedSource(identity))
        }
        CallableFact::CheckerBuiltin {
            declaring_owner, ..
        } if declaring_owner == SymbolId::of("/") => Ok(ReturnFixHint::None),
        // Keep the previously supported plain call. A later field follow must
        // still decline until builtin-location hint provenance is issued.
        CallableFact::CheckerBuiltin { .. } => Ok(ReturnFixHint::UnissuedBuiltin),
        CallableFact::Missing => Err("return fix-hint callable is missing".into()),
    }
}

#[cfg(test)]
#[path = "checker_purity_settings_tests.rs"]
mod purity_settings_tests;


pub(crate) fn return_hint_with_prefix_using<D:PrefixDemand>(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive> , demand:&D
) -> Result<ReturnHint , D::Error> {
    return_hint_mode_using(tree, resolver, profile, receiver, name, archive, None, demand)
}

pub(crate) fn return_hint_with_prefix_for_purity_using<D:PrefixDemand>(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    permit: &PuritySettingsPermit<'_> , demand:&D
) -> Result<ReturnHint , D::Error> {
    permit.require(tree, archive, profile, permit.identity)?;
    return_hint_mode_using(
        tree,
        resolver,
        profile,
        receiver,
        name,
        archive,
        Some(permit), demand)
}

pub(crate) fn validate_source_directives_using<D:PrefixDemand>(
    tree: &SemanticTree,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    identity: dm_ir::ProcedureIdentity , demand:&D
) -> Result<() , D::Error> {
    validate_source_directives_mode_using(tree, archive, identity, None, demand)
}

pub(crate) fn validate_source_directives_for_purity_using<D:PrefixDemand>(
    tree: &SemanticTree,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    identity: dm_ir::ProcedureIdentity,
    permit: &PuritySettingsPermit<'_> , demand:&D
) -> Result<() , D::Error> {
    permit.require(tree, archive, permit.profile, identity)?;
    validate_source_directives_mode_using(tree, archive, identity, Some(permit), demand)
}

pub(crate) fn return_fix_hint_using<D:PrefixDemand>(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive> , demand:&D
) -> Result<ReturnFixHint , D::Error> {
    return_fix_hint_mode_using(tree, resolver, profile, receiver, name, archive, None, demand)
}

pub(crate) fn return_fix_hint_for_purity_using<D:PrefixDemand>(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    receiver: SymbolId,
    name: SymbolId,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    permit: &PuritySettingsPermit<'_> , demand:&D
) -> Result<ReturnFixHint , D::Error> {
    permit.require(tree, archive, profile, permit.identity)?;
    return_fix_hint_mode_using(
        tree,
        resolver,
        profile,
        receiver,
        name,
        archive,
        Some(permit), demand)
}
