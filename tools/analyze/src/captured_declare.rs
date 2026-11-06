//! Whole declare generator over SAME authenticated RAW_FILE views.
use crate::{
    captured_generator_budget::Budget,
    captured_raw_policy::CapturedRawPolicy,
    declare_policy::{Input, Marker, MARKERS},
    sparse_slots_policy::Output,
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{collections::HashMap, sync::Arc};
pub const FULL_WORKSPACE_COVERAGE: bool = false;
pub struct BorrowedDeclare<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
    order: HashMap<String, usize>,
    budget: Arc<Budget>,
}
struct RelationPreflight<'a> {
    budget: &'a Budget,
    checkpoint: &'a mut dyn FnMut() -> Result<(), String>,
}
impl crate::key_policy_control::Control for RelationPreflight<'_> {
    type Error = String;
    const CHECKED: bool = true;
    fn checkpoint(&mut self) -> Result<(), String> {
        self.budget.require()?;
        (self.checkpoint)()?;
        self.budget.require()
    }
    fn reserve(&mut self, bytes: usize) -> Result<(), String> { self.budget.charge(bytes) }
    fn overflow(&mut self) -> String {
        self.budget.deny();
        "Declare implicit relation preflight capacity overflow".into()
    }
    fn allocation_failed(&mut self) -> String {
        self.budget.deny();
        "Declare implicit relation preflight allocation refused".into()
    }
}
fn intact(raw: &CapturedRawPolicy) -> Result<(), String> {
    raw.tree.captured_violation().map_or(Ok(()), Err)
}
impl<'a> BorrowedDeclare<'a> {
    pub fn capture(
        raw: &'a CapturedRawPolicy,
        inputs: &'a PolicyInputs,
        budget: Arc<Budget>,
    ) -> Result<Self, String> {
        let order = crate::captured_sparse_slots::captured_order(raw, inputs, &budget)?;
        Ok(Self {
            raw,
            inputs,
            order,
            budget,
        })
    }
    pub fn generate(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Output, String> {
        checkpoint()?;
        self.budget.require()?;
        intact(self.raw)?;
        self.raw.validate_current_raw_roster(self.inputs)?;
        let captured = crate::captured_marker_rows::collect(
            self.raw,
            &self.order,
            &self.budget,
            MARKERS,
            false,
            &mut checkpoint,
        )?;
        let rows = captured.markers;
        let engine_sources = captured.engine_sources;
        self.budget.charge(
            rows.len()
                .checked_mul(std::mem::size_of::<Marker<'_>>() + std::mem::size_of::<Option<&str>>())
                .ok_or_else(|| {
                    self.budget.deny();
                    "declare borrowed roster overflow"
                })?,
        )?;
        let mut views = Vec::new();
        views.try_reserve_exact(rows.len()).map_err(|_| {
            self.budget.deny();
            "declare borrowed roster allocation"
        })?;
        let mut part_features = Vec::new();
        part_features.try_reserve_exact(rows.len()).map_err(|_| {
            self.budget.deny();
            "declare part roster allocation"
        })?;
        for m in &rows {
            checkpoint()?;
            part_features.push(m.part.as_deref());
            views.push(Marker {
                name: &m.name,
                rel: &m.rel,
                line: m.line,
                body: &m.body,
                args: &m.args,
                body_offset: m.body_offset,
                line_starts: &m.line_starts,
            });
        }
        {
            let input = Input {
                markers: &views, part_features: &part_features, engine_sources: &engine_sources,
                budget: None, poll: None,
            };
            let mut preflight = RelationPreflight { budget: &self.budget, checkpoint: &mut checkpoint };
            crate::declare_policy::visit_rel_var_type_candidates(&mut preflight, &input, |_, _, _| {
                Err(crate::declare_policy::REL_VAR_TYPES_UNAVAILABLE.into())
            })?;
        }
        let stopped = std::cell::RefCell::new(None);
        let callback = std::cell::RefCell::new(&mut checkpoint);
        let poll = || {
            if stopped.borrow().is_some() {
                return false;
            }
            match (callback.borrow_mut())() {
                Ok(()) => true,
                Err(e) => {
                    *stopped.borrow_mut() = Some(e);
                    false
                }
            }
        };
        let input = Input {
            markers: &views,
            part_features: &part_features,
            engine_sources: &engine_sources,
            budget: Some(self.budget.clone()),
            poll: Some(&poll),
        };
        let out = crate::declare_policy::generate(&input, || {
            if poll() {
                Ok(())
            } else {
                Err(stopped
                    .borrow_mut()
                    .take()
                    .unwrap_or_else(|| "declare operation stopped".into()))
            }
        })?;
        drop(input);
        drop(callback);
        self.budget.require()?;
        intact(self.raw)?;
        checkpoint()?;
        Ok(out)
    }
}
