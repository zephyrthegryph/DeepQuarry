//! Static return hints from native source declarations and exact checker SDK
//! provenance, not executable-body inference or builtin-name availability.
//! Policy: SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc,
//! dreamchecker/lib.rs SHA256 dd17edc32409c5f9a8c2ca31b55386b6bcfdd309d9c0455627c667b0d9f45fdd (GPL-3.0).
use crate::checker_call_facts::{self,CallableFact};
use dm_ir::{PackedU128,ProcedureDefinition,ResolveQuery as Q,ResolvedMeaning as M,Resolver,SymbolId};
use dm_tree::SemanticTree;
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub struct ReturnHint {pub declared_type:Option<SymbolId>,pub list_element_type:Option<SymbolId>}
impl ReturnHint {
    fn none()->Self {Self{declared_type:None,list_element_type:None}}
    fn direct(path:&str)->Self {Self{declared_type:Some(SymbolId::of(path)),list_element_type:None}}
    fn list(element:Option<&str>)->Self {Self{declared_type:Some(SymbolId::of("/list")),list_element_type:element.map(SymbolId::of)}}
}
pub fn return_hint(tree:&SemanticTree,resolver:&(impl Resolver+?Sized),profile:PackedU128,
                   receiver:SymbolId,name:SymbolId)->Result<ReturnHint,String> {
    return_hint_with_prefix(tree,resolver,profile,receiver,name,None)
}
pub fn return_hint_with_prefix(tree:&SemanticTree,resolver:&(impl Resolver+?Sized),profile:PackedU128,
                   receiver:SymbolId,name:SymbolId,archive:Option<&dm_tree::frontend::BodyArchive>)->Result<ReturnHint,String> {
    if resolver.source_owner()!=Resolver::source_owner(tree) {return Err("return context lacks original compiled owner provenance".into());}
    tree.validate_checker_builtin_profile(profile).map_err(|e|format!("return checker profile unavailable: {e:?}"))?;
    let fact=checker_call_facts::callable_any(tree,resolver,profile,receiver,name)?;
    match fact {
        CallableFact::Missing=>Err("return hint requires a positively resolved callable".into()),
        CallableFact::CheckerBuiltin{declaring_owner,..}=>{
            // Gate every name by genuine hash-qualified declaration provenance;
            // this table never proves callable presence or runtime ABI metadata.
            if declaring_owner!=SymbolId::of("/") {return Ok(ReturnHint::none());}
            Ok(match name {
                x if ["block"].iter().any(|s|x==SymbolId::of(s))=>ReturnHint::list(Some("/turf")),
                x if ["bounds","obounds","orange","oview","range","view"].iter().any(|s|x==SymbolId::of(s))=>ReturnHint::list(Some("/atom")),
                x if ["hearers","ohearers","oviewers","viewers"].iter().any(|s|x==SymbolId::of(s))=>ReturnHint::list(Some("/mob")),
                // Preserve pinned unreachable "argslist" spelling. The fixed
                // SDK declares arglist, not argslist, so real resolver facts
                // cannot admit this branch for an invented builtin.
                x if ["argslist","flist","icon_states","splittext","typesof"].iter().any(|s|x==SymbolId::of(s))=>ReturnHint::list(None),
                x if x==SymbolId::of("get_step")=>ReturnHint::direct("/turf"),
                x if x==SymbolId::of("icon")=>ReturnHint::direct("/icon"),
                x if x==SymbolId::of("matrix")=>ReturnHint::direct("/matrix"),
                x if x==SymbolId::of("regex")=>ReturnHint::direct("/regex"),
                _=>ReturnHint::none(),
            })
        }
        CallableFact::Source{identity,metadata}=>{
            if identity.owner==SymbolId::of("/") && identity.name==SymbolId::of("astype") {
                return Err("pinned astype needs shared argument typepath/value facts".into());
            }
            let prefix = if metadata.procedure.as_ref().ok_or("source signature absent")?.settings.is_empty() {None} else {
                validate_source_directives(tree,archive,identity)?;
                prefix_return_override(tree,archive,identity)?
            };
            let query=Q::SourceDeclarationChain{owner:identity.owner,name:identity.name,verb:identity.verb};
            let answer=resolver.resolve(query);
            if answer!=Resolver::resolve(tree,query) {return Err("return header host differs from source declaration chain".into());}
            let M::Members(rows)=answer else{return Err("return header source chain unavailable".into());};
            let mut annotation=None;let mut formal_seen=false;
            for row in rows.iter() {
                let M::Declaration{definition,data,..}=row else{return Err("return header malformed source chain".into());};
                if *definition==ProcedureDefinition::Declare {
                    formal_seen=true;
                    annotation=data.procedure.as_ref().ok_or("formal signature absent")?.signature.return_annotation.as_ref();
                    break;
                }
            }
            if !formal_seen && metadata.procedure.as_ref().unwrap().signature.return_annotation.is_some() {
                return Err("implicit callable return annotation lacks native formal-selection proof".into());
            }
            if let Some(annotation)=annotation {
                let path=annotation.absolute_type_path(tree.symbols()).ok_or("source return annotation requires native input-union/type-expression facts")?;
                let projected=dm_syntax::project_declaration_type(&path);
                let header=ReturnHint {declared_type:Some(SymbolId::of(projected.runtime_path)),
                    list_element_type:projected.list_element_path.map(|p|SymbolId::of(&format!("/{p}")))};
                return Ok(prefix.unwrap_or(header));
            }
            if let Some(prefix)=prefix {return Ok(prefix);}
            if identity.owner==SymbolId::of("/") && identity.name==SymbolId::of("get_step") {
                return Err("source override of pinned get_step seed requires exact settings-stage selection proof".into());
            }
            Ok(ReturnHint::none())
        }
    }
}

