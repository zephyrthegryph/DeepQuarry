//! `read_back`: a notice handler writes into its notice, so the sender reads it back, but the notice type does not declare
//! `read_back = TRUE` (doc/rewrite/reactions.md section 3).
//!
//! publish() queues a notice published inside another delivery until that delivery finishes. A sender that reads back what the
//! handlers wrote (examine lines, a scaled amount, post-change callbacks) would then read its list before any handler ran. A
//! notice type that declares `read_back = TRUE` is answered at once instead (rx_answer_notice()). This lint finds handlers that
//! write into a notice, either a field (`event.texts += x`, `N.ref[1] = y`) or a list read from a field (`var/list/l = event.texts`
//! then `l += x`), and fails when the notice type (or an ancestor) is not declared read_back.
//!
//! A handler's notice is a variable typed `/datum/notice/...` that is a proc parameter or is cast from a bare name (`= N`); a notice
//! the code takes itself (`= notice_take(...)`, `= take_notice(...)`) is a sender filling it, not a handler, and is not counted.

use std::collections::{BTreeMap, BTreeSet};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::CODE_DM;

const HINT: &str = "the sender reads back what this handler writes, but a notice published inside another delivery is queued: declare `read_back = TRUE` \
on the notice type so publish() answers it at once. doc/rewrite/reactions.md section 3";

static META: Meta = Meta {
    name: "read_back",
    group: "",
    label: "read_back",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "undeclared_read_back", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct ReadBack {
    type_head: Pat,
    read_back_decl: Pat,
    notice_var: Pat,
    list_alias: Pat,
}

impl ReadBack {
    fn new() -> ReadBack {
        ReadBack {
            type_head: Pat::new(r"^/datum/notice/([A-Za-z0-9_/]+?)/?\s*$"),
            read_back_decl: Pat::new(r"^\s+read_back\s*=\s*(TRUE|1)\b"),
            notice_var: Pat::new(r"(?:var/)?datum/notice/([A-Za-z0-9_/]+)/([A-Za-z_]\w*)\s*(=\s*([^\n]*))?"),
            list_alias: Pat::new(r"var/list/([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*(?:\|\|.*)?$"),
        }
    }
}

fn writes(line: &str, name: &str, field: bool) -> bool {
    let n = regex::escape(name);
    let target = if field { format!(r"\b{}\.\w+", n) } else { format!(r"(?:^|[^.\w]){}", n) };
    let assign = regex::Regex::new(&format!(r"{}\s*(?:\[[^\]]*\])?\s*(?:\+=|-=|\|=|\*=|/=|&=|=[^=])", target)).unwrap();
    let call = regex::Regex::new(&format!(r"{}\.(?:Add|Insert|Cut|Remove|Swap)\(", target)).unwrap();
    assign.is_match(line) || call.is_match(line)
}

fn declared(types: &BTreeSet<String>, t: &str) -> bool {
    let mut cur = t;
    loop {
        if types.contains(cur) {
            return true;
        }
        match cur.rsplit_once('/') {
            Some((parent, _)) => cur = parent,
            None => return false,
        }
    }
}

impl Lint for ReadBack {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        // Every notice type that declares read_back, tree-wide.
        let mut read_back: BTreeSet<String> = BTreeSet::new();
        for f in cx.all_files() {
            let mut current: Option<String> = None;
            for (_, text) in f.code().numbered() {
                if !text.starts_with('\t') && !text.starts_with(' ') && !text.trim().is_empty() {
                    current = self.type_head.captures(text).map(|c| c.s(1).to_string());
                    continue;
                }
                if let Some(t) = &current {
                    if self.read_back_decl.is_match(text) {
                        read_back.insert(t.clone());
                    }
                }
            }
        }
        for f in cx.files() {
            let lines: Vec<(usize, &str)> = f.code().numbered().collect();
            let mut i = 0;
            while i < lines.len() {
                let head = lines[i].1;
                let top = !head.starts_with('\t') && !head.starts_with(' ') && !head.trim().is_empty();
                if !(top && head.contains('(')) {
                    i += 1;
                    continue;
                }
                let mut j = i + 1;
                while j < lines.len() && (lines[j].1.trim().is_empty() || lines[j].1.starts_with('\t') || lines[j].1.starts_with(' ')) {
                    j += 1;
                }
                // fill() and the generated make_notice() are the notice filling itself.
                if head.contains("/fill(") || head.contains("/make_notice(") {
                    i = j;
                    continue;
                }
                let mut notices: BTreeMap<String, String> = BTreeMap::new();
                let mut aliases: BTreeMap<String, String> = BTreeMap::new();
                for c in self.notice_var.captures_iter(head) {
                    notices.insert(c.s(2).to_string(), c.s(1).to_string());
                }
                for &(n, text) in &lines[i + 1..j] {
                    if let Some(c) = self.notice_var.captures(text) {
                        let rhs = c.get(4).map(|m| m.trim()).unwrap_or("");
                        let bare = !rhs.is_empty() && rhs.chars().all(|ch| ch.is_alphanumeric() || ch == '_');
                        if bare {
                            notices.insert(c.s(2).to_string(), c.s(1).to_string());
                        }
                        continue;
                    }
                    if let Some(c) = self.list_alias.captures(text) {
                        if let Some(t) = notices.get(c.s(2)) {
                            aliases.insert(c.s(1).to_string(), t.clone());
                        }
                        continue;
                    }
                    let mut hit: Option<&String> = None;
                    for (v, t) in &notices {
                        if writes(text, v, true) {
                            hit = Some(t);
                        }
                    }
                    for (a, t) in &aliases {
                        if writes(text, a, false) {
                            hit = Some(t);
                        }
                    }
                    if let Some(t) = hit {
                        if !declared(&read_back, t) && !out.allowed_here(f, n, "read_back") {
                            out.site_in_msg("undeclared_read_back", &f.rel, n, format!("a handler writes into /datum/notice/{}, which does not declare read_back", t));
                        }
                    }
                }
                i = j;
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(ReadBack::new());
}
