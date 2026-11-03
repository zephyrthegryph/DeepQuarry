//! Original UI-actions metadata and prepared dispatcher DATA, not source authority.
use std::{io,sync::Arc};
use crate::{lint::{Meta,Policy,RuleMeta,ScanKind},tree::Select};
#[cfg(feature="native-policy")]use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure,key_policy_control::{self as kc,Control},ui_actions_normalizer::{Normaliser,DispatcherControl,normaliser_from_using}};
pub const DISPATCHER:&str="code/datums/capabilities/ui_actions.dm";
pub const INTERFACES:&str="tgui/packages/tgui/interfaces";
pub(crate) const BASELINE:&str="tools/ci/ui_actions_baseline.txt";
pub(crate) const R_UNSENT:&str="ui_unsent_param";
pub(crate) const R_UNVALIDATED:&str="ui_unvalidated_param";
pub(crate) const R_PROBLEM:&str="problem";
pub(crate) static META: Meta = Meta {
    name: crate::allow_registry_fields::ui_actions::SCOPE_META_0.name,
    group: crate::allow_registry_fields::ui_actions::SCOPE_META_0.group,
    label: "ui_actions",
    legacy: "tools/ci/ui_actions_lint.py",
    select: Select {
        roots: &[
            ("code", "dm"),
            (INTERFACES, "tsx"),
            (INTERFACES, "ts"),
            (INTERFACES, "jsx"),
            (INTERFACES, "js"),
        ],
        hidden: false,
    },
    scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: BASELINE,
        header: &["ui_actions_lint C1/C2 baseline (design review C1, C2); shrink-only, target 0"],
        banned: &[R_PROBLEM],
    },
    rules: &[
        RuleMeta {
            name: R_UNSENT,
            hint: "every act_ parameter must be sent by some TSX act(); move internal flags to an internal proc (design review C1)",
        },
        RuleMeta {
            name: R_UNVALIDATED,
            hint: "validate the parameter first: ui_number/ui_text/ui_choice/ui_ref/ui_token/ui_member/ui_bool(param), or compare it to a constant (design review C2)",
        },
        RuleMeta {
            name: R_PROBLEM,
            hint: "make the act() match an act_ proc of the interface's host (dispatcher rules: code/datums/capabilities/ui_actions.dm)",
        },
    ],
    allow: crate::allow_registry_fields::ui_actions::ALLOW_0,
    lists: crate::allow_registry_fields::ui_actions::SCOPE_META_0.lists,
};

// ---- the dispatcher's normalisation -----------------------------------------------------------


pub fn metadata()->&'static Meta{&META}

