//! Port of the reusable half of `tools/ci/sys_rules/dx_reactive.py`: the reactive-proc analysis
//! (design review H4, H5, M3, M5) that `sys/dx_reactive` runs and `sys/dx_look_side_effects`
//! reuses (`reactive_writes`, `WRITER_CALL`, `MEMBER_WRITER`).
//!
//! Everything works on a [`Proc`]'s sanitized body lines, like the Python, by VAR NAME and with
//! the documented static limits (see the Python module docstring).

use std::collections::{HashMap, HashSet};

use crate::dm::dx::{self, call_args, match_paren, DxFacts, Proc};
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree};
use crate::util::{py_lstrip, py_rstrip, py_strip};
use crate::{pat, pat_match};

const REACTIVE_ANY: &[&str] = &["should_run", "hidden_verbs", "tgui_data"];
const REACTIVE_CAP: &[&str] = &["draw", "gate", "ui_data", "examine", "hidden_verbs"];
const CONTEXT_ROOTS: &[&str] = &["src", "user", "held", "look", "entry", "data", "ui", "state", "world", "global", "usr", "GLOB", "config", "callee"];
/// Relation vars whose target marks its owner changed on every write (review 2 M8).
const MARKING_RELATIONS: &[&str] = &["reagents"];
const NEVER_STATE: &[&str] = &["len", "type", "parent_type"];

pub fn writer_call() -> &'static Pat {
    pat!(r"(?<![\w./:])(?:changed|cap_set|timed_set|timed_cancel|own_set|own_add|own_put|own_take|own_take_all|own_take_member|own_remove|own_clear|own_transfer|own_move|rel_set|rel_add|rel_remove|rel_clear|om_set|qdel|forceMove|set_light|update_icon|add_fingerprint|to_chat|playsound|set_\w+)\s*\(")
}

pub fn member_writer() -> &'static Pat {
    pat!(r"(?<![\w.])([A-Za-z_]\w*|\.)((?:\s*\??\.\s*[A-Za-z_]\w*)*?)\s*\??\.\s*(set_\w+|forceMove|qdel|set_light|update_icon|add_fingerprint|Add|Cut|Remove|RemoveAll|Insert|Swap|Splice)\s*\(")
}

fn hide_args() -> &'static Pat {
    pat!(r"\b(?:nameof|PROC_REF|TYPE_PROC_REF|GLOBAL_PROC_REF|TYPE_VERB_REF|VERB_REF)\s*\(")
}

fn initial_call() -> &'static Pat {
    pat!(r"\binitial\s*\(")
}

fn local_decl() -> &'static Pat {
    pat!(r"\bvar/(?:[\w/]+/)?(\w+)")
}

const ASSIGN_OP: &str = r"\s*(?:=(?!=)|\+=|-=|\*=|/=|\|=|&=|\^=|<<=|>>=|\+\+|--)";

// ---- reactive procs ---------------------------------------------------------------------------

pub fn is_reactive(proc: &Proc, needs_names: &HashSet<String>) -> bool {
    if proc.path.starts_with("/datum/capability") {
        return REACTIVE_CAP.contains(&proc.name.as_str()) || needs_names.contains(&proc.name);
    }
    if proc.name == "draw" || proc.name == "look_parts" {
        // look_parts(look) is a chain's provider dispatch, called only from its draw (the draw sweep): it is the draw's body
        return proc.params.iter().any(|p| p.contains("look"));
    }
    REACTIVE_ANY.contains(&proc.name.as_str()) || needs_names.contains(&proc.name)
}

/// `blank_calls`: `text` with the argument lists of the calls `p` matches blanked out.
pub fn blank_calls(text: &str, p: &Pat) -> String {
    let mut b = text.as_bytes().to_vec();
    for m in p.find_iter(text) {
        if let Some(end) = match_paren(text, m.end - 1) {
            if end > 0 {
                for byte in b.iter_mut().take(end).skip(m.end) {
                    *byte = b' ';
                }
            }
        }
    }
    String::from_utf8(b).unwrap_or_else(|_| text.to_string())
}

