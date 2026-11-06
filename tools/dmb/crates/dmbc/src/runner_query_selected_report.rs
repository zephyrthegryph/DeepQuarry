//! Explicit selected-policy embedding pilot. No default/IPC/baseline route.
use super::{full_unused, operational, CompleteAllowRun, SourceSnapshot, UnionRows};
use crate::{daemon::selected_report_wire::Roster, selected_report_spool::{Stage, Verified}};
use dq_analyze::{
    baseline::SiteText,
    captured_allow_annotations::Operation,
    captured_generator_budget::Budget,
    key_policy_control::{self as kc, Control},
    lint::{Meta, Policy, Run, Site},
    policy_finish, policy_judge,
    scopes::LintScope,
};
use std::{cell::RefCell, io::{self, Write}, path::Path, sync::Arc};

pub(in crate::runner_host) fn validate_selection(exclusions: &[String], budget: &Budget) -> io::Result<Roster> {
    let mut control = Operation { budget, poll: &|| crate::daemon::control::checkpoint() };
    let selected = full_unused::registered_full_selection(exclusions, &mut control).map_err(operational)?;
    Roster::ALL.into_iter().find(|roster| {
        selected.names().iter().map(String::as_str).eq(roster.names().iter().copied())
    }).ok_or_else(|| io::Error::new(io::ErrorKind::Unsupported, "selection differs from the qualified report rosters"))
}

struct Projection {
    run: Run,
    text: Vec<String>,
    width: usize,
}
impl Projection {
    fn new() -> Self { Self { run: Run::default(), text: Vec::new(), width: 0 } }

    fn row(&mut self, site: &Site, text: Option<&str>, control: &mut Operation<'_>) -> io::Result<()> {
        control.checkpoint().map_err(operational)?;
        if text.is_none() && site.msg.is_empty() {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected finding lacks actual source text or a message"));
        }
        let text = text.unwrap_or("");
        let width = [&site.rule, &site.rel, &site.msg, &site.key, &site.ident]
            .into_iter().try_fold(text.len(), |n, value| n.checked_add(value.len()))
            .ok_or_else(|| operational(control.overflow()))?;
        self.width = self.width.checked_add(width).ok_or_else(|| operational(control.overflow()))?;
        kc::reserve(control, || width.checked_mul(4)?.checked_add(1024)).map_err(operational)?;
        kc::row(control, &mut self.run.sites).map_err(operational)?;
        kc::row(control, &mut self.text).map_err(operational)?;
        self.run.sites.push(site.clone());
        self.text.push(text.to_owned());
        Ok(())
    }

    fn notes(&mut self, notes: &[String], control: &mut Operation<'_>) -> io::Result<()> {
        for note in notes {
            self.width = self.width.checked_add(note.len()).ok_or_else(|| operational(control.overflow()))?;
            kc::row(control, &mut self.run.notes).map_err(operational)?;
            self.run.notes.push(kc::own(control, note).map_err(operational)?);
        }
        Ok(())
    }
}
struct Text<'a> { sites: &'a [Site], lines: &'a [String] }
impl SiteText for Text<'_> {
    fn site_text(&self, relative: &str, line: usize) -> String {
        self.sites.iter().zip(self.lines).find(|(site, _)| site.rel == relative && site.line as usize == line)
            .map(|(_, text)| text.clone()).unwrap_or_default()
    }
}
struct SectionScratch { budget: Arc<Budget>, complete: bool }
impl Drop for SectionScratch {
    fn drop(&mut self) { if !self.complete { self.budget.keep_failed_scratch(); } }
}

