//! Complete STAT generator policy over the existing original RAW_FILE owners.
//! Explicit admitted captured roster only; no source reads or generated-file installation.
use crate::{
    captured_generator_budget::Budget, captured_raw_policy::CapturedRawPolicy,
    sparse_slots_policy::Output, stats_policy::Builder,
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{
    collections::{BTreeMap, HashMap},
    sync::Arc,
};
pub const FULL_WORKSPACE_COVERAGE: bool = false;
pub struct BorrowedStats<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
    order: HashMap<String, usize>,
    budget: Arc<Budget>,
}
fn intact(raw: &CapturedRawPolicy) -> Result<(), String> {
    raw.tree.captured_violation().map_or(Ok(()), Err)
}
impl<'a> BorrowedStats<'a> {
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
                .ok_or("stats file roster accounting overflow")?,
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
            intact(self.raw)?;
            self.budget.require()?;
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
                    &["STAT"],
                ) {
                    count = count.checked_add(1).ok_or("stats marker count overflow")?;
                    if count > crate::captured_raw_policy::MAX_FIXTURE_SITES {
                        return Err("stats marker count exceeds captured scope budget".into());
                    }
                    self.budget.split_args(m.close - m.open)?;
                    let args =
                        crate::raw_marker_policy::split_args(&marker.as_str()[m.open + 1..m.close]);
                    builder.push(
                        &file.rel,
                        u32::try_from(line + 1).map_err(|_| "stats line overflow")?,
                        &args,
                    );
                    self.budget.require()?;
                }
                offset = offset
                    .checked_add(text.len() + 1)
                    .ok_or("stats marker offset overflow")?;
            }
            intact(self.raw)?;
        }
        // Only requested lexical-ancestor/name membership is retained. This is
        // not a copied source variable table or native inheritance projection.
        let mut requested: BTreeMap<String, BTreeMap<String, bool>> = BTreeMap::new();
        for (mut ty, name) in builder.requests() {
            loop {
                checkpoint()?;
                if !requested.get(ty).is_some_and(|v| v.contains_key(name)) {
                    self.budget.charge(
                        ty.len()
                            .checked_add(name.len())
                            .and_then(|n| n.checked_mul(2))
                            .and_then(|n| n.checked_add(512))
                            .ok_or("stats requested membership overflow")?,
                    )?;
                    requested
                        .entry(ty.to_owned())
                        .or_default()
                        .insert(name.to_owned(), false);
                }
                match ty.rfind('/') {
                    Some(0) | None => break,
                    Some(i) => ty = &ty[..i],
                }
            }
        }
        for file in &files {
            checkpoint()?;
            intact(self.raw)?;
            self.budget.require()?;
            // The old generator excludes its own PREVIOUS raw output only for
            // membership. Its marker-selection policy remains unchanged.
            if file.rel.ends_with("_generated/stats.dm") || requested.is_empty() {
                continue;
            }
            self.budget.charge(
                file.raw()
                    .text
                    .len()
                    .checked_mul(4)
                    .and_then(|n| n.checked_add(4096))
                    .ok_or("stats raw matcher temporary overflow")?,
            )?;
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
                if let Some(found) = requested.get_mut(ty).and_then(|vars| vars.get_mut(var)) {
                    *found = true;
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
        let out = builder.finish_checked(
            |ty, name| {
                crate::stats_policy::declares_var(
                    |ty, name| {
                        requested
                            .get(ty)
                            .and_then(|v| v.get(name))
                            .copied()
                            .unwrap_or(false)
                    },
                    ty,
                    name,
                )
            },
            &mut checkpoint,
        )?;
        self.budget.require()?;
        intact(self.raw)?;
        checkpoint()?;
        Ok(out)
    }
}
