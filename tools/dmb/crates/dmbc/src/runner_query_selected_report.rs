//! Explicit selected-policy embedding pilot. No default/IPC/baseline route.
use super::{full_unused, operational, CompleteAllowRun, Producer, SourceSnapshot, UnionRows};
use crate::{
    daemon::selected_report_wire::Roster,
    policy_request::WorkspaceAuxiliaryQuestion as Q,
    selected_report_spool::{Stage, Verified},
};
use dq_analyze::{
    baseline::SiteText,
    selected_exclusions_wire::JudgmentV2,
    captured_allow_annotations::Operation,
    captured_generator_budget::Budget,
    key_policy_control::{self as kc, Control},
    lint::{Meta, Policy, Run, Site},
    policy_finish, policy_judge,
    scopes::LintScope,
};
use std::{cell::RefCell, io::{self, Write}, path::Path, sync::Arc};

/// Existing v1 aliases still choose the exact producer order. Preparation
/// derives its evidence from those producers, under the same closed profiles.
pub(in crate::runner_host) struct SelectedReportPlan {
    roster: Roster,
    questions: &'static [Q],
    judgment: JudgmentV2,
}

impl SelectedReportPlan {
    fn for_roster(roster: Roster, judgment: JudgmentV2, control: &mut Operation<'_>) -> io::Result<Self> {
        if roster.names().len() > Roster::MAX_STAGED_POLICIES {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report sections exceed the staged bound"));
        }
        const PROFILES: &[&[Q]] = &[
            &[], &[Q::SiliconEntry], &[Q::LibraryLayeringFullAllow], &[Q::SemHandlersFullAllow],
            Q::SELECTED_SETTER, Q::SELECTED_READS, Q::SELECTED_REACTIVE, &[Q::Untyped], &[Q::DerivedReads], &[Q::SysReactive], &[Q::Lifeforms], &[Q::PlayerLink],
            Q::SELECTED_LIFEFORMS_PLAYER_LINK, Q::SELECTED_REFERENCE_POLICIES, &[Q::RequirementBool], Q::SELECTED_DECLARATION_POLICIES,
        ];
        let mut requested = [None; Roster::MAX_POLICIES];
        let mut count = 0;
        for &name in roster.names() {
            control.checkpoint().map_err(operational)?;
            let producer = Producer::from_name(name).filter(|producer| producer.stages_report())
                .ok_or_else(|| io::Error::new(io::ErrorKind::Unsupported, "selected policy has no staged report adapter"))?;
            if !judgment.is_raw() && !matches!(producer.metadata().policy, Policy::Hard)
                && !(judgment == JudgmentV2::CiLibrarySites && library_sites(producer.metadata()))
            {
                return Err(io::Error::new(io::ErrorKind::Unsupported, "selected CI ceiling judgment requires a Hard policy"));
            }
            if let Some(question) = producer.question() {
                let slot = requested.get_mut(count)
                    .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "selected report questions exceed its fixed bound"))?;
                *slot = Some(question);
                count += 1;
            }
        }
        // PolicyInputRequest also canonicalizes by question order. The legacy
        // report section order is a separate registry-order contract.
        let requested = &mut requested[..count];
        requested.sort_unstable();
        let questions = PROFILES.iter().copied().find(|profile| profile.iter().copied().map(Some).eq(requested.iter().copied()))
            .ok_or_else(|| io::Error::new(io::ErrorKind::Unsupported, "selected report lacks a qualified capture profile"))?;
        let plan = Self { roster, questions, judgment };
        if plan.supports_combined() != roster.is_combined() {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report profile differs from v1 wire eligibility"));
        }
        Ok(plan)
    }

    pub(in crate::runner_host) fn roster(&self) -> Roster { self.roster }
    pub(in crate::runner_host) fn questions(&self) -> &'static [Q] { self.questions }
    pub(in crate::runner_host) fn needs_library_sites_baseline(&self) -> bool {
        self.judgment == JudgmentV2::CiLibrarySites
    }
    pub(in crate::runner_host) fn supports_combined(&self) -> bool { Q::admits_combined_reports(self.questions) }
    pub(in crate::runner_host) fn requires_handlers(&self) -> bool { self.questions == [Q::SemHandlersFullAllow] }
}

