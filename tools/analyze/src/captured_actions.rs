//! Whole ACTION policy from the SAME original captured RAW_FILE views.
//! Explicit bounded roster only; no file installation, parser/model or IO.
use crate::{
    actions_policy::Builder, captured_generator_budget::Budget,
    captured_raw_policy::CapturedRawPolicy, sparse_slots_policy::Output,
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{
    collections::{BTreeMap, HashMap},
    sync::Arc,
};
pub const FULL_WORKSPACE_COVERAGE: bool = false;
pub struct BorrowedActions<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
    order: HashMap<String, usize>,
    budget: Arc<Budget>,
}
fn intact(raw: &CapturedRawPolicy) -> Result<(), String> {
    raw.tree.captured_violation().map_or(Ok(()), Err)
}
impl<'a> BorrowedActions<'a> {
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
                .ok_or("actions source roster overflow")?,
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
                    &["ACTION"],
                ) {
                    count = count.checked_add(1).ok_or("actions marker overflow")?;
                    if count > crate::captured_raw_policy::MAX_FIXTURE_SITES {
                        return Err("actions marker count exceeds captured scope budget".into());
                    }
                    self.budget.split_args(m.close - m.open)?;
                    let args =
                        crate::raw_marker_policy::split_args(&marker.as_str()[m.open + 1..m.close]);
                    builder.push(
                        &file.rel,
                        u32::try_from(line + 1).map_err(|_| "actions line overflow")?,
                        &args,
                    )?;
                }
                offset = offset
                    .checked_add(text.len() + 1)
                    .ok_or("actions offset overflow")?;
            }
            intact(self.raw)?;
        }
        let prepared = builder.prepare(&mut checkpoint)?;
        self.budget.require()?;
        intact(self.raw)?;
        let mut requested: BTreeMap<String, BTreeMap<String, bool>> = BTreeMap::new();
        for (notice, var) in prepared.requests() {
            checkpoint()?;
            if !requested
                .get(notice)
                .is_some_and(|vars| vars.contains_key(var))
            {
                self.budget.charge(
                    notice
                        .len()
                        .checked_add(var.len())
                        .and_then(|n| n.checked_mul(2))
                        .and_then(|n| n.checked_add(512))
                        .ok_or("actions requested membership overflow")?,
                )?;
                requested
                    .entry(notice.to_owned())
                    .or_default()
                    .insert(var.to_owned(), false);
            }
        }
        // Names are only the requested notice projection, not another type or
        // ownership model. Pre-admit cloned keys and vector before allocation.
        self.budget.charge(
            requested
                .keys()
                .try_fold(256usize, |n, k| {
                    n.checked_add(k.len().checked_mul(2)?)?
                        .checked_add(3 * std::mem::size_of::<String>())
                })
                .ok_or("actions notice selector overflow")?,
        )?;
        let names: Vec<String> = requested.keys().cloned().collect();
        for file in &files {
            checkpoint()?;
            intact(self.raw)?;
            self.budget.require()?;
            if names.is_empty() || file.rel == "code/engine/_generated/actions.dm" {
                continue;
            }
            self.budget.charge(
                file.raw()
                    .text
                    .len()
                    .checked_mul(4)
                    .and_then(|n| n.checked_add(names.len().checked_mul(8)?))
                    .and_then(|n| n.checked_add(4096))
                    .ok_or("actions raw matcher temporary overflow")?,
            )?;
            let code = file.code();
            intact(self.raw)?;
            let selected: Vec<bool> = names
                .iter()
                .map(|name| crate::actions_policy::file_mentions_notice(&code.text, name))
                .collect();
            if !selected.iter().any(|yes| *yes) {
                continue;
            }
            let clean = file.clean();
            intact(self.raw)?;
            let mut aborted = None;
            crate::raw_type_vars_policy::visit(&clean.text, |ty, var| {
                if aborted.is_some() {
                    return;
                }
                if let Err(e) = checkpoint() {
                    aborted = Some(e);
                    return;
                }
                if let Ok(index) = names.binary_search_by(|n| n.as_str().cmp(ty)) {
                    if selected[index] {
                        if let Some(found) =
                            requested.get_mut(ty).and_then(|vars| vars.get_mut(var))
                        {
                            *found = true;
                        }
                    }
                }
            });
            if let Some(e) = aborted {
                return Err(e);
            }
            intact(self.raw)?;
        }
        checkpoint()?;
        self.budget.require()?;
        intact(self.raw)?;
        let output = prepared.finish(
            |notice, var| {
                requested
                    .get(notice)
                    .and_then(|v| v.get(var))
                    .copied()
                    .unwrap_or(false)
            },
            &mut checkpoint,
        )?;
        self.budget.require()?;
        intact(self.raw)?;
        checkpoint()?;
        Ok(output)
    }
}
