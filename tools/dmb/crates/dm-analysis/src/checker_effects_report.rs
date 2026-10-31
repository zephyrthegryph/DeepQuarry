//! One diagnostic judgement over borrowed legacy rows or current page loans.
//! No source/AST/table clone is part of this interface. Each loan must retain
//! its actual original producer and physical reservation until dropped.
use super::*;
use std::{marker::PhantomData,ops::Deref};

#[derive(Clone,Copy)]
pub(crate) struct ReportSource<'a>{pub(crate) archive:&'a BodyArchive,pub(crate) profile:PackedU128}
impl<'a> From<&'a EffectInput> for ReportSource<'a>{fn from(input:&'a EffectInput)->Self{Self{archive:&input.archive,profile:input.profile}}}

pub(crate) trait ReportAccess{
 type Error:From<String>+From<&'static str>;
 type Scope;
 type Body<'a>:Deref<Target=BodyEffects> where Self:'a;
 type Overrides<'a>:Deref<Target=[usize]> where Self:'a;
 fn source(&self)->ReportSource<'_>;
 fn group_mark(&self)->Result<Self::Scope,Self::Error>;
 fn group_finished(&self,marker:Self::Scope,retained_delta:usize)->Result<(),Self::Error>;
 fn observes_allocations(&self)->bool{false}
 fn reserve(&self,bytes:usize)->Result<(),Self::Error>;
 fn len(&self)->usize;
 fn ordered_node(&self,rank:usize)->Result<usize,Self::Error>;
 fn target_range(&self)->std::ops::Range<usize>{0..self.len()}
 fn body(&self,node:usize,live:&ExecutionAdmission)->Result<Self::Body<'_>,Self::Error>;
 fn index(&self,id:ProcedureIdentity)->Result<usize,Self::Error>;
 fn source_parent(&self,id:ProcedureIdentity,live:&ExecutionAdmission)->Result<Option<EffectTarget>,Self::Error>{Ok(self.body(self.index(id)?,live)?.parent)}
 fn has_effect(&self,node:usize)->Result<bool,Self::Error>;
 fn override_children(&self,node:usize,budget:&output::ReportBudgetWith<'_,Self::Error>)->Result<Self::Overrides<'_>,Self::Error>;
 fn callable_point(&self,body:&BodyEffects,missing:&'static str,budget:&output::ReportBudgetWith<'_,Self::Error>)->Result<(SourceNoteOrigin,Span),Self::Error>;
}

pub(crate) struct LegacyReportAccess<'a,D>{pub(crate) input:&'a Arc<EffectInput>,pub(crate) plan:&'a EffectPlan,pub(crate) summary:Option<&'a SccSummary>,pub(crate) demand:PhantomData<D>}
impl<D:crate::policy_body_demand::Demand> ReportAccess for LegacyReportAccess<'_,D>{
 type Error=D::Error;type Scope=();type Body<'a>=&'a BodyEffects where Self:'a;type Overrides<'a>=&'a [usize] where Self:'a;
 fn source(&self)->ReportSource<'_>{ReportSource::from(self.input.as_ref())}
 fn group_mark(&self)->Result<Self::Scope,Self::Error>{Ok(())}
 fn group_finished(&self,_:Self::Scope,_:usize)->Result<(),Self::Error>{Ok(())}
 fn reserve(&self,_:usize)->Result<(),Self::Error>{Ok(())}
 fn len(&self)->usize{self.plan.bodies.len()}
 fn ordered_node(&self,rank:usize)->Result<usize,Self::Error>{if rank<self.len(){Ok(rank)}else{Err("effect report rank outside original roster".into())}}
 fn body(&self,node:usize,_:&ExecutionAdmission)->Result<Self::Body<'_>,Self::Error>{self.plan.bodies.get(node).map(Arc::as_ref).ok_or_else(||"effect report source row absent".into())}
 fn index(&self,id:ProcedureIdentity)->Result<usize,Self::Error>{self.plan.index.get(&id).copied().ok_or_else(||"effect report identity absent".into())}
 fn has_effect(&self,node:usize)->Result<bool,Self::Error>{let summary=self.summary.ok_or("purity report summary absent")?;Ok(summary.has_effect.get(*self.plan.components.get(node).ok_or("purity report component absent")?).copied().unwrap_or(false))}
 fn override_children(&self,node:usize,_:&output::ReportBudgetWith<'_,Self::Error>)->Result<Self::Overrides<'_>,Self::Error>{self.plan.overrides.get(node).map(Vec::as_slice).ok_or_else(||"effect report override row absent".into())}
 fn callable_point(&self,body:&BodyEffects,missing:&'static str,_:&output::ReportBudgetWith<'_,Self::Error>)->Result<(SourceNoteOrigin,Span),Self::Error>{let origin=self.input.archive.callable_note_origin_with(body.procedure,D::parse)?;let header=D::parse(&self.input.archive,body.ordinal)?.signature_opening_parenthesis().ok_or(missing)?;Ok((origin,header))}
}

