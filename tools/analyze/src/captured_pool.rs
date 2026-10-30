//! Whole cross-file pool policy on original captured raw owners, no IO/model.
use crate::{
    captured_generator_budget::{Budget, BudgetedText},
    captured_raw_policy::{CapturedRawPolicy, RawRun},
    lint::{Run, Site},
    pool_policy,
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{collections::BTreeSet, sync::Arc};
pub const FULL_WORKSPACE_COVERAGE: bool = false;
pub struct BorrowedPool<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
fn intact(raw: &CapturedRawPolicy) -> Result<(), String> {
    raw.tree.captured_violation().map_or(Ok(()), Err)
}
fn own(b: &Budget, text: &str) -> Result<String, String> {
    let mut s = String::new();
    if !b.string(&mut s, text) {
        return Err("pool output text retention denied".into());
    }
    Ok(s)
}
impl<'a> BorrowedPool<'a> {
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Result<Self, String> {
        raw.validate_current_raw_roster(inputs)?;
        Ok(Self { raw, inputs })
    }
    pub fn scan(
        &self,
        budget: Arc<Budget>,
        remaining_sites: usize,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, String> {
        use std::fmt::Write;
        checkpoint()?;
        budget.require()?;
        intact(self.raw)?;
        self.raw.validate_current_raw_roster(self.inputs)?;
        let scope = self.raw.scopes.for_lint("pool", "");
        budget.charge(
            self.raw
                .tree
                .files
                .len()
                .checked_mul(256)
                .and_then(|n| n.checked_add(4096))
                .ok_or("pool source roster overflow")?,
        )?;
        // Exact Cx.files generic exemption applies BEFORE both index and judge.
        // The separate named list below suppresses findings only, not facts.
        let files = self
            .raw
            .tree
            .select(&crate::tree::CODE_DM)
            .into_iter()
            .filter(|f| !scope.exempt(&f.rel))
            .collect::<Vec<_>>();
        let mut pooled: BTreeSet<String> = BTreeSet::new();
        for f in &files {
            checkpoint()?;
            intact(self.raw)?;
            let facts = pool_policy::facts_of(f, Some(&budget), &mut checkpoint)?;
            for ty in facts.pooled {
                checkpoint()?;
                budget.charge(
                    ty.len()
                        .checked_mul(2)
                        .and_then(|n| n.checked_add(512))
                        .ok_or("pool merged fact retention overflow")?,
                )?;
                pooled.insert(ty);
            }
            intact(self.raw)?;
        }
        let mut sites = Vec::new();
        for f in &files {
            checkpoint()?;
            intact(self.raw)?;
            pool_policy::judge(
                f,
                &pooled,
                scope.list("exempt_prefixes"),
                Some(&budget),
                &mut checkpoint,
                |rule, line, args| {
                    if sites.len()
                        >= remaining_sites.min(crate::captured_raw_policy::MAX_FIXTURE_SITES)
                    {
                        budget.deny();
                        return Err("pool complete result exceeds remaining site admission".into());
                    }
                    if !budget.row(&mut sites) {
                        return Err("pool output row retention denied".into());
                    }
                    let rule = own(&budget, pool_policy::RULE_NAMES[rule as usize])?;
                    let rel = own(&budget, &f.rel)?;
                    let mut msg = BudgetedText::new(&budget);
                    msg.write_fmt(args)
                        .map_err(|_| "pool output message denied")?;
                    sites.push(Site {
                        rule,
                        rel,
                        line,
                        msg: msg.finish()?,
                        key: String::new(),
                        ident: String::new(),
                    });
                    Ok(())
                },
            )?;
            intact(self.raw)?;
        }
        let mut note = BudgetedText::new(&budget);
        write!(note, "pool_lint: {} problem(s)", sites.len())
            .map_err(|_| "pool summary retention denied")?;
        let mut notes = Vec::new();
        if !budget.row(&mut notes) {
            return Err("pool note retention denied".into());
        }
        notes.push(note.finish()?);
        let name = own(&budget, "pool")?;
        checkpoint()?;
        budget.require()?;
        intact(self.raw)?;
        Ok(RawRun {
            name,
            run: Run { sites, notes },
            allow_used: Vec::new(),
        })
    }
}
