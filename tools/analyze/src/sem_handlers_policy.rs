//! Unique original declared-handler judgement. No source/model/parser/cache.
//! Producer supplies actual ordered facts; complete-policy admission remains separate.
use crate::{key_policy_control as kc,reactive_hooks_policy::HandlerRef};
use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::tree::CODE_DM;
const H_UNRESOLVED: &str = "name a proc the type declares, or fix the declaration";
const H_SIG: &str = "every handler is x(datum/act/A): one parameter of a datum/act type, A.holder always set";
const H_FIELD: &str = "read only the fields the context type carries (doc/rewrite/final_api.html section 8): use a requirement for A.actor, an output for A.dt";
const H_IMPURE: &str = "requirements, conditions, outputs and contributions are pure: move the write into an effect (then()) or a setter called from one";
const H_RETURN: &str = "req callbacks return null to allow or text/a refusal datum to refuse; conditions and transitional req_bool callbacks return TRUE/FALSE";
const H_PAIR: &str = "act_done(F) or act_cancel(F) on every path after ACT_ATTEMPT (a branch that tests ACT_REFUSED_BY(F), null or ACT_PASS needs neither)";
const H_ESCAPE: &str = "a context is pooled and lives for one trigger: use A.snapshot() for anything that must outlive it";
const H_OUTPUT: &str = "an override takes the base's parameters exactly, or it is a silent no-op";

static META: Meta = Meta {
    name: crate::allow_registry_fields::sem_handlers::SCOPE_META_0.name,
    group: crate::allow_registry_fields::sem_handlers::SCOPE_META_0.group,
    label: "handlers",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "handler_unresolved", hint: H_UNRESOLVED },
        RuleMeta { name: "signature", hint: H_SIG },
        RuleMeta { name: "context_field", hint: H_FIELD },
        RuleMeta { name: "impure", hint: H_IMPURE },
        RuleMeta { name: "requirement_return", hint: H_RETURN },
        RuleMeta { name: "act_try_unpaired", hint: H_PAIR },
        RuleMeta { name: "context_escape", hint: H_ESCAPE },
        RuleMeta { name: "output_signature", hint: H_OUTPUT },
    ],
    allow: crate::allow_registry_fields::sem_handlers::ALLOW_0,
    lists: crate::allow_registry_fields::sem_handlers::SCOPE_META_0.lists,
};

/// Standard outputs: base procs the engine calls by name.
const STD_OUTPUTS: &[&str] = &["draw", "ui_data", "push_to_rust", "examine"];


