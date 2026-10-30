//! Whole stored_refs policy on ORIGINAL native declarations/body graph/raw views.
//! Qualification and local-array authority gaps fail atomically, never clean.
use crate::{
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::{Run, Sink},
};
use dm_analysis::{policy_inputs::PolicyInputs, untyped::StoredPolicy};
use std::{collections::HashSet, path::Path};
pub struct CapturedStoredRefs<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> CapturedStoredRefs<'a> {
    pub fn capture(
        root: &Path,
        inputs: &'a PolicyInputs,
        configuration: Configuration<'_>,
    ) -> Result<Self, String> {
        Ok(Self {
            raw: CapturedRawPolicy::capture(root, inputs, configuration)?,
            inputs,
        })
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        BorrowedStoredRefs::capture(&self.raw, self.inputs)?.scan(checkpoint)
    }
}
pub struct BorrowedStoredRefs<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> BorrowedStoredRefs<'a> {
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Result<Self, String> {
        raw.validate_current_raw_roster(inputs)?;
        Ok(Self { raw, inputs })
    }
    fn intact(&self) -> Result<(), String> {
        match self.raw.tree.captured_violation() {
            Some(e) => Err(e),
            None => Ok(()),
        }
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        self.scan_with::<dm_analysis::policy_body_demand::Compatibility>(checkpoint)
            .map_err(|e| e.0)
    }
    pub fn scan_checked(
        &self,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, dm_analysis::policy_body_demand::PolicyFailure> {
        self.scan_with::<dm_analysis::policy_body_demand::Checked>(checkpoint)
    }
    fn scan_with<D: dm_analysis::policy_body_demand::Demand>(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, D::Error> {
        checkpoint()?;
        self.intact()?;
        let facts = crate::stored_refs_policy::SourceFacts::capture(self.raw, &mut checkpoint)?;
        self.intact()?;
        let scope = self.raw.scopes.for_lint("stored_refs", "");
        let policy = StoredPolicy {
            exempt_types: scope.list("exempt_types"),
            registry: &facts.relations.registry,
            transient_types: scope.list("transient_types"),
            work_queues: scope.list("work_queues"),
            relations: &facts.relations.relations,
            init_only: &facts.init_only,
            has_schema: &|t, v| facts.schemas.has(t, v),
        };
        let mut remaining = facts.remaining;
        let rows = dm_analysis::untyped::stored_findings_with::<D>(
            self.inputs,
            &self.raw.tree.root,
            &policy,
            |f| scope.exempt(f),
            &mut remaining,
            &mut checkpoint,
        )?;
        let key_budget = rows
            .iter()
            .try_fold(0usize, |total, row| {
                row.rule
                    .len()
                    .checked_add(row.rel.len())
                    .and_then(|n| n.checked_mul(4))
                    .and_then(|n| n.checked_add(256))
                    .and_then(|n| total.checked_add(n))
            })
            .ok_or("stored emitted-key overflow")?;
        remaining = remaining
            .checked_sub(key_budget)
            .ok_or("stored emitted-key budget exceeded before allocation")?;
        let mut sink = Sink::bounded(MAX_FIXTURE_SITES, remaining);
        let mut emitted = HashSet::new();
        for row in rows {
            checkpoint()?;
            self.intact()?;
            if !row.rel.starts_with("code/") || scope.exempt(&row.rel) {
                continue;
            }
            if !emitted.insert((row.rule, row.rel.clone(), row.line)) {
                continue;
            }
            if self
                .raw
                .tree
                .get(&row.rel)
                .is_some_and(|f| sink.allowed(f, row.line, "stored_refs"))
            {
                continue;
            }
            sink.site_decl(row.rule, &row.rel, row.line, row.message, row.ident);
            if let Some(e) = sink.admission_error() {
                return Err(e.into());
            }
        }
        checkpoint()?;
        self.intact()?;
        if let Some(e) = sink.admission_error() {
            return Err(e.into());
        }
        Ok(RawRun {
            name: "stored_refs".into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}
#[cfg(test)]
#[path = "captured_stored_refs_tests.rs"]
mod tests;