fn library_sites(meta: &Meta) -> bool {
    meta.name == "library_layering" &&
        matches!(meta.policy, Policy::Sites { baseline, .. }
            if baseline == crate::runner_host::workspace_capture::LIBRARY_SITES_BASELINE)
}

pub(in crate::runner_host) fn validate_selection(exclusions: &[String], budget: &Budget) -> io::Result<SelectedReportPlan> {
    let mut control = Operation { budget, poll: &|| crate::daemon::control::checkpoint() };
    let selected = full_unused::registered_full_selection(exclusions, &mut control).map_err(operational)?;
    let roster = Roster::ALL.into_iter().find(|roster| {
        selected.names().iter().map(String::as_str).eq(roster.names().iter().copied())
    }).ok_or_else(|| io::Error::new(io::ErrorKind::Unsupported, "selection differs from the qualified report rosters"))?;
    SelectedReportPlan::for_roster(roster, JudgmentV2::Raw, &mut control)
}

pub(in crate::runner_host) fn validate_selection_v2(exclusions: &[String], budget: &Budget, judgment: JudgmentV2) -> io::Result<SelectedReportPlan> {
    let mut control = Operation { budget, poll: &|| crate::daemon::control::checkpoint() };
    let registered = full_unused::registered_full_selection(&[], &mut control).map_err(operational)?;
    // Exactly the registry-order complement, using individual full names.
    // Aliases, duplicate/unknown names and caller-defined unions have no v2 plan.
    for &roster in Roster::v2_for(judgment) {
        control.checkpoint().map_err(operational)?;
        let names = || registered.names().iter().map(String::as_str);
        let selected = names().filter(|name| roster.names().contains(name));
        let complement = names().filter(|name| !roster.names().contains(name));
        if selected.eq(roster.names().iter().copied())
            && exclusions.iter().map(|name| name.strip_prefix('-')).eq(complement.map(Some))
        {
            return SelectedReportPlan::for_roster(roster, judgment, &mut control);
        }
    }
    Err(io::Error::new(io::ErrorKind::Unsupported, "selection differs from the canonical Analyze-only v2 plans"))
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

enum ReportRows<'a,'borrow> {
    Union(UnionRows<'a,'borrow>),
    ImageDir(&'a dq_analyze::captured_image_dir::Data),
}

struct SitesWork<'a>(&'a Budget);
impl dq_analyze::policy_finish::admitted::Work for SitesWork<'_> {
    fn checkpoint(&self) -> io::Result<()> {
        crate::daemon::control::checkpoint()?;
        self.0.require().map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))
    }
    fn reserve(&self, bytes: usize) -> io::Result<()> {
        self.0.charge(bytes).map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))
    }
    fn overflow(&self) -> io::Error {
        self.0.deny();
        io::ErrorKind::OutOfMemory.into()
    }
}

