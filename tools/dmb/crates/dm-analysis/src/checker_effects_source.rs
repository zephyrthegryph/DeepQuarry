//! Bounded contribution windows over the EXISTING original callable roster.
//! This is not a page-local effect graph/SCC or a new Type/Proc model. All
//! source calls and predecessor IDs remain global original ProcedureIdentity.
use super::*;
use crate::policy_body_demand::PolicyFailure;
use dm_tree::frontend::{BodySyntax,BodySyntaxInput,BodySyntaxFailure};
use std::{io,mem::size_of};

/// Borrowed immutable source/profile view, with no copied whole-program roster.
/// A current source query must still validate its existing PurityScope before
/// asking this additive producer; this view does not grant a public frame lease.
pub struct EffectSource<'source>{pub(super) archive:&'source Arc<BodyArchive>,pub(super) profile:PackedU128}
impl<'source> EffectSource<'source>{
    pub fn new(archive:&'source Arc<BodyArchive>,profile:PackedU128)->Result<Self,PolicyFailure>{
        archive.tree().validate_checker_builtin_profile(profile).map_err(|e|PolicyFailure::from(format!("purity builtin profile: {e:?}")))?;
        if archive.syntax_inputs().is_none()||archive.body_query_host().is_none(){return Err("effect source requires original compiler body-query graph".into())}
        if !archive.callables().authenticates_borrowed_tree(archive.tree()){return Err("effect source callable roster has foreign tree".into())}
        Ok(Self{archive,profile})
    }
    pub fn len(&self)->usize{self.archive.callables().source_order().len()}
    pub fn is_empty(&self)->bool{self.len()==0}
    /// Original authored order is the contribution order only. Reporting keeps
    /// the established checker_order traversal and global phase/target order.
    pub fn original_ordinal(&self,index:usize)->Option<usize>{self.archive.callables().source_order().get(index).copied()}
    pub fn validate_current(&self,current:&Arc<BodyArchive>,host:&dyn BodySyntaxQueries)->Result<(),PolicyFailure>{
        if !Arc::ptr_eq(self.archive,current)||!current.uses_body_queries(host){return Err("effect source is not current original archive/Db".into())}
        current.tree().validate_checker_builtin_profile(self.profile).map_err(|e|PolicyFailure::from(format!("effect source profile changed: {e:?}")))
    }
    /// The page and contribution owners cannot escape through these borrowed
    /// views. Callers can explicitly copy separate data under their own budget.
    /// Callee syntax for the existing return/directive policy uses the SAME
    /// checked body loan; no callee EFFECT contribution is demanded. A global
    /// SCC reader must join these SAME full source IDs across page boundaries.
    pub fn for_each_page_checked(
        &self,width:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,
        checkpoint:&mut impl FnMut()->io::Result<()>,
        body:&dyn Fn(&Arc<BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<BodySyntax>,BodySyntaxFailure>,
        mut consume:impl FnMut(EffectSourcePage<'_>)->Result<(),PolicyFailure>,
    )->Result<(),PolicyFailure>{
        checkpoint().map_err(PolicyFailure::Operational)?;
        require_admission(admission)?;
        if resolver.source_owner()!=Resolver::source_owner(self.archive.tree()){return Err("effect source resolver is foreign".into())}
        if width==0||width>MAX_EVENTS{return Err("effect source page width is outside existing event bound".into())}
        let mut start=0usize;
        while start<self.len(){let mut consumed=0;self.with_page_checked(start,width,resolver,admission,checkpoint,body,|page|{consumed=page.len();consume(page)})?;if consumed==0{return Err("effect source produced an empty window".into())}start=start.checked_add(consumed).ok_or("effect source window cursor overflow")?;}
        checkpoint().map_err(PolicyFailure::Operational)?;require_admission(admission)
    }
    /// One current original contribution loan. Callers can lower the SAME
    /// admission between pages as their own retained scalar graph grows.
    pub fn with_page_checked(
        &self,start:usize,width:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,
        checkpoint:&mut impl FnMut()->io::Result<()>,
        body:&dyn Fn(&Arc<BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<BodySyntax>,BodySyntaxFailure>,
        mut consume:impl FnMut(EffectSourcePage<'_>)->Result<(),PolicyFailure>,
    )->Result<(),PolicyFailure>{
        checkpoint().map_err(PolicyFailure::Operational)?;
        require_admission(admission)?;
        let result=(||{
            if width==0||width>MAX_EVENTS||start>=self.len(){return Err("effect source page range is outside original roster".into())}
            if resolver.source_owner()!=Resolver::source_owner(self.archive.tree()){return Err("effect source resolver is foreign".into())}
            let order=self.archive.callables().source_order();
                let end=start.saturating_add(width).min(order.len());let count=end-start;
                let budget=ReportBudget::for_operation(admission);
                // Both original page-row storage and body-owner vector overlap
                // are reserved BEFORE their allocations, under the unchanged
                // operation allowance. Whole-roster order is never copied.
                let fixed=count.checked_mul(size_of::<(usize,ProcedureIdentity)>()+size_of::<Arc<BodyEffects>>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(size_of::<EffectInput>()+size_of::<Vec<Arc<BodyEffects>>>()+256)).ok_or_else(||resource(&budget,"effect page coordinate overflow"))?;
                budget.charge(fixed).map_err(|_|resource(&budget,"effect page coordinate admission exhausted"))?;
                let mut rows=Vec::new();rows.try_reserve_exact(count).map_err(|_|resource(&budget,"effect page order allocation refused"))?;
                if rows.capacity()>count.saturating_mul(4){return Err(resource(&budget,"effect page order exposed excess capacity"))}
                for &ordinal in &order[start..end]{checkpoint().map_err(PolicyFailure::Operational)?;rows.push((ordinal,identity(self.archive,ordinal)?));}
                let input=Arc::new(EffectInput{key:next_input_key()?,archive:Arc::clone(self.archive),profile:self.profile,order:rows.into(),whole_roster:false});
                let mut values=Vec::new();values.try_reserve_exact(count).map_err(|_|resource(&budget,"effect page contributions allocation refused"))?;
                if values.capacity()>count.saturating_mul(4){return Err(resource(&budget,"effect page contributions exposed excess capacity"))}
                let mut events=0usize;
                for &(ordinal,_) in input.order.iter(){
                    checkpoint().map_err(PolicyFailure::Operational)?;
                    // The next child receives only the live page's remaining
                    // allowance, sharing the SAME denial state (never reset).
                    let child=budget.admission_view();
                    let computed=input.compute_body_checked_using_admitted(ordinal,resolver,&child,body);
                    let value=match computed{Err(PolicyFailure::Operational(actual))=>return Err(PolicyFailure::Operational(actual)),result=>{if child.is_denied(){return Err(resource(&budget,"effect page body admission exhausted"))}result?}};
                    checkpoint().map_err(PolicyFailure::Operational)?;
                    let count=value.direct.len().checked_add(value.calls.len()).and_then(|n|n.checked_add(value.blocking.len())).and_then(|n|n.checked_add(value.immediate.len())).ok_or_else(||resource(&budget,"effect page event overflow"))?;
                    let next=events.checked_add(count).ok_or_else(||resource(&budget,"effect page event overflow"))?;
                    // Full original bodies remain indivisible. A genuine next
                    // body can begin the following window without denying the
                    // shared operation or omitting its global source IDs.
                    if next>MAX_EVENTS&&!values.is_empty(){drop(value);break}
                    if next>MAX_EVENTS{return Err(resource(&budget,"effect body exceeds existing event allowance"))}
                    events=next;
                    budget.charge(value.charge()).map_err(|_|resource(&budget,"effect page retained contribution admission exhausted"))?;
                    values.push(value);
                }
                checkpoint().map_err(PolicyFailure::Operational)?;
                consume(EffectSourcePage{input:&input,bodies:&values,start,total:order.len(),events,live_charge:budget.used()})?;

            checkpoint().map_err(PolicyFailure::Operational)?;
            Ok(())
        })();
        if matches!(&result,Err(PolicyFailure::Operational(_))){return result}
        checkpoint().map_err(PolicyFailure::Operational)?;require_admission(admission)?;result
    }
}
fn require_admission(admission:&ExecutionAdmission)->Result<(),PolicyFailure>{if admission.is_denied(){Err(PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"effect source shared operation admission was denied")))}else{Ok(())}}
fn resource(budget:&ReportBudget,message:&'static str)->PolicyFailure{budget.deny();PolicyFailure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message))}
/// Readonly loan of one bounded page. The SAME BodyEffects owner exists only
/// inside the caller's operation; no Arc or independently plannable input escapes.
pub struct EffectSourcePage<'page>{input:&'page Arc<EffectInput>,bodies:&'page[Arc<BodyEffects>],start:usize,total:usize,events:usize,live_charge:usize}
impl EffectSourcePage<'_>{
    pub fn start(&self)->usize{self.start}
    pub fn total(&self)->usize{self.total}
    pub fn len(&self)->usize{self.bodies.len()}
    pub fn is_empty(&self)->bool{self.bodies.is_empty()}
    pub fn events(&self)->usize{self.events}
    /// Conservative currently live page reservation, for overlapping parent work.
    pub fn live_charge(&self)->usize{self.live_charge}
    pub(super) fn retain_contribution(&self,index:usize)->Result<Option<Arc<BodyEffects>>,PolicyFailure>{match self.bodies.get(index){Some(body)=>{body.validate(self.input)?;Ok(Some(Arc::clone(body)))},None=>Ok(None)}}
    pub fn contribution(&self,index:usize)->Result<Option<EffectContribution<'_>>,PolicyFailure>{match self.bodies.get(index){Some(body)=>{body.validate(self.input)?;Ok(Some(EffectContribution{body}))},None=>Ok(None)}}
}
pub struct EffectContribution<'body>{body:&'body BodyEffects}
impl EffectContribution<'_>{
    pub(super) fn source_call_count(&self)->usize{self.body.calls.iter().filter(|edge|matches!(edge.callee,EffectTarget::Source(_))).count()}
    pub(super) fn parent(&self)->Option<EffectTarget>{self.body.parent}
    pub(super) fn try_source_calls<E>(&self,mut visit:impl FnMut(ProcedureIdentity)->Result<(),E>)->Result<(),E>{for edge in self.body.calls.iter(){if let EffectTarget::Source(id)=edge.callee{visit(id)?}}Ok(())}
    pub fn ordinal(&self)->usize{self.body.ordinal}
    pub fn procedure(&self)->ProcedureIdentity{self.body.procedure}
    pub fn source_parent(&self)->Option<ProcedureIdentity>{match self.body.parent{Some(EffectTarget::Source(id))=>Some(id),_=>None}}
    pub fn has_direct_effect(&self)->bool{!self.body.direct.is_empty()}
    pub fn has_builtin_effect_call(&self)->bool{self.body.calls.iter().any(|edge|matches!(edge.callee,EffectTarget::Builtin(_)))}
    pub fn visit_source_calls(&self,mut visit:impl FnMut(ProcedureIdentity,bool,bool)){for edge in self.body.calls.iter(){if let EffectTarget::Source(id)=edge.callee{visit(id,edge.exact,edge.new_context)}}}
}
impl BodyEffects{
    pub fn source_contribution(&self)->EffectContribution<'_>{EffectContribution{body:self}}
}