#[cfg(test)]
#[path="checker_return_facts_tests.rs"]
mod tests;

fn require_prefix<'a>(tree:&SemanticTree, archive:Option<&'a dm_tree::frontend::BodyArchive>)->Result<&'a dm_tree::frontend::BodyArchive,String> {
    let archive=archive.ok_or("source settings require a primary contiguous-prefix proof from the original retained BodySyntax owner")?;
    if !std::ptr::eq(tree,archive.tree()) {return Err("setting prefix archive belongs to another compiled source owner".into());}
    Ok(archive)
}
pub fn validate_source_directives(tree:&SemanticTree,archive:Option<&dm_tree::frontend::BodyArchive>,identity:dm_ir::ProcedureIdentity)->Result<(),String> {
    require_prefix(tree,archive)?.with_initial_setting_prefix(identity,|prefix|->Result<(),String>{
        for statement in prefix.settings() {
            let dm_syntax::StatementKind::Set{attribute,..}=&statement.kind else{unreachable!();};
            if attribute.starts_with("SpacemanDMM_") && attribute!="SpacemanDMM_return_type" {
                return Err("source directive prefix is issued but its exact policy is not implemented".into());
            }
        }Ok(())
    })?
}
fn prefix_return_override(tree:&SemanticTree,archive:Option<&dm_tree::frontend::BodyArchive>,identity:dm_ir::ProcedureIdentity)->Result<Option<ReturnHint>,String> {
    let archive=require_prefix(tree,archive)?;
    archive.with_initial_setting_prefix(identity,|prefix|->Result<Option<ReturnHint>,String>{
        let mut result=None;
        for statement in prefix.settings() {
            let dm_syntax::StatementKind::Set{attribute,value,..}=&statement.kind else{unreachable!();};
            if attribute.starts_with("SpacemanDMM_") && attribute!="SpacemanDMM_return_type" {
                return Err("source directive prefix requires an unimplemented exact policy".into());
            }
            if attribute!="SpacemanDMM_return_type" {continue;}
            let mut value=value;
            while let dm_syntax::ExprKind::Group(inner)=&value.kind {value=inner;}
            result=Some(match &value.kind {
                dm_syntax::ExprKind::TypePath(path) if path.starts_with('/')=>{
                    let projected=dm_syntax::project_declaration_type(path);
                    ReturnHint {declared_type:Some(SymbolId::of(projected.runtime_path)),
                        list_element_type:projected.list_element_path.map(|p|SymbolId::of(&format!("/{p}")))}
                }
                dm_syntax::ExprKind::Ident(name) if name=="null"=>ReturnHint::none(),
                dm_syntax::ExprKind::Literal(text) if text=="null"=>ReturnHint::none(),
                _=>return Err("return prefix TypeExpr requires shared argument value/type facts".into()),
            });
        }Ok(result)
    })?
}