struct ReportStage<'a> {
    file: Stage,
    finished: usize,
    selected: &'static [&'static str],
    failed: [bool; Roster::MAX_STAGED_POLICIES],
    judgment: JudgmentV2,
    // Outer None means the fixed role is unissued; inner None is its observed empty baseline.
    library_baseline: Option<Option<&'a [u8]>>,
}
impl ReportStage<'_> {
    fn observe(&mut self, root: &Path, meta: &Meta, rows: ReportRows<'_, '_>, scope: &LintScope, child: &Arc<Budget>) -> io::Result<()> {
        if self.selected.get(self.finished).copied() != Some(meta.name) || !matches!(meta.policy, Policy::Hard | Policy::Sites { .. }) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report section order or judge differs"));
        }
        let mut scratch = SectionScratch { budget: Budget::scoped_temporaries(child)
            .map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))?, complete: false };
        let mut control = Operation { budget: &scratch.budget, poll: &|| crate::daemon::control::checkpoint() };
        let mut projection = Projection::new();
        let mut post_judge = None;
        match rows {
            ReportRows::ImageDir(data) => {
                if self.selected != ["image_dir_after_build"]
                    || meta.name != "image_dir_after_build"
                    || !std::ptr::eq(meta, data.metadata())
                    || !matches!(meta.policy, Policy::Hard)
                    || !data.allow_used().is_empty() {
                    return Err(io::Error::new(io::ErrorKind::InvalidData,
                        "named ImageDir report does not have its exact Hard output role"));
                }
                for site in data.sites() {
                    projection.row(site, None, &mut control)?;
                }
            }
            ReportRows::Union(rows) => match rows {
            UnionRows::Raw(files) => for file in files {
                if file.name != meta.name { return Err(io::Error::new(io::ErrorKind::InvalidData, "raw result belongs to another policy")); }
                for (index, site) in file.run.sites.iter().enumerate() {
                    projection.row(site, file.site_text(index), &mut control)?;
                }
                projection.notes(&file.run.notes, &mut control)?;
            },
            UnionRows::Fold(policy, data) => {
                use dq_analyze::workspace_fold_policy::{Data, Policy as Fold};
                let compatible = matches!((policy, data),
                    (Fold::StateSchema, Data::StateSchema(_)) |
                    (Fold::Lifecycle, Data::Lifecycle(_)) |
                    (Fold::Loot, Data::Loot(_)) |
                    (Fold::InstanceList, Data::InstanceList(_)) |
                    (Fold::Cache, Data::Cache(_)) |
                    (Fold::OwnershipForms, Data::OwnershipForms(_)) |
                    (Fold::Api, Data::Api(_)) |
                    (Fold::Fields, Data::Fields(_)) |
                    (Fold::Appearance, Data::Appearance(_)));
                if self.selected != Roster::WithWorkspaceFoldPolicies.names()
                    || !compatible || !std::ptr::eq(meta, policy.metadata())
                    || !matches!(meta.policy, Policy::Hard)
                {
                    return Err(io::Error::new(io::ErrorKind::InvalidData,
                        "selected fold findings differ from their admitted Hard policy"));
                }
                match data.source_text() {
                    None if policy.message_only() => {
                        for site in data.sites() {
                            projection.row(site, None, &mut control)?;
                        }
                    }
                    Some(text) if !policy.message_only() && data.sites().len() == text.len() => {
                        for (site, text) in data.sites().iter().zip(text) {
                            projection.row(site, Some(text), &mut control)?;
                        }
                    }
                    _ => return Err(io::Error::new(io::ErrorKind::InvalidData,
                        "selected fold findings lack their actual source or message shape")),
                }
                projection.notes(data.notes(), &mut control)?;
            }
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
            UnionRows::DerivedReads(data) => {
                if self.selected != Roster::WithDerivedReads.names() || !std::ptr::eq(meta, data.metadata())
                    || !std::ptr::eq(meta, dq_analyze::captured_derived_reads::metadata())
                    || !matches!(meta.policy, Policy::Hard) || data.sites().len() != data.source_text().len() {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "selected Derived findings differ from their actual Hard source shape"));
                }
                for (site, text) in data.sites().iter().zip(data.source_text()) {
                    projection.row(site, Some(text), &mut control)?;
                }
                post_judge = data.post_judge_message();
            }
            UnionRows::MessageOnlyHard(question, sites, allows) => {
                let (rosters, expected): (&[Roster], _) = match question {
                    Q::Lifeforms => (&[Roster::WithLifeforms, Roster::WithLifeformsAndPlayerLink], dq_analyze::lifeforms_policy::metadata()),
                    Q::PlayerLink => (&[Roster::WithPlayerLink, Roster::WithLifeformsAndPlayerLink], dq_analyze::player_link_policy::metadata()),
                    Q::UntypedMember => (&[Roster::WithReferencePolicies], dq_analyze::untyped_member_policy::metadata()),
                    Q::WeakRawRead => (&[Roster::WithReferencePolicies], dq_analyze::weak_relation_policy::metadata()),
                    Q::RelWriteUndeclared => (&[Roster::WithReferencePolicies], dq_analyze::rel_write_policy::metadata()),
                    _ => return Err(io::Error::new(io::ErrorKind::InvalidData, "unissued message-only selected report role")),
                };
                if !rosters.iter().any(|roster| self.selected == roster.names())
                    || !std::ptr::eq(meta, expected)
                    || !matches!(meta.policy, Policy::Hard) || !meta.allow.is_empty()
                    || !allows.is_empty() {
                    return Err(io::Error::new(io::ErrorKind::InvalidData,
                        "selected message-only findings differ from their actual Hard/no-ALLOW role"));
                }
                for site in sites {
                    if site.msg.is_empty() {
                        return Err(io::Error::new(io::ErrorKind::InvalidData,
                            "selected Hard finding lacks its actual message"));
                    }
                    projection.row(site, None, &mut control)?;
                }
            }
            UnionRows::DeclarationHard(question, sites, source_text, notes) => {
                let expected = match question {
                    Q::Decl => dq_analyze::captured_decl_pages::metadata(),
                    Q::Init => dq_analyze::captured_init_pages::metadata(),
                    Q::BaseVars => dq_analyze::captured_base_vars_pages::metadata(),
                    _ => return Err(io::Error::new(io::ErrorKind::InvalidData, "unissued selected declaration report role")),
                };
                if self.selected != Roster::WithDeclarationPolicies.names()
                    || !std::ptr::eq(meta, expected)
                    || !matches!(meta.policy, Policy::Hard)
                    || sites.len() != source_text.len()
                {
                    return Err(io::Error::new(io::ErrorKind::InvalidData,
                        "selected declaration findings differ from their actual Hard source shape"));
                }
                for (site, text) in sites.iter().zip(source_text) {
                    projection.row(site, Some(text), &mut control)?;
                }
                projection.notes(notes, &mut control)?;
            }
            UnionRows::RequirementBool(data) => {
                if self.selected != Roster::WithRequirementBool.names()
                    || !std::ptr::eq(meta, data.metadata())
                    || !std::ptr::eq(meta, dq_analyze::captured_requirement_bool_pages::metadata())
                    || !matches!(meta.policy, Policy::Hard) || !meta.allow.is_empty()
                    || !data.allow_used().is_empty()
                    || data.sites().len() != data.source_text().len()
                {
                    return Err(io::Error::new(io::ErrorKind::InvalidData,
                        "selected requirement_bool findings differ from their actual Hard/no-ALLOW source shape"));
                }
                for (site, text) in data.sites().iter().zip(data.source_text()) {
                    projection.row(site, Some(text), &mut control)?;
                }
                projection.notes(data.notes(), &mut control)?;
            }
            UnionRows::SysReactive(data) => {
                if self.selected != Roster::WithSysReactive.names()
                    || !std::ptr::eq(meta, dq_analyze::sys_reactive_policy::metadata())
                    || !matches!(meta.policy, Policy::Hard)
                    || data.sites().len() != data.source_text().len()
                {
                    return Err(io::Error::new(io::ErrorKind::InvalidData,
                        "selected Sys reactive findings differ from their actual Hard source shape"));
                }
                for (site, text) in data.sites().iter().zip(data.source_text()) {
                    projection.row(site, Some(text), &mut control)?;
                }
            }
            UnionRows::Untyped(data) => {
                if self.selected != Roster::WithUntyped.names() || !std::ptr::eq(meta, data.metadata())
                    || !std::ptr::eq(meta, dq_analyze::untyped_policy_metadata::metadata())
                    || !matches!(meta.policy, Policy::Hard) || !meta.allow.is_empty()
                    || !data.allow_used().is_empty() || data.sites().len() != data.source_text().len() {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "selected untyped findings differ from their exact Hard/no-ALLOW source shape"));
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
            },
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
        let raw = self.judgment.is_raw();
        let (failed, text) = if raw || matches!(meta.policy, Policy::Hard) {
            policy_judge::judge_report(meta, scope, &source_text, &projection.run, root, &None, raw,
                |_, _, _| false, |_, text| {
                    if let Some(message) = post_judge { text.push_str(message); true } else { false }
                })
        } else if self.judgment == JudgmentV2::CiLibrarySites && library_sites(meta) {
            let baseline = self.library_baseline.ok_or_else(|| io::Error::new(
                io::ErrorKind::InvalidData, "staged library layering requires captured fixed baseline evidence",
            ))?;
            dq_analyze::policy_finish::admitted::judge_captured_sites(
                meta, scope, &projection.text, &projection.run, root, baseline, &SitesWork(&scratch.budget),
            )?
        } else {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "staged CI judgment cannot read a baseline"));
        };
        if !raw { writeln!(self.file, "::group::{}", meta.name)?; }
        self.file.write_all(text.as_bytes())?;
        if !raw { self.file.write_all(b"::endgroup::\n")?; }
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
        // Only the admitted roster's policy names and at most one unused-audit label.
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
        root: &Path, plan: &SelectedReportPlan, handlers: Option<&super::super::HandlerWorkspaceSnapshot>, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        use crate::request::BuildOutcome;
        let BuildOutcome::QueryPrepared { semantic_revision, source_revision, policy_revision: Some(policy_revision), retained: true } = prepared else {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report preparation did not issue a current Original frame"));
        };
        let pin = |text: &str| u128::from_str_radix(text, 16).ok();
        let workspace = self.native_workspace.as_ref().ok_or_else(|| io::Error::other("selected report has no actual workspace"))?;
        if workspace.root() != root || workspace.configuration().1.is_none()
            || !workspace.matches_auxiliary_questions(plan.questions())
            || handlers.is_some() != plan.requires_handlers()
            || pin(semantic_revision) != Some(self.tree.identity()) || pin(source_revision) != Some(self.source_revision)
            || pin(policy_revision) != Some(workspace.policy_revision()) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report preparation differs from its current workspace"));
        }
        let library_baseline = if plan.needs_library_sites_baseline() {
            let guard = self.workspace_native_read()?;
            Some(workspace.library_sites_baseline(&guard)?)
        } else { None };
        let stage = RefCell::new(ReportStage {
            file, finished: 0, selected: plan.roster().names(), failed: [false; Roster::MAX_STAGED_POLICIES],
            judgment: plan.judgment, library_baseline,
        });
        let clean = self.with_native_allow_full_run_using(&self.tree, exclusions, Some(retained), handlers, Some(&mut |meta, rows, scope, budget| {
            stage.borrow_mut().observe(root, meta, ReportRows::Union(rows), scope, budget)
        }), |data, _, budget| stage.borrow_mut().finish(data,budget)).map_err(operational)?;
        let stage = stage.into_inner();
        let output = checked_stage(stage.file)?;
        workspace.require_scope(&self.workspace_native_read()?)?;
        Ok((clean, output))
    }
}