/// `foreign_reads`: the var names read on another object in one sanitized line.
pub fn foreign_reads<'t>(text: &'t str, own_roots: &HashSet<String>, context: &HashSet<String>, relations: &HashSet<String>) -> Vec<&'t str> {
    let mut out: Vec<&'t str> = Vec::new();
    let chain = pat!(r#"(?<![\w.\]\)"'/:])([A-Za-z_]\w*)((?:\s*\??\.\s*[A-Za-z_]\w*)+)"#);
    let segment = pat!(r"\??\.\s*([A-Za-z_]\w*)");
    let global_root = pat_match!(r"(?:SS[a-z]\w*|[A-Z][A-Z0-9_]{2,})$");
    for m in chain.captures_iter(text) {
        let root = m.s(1);
        let mut segs: Vec<&str> = segment.captures_iter(m.s(2)).iter().map(|c| c.s(1)).collect();
        let after = py_lstrip(&text[m.end(0)..]);
        if after.starts_with('(') {
            segs.pop();
        }
        if segs.is_empty() {
            continue;
        }
        let first_foreign;
        if root == "GLOB" || own_roots.contains(root) {
            first_foreign = 1;
        } else if global_root.is_match(root) || CONTEXT_ROOTS.contains(&root) || context.contains(root) {
            continue;
        } else {
            first_foreign = 0;
        }
        let mut prev = root;
        for (k, name) in segs.iter().enumerate() {
            if k >= first_foreign && !NEVER_STATE.contains(name) && !relations.contains(prev) {
                out.push(name);
            }
            prev = name;
        }
    }
    out
}

// ---- dx_caps_instance_read --------------------------------------------------------------------

/// `caps_reads`: `(line, name)` for each instance read in a capabilities() body.
pub fn caps_reads(proc: &Proc, tree: &Tree, table: &HashMap<String, HashSet<String>>) -> Vec<(usize, String)> {
    let own = dx::vars_of(table, &proc.path, true);
    let lines = proc.lines(tree);
    let mut local: HashSet<String> = proc.params.iter().cloned().collect();
    for (_n, text) in &lines {
        for m in local_decl().captures_iter(text) {
            local.insert(m.s(1).to_string());
        }
    }
    let mut out = Vec::new();
    let ident = pat!(r"(?<![\w./:])(src\s*\??\.\s*)?([A-Za-z_]\w*)");
    for (number, text) in &lines {
        let text = blank_calls(text, hide_args());
        let mut hit: Option<String> = None;
        for m in ident.captures_iter(&text) {
            let name = m.s(2);
            if m.matched(1) && !m.s(1).is_empty() {
                if !py_lstrip(&text[m.end(0)..]).starts_with('(') {
                    hit = Some(name.to_string());
                    break;
                }
                continue;
            }
            if name == "src" || local.contains(name) || !own.contains(name) {
                continue;
            }
            let rest = &text[m.end(0)..];
            if py_lstrip(rest).starts_with('(') {
                continue; // a call
            }
            let before = &text[..m.start(0)];
            if pat_match!(r"\s*=(?!=)").is_match(rest) && before.matches('(').count() > before.matches(')').count() {
                continue; // a named argument key
            }
            if py_rstrip(before).ends_with("var") {
                continue;
            }
            hit = Some(name.to_string());
            break;
        }
        if let Some(h) = hit {
            out.push((*number, h));
        }
    }
    out
}

// ---- dx_timed_write ---------------------------------------------------------------------------

