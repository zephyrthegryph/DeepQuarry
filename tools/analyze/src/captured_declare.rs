//! Whole declare generator over SAME authenticated RAW_FILE views.
use crate::{
    captured_generator_budget::Budget,
    captured_raw_policy::CapturedRawPolicy,
    declare_policy::{Input, Marker, MARKERS},
    reactive_original_source::ReadSource,
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
struct DeclareControl<'a> {
    budget: &'a Budget,
    checkpoint: &'a mut dyn FnMut() -> Result<(), String>,
}
impl crate::key_policy_control::Control for DeclareControl<'_> {
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
        "Declare policy capacity overflow".into()
    }
    fn allocation_failed(&mut self) -> String {
        self.budget.deny();
        "Declare policy allocation refused".into()
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
        // The raw roster and the certified typed source borrow the very same
        // current capture. Resolving original formals does not request bodies.
        let source = ReadSource::native(self.inputs, &self.raw.tree.root, &self.budget)?;
        let input = Input {
            markers: &views,
            part_features: &part_features,
            engine_sources: &engine_sources,
            budget: Some(self.budget.clone()),
            poll: None,
        };
        let mut control = DeclareControl { budget: &self.budget, checkpoint: &mut checkpoint };
        let out = crate::declare_policy::generate_with_relation_types(&input, &mut control,
            &mut |owner, var| source.variable_type(owner, var))?;
        self.budget.require()?;
        intact(self.raw)?;
        checkpoint()?;
        Ok(out)
    }
}
