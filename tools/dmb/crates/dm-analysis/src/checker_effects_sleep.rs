//! Blocking-call propagation over the SAME original effect plan.
//! Pinned DreamChecker call-tree order, including visited-before-skip.
use super::*;
#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct SleepSettings {
    pub no_sleep: Option<Span>,
    pub exempt: Option<Span>,
    pub waitfor_disabled: bool,
}
fn row(at: Span, message: String, notes: Vec<Note>) -> Diagnostic {
    Diagnostic {
        family: "must_not_sleep",
        severity: Severity::Error,
        span: at,
        expression_span: at,
        message,
        notes,
    }
}
impl EffectPlan {
    /// Borrows the existing BodyEffects, source-identity index and call edges.
    /// No second call graph, Proc table or source owner is materialized.
    pub fn sleep_report(
        &self,
        input: &Arc<EffectInput>,
        resolver: &(impl Resolver + ?Sized),
        policy: &CheckerPolicy,
        admission: &ExecutionAdmission,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<Produced>, String> {
        self.sleep_report_with::<crate::policy_body_demand::Compatibility>(
            input, resolver, policy, admission, checkpoint,
        )
        .map_err(|e| e.0)
    }
    pub fn sleep_report_checked(
        &self,
        input: &Arc<EffectInput>,
        resolver: &(impl Resolver + ?Sized),
        policy: &CheckerPolicy,
        admission: &ExecutionAdmission,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<Produced>, crate::policy_body_demand::PolicyFailure> {
        self.sleep_report_with::<crate::policy_body_demand::Checked>(
            input, resolver, policy, admission, checkpoint,
        )
    }
    fn sleep_report_with<D: crate::policy_body_demand::Demand>(
        &self,
        input: &Arc<EffectInput>,
        resolver: &(impl Resolver + ?Sized),
        policy: &CheckerPolicy,
        admission: &ExecutionAdmission,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<Produced>, D::Error> {
        self.validate(input)?;
        if resolver.source_owner() != Resolver::source_owner(input.archive.tree()) {
            return Err("sleep report resolver is not the original owner".into());
        }
        let budget = ReportBudget::for_operation(admission);
        let mut targets = Vec::new();
        for (i, body) in self.bodies.iter().enumerate() {
            checkpoint()?;
            let mut at = Some(EffectTarget::Source(body.procedure));
            let mut visited = BTreeSet::new();
            while let Some(target) = at {
                if !budget.insert(&mut visited, target)? {
                    return Err("sleep directive predecessor cycle".into());
                }
                if let EffectTarget::Source(id) = target {
                    let j = *self
                        .index
                        .get(&id)
                        .ok_or("sleep annotation source contribution absent")?;
                    if let Some(annotation) = self.bodies[j].sleep.no_sleep {
                        budget.push(&mut targets, (i, annotation))?;
                        break;
                    }
                }
                at = target_parent_parts(input, resolver, target, &self.bodies, &self.index)?;
            }
        }
        // The old HashMap groups have no stable inter-target order. Refuse the
        // boundary until a documented normalizer exists; never sort old rows.
        if targets.len() > 1 {
            return Err(
                "sleep multi-target report order needs documented group-order normalization".into(),
            );
        }
        let mut output = Vec::new();
        for (target, annotation) in targets {
            checkpoint()?;
            let body = &self.bodies[target];
            let origin = input
                .archive
                .callable_note_origin_with(body.procedure, D::parse)?;
            let header = D::parse(&input.archive, body.ordinal)?
                .signature_opening_parenthesis()
                .ok_or("sleep callable point unavailable")?;
            let name = display(input, body.procedure, &budget)?;
            let annotation_note = Note {
                message: budget.format(format_args!("SpacemanDMM_should_not_sleep set here"))?,
                source: Some(input.archive.source_note_point(annotation.start)?),
            };
            // Pinned own direct violations do NOT skip waitfor/exempt flags.
            if !body.blocking.is_empty() {
                let mut notes = budget.annotation(&annotation_note)?;
                effect_notes(input, &body.blocking, true, &mut notes, &budget)?;
                emit(&mut output,input,Some("must_not_sleep"),row(header,
                    budget.format(format_args!("{name} sets SpacemanDMM_should_not_sleep but calls blocking built-in(s)"))?,notes),origin.clone(),policy, &budget)?;
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
                    for child in self.bodies.iter() {
                        checkpoint()?;
                        if child.blocking.is_empty()
                            || child.procedure.name == SymbolId::of("New")
                            || !source_child_overrides_target(
                                self, input, resolver, child, target, &budget,
                            )?
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
                        emit(&mut output,input,Some("must_not_sleep"),row(header,budget.format(format_args!("{name} calls {called} which has override child proc that sleeps {}",display(input,child.procedure, &budget)?))?,notes),origin.clone(),policy, &budget)?;
                    }
                    continue;
                }
                let EffectTarget::Source(id) = target else {
                    unreachable!()
                };
                let i = *self.index.get(&id).ok_or("sleep source callee absent")?;
                let callee = &self.bodies[i];
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
                    emit(&mut output,input,Some("must_not_sleep"),row(header,
                        budget.format(format_args!("{name} sets SpacemanDMM_should_not_sleep but calls blocking proc {called}"))?,notes),origin.clone(),policy, &budget)?;
                } else {
                    // Derive the direct-only override relation by BORROWING the
                    // existing original parent chain. No retained adjacency copy.
                    for child in self.bodies.iter() {
                        checkpoint()?;
                        if child.blocking.is_empty() || child.procedure.name == SymbolId::of("New")
                        {
                            continue;
                        }
                        if !source_child_overrides_target(
                            self,
                            input,
                            resolver,
                            child,
                            EffectTarget::Source(id),
                            &budget,
                        )? {
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
                        emit(&mut output,input,Some("must_not_sleep"),row(header,
                            budget.format(format_args!("{name} calls {called} which has override child proc that sleeps {}",display(input,child.procedure, &budget)?))?,notes),origin.clone(),policy, &budget)?;
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
        }
        Ok(output)
    }
}
