//! ONE six-rule derived-read judgment kernel; source authority is never a boolean here.
//! Callers lend authentic raw Procedure views and their existing SAME-run facts.
use crate::{key_policy_control::{self as kc,Control},reactive_reaction_policy::{self as reaction,Procedure,Membership,EXEMPT_VARS},derived_entry_policy::Entry,derived_reads_collect_policy::{proc_kind,derive_value}};
#[derive(Clone,Debug)]pub(crate) struct Finding{pub rel:String,pub line:usize,pub rule:&'static str,pub owner:String,pub proc:String,pub var:Option<String>,pub kind:Option<String>}
#[derive(Clone,Copy)]pub(crate) enum Table{Tracked,Relation,Object,Derived}
pub(crate) trait Facts{
 type Error;type Known<'a>:Membership<Error=Self::Error> where Self:'a;
 fn known<'a>(&'a self,owner:&'a str)->Result<Self::Known<'a>,Self::Error>;
 fn has(&self,table:Table,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn exact(&self,owner:&str)->Result<bool,Self::Error>;
 fn declared_value(&self,owner:&str,value:&str)->Result<bool,Self::Error>;
 fn declared_read(&self,owner:&str,kind:&str,value:Option<&str>,name:&str)->Result<bool,Self::Error>;
 fn published(&self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn never_written(&self,owner:&str,name:&str)->Result<bool,Self::Error>;
 fn allowed(&self,relative:&str,line:usize)->Result<bool,Self::Error>;
}
fn skipped(relative:&str)->bool{relative.starts_with("code/tests/unit_tests/")}
fn emit<C:Control>(control:&mut C,relative:&str,line:usize,rule:&'static str,owner:&str,proc:&str,var:Option<&str>,kind:Option<&str>,out:&mut dyn FnMut(Finding)->Result<(),C::Error>)->Result<(),C::Error>{
 control.checkpoint()?;out(Finding{rel:kc::own(control,relative)?,line,rule,owner:kc::own(control,owner)?,proc:kc::own(control,proc)?,var:var.map(|v|kc::own(control,v)).transpose()?,kind:kind.map(|v|kc::own(control,v)).transpose()?})
}
fn admits<F:Facts>(facts:&F,owner:&str,name:&str)->Result<bool,F::Error>{Ok(EXEMPT_VARS.contains(&name)||facts.has(Table::Tracked,owner,name)?||facts.has(Table::Derived,owner,name)?||facts.has(Table::Relation,owner,name)?)}
pub(crate) fn reactive<F:Facts,C:Control<Error=F::Error>>(facts:&F,proc:Procedure<'_>,generated_covers:bool,control:&mut C,out:&mut dyn FnMut(Finding)->Result<(),F::Error>)->Result<(),F::Error>{
 control.checkpoint()?;if proc.owner=="/"||skipped(proc.relative)||proc.owner.starts_with("/datum/capability"){return Ok(())}
 let kind=proc_kind(proc.name);let value=derive_value(proc.name);if kind.is_none()&&value.is_none(){return Ok(())}let known=facts.known(proc.owner)?;
 if proc.name=="ui_data"{for(name,line)in reaction::body_reads(&proc,&known,control)?{if admits(facts,proc.owner,&name)?||facts.never_written(proc.owner,&name)?||facts.allowed(proc.relative,line)?{continue}emit(control,proc.relative,line,"untracked_ui_read",proc.owner,proc.name,Some(&name),Some("ui"),out)?}}
 if generated_covers&&(proc.name=="ui_data"||!facts.exact(proc.owner)?){return Ok(())}
 let(label,wanted)=if let Some(value)=value{if !facts.declared_value(proc.owner,value)?{return Ok(())}(kc::format(control,format_args!("derive_{}",value))?,"derive")}else{(kc::own(control,proc.name)?,kind.unwrap())};
 for(name,line)in reaction::body_reads(&proc,&known,control)?{if facts.declared_read(proc.owner,wanted,value,&name)?||facts.allowed(proc.relative,line)?{continue}emit(control,proc.relative,line,"undeclared_read",proc.owner,&label,Some(&name),Some(wanted),out)?}Ok(())
}
pub(crate) fn exact<F:Facts,C:Control<Error=F::Error>>(facts:&F,proc:Procedure<'_>,header:usize,control:&mut C,out:&mut dyn FnMut(Finding)->Result<(),F::Error>)->Result<(),F::Error>{
 control.checkpoint()?;if proc.name=="on_state_changed"&&proc.owner!="/"&&!skipped(proc.relative)&&facts.exact(proc.owner)?&&!facts.allowed(proc.relative,header)?{emit(control,proc.relative,header,"exact_on_state_changed",proc.owner,proc.name,None,None,out)?}Ok(())
}
pub(crate) fn entry<F:Facts,C:Control<Error=F::Error>>(facts:&F,owner:&str,e:&Entry,control:&mut C,out:&mut dyn FnMut(Finding)->Result<(),F::Error>)->Result<(),F::Error>{
 control.checkpoint()?;if skipped(&e.rel)||facts.allowed(&e.rel,e.line)?{return Ok(())}
 for link in &e.hops{if !facts.has(Table::Relation,owner,link)?{emit(control,&e.rel,e.line,"hop_not_relation",owner,"",Some(link),Some(e.kind),out)?}}
 for name in &e.local{if !admits(facts,owner,name)?{emit(control,&e.rel,e.line,"declared_untracked",owner,"",Some(name),Some(e.kind),out)?}}
 for(ty,name)in &e.remote{let Some(ty)=ty.as_ref().filter(|t|!t.is_empty())else{continue};if !admits(facts,ty,name)?{let var=kc::format(control,format_args!("{}::{}",ty,name))?;emit(control,&e.rel,e.line,"declared_untracked",owner,"",Some(&var),Some(e.kind),out)?}}Ok(())
}
pub(crate) fn reaction<F:Facts,C:Control<Error=F::Error>>(facts:&F,proc:Procedure<'_>,kind:&str,reads:&[(String,usize)],control:&mut C,out:&mut dyn FnMut(Finding)->Result<(),F::Error>)->Result<(),F::Error>{
 for(name,line)in reads{control.checkpoint()?;if facts.has(Table::Tracked,proc.owner,name)?||facts.has(Table::Relation,proc.owner,name)?||facts.has(Table::Object,proc.owner,name)?||EXEMPT_VARS.contains(&name.as_str())||facts.published(proc.owner,name)?||facts.allowed(proc.relative,*line)?{continue}emit(control,proc.relative,*line,"reaction_read_untracked",proc.owner,proc.name,Some(name),Some(kind),out)?}Ok(())
}
pub(crate) fn compare(a:&Finding,b:&Finding)->std::cmp::Ordering{(a.rel.as_str(),a.line,a.rule,a.var.as_deref().unwrap_or("")).cmp(&(b.rel.as_str(),b.line,b.rule,b.var.as_deref().unwrap_or("")))}
