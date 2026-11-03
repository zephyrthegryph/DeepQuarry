//! Shared read-back schema and selected-file judgment.
use std::collections::{BTreeMap,BTreeSet};
use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::pat::Pat;
use crate::tree::{SourceFile,CODE_DM};
use crate::raw_tree_report::Reporter;
const HINT: &str = "the sender reads back what this handler writes, but a notice published inside another delivery is queued: declare `read_back = TRUE` \
on the notice type so publish() answers it at once. doc/rewrite/reactions.md section 3";

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::read_back::SCOPE_META_0.name,
    group: crate::allow_registry_fields::read_back::SCOPE_META_0.group,
    label: "read_back",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "undeclared_read_back", hint: HINT }],
    allow: crate::allow_registry_fields::read_back::ALLOW_0,
    lists: crate::allow_registry_fields::read_back::SCOPE_META_0.lists,
};

pub struct ReadBack {
    type_head: Pat,
    read_back_decl: Pat,
    notice_var: Pat,
    list_alias: Pat,
}

impl ReadBack {
    pub fn new() -> ReadBack {
        ReadBack {
            type_head: Pat::new(r"^/datum/notice/([A-Za-z0-9_/]+?)/?\s*$"),
            read_back_decl: Pat::new(r"^\s+read_back\s*=\s*(TRUE|1)\b"),
            notice_var: Pat::new(r"(?:var/)?datum/notice/([A-Za-z0-9_/]+)/([A-Za-z_]\w*)\s*(=\s*([^\n]*))?"),
            list_alias: Pat::new(r"var/list/([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*(?:\|\|.*)?$"),
        }
    }
}

fn writes(line: &str, name: &str, field: bool) -> bool {
    crate::raw_name_match::writes(line, name, field)
}

fn declared_using<C:crate::key_policy_control::Control>(types:&BTreeSet<String>,t:&str,c:&mut C)->Result<bool,C::Error>{let mut cur=t;loop{c.checkpoint()?;if types.contains(cur){return Ok(true)}match cur.rsplit_once('/'){Some((parent,_))=>cur=parent,None=>return Ok(false)}}}



pub fn schema(f:&SourceFile,p:&ReadBack,mut visit:impl FnMut(&str)){schema_using(f,p,visit,&mut crate::key_policy_control::Compatibility).expect("original read_back source index")}
pub fn schema_using<C:crate::key_policy_control::Control>(f:&SourceFile,p:&ReadBack,mut visit:impl FnMut(&str),c:&mut C)->Result<(),C::Error>{c.checkpoint()?;
            let mut current: Option<&str> = None;
            for (_, text) in f.code().numbered() {c.checkpoint()?;
                if !text.starts_with('\t') && !text.starts_with(' ') && !text.trim().is_empty() {
                    current = p.type_head.captures(text).map(|c| c.s(1));
                    continue;
                }
                if let Some(t) = &current {
                    if p.read_back_decl.is_match(text) {
                        visit(t);
                    }
                }
            }
c.checkpoint()?;Ok(())}
pub fn judge_file(f:&SourceFile,p:&ReadBack,read_back:&BTreeSet<String>,out:&mut impl Reporter){judge_file_using(f,p,read_back,out,&mut crate::key_policy_control::Compatibility).expect("original read-back judge")}
pub fn judge_file_using<C:crate::key_policy_control::Control>(f:&SourceFile,p:&ReadBack,read_back:&BTreeSet<String>,out:&mut impl Reporter,c:&mut C)->Result<(),C::Error>{c.checkpoint()?;crate::key_policy_control::reserve(c,||f.text().len().checked_mul(8)?.checked_add(1024))?;
            crate::key_policy_control::reserve(c,||f.text().len().checked_add(1)?.checked_mul(4*std::mem::size_of::<(usize,&str)>())?.checked_add(128))?;let lines:Vec<(usize,&str)>=f.code().numbered().collect();if C::CHECKED&&lines.capacity()>f.text().len().saturating_add(1).saturating_mul(4){return Err(c.allocation_failed())}
            let mut i = 0;
            while i < lines.len() {c.checkpoint()?;
                let head = lines[i].1;
                let top = !head.starts_with('\t') && !head.starts_with(' ') && !head.trim().is_empty();
                if !(top && head.contains('(')) {
                    i += 1;
                    continue;
                }
                let mut j = i + 1;
                while j < lines.len() && (lines[j].1.trim().is_empty() || lines[j].1.starts_with('\t') || lines[j].1.starts_with(' ')) {
                    c.checkpoint()?;j += 1;
                }
                // fill() and the generated make_notice() are the notice filling itself.
                if head.contains("/fill(") || head.contains("/make_notice(") {
                    i = j;
                    continue;
                }
                let mut notices: BTreeMap<String, String> = BTreeMap::new();
                let mut aliases: BTreeMap<String, String> = BTreeMap::new();
                for capture in p.notice_var.captures_iter(head) {
                    c.checkpoint()?;crate::key_policy_control::reserve(c,||Some(2048))?;notices.insert(crate::raw_tree_report::own(c,capture.s(2))?,crate::raw_tree_report::own(c,capture.s(1))?);
                }
                for &(n, text) in &lines[i + 1..j] {c.checkpoint()?;
                    if let Some(capture) = p.notice_var.captures(text) {
                        let rhs = capture.get(4).map(|m| m.trim()).unwrap_or("");
                        let bare = !rhs.is_empty() && rhs.chars().all(|ch| ch.is_alphanumeric() || ch == '_');
                        if bare {
                            crate::key_policy_control::reserve(c,||Some(2048))?;notices.insert(crate::raw_tree_report::own(c,capture.s(2))?,crate::raw_tree_report::own(c,capture.s(1))?);
                        }
                        continue;
                    }
                    if let Some(capture) = p.list_alias.captures(text) {
                        if let Some(t) = notices.get(capture.s(2)) {
                            crate::key_policy_control::reserve(c,||Some(2048))?;aliases.insert(crate::raw_tree_report::own(c,capture.s(1))?,crate::raw_tree_report::own(c,t)?);
                        }
                        continue;
                    }
                    let mut hit: Option<&String> = None;
                    for (v, t) in &notices {c.checkpoint()?;
                        if writes(text, v, true) {
                            hit = Some(t);
                        }
                    }
                    for (a, t) in &aliases {c.checkpoint()?;
                        if writes(text, a, false) {
                            hit = Some(t);
                        }
                    }
                    if let Some(t) = hit {
                        if !declared_using(read_back,t,c)? && !out.allowed_here(f, n, "read_back") {
                            out.site_in_msg("undeclared_read_back", &f.rel, n, format!("a handler writes into /datum/notice/{}, which does not declare read_back", t));
                        }
                    }
                }
                i = j;
            }
        c.checkpoint()?;Ok(())}