struct ReportStage {
    file: Stage,
    finished: usize,
    selected: &'static [&'static str],
    failed: [bool; Roster::MAX_POLICIES],
}
impl ReportStage {
    fn observe(&mut self, root: &Path, meta: &Meta, rows: UnionRows<'_, '_>, scope: &LintScope, child: &Arc<Budget>) -> io::Result<()> {
        if self.selected.get(self.finished).copied() != Some(meta.name) || !matches!(meta.policy, Policy::Hard | Policy::Sites { .. }) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report section order or judge differs"));
        }
        let mut scratch = SectionScratch { budget: Budget::scoped_temporaries(child)
            .map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))?, complete: false };
        let mut control = Operation { budget: &scratch.budget, poll: &|| crate::daemon::control::checkpoint() };
        let mut projection = Projection::new();
        match rows {
            UnionRows::Raw(files) => for file in files {
                if file.name != meta.name { return Err(io::Error::new(io::ErrorKind::InvalidData, "raw result belongs to another policy")); }
                for (index, site) in file.run.sites.iter().enumerate() {
                    projection.row(site, file.site_text(index), &mut control)?;
                }
                projection.notes(&file.run.notes, &mut control)?;
            },
            UnionRows::Tree(tree) => {
                if tree.message_only() {
                    if !matches!(meta.policy, Policy::Hard) || !tree.source_text().is_empty() {
                        return Err(io::Error::new(io::ErrorKind::InvalidData, "message-only tree findings require the exact hard-judge source shape"));
                    }
                    for site in tree.sites() { projection.row(site, None, &mut control)?; }
                } else {
                    if tree.sites().len() != tree.source_text().len() {
                        return Err(io::Error::new(io::ErrorKind::InvalidData, "selected tree findings lack their actual source lines"));
                    }
                    for (site, text) in tree.sites().iter().zip(tree.source_text()) {
                        projection.row(site, Some(text), &mut control)?;
                    }
                }
                projection.notes(tree.notes(), &mut control)?;
            }
            UnionRows::Silicon(data) => {
                if meta.name != "silicon_entry" || !matches!(meta.policy, Policy::Hard)
                    || data.sites().len() != data.source_text().len() {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "selected silicon findings differ from their actual Hard source shape"));
                }
                for (site, text) in data.sites().iter().zip(data.source_text()) {
                    projection.row(site, Some(text), &mut control)?;
                }
            }
            UnionRows::LibraryLayering(data) => {
                let text = data.source_text().ok_or_else(|| io::Error::new(
                    io::ErrorKind::InvalidData, "selected library layering source evidence is absent"))?;
                if meta.name != "library_layering" || !std::ptr::eq(meta, data.metadata())
                    || !matches!(meta.policy, Policy::Sites { .. }) || data.sites().len() != text.len() {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "selected library layering findings differ from their actual Sites shape"));
                }
                for (site, text) in data.sites().iter().zip(text) {
                    projection.row(site, Some(text), &mut control)?;
                }
                projection.notes(data.notes(), &mut control)?;
            }
            UnionRows::Handlers(data) => {
                if meta.name != "sem/handlers" || !std::ptr::eq(meta, data.metadata())
                    || !matches!(meta.policy, Policy::Hard) || data.sites().len() != data.source_text().len() {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "selected handler findings differ from their actual Hard source shape"));
                }
                for (site, text) in data.sites().iter().zip(data.source_text()) {
                    projection.row(site, Some(text), &mut control)?;
                }
            }
            UnionRows::Semantic(question, data) => {
                use crate::policy_request::WorkspaceAuxiliaryQuestion as Q;
                let expected = match question {
                    Q::SemReads => dq_analyze::sem_reads_policy::metadata(),
                    Q::UntrackedInputs => dq_analyze::untracked_inputs_policy::metadata(),
                    Q::SetterPublishes => dq_analyze::setter_publication_policy::metadata(),
                    _ => return Err(io::Error::new(io::ErrorKind::InvalidData, "unissued semantic read report role")),
                };
                if !std::ptr::eq(meta, expected) || !matches!(meta.policy, Policy::Hard) {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "semantic read report metadata differs"));
                }
                for site in data.sites() {
                    if site.msg.is_empty() {
                        return Err(io::Error::new(io::ErrorKind::InvalidData, "semantic read report is missing its actual finding message"));
                    }
                    projection.row(site, None, &mut control)?;
                }
            }
            UnionRows::Validation(validation) => {
                if validation.sites.len() != validation.source_text.len() {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "actual ALLOW validation text shape differs"));
                }
                for (site, text) in validation.sites.iter().zip(&validation.source_text) {
                    projection.row(site, Some(text), &mut control)?;
                }
            }
        }
        // Includes the legacy grouping, normalized line clone, hints and final
        // text before the common renderer allocates them.
        let rule_width = meta.rules.iter().try_fold(0usize, |n, rule| n.checked_add(rule.name.len())?.checked_add(rule.hint.len()))
            .ok_or_else(|| operational(control.overflow()))?;
        kc::reserve(&mut control, || {
            let width = projection.width.checked_add(rule_width)?.checked_add(root.as_os_str().len().checked_mul(4)?)?.checked_add(1)?;
            let rows = projection.run.sites.len().checked_add(projection.run.notes.len())?.checked_add(meta.rules.len())?.checked_add(1)?;
            // A hint may repeat once per site and is not bounded by width alone.
            let repeated = projection.run.sites.len().checked_mul(meta.rules.iter().map(|rule| rule.hint.len()).max().unwrap_or(0))?;
            width.checked_add(repeated)?.checked_mul(128)?.checked_add(rows.checked_mul(8192)?)
        }).map_err(operational)?;

        let source_text = Text { sites: &projection.run.sites, lines: &projection.text };
        let (failed, text) = policy_judge::judge_report(meta, scope, &source_text, &projection.run, root, &None, true,
            |_, _, _| false, |_, _| false);
        self.file.write_all(text.as_bytes())?;
        self.failed[self.finished] = failed;
        self.finished += 1;
        drop(text);
        drop(projection);
        scratch.complete = true;
        Ok(())
    }

    fn finish(&mut self, data: &CompleteAllowRun<'_>, budget: &Budget) -> io::Result<bool> {
        if self.finished != self.selected.len() || !data.selected().iter().map(String::as_str).eq(self.selected.iter().copied()) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected sections did not complete their actual ALLOW join"));
        }
        for problem in data.unused() { writeln!(self.file, "{problem}")?; }
        writeln!(self.file, "allow annotations: {} unused", data.unused().len())?;
        // At most six static policy names and at most one unused-audit label.
        budget.charge(4096).map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))?;
        let mut failed: Vec<String> = self.selected.iter().copied().zip(self.failed)
            .filter(|(_, failed)| *failed).map(|(name, _)| name.to_owned()).collect();
        if !data.unused().is_empty() { failed.push("allow_annotations --unused".to_owned()); }
        self.file.write_all(policy_finish::result_line(&failed).as_bytes())?;
        Ok(failed.is_empty())
    }
}