fn parent<A:ReportAccess>(access:&A,resolver:&(impl Resolver+?Sized),target:EffectTarget,live:&ExecutionAdmission)->Result<Option<EffectTarget>,A::Error>{match target{EffectTarget::Source(id)=>access.source_parent(id,live),EffectTarget::Builtin(_)=>{let source=access.source();Ok(original_target_parent(source.archive,source.profile,resolver,target)?)}}}
fn overrides<A:ReportAccess>(access:&A,resolver:&(impl Resolver+?Sized),child:&BodyEffects,target:EffectTarget,budget:&output::ReportBudgetWith<'_,A::Error>)->Result<bool,A::Error>{let mut at=child.parent;let mut seen=BTreeSet::new();while let Some(p)=at{if !budget.insert(&mut seen,p)?{return Err("effect target predecessor cycle".into())}if p==target{return Ok(true)}at=parent(access,resolver,p,&budget.admission_view())?;}Ok(false)}

pub(crate) fn purity<A:ReportAccess>(access:&A,resolver:&(impl Resolver+?Sized),policy:&CheckerPolicy,admission:&ExecutionAdmission,mut checkpoint:impl FnMut()->Result<(),A::Error>)->Result<Vec<Produced>,A::Error>{let source=access.source();let input=&source;

        if resolver.source_owner() != Resolver::source_owner(input.archive.tree()) {
            return Err("purity report original resolver mismatch".into());
        }
        let observer=|bytes|access.reserve(bytes);let budget=if access.observes_allocations(){output::ReportBudgetWith::observed(admission,&observer)}else{output::ReportBudgetWith::for_operation(admission)};

        let mut output = Vec::new();
        let mut targets = Vec::new();
        for rank in access.target_range(){let marker=access.group_mark()?;let marked_used=budget.used();let before=budget.output_bound(&output)?.checked_add(coordinate_charge::<_,A::Error>(&targets)?).ok_or("effect report retained coordinate overflow")?;let pending=(||->Result<(),A::Error>{let i=access.ordered_node(rank)?;let loan=access.body(i,&budget.admission_view())?;let body=&*loan;
            checkpoint()?;
            for row in body.immediate.iter() {
                emit(
                    &mut output,
                    input,
                    None,
                    budget.diagnostic(row)?,
                    report_source_note(input,row.span.start,&budget)?,
                    policy,
                    &budget,
                )?;
            }
            let mut at = Some(EffectTarget::Source(body.procedure));
            let mut visited = BTreeSet::new();
            while let Some(target) = at {
                if !budget.insert(&mut visited, target)? {
                    return Err("purity directive predecessor cycle".into());
                }
                if let EffectTarget::Source(id) = target {
                    let j=access.index(id)?;
                    if let Some(annotation) = access.body(j,&budget.admission_view())?.pure {
                        budget.push(&mut targets, (i, annotation))?;
                        break;
                    }
                }
                at=parent(access,resolver,target,&budget.admission_view())?;
            }

Ok(())})();if pending.is_ok(){let after=budget.output_bound(&output)?.checked_add(coordinate_charge::<_,A::Error>(&targets)?).ok_or("effect report retained coordinate overflow")?;finish_group(access,&budget,marker,marked_used,before,after)?;}pending?;}
        // The pinned checker iterates HashMap directive groups and prints
        // immediately: only inter-target permutations are unspecified. Keep
        // deterministic authored target order here, never sort rows or notes.
        for (target, annotation) in targets {let marker=access.group_mark()?;let marked_used=budget.used();let before=budget.output_bound(&output)?;let pending=(||->Result<(),A::Error>{
            checkpoint()?;
            let body_loan=access.body(target,&budget.admission_view())?;let body=&*body_loan;
            let(origin,header)=access.callable_point(body,"purity primary callable point absent",&budget)?;
            let target_display = display(input, body.procedure, &budget)?;
            let annotation_note = Note {
                message: budget.format(format_args!("SpacemanDMM_should_be_pure set here"))?,
                source: Some(report_source_note(input,annotation.start,&budget)?),
            };
            if !body.direct.is_empty() {
                let mut notes = budget.annotation(&annotation_note)?;
                effect_notes(input, &body.direct, false, &mut notes, &budget)?;
                emit(
                    &mut output,
                    input,
                    Some("must_be_pure"),
                    diagnostic(
                        header,
                        budget.format(format_args!("{target_display} does impure operations"))?,
                        notes,
                    ),
                    budget.point(&origin)?,
                    policy,
                    &budget,
                )?;
            }
            if !access.has_effect(target)?{return Ok(())}
            let mut queue = output::initial_queue(&body.calls, &budget)?;
            let mut queued_edges = body.calls.len();
            let mut visited = BTreeSet::new();
            while let Some((id, path)) = queue.pop_front() {
                queued_edges = queued_edges.saturating_sub(path.len());
                checkpoint()?;
                if !budget.insert(&mut visited, id)? {
                    continue;
                }
                let target = id;
                if let EffectTarget::Builtin(_) = target {
                    let called = display_target(input, target, &budget)?;
                    let owner = target_owner(input, target)?;
                    for child_rank in 0..access.len(){let child_index=access.ordered_node(child_rank)?;let child_loan=access.body(child_index,&budget.admission_view())?;let child=&*child_loan;
                        checkpoint()?;
                        if child.direct.is_empty()
                            || child.procedure.name == SymbolId::of("New")
                            || !overrides(access,resolver,child,target,&budget)?
                        {
                            continue;
                        }
                        if is_subtype(resolver, body.procedure.owner, owner)?
                            && !is_subtype(resolver, child.procedure.owner, body.procedure.owner)?
                        {
                            continue;
                        }
                        let mut notes = budget.annotation(&Note {
                            message: budget
                                .format(format_args!("SpacemanDMM_should_not_pure set here"))?,
                            source: annotation_note.source.clone(),
                        })?;
                        call_notes(input, &path, &mut notes, &budget)?;
                        effect_notes(input, &child.direct, true, &mut notes, &budget)?;
                        emit(&mut output,input,Some("must_be_pure"),diagnostic(header,budget.format(format_args!("{target_display} calls {called} which has override child proc that does impure operations {}",display(input,child.procedure, &budget)?))?,notes),budget.point(&origin)?,policy, &budget)?;
                    }
                    continue;
                }
                let EffectTarget::Source(id) = target else {
                    unreachable!()
                };
                let index=access.index(id)?;
                let callee_loan=access.body(index,&budget.admission_view())?;let callee=&*callee_loan;
                let called = display(input, id, &budget)?;
                if !callee.direct.is_empty() {
                    let mut notes = budget.annotation(&annotation_note)?;
                    call_notes(input, &path, &mut notes, &budget)?;
                    effect_notes(input, &callee.direct, false, &mut notes, &budget)?;
                    emit(&mut output,input,Some("must_be_pure"),diagnostic(header,budget.format(format_args!("{target_display} sets SpacemanDMM_should_be_pure but calls a {called} that does impure operations"))?,notes),budget.point(&origin)?,policy, &budget)?;
                } else {
                    let override_children=access.override_children(index,&budget)?;for &child_index in override_children.iter(){let child_loan=access.body(child_index,&budget.admission_view())?;let child=&*child_loan;
                        if is_subtype(resolver, body.procedure.owner, id.owner)?
                            && !is_subtype(resolver, child.procedure.owner, body.procedure.owner)?
                        {
                            continue;
                        }
                        let mut notes = budget.annotation(&Note {
                            message: budget
                                .format(format_args!("SpacemanDMM_should_not_pure set here"))?,
                            source: annotation_note.source.clone(),
                        })?;
                        call_notes(input, &path, &mut notes, &budget)?;
                        effect_notes(input, &child.direct, true, &mut notes, &budget)?;
                        emit(&mut output,input,Some("must_be_pure"),diagnostic(header,budget.format(format_args!("{target_display} calls {called} which has override child proc that does impure operations {}",display(input,child.procedure, &budget)?))?,notes),budget.point(&origin)?,policy, &budget)?;
                    }
                }
                for edge in callee.calls.iter() {
                    let next_len = path
                        .len()
                        .checked_add(1)
                        .ok_or("purity callstack admission overflow")?;
                    queued_edges = queued_edges
                        .checked_add(next_len)
                        .filter(|n| *n <= MAX_EVENTS)
                        .ok_or("purity BFS retained paths exceed bounded admission")?;
                    let next = budget.path(&path, edge)?;
                    budget.queue(&mut queue, (edge.callee, next))?;
                }
            }

Ok(())})();if pending.is_ok(){let after=budget.output_bound(&output)?;finish_group(access,&budget,marker,marked_used,before,after)?;}pending?;}
        Ok(output)
    }

pub(crate) fn sleep<A:ReportAccess>(access:&A,resolver:&(impl Resolver+?Sized),policy:&CheckerPolicy,admission:&ExecutionAdmission,mut checkpoint:impl FnMut()->Result<(),A::Error>)->Result<Vec<Produced>,A::Error>{let source=access.source();let input=&source;

        if resolver.source_owner() != Resolver::source_owner(input.archive.tree()) {
            return Err("sleep report resolver is not the original owner".into());
        }
        let observer=|bytes|access.reserve(bytes);let budget=if access.observes_allocations(){output::ReportBudgetWith::observed(admission,&observer)}else{output::ReportBudgetWith::for_operation(admission)};
        let mut targets = Vec::new();
        for rank in access.target_range(){let marker=access.group_mark()?;let marked_used=budget.used();let before=0usize.checked_add(coordinate_charge::<_,A::Error>(&targets)?).ok_or("effect report retained coordinate overflow")?;let pending=(||->Result<(),A::Error>{let i=access.ordered_node(rank)?;let loan=access.body(i,&budget.admission_view())?;let body=&*loan;
            checkpoint()?;
            let mut at = Some(EffectTarget::Source(body.procedure));
            let mut visited = BTreeSet::new();
            while let Some(target) = at {
                if !budget.insert(&mut visited, target)? {
                    return Err("sleep directive predecessor cycle".into());
                }
                if let EffectTarget::Source(id) = target {
                    let j=access.index(id)?;
                    if let Some(annotation) = access.body(j,&budget.admission_view())?.sleep.no_sleep {
                        budget.push(&mut targets, (i, annotation))?;
                        break;
                    }
                }
                at=parent(access,resolver,target,&budget.admission_view())?;
            }

Ok(())})();if pending.is_ok(){let after=0usize.checked_add(coordinate_charge::<_,A::Error>(&targets)?).ok_or("effect report retained coordinate overflow")?;finish_group(access,&budget,marker,marked_used,before,after)?;}pending?;}
        // Same TARGET_GROUP_ORDER_CONTRACT as purity: only whole target-group
        // permutation is unspecified; each target gets a fresh visited/BFS below.
        let mut output = Vec::new();
        for (target, annotation) in targets {let marker=access.group_mark()?;let marked_used=budget.used();let before=budget.output_bound(&output)?;let pending=(||->Result<(),A::Error>{
            checkpoint()?;
            let body_loan=access.body(target,&budget.admission_view())?;let body=&*body_loan;
            let(origin,header)=access.callable_point(body,"sleep callable point unavailable",&budget)?;
            let name = display(input, body.procedure, &budget)?;
            let annotation_note = Note {
                message: budget.format(format_args!("SpacemanDMM_should_not_sleep set here"))?,
                source: Some(report_source_note(input,annotation.start,&budget)?),
            };
            // Pinned own direct violations do NOT skip waitfor/exempt flags.
            if !body.blocking.is_empty() {
                let mut notes = budget.annotation(&annotation_note)?;
                effect_notes(input, &body.blocking, true, &mut notes, &budget)?;
                emit(&mut output,input,Some("must_not_sleep"),sleep::row(header,
                    budget.format(format_args!("{name} sets SpacemanDMM_should_not_sleep but calls blocking built-in(s)"))?,notes),budget.point(&origin)?,policy, &budget)?;
            }
            let mut queue = output::initial_queue(&body.calls, &budget)?;
            let mut queued = body.calls.len();
            let mut visited = BTreeSet::new();
            while let Some((id, path)) = queue.pop_front() {
                queued = queued.saturating_sub(path.len());
                checkpoint()?;
                // Deliberately before all suppression checks: a spawned first
                // encounter may suppress a later ordinary call in the old code.
                if !budget.insert(&mut visited, id)? {
                    continue;
                }
                let target = id;
                if let EffectTarget::Builtin(_) = target {
                    if path.last().is_some_and(|edge| edge.new_context) {
                        continue;
                    }
                    let called = display_target(input, target, &budget)?;
                    let owner = target_owner(input, target)?;
                    for child_rank in 0..access.len(){let child_index=access.ordered_node(child_rank)?;let child_loan=access.body(child_index,&budget.admission_view())?;let child=&*child_loan;
                        checkpoint()?;
                        if child.blocking.is_empty()
                            || child.procedure.name == SymbolId::of("New")
                            || !overrides(access,resolver,child,target,&budget)?
                        {
                            continue;
                        }
                        if is_subtype(resolver, body.procedure.owner, owner)?
                            && !is_subtype(resolver, child.procedure.owner, body.procedure.owner)?
                        {
                            continue;
                        }
                        let mut notes = budget.annotation(&annotation_note)?;
                        call_notes(input, &path, &mut notes, &budget)?;
                        effect_notes(input, &child.blocking, true, &mut notes, &budget)?;
                        emit(&mut output,input,Some("must_not_sleep"),sleep::row(header,budget.format(format_args!("{name} calls {called} which has override child proc that sleeps {}",display(input,child.procedure, &budget)?))?,notes),budget.point(&origin)?,policy, &budget)?;
                    }
                    continue;
                }
                let EffectTarget::Source(id) = target else {
                    unreachable!()
                };
                let i=access.index(id)?;
                let callee_loan=access.body(i,&budget.admission_view())?;let callee=&*callee_loan;
                if callee.sleep.waitfor_disabled
                    || callee.sleep.exempt.is_some()
                    || path.last().is_some_and(|edge| edge.new_context)
                {
                    continue;
                }
                let called = display(input, id, &budget)?;
                if !callee.blocking.is_empty() {
                    let mut notes = budget.annotation(&annotation_note)?;
                    call_notes(input, &path, &mut notes, &budget)?;
                    effect_notes(input, &callee.blocking, true, &mut notes, &budget)?;
                    emit(&mut output,input,Some("must_not_sleep"),sleep::row(header,
                        budget.format(format_args!("{name} sets SpacemanDMM_should_not_sleep but calls blocking proc {called}"))?,notes),budget.point(&origin)?,policy, &budget)?;
                } else {
                    // Derive the direct-only override relation by BORROWING the
                    // existing original parent chain. No retained adjacency copy.
                    for child_rank in 0..access.len(){let child_index=access.ordered_node(child_rank)?;let child_loan=access.body(child_index,&budget.admission_view())?;let child=&*child_loan;
                        checkpoint()?;
                        if child.blocking.is_empty() || child.procedure.name == SymbolId::of("New")
                        {
                            continue;
                        }
                        if !overrides(access,resolver,child,EffectTarget::Source(id),&budget)? {
                            continue;
                        }
                        if is_subtype(resolver, body.procedure.owner, id.owner)?
                            && !is_subtype(resolver, child.procedure.owner, body.procedure.owner)?
                        {
                            continue;
                        }
                        let mut notes = budget.annotation(&annotation_note)?;
                        call_notes(input, &path, &mut notes, &budget)?;
                        effect_notes(input, &child.blocking, true, &mut notes, &budget)?;
                        emit(&mut output,input,Some("must_not_sleep"),sleep::row(header,
                            budget.format(format_args!("{name} calls {called} which has override child proc that sleeps {}",display(input,child.procedure, &budget)?))?,notes),budget.point(&origin)?,policy, &budget)?;
                    }
                }
                for edge in callee.calls.iter() {
                    let length = path
                        .len()
                        .checked_add(1)
                        .ok_or("sleep path length overflow")?;
                    queued = queued
                        .checked_add(length)
                        .filter(|n| *n <= MAX_EVENTS)
                        .ok_or("sleep BFS paths exceed bounded admission")?;
                    let next = budget.path(&path, edge)?;
                    budget.queue(&mut queue, (edge.callee, next))?;
                }
            }

Ok(())})();if pending.is_ok(){let after=budget.output_bound(&output)?;finish_group(access,&budget,marker,marked_used,before,after)?;}pending?;}
        Ok(output)
    }

fn coordinate_charge<T,E:From<&'static str>>(rows:&Vec<T>)->Result<usize,E>{rows.capacity().checked_mul(std::mem::size_of::<T>()).ok_or_else(||E::from("effect report target-coordinate retention overflow"))}
fn finish_group<A:ReportAccess>(access:&A,budget:&output::ReportBudgetWith<'_,A::Error>,marker:A::Scope,marked_used:usize,before:usize,after:usize)->Result<(),A::Error>{if !access.observes_allocations(){return Ok(())}let retained=after.checked_sub(before).ok_or_else(||{budget.deny();A::Error::from("effect report output retention unexpectedly shrank")})?;budget.retire_scope(marked_used,retained)?;access.group_finished(marker,retained)}
