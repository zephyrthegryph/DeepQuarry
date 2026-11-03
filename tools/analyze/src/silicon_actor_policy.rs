//! Unique silicon actor judgment over borrowed producer data.
//! No parser, source/model authority, body cache or alternative AST lives here.
use std::collections::BTreeSet;
use crate::key_policy_control::{self as kc,Control};
/// How deep a helper chain is followed from a handler.
pub const MAX_DEPTH: usize = 8;

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct ActorTest {
    pub rule: &'static str,
    pub rel: String,
    pub line: u32,
    /// The handler the test is reached from (`/type/proc/name`).
    pub handler: String,
    /// The tested type.
    pub tested: String,
}


pub fn is_act_parts<'a>(path:impl IntoIterator<Item=&'a str>)->bool{let mut path=path.into_iter();path.next()==Some("datum")&&path.next()==Some("act")}
#[derive(Clone,Copy)]pub enum HandlerParameter{Other,Act,Timer}
pub fn handler_parameter(first:Option<&str>,second:Option<&str>,third:Option<&str>)->HandlerParameter{if first==Some("datum")&&second==Some("act"){if third==Some("timer"){HandlerParameter::Timer}else{HandlerParameter::Act}}else{HandlerParameter::Other}}
pub fn is_handler_kinds(owner:&str,name:&str,parameters:impl IntoIterator<Item=HandlerParameter>)->bool{let mut any=false;for parameter in parameters{match parameter{HandlerParameter::Timer=>return false,HandlerParameter::Act=>any=true,HandlerParameter::Other=>()}}any&&!(name=="prepare"&&owner.starts_with("/datum/prompt/"))}
pub fn is_handler_paths<'a,I,P>(owner:&str,name:&str,parameters:I)->bool where I:IntoIterator<Item=P>,P:IntoIterator<Item=&'a str>{is_handler_kinds(owner,name,parameters.into_iter().map(|path|{let mut path=path.into_iter();handler_parameter(path.next(),path.next(),path.next())}))}
pub fn silicon_type(path:&str)->bool{path=="/mob/living/silicon"||path.starts_with("/mob/living/silicon/")}
/// Only exact old actor shapes, not semantic equivalence or general alias analysis.
pub trait ActorExpression:Sized{
 fn group(&self)->Option<&Self>;
 fn bare_name(&self)->Option<&str>;
 fn actor_receiver(&self)->Option<&str>;
 fn actor_arms(&self)->Option<(&Self,&Self)>;
}
#[derive(Clone,Default,Debug)]pub struct Taint{pub(crate) acts:BTreeSet<String>,pub(crate) actors:BTreeSet<String>}
impl Taint{
 pub fn is_act<E:ActorExpression>(&self,mut expression:&E)->bool{while let Some(inner)=expression.group(){expression=inner;}expression.bare_name().is_some_and(|name|self.acts.contains(name))}
 pub fn is_actor<E:ActorExpression>(&self,mut expression:&E)->bool{while let Some(inner)=expression.group(){expression=inner;}if let Some(name)=expression.bare_name(){return self.actors.contains(name)}if let Some(name)=expression.actor_receiver(){return self.acts.contains(name)}if let Some((left,right))=expression.actor_arms(){return self.is_actor(left)||self.is_actor(right)}false}
 pub fn take_using<C:Control,E:ActorExpression>(&mut self,name:&str,value:&E,c:&mut C)->Result<(),C::Error>{
  c.checkpoint()?;let kind=if self.is_actor(value){1}else if self.is_act(value){2}else{0};let target=match kind{1=>&mut self.actors,2=>&mut self.acts,_=>return Ok(())};
  if !target.contains(name){kc::reserve(c,||name.len().checked_mul(4)?.checked_add(1024))?;target.insert(name.to_owned());}Ok(())
 }
 #[cfg(feature="legacy-sem")]pub(crate) fn take(&mut self,name:&str,value:&dreammaker::ast::Expression){self.take_using(name,value,&mut kc::Compatibility).unwrap();}
}
pub fn finalize_using<C:Control>(mut out:Vec<ActorTest>,c:&mut C)->Result<Vec<ActorTest>,C::Error>{
 kc::sort_data(&mut out,&mut|a,b|{c.checkpoint()?;Ok(a.cmp(b))})?;
 let mut direct=BTreeSet::new();for row in &out{c.checkpoint()?;if row.rule!="helper_actor_check"{kc::reserve(c,||row.rel.len().checked_mul(4)?.checked_add(1024))?;direct.insert((row.rel.clone(),row.line));}}
 let mut seen=BTreeSet::new();let mut kept=Vec::new();
 for row in out{c.checkpoint()?;if row.rule=="helper_actor_check"{kc::reserve(c,||row.rel.len().checked_mul(4)?.checked_add(128))?;if direct.contains(&(row.rel.clone(),row.line)){continue}}kc::reserve(c,||row.rel.len().checked_mul(4)?.checked_add(1024))?;if seen.insert((row.rule,row.rel.clone(),row.line)){kc::row(c,&mut kept)?;kept.push(row);}}
 c.checkpoint()?;Ok(kept)
}
pub fn describe_using<C:Control>(row:&ActorTest,c:&mut C)->Result<String,C::Error>{let what=if row.tested=="macro"{kc::own(c,"an isAI()/issilicon()/isrobot()/ispAI() test")?}else{kc::format(c,format_args!("istype(actor, {})",row.tested))?};if row.rule!="helper_actor_check"{kc::format(c,format_args!("{} in the op handler {}",what,row.handler))}else{kc::format(c,format_args!("{} on the actor the op handler {} passes in",what,row.handler))}}
#[cfg(feature="legacy-sem")]impl ActorExpression for dreammaker::ast::Expression{
 fn group(&self)->Option<&Self>{use dreammaker::ast::{Expression as E,Term};match self{E::Base{term,follow}if follow.is_empty()=>match &term.elem{Term::Expr(inner)=>Some(inner),_=>None},_=>None}}
 fn bare_name(&self)->Option<&str>{use dreammaker::ast::{Expression as E,Term};match self{E::Base{term,follow}if follow.is_empty()=>match &term.elem{Term::Ident(name)=>Some(name),_=>None},_=>None}}
 fn actor_receiver(&self)->Option<&str>{use dreammaker::ast::{Expression as E,Term,Follow};match self{E::Base{term,follow}if follow.len()==1=>match(&term.elem,&follow[0].elem){(Term::Ident(name),Follow::Field(_,field))if field.as_str()=="actor"=>Some(name),_=>None},_=>None}}
 fn actor_arms(&self)->Option<(&Self,&Self)>{if let dreammaker::ast::Expression::TernaryOp{if_,else_,..}=self{Some((if_,else_))}else{None}}
}

#[cfg(feature="native-policy")]impl ActorExpression for dm_syntax::Expr{
 fn group(&self)->Option<&Self>{if let dm_syntax::ExprKind::Group(inner)=&self.kind{Some(inner)}else{None}}
 fn bare_name(&self)->Option<&str>{if let dm_syntax::ExprKind::Ident(name)=&self.kind{Some(name)}else{None}}
 fn actor_receiver(&self)->Option<&str>{use dm_syntax::ExprKind as E;match &self.kind{E::Member{object,selector,..}|E::SafeMember{object,selector,..}if selector=="actor"=>match &object.kind{E::Ident(name)=>Some(name),_=>None},_=>None}}
 fn actor_arms(&self)->Option<(&Self,&Self)>{if let dm_syntax::ExprKind::Conditional{then_value,else_value,..}=&self.kind{Some((then_value,else_value))}else{None}}
}