pub fn metadata()->&'static Meta{&META}
pub const STANDARD_OUTPUTS:&[&str]=STD_OUTPUTS;
pub trait ReturnFinding{fn rule(&self)->&'static str;fn line(&self)->u32;fn message(&self)->&str;}
#[derive(Debug,PartialEq,Eq)]pub struct Found{pub rule:&'static str,pub line:u32,pub msg:String}
impl ReturnFinding for Found{fn rule(&self)->&'static str{self.rule}fn line(&self)->u32{self.line}fn message(&self)->&str{&self.msg}}
#[cfg(feature="legacy-sem")]impl ReturnFinding for crate::sem::checks::Found{fn rule(&self)->&'static str{self.rule}fn line(&self)->u32{self.line}fn message(&self)->&str{&self.msg}}
pub struct Declared<'a,R>{pub hook:&'a HandlerRef,pub on:&'a str,pub proc_found:bool,pub type_found:bool,pub definition:Option<(&'a str,u32)>,pub parameters:&'a[Vec<String>],pub bad_context:&'a[(String,String,u32)],pub impure:&'a[(String,String,u32)],pub returns:&'a[R]}
pub fn declared_using<C:kc::Control,R:ReturnFinding>(a:Declared<'_,R>,c:&mut C,emit:&mut impl FnMut(&mut C,&'static str,&str,u32,String)->Result<(),C::Error>)->Result<(),C::Error>{
 c.checkpoint()?;let h=a.hook;let who=kc::format(c,format_args!("{}::{} ({}())",a.on,h.proc,h.form))?;
 if !a.proc_found{let why=if a.type_found{kc::format(c,format_args!("{} has no proc `{}`",a.on,h.proc))?}else{kc::format(c,format_args!("type {} does not exist",a.on))?};let message=kc::format(c,format_args!("{} names a handler that does not resolve: {}",h.form,why))?;emit(c,"handler_unresolved",&h.rel,h.line,message)?;return c.checkpoint()}
 let(drel,dline)=a.definition.unwrap_or((&h.rel,h.line));let expected=1+h.ui_args.as_ref().map_or(0,Vec::len);let is_act=|p:&Vec<String>|p.len()>=2&&p[0]=="datum"&&p[1]=="act";
 if a.parameters.len()!=expected||a.parameters.is_empty()||!is_act(&a.parameters[0]){let message=kc::format(c,format_args!("{} takes {} parameter(s); a handler is x(datum/act/A){}",who,a.parameters.len(),if expected>1{" plus one parameter per declared arg()"}else{""}))?;emit(c,"signature",drel,dline,message)?;}
 for(field,rel,line)in a.bad_context{c.checkpoint()?;let message=kc::format(c,format_args!("{} reads A.{}, which a {} context does not carry",who,field,h.ctx.type_path()))?;emit(c,"context_field",rel,*line,message)?;}
 for(what,rel,line)in a.impure{c.checkpoint()?;let message=kc::format(c,format_args!("{} is pure ({}) but {}",who,h.form,what))?;emit(c,"impure",rel,*line,message)?;}
 for f in a.returns{c.checkpoint()?;let message=kc::format(c,format_args!("{}: {}",who,f.message()))?;emit(c,f.rule(),drel,f.line(),message)?;}
 c.checkpoint()
}
/// Exact old definite-return classification; this is not runtime truth/evaluation.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]pub enum ReturnTerm{Int(i32),Float,Text,Null,List,RefusalPath,OtherPath,Other}
#[derive(Clone,Copy)]pub struct BaseReturn{pub not:bool,pub term:ReturnTerm}
pub trait ReturnExpression<E>:Sized{
 fn group(&self)->Option<&Self>;
 fn base<C:kc::Control<Error=E>>(&self,c:&mut C)->Result<Option<BaseReturn>,E>;
 fn comparison(&self)->bool;
 fn arms(&self)->Option<(&Self,&Self)>;
}
#[derive(Clone,Copy)]pub enum ReturnProtocol{Boolean,Requirement}
pub fn invalid_return_using<C:kc::Control,N:ReturnExpression<C::Error>>(mut n:&N,protocol:ReturnProtocol,c:&mut C)->Result<Option<&'static str>,C::Error>{
 c.checkpoint()?;while let Some(inner)=n.group(){c.checkpoint()?;n=inner;}
 if let Some(base)=n.base(c)?{return Ok(match protocol{
  ReturnProtocol::Boolean if base.not=>None,ReturnProtocol::Requirement if base.not=>Some("a boolean"),
  ReturnProtocol::Boolean=>match base.term{ReturnTerm::Text=>Some("text"),ReturnTerm::Null=>Some("null"),ReturnTerm::RefusalPath|ReturnTerm::OtherPath=>Some("a type path"),ReturnTerm::List=>Some("a list"),ReturnTerm::Int(i)if i!=0&&i!=1=>Some("a number other than TRUE/FALSE"),ReturnTerm::Float=>Some("a number other than TRUE/FALSE"),_=>None},
  ReturnProtocol::Requirement=>match base.term{ReturnTerm::Int(_)|ReturnTerm::Float=>Some("a number/boolean"),ReturnTerm::List=>Some("a list"),ReturnTerm::OtherPath=>Some("a non-refusal type path"),_=>None},
 });}
 if matches!(protocol,ReturnProtocol::Requirement)&&n.comparison(){return Ok(Some("a boolean comparison"))}
 if let Some((left,right))=n.arms(){if let Some(why)=invalid_return_using(left,protocol,c)?{return Ok(Some(why))}return invalid_return_using(right,protocol,c)}Ok(None)
}
pub fn return_message_using<C:kc::Control,N:ReturnExpression<C::Error>>(value:Option<&N>,protocol:ReturnProtocol,c:&mut C)->Result<Option<String>,C::Error>{
 c.checkpoint()?;let Some(value)=value else{return match protocol{ReturnProtocol::Boolean=>Ok(Some(kc::own(c,"a bare `return` answers null; a condition or req_bool callback must answer TRUE or FALSE")?)),ReturnProtocol::Requirement=>Ok(None)}};
 let Some(why)=invalid_return_using(value,protocol,c)?else{return Ok(None)};Ok(Some(match protocol{ReturnProtocol::Boolean=>kc::format(c,format_args!("returns {}: a condition or req_bool callback answers TRUE or FALSE",why))?,ReturnProtocol::Requirement=>kc::format(c,format_args!("returns {}: req callbacks return null to allow, or text/a refusal datum to refuse; use req_bool only for transitional boolean callbacks",why))?}))
}
#[cfg(feature="legacy-sem")]impl ReturnExpression<std::convert::Infallible> for dreammaker::ast::Expression{
 fn group(&self)->Option<&Self>{use dreammaker::ast::{Expression as E,Term};match self{E::Base{term,follow}if follow.is_empty()=>match &term.elem{Term::Expr(inner)=>Some(inner),_=>None},_=>None}}
 fn base<C:kc::Control<Error=std::convert::Infallible>>(&self,c:&mut C)->Result<Option<BaseReturn>,std::convert::Infallible>{use dreammaker::ast::{Expression as E,Term,Follow,UnaryOp};let E::Base{term,follow}=self else{return Ok(None)};let mut not=false;for f in follow{c.checkpoint()?;not|=matches!(f.elem,Follow::Unary(UnaryOp::Not));}let term=match &term.elem{Term::Int(i)=>ReturnTerm::Int(*i),Term::Float(_)=>ReturnTerm::Float,Term::String(_)|Term::InterpString(..)=>ReturnTerm::Text,Term::Null=>ReturnTerm::Null,Term::List(_)=>ReturnTerm::List,Term::Prefab(prefab)=>{let mut path=prefab.path.iter().map(|(_,name)|name.as_str());if path.next()==Some("datum")&&path.next()==Some("msg"){ReturnTerm::RefusalPath}else{ReturnTerm::OtherPath}},_=>ReturnTerm::Other};Ok(Some(BaseReturn{not,term}))}
 fn comparison(&self)->bool{matches!(self,dreammaker::ast::Expression::BinaryOp{op:dreammaker::ast::BinaryOp::Eq|dreammaker::ast::BinaryOp::NotEq,..})}
 fn arms(&self)->Option<(&Self,&Self)>{match self{dreammaker::ast::Expression::TernaryOp{if_,else_,..}=>Some((if_,else_)),_=>None}}
}

