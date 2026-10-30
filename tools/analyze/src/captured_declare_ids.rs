//! Whole declare_ids generator over SAME authenticated RAW_FILE views.
use crate::{
    captured_generator_budget::Budget,
    captured_raw_policy::CapturedRawPolicy,
    declare_ids_policy::{Builder, MARKERS},
    sparse_slots_policy::Output,
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{collections::HashMap, sync::Arc};
pub const FULL_WORKSPACE_COVERAGE: bool = false;
pub struct BorrowedDeclareIds<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
    order: HashMap<String, usize>,
    budget: Arc<Budget>,
}
fn intact(raw: &CapturedRawPolicy) -> Result<(), String> {
    raw.tree.captured_violation().map_or(Ok(()), Err)
}
impl<'a> BorrowedDeclareIds<'a> {
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
        self.budget.charge(
            self.raw
                .tree
                .files
                .len()
                .checked_mul(256)
                .and_then(|n| n.checked_add(4096))
                .ok_or("declare_ids roster overflow")?,
        )?;
        let mut files = self.raw.tree.select(&crate::tree::CODE_DM);
        files.sort_by(|a, b| {
            (
                self.order.get(&a.rel).copied().unwrap_or(usize::MAX),
                &a.rel,
            )
                .cmp(&(
                    self.order.get(&b.rel).copied().unwrap_or(usize::MAX),
                    &b.rel,
                ))
        });
        let mut builder = Builder::captured(self.budget.clone());
        let mut count = 0usize;
        for file in &files {
            checkpoint()?;
            self.budget.require()?;
            intact(self.raw)?;
            if file.rel != "code/engine/_generated/ids.dm" {
                let mut error = None;
                crate::declare_ids_policy::visit_defines(file.text(), |name| {
                    if error.is_none() {
                        if let Err(e) = checkpoint().and_then(|_| builder.define(name)) {
                            error = Some(e);
                        }
                    }
                });
                if let Some(e) = error {
                    return Err(e);
                }
            }
            let marker = file.marker();
            intact(self.raw)?;
            let mut offset = 0usize;
            for (line, text) in marker.as_str().split('\n').enumerate() {
                checkpoint()?;
                self.budget.require()?;
                if let Some(m) = crate::raw_marker_policy::statement_marker(
                    marker.as_str(),
                    offset,
                    text,
                    MARKERS,
                ) {
                    count += 1;
                    if count > crate::captured_raw_policy::MAX_FIXTURE_SITES {
                        return Err("declare_ids marker count exceeds captured scope".into());
                    }
                    let block_end = if !text.starts_with(char::is_whitespace)
                        && ["CAPABILITY_DEF", "STATE_GRAPH"].contains(&m.name)
                    {
                        crate::raw_marker_policy::block_extent(marker.as_str(), m.close)
                    } else {
                        None
                    };
                    let end = block_end.unwrap_or(m.close);
                    let width = end
                        .checked_sub(m.open)
                        .ok_or("declare_ids marker range overflow")?;
                    // Original block_body owns one width-sized Vec/String, split_args owns its
                    // documented3N slots+4L temporary. Admit both before either construction.
                    self.budget.charge(
                        width
                            .checked_mul(4)
                            .and_then(|n| n.checked_add(256))
                            .ok_or("declare_ids block temporary overflow")?,
                    )?;
                    self.budget.split_args(width)?;
                    let body = match block_end {
                        Some(end) => crate::raw_marker_policy::block_body(
                            marker.as_str(),
                            m.open + 1,
                            m.close,
                            end,
                        ),
                        None => marker.as_str()[m.open + 1..m.close].to_owned(),
                    };
                    let args = crate::raw_marker_policy::split_args(&body);
                    builder.push(
                        m.name,
                        &file.rel,
                        u32::try_from(line + 1).map_err(|_| "declare_ids line overflow")?,
                        &args,
                    )?;
                }
                offset = offset
                    .checked_add(text.len() + 1)
                    .ok_or("declare_ids marker offset overflow")?;
            }
            intact(self.raw)?;
        }
        let out = builder.finish_checked(&mut checkpoint)?;
        self.budget.require()?;
        intact(self.raw)?;
        checkpoint()?;
        Ok(out)
    }
}