/// Fallible payload allocation for checked UI execution; compatibility keeps
/// the original exact String/Proc clone path and does no added polling.
pub(crate) fn own_using<C:crate::key_policy_control::Control>(c:&mut C,value:&str)->Result<String,C::Error>{if !C::CHECKED{return Ok(value.to_owned())}crate::key_policy_control::reserve(c,||value.len().checked_add(64))?;let mut out=String::new();out.try_reserve_exact(value.len()).map_err(|_|c.allocation_failed())?;out.push_str(value);Ok(out)}
pub(crate) fn map_room_using<C:crate::key_policy_control::Control,K:Eq+std::hash::Hash,V>(map:&mut std::collections::HashMap<K,V>,c:&mut C)->Result<(),C::Error>{if C::CHECKED&&map.len()==map.capacity(){crate::key_policy_control::reserve(c,||map.capacity().checked_add(1)?.checked_next_power_of_two()?.checked_mul(2)?.max(4).checked_mul(std::mem::size_of::<(K,V)>().checked_add(1)?)?.checked_add(64))?;map.try_reserve(1).map_err(|_|c.allocation_failed())?;}Ok(())}
pub(crate) fn set_room_using<C:crate::key_policy_control::Control,K:Eq+std::hash::Hash>(set:&mut std::collections::HashSet<K>,c:&mut C)->Result<(),C::Error>{if C::CHECKED&&set.len()==set.capacity(){crate::key_policy_control::reserve(c,||set.capacity().checked_add(1)?.checked_next_power_of_two()?.checked_mul(2)?.max(4).checked_mul(std::mem::size_of::<K>().checked_add(1)?)?.checked_add(64))?;set.try_reserve(1).map_err(|_|c.allocation_failed())?;}Ok(())}
pub(crate) fn copy_proc_using<C:crate::key_policy_control::Control>(c:&mut C,p:&crate::dm::dx::Proc)->Result<crate::dm::dx::Proc,C::Error>{if !C::CHECKED{return Ok(p.clone())}let rel=own_using(c,&p.rel)?;let path=own_using(c,&p.path)?;let name=own_using(c,&p.name)?;let mut params=Vec::new();for v in &p.params{crate::key_policy_control::row(c,&mut params)?;params.push(own_using(c,v)?);}Ok(crate::dm::dx::Proc{rel,line:p.line,path,name,params,body_start:p.body_start,body_len:p.body_len})}
#[cfg(feature="native-policy")]mod prepared{use super::*;
/// Prepared from actual dispatcher bytes by the private raw source owner. The
/// result itself is only DATA and cannot mint file, role, or completion grants.
pub struct PreparedDispatcher{pub(crate) state:DispatcherState,charge:usize,first_line:String}
pub(crate) enum DispatcherState{Missing,Bad(String),Ready(Normaliser)}
impl PreparedDispatcher{pub fn needs_sources(&self)->bool{matches!(self.state,DispatcherState::Ready(_))}pub fn budget_charge(&self)->usize{self.charge}}
pub fn prepare_dispatcher(text:Option<&str>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<PreparedDispatcher,Failure>{
 poll()?;budget.require().map_err(oom)?;let before=budget.used();budget.charge(std::mem::size_of::<PreparedDispatcher>()+128).map_err(oom)?;let state=match text{None=>DispatcherState::Missing,Some(text)=>match normaliser_from_using(text,&mut Work{budget,poll})?{Ok(normalizer)=>DispatcherState::Ready(normalizer),Err(message)=>DispatcherState::Bad(message)}};poll()?;budget.require().map_err(oom)?;let first_line=match text{None=>String::new(),Some(text)=>{let raw=text.lines().next().unwrap_or("");budget.charge(raw.len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or_else(||oom("UI first-line bound overflow".into()))?).map_err(oom)?;crate::util::normalize_ws(raw)}};poll()?;budget.require().map_err(oom)?;let charge=budget.used().checked_sub(before).ok_or_else(||oom("UI dispatcher accounting moved backwards".into()))?;Ok(PreparedDispatcher{state,charge,first_line})
}
fn oom(message:String)->Failure{Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
pub(crate) struct Work<'a>{pub(crate) budget:&'a Arc<Budget>,pub(crate) poll:&'a dyn Fn()->io::Result<()>}
impl Control for Work<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{(self.poll)()?;self.budget.require().map_err(oom)}fn reserve(&mut self,n:usize)->Result<(),Failure>{self.budget.charge(n).map_err(oom)}fn overflow(&mut self)->Failure{let _=self.budget.charge(usize::MAX);oom("UI-actions allocation overflow".into())}fn allocation_failed(&mut self)->Failure{let _=self.budget.charge(usize::MAX);oom("UI-actions allocation refused".into())}}
impl DispatcherControl for Work<'_>{fn invalid_pattern(&mut self,pattern:&str,message:String)->Failure{match kc::format(self,format_args!("original UI dispatcher pattern unavailable ({pattern:?}): {message}")){Ok(message)=>Failure::Unsupported(message),Err(actual)=>actual}}}

impl PreparedDispatcher{
 /// Only actually exposed allocation identities; compiled regex internals and
 /// HashSet buckets stay explicitly unknown in heap census, not invented RSS.
 pub fn visit_exposed_storage(&self,mut visit:impl FnMut(usize,usize,usize)){visit(self.first_line.as_ptr()as usize,self.first_line.len(),self.first_line.capacity());match &self.state{DispatcherState::Missing=>(),DispatcherState::Bad(message)=>visit(message.as_ptr()as usize,message.len(),message.capacity()),DispatcherState::Ready(normalizer)=>normalizer.visit_exposed_storage(&mut visit)}}
 pub fn first_source_line(&self)->&str{&self.first_line}
 pub fn has_opaque_storage(&self)->bool{matches!(self.state,DispatcherState::Ready(_))}
}

}
#[cfg(feature="native-policy")]pub use prepared::{PreparedDispatcher,prepare_dispatcher};
#[cfg(feature="native-policy")]pub(crate) use prepared::{Work,DispatcherState};
