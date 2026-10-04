//! `op_order`: the order ops answer a click in (doc/rewrite/final_api.html section 8, "Order"; section 9, metadata).
//!
//! Two rules:
//!
//! * `unordered_clash`: two ops one type composes (its own, its named bundles' and the capabilities its CAPABILITIES block expands to, with
//!   their parameters substituted) that can answer the same input (the same intent, an overlapping held tool or item type, the same binding
//!   kind) at the same tier, with nothing ordering them: no priority(above/below(...)) naming the other, no click_order() of a composing bundle
//!   covering both, no default precedence (a narrower item before storage.put_in), no passes(), and when() parts that are not mutually
//!   exclusive. The engine's boot check (RULE_OP_CLASH) catches the identical-binding case at runtime; this one also sees overlapping item
//!   types, statically. Ops the engine derives (a construction ladder's steps) are not modelled.
//! * `relative_priority`: a hand-written priority(above(...)) or priority(below(...)). Each one is a per-type patch for an order a bundle
//!   should declare once (click_order()); the count is a ceiling that can only fall.
//!
//! Both are counted against ceilings in `tools/ci/op_order_baseline.txt` (`analyze baseline --update --lint op_order` lowers them).

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::sem::decls::{matching_paren, split_args, strip_comments_keep_strings, Decls};
use crate::tree::{SourceFile, CODE_DM};

const H_CLASH: &str = "order them once in the composing bundle's click_order() (code/engine/parts/plan.dm), or give one a different input, tier or a when() exclusive of the other's";
const H_REL: &str = "declare the order once where the ops are composed (click_order() in the bundle), not per type: this count only falls";

static META: Meta = Meta {
    name: "op_order",
    group: "",
    label: "op_order",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Both,
    policy: Policy::Ceilings {
        baseline: "tools/ci/op_order_baseline.txt",
        header: &[
            "op_order ceilings: `relative_priority` counts hand-written priority(above/below(...)), `unordered_clash` the ops a type composes that",
            "answer one input at one tier with no order. Shrink-only: `analyze baseline --update --lint op_order` lowers them.",
        ],
    },
    rules: &[RuleMeta { name: "unordered_clash", hint: H_CLASH }, RuleMeta { name: "relative_priority", hint: H_REL }],
    allow: &["op_order"],
    lists: &[],
};

struct OpOrder;

impl Lint for OpOrder {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if f.rel.starts_with("code/engine/_generated/") {
            return;
        }
        let rel = crate::pat!(r"\bpriority\(\s*(?:above|below)\(");
        for (number, line) in f.clean().numbered() {
            if rel.is_match(line) && !out.allowed(f, number, "op_order") {
                let rel_name = f.rel.clone();
                out.site_keyed("relative_priority", &rel_name, number, f.line(number).trim().to_string(), "relative_priority");
            }
        }
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let decls = Decls::get(cx.tree);
        let model = Model::build(cx, &decls);
        for m in decls.markers_named("CAPABILITIES") {
            if cx.exempt(&m.rel) || m.rel.starts_with("code/engine/_generated/") {
                continue;
            }
            let Some(ty) = m.args.first() else { continue };
            let mut comp = Composition::default();
            let mut seen = HashSet::new();
            for entry in m.args.iter().skip(1) {
                model.expand(entry, "", &HashMap::new(), &mut comp, &mut seen, 0);
            }
            comp.apply_extends();
            for (a, b, input) in comp.clashes() {
                let msg = format!("{}: ops \"{}\" and \"{}\" both answer {} at tier {} with no order between them", ty, a.key, b.key, input, a.tier);
                if let Some(f) = cx.tree.get(&m.rel) {
                    if out.allowed(f, m.line as usize, "op_order") {
                        continue;
                    }
                }
                out.site_keyed("unordered_clash", &m.rel, m.line as usize, msg, format!("unordered_clash:{}", ty));
            }
        }
    }
}

