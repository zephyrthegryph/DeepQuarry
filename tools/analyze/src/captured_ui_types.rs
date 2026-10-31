//! Whole ui_types generator over SAME authenticated RAW_FILE views.
use crate::{
    captured_generator_budget::Budget,
    captured_raw_policy::CapturedRawPolicy,
    declare_policy::Marker,
    ui_types_policy::{Input, MARKERS},
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{collections::HashMap, sync::Arc};
pub const FULL_WORKSPACE_COVERAGE: bool = false;
pub struct BorrowedUiTypes<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
    order: HashMap<String, usize>,
    budget: Arc<Budget>,
}
fn intact(raw: &CapturedRawPolicy) -> Result<(), String> {
    raw.tree.captured_violation().map_or(Ok(()), Err)
}
impl<'a> BorrowedUiTypes<'a> {
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
    ) -> Result<crate::ui_types_policy::Files, String> {
        checkpoint()?;
        self.budget.require()?;
        intact(self.raw)?;
        self.raw.validate_current_raw_roster(self.inputs)?;
        let captured = crate::captured_marker_rows::collect(
            self.raw,
            &self.order,
            &self.budget,
            MARKERS,
            true,
            &mut checkpoint,
        )?;
        let rows = captured.markers;
        self.budget.charge(
            rows.len()
                .checked_mul(std::mem::size_of::<Marker<'_>>())
                .ok_or("declare borrowed roster overflow")?,
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
        let input=Input{markers:&views,budget:Some(self.budget.clone()),poll:None};
        let out=crate::ui_types_policy::generate_with(&input,&mut checkpoint)?;
        drop(input);
        self.budget.require()?;
        intact(self.raw)?;
        checkpoint()?;
        Ok(out)
    }
}
