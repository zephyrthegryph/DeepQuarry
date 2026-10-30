//! Whole rel_write_undeclared policy over the original native owner/raw views.
use crate::{
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::{Run, Sink},
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{collections::BTreeMap, path::Path};
pub struct CapturedRelWrite<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> CapturedRelWrite<'a> {
    pub fn capture(
        root: &Path,
        inputs: &'a PolicyInputs,
        config: Configuration<'_>,
    ) -> Result<Self, String> {
        Ok(Self {
            raw: CapturedRawPolicy::capture(root, inputs, config)?,
            inputs,
        })
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        BorrowedRelWrite::capture(&self.raw, self.inputs)?.scan(checkpoint)
    }
}
pub struct BorrowedRelWrite<'a> {
    raw: &'a CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> BorrowedRelWrite<'a> {
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
    pub fn scan(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, String> {
        checkpoint()?;
        self.intact()?;
        let scope = self.raw.scopes.for_lint("rel_write_undeclared", "");
        let files = self.raw.tree.select(&crate::tree::CODE_DM);
        let index = crate::relation_decl_policy::declarations(files.clone(), &mut checkpoint)?;
        let rels = &index.relations;
        let mut remaining = (64usize * 1024 * 1024)
            .checked_sub(index.retained_admission)
            .ok_or("relation index admission overflow")?;
        self.intact()?;
        let native = dm_analysis::rel_write_native::findings(
            self.inputs,
            &self.raw.tree.root,
            rels,
            |f| scope.exempt(f),
            &mut remaining,
            &mut checkpoint,
        )
        .map_err(|e| e.0)?;
        let mut found = BTreeMap::new();
        for row in native {
            found.insert((row.rel, row.line, row.var), row.message);
        }
        // Exact old second pass: text path form, first pair only, no private verbs.
        let pattern = crate::pat!(
            r"\b(rel_(?:set|add|remove|clear|take|take_all|move))\(\s*[^,]+,\s*nameof\(\s*(/[\w/]+?)/?::(\w+)\s*\)"
        );
        for f in files {
            checkpoint()?;
            self.intact()?;
            if scope.exempt(&f.rel) {
                continue;
            }
            let code = f.code();
            self.intact()?;
            for (i, line) in code.lines().enumerate() {
                checkpoint()?;
                for c in pattern.captures_iter(line) {
                    let (verb, ty, var) = (c.s(1), c.s(2), c.s(3));
                    if dm_analysis::rel_write_native::declared(
                        self.inputs.archive().tree(),
                        &rels,
                        Some(ty),
                        var,
                    )
                    .map_err(|e| e.0)?
                    {
                        continue;
                    }
                    let coordinate = f
                        .rel
                        .len()
                        .checked_add(var.len())
                        .and_then(|n| n.checked_mul(4))
                        .and_then(|n| n.checked_add(256))
                        .ok_or("relation raw finding coordinate overflow")?;
                    remaining = remaining
                        .checked_sub(coordinate)
                        .ok_or("relation raw finding coordinate budget exceeded")?;
                    let key = (f.rel.clone(), i + 1, var.to_owned());
                    if !found.contains_key(&key) {
                        if found.len() >= MAX_FIXTURE_SITES {
                            return Err("rel_write_undeclared exceeds finding admission".into());
                        }
                        let message = dm_analysis::rel_write_native::detail(
                            self.inputs,
                            &self.raw.tree.root,
                            Some(ty),
                            var,
                            verb,
                            false,
                            &mut remaining,
                        )
                        .map_err(|e| e.0)?;
                        found.insert(key, message);
                    }
                }
            }
            self.intact()?;
        }
        let mut rows = found
            .into_iter()
            .map(|((rel, line, _), message)| (rel, line, message))
            .collect::<Vec<_>>();
        rows.sort();
        let mut sink = Sink::new();
        for (rel, line, message) in rows {
            sink.site_in_msg("undeclared", &rel, line, message)
        }
        checkpoint()?;
        self.intact()?;
        Ok(RawRun {
            name: "rel_write_undeclared".into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}
#[cfg(test)]
#[path = "captured_rel_write_tests.rs"]
mod tests;
