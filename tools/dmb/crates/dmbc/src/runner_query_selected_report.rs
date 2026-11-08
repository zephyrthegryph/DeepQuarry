//! Explicit selected-policy embedding pilot. No default/IPC/baseline route.
use super::{full_unused, operational, CompleteAllowRun, Producer, SourceSnapshot, UnionRows, PRIVATE_IMAGE_DIR_ROSTER};
use crate::{
    daemon::selected_report_wire::Roster,
    policy_request::WorkspaceAuxiliaryQuestion as Q,
    runner_host::workspace_capture::WorkspaceCapture,
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

pub(super) const PRIVATE_DOC_UI: &[&str] = &[
    "allow_annotations", "doc_snippets", "notice_publisher", "report_in_catch", "scheduler", "ui_actions",
];


pub(super) const PRIVATE_AUTHORED_DOC_UI: &[&str] = &[
    "allow_annotations", "doc_snippets", "engine_layering", "library_layering", "map_edits",
    "notice_publisher", "report_in_catch", "scheduler", "ui_actions",
];

/// Exact CODE+MAPS union of the existing reactive, raw declaration, raw runtime,
/// cooldown and engine-internal report sections. No new source role.
pub(super) const PRIVATE_REACTIVE_RAW_UNION: &[&str] = &[
    "allow_annotations", "cap_bits", "cooldown", "declaration_block", "duplicate_input_key",
    "engine_internal", "interactions", "latent", "notice_publisher", "pollers", "pool",
    "read_back", "report_in_catch", "scheduler", "sem/reads", "setter_publishes", "untracked_inputs",
];

pub(super) const PRIVATE_ORDINARY_SEMANTIC_AND_FIXED: &[&str] = &[
    "base_vars", "deadline_polling", "decl", "init", "lifeforms", "op_order", "ownership",
    "player_link", "rel_write_undeclared", "requirement_bool", "sem/keys", "sys/dx_reactive",
    "untyped_member", "weak_raw_read",
];

pub(super) const PRIVATE_MAP_AND_LAYERING: &[&str] = &[
    "allow_annotations", "engine_layering", "library_layering", "map_edits",
    "notice_publisher", "report_in_catch", "scheduler",
];


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
            &[], &[Q::DocSnippetsFullAllow], &[Q::UiActionsFullAllow], &[Q::CheckGrep], &[Q::DeadlinePollingAllowlist], &[Q::SiliconEntry], &[Q::LibraryLayeringFullAllow], &[Q::EngineLayeringFullAllow], &[Q::SemHandlersFullAllow],
            Q::SELECTED_SETTER, Q::SELECTED_READS, Q::SELECTED_REACTIVE, &[Q::Untyped], &[Q::Keys], &[Q::MapEdits], Q::SELECTED_ORDER_AND_OWNERSHIP, &[Q::DerivedReads], &[Q::SysReactive], &[Q::Lifeforms], &[Q::PlayerLink],
            Q::SELECTED_LIFEFORMS_PLAYER_LINK, Q::SELECTED_REFERENCE_POLICIES, Q::SELECTED_STORED_AND_TRACKED, &[Q::RequirementBool], Q::SELECTED_DECLARATION_POLICIES,
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

/// Private selection data only. The current report still owes its fixed
/// capture and the existing coordinator's completed usage fold.
pub(super) fn preflight_no_aux_raw_subset(
    exclusions: &[String], control: &mut Operation<'_>,
) -> io::Result<impl AsRef<[&'static str]>> {
    struct Names { rows: [&'static str; Roster::MAX_POLICIES], count: usize }
    impl AsRef<[&'static str]> for Names {
        fn as_ref(&self) -> &[&'static str] { &self.rows[..self.count] }
    }
    let registered = full_unused::registered_full_selection(&[], control).map_err(operational)?;
    let qualified = Roster::WithCooldownAndEngineInternal.names();
    let mut selected = Names { rows: [""; Roster::MAX_POLICIES], count: 0 };
    let mut omitted = exclusions.iter().peekable();
    for name in registered.names() {
        control.checkpoint().map_err(operational)?;
        if omitted.peek().and_then(|next| next.strip_prefix('-')) == Some(name.as_str()) {
            omitted.next();
            continue;
        }
        let producer = Producer::from_name(name).filter(|producer| {
            qualified.contains(&producer.name()) && producer.stages_report()
                && producer.question().is_none() && matches!(producer.metadata().policy, Policy::Hard)
        }).ok_or_else(|| io::Error::new(io::ErrorKind::Unsupported,
            "selection exceeds the qualified no-aux raw report profile"))?;
        let slot = selected.rows.get_mut(selected.count)
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "no-aux selection exceeds its fixed bound"))?;
        *slot = producer.name();
        selected.count += 1;
    }
    if omitted.next().is_some() || selected.count == 0 {
        return Err(io::Error::new(io::ErrorKind::Unsupported,
            "selection is not a nonempty canonical registry complement"));
    }
    Ok(selected)
}

pub(in crate::runner_host) fn validate_selection_v2(exclusions: &[String], budget: &Budget, judgment: JudgmentV2) -> io::Result<SelectedReportPlan> {
    let mut control = Operation { budget, poll: &|| crate::daemon::control::checkpoint() };
    if judgment != JudgmentV2::CiLibrarySites {
        let subset = preflight_no_aux_raw_subset(exclusions, &mut control)?;
        // A private subset does not acquire an existing wire identity.
        let roster = Roster::v2_for(judgment).iter().copied()
            .find(|roster| roster.names() == subset.as_ref())
            .ok_or_else(|| io::Error::new(io::ErrorKind::Unsupported,
                "selection differs from the canonical Analyze-only v2 plans"))?;
        return SelectedReportPlan::for_roster(roster, judgment, &mut control);
    }
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

/// Operation-local status indexed by the admitted section order. The caller
/// retains the order and authority; status bits grant neither.
struct SectionFailures {
    bits: Vec<u8>,
    sections: usize,
}

impl SectionFailures {
    fn new(sections: usize, budget: &Budget) -> io::Result<Self> {
        let bytes = sections.div_ceil(u8::BITS as usize);
        let mut bits = Vec::new();
        if bytes != 0 {
            budget.charge(bytes).map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))?;
            bits.try_reserve_exact(bytes).map_err(|_| io::ErrorKind::OutOfMemory)?;
            bits.resize(bytes, 0);
        }
        Ok(Self { bits, sections })
    }

    fn record(&mut self, ordinal: usize, failed: bool) -> io::Result<()> {
        if ordinal >= self.sections {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "section status is outside the admitted order"));
        }
        if failed {
            self.bits[ordinal / u8::BITS as usize] |= 1 << (ordinal % u8::BITS as usize);
        }
        Ok(())
    }

    fn failed(&self, ordinal: usize) -> bool {
        assert!(ordinal < self.sections);
        self.bits[ordinal / u8::BITS as usize] & (1 << (ordinal % u8::BITS as usize)) != 0
    }
}