// ---- the model ----

/// A capability's constructor: its op prefix, its params in order (with defaults), the selector param and the body of its entries().
struct CapDef {
    prefix: String,
    params: Vec<(String, String)>,
    selector: Option<String>,
    body: String,
}

struct Model {
    caps: HashMap<String, CapDef>,
    /// Entry procs (a global proc returning a list of entries): name -> the entries joined.
    bundles: HashMap<String, String>,
    /// Global procs: name -> (params, body).
    procs: HashMap<String, (Vec<String>, String)>,
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
enum Bind {
    Hand,
    InHand,
    Tool(String),
    Item(String),
    Stack(String),
}

impl Bind {
    fn describe(&self) -> String {
        match self {
            Bind::Hand => "hand()".to_string(),
            Bind::InHand => "in_hand()".to_string(),
            Bind::Tool(q) => format!("tool({})", q),
            Bind::Item(t) => format!("item({})", t),
            Bind::Stack(t) => format!("stack({})", t),
        }
    }
}

#[derive(Clone, Debug, Default)]
struct Op {
    key: String,
    binds: Vec<Bind>,
    tier: String,
    explicit_tier: Option<String>,
    intents: Vec<String>,
    conds: Vec<String>,
    rel: Option<String>,
    passes: bool,
}

#[derive(Default)]
struct Composition {
    ops: BTreeMap<String, Op>,
    order: Vec<String>,
    extends: Vec<(Vec<String>, Vec<String>)>,
    /// click_order(input, ranks...): the input, then each rank's patterns.
    chains: Vec<(String, Vec<Vec<String>>)>,
}

fn unquote(s: &str) -> Option<String> {
    let t = s.trim();
    t.strip_prefix('"').and_then(|x| x.strip_suffix('"')).map(|x| x.to_string())
}

/// `name(` at `at` in `text`: the call's name and its argument text, or None.
fn call_at(text: &str, at: usize) -> Option<(String, usize, usize)> {
    let b = text.as_bytes();
    let mut e = at;
    while e < b.len() && (b[e].is_ascii_alphanumeric() || b[e] == b'_') {
        e += 1;
    }
    if e == at || e >= b.len() || b[e] != b'(' {
        return None;
    }
    let close = matching_paren(text, e)?;
    Some((text[at..e].to_string(), e + 1, close))
}

/// The calls in `text` at nesting depth zero of other calls we parse whole (op, extend, click_order) and every other call's insides:
/// (name, args text, offset). A call we do not know is looked into, so `entries += wires(...)` and `list(cover(), panel())` are found.
fn calls(text: &str) -> Vec<(String, String)> {
    let b = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    let mut in_str = false;
    while i < b.len() {
        let c = b[i];
        if in_str {
            if c == b'\\' {
                i += 2;
                continue;
            }
            if c == b'"' {
                in_str = false;
            }
            i += 1;
            continue;
        }
        if c == b'"' {
            in_str = true;
            i += 1;
            continue;
        }
        let boundary = i == 0 || !(b[i - 1].is_ascii_alphanumeric() || b[i - 1] == b'_' || b[i - 1] == b'.' || b[i - 1] == b'/');
        if boundary && (c.is_ascii_alphabetic() || c == b'_') {
            if let Some((name, open, close)) = call_at(text, i) {
                out.push((name.clone(), text[open..close].to_string()));
                // the whole-call forms are not looked into; any other call is (its arguments may hold entries)
                if matches!(name.as_str(), "op" | "extend" | "click_order") {
                    i = close + 1;
                } else {
                    i = open;
                }
                continue;
            }
            while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
                i += 1;
            }
            continue;
        }
        i += 1;
    }
    out
}