/// `timed_vars`: `{var name: type paths}` for every `timed_set(D, nameof(v))` / `timed_set(D, "v")`.
pub fn timed_vars(tree: &Tree, procs: &[Proc]) -> HashMap<String, HashSet<String>> {
    let timed = pat!(r"(?<![\w./:])timed_set\s*\(");
    let nameof_var = pat_match!(r"\s*nameof\(\s*(?:[\w.]+\.|/[\w/]+::)?(\w+)\s*\)\s*$");
    let mut out: HashMap<String, HashSet<String>> = HashMap::new();
    for proc in procs {
        for (number, text) in proc.lines(tree) {
            for m in timed.find_iter(text) {
                let Some(args) = call_args(text, m.end - 1) else { continue };
                if args.len() < 2 {
                    continue;
                }
                let name: Option<String> = if let Some(nm) = nameof_var.captures(&args[1]) {
                    Some(nm.s(1).to_string())
                } else {
                    let raw = tree.get(&proc.rel).map(|f| f.line(number)).unwrap_or("");
                    pat!(r#"timed_set\s*\([^,]*,\s*"(\w+)""#).captures(raw).map(|l| l.s(1).to_string())
                };
                if let Some(n) = name {
                    if !n.is_empty() {
                        out.entry(n).or_default().insert(proc.path.clone());
                    }
                }
            }
        }
    }
    out
}

/// The local `related` of dx_reactive.py (path prefixes only; not `dx::related`).
fn related(a: &str, b: &str) -> bool {
    a == b || a.starts_with(&format!("{}/", b)) || b.starts_with(&format!("{}/", a))
}

pub struct TimedPats {
    dotted: Pat,
    bare: Pat,
    incdec: Pat,
    decl: Pat,
}

/// `timed_writes`: the lines where a timed var is written outside timed_set()/its setter.
pub fn timed_writes(proc: &Proc, tree: &Tree, timed: &HashMap<String, HashSet<String>>, cache: &mut HashMap<String, TimedPats>) -> Vec<usize> {
    let lines = proc.lines(tree);
    let mut local: HashSet<String> = proc.params.iter().cloned().collect();
    for (_n, text) in &lines {
        for m in local_decl().captures_iter(text) {
            local.insert(m.s(1).to_string());
        }
    }
    let timed_set = pat!(r"(?<![\w./:])timed_set\s*\(");
    let mut out = Vec::new();
    for (number, text) in &lines {
        if timed_set.is_match(text) {
            continue;
        }
        for (name, paths) in timed {
            // Every pattern below needs the name in the line.
            if !text.contains(name.as_str()) {
                continue;
            }
            if proc.name == format!("set_{}", name) {
                continue;
            }
            let p = cache.entry(name.clone()).or_insert_with(|| TimedPats {
                dotted: Pat::new(&format!(r"\??\.\s*{}\b{}", name, ASSIGN_OP)),
                bare: Pat::new(&format!(r"(?<![\w.]){}\b{}", name, ASSIGN_OP)),
                incdec: Pat::new(&format!(r"(?:\+\+|--)\s*{}\b", name)),
                decl: Pat::new(&format!(r"\bvar/(?:[\w/]+/)?{}\b", name)),
            });
            let dotted = p.dotted.is_match(text);
            let mut bare = false;
            if !local.contains(name) && paths.iter().any(|q| related(&proc.path, q)) {
                bare = p.bare.is_match(text) || p.incdec.is_match(text);
                if bare && p.decl.is_match(text) {
                    bare = false;
                }
            }
            if dotted || bare {
                out.push(*number);
                break;
            }
        }
    }
    out
}

// ---- dx_reactive_write ------------------------------------------------------------------------

/// `write_op_at`: the length of an assignment operator at `b[k]` (the Python's WRITE_OP matched
/// at that offset, lookbehind included), or None.
fn write_op_at(b: &[u8], k: usize) -> Option<usize> {
    const BEHIND: &[u8] = b"=!<>+-*/|&^%";
    if k > 0 && BEHIND.contains(&b[k - 1]) {
        return None;
    }
    let c = b[k];
    if c == b'=' {
        return if b.get(k + 1) != Some(&b'=') { Some(1) } else { None };
    }
    if matches!(c, b'+' | b'-' | b'*' | b'/' | b'|' | b'&' | b'^') && b.get(k + 1) == Some(&b'=') {
        return Some(2);
    }
    if (c == b'<' || c == b'>') && b.get(k + 1) == Some(&c) && b.get(k + 2) == Some(&b'=') {
        return Some(3);
    }
    None
}

/// `top_level_ops`: offsets of assignment operators outside parentheses/brackets.
fn top_level_ops(text: &str) -> Vec<usize> {
    let b = text.as_bytes();
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut k = 0usize;
    while k < b.len() {
        let c = b[k];
        if c == b'(' || c == b'[' {
            depth += 1;
        } else if c == b')' || c == b']' {
            depth -= 1;
        } else if depth == 0 {
            if let Some(len) = write_op_at(b, k) {
                out.push(k);
                k += len;
                continue;
            }
        }
        k += 1;
    }
    out
}

/// `write_target_bad`: an assignment target that is state (not a local, parameter, `.` or `look`).
fn write_target_bad(target: &str, locals: &HashSet<String>) -> bool {
    let target = py_strip(target);
    if target.is_empty() || target.starts_with("var/") || pat!(r"\bvar/").is_match(target) {
        return false;
    }
    let Some(m) = pat_match!(r"(\.|[A-Za-z_]\w*)").captures(target) else { return false };
    let root = m.s(1);
    let rest = py_strip(&target[m.end(0)..]);
    if root == "." || root == "look" {
        return false;
    }
    if rest.is_empty() {
        return !locals.contains(root); // a bare var: a src var unless it is a local or parameter
    }
    if rest.starts_with('[') {
        return !locals.contains(root) && root != "src"; // an index of a local/param list is fine
    }
    true // a member write: another object's (or src's) state
}

/// `reactive_writes`: the line numbers where a reactive proc writes state.
pub fn reactive_writes(proc: &Proc, tree: &Tree) -> Vec<usize> {
    let lines = proc.lines(tree);
    let mut declared: HashSet<String> = HashSet::new();
    for (_n, text) in &lines {
        for m in local_decl().captures_iter(text) {
            declared.insert(m.s(1).to_string());
        }
    }
    let mut locals: HashSet<String> = declared.clone();
    locals.extend(proc.params.iter().cloned());
    let mut mutable: HashSet<&str> = declared.iter().map(|s| s.as_str()).collect();
    mutable.extend([".", "look", "data"]);
    let splitter = pat!(r"[;{]|\bin\b|^\s*(?:if|while|else if)\s*\(.*\)\s*");
    let incdec = pat!(r#"(\+\+|--)\s*([A-Za-z_.][\w.?\[\]]*)|([A-Za-z_.][\w.?\[\]"]*?)\s*(\+\+|--)"#);
    let mut out = Vec::new();
    for (number, code) in &lines {
        let code: &str = code;
        let mut bad = writer_call().is_match(code);
        if !bad {
            for m in member_writer().captures_iter(code) {
                let root = m.s(1);
                let through = py_strip(m.s(2));
                // `L.Add(x)` on a local list and `look.set_icon()` are fine; `holder.verbs.Remove()`
                // or `cell.set_charge()` mutate another object.
                if !through.is_empty() || !mutable.contains(root) {
                    bad = true;
                    break;
                }
            }
        }
        if !bad {
            let stripped = py_strip(code);
            if !(stripped.starts_with("var/") || stripped.starts_with("for(") || stripped.starts_with("for (")) {
                for k in top_level_ops(code) {
                    // the target is the text since the statement start (after `if(...)` etc.)
                    let lhs = &code[..k];
                    let lhs = match splitter.find_iter(lhs).last() {
                        Some(m) => &lhs[m.end..],
                        None => lhs,
                    };
                    if write_target_bad(lhs, &locals) {
                        bad = true;
                        break;
                    }
                }
            }
        }
        if !bad {
            for m in incdec.captures_iter(code) {
                let target = if m.matched(2) { m.s(2) } else { m.s(3) };
                if !target.is_empty() && write_target_bad(target, &locals) {
                    bad = true;
                    break;
                }
            }
        }
        if bad {
            out.push(*number);
        }
    }
    out
}

// ---- own roots --------------------------------------------------------------------------------

/// `own_roots_of`: (own roots, context roots, relation roots) of a proc.
pub fn own_roots_of(proc: &Proc, tree: &Tree, relations: &HashSet<String>) -> (HashSet<String>, HashSet<String>, HashSet<String>) {
    let mut roots: HashSet<String> = HashSet::new();
    roots.insert("src".to_string());
    let mut context: HashSet<String> = HashSet::new();
    let mut rels: HashSet<String> = HashSet::new();
    if proc.path.starts_with("/datum/capability") && !proc.params.is_empty() {
        roots.insert(proc.params[0].clone());
    }
    let cap_typed = pat!(r"\bvar/datum/capability(?:/\w+)*/(\w+)\b");
    let local_from = pat!(r"\bvar/(?:[\w/]+/)?(\w+)\s*=\s*(.+)$");
    let config_calls = pat_match!(r"(?:cap_of|ladder_for|caps_of|caps_all)\s*\(");
    let cap_data_expr = pat_match!(r"(?:(\w+)\s*\??\.\s*)?cap_data\s*(?:\(|\??\[)");
    let capability_data_expr = pat_match!(r"\bcapability_data\s*\(\s*(\w+)\s*\)");
    let relation_expr = pat_match!(r"(?:(\w+)\s*\??\.\s*)?(\w+)\s*$");
    let dotted_root = pat_match!(r"(\w+)\s*\??\.");
    for (_n, text) in proc.lines(tree) {
        for m in cap_typed.captures_iter(text) {
            context.insert(m.s(1).to_string());
        }
        let Some(m) = local_from.captures(py_rstrip(text)) else { continue };
        let name = m.s(1).to_string();
        let expr = py_strip(m.s(2));
        if roots.contains(expr) {
            roots.insert(name);
        } else if context.contains(expr) || CONTEXT_ROOTS.contains(&expr) {
            context.insert(name); // `var/datum/interaction/capability/E = entry`: still context
        } else if let Some(cd) = cap_data_expr.captures(expr).filter(|cd| !cd.matched(1) || cd.s(1).is_empty() || roots.contains(cd.s(1))) {
            let _ = cd;
            roots.insert(name);
        } else if capability_data_expr.captures(expr).is_some_and(|cd| roots.contains(cd.s(1))) {
            // The runtime accessor retains the same holder-owned payload identity.
            roots.insert(name);
        } else if config_calls.is_match(expr) {
            context.insert(name);
        } else if let Some(d) = dotted_root.captures(expr).filter(|d| context.contains(d.s(1))) {
            let _ = d;
            context.insert(name);
        } else if let Some(r) = relation_expr.captures(expr) {
            if relations.contains(r.s(2)) && (!r.matched(1) || r.s(1).is_empty() || roots.contains(r.s(1))) {
                rels.insert(name);
            }
        }
    }
    (roots, context, rels)
}

// ---- the whole analysis -----------------------------------------------------------------------

pub const RULE_READ: &str = "dx_untracked_read";
pub const RULE_WRITE: &str = "dx_reactive_write";
pub const RULE_CAPS: &str = "dx_caps_instance_read";
pub const RULE_TIMED: &str = "dx_timed_write";

/// One file's contribution to the shared context of [`analyse`]: the proc names it names as a
/// `needs =` handler, the vars it declares tracked, the relation vars it watches, and the
/// `timed_set` vars it writes (`(var, owning type)`). All sorted and deduplicated.
#[derive(Clone, Default, PartialEq, serde::Serialize, serde::Deserialize)]
struct ReactiveFacts {
    needs: Vec<String>,
    tracked: Vec<String>,
    watched: Vec<String>,
    timed: Vec<(String, String)>,
}

fn reactive_facts(tree: &Tree, f: &SourceFile, procs: &[Proc]) -> ReactiveFacts {
    let needs_re = pat!(r"\bneeds\s*=\s*(?:PROC_REF\(\s*(\w+)\s*\)|TYPE_PROC_REF\(\s*[/\w]+\s*,\s*(\w+)\s*\))");
    let tracked_re = pat_match!(r"\s*(?:TRACKED(?:_BRIDGED)?\(\s*/[\w/]+\s*,\s*(\w+)\s*[,)]|SETTER\(\s*/[\w/]+\s*,\s*(\w+)\s*\))");
    let watch_re = pat!(r"^\s*REL\w*\(\s*/[\w/]+\s*,\s*(\w+)\b[^\n]*\bWATCH\w*|\brel\(\s*nameof\(\s*(?:[\w.]+\.|/[\w/]+::)?(\w+)\s*\)[^\n]*\bwatch\s*=");
    let mut needs: HashSet<String> = HashSet::new();
    let mut tracked: HashSet<String> = HashSet::new();
    let mut watched: HashSet<String> = HashSet::new();
    for line in f.clean().lines() {
        if line.contains("needs") {
            for m in needs_re.captures_iter(line) {
                let n = if m.matched(1) { m.s(1) } else { m.s(2) };
                needs.insert(n.to_string());
            }
        }
        if line.contains("TRACKED") || line.contains("SETTER(") {
            if let Some(t) = tracked_re.captures(line) {
                let n = if m_nonempty(&t, 1) { t.s(1) } else { t.s(2) };
                tracked.insert(n.to_string());
            }
        }
        if line.contains("REL") || line.contains("rel(") {
            if let Some(w) = watch_re.captures(line) {
                let n = if m_nonempty(&w, 1) { w.s(1) } else { w.s(2) };
                watched.insert(n.to_string());
            }
        }
    }
    let sorted = |s: HashSet<String>| -> Vec<String> {
        let mut v: Vec<String> = s.into_iter().collect();
        v.sort();
        v
    };
    let mut timed: Vec<(String, String)> = timed_vars(tree, procs).into_iter().flat_map(|(n, set)| set.into_iter().map(move |p| (n.clone(), p))).collect();
    timed.sort();
    ReactiveFacts { needs: sorted(needs), tracked: sorted(tracked), watched: sorted(watched), timed }
}

/// What the per-file judge reads (everything except the type-var table).
#[derive(serde::Serialize)]
struct ReactiveCtx {
    needs: std::collections::BTreeSet<String>,
    tracked: std::collections::BTreeSet<String>,
    watched: std::collections::BTreeSet<String>,
    timed: std::collections::BTreeMap<String, std::collections::BTreeSet<String>>,
}

/// One file's findings by emission group: reads, writes, timed.
type FileSites = (Vec<u32>, Vec<u32>, Vec<u32>);

/// `analyse`: every site of the four rules, in the Python's emission order.
///
/// Incremental: per-file facts (cached by content) merge into the shared name sets; each file's
/// reactive/timed findings are cached while those sets are unchanged, and the capabilities()
/// instance reads (the only rule that reads the type-var table) while the file facts that feed that
/// table are unchanged.
pub fn analyse(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let dxf = DxFacts::all(tree);
    let facts: Vec<ReactiveFacts> = crate::incr::facts("dx-reactive-facts", files, |f| reactive_facts(tree, f, &dxf.of(f).procs));
    let mut ctx = ReactiveCtx { needs: Default::default(), tracked: Default::default(), watched: Default::default(), timed: Default::default() };
    for fs in &facts {
        ctx.needs.extend(fs.needs.iter().cloned());
        ctx.tracked.extend(fs.tracked.iter().cloned());
        ctx.watched.extend(fs.watched.iter().cloned());
        for (n, p) in &fs.timed {
            ctx.timed.entry(n.clone()).or_default().insert(p.clone());
        }
    }
    let needs_names: HashSet<String> = ctx.needs.iter().cloned().collect();
    let tracked: HashSet<String> = ctx.tracked.iter().cloned().collect();
    let watched: HashSet<String> = ctx.watched.iter().cloned().collect();
    let timed: HashMap<String, HashSet<String>> = ctx.timed.iter().map(|(n, ps)| (n.clone(), ps.iter().cloned().collect())).collect();
    let marking: HashSet<String> = MARKING_RELATIONS.iter().map(|s| s.to_string()).collect();
    let base_relations: HashSet<String> = watched.union(&marking).cloned().collect();

    let sites: Vec<FileSites> = crate::incr::keyed("dx-reactive-judge-runtime-data-v2", crate::incr::ctx_key(&ctx), files, |f| {
        let fd = dxf.of(f);
        let mut reads: Vec<u32> = Vec::new();
        let mut writes: Vec<u32> = Vec::new();
        let mut timed_out: Vec<u32> = Vec::new();
        for proc in &fd.procs {
            if is_reactive(proc, &needs_names) {
                let mut relations = base_relations.clone();
                let (own_roots, context, local_rels) = own_roots_of(proc, tree, &relations);
                relations.extend(local_rels);
                for (number, text) in proc.lines(tree) {
                    let text = blank_calls(text, initial_call()); // initial(x.y) is a compile-time default
                    let bad = foreign_reads(&text, &own_roots, &context, &relations).into_iter().any(|n| !tracked.contains(n));
                    if bad {
                        reads.push(number as u32);
                    }
                }
                for number in reactive_writes(proc, tree) {
                    writes.push(number as u32);
                }
            }
        }
        if !timed.is_empty() {
            let mut cache: HashMap<String, TimedPats> = HashMap::new();
            for proc in &fd.procs {
                for number in timed_writes(proc, tree, &timed, &mut cache) {
                    timed_out.push(number as u32);
                }
            }
        }
        (reads, writes, timed_out)
    });

    // capabilities() instance reads: the one rule that reads the `{type: vars}` table. Keyed by the
    // files' var facts; the merged table is only built when a capabilities() file must be judged.
    let vars_key = {
        let cows: Vec<std::borrow::Cow<'_, dx::FileDx>> = files.iter().map(|f| dxf.of(f)).collect();
        let all: Vec<&Vec<(String, Vec<String>)>> = cows.iter().map(|c| &c.vars).filter(|v| !v.is_empty()).collect();
        crate::incr::ctx_key(&all)
    };
    let table: std::sync::OnceLock<HashMap<String, HashSet<String>>> = std::sync::OnceLock::new();
    let caps: Vec<Vec<u32>> = crate::incr::keyed("dx-reactive-caps", vars_key, files, |f| {
        let fd = dxf.of(f);
        if !fd.procs.iter().any(|p| p.name == "capabilities" && p.path != "/atom") {
            return Vec::new();
        }
        let table = table.get_or_init(|| {
            let mut t: HashMap<String, HashSet<String>> = HashMap::new();
            for g in files {
                for (ty, vs) in &dxf.of(g).vars {
                    t.entry(ty.clone()).or_default().extend(vs.iter().cloned());
                }
            }
            t
        });
        let mut out = Vec::new();
        for proc in &fd.procs {
            if proc.name == "capabilities" && proc.path != "/atom" {
                for (number, _name) in caps_reads(proc, tree, table) {
                    out.push(number as u32);
                }
            }
        }
        out
    });

    let mut out: Vec<(&'static str, String, usize)> = Vec::new();
    for (f, s) in files.iter().zip(&sites) {
        out.extend(s.0.iter().map(|&n| (RULE_READ, f.rel.clone(), n as usize)));
    }
    for (f, s) in files.iter().zip(&sites) {
        out.extend(s.1.iter().map(|&n| (RULE_WRITE, f.rel.clone(), n as usize)));
    }
    for (f, c) in files.iter().zip(&caps) {
        out.extend(c.iter().map(|&n| (RULE_CAPS, f.rel.clone(), n as usize)));
    }
    for (f, s) in files.iter().zip(&sites) {
        out.extend(s.2.iter().map(|&n| (RULE_TIMED, f.rel.clone(), n as usize)));
    }
    out
}

/// `m.group(i)` is truthy: it participated and is not empty.
fn m_nonempty(c: &crate::pat::Caps, i: usize) -> bool {
    c.matched(i) && !c.s(i).is_empty()
}
