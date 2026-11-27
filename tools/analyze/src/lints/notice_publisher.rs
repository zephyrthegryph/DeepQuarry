//! `notice_publisher`: a subscriber waits for a notice nothing publishes (doc/rewrite/reactions.md section 3).
//!
//! `on_notice(/datum/notice/x, ...)` or `observe(E, /datum/notice/x, ...)` on a type nobody publishes is behaviour that silently never runs. A notice has a
//! publisher when the type or a subtype (a handler hears its subtypes) is named on a line that publishes it (`PUBLISH_LEGACY`, `publish(`, `take_notice`,
//! `notice_take`, a `*_publish(` helper), is assigned to a `notice`/`notice_type` var (a publisher reading its type from data), or is the notice of an `ACTION()`
//! whose `act_x`, `publish_x`, `ACT_ATTEMPT(E, x` or `PUBLISH(E, x` appears. Publishers in code/tests only count for subscribers in code/tests. The check is
//! textual: it proves a publishing line exists, not that its proc runs (tools/ci/dead_code_scan.py lists procs nothing names). Generated files are not read.

use std::collections::{BTreeMap, BTreeSet};

use crate::gens::actions::past_tense;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "nothing publishes this notice, so this subscriber never runs: wire up the publisher, or delete the subscriber and the notice. doc/rewrite/reactions.md section 3";

static META: Meta = Meta {
    name: "notice_publisher",
    group: "",
    label: "notice_publisher",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "no_publisher", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct NoticePublisher {
    path: Pat,
    subscribes: Pat,
    publishes: Pat,
    assigned: Pat,
    action: Pat,
    action_notice: Pat,
    token_call: Pat,
    token_macro: Pat,
}

impl NoticePublisher {
    fn new() -> NoticePublisher {
        NoticePublisher {
            path: Pat::new(r"/datum/notice/([A-Za-z0-9_/]+)"),
            subscribes: Pat::new(r"(?:^|[^\w])(?:on_notice|observe)\("),
            publishes: Pat::new(r"PUBLISH_LEGACY\(|(?:^|[^\w])publish\(|take_notice\(|notice_take\(|\w_publish\("),
            assigned: Pat::new(r"\bnotice(?:_type)?\s*=\s*/datum/notice/([A-Za-z0-9_/]+)"),
            action: Pat::new(r"^ACTION\(\s*([A-Za-z0-9_/]+)"),
            action_notice: Pat::new(r"\bnotice\s*=\s*/datum/notice/([A-Za-z0-9_/]+)"),
            token_call: Pat::new(r"\b(?:act|publish)_(\w+)"),
            token_macro: Pat::new(r"\b(?:ACT_ATTEMPT|PUBLISH)\([^,]*,\s*(\w+)"),
        }
    }
}

fn is_test(rel: &str) -> bool {
    rel.starts_with("code/tests/")
}

impl Lint for NoticePublisher {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        // Each pair is [live, tests].
        let mut published: [BTreeSet<String>; 2] = Default::default();
        let mut tokens: [BTreeSet<String>; 2] = Default::default();
        let mut actions: BTreeMap<String, String> = BTreeMap::new();
        let sources: Vec<&SourceFile> = cx.all_files().into_iter().filter(|f| !f.rel.contains("/_generated/")).collect();
        // What each file declares and publishes, kept per file (`crate::incr`), folded in file order.
        let facts: Vec<Published> = crate::incr::facts("notice_publisher-published", &sources, |f| {
            let mut p = Published::default();
            for (_, text) in f.code().numbered() {
                if let Some(c) = self.action.captures(text) {
                    let name = c.s(1).to_string();
                    let notice = self.action_notice.captures(text).map(|n| n.s(1).to_string()).unwrap_or_else(|| past_tense(&name));
                    p.actions.push((name.replace('/', "_"), notice));
                    continue;
                }
                if text.starts_with("/datum/notice/") {
                    continue;
                }
                for c in self.token_call.captures_iter(text) {
                    p.tokens.push(c.s(1).to_string());
                }
                for c in self.token_macro.captures_iter(text) {
                    p.tokens.push(c.s(1).to_string());
                }
                if self.publishes.is_match(text) {
                    for c in self.path.captures_iter(text) {
                        p.published.push(c.s(1).to_string());
                    }
                }
                for c in self.assigned.captures_iter(text) {
                    p.published.push(c.s(1).to_string());
                }
            }
            p
        });
        for (f, p) in sources.iter().zip(facts) {
            let side = is_test(&f.rel) as usize;
            for (name, notice) in p.actions {
                actions.insert(name, notice);
            }
            tokens[side].extend(p.tokens);
            published[side].extend(p.published);
        }
        for side in 0..2 {
            for (token, notice) in &actions {
                if tokens[side].contains(token) {
                    published[side].insert(notice.clone());
                }
            }
        }
        let heard = |set: &BTreeSet<String>, t: &str| {
            let child = format!("{}/", t);
            set.contains(t) || set.range(child.clone()..).next().is_some_and(|p| p.starts_with(&child))
        };
        let subscribers: Vec<&SourceFile> = cx.files().into_iter().filter(|f| !f.rel.contains("/_generated/")).collect();
        // Each file's subscriptions (line, notice path), kept per file.
        let subscriptions: Vec<Vec<(usize, String)>> = crate::incr::facts("notice_publisher-subscriptions", &subscribers, |f| {
            let mut out = Vec::new();
            for (n, text) in f.code().numbered() {
                if !self.subscribes.is_match(text) {
                    continue;
                }
                for c in self.path.captures_iter(text) {
                    out.push((n, c.s(1).to_string()));
                }
            }
            out
        });
        for (f, subs) in subscribers.iter().zip(subscriptions) {
            let f: &SourceFile = f;
            let test = is_test(&f.rel);
            {
                for (n, t) in &subs {
                    let (n, t) = (*n, t.as_str());
                    if heard(&published[0], t) || (test && heard(&published[1], t)) {
                        continue;
                    }
                    if !out.allowed_here(f, n, "notice_publisher") {
                        out.site_in_msg("no_publisher", &f.rel, n, format!("a subscriber waits for /datum/notice/{}, which nothing publishes", t));
                    }
                }
            }
        }
    }
}

/// What one file declares and publishes (`notice_publisher-published`): ACTION names with their notices, tokens, notice paths.
#[derive(Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
struct Published {
    actions: Vec<(String, String)>,
    tokens: Vec<String>,
    published: Vec<String>,
}

pub fn register(reg: &mut Registry) {
    reg.add(NoticePublisher::new());
}