impl SourceSnapshot {
    pub(in crate::runner_host) fn stage_selected_report(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, selected: &'static [&'static str], handlers: Option<&super::super::HandlerWorkspaceSnapshot>, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        use crate::request::BuildOutcome;
        let BuildOutcome::QueryPrepared { semantic_revision, source_revision, policy_revision: Some(policy_revision), retained: true } = prepared else {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report preparation did not issue a current Original frame"));
        };
        let pin = |text: &str| u128::from_str_radix(text, 16).ok();
        let workspace = self.native_workspace.as_ref().ok_or_else(|| io::Error::other("selected report has no actual workspace"))?;
        if workspace.root() != root || workspace.configuration().1.is_none()
            || pin(semantic_revision) != Some(self.tree.identity()) || pin(source_revision) != Some(self.source_revision)
            || pin(policy_revision) != Some(workspace.policy_revision()) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report preparation differs from its current workspace"));
        }
        let stage = RefCell::new(ReportStage { file, finished: 0, selected, failed: [false; Roster::MAX_POLICIES] });
        let clean = self.with_native_allow_full_run_using(&self.tree, exclusions, Some(retained), handlers, Some(&mut |meta, rows, scope, budget| {
            stage.borrow_mut().observe(root, meta, rows, scope, budget)
        }), |data, _, budget| stage.borrow_mut().finish(data,budget)).map_err(operational)?;
        let stage = stage.into_inner();
        let output = checked_stage(stage.file)?;
        workspace.require_scope(&self.workspace_native_read()?)?;
        Ok((clean, output))
    }
}

pub(in crate::runner_host) fn checked_stage(file: Stage) -> io::Result<Verified> {
    let length = file.length();
    let (verified, copied) = file.seal()?.validate(|read| io::copy(read, &mut io::sink()))?;
    if length != copied || verified.length() != copied {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report omitted bytes during sealed validation"));
    }
    Ok(verified)
}