/// Replaces whole identifiers of `subst` in `text` (not a call name, not a member, not the name of a named argument, not inside a string).
fn substitute(text: &str, subst: &HashMap<String, String>) -> String {
    if subst.is_empty() {
        return text.to_string();
    }
    let b = text.as_bytes();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    let mut in_str = false;
    while i < b.len() {
        let c = b[i];
        if in_str {
            out.push(c as char);
            if c == b'"' {
                in_str = false;
            }
            i += 1;
            continue;
        }
        if c == b'"' {
            in_str = true;
            out.push('"');
            i += 1;
            continue;
        }
        if c.is_ascii_alphabetic() || c == b'_' {
            let s = i;
            while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
                i += 1;
            }
            let word = &text[s..i];
            let prev = if s > 0 { b[s - 1] } else { b' ' };
            let rest = text[i..].trim_start();
            let is_call = rest.starts_with('(');
            let is_named = rest.starts_with('=') && !rest.starts_with("==");
            if prev != b'.' && prev != b'/' && !is_call && !is_named {
                if let Some(v) = subst.get(word) {
                    out.push_str(v);
                    continue;
                }
            }
            out.push_str(word);
            continue;
        }
        out.push(c as char);
        i += 1;
    }
    out
}

/// The text a named argument or a positional one gives a param (`params` in declaration order).
fn bind_args(params: &[(String, String)], args_text: &str) -> HashMap<String, String> {
    let mut map: HashMap<String, String> = params.iter().map(|(p, d)| (p.clone(), d.clone())).collect();
    let mut pos = 0;
    for a in split_args(args_text) {
        if a.is_empty() {
            continue;
        }
        if let Some((k, v)) = a.split_once('=') {
            let k = k.trim();
            if !k.is_empty() && k.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') && !v.starts_with('=') {
                map.insert(k.to_string(), v.trim().to_string());
                continue;
            }
        }
        if let Some((p, _)) = params.get(pos) {
            map.insert(p.clone(), a.trim().to_string());
        }
        pos += 1;
    }
    map
}

impl Model {
    fn build(cx: &Cx, decls: &Decls) -> Model {
        // entries() bodies by datum type, global proc bodies by name
        let mut entries: HashMap<String, String> = HashMap::new();
        let mut procs: HashMap<String, (Vec<String>, String)> = HashMap::new();
        for f in cx.all_files() {
            if f.rel.starts_with("code/engine/_generated/") {
                continue;
            }
            let text = f.text();
            if !text.contains("entries()") && !text.contains("/proc/") {
                continue;
            }
            let stripped = strip_comments_keep_strings(text);
            let mut cur: Option<(bool, String, Vec<String>)> = None;
            let mut body = String::new();
            let mut flush = |cur: &mut Option<(bool, String, Vec<String>)>, body: &mut String| {
                if let Some((is_entries, name, params)) = cur.take() {
                    if is_entries {
                        entries.insert(name, std::mem::take(body));
                    } else {
                        procs.insert(name, (params, std::mem::take(body)));
                    }
                }
                body.clear();
            };
            for line in stripped.split('\n') {
                if !line.is_empty() && !line.starts_with(|c: char| c.is_whitespace()) {
                    flush(&mut cur, &mut body);
                    if let Some(m) = crate::pat_match!(r"^(/datum/[\w/]+)/entries\(\)").captures(line) {
                        cur = Some((true, m.s(1).to_string(), Vec::new()));
                    } else if let Some(m) = crate::pat_match!(r"^/proc/(\w+)\(([^)]*)\)").captures(line) {
                        let params = m
                            .s(2)
                            .split(',')
                            .map(|p| p.split('=').next().unwrap_or("").trim().rsplit('/').next().unwrap_or("").to_string())
                            .filter(|p| !p.is_empty())
                            .collect();
                        cur = Some((false, m.s(1).to_string(), params));
                    }
                    continue;
                }
                if cur.is_some() {
                    body.push_str(line);
                    body.push('\n');
                }
            }
            flush(&mut cur, &mut body);
        }
        let mut caps = HashMap::new();
        for m in decls.markers.iter().filter(|m| m.name == "CAPABILITY_TYPE" || m.name == "CAPABILITY_DEF") {
            let Some(name) = m.args.first() else { continue };
            let (datum, skip) = if m.name == "CAPABILITY_TYPE" {
                (m.args.get(2).cloned().unwrap_or_default(), 3)
            } else {
                (format!("/datum/capability/def/{}", name), 2)
            };
            let mut params = Vec::new();
            let mut selector = None;
            let mut prefix = name.clone();
            for a in m.args.iter().skip(skip) {
                let (k, v) = match a.split_once('=') {
                    Some((k, v)) => (k.trim().to_string(), v.trim().to_string()),
                    None => (a.trim().to_string(), "null".to_string()),
                };
                match k.as_str() {
                    "key" => {
                        if v != "NONE" {
                            selector = Some(v);
                        }
                    }
                    "prefix" => prefix = v.trim_matches('"').to_string(),
                    "stacks" => {}
                    _ => params.push((k, v)),
                }
            }
            let body = entries.get(&datum).cloned().unwrap_or_default();
            caps.insert(name.clone(), CapDef { prefix, params, selector, body });
        }
        let bundles = decls.markers_named(crate::sem::decls::ENTRY_PROC).filter_map(|m| m.args.first().map(|n| (n.trim().to_string(), m.args[1..].join(", ")))).collect();
        Model { caps, bundles, procs }
    }