#[cfg(test)]mod final_control_tests{
 use super::*;use std::{cell::Cell,io};
 struct Work<'a>(&'a Cell<bool>);impl kc::Control for Work<'_>{type Error=io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->io::Result<()>{if self.0.get(){Err(io::ErrorKind::Interrupted.into())}else{Ok(())}}fn reserve(&mut self,_:usize)->io::Result<()>{self.checkpoint()}fn overflow(&mut self)->io::Error{io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->io::Error{self.overflow()}}
 #[test]fn unresolved_handler_completion_rechecks_actual_control_and_preserves_first_callback_io(){
  let args=vec!["/obj/probe".to_owned(),"when(PROC_REF(handler))".to_owned()];let marker=crate::declare_policy::Marker{name:"CAPABILITIES",rel:"code/probe.dm",line:3,body:"/obj/probe,when(PROC_REF(handler))",args:&args,body_offset:0,line_starts:&[0]};let mut refs=crate::reactive_hooks_policy::discover(&[marker]);assert_eq!(refs.len(),1);let hook=refs.pop().unwrap();let late=Cell::new(false);
  for actual_io in [false,true]{late.set(false);let result=declared_using(Declared::<Found>{hook:&hook,on:"/obj/probe",proc_found:false,type_found:true,definition:None,parameters:&[],bad_context:&[],impure:&[],returns:&[]},&mut Work(&late),&mut|_,rule,_,_,_|{assert_eq!(rule,"handler_unresolved");late.set(true);if actual_io{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}});let error=result.unwrap_err();if actual_io{assert_eq!(error.raw_os_error(),Some(1450))}else{assert_eq!(error.kind(),io::ErrorKind::Interrupted)}}
  late.set(false);declared_using(Declared::<Found>{hook:&hook,on:"/obj/probe",proc_found:false,type_found:true,definition:None,parameters:&[],bad_context:&[],impure:&[],returns:&[]},&mut Work(&late),&mut|_,_,_,_,_|Ok(())).unwrap();
 }
}