struct ReportStage<'a> {
    file: Stage,
    finished: usize,
    selected: &'a [&'a str],
    failed: SectionFailures,
    authored_doc_ui: bool,
    ordinary_fold_sys: bool,
    ordinary_semantic_and_fixed: bool,
    private_checker_body: bool,
    private_image_dir: bool,
    private_check_grep: bool,
    private_derived_reads: bool,
    judgment: JudgmentV2,
    // Outer None means the fixed role is unissued; inner None is its observed empty baseline.
    library_baseline: Option<Option<&'a [u8]>>,
}
impl ReportStage<'_> {
    fn observe(&mut self, root: &Path, meta: &Meta, rows: ReportRows<'_, '_>, scope: &LintScope, child: &Arc<Budget>) -> io::Result<()> {
        if let ReportRows::Union(UnionRows::CheckGrep(data)) = &rows {
            if (self.selected != Roster::WithCheckGrep.names() && !self.private_check_grep)
                || self.selected.get(self.finished).copied() != Some(meta.name)
                || !std::ptr::eq(meta, dq_analyze::lints::check_grep::native::metadata())
                || !self.judgment.is_raw() || !matches!(meta.policy, Policy::Custom)
            {
                return Err(io::Error::new(io::ErrorKind::InvalidData, "check_grep requires its exact completed raw report"));
            }
            let checkpoint = || -> io::Result<()> {
                crate::daemon::control::checkpoint()?;
                child.require().map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))
            };
            // This producer has already run the original custom renderer over
            // the actual Check observations, and owns its admitted report
            // bytes. The generic judge prefixes notes before that hook.
            checkpoint()?;
            for note in &data.run.notes {
                writeln!(self.file, "{note}")?;
            }
            self.file.write_all(data.report.as_bytes())?;
            checkpoint()?;
            self.failed.record(self.finished, data.failed)?;
            self.finished += 1;
            return Ok(());
        }
        let deadline = matches!(&rows, ReportRows::Union(UnionRows::Deadline(..)))
            && (self.selected == Roster::WithDeadlinePolling.names() || self.ordinary_semantic_and_fixed)
            && self.judgment.is_raw() && matches!(meta.policy, Policy::Custom)
            && dq_analyze::captured_raw_policy::metadata("deadline_polling")
                .is_some_and(|expected| std::ptr::eq(meta, expected));
        if self.selected.get(self.finished).copied() != Some(meta.name)
            || (!deadline && !matches!(meta.policy, Policy::Hard | Policy::Sites { .. })) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report section order or judge differs"));
        }
        let mut scratch = SectionScratch { budget: Budget::scoped_temporaries(child)
            .map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))?, complete: false };
        let mut control = Operation { budget: &scratch.budget, poll: &|| crate::daemon::control::checkpoint() };
        let mut projection = Projection::new();
        let mut post_judge = None;
        let mut doc_summary = None;
        let mut deadline_judge = None;
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
            UnionRows::ImageDir(data) => {
                if (self.selected != PRIVATE_IMAGE_DIR_ROSTER && !self.private_image_dir) || meta.name != "image_dir_after_build"
                    || !std::ptr::eq(meta,data.metadata()) || !matches!(meta.policy,Policy::Hard)
                    || !data.allow_used().is_empty() {
                    return Err(io::Error::new(io::ErrorKind::InvalidData,"selected ImageDir role differs"));
                }
                for site in data.sites() { projection.row(site,None,&mut control)?; }
            }
            UnionRows::Deadline(files, path, bytes) => {
                use dq_analyze::lints::deadline_polling::{prepare_observed_report, ReportAllowlist};
                if !deadline {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "Deadline requires its exact raw observed judge"));
                }
                let observation = match bytes.map(std::str::from_utf8) {
                    None => ReportAllowlist::ProvenMissing,
                    Some(Ok(text)) => ReportAllowlist::CapturedUtf8(text),
                    Some(Err(_)) => ReportAllowlist::CapturedNonUtf8,
                };
                let parsed = prepare_observed_report(observation, &mut control).map_err(operational)?;
                // The custom renderer can print one stale line for every
                // physical allowlist line, repeating the exact observed path.
                let input = bytes.unwrap_or_default();
                let count = input.split(|byte| *byte == b'\n').count();
                kc::reserve(&mut control, || {
                    let prefix = path.as_os_str().len().checked_mul(4)?.checked_add(128)?;
                    input.len().checked_add(count.checked_mul(prefix)?)?.checked_mul(8)
                }).map_err(operational)?;
                let shown = path.to_string_lossy();
                deadline_judge = Some((parsed, shown));
                for file in files {
                    if file.name != meta.name {
                        return Err(io::Error::new(io::ErrorKind::InvalidData, "Deadline raw result belongs to another policy"));
                    }
                    for (index, site) in file.run.sites.iter().enumerate() {
                        projection.row(site, file.site_text(index), &mut control)?;
                    }
                    projection.notes(&file.run.notes, &mut control)?;
                }
            }
            UnionRows::CheckGrep(_) => unreachable!("CheckGrep has its exact pre-rendered stage"),
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
                if (self.selected != Roster::WithWorkspaceFoldPolicies.names() && !self.ordinary_fold_sys)
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
                if meta.name == "ui_actions"
                    && ((self.selected != Roster::WithUiActions.names() && self.selected != PRIVATE_DOC_UI && !self.authored_doc_ui)
                        || !std::ptr::eq(meta, dq_analyze::ui_actions_policy::metadata())
                        || !self.judgment.is_raw())
                {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "UI Actions requires its exact source-only profile"));
                }
                if meta.name == "doc_snippets" {
                    if (self.selected != Roster::WithDocSnippets.names() && self.selected != PRIVATE_DOC_UI && !self.authored_doc_ui)
                        || !std::ptr::eq(meta, dq_analyze::doc_snippets_policy::metadata())
                        || !self.judgment.is_raw()
                    {
                        return Err(io::Error::new(io::ErrorKind::InvalidData, "Docs report requires its exact source-only profile"));
                    }
                    let blocks = tree.doc_blocks().ok_or_else(|| io::Error::other("actual Docs summary phase missing"))?;
                    kc::reserve(&mut control, || blocks.len().checked_mul(512)?.checked_add(4096)).map_err(operational)?;
                    doc_summary = Some(blocks);
                }
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
            UnionRows::MapEdits(sites) => {
                if (self.selected != Roster::WithMapEdits.names() && self.selected != PRIVATE_MAP_AND_LAYERING && !self.authored_doc_ui)
                    || !std::ptr::eq(meta, &dq_analyze::map_edits_policy::META)
                    || !matches!(meta.policy, Policy::Hard)
                {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "map_edits requires its exact Hard report profile"));
                }
                for site in sites {
                    projection.row(site, None, &mut control)?;
                }
            }
            UnionRows::Keys(data) => {
                if (self.selected != Roster::WithKeys.names() && !self.ordinary_semantic_and_fixed)
                    || !std::ptr::eq(meta, dq_analyze::keys_policy::metadata())
                    || !matches!(meta.policy, Policy::Hard)
                {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "keys require their exact Hard report profile"));
                }
                for site in data.sites() {
                    projection.row(site, None, &mut control)?;
                }
            }
            UnionRows::DerivedReads(data) => {
                if (self.selected != Roster::WithDerivedReads.names() && !self.private_derived_reads) || !std::ptr::eq(meta, data.metadata())
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
                    Q::EngineLayeringFullAllow => (&[Roster::WithEngineLayering], dq_analyze::engine_layering_policy::metadata()),
                    Q::Lifeforms => (&[Roster::WithLifeforms, Roster::WithLifeformsAndPlayerLink], dq_analyze::lifeforms_policy::metadata()),
                    Q::PlayerLink => (&[Roster::WithPlayerLink, Roster::WithLifeformsAndPlayerLink], dq_analyze::player_link_policy::metadata()),
                    Q::UntypedMember => (&[Roster::WithReferencePolicies], dq_analyze::untyped_member_policy::metadata()),
                    Q::WeakRawRead => (&[Roster::WithReferencePolicies], dq_analyze::weak_relation_policy::metadata()),
                    Q::RelWriteUndeclared => (&[Roster::WithReferencePolicies], dq_analyze::rel_write_policy::metadata()),
                    _ => return Err(io::Error::new(io::ErrorKind::InvalidData, "unissued message-only selected report role")),
                };
                let joined_engine = (self.selected == PRIVATE_MAP_AND_LAYERING || self.authored_doc_ui)
                    && question == Q::EngineLayeringFullAllow;
                let joined_semantic = self.ordinary_semantic_and_fixed && matches!(question,
                    Q::Lifeforms | Q::PlayerLink | Q::UntypedMember | Q::WeakRawRead | Q::RelWriteUndeclared);
                if (!joined_engine && !joined_semantic && !rosters.iter().any(|roster| self.selected == roster.names()))
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
                if (self.selected != Roster::WithDeclarationPolicies.names() && !self.ordinary_semantic_and_fixed)
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
            UnionRows::StoredAndTracked(question, sites, source_text, notes) => {
                let expected = match question {
                    Q::StoredRefs => dq_analyze::stored_refs_policy::metadata(),
                    Q::Tracked => dq_analyze::tracked_policy::metadata(false),
                    Q::TrackedTests => dq_analyze::tracked_policy::metadata(true),
                    _ => return Err(io::Error::new(io::ErrorKind::InvalidData, "unissued stored or tracked role")),
                };
                if (self.selected != Roster::WithStoredAndTracked.names() && !self.private_checker_body)
                    || !std::ptr::eq(meta, expected) || !matches!(meta.policy, Policy::Hard)
                    || sites.len() != source_text.len()
                {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "stored or tracked findings differ from their issued Hard shape"));
                }
                for (site, text) in sites.iter().zip(source_text) {
                    projection.row(site, Some(text), &mut control)?;
                }
                projection.notes(notes, &mut control)?;
            }
            UnionRows::SysSource(name, sites, source_text) => {
                let expected = match name {
                    "sys/hygiene" => dq_analyze::captured_sys_hygiene_pages::metadata(),
                    "sys/resolvers" => dq_analyze::captured_sys_resolvers_pages::metadata(),
                    "sys/tables" => dq_analyze::captured_sys_tables_pages::metadata(),
                    "system_boundary" => dq_analyze::captured_system_boundary_pages::metadata(),
                    _ => return Err(io::Error::new(io::ErrorKind::InvalidData, "unissued Sys source policy")),
                };
                if (self.selected != Roster::WithSysSourcePolicies.names() && !self.ordinary_fold_sys)
                    || !std::ptr::eq(meta, expected) || !matches!(meta.policy, Policy::Hard)
                    || sites.len() != source_text.len()
                {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "Sys source findings differ from their issued Hard shape"));
                }
                for (site, text) in sites.iter().zip(source_text) {
                    projection.row(site, Some(text), &mut control)?;
                }
            }
            UnionRows::RequirementBool(data) => {
                if (self.selected != Roster::WithRequirementBool.names() && !self.ordinary_semantic_and_fixed)
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
                if (self.selected != Roster::WithSysReactive.names() && !self.ordinary_semantic_and_fixed)
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
                if (self.selected != Roster::WithUntyped.names() && !self.private_checker_body) || !std::ptr::eq(meta, data.metadata())
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
                if (self.selected != Roster::WithLibraryLayering.names()
                    && self.selected != PRIVATE_MAP_AND_LAYERING && !self.authored_doc_ui)
                    || meta.name != "library_layering" || !std::ptr::eq(meta, data.metadata())
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
                |run, text, _| deadline_judge.take().is_some_and(|(parsed, shown)| parsed.finish(run, &shown, text)),
                |run, text| {
                    if let Some(blocks) = doc_summary {
                        return dq_analyze::doc_snippets_policy::finish_summary(meta, root, &source_text, blocks, run, text, raw);
                    }
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
        self.failed.record(self.finished, failed)?;
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
        budget.require().map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))?;
        let failed = data.selected().iter().enumerate()
            .filter_map(|(ordinal, name)| self.failed.failed(ordinal).then_some(name.as_str()))
            .chain((!data.unused().is_empty()).then_some("allow_annotations --unused"));
        policy_finish::write_result_line(failed, &mut self.file)
    }
}

