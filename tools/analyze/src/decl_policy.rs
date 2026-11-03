//! Unique declarative-lifecycle policy; adapters supply source/header evidence.
use std::collections::BTreeSet;
use crate::{tree::SourceFile,pat::Pat,pat_match,dm::sys::col0,util::{before_slashes,py_strip},key_policy_control::{self as kc,Control}};
fn metadata()->&'static crate::lint::Meta{crate::lints::decl::captured_metadata()}
pub(crate) struct Decl {
    init_rules: Vec<(&'static str, Pat)>,
    destroy_rules: Vec<(&'static str, Pat)>,
}

impl Decl {
    pub(crate) fn new() -> Decl {
        Decl {
            init_rules: vec![
                (
                    "init_reagents",
                    Pat::new(r"\bcreate_reagents\s*\(|\breagents\.add_reagent\s*\("),
                ),
                (
                    "init_gas",
                    Pat::new(r"\bair_contents\s*=\s*new\b|\.adjust_gas\s*\("),
                ),
                (
                    "init_registry",
                    Pat::new(r"\bregistry_join\s*\([^)]*\bsrc\b|\bGLOB\.\w+\[[^\]]*\]\s*=\s*src\b"),
                ),
                (
                    "init_service",
                    Pat::new(r"\bGLOB\.\w+_service\.\w+\(\s*src\b"),
                ),
                (
                    "init_bind",
                    Pat::new(
                        r"\bconnect_to_network\s*\(\s*\)|\bvg_\w*bind\w*\s*\(|\bheat_body_create\s*\(",
                    ),
                ),
                (
                    "init_scheduling",
                    Pat::new(
                        r"\bom_task_periodic\s*\(\s*src\s*,|\bom_attach\s*\(\s*src\s*,|\b(?:om_after|after)\s*\(\s*src\s*,",
                    ),
                ),
                (
                    "init_visuals",
                    Pat::new(
                        r"\badd_overlay\s*\(|\bcut_overlays\s*\(|^\s*(?:src\.)?icon_state\s*=",
                    ),
                ),
            ],
            destroy_rules: vec![
                (
                    "destroy_drop",
                    Pat::new(
                        r"\bdump_contents\s*\(|\bfor\s*\(\s*var/[\w/]+\s+in\s+(?:src\.)?contents\b.*|\bfor\s*\(\s*var/[\w/]+\s+in\s+contents_of\(\s*src\s*\)",
                    ),
                ),
                (
                    "destroy_registry",
                    Pat::new(r"\bregistry_leave\s*\(|\bGLOB\.\w+\s*-=\s*src\b"),
                ),
                (
                    "destroy_scheduling",
                    Pat::new(r"\bom_task_periodic_stop\s*\(|\bSTOP_PROCESSING\s*\("),
                ),
                (
                    "destroy_unbind",
                    Pat::new(r"\bdisconnect_from_network\s*\(|\bvg_\w*unbind\w*\s*\("),
                ),
                (
                    "destroy_effects",
                    Pat::new(
                        r"\bvisible_message\s*\(|\bplaysound\s*\(|\bnew\s+/obj/[\w/]+\s*\(\s*(?:loc|src\.loc|get_turf\([^)]*\)|T)\s*\)",
                    ),
                ),
            ],
        }
    }
}

/// `OWN_WRITE` over every raw line of one file: the var names written through the own_* accessors
/// (sorted, unique). The tree-wide set is the union over every file, exempt ones too.
pub(crate) fn owned_vars_of(f:&SourceFile)->Vec<String>{owned_vars_using(f,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}
pub(crate) fn owned_vars_using<C:Control>(f: &SourceFile,control:&mut C)->Result<Vec<String>,C::Error>{
    control.checkpoint()?;
    let own_write = crate::pat!(
        r#"\b(?:own_(?:set|add|put|transfer|move)|rel_(?:set|add))\([^,]+,\s*(?:"|nameof\((?:/[\w/]+::|\w+\.)?)(\w+)(?:"|\))"#
    );
    let mut names: BTreeSet<String> = BTreeSet::new();
    for line in f.raw().lines() {
        control.checkpoint()?;
        // `\bown_...` needs the text `own_`: a prefilter with the same result.
        if !line.contains("own_") && !line.contains("rel_") {
            continue;
        }
        for m in own_write.captures_iter(line) {
            control.checkpoint()?;if !names.contains(m.s(1)){kc::reserve(control,||Some(2048))?;names.insert(kc::own(control,m.s(1))?); }
        }
    }
    kc::reserve(control,||names.len().checked_mul(4*std::mem::size_of::<String>())?.checked_add(128))?;
    Ok(names.into_iter().collect())
}

impl Decl {
    /// One file's sites as `(rule index, line)`, in emission order. ALLOW questions are recorded
    /// (the cache replays them).
    pub(crate) fn judge(&self, f: &SourceFile, refs: &BTreeSet<String>) -> Vec<(u8, u32)> {
        self.judge_spans(f, refs, &text_spans(f))
    }
}

/// The text rule's bodies: from a `/type/proc(` header to the next column-0 line.
pub(crate) fn text_spans(f:&SourceFile)->Vec<(&'static str,std::ops::Range<usize>)>{text_spans_using(f,&mut kc::Compatibility).unwrap_or_else(|never|match never{})}
pub(crate) fn text_spans_using<C:Control>(f:&SourceFile,control:&mut C)->Result<Vec<(&'static str,std::ops::Range<usize>)>,C::Error>{
    control.checkpoint()?;
    let header = pat_match!(r"^(/[\w/]+)/(Initialize|on_materialize|on_destroy)\s*\(");
    let mut spans: Vec<(&'static str, std::ops::Range<usize>)> = Vec::new();
    let mut open: Option<(&'static str, usize)> = None;
    let mut last = 0;
    for (number, line) in f.raw().numbered() {
        control.checkpoint()?;
        last = number;
        if let Some(m) = header.captures(line) {
            if let Some((p, start)) = open.take() {
                kc::row(control,&mut spans)?;spans.push((p, start..number));
            }
            open = Some((proc_kind(m.s(2)), number + 1));
            continue;
        }
        if col0(line) {
            if let Some((p, start)) = open.take() {
                kc::row(control,&mut spans)?;spans.push((p, start..number));
            }
        }
    }
    if let Some((p, start)) = open.take() {
        kc::row(control,&mut spans)?;spans.push((p, start..last + 1));
    }
    Ok(spans)
}

impl Decl {
    /// The sites of the given bodies (`(proc, 1-based line range)`), in line order.
    pub(crate) fn judge_spans(&self,f:&SourceFile,refs:&BTreeSet<String>,spans:&[(&'static str,std::ops::Range<usize>)])->Vec<(u8,u32)>{self.judge_spans_using(f,refs,spans,&mut kc::Compatibility,&mut|number|Ok(crate::dm::sys::kept_recorded(f,number,"decl"))).unwrap_or_else(|never|match never{})}
    pub(crate) fn judge_spans_using<C:Control>(
        &self,
        f: &SourceFile,
        refs: &BTreeSet<String>,
        spans: &[(&'static str, std::ops::Range<usize>)],
        control:&mut C,allowed:&mut impl FnMut(usize)->Result<bool,C::Error>,
    ) -> Result<Vec<(u8,u32)>,C::Error> {
        control.checkpoint()?;
        kc::reserve(control,||{let n=spans.iter().try_fold(0usize,|n,(_,r)|n.checked_add(r.end.saturating_sub(r.start)))?;n.checked_mul(4*std::mem::size_of::<(usize,&'static str)>())?.checked_add(128)})?;
        let new_into = pat_match!(
            r#"^\s*(?:own|rel)_(?:set|add)\(\s*src\s*,\s*(?:"|nameof\((?:/[\w/]+::|\w+\.)?)(\w+)(?:"|\))\s*,\s*new\b"#
        );
        let qdel_var = crate::pat!(
            r#"\b(?:own_(?:clear|take|take_all)|rel_clear)\(\s*src\s*,\s*(?:"|nameof\((?:/[\w/]+::|\w+\.)?)(\w+)(?:"|\))|\bqdel\s*\(\s*(?:src\.)?(\w+)\s*\)"#
        );
        // MATERIALIZE_RULES: the INIT_RULES that also apply to on_materialize(), in INIT_RULES order.
        let materialize = ["init_registry", "init_service", "init_scheduling"];
        let rule_index =
            |name: &str| metadata().rules.iter().position(|r| r.name == name).unwrap_or(0) as u8;

        let mut out: Vec<(u8, u32)> = Vec::new();
        let raw = f.raw();
        let mut lines: Vec<(usize, &'static str)> = spans
            .iter()
            .flat_map(|(p, r)| r.clone().map(move |n| (n, *p)))
            .collect();
        lines.sort();
        lines.dedup_by_key(|(n, _)| *n);
        for (number, proc) in lines {
            control.checkpoint()?;
            if number == 0 || number > raw.num_lines() {
                continue;
            }
            let line = raw.line(number);
            if py_strip(line).is_empty() {
                continue;
            }
            let code = before_slashes(line);
            if py_strip(code).is_empty() {
                continue;
            }
            kc::reserve(control,||Some(14*std::mem::size_of::<&str>()+128))?;
            let mut hit: Vec<&'static str> = Vec::new();
            match proc {
                "Initialize" => {
                    hit.extend(
                        self.init_rules
                            .iter()
                            .filter(|(_, rx)| rx.is_match(code))
                            .map(|(r, _)| *r),
                    );
                    if new_into.is_match(code) {
                        hit.push("init_new_child");
                    }
                }
                "on_materialize" => {
                    hit.extend(
                        self.init_rules
                            .iter()
                            .filter(|(r, rx)| materialize.contains(r) && rx.is_match(code))
                            .map(|(r, _)| *r),
                    );
                }
                _ => {
                    hit.extend(
                        self.destroy_rules
                            .iter()
                            .filter(|(_, rx)| rx.is_match(code))
                            .map(|(r, _)| *r),
                    );
                    for qm in qdel_var.captures_iter(code) {
                        if qm.matched(1) || (qm.matched(2) && refs.contains(qm.s(2))) {
                            hit.push("destroy_qdel_owned");
                            break;
                        }
                    }
                }
            }
            // Asked only about a line that would otherwise count.
            if !hit.is_empty() && !allowed(number)? {
                for rule in hit {
                    control.checkpoint()?;kc::row(control,&mut out)?;
                    out.push((rule_index(rule), number as u32));
                }
            }
        }
        Ok(out)
    }
}

pub(crate) fn proc_kind(name: &str) -> &'static str {
    match name {
        "Initialize" => "Initialize",
        "on_materialize" => "on_materialize",
        _ => "on_destroy",
    }
}