    /// Adds what `text` (an entry, or a body of entries) brings to `comp`: op keys get `prefix`.
    fn expand(&self, text: &str, prefix: &str, subst: &HashMap<String, String>, comp: &mut Composition, seen: &mut HashSet<String>, depth: usize) {
        if depth > 8 {
            return;
        }
        let text = substitute(text, subst);
        // a local `var/list/x = list(...)` of a body stands for its value where it is named
        let mut locals = HashMap::new();
        for c in crate::pat!(r"var/list/(\w+)\s*=\s*").captures_iter(&text) {
            let start = c.end(0);
            if let Some((name, open, close)) = call_at(&text, start) {
                locals.insert(c.s(1).to_string(), format!("{}({})", name, &text[open..close]));
            }
        }
        let text = if locals.is_empty() { text } else { substitute(&text, &locals) };
        for (name, args) in calls(&text) {
            match name.as_str() {
                "op" => {
                    if let Some(op) = self.parse_op(&args, prefix, 0) {
                        if !comp.ops.contains_key(&op.key) {
                            comp.order.push(op.key.clone());
                        }
                        comp.ops.insert(op.key.clone(), op);
                    }
                }
                "extend" => {
                    let parts = split_args(&args);
                    let Some(target) = parts.first() else { continue };
                    let keys: Vec<String> = if let Some(k) = unquote(target) {
                        vec![k]
                    } else if let Some(inner) = target.strip_prefix("list(").and_then(|t| t.strip_suffix(')')) {
                        split_args(inner).iter().filter_map(|k| unquote(k)).collect()
                    } else {
                        Vec::new()
                    };
                    if !keys.is_empty() {
                        comp.extends.push((keys, parts[1..].to_vec()));
                    }
                }
                "click_order" => {
                    let parts = split_args(&args);
                    let Some(input) = parts.first() else { continue };
                    let input = if input.trim() == "BIND_HAND" { "hand".to_string() } else { input.trim().to_string() };
                    let mut ranks = Vec::new();
                    for p in &parts[1..] {
                        if let Some(k) = unquote(p) {
                            ranks.push(vec![k]);
                        } else if let Some(inner) = p.strip_prefix("list(").and_then(|t| t.strip_suffix(')')) {
                            ranks.push(split_args(inner).iter().filter_map(|k| unquote(k)).collect());
                        }
                    }
                    comp.chains.push((input, ranks));
                }
                _ => {
                    if let Some(cap) = self.caps.get(&name) {
                        let bound = bind_args(&cap.params, &args);
                        let mut pre = format!("{}.", cap.prefix);
                        if let Some(sel) = &cap.selector {
                            if let Some(v) = bound.get(sel) {
                                let v = v.trim();
                                let v = v.strip_prefix("nameof(").and_then(|x| x.strip_suffix(')')).unwrap_or(v).trim_matches('"');
                                if v != "null" && !v.is_empty() {
                                    pre = format!("{}.{}.", cap.prefix, v);
                                }
                            }
                        }
                        let sig = format!("{}|{}", name, args);
                        if seen.insert(sig) {
                            self.expand(&cap.body, &pre, &bound, comp, seen, depth + 1);
                        }
                    } else if let Some(body) = self.bundles.get(&name).filter(|_| args.trim().is_empty()) {
                        if seen.insert(format!("bundle|{}", name)) {
                            self.expand(body, prefix, &HashMap::new(), comp, seen, depth + 1);
                        }
                    } else if let Some((params, body)) = self.procs.get(&name) {
                        // a named bundle (a global proc returning entries): its ops are the type's own
                        if body.contains("op(") || body.contains("extend(") || body.contains("click_order(") {
                            let pdefs: Vec<(String, String)> = params.iter().map(|p| (p.clone(), "null".to_string())).collect();
                            let bound = bind_args(&pdefs, &args);
                            let sig = format!("{}|{}", name, args);
                            if seen.insert(sig) {
                                self.expand(body, prefix, &bound, comp, seen, depth + 1);
                            }
                        }
                    }
                }
            }
        }
    }