impl super::super::RawWorkspaceSnapshot {
    pub(in crate::runner_host) fn stage_raw_file_report(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, plan: &SelectedReportPlan, file: Stage,
        cache_report: bool, prior: Option<Arc<WorkspaceCapture>>,
    ) -> io::Result<(bool, Verified)> {
        use crate::runner_host::workspace_capture::RawSourcePurpose;
        let roster = plan.roster();
        let purpose = match roster {
            Roster::AllRawFilePolicies => RawSourcePurpose::AllRawFilePolicies,
            Roster::WithDocSnippets => RawSourcePurpose::DocSnippetsFullAllow,
            Roster::WithUiActions => RawSourcePurpose::UiActionsFullAllow,
            _ => return Err(io::Error::new(io::ErrorKind::InvalidData, "unissued source-only report profile")),
        };

        if !plan.judgment.is_raw() {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "source-only report requires raw judgment"));
        }
        self.stage_raw_file_report_using(prepared, exclusions, retained, root, roster.names(),
            purpose, file, cache_report, prior)
    }

    #[cfg(test)]
    pub(super) fn stage_private_doc_ui(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        use crate::runner_host::workspace_capture::RawSourcePurpose;
        self.stage_raw_file_report_using(prepared, exclusions, retained, root, PRIVATE_DOC_UI,
            RawSourcePurpose::DocUiFullAllow, file, false, None)
    }

    fn stage_raw_file_report_using(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, selected: &'static [&'static str],
        purpose: crate::runner_host::workspace_capture::RawSourcePurpose, mut file: Stage,
        cache_report: bool, prior: Option<Arc<WorkspaceCapture>>,
    ) -> io::Result<(bool, Verified)> {
        use crate::{request::BuildOutcome, runner_host::workspace_capture::RawSourcePurpose};
        use dq_analyze::captured_allow_annotations::full_unused::{FrameData, FrameOwner, SelectedTreePlanData, UsageJoinData};
        let BuildOutcome::RawQueryPrepared { query_revision, source_revision, policy_revision, retained: true } = prepared else {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected raw-file preparation did not issue a current source-only frame"));
        };
        let pin = |text: &str| u128::from_str_radix(text, 16).ok();
        let capture = &self.capture;
        let queries = &self.queries;
        let sealed_bulk = purpose == RawSourcePurpose::AllRawFilePolicies;
        if (!sealed_bulk && (cache_report || prior.is_some()))
            || self.source.purpose() != purpose
            || capture.root() != root || capture.configuration().1.is_none()
            || !capture.matches_auxiliary_questions(&[purpose.question()])
            || pin(query_revision) != Some(self.revision())
            || pin(source_revision) != Some(self.source_revision())
            || pin(policy_revision) != Some(self.policy_revision())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected raw-file preparation differs from the actual workspace frame"));
        }
        let guard = super::super::workspace_native_guard::NativeReadGuard::raw_owned(capture, &self.source, queries)?;
        let poll = || {
            retained.require().map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))?;
            crate::daemon::control::checkpoint()?;
            capture.require_scope(&guard)
        };
        queries.require_workspace_report_configuration(capture, &guard).map_err(operational)?;
        let mut work = Operation { budget: retained, poll: &poll };
        let selection = full_unused::registered_full_selection(exclusions, &mut work).map_err(operational)?;
        if !selection.names().iter().map(String::as_str).eq(selected.iter().copied()) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "raw-file scope differs from the registered selected report"));
        }
        if let Some(prior) = prior {
            let replay = queries.restore_bulk_raw_report(capture, &guard, &prior, &mut file)?;
            drop(prior);
            if let Some((clean, hash)) = replay {
                let verified = checked_stage(file)?;
                if verified.hash() != hash {
                    return Err(io::Error::new(io::ErrorKind::InvalidData, "raw terminal report digest differs on replay"));
                }
                poll()?;
                return Ok((clean, verified));
            }
        }
        let producer = |name| Producer::from_name(name).expect("selected raw roster already admitted");
        let selected_tree = SelectedTreePlanData::new(selected.iter().map(|&name| producer(name).metadata().select), &mut work)
            .map_err(operational)?;
        let frame = FrameData {
            owner: FrameOwner::RawQuery(self.revision()),
            source: self.source_revision(),
            configuration: self.policy_revision(),
        };
        let mut usage = UsageJoinData::new(&selection, frame);
        let mut stage = ReportStage {
            file, finished: 0, selected, failed: SectionFailures::new(selected.len(), retained)?,
            authored_doc_ui: false, ordinary_fold_sys: false, ordinary_semantic_and_fixed: false, private_checker_body: false, private_image_dir: false, private_check_grep: false, private_derived_reads: false, judgment: JudgmentV2::Raw, library_baseline: None,
        };
        for &name in selected {
            let policy_started = std::time::Instant::now();
            poll()?;
            let producer = producer(name);
            let meta = producer.metadata();
            match producer {
                Producer::Raw(_) if producer.question().is_none() => {
                    let consume = |
                        rows: &mut dyn Iterator<Item = &dq_analyze::captured_raw_file::Findings>,
                        allows: &mut dyn Iterator<Item = &dq_analyze::lint::AllowUse>,
                        report: Option<(&LintScope, &Arc<Budget>)>,
                    | {
                        let (scope, child) = report.ok_or_else(|| io::Error::other("raw-file producer omitted its report scope"))?;
                        stage.observe(root, meta, ReportRows::Union(UnionRows::Raw(rows)), scope, child)?;
                        usage.record_fold_iter(name, frame, allows, &mut work).map_err(operational)
                    };
                    if sealed_bulk {
                        queries.with_workspace_bulk_raw_union_rows(capture, &guard, name, retained, consume)?;
                    } else {
                        // Joined Docs/UI use an ordinary live raw capture, so
                        // their base raw policies must take the ordinary lender.
                        queries.with_workspace_raw_union_rows(capture, &guard, name, retained, true, consume)?;
                    }
                }
                Producer::Tree(policy) if matches!(policy,
                    dq_analyze::captured_raw_tree_pages::Policy::NoticePublisher
                    | dq_analyze::captured_raw_tree_pages::Policy::ReportInCatch)
                    || (matches!(purpose, RawSourcePurpose::DocSnippetsFullAllow | RawSourcePurpose::DocUiFullAllow)
                        && policy == dq_analyze::captured_raw_tree_pages::Policy::DocSnippets)
                    || (matches!(purpose, RawSourcePurpose::UiActionsFullAllow | RawSourcePurpose::DocUiFullAllow)
                        && policy == dq_analyze::captured_raw_tree_pages::Policy::UiActions) => {
                    queries.with_workspace_raw_tree(capture, &guard, policy, |data, config, child| {
                        let empty = LintScope::default();
                        let scope = config.borrowed_report_scope(meta.name, meta.group).unwrap_or(&empty);
                        stage.observe(root, meta, ReportRows::Union(UnionRows::Tree(data)), scope, child)?;
                        usage.record_fold(name, frame, data.allow_used(), &mut work).map_err(operational)
                    }).map_err(operational)?;
                }
                Producer::Special("allow_annotations") => {
                    queries.with_workspace_allow_annotations(capture, &guard, |data, config, child| {
                        let empty = LintScope::default();
                        let scope = config.borrowed_report_scope(meta.name, meta.group).unwrap_or(&empty);
                        stage.observe(root, meta, ReportRows::Union(UnionRows::Validation(data)), scope, child)?;
                        usage.record_fold(name, frame, &[], &mut work).map_err(operational)
                    }).map_err(operational)?;
                }
                _ => return Err(io::Error::new(io::ErrorKind::Unsupported, "raw-file roster contains a model or foreign producer")),
            }
            dm_profile::detail_mark(name, policy_started);
        }
        let completed = usage.finish_data(&mut work).map_err(operational)?;
        let clean = queries.with_workspace_full_allow_unused(capture, &guard, &selected_tree, &completed, |unused, _, budget| {
            poll()?;
            stage.finish(&CompleteAllowRun { selected: selection.names(), validation: None, unused }, budget)
        }).map_err(operational)?;
        let output = if cache_report {
            queries.finish_bulk_raw_report(capture, &guard, stage.file, clean)?
        } else {
            checked_stage(stage.file)?
        };
        poll()?;
        Ok((clean, output))
    }
}