#[cfg(test)]
mod selected_plan_tests {
    use super::*;

    #[test]
    fn selected_v1_aliases_derive_the_exact_previous_capture_profiles() {
        let budget = Budget::new(1 << 20).unwrap();
        let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
        let registry = full_unused::registered_full_selection(&[], &mut work).unwrap();
        let expected: [(Roster, &[Q]); Roster::ALL.len()] = [
            (Roster::Base, &[]),
            (Roster::AllRawFilePolicies, &[]),
            (Roster::WithWorkspaceFoldPolicies, &[]),
            (Roster::WithRawRuntimePolicies, &[]),
            (Roster::WithRawDeclarationPolicies, &[]),
            (Roster::WithCooldown, &[]),
            (Roster::WithEngineInternal, &[]),
            (Roster::WithSilicon, &[Q::SiliconEntry]),
            (Roster::WithLibraryLayering, &[Q::LibraryLayeringFullAllow]),
            (Roster::WithHandlers, &[Q::SemHandlersFullAllow]),
            (Roster::WithSemanticReads, Q::SELECTED_READS),
            (Roster::WithSetterPublishes, Q::SELECTED_SETTER),
            (Roster::WithReactivePolicies, Q::SELECTED_REACTIVE),
            (Roster::WithUntyped, &[Q::Untyped]),
            (Roster::WithDerivedReads, &[Q::DerivedReads]),
            (Roster::WithSysReactive, &[Q::SysReactive]),
            (Roster::WithLifeforms, &[Q::Lifeforms]),
            (Roster::WithPlayerLink, &[Q::PlayerLink]),
            (Roster::WithLifeformsAndPlayerLink, Q::SELECTED_LIFEFORMS_PLAYER_LINK),
            (Roster::WithReferencePolicies, Q::SELECTED_REFERENCE_POLICIES),
            (Roster::WithRequirementBool, &[Q::RequirementBool]),
            (Roster::WithDeclarationPolicies, Q::SELECTED_DECLARATION_POLICIES),
        ];
        let all_raw = Roster::AllRawFilePolicies.names();
        for name in dq_analyze::captured_raw_policy::RAW_FILE_LINTS {
            assert_eq!(all_raw.contains(name), *name != "deadline_polling", "{name}");
        }
        assert_eq!(all_raw.len(), Roster::MAX_STAGED_POLICIES);
        assert!(all_raw.iter().all(|name| Roster::Base.names().contains(name)
            || dq_analyze::captured_raw_policy::RAW_FILE_LINTS.contains(name)));
        for (roster, questions) in expected {
            let exclusions: Vec<_> = registry.names().iter().filter(|name| !roster.names().contains(&name.as_str()))
                .map(|name| format!("-{name}")).collect();
            let plan = validate_selection(&exclusions, &budget).unwrap();
            assert_eq!(plan.roster(), roster);
            assert_eq!(plan.questions(), questions);
            assert_eq!(plan.supports_combined(), roster.is_combined());
            assert_eq!(plan.requires_handlers(), roster == Roster::WithHandlers);
        }
    }
}

