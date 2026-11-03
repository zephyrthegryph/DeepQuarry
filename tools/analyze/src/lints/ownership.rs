//! Old registry entry around the SAME shared ownership policy kernels.
use crate::ownership_policy::*;
use crate::lint::{Cx,Lint,Meta,Registry,Sink,AllowUse};
use crate::parity::{Parity,ParseKind};
use crate::dm::ownership_index::{self as oi,Index,OrdMap};
use crate::incr;
use std::{collections::{HashMap,BTreeSet},sync::RwLock};

struct Ownership;

impl Lint for Ownership {
    fn meta(&self) -> &Meta {
        crate::ownership_policy::metadata()
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let files = cx.files();
        let mut problems: Vec<Problem> = Vec::new();

        // ---- the index-independent per-line checks run beside the index and the usage scan
        let (contents, (idx, scans)) = rayon::join(
            || oi::sharded_facts("ownership-content", &files, content_checks),
            || {
                let idx = Index::get(cx.tree, &all);
                // ---- the assignment index: accessor usage per var name and receiver type. A file's
                // scan reads the members and name declarations only, so it is cached under their key.
                let scans: Vec<UsageScan> = oi::sharded_keyed("ownership-usage", idx.key_members, &all, |f| usage_scan(&idx, f));
                (idx, scans)
            },
        );
        let mut usage: OrdMap<UsageKinds> = OrdMap::new();
        let mut unknown: Vec<Problem> = Vec::new();
        for (f, sc) in all.iter().zip(scans) {
            for (name, kind, rtype, no) in sc.events {
                let u = usage.entry_or_insert_with(&name, UsageKinds::default);
                let set = match kind {
                    0 => &mut u.own,
                    1 => &mut u.rel,
                    2 => &mut u.proto,
                    4 => &mut u.relw,
                    _ => &mut u.shared,
                };
                set.insert((rtype, f.rel.clone(), no as usize));
            }
            for (no, msg) in sc.unknown {
                unknown.push(Problem { check: "unknown_var", rel: f.rel.clone(), line: no as usize, msg });
            }
        }
        problems.extend(unknown);
        // What a per-file raw_write judgement reads of the usage map: the receiver types only.
        fn types_of(set: &BTreeSet<Loc>) -> Vec<&str> {
            let mut v: Vec<&str> = set.iter().map(|(t, _, _)| t.as_str()).collect();
            v.dedup();
            v
        }
        let usage_types: Vec<(&str, [Vec<&str>; 4])> =
            usage.iter().map(|(name, u)| (name, [types_of(&u.own), types_of(&u.rel), types_of(&u.relw), types_of(&u.proto)])).collect();
        let judge_key = incr::mix(&[idx.key_struct, incr::ctx_key(&usage_types)]);
        let cxt=Ctx::new(idx.clone(),usage);

        // ---- raw_write per file, beside the whole-tree checks (kinds, matrix, contradictions)
        let (raws, global) = rayon::join(
            || -> Vec<RawOut> { oi::sharded_keyed("ownership-raw", judge_key, &files, |f| raw_checks(&cxt, f)) },
            || -> Vec<Problem>{crate::ownership_policy::judge_global_using(&idx,&cxt,&mut crate::key_policy_control::Compatibility).unwrap_or_else(|never|match never{})},
        );

        // ---- string_name (first, as the Python's second loop), per-line checks collected for later
        let mut line_problems: Vec<Problem> = Vec::new();
        let mut uses: Vec<AllowUse> = Vec::new();
        for ((f, c), r) in files.iter().zip(contents).zip(raws) {
            for (no, msg) in c.string_name {
                problems.push(Problem { check: "string_name", rel: f.rel.clone(), line: no as usize, msg });
            }
            for (check, no, msg) in c.lines {
                line_problems.push(Problem { check: LINE_CHECKS[check as usize], rel: f.rel.clone(), line: no as usize, msg });
            }
            for (no, msg) in r.lines {
                line_problems.push(Problem { check: "raw_write", rel: f.rel.clone(), line: no as usize, msg });
            }
            uses.extend(c.uses);
            uses.extend(r.uses);
        }
        problems.extend(global);
        // ---- per-line checks (removed, callback, handle, raw_write), then the ALLOW usage
        problems.extend(line_problems);
        for u in uses {
            if !out.allow_used.contains(&u) {
                out.allow_used.push(u);
            }
        }

        // The summary line counts in discovery order (Counter.most_common is stable); the report is
        // sorted by (file, line) like the Python's print loop.
        let mut counts: Vec<(&'static str, usize)> = Vec::new();
        for p in &problems {
            match counts.iter_mut().find(|(c, _)| *c == p.check) {
                Some((_, n)) => *n += 1,
                None => counts.push((p.check, 1)),
            }
        }
        counts.sort_by(|a, b| b.1.cmp(&a.1));
        let summary: Vec<String> = counts.iter().map(|(c, n)| format!("{} {}", c, n)).collect();
        out.note(format!(
            "ownership lint: {} problem{} ({})",
            problems.len(),
            if problems.len() == 1 { "" } else { "s" },
            if summary.is_empty() { "clean".to_string() } else { summary.join(", ") }
        ));
        problems.sort_by(|a, b| (&a.rel, a.line).cmp(&(&b.rel, b.line)));
        for p in problems {
            out.site_in_msg(p.check, &p.rel, p.line, p.msg);
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/ownership_lint.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::Bracketed,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Ownership);
}