    /// An op(...) call's model, or None when it has no physical input we compare (a window button, a menu entry).
    fn parse_op(&self, args: &str, prefix: &str, depth: usize) -> Option<Op> {
        let parts = split_args(args);
        let key = unquote(parts.first()?)?;
        let mut op = Op { key: format!("{}{}", prefix, key), tier: "NORMAL".to_string(), ..Op::default() };
        let mut yields_part = false;
        let mut take_out = false;
        for p in &parts[1..] {
            self.read_part(p, &mut op, &mut yields_part, &mut take_out, depth);
        }
        if op.binds.is_empty() {
            return None;
        }
        op.tier = match &op.explicit_tier {
            Some(t) => t.clone(),
            None if take_out => "TAKE_OUT".to_string(),
            None if yields_part => "PART".to_string(),
            None => "NORMAL".to_string(),
        };
        if op.intents.is_empty() {
            op.intents.push("default".to_string());
        }
        Some(op)
    }

    fn read_part(&self, part: &str, op: &mut Op, yields_part: &mut bool, take_out: &mut bool, depth: usize) {
        let p = part.trim();
        let Some((name, open, close)) = call_at(p, 0) else { return };
        let inner = &p[open..close];
        let first = split_args(inner).first().cloned().unwrap_or_default();
        let none = |v: &str| v.is_empty() || v == "NONE" || v == "null";
        match name.as_str() {
            "hand" => op.binds.push(Bind::Hand),
            "in_hand" => op.binds.push(Bind::InHand),
            "tool" => {
                if !none(&first) {
                    op.binds.push(Bind::Tool(first));
                    *yields_part = true;
                }
            }
            "item" => {
                if !none(&first) {
                    op.binds.push(Bind::Item(first));
                    *yields_part = true;
                }
            }
            "stack" => {
                if !none(&first) {
                    op.binds.push(Bind::Stack(first));
                    *yields_part = true;
                }
            }
            "put_in" => *yields_part = true,
            "take_out" => *take_out = true,
            "priority" => {
                if let Some(rest) = first.strip_prefix("above(").or_else(|| first.strip_prefix("below(")) {
                    op.rel = unquote(rest.trim_end_matches(')'));
                } else if let Some(t) = first.strip_prefix("OP_PRIORITY_") {
                    op.explicit_tier = Some(t.to_string());
                }
            }
            "when" => op.conds.push(compact(inner)),
            "answers" => op.intents = split_args(inner).iter().map(|s| s.trim().to_string()).collect(),
            "passes" => op.passes = true,
            "inputs" | "list" => {
                for q in split_args(inner) {
                    self.read_part(&q, op, yields_part, take_out, depth);
                }
            }
            other => {
                // a part bundle (force_pry(), component_swap(T)): a global proc returning parts
                if depth < 4 {
                    if let Some((_, body)) = self.procs.get(other) {
                        if let Some(at) = body.find("return ") {
                            let ret = body[at + 7..].trim();
                            if let Some((n2, o2, c2)) = call_at(ret, 0) {
                                if n2 == "list" {
                                    for q in split_args(&ret[o2..c2]) {
                                        self.read_part(&q, op, yields_part, take_out, depth + 1);
                                    }
                                } else {
                                    self.read_part(&ret[..=c2], op, yields_part, take_out, depth + 1);
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

fn compact(s: &str) -> String {
    s.chars().filter(|c| !c.is_whitespace()).collect()
}

fn key_matches(key: &str, pattern: &str) -> bool {
    match pattern.strip_suffix('*') {
        Some(pre) => key.starts_with(pre),
        None => key == pattern,
    }
}

/// Does a held thing that fits `a` also fit `b`? Same tool quality, or item types where one is the other or its ancestor (item(/obj/item)
/// takes any item, tools included).
fn overlap(a: &Bind, b: &Bind) -> Option<String> {
    let sub = |x: &str, y: &str| x == y || x.starts_with(&format!("{}/", y)) || y.starts_with(&format!("{}/", x));
    match (a, b) {
        (Bind::Hand, Bind::Hand) | (Bind::InHand, Bind::InHand) => Some(a.describe()),
        (Bind::Tool(x), Bind::Tool(y)) if x == y => Some(a.describe()),
        (Bind::Item(x), Bind::Item(y)) | (Bind::Stack(x), Bind::Stack(y)) | (Bind::Item(x), Bind::Stack(y)) | (Bind::Stack(x), Bind::Item(y)) if sub(x, y) => {
            Some(format!("{} / {}", a.describe(), b.describe()))
        }
        (Bind::Item(x), Bind::Tool(_)) | (Bind::Tool(_), Bind::Item(x)) if x == "/obj/item" => Some(format!("{} / {}", a.describe(), b.describe())),
        _ => None,
    }
}

fn cond_negates(a: &str, b: &str) -> bool {
    if b == format!("cond_not({})", a) || a == format!("cond_not({})", b) {
        return true;
    }
    // req_is(K) against req_is(K, FALSE)
    if let (Some(x), Some(y)) = (a.strip_prefix("req_is("), b.strip_prefix("req_is(")) {
        let xa = split_args(x.trim_end_matches(')'));
        let ya = split_args(y.trim_end_matches(')'));
        let truthy = |v: &[String]| v.get(1).map(|s| s != "FALSE" && s != "0").unwrap_or(true);
        return xa.first() == ya.first() && truthy(&xa) != truthy(&ya);
    }
    false
}

impl Composition {
    fn apply_extends(&mut self) {
        for (keys, parts) in std::mem::take(&mut self.extends) {
            for k in keys {
                let Some(op) = self.ops.get_mut(&k) else { continue };
                for p in &parts {
                    let p = p.trim();
                    let Some((name, open, close)) = call_at(p, 0) else { continue };
                    let inner = &p[open..close];
                    let first = split_args(inner).first().cloned().unwrap_or_default();
                    match name.as_str() {
                        "priority" => {
                            if let Some(rest) = first.strip_prefix("above(").or_else(|| first.strip_prefix("below(")) {
                                op.rel = unquote(rest.trim_end_matches(')'));
                            } else if let Some(t) = first.strip_prefix("OP_PRIORITY_") {
                                op.tier = t.to_string();
                            }
                        }
                        "when" => op.conds.push(compact(inner)),
                        "answers" => op.intents = split_args(inner).iter().map(|s| s.trim().to_string()).collect(),
                        "passes" => op.passes = true,
                        _ => {}
                    }
                }
            }
        }
    }

    /// A click order puts one of the two above the other for an input both take.
    fn chain_orders(&self, a: &Op, b: &Op) -> bool {
        for (input, ranks) in &self.chains {
            let takes = |o: &Op| o.binds.iter().any(|x| match x {
                Bind::Hand => input == "hand",
                Bind::Tool(q) => q == input,
                _ => false,
            });
            if !takes(a) || !takes(b) {
                continue;
            }
            let rank = |o: &Op| ranks.iter().position(|r| r.iter().any(|p| key_matches(&o.key, p)));
            if let (Some(x), Some(y)) = (rank(a), rank(b)) {
                if x != y {
                    return true;
                }
            }
        }
        false
    }

    fn clashes(&self) -> Vec<(Op, Op, String)> {
        let ops: Vec<&Op> = self.order.iter().filter_map(|k| self.ops.get(k)).collect();
        let mut out = Vec::new();
        let mut reported: BTreeSet<(String, String)> = BTreeSet::new();
        for i in 0..ops.len() {
            for j in i + 1..ops.len() {
                let (a, b) = (ops[i], ops[j]);
                if a.tier != b.tier || a.passes || b.passes {
                    continue;
                }
                if a.rel.as_deref() == Some(b.key.as_str()) || b.rel.as_deref() == Some(a.key.as_str()) {
                    continue;
                }
                if !a.intents.iter().any(|x| b.intents.contains(x)) {
                    continue;
                }
                if a.conds.iter().any(|x| b.conds.iter().any(|y| cond_negates(x, y))) {
                    continue;
                }
                if self.chain_orders(a, b) {
                    continue;
                }
                // the default precedence: an op for a narrower item answers above the storage catch-all
                if a.key == "storage.put_in" || b.key == "storage.put_in" {
                    continue;
                }
                let mut input = None;
                'outer: for x in &a.binds {
                    for y in &b.binds {
                        if let Some(d) = overlap(x, y) {
                            input = Some(d);
                            break 'outer;
                        }
                    }
                }
                let Some(input) = input else { continue };
                if reported.insert((a.key.clone(), b.key.clone())) {
                    out.push((a.clone(), b.clone(), input));
                }
            }
        }
        out
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(OpOrder);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn calls_skip_inside_ops() {
        let c = calls("list(op(\"a\", tool(TOOL_X)), wires(kind), extend(\"a\", priority(above(\"b\"))))");
        let names: Vec<&str> = c.iter().map(|(n, _)| n.as_str()).collect();
        assert_eq!(names, vec!["list", "op", "wires", "extend"]);
    }

    #[test]
    fn substitute_skips_calls_and_named_args() {
        let mut m = HashMap::new();
        m.insert("wires".to_string(), "/datum/wires/apc".to_string());
        assert_eq!(substitute("wires(wires, wires = wires)", &m), "wires(/datum/wires/apc, wires = /datum/wires/apc)");
    }

    #[test]
    fn overlap_of_items() {
        assert!(overlap(&Bind::Item("/obj/item".into()), &Bind::Item("/obj/item/pen".into())).is_some());
        assert!(overlap(&Bind::Item("/obj/item/pen".into()), &Bind::Item("/obj/item/paper".into())).is_none());
        assert!(overlap(&Bind::Tool("TOOL_X".into()), &Bind::Tool("TOOL_Y".into())).is_none());
    }

    #[test]
    fn negation() {
        assert!(cond_negates("PANEL_OPEN", "cond_not(PANEL_OPEN)"));
        assert!(cond_negates("req_is(K)", "req_is(K,FALSE)"));
        assert!(!cond_negates("A", "B"));
    }
}
