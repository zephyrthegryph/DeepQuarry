//! Complete base_var/list_init candidate cohort with schema hints and all
//! base_vars ALLOW questions. Does not emit hot_home/records_data_only sites.
use crate::{
    base_var_candidate_policy::{classify, file_facts, raw_allow_lines, VarView},
    base_var_hot_policy::{hot_problems, BASE_TYPES, HOT_TABLE, SCOPES_FILE},
    captured_base_var_hot_policy::NativeBaseVarFacts,
    captured_raw_policy::{CapturedRawPolicy, Configuration, RawRun, MAX_FIXTURE_SITES},
    lint::{Run, Sink},
    tree::{Select, CODE_DM},
    value_schema_policy::SchemaHints,
};
use dm_analysis::policy_inputs::PolicyInputs;
use std::{
    collections::{BTreeSet, HashMap, HashSet},
    path::Path,
};
pub struct CapturedBaseVarCandidates<'a> {
    raw: CapturedRawPolicy,
    inputs: &'a PolicyInputs,
}
impl<'a> CapturedBaseVarCandidates<'a> {
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
        BorrowedBaseVarCandidates::capture(&self.raw, self.inputs)?.scan(checkpoint)
    }
}
/// Host can reuse its existing captured source-policy owner, including the
/// code/marker OnceLocks. This facade owns no Tree or source projection.
pub struct BorrowedBaseVarCandidates<'a> {
    raw: &'a CapturedRawPolicy,
    facts: NativeBaseVarFacts<'a>,
}
impl<'a> BorrowedBaseVarCandidates<'a> {
    pub fn capture(raw: &'a CapturedRawPolicy, inputs: &'a PolicyInputs) -> Result<Self, String> {
        Ok(Self {
            raw,
            facts: NativeBaseVarFacts::capture(raw, inputs)?,
        })
    }
    pub fn scan(&self, checkpoint: impl FnMut() -> Result<(), String>) -> Result<RawRun, String> {
        self.scan_selected(checkpoint, false)
    }
    /// Composition adds hot-home findings while this same captured homes and
    /// declaration set is live; the raw annotation phase is never repeated.
    pub(crate) fn scan_for_composition(
        &self,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<RawRun, String> {
        self.scan_selected(checkpoint, true)
    }
    fn scan_selected(
        &self,
        checkpoint: impl FnMut() -> Result<(), String>,
        include_hot: bool,
    ) -> Result<RawRun, String> {
        let previous = crate::dm::sys::take_recorded();
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            self.scan_inner(checkpoint, include_hot)
        }));
        // A policy panic must not leak partially recorded annotation use into
        // the next query on this worker thread. Preserve caller-owned state.
        let _ = crate::dm::sys::take_recorded();
        crate::dm::sys::restore_recorded(previous);
        match result {
            Ok(result) => result,
            Err(_) => Err(self.raw.tree.captured_violation().unwrap_or_else(|| {
                "captured base-var candidate policy panicked; findings discarded".into()
            })),
        }
    }
    fn scan_inner(
        &self,
        mut checkpoint: impl FnMut() -> Result<(), String>,
        include_hot: bool,
    ) -> Result<RawRun, String> {
        checkpoint()?;
        let scope = self.raw.scopes.for_lint("base_vars", "");
        let select = Select {
            roots: &[("code", "dm")],
            hidden: true,
        };
        let all = self.raw.tree.select(&select);
        let mut homes = HashSet::new();
        let mut globals = BTreeSet::new();
        for file in &all {
            checkpoint()?;
            let facts = file_facts(
                file,
                scope.list("base_var_home_macros"),
                scope.list("base_var_home_relations"),
            );
            homes.extend(facts.homes);
            globals.extend(facts.singles);
        }
        globals.remove("/datum");
        let singletons = globals.into_iter().collect::<HashSet<_>>();
        let mut hints = SchemaHints::default();
        for file in self.raw.tree.select(&CODE_DM) {
            checkpoint()?;
            hints.read(file);
        }
        let declarations = self.facts.declarations(BASE_TYPES)?;
        let by_rel = all
            .iter()
            .filter(|file| !file.hidden)
            .map(|file| (file.rel.as_str(), *file))
            .collect::<HashMap<_, _>>();
        let hot = scope.table(HOT_TABLE).cloned().unwrap_or_default();
        let mut sink = Sink::new();
        sink.note(format!(
            "base_vars: {} hot base vars homed by base_var_home_hot",
            hot.len()
        ));
        crate::dm::pylines::recorded_into(&mut sink, || {
            // Same first phase and owner grouping as legacy facts_of, including
            // annotations which no typed declaration subsequently selects.
            for file in &all {
                for line in raw_allow_lines(file) {
                    crate::dm::sys::kept_recorded(file, line, "base_vars");
                }
            }
            let mut sites = Vec::new();
            for row in &declarations {
                checkpoint()?;
                let Some(file) = by_rel.get(row.relative) else {
                    continue;
                };
                let vtype = row.native.declared_type_text().map_err(|e| e.0)?;
                let view = VarView {
                    rel: row.relative,
                    line: row.line,
                    owner: row.owner,
                    name: row.name,
                    vtype: &vtype,
                    base: row.native.base,
                    list_init: row.native.list_init,
                };
                let Some(checked) = classify(
                    view,
                    file,
                    &singletons,
                    scope.list("list_init_exempt_prefixes"),
                    scope.list("list_init_exempt_files"),
                    &homes,
                    &hot,
                    scope.list("base_var_home_types"),
                ) else {
                    continue;
                };
                let ident = format!("{}::{}", row.owner, row.name);
                if checked.base {
                    let msg = if hints.has(row.owner, row.name) {
                        crate::value_schema_policy::hint_message(&ident)
                    } else {
                        String::new()
                    };
                    sites.push(("base_var", row.relative, row.line, msg, ident.clone()));
                }
                if checked.list {
                    sites.push(("list_init", row.relative, row.line, String::new(), ident));
                }
            }
            Ok::<_, String>(sites)
        })
        .map(|sites| {
            for (rule, rel, line, msg, ident) in sites {
                sink.site_decl(rule, rel, line as usize, msg, ident);
            }
        })?;
        if include_hot {
            // Legacy builds this set before hidden/ALLOW/home filtering.
            let declared = declarations
                .iter()
                .filter(|row| row.native.base)
                .map(|row| (row.owner.to_string(), row.name.to_string()))
                .collect::<HashSet<_>>();
            let ceiling = scope
                .list("hot_ceiling")
                .first()
                .and_then(|value| value.trim().parse().ok());
            for (key, msg) in hot_problems(&hot, Some(&declared), &homes, ceiling) {
                sink.site_decl("hot_home", SCOPES_FILE, 1, msg, format!("hot::{key}"));
            }
        }
        checkpoint()?;
        if let Some(error) = self.raw.tree.captured_violation() {
            return Err(error);
        }
        if sink.sites.len() > MAX_FIXTURE_SITES {
            return Err("base-var candidate fixture exceeds finding admission".into());
        }
        Ok(RawRun {
            name: "base_vars".into(),
            run: Run {
                sites: sink.sites,
                notes: sink.notes,
            },
            allow_used: sink.allow_used,
        })
    }
}
#[cfg(test)]
#[path = "captured_base_var_candidates_tests.rs"]
mod tests;
