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
        if rows.iter().any(|row| row.part.is_some()) {
            return Err(crate::captured_marker_rows::DECLARE_PARTS_UNSUPPORTED.into());
        }
        let engine_sources = captured.engine_sources;
        self.budget.charge(
            rows.len()
                .checked_mul(std::mem::size_of::<Marker<'_>>())
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
        for m in &rows {
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