/// Stage exactly one named ImageDir section. The caller still holds its
/// recorder/configuration proof and verifies freshness after this returns.
/// This helper has no public request, capture authority or publication hook.
pub(in crate::runner_host) fn stage_named_image_dir(
    source: &dm_tree::frontend::OriginalImageDirFrontend,
    root: &Path,
    config: &dq_analyze::captured_raw_file::Config,
    budget: &Arc<Budget>,
    file: Stage,
) -> io::Result<(bool, Verified)> {
    let poll = || crate::daemon::control::checkpoint();
    let data = dq_analyze::captured_image_dir::collect(source, root, config, budget, &poll)
        .map_err(operational)?;
    let empty = LintScope::default();
    let meta = data.metadata();
    let scope = config.borrowed_report_scope(meta.name, meta.group).unwrap_or(&empty);
    let mut stage = ReportStage {
        file,
        finished: 0,
        selected: &["image_dir_after_build"],
        failed: [false; Roster::MAX_STAGED_POLICIES],
        judgment: JudgmentV2::Raw,
        library_baseline: None,
    };
    stage.observe(root, meta, ReportRows::ImageDir(&data), scope, budget)?;
    if stage.finished != 1 {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "named ImageDir section did not complete"));
    }
    let clean = !stage.failed[0];
    let verified = checked_stage(stage.file)?;
    poll()?;
    budget.require().map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))?;
    Ok((clean, verified))
}

pub(in crate::runner_host) fn checked_stage(file: Stage) -> io::Result<Verified> {
    let length = file.length();
    let (verified, copied) = file.seal()?.validate(|read| io::copy(read, &mut io::sink()))?;
    if length != copied || verified.length() != copied {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report omitted bytes during sealed validation"));
    }
    Ok(verified)
}