impl SourceSnapshot {
    pub(in crate::runner_host) fn stage_selected_report(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, plan: &SelectedReportPlan, handlers: Option<&super::super::HandlerWorkspaceSnapshot>, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        self.stage_selected_report_using(prepared, exclusions, retained, root,
            plan.roster().names(), plan.questions(), plan.judgment,
            plan.needs_library_sites_baseline(), plan.requires_handlers(), handlers, file, false, None)
    }

    /// Private until the exact report cohort has an independently qualified wire identity.
    #[cfg(test)]
    pub(super) fn stage_private_image_dir_report(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        self.stage_selected_report_using(prepared, exclusions, retained, root,
            PRIVATE_IMAGE_DIR_ROSTER, &[Q::ImageDir], JudgmentV2::Raw, false, false, None, file, false, None)
    }

    #[cfg(test)]
    pub(super) fn stage_private_map_and_layering(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        let mut control = Operation { budget: retained, poll: &|| crate::daemon::control::checkpoint() };
        let selection = full_unused::registered_full_selection(exclusions, &mut control).map_err(operational)?;
        if !selection.names().iter().map(String::as_str).eq(PRIVATE_MAP_AND_LAYERING.iter().copied()) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "joined capture requires its exact private report roster"));
        }
        self.stage_selected_report_using(prepared, exclusions, retained, root,
            PRIVATE_MAP_AND_LAYERING, Q::SELECTED_MAP_AND_LAYERING,
            JudgmentV2::Raw, false, false, None, file, false, None)
    }

    #[cfg(test)]
    pub(super) fn stage_private_authored_doc_ui(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        let mut control = Operation { budget: retained, poll: &|| crate::daemon::control::checkpoint() };
        let selection = full_unused::registered_full_selection(exclusions, &mut control).map_err(operational)?;
        if !selection.names().iter().map(String::as_str).eq(PRIVATE_AUTHORED_DOC_UI.iter().copied())
            || !self.native_workspace.as_ref().is_some_and(|capture| capture.has_authored_doc_ui_capture())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "mixed report needs its exact private selection and authored capture"));
        }
        self.stage_selected_report_using(prepared, exclusions, retained, root,
            PRIVATE_AUTHORED_DOC_UI, Q::PRIVATE_AUTHORED_DOC_UI,
            JudgmentV2::Raw, false, false, None, file, false, None)
    }

    #[cfg(test)]
    pub(super) fn stage_private_reactive_raw_union(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        let mut control = Operation { budget: retained, poll: &|| crate::daemon::control::checkpoint() };
        let selection = full_unused::registered_full_selection(exclusions, &mut control).map_err(operational)?;
        if !selection.names().iter().map(String::as_str).eq(PRIVATE_REACTIVE_RAW_UNION.iter().copied()) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "reactive/raw report requires its exact private selection"));
        }
        let capture = self.native_workspace.as_ref()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "reactive/raw report needs its actual authored capture"))?;
        let questions = Q::SELECTED_REACTIVE;
        if !capture.matches_auxiliary_questions(questions)
            || !crate::policy_request::exact_code_maps_roots(root, capture.recursive_roots())
            || self.workspace_semantic_inputs(Q::SemReads)?.original_analysis_subject().is_none_or(|subject| subject.synthetic())
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "reactive/raw report capture differs"));
        }
        self.stage_selected_report_using(prepared, exclusions, retained, root,
            PRIVATE_REACTIVE_RAW_UNION, questions, JudgmentV2::Raw, false, false, None, file, false, None)
    }

    #[cfg(test)]
    pub(super) fn stage_private_extended_reactive_raw_union(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        self.stage_private_extended_union(prepared, exclusions, retained, root, file, false, false, false, None, false, false, false, None, false)
    }

    #[cfg(test)]
    pub(super) fn stage_private_extended_authored_doc_ui(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        self.stage_private_extended_union(prepared, exclusions, retained, root, file, true, false, false, None, false, false, false, None, false)
    }

    #[cfg(test)]
    pub(super) fn stage_private_extended_authored_with_ordinary_sources(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        self.stage_private_extended_union(prepared, exclusions, retained, root, file, true, true, false, None, false, false, false, None, false)
    }

    #[cfg(test)]
    pub(super) fn stage_private_extended_authored_with_ordinary_semantics(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage,
    ) -> io::Result<(bool, Verified)> {
        self.stage_private_extended_union(prepared, exclusions, retained, root, file, true, true, true, None, false, false, false, None, false)
    }

    #[cfg(test)]
    pub(super) fn stage_private_extended_authored_with_checker(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage, checker: &crate::request_runner::PreparedCheckerTranscript,
    ) -> io::Result<(bool, Verified)> {
        self.stage_private_extended_union(prepared, exclusions, retained, root, file, true, true, true, Some(checker), false, false, false, None, false)
    }

    #[cfg(test)]
    pub(super) fn stage_private_extended_authored_with_checker_and_image(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage, checker: &crate::request_runner::PreparedCheckerTranscript,
    ) -> io::Result<(bool, Verified)> {
        self.stage_private_extended_union(prepared, exclusions, retained, root, file, true, true, true, Some(checker), true, false, false, None, false)
    }

    #[cfg(test)]
    pub(super) fn stage_private_extended_authored_with_actors(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage, checker: &crate::request_runner::PreparedCheckerTranscript,
    ) -> io::Result<(bool, Verified)> {
        self.stage_private_extended_union(prepared, exclusions, retained, root, file, true, true, true, Some(checker), true, true, false, None, false)
    }

    #[cfg(test)]
    pub(super) fn stage_private_extended_authored_with_check_grep(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage, checker: &crate::request_runner::PreparedCheckerTranscript,
    ) -> io::Result<(bool, Verified)> {
        self.stage_private_extended_union(prepared, exclusions, retained, root, file, true, true, true, Some(checker), true, true, true, None, false)
    }

    #[cfg(test)]
    pub(super) fn stage_private_extended_authored_with_handlers(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage, checker: &crate::request_runner::PreparedCheckerTranscript,
        grep: bool, handlers: &super::super::HandlerWorkspaceSnapshot,
    ) -> io::Result<(bool, Verified)> {
        self.stage_private_extended_union(prepared, exclusions, retained, root, file,
            true, true, true, Some(checker), true, true, grep, Some(handlers), false)
    }

    pub(in crate::runner_host) fn stage_private_full_registry(
        &self, prepared: &crate::request::BuildOutcome, retained: &Arc<Budget>,
        root: &Path, file: Stage, checker: &crate::request_runner::PreparedCheckerTranscript,
        handlers: &super::super::HandlerWorkspaceSnapshot,
    ) -> io::Result<(bool, Verified)> {
        self.stage_private_extended_union(prepared, &[], retained, root, file,
            true, true, true, Some(checker), true, true, true, Some(handlers), true)
    }

    fn stage_private_extended_union(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, file: Stage, mixed: bool, ordinary_fold_sys: bool, ordinary_semantics: bool,
        checker: Option<&crate::request_runner::PreparedCheckerTranscript>, image_dir: bool, actors: bool, grep: bool,
        handlers: Option<&super::super::HandlerWorkspaceSnapshot>, derived: bool,
    ) -> io::Result<(bool, Verified)> {
        let mut control = Operation { budget: retained, poll: &|| crate::daemon::control::checkpoint() };
        let selection = full_unused::registered_full_selection(exclusions, &mut control).map_err(operational)?;
        let raw = Roster::AllRawFilePolicies.names();
        let extra = if mixed { PRIVATE_AUTHORED_DOC_UI } else { &[] };
        let fold = if ordinary_fold_sys { Roster::WithWorkspaceFoldPolicies.names() } else { &[] };
        let sys = if ordinary_fold_sys { Roster::WithSysSourcePolicies.names() } else { &[] };
        let semantic = if ordinary_semantics { PRIVATE_ORDINARY_SEMANTIC_AND_FIXED } else { &[] };
        let bodies = if checker.is_some() { &["stored_refs", "tracked", "tracked_tests", "untyped"][..] } else { &[] };
        let image = if image_dir { &["image_dir_after_build"][..] } else { &[] };
        let silicon = if actors { &["silicon_entry"][..] } else { &[] };
        let grep_policy = if grep { &["check_grep"][..] } else { &[] };
        let handler = if handlers.is_some() { &["sem/handlers"][..] } else { &[] };
        let derived_policy = if derived { &["derived_reads"][..] } else { &[] };
        let qualified = || raw.iter().chain(PRIVATE_REACTIVE_RAW_UNION).chain(extra).chain(fold).chain(sys).chain(semantic).chain(bodies).chain(image).chain(silicon).chain(grep_policy).chain(handler).chain(derived_policy);
        let selected = selection.names();
        if selected.iter().any(|name| !qualified().any(|&actual| name == actual))
            || qualified().any(|&name| !selected.iter().any(|actual| actual == name))
        {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "extended reactive/raw report needs its exact registered union"));
        }

        let workspace = self.native_workspace.as_ref()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "extended reactive/raw report needs an authored capture"))?;
        let child = self.workspace_semantic_inputs(Q::SemReads)?;
        let subject = child.original_analysis_subject().filter(|subject| !subject.synthetic())
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "extended reactive/raw report needs an authored subject"))?;
        workspace.require_analysis_subject(subject)?;
        subject.require_bound_mapping(child.policy().mapping())?;
        let guard = self.workspace_native_read()?;
        workspace.require_scope(&guard)?;
        let questions = if derived { Q::PRIVATE_FULL_REGISTRY }
            else if handlers.is_some() && grep { Q::PRIVATE_EXTENDED_AUTHORED_WITH_GREP_AND_HANDLERS }
            else if handlers.is_some() { Q::PRIVATE_EXTENDED_AUTHORED_WITH_HANDLERS }
            else if grep { Q::PRIVATE_EXTENDED_AUTHORED_WITH_GREP }
            else if actors { Q::PRIVATE_EXTENDED_AUTHORED_WITH_ACTORS }
            else if image_dir { Q::PRIVATE_EXTENDED_AUTHORED_WITH_CHECKER_AND_IMAGE }
            else if checker.is_some() { Q::PRIVATE_EXTENDED_AUTHORED_WITH_CHECKER }
            else if ordinary_semantics { Q::PRIVATE_EXTENDED_AUTHORED_ORDINARY_SEMANTIC }
            else if mixed { Q::PRIVATE_EXTENDED_AUTHORED_DOC_UI } else { Q::SELECTED_REACTIVE };
        let has_domains = if mixed {
            workspace.has_extended_authored_doc_ui_capture()
        } else {
            workspace.covers_extended_reactive_raw_domains(&mut |bytes| {
                retained.charge(bytes).map_err(|m| io::Error::new(io::ErrorKind::OutOfMemory, m))
            })?
        };
        if workspace.root() != root || !has_domains {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "extended reactive/raw report lacks its observed source roots"));
        }

        let mut order = Vec::new();
        for name in selected {
            kc::row(&mut control, &mut order).map_err(operational)?;
            order.push(name.as_str());
        }
        self.stage_selected_report_using(prepared, exclusions, retained, root,
            &order, questions, JudgmentV2::Raw, false, handlers.is_some(), handlers, file, ordinary_fold_sys, checker)
    }

    fn stage_selected_report_using(
        &self, prepared: &crate::request::BuildOutcome, exclusions: &[String], retained: &Arc<Budget>,
        root: &Path, selected: &[&str], questions: &[Q], judgment: JudgmentV2,
        needs_library_sites_baseline: bool, requires_handlers: bool,
        handlers: Option<&super::super::HandlerWorkspaceSnapshot>, file: Stage, ordinary_fold_sys: bool,
        checker: Option<&crate::request_runner::PreparedCheckerTranscript>,
    ) -> io::Result<(bool, Verified)> {
        use crate::request::BuildOutcome;
        let BuildOutcome::QueryPrepared { semantic_revision, source_revision, policy_revision: Some(policy_revision), retained: true } = prepared else {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report preparation did not issue a current Original frame"));
        };
        let pin = |text: &str| u128::from_str_radix(text, 16).ok();
        let workspace = self.native_workspace.as_ref().ok_or_else(|| io::Error::other("selected report has no actual workspace"))?;
        if workspace.root() != root || workspace.configuration().1.is_none()
            || !workspace.matches_auxiliary_questions(questions)
            || ordinary_fold_sys && !workspace.has_extended_authored_doc_ui_capture()
            || handlers.is_some() != requires_handlers
            || pin(semantic_revision) != Some(self.tree.identity()) || pin(source_revision) != Some(self.source_revision)
            || pin(policy_revision) != Some(workspace.policy_revision()) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "selected report preparation differs from its current workspace"));
        }
        let private_checker_body = Q::is_private_authored_checker(questions);
        match checker {
            Some(checker) if private_checker_body => {
                self.require_staged_checker_body_domain(checker)?;
                crate::daemon::selected_report_wire::Frame::from_prepared(prepared)?
                    .require_checker_frame(checker.frame)?;
            }
            None if !private_checker_body => {}
            _ => return Err(io::Error::new(io::ErrorKind::InvalidInput, "private Checker transcript purpose differs")),
        }
        let library_baseline = if needs_library_sites_baseline {
            let guard = self.workspace_native_read()?;
            Some(workspace.library_sites_baseline(&guard)?)
        } else { None };
        let stage = RefCell::new(ReportStage {
            file, finished: 0, selected, failed: SectionFailures::new(selected.len(), retained)?,
            authored_doc_ui: workspace.has_authored_doc_ui_capture(), ordinary_fold_sys,
            ordinary_semantic_and_fixed: ordinary_fold_sys && (private_checker_body || questions == Q::PRIVATE_EXTENDED_AUTHORED_ORDINARY_SEMANTIC),
            private_checker_body,
            private_image_dir: questions == Q::PRIVATE_EXTENDED_AUTHORED_WITH_CHECKER_AND_IMAGE
                || Q::is_private_authored_actor_domain(questions)
                || Q::is_private_grep_domain(questions),
            private_check_grep: Q::is_private_grep_domain(questions),
            private_derived_reads: questions == Q::PRIVATE_FULL_REGISTRY,
            judgment, library_baseline,
        });
        let clean = self.with_native_allow_full_run_using(&self.tree, exclusions, Some(retained), handlers, private_checker_body, Some(&mut |meta, rows, scope, budget| {
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
    #[test]
    fn section_status_funds_the_actual_order_and_checks_its_end() {
        use super::{Budget, SectionFailures};
        let sections = super::Roster::MAX_STAGED_POLICIES * 2 + 3;
        let bytes = sections.div_ceil(u8::BITS as usize);
        let budget = Budget::new(4096).unwrap();
        let before = budget.used();
        let mut status = SectionFailures::new(sections, &budget).unwrap();
        assert_eq!(budget.used() - before, bytes);
        assert_eq!(status.bits.capacity(), bytes);
        for ordinal in [0, 7, 8, sections - 1] {
            status.record(ordinal, true).unwrap();
        }
        assert_eq!(
            (0..sections).filter(|&ordinal| status.failed(ordinal)).collect::<Vec<_>>(),
            [0, 7, 8, sections - 1],
        );
        assert_eq!(status.record(sections, false).unwrap_err().kind(), std::io::ErrorKind::InvalidData);

        let tiny = Budget::new(before + bytes - 1).unwrap();
        let error = SectionFailures::new(sections, &tiny).err().expect("bitmap must be prepaid");
        assert_eq!(error.kind(), std::io::ErrorKind::OutOfMemory);
        assert_eq!(tiny.used(), before);
    }

    use super::*;

    #[test]
    fn selected_v1_aliases_derive_the_exact_previous_capture_profiles() {
        let budget = Budget::new(1 << 20).unwrap();
        let mut work = Operation { budget: &budget, poll: &|| Ok(()) };
        let registry = full_unused::registered_full_selection(&[], &mut work).unwrap();
        let expected: [(Roster, &[Q]); Roster::ALL.len()] = [
            (Roster::Base, &[]),
            (Roster::AllRawFilePolicies, &[]),
            (Roster::WithDocSnippets, &[Q::DocSnippetsFullAllow]),
            (Roster::WithUiActions, &[Q::UiActionsFullAllow]),
            (Roster::WithWorkspaceFoldPolicies, &[]),
            (Roster::WithSysSourcePolicies, &[]),
            (Roster::WithStoredAndTracked, Q::SELECTED_STORED_AND_TRACKED),
            (Roster::WithRawRuntimePolicies, &[]),
            (Roster::WithRawDeclarationPolicies, &[]),
            (Roster::WithCooldown, &[]),
            (Roster::WithEngineInternal, &[]),
            (Roster::WithDeadlinePolling, &[Q::DeadlinePollingAllowlist]),
            (Roster::WithCheckGrep, &[Q::CheckGrep]),
            (Roster::WithSilicon, &[Q::SiliconEntry]),
            (Roster::WithLibraryLayering, &[Q::LibraryLayeringFullAllow]),
            (Roster::WithEngineLayering, &[Q::EngineLayeringFullAllow]),
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
            (Roster::WithKeys, &[Q::Keys]),
            (Roster::WithMapEdits, &[Q::MapEdits]),
            (Roster::WithOrderAndOwnership, Q::SELECTED_ORDER_AND_OWNERSHIP),
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
        failed: SectionFailures::new(1, budget)?,
        authored_doc_ui: false,
        ordinary_fold_sys: false,
        ordinary_semantic_and_fixed: false,
        private_checker_body: false,
        private_image_dir: false,
        private_check_grep: false,
        private_derived_reads: false,
        judgment: JudgmentV2::Raw,
        library_baseline: None,
    };
    stage.observe(root, meta, ReportRows::ImageDir(&data), scope, budget)?;
    if stage.finished != 1 {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "named ImageDir section did not complete"));
    }
    let clean = !stage.failed.failed(0);
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
