//! `op_order`: the order ops answer a click in (doc/rewrite/final_api.html section 8, "Order"; section 9, metadata).
//!
//! Two rules:
//!
//! * `unordered_clash`: two ops one type composes (its own, its named bundles' and the capabilities its CAPABILITIES block expands to, with
//!   their parameters substituted) that can answer the same input (the same intent, an overlapping held tool or item type, the same binding
//!   kind) at the same tier, with nothing ordering them: no priority(above/below(...)) naming the other, no click_order() of a composing bundle
//!   covering both, no binding specificity (a narrower item type, then a tool quality, then a broad item), no passes(), and when() parts that are not mutually
//!   exclusive. The engine's boot check (RULE_OP_CLASH) catches the identical-binding case at runtime; this one also sees overlapping item
//!   types, statically. Ops the engine derives (a construction ladder's steps) are not modelled.
//!
//!   What it models as the resolver does (code/engine/parts/resolve.dm): the intents each binding answers (answers(), hostile(), a pinned
//!   gesture(): a drag answers INTENT_DROP_ONTO, never a click), the tier by value (hostile() yields ATTACK; OP_PRIORITY_PART - 1 is its own
//!   tier), disjoint stance() sets, when() conjuncts that negate (c / cond_not(c), req_is(K) / req_is(K, FALSE), req(X) is X, graph stages
//!   that do not meet), and a constructor's entries its params switch off (`lid ? op(...) : null`, `if(by_hand)`), and binding specificity
//!   (op_binding_specificity): of two held-item bindings, an item type narrower than /obj/item answers before a tool quality, which answers
//!   before a broad item (item(/obj/item), whatever acceptance proc gates it), and a deeper item type before a shallower one, so only two
//!   bindings of equal specificity clash. An opaque when() proc is not exclusive of anything; the engine has no annotation that says it is.
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
                let msg = format!(
                    "{}: ops \"{}\" and \"{}\" both answer {} at tier {} with no order between them",
                    ty,
                    a.key,
                    b.key,
                    input,
                    a.tier.trim_start_matches("OP_PRIORITY_")
                );
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

    /// How specific the binding is about the held item (resolve.dm: op_binding_specificity): 0 names no held item (not compared), 1 a broad
    /// item (item(/obj/item), whatever acceptance proc gates it), 2 a tool quality (tool(Q), any_of_tools(...)), 4 and up an item or stack
    /// type narrower than /obj/item by path depth. The more specific answers first, so only equal specificities can clash.
    fn specificity(&self) -> usize {
        match self {
            Bind::Hand | Bind::InHand => 0,
            Bind::Tool(_) => 2,
            Bind::Item(t) | Bind::Stack(t) => {
                if t == "/obj/item" {
                    1
                } else if t.starts_with("/obj/item/") {
                    t.split('/').count()
                } else {
                    0 // a mob or structure dragged in: not a held item
                }
            }
        }
    }
}

#[derive(Clone, Debug, Default)]
struct Op {
    key: String,
    binds: Vec<Bind>,
    /// The tier expression (OP_PRIORITY_X, or OP_PRIORITY_X+n): compared by value (`tier_value`).
    tier: String,
    explicit_tier: Option<String>,
    /// answers(...) / hostile(): the intents it answers, replacing what the binding implies (resolve.dm, op_answers).
    answers: Option<Vec<String>>,
    /// gesture(G): a pinned gesture; the op answers the intents that gesture means.
    gesture: Option<String>,
    /// toggles(...): a hand binding also answers INTENT_TOGGLE.
    toggles: bool,
    /// presents(T): the op answers INTENT_PRESENT only.
    presents: bool,
    /// hostile(): the op yields the attack tier.
    hostile: bool,
    /// stance(S...) / when(req_stance(S...)): the stances the actor must be in (a Match gate), or None for any.
    stances: Option<BTreeSet<String>>,
    /// The when() conditions, normalized (`norm_cond`), one per conjunct.
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
        // a constructor's params decide some of its entries: `lid ? op(...) : null`, `if(by_hand)`
        let text = if subst.is_empty() { text } else { prune_ifs(&prune_ternaries(&text)) };
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
        let mut op = Op { key: format!("{}{}", prefix, key), ..Op::default() };
        let mut yields_part = false;
        let mut take_out = false;
        for p in &parts[1..] {
            self.read_part(p, &mut op, &mut yields_part, &mut take_out, depth);
        }
        if op.binds.is_empty() {
            return None;
        }
        // the tier (plan.dm): an explicit priority, else the highest its parts yield
        op.tier = match &op.explicit_tier {
            Some(t) => t.clone(),
            None => {
                let mut tier = 0;
                if op.hostile {
                    tier = tier.max(20);
                }
                if yields_part {
                    tier = tier.max(10);
                }
                if take_out {
                    tier = tier.max(30);
                }
                tier_name(tier)
            }
        };
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
            "tool" | "any_of_tools" => {
                for q in split_args(inner) {
                    if !none(&q) && !q.contains('=') {
                        op.binds.push(Bind::Tool(q));
                        *yields_part = true;
                    }
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
            "inputs" | "list" => {
                for q in split_args(inner) {
                    self.read_part(&q, op, yields_part, take_out, depth);
                }
            }
            other => {
                if apply_select(other, inner, op) {
                    return;
                }
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

/// The select, order and Match parts an op or an extend() carries: priority, when, answers, hostile, gesture, stance, toggles, presents, passes.
/// Returns whether `name` was one of them.
fn apply_select(name: &str, inner: &str, op: &mut Op) -> bool {
    let first = split_args(inner).first().cloned().unwrap_or_default();
    match name {
        "priority" => {
            if let Some(rest) = first.strip_prefix("above(").or_else(|| first.strip_prefix("below(")) {
                op.rel = unquote(rest.trim_end_matches(')'));
            } else if first.starts_with("OP_PRIORITY_") {
                op.explicit_tier = Some(compact(&first));
                op.tier = compact(&first);
            }
        }
        "when" => {
            for c in split_args(inner) {
                add_cond(op, &compact(&c));
            }
        }
        "answers" => op.answers = Some(split_args(inner).iter().map(|s| s.trim().to_string()).collect()),
        "hostile" => {
            op.answers = Some(vec!["INTENT_ATTACK".to_string()]);
            op.hostile = true;
        }
        "gesture" => op.gesture = Some(first.trim().to_string()),
        "stance" => op.stances = stance_set(inner),
        "toggles" | "toggles_hold" => op.toggles = true,
        "presents" => op.presents = true,
        "passes" => op.passes = true,
        _ => return false,
    }
    true
}

/// `s` is `name(...)` with the call closing at its last character: the argument text, or None.
fn whole_call<'a>(s: &'a str, name: &str) -> Option<&'a str> {
    let rest = s.strip_prefix(name)?;
    if !rest.starts_with('(') || matching_paren(s, name.len()) != Some(s.len() - 1) {
        return None;
    }
    Some(&s[name.len() + 1..s.len() - 1])
}

/// The stances a stance(...) / req_stance(...) argument list names, or None when one is not a literal I_X.
fn stance_set(inner: &str) -> Option<BTreeSet<String>> {
    let mut out = BTreeSet::new();
    for a in split_args(inner) {
        let a = a.trim();
        if let Some(l) = whole_call(a, "list") {
            out.extend(stance_set(l)?);
        } else if a.starts_with("I_") && a.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            out.insert(a.to_string());
        } else if !a.is_empty() {
            return None;
        }
    }
    Some(out)
}

/// Adds one when() condition: a conjunction is split into its conjuncts, a stance condition narrows the op's stances.
fn add_cond(op: &mut Op, c: &str) {
    if let Some(inner) = whole_call(c, "cond_all") {
        for part in split_args(inner) {
            add_cond(op, &compact(&part));
        }
        return;
    }
    if let Some(set) = whole_call(c, "req_stance").and_then(stance_set) {
        op.stances = Some(match op.stances.take() {
            Some(prev) => prev.intersection(&set).cloned().collect(),
            None => set,
        });
        return;
    }
    op.conds.push(norm_cond(c));
}

/// One condition in a canonical spelling, so two spellings of one test compare equal: req(X) is X, req_is(K) is K, req_is(K, FALSE) is
/// cond_not(K), and a double negation cancels.
fn norm_cond(c: &str) -> String {
    let c = c.trim();
    if let Some(inner) = whole_call(c, "cond_not") {
        let n = norm_cond(inner);
        return match whole_call(&n, "cond_not") {
            Some(back) => back.to_string(),
            None => format!("cond_not({})", n),
        };
    }
    if let Some(inner) = whole_call(c, "req_is") {
        let args: Vec<String> = split_args(inner).into_iter().filter(|a| !a.contains('=') || a.contains("==")).collect();
        if let Some(key) = args.first() {
            match args.get(1).map(|v| v.as_str()) {
                Some("FALSE") | Some("0") => return format!("cond_not({})", norm_cond(key)),
                None | Some("TRUE") | Some("1") => return norm_cond(key),
                _ => {}
            }
        }
    }
    if let Some(inner) = whole_call(c, "req_actor_kind") {
        // req_actor_kind(types, because =, not = TRUE): the kinds are the test, `not = TRUE` negates it, the reason is no part of the condition.
        let args = split_args(inner);
        let mut types: Option<String> = None;
        let mut negated = false;
        for a in &args {
            let a = a.trim();
            if let Some((name, value)) = a.split_once('=') {
                if name.trim() == "not" {
                    negated = matches!(value.trim(), "TRUE" | "1");
                }
            } else if types.is_none() {
                types = Some(compact(a));
            }
        }
        if let Some(t) = types {
            let base = format!("actor_kind({})", t);
            return if negated { format!("cond_not({})", base) } else { base };
        }
    }
    if let Some(inner) = whole_call(c, "req") {
        let args = split_args(inner);
        if args.len() == 1 {
            return norm_cond(&args[0]);
        }
    }
    c.to_string()
}

/// The value of a tier expression (OP_PRIORITY_X, OP_PRIORITY_X+n, OP_PRIORITY_X-n, a number), or None.
fn tier_value(expr: &str) -> Option<i64> {
    let named = |n: &str| -> Option<i64> {
        Some(match n {
            "OP_PRIORITY_DEFAULT" => -2000,
            "OP_PRIORITY_NORMAL" => 0,
            "OP_PRIORITY_PART" => 10,
            "OP_PRIORITY_ATTACK" => 20,
            "OP_PRIORITY_TAKE_OUT" => 30,
            "OP_PRIORITY_CLAW" => 40,
            "OP_PRIORITY_SUBVERT" => 50,
            _ => n.parse().ok()?,
        })
    };
    let mut total = 0i64;
    let mut sign = 1i64;
    let mut term = String::new();
    for ch in compact(expr).chars().chain(std::iter::once('+')) {
        if ch == '+' || ch == '-' {
            if term.is_empty() {
                if ch == '-' {
                    sign = -sign;
                }
                continue;
            }
            total += sign * named(&term)?;
            term.clear();
            sign = if ch == '-' { -1 } else { 1 };
        } else {
            term.push(ch);
        }
    }
    Some(total)
}

fn tier_name(v: i64) -> String {
    match v {
        -2000 => "OP_PRIORITY_DEFAULT".to_string(),
        0 => "OP_PRIORITY_NORMAL".to_string(),
        10 => "OP_PRIORITY_PART".to_string(),
        20 => "OP_PRIORITY_ATTACK".to_string(),
        30 => "OP_PRIORITY_TAKE_OUT".to_string(),
        40 => "OP_PRIORITY_CLAW".to_string(),
        50 => "OP_PRIORITY_SUBVERT".to_string(),
        n => n.to_string(),
    }
}

fn same_tier(a: &str, b: &str) -> bool {
    match (tier_value(a), tier_value(b)) {
        (Some(x), Some(y)) => x == y,
        _ => a == b,
    }
}

/// The intents an op answers through one of its bindings (resolve.dm, op_answers): answers() when written, else a pinned gesture's, else
/// INTENT_USE (and INTENT_TOGGLE for a toggling hand op; INTENT_PRESENT alone for presents()).
fn bind_intents(op: &Op, b: &Bind) -> Vec<String> {
    if let Some(a) = &op.answers {
        return a.clone();
    }
    if let Some(g) = &op.gesture {
        return match g.as_str() {
            "GESTURE_CLICK" | "GESTURE_SELF" => vec!["INTENT_USE".to_string()],
            "GESTURE_ALT" => vec!["INTENT_TOGGLE".to_string(), "INTENT_OPEN".to_string(), "INTENT_EJECT".to_string()],
            "GESTURE_SHIFT" => vec!["INTENT_EXAMINE".to_string()],
            "GESTURE_DRAG" => vec!["INTENT_DROP_ONTO".to_string()],
            // a gesture the engine maps to no intent (ctrl, middle, right click) or one we cannot read: ops pinning the same one still meet
            other => vec![format!("pinned:{}", other)],
        };
    }
    if op.presents {
        return vec!["INTENT_PRESENT".to_string()];
    }
    let mut v = vec!["INTENT_USE".to_string()];
    if op.toggles && *b == Bind::Hand {
        v.push("INTENT_TOGGLE".to_string());
    }
    v
}

// ---- constructor arguments decided at expansion: `cond ? a : b` and `if(cond)` in an entries() body ----

/// The truth of a condition whose params are substituted, three-valued: Some when every operand is a literal (TRUE, FALSE, null, a number, a
/// string, a list, length() of a literal list), else None.
fn eval_cond(s: &str) -> Option<bool> {
    let toks = cond_tokens(s)?;
    let mut i = 0;
    let v = cond_or(&toks, &mut i)?;
    if i != toks.len() {
        return None;
    }
    v
}

/// Tokens: operators ("!", "&&", "||", "(", ")", "==", "!=") and whole terms (a call with its arguments, a word, a number, a string, a path).
fn cond_tokens(s: &str) -> Option<Vec<String>> {
    let b = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c.is_ascii_whitespace() || c == b'\\' {
            i += 1;
            continue;
        }
        let two = if i + 1 < b.len() { &s[i..i + 2] } else { "" };
        if matches!(two, "&&" | "||" | "==" | "!=") {
            out.push(two.to_string());
            i += 2;
            continue;
        }
        if matches!(c, b'!' | b'(' | b')') {
            out.push((c as char).to_string());
            i += 1;
            continue;
        }
        if c == b'"' {
            let mut j = i + 1;
            while j < b.len() && b[j] != b'"' {
                if b[j] == b'\\' {
                    j += 1;
                }
                j += 1;
            }
            if j >= b.len() {
                return None;
            }
            out.push(s[i..=j].to_string());
            i = j + 1;
            continue;
        }
        if c.is_ascii_alphanumeric() || c == b'_' || c == b'/' || c == b'.' {
            let mut j = i;
            while j < b.len() && (b[j].is_ascii_alphanumeric() || b[j] == b'_' || b[j] == b'/' || b[j] == b'.') {
                j += 1;
            }
            if j < b.len() && b[j] == b'(' {
                j = matching_paren(s, j)? + 1;
            }
            out.push(s[i..j].to_string());
            i = j;
            continue;
        }
        return None;
    }
    Some(out)
}

/// The parse result is Some(truth) on a parse, None on a failure; the truth itself is Option (None: unknown).
fn cond_or(t: &[String], i: &mut usize) -> Option<Option<bool>> {
    let mut v = cond_and(t, i)?;
    while t.get(*i).map(|x| x == "||").unwrap_or(false) {
        *i += 1;
        let r = cond_and(t, i)?;
        v = match (v, r) {
            (Some(true), _) | (_, Some(true)) => Some(true),
            (Some(false), Some(false)) => Some(false),
            _ => None,
        };
    }
    Some(v)
}

fn cond_and(t: &[String], i: &mut usize) -> Option<Option<bool>> {
    let mut v = cond_unary(t, i)?;
    while t.get(*i).map(|x| x == "&&").unwrap_or(false) {
        *i += 1;
        let r = cond_unary(t, i)?;
        v = match (v, r) {
            (Some(false), _) | (_, Some(false)) => Some(false),
            (Some(true), Some(true)) => Some(true),
            _ => None,
        };
    }
    Some(v)
}

fn cond_unary(t: &[String], i: &mut usize) -> Option<Option<bool>> {
    let tok = t.get(*i)?.clone();
    *i += 1;
    let v = match tok.as_str() {
        "!" => return cond_unary(t, i).map(|v| v.map(|b| !b)),
        "(" => {
            let v = cond_or(t, i)?;
            if t.get(*i).map(|x| x.as_str()) != Some(")") {
                return None;
            }
            *i += 1;
            v
        }
        ")" | "&&" | "||" | "==" | "!=" => return None,
        term => term_truth(term),
    };
    // a comparison is not decided here
    if matches!(t.get(*i).map(|x| x.as_str()), Some("==") | Some("!=")) {
        *i += 2;
        if *i > t.len() {
            return None;
        }
        return Some(None);
    }
    Some(v)
}

fn term_truth(term: &str) -> Option<bool> {
    match term {
        "TRUE" => return Some(true),
        "FALSE" | "null" | "NONE" => return Some(false),
        _ => {}
    }
    if let Ok(n) = term.parse::<f64>() {
        return Some(n != 0.0);
    }
    if term.starts_with('"') {
        return Some(term.len() > 2);
    }
    if term.starts_with('/') || whole_call(term, "list").is_some() {
        return Some(true);
    }
    if let Some(inner) = whole_call(term, "length") {
        let inner = inner.trim();
        if inner == "null" {
            return Some(false);
        }
        if let Some(items) = whole_call(inner, "list") {
            return Some(split_args(items).iter().any(|a| !a.trim().is_empty()));
        }
    }
    None
}

/// The bounds of each `cond ? a : b` at one nesting level whose condition is decided, replaced by the branch it takes. Undecided ones stay.
fn prune_ternaries(text: &str) -> String {
    let mut text = text.to_string();
    let mut from = 0;
    'scan: loop {
        let b = text.as_bytes();
        let mut in_str = false;
        let mut q = None;
        let mut i = from;
        while i < b.len() {
            let c = b[i];
            if in_str {
                if c == b'\\' {
                    i += 1;
                } else if c == b'"' {
                    in_str = false;
                }
            } else if c == b'"' {
                in_str = true;
            } else if c == b'?' && !matches!(b.get(i + 1), Some(b'.') | Some(b'[') | Some(b':')) {
                q = Some(i);
                break;
            }
            i += 1;
        }
        let Some(q) = q else { break };
        from = q + 1;
        // the condition: back to the comma, the open paren, the assignment or the line start that bounds it
        let mut depth = 0i32;
        let mut start = 0;
        let mut j = q;
        while j > 0 {
            j -= 1;
            let c = b[j];
            match c {
                b')' => depth += 1,
                b'(' => {
                    if depth == 0 {
                        start = j + 1;
                        break;
                    }
                    depth -= 1;
                }
                b',' | b'\n' | b';' if depth == 0 => {
                    start = j + 1;
                    break;
                }
                b'=' if depth == 0 && !matches!(b.get(j + 1), Some(b'=')) && !(j > 0 && matches!(b[j - 1], b'=' | b'!' | b'<' | b'>')) => {
                    start = j + 1;
                    break;
                }
                _ => {}
            }
        }
        let mut cond = text[start..q].trim();
        cond = cond.strip_prefix("return ").unwrap_or(cond).trim();
        if cond.is_empty() {
            continue;
        }
        // the colon of this ternary, and the end of its else branch
        let mut depth = 0i32;
        let mut in_str = false;
        let mut colon = None;
        let mut end = b.len();
        let mut k = q + 1;
        while k < b.len() {
            let c = b[k];
            if in_str {
                if c == b'\\' {
                    k += 1;
                } else if c == b'"' {
                    in_str = false;
                }
                k += 1;
                continue;
            }
            match c {
                b'"' => in_str = true,
                b'(' | b'[' => depth += 1,
                b')' | b']' => {
                    if depth == 0 {
                        end = k;
                        break;
                    }
                    depth -= 1;
                }
                b',' | b'\n' | b';' if depth == 0 => {
                    if colon.is_none() {
                        continue 'scan;
                    }
                    end = k;
                    break;
                }
                b':' if depth == 0 && colon.is_none() => {
                    if b.get(k + 1) == Some(&b':') {
                        k += 2;
                        continue;
                    }
                    colon = Some(k);
                }
                b'?' if depth == 0 && colon.is_none() => continue 'scan,
                _ => {}
            }
            k += 1;
        }
        let Some(colon) = colon else { continue };
        let Some(truth) = eval_cond(cond) else { continue };
        let branch = if truth { &text[q + 1..colon] } else { &text[colon + 1..end] };
        let branch = branch.trim().to_string();
        let prefix_ws = if start > 0 && !text[..start].ends_with(char::is_whitespace) { " " } else { "" };
        text = format!("{}{}{}{}", &text[..start], prefix_ws, branch, &text[end..]);
        from = start;
    }
    text
}

/// Drops the statements of an `if(cond)` whose condition is decided false (keeping its else), or the else of one decided true.
fn prune_ifs(text: &str) -> String {
    let lines: Vec<&str> = text.split('\n').collect();
    let indent = |l: &str| l.len() - l.trim_start().len();
    let mut out: Vec<String> = Vec::with_capacity(lines.len());
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        let t = line.trim_start();
        let ind = indent(line);
        let head = t.strip_prefix("if").filter(|r| r.trim_start().starts_with('('));
        let Some(head) = head else {
            out.push(line.to_string());
            i += 1;
            continue;
        };
        let open = t.len() - head.len() + (head.len() - head.trim_start().len());
        let Some(close) = matching_paren(t, open) else {
            out.push(line.to_string());
            i += 1;
            continue;
        };
        let cond = &t[open + 1..close];
        let rest = t[close + 1..].trim();
        // the if's body: the rest of its line, or the more indented lines below it
        let mut j = i + 1;
        if rest.is_empty() {
            while j < lines.len() && (lines[j].trim().is_empty() || indent(lines[j]) > ind) {
                j += 1;
            }
        }
        let body: Vec<String> = if rest.is_empty() { lines[i + 1..j].iter().map(|s| s.to_string()).collect() } else { vec![format!("{}{}", &line[..ind], rest)] };
        // an else at the same indent
        let mut else_body: Vec<String> = Vec::new();
        let mut k = j;
        if j < lines.len() && indent(lines[j]) == ind && lines[j].trim_start().starts_with("else") {
            let et = lines[j].trim_start();
            let erest = et["else".len()..].trim();
            k = j + 1;
            if erest.is_empty() {
                while k < lines.len() && (lines[k].trim().is_empty() || indent(lines[k]) > ind) {
                    k += 1;
                }
                else_body = lines[j + 1..k].iter().map(|s| s.to_string()).collect();
            } else {
                else_body = vec![format!("{}{}", &lines[j][..ind], erest)];
            }
        }
        match eval_cond(cond) {
            Some(true) => {
                out.extend(body);
                i = k;
            }
            Some(false) => {
                out.extend(else_body);
                i = k;
            }
            None => {
                out.push(line.to_string());
                i += 1;
            }
        }
    }
    out.join("\n")
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

/// Two normalized conditions (`norm_cond`) that cannot both hold: c against cond_not(c), and graph stages that do not meet.
fn cond_negates(a: &str, b: &str) -> bool {
    if b == format!("cond_not({})", a) || a == format!("cond_not({})", b) {
        return true;
    }
    // req_graph_at(list(S...)) against one with none of its stages
    if let (Some(x), Some(y)) = (whole_call(a, "req_graph_at"), whole_call(b, "req_graph_at")) {
        let stages = |v: &str| -> Option<BTreeSet<String>> {
            let first = split_args(v).into_iter().next()?;
            let first = first.trim();
            let items = whole_call(first, "list").map(split_args).unwrap_or_else(|| vec![first.to_string()]);
            Some(items.into_iter().map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
        };
        if let (Some(sx), Some(sy)) = (stages(x), stages(y)) {
            return sx.is_disjoint(&sy);
        }
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
                    apply_select(&name, &p[open..close], op);
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
                if !same_tier(&a.tier, &b.tier) || a.passes || b.passes {
                    continue;
                }
                if a.rel.as_deref() == Some(b.key.as_str()) || b.rel.as_deref() == Some(a.key.as_str()) {
                    continue;
                }
                // stance() gates: an actor is in one stance at a time
                if let (Some(sa), Some(sb)) = (&a.stances, &b.stances) {
                    if sa.is_disjoint(sb) {
                        continue;
                    }
                }
                if a.conds.iter().any(|x| b.conds.iter().any(|y| cond_negates(x, y))) {
                    continue;
                }
                if self.chain_orders(a, b) {
                    continue;
                }
                let mut input = None;
                // two bindings meet when they take one held thing and answer an intent in common (plan.dm, op_plans_clash); binding
                // specificity orders two held-item bindings of different specificity (an item type narrower than /obj/item, then a tool
                // quality, then a broad item: resolve.dm, op_binding_specificity), so only an equal pair is unordered
                'outer: for x in &a.binds {
                    for y in &b.binds {
                        let (sx, sy) = (x.specificity(), y.specificity());
                        if sx != 0 && sy != 0 && sx != sy {
                            continue;
                        }
                        let (ix, iy) = (bind_intents(a, x), bind_intents(b, y));
                        if !ix.iter().any(|i| iy.contains(i)) {
                            continue;
                        }
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
    fn specificity_orders_item_tool_broad() {
        let broad = Bind::Item("/obj/item".into()).specificity();
        let tool = Bind::Tool("TOOL_X".into()).specificity();
        let pen = Bind::Item("/obj/item/pen".into()).specificity();
        let plasteel = Bind::Stack("/obj/item/stack/material/plasteel".into()).specificity();
        assert!(broad < tool && tool < pen && pen < plasteel);
        assert_eq!(Bind::Hand.specificity(), 0);
    }

    #[test]
    fn negation() {
        assert!(cond_negates("PANEL_OPEN", "cond_not(PANEL_OPEN)"));
        assert!(cond_negates(&norm_cond("req_is(K)"), &norm_cond("req_is(K,FALSE)")));
        assert!(cond_negates(&norm_cond("req(PROC_REF(x))"), &norm_cond("cond_not(PROC_REF(x))")));
        assert!(cond_negates(&norm_cond("cond_not(cond_not(A))"), &norm_cond("cond_not(A)")));
        assert!(cond_negates("req_graph_at(list(S1,S2))", "req_graph_at(list(S3))"));
        assert!(!cond_negates("req_graph_at(list(S1,S2))", "req_graph_at(list(S2))"));
        assert!(!cond_negates("A", "B"));
    }

    #[test]
    fn conjunctions_and_stances() {
        let mut op = Op::default();
        add_cond(&mut op, "cond_all(nameof(x),req_stance(list(I_HELP,I_GRAB)))");
        assert_eq!(op.conds, vec!["nameof(x)".to_string()]);
        assert_eq!(op.stances.unwrap().into_iter().collect::<Vec<_>>(), vec!["I_GRAB".to_string(), "I_HELP".to_string()]);
        assert!(stance_set("I_HURT, CAP_PROC(x)").is_none());
    }

    #[test]
    fn tiers_by_value() {
        assert_eq!(tier_value("OP_PRIORITY_PART - 1"), Some(9));
        assert_eq!(tier_value("OP_PRIORITY_SUBVERT+1"), Some(51));
        assert!(same_tier("OP_PRIORITY_NORMAL+10", "OP_PRIORITY_PART"));
        assert!(!same_tier("OP_PRIORITY_PART-1", "OP_PRIORITY_PART"));
    }

    #[test]
    fn intents_of_bindings() {
        let drag = Op { gesture: Some("GESTURE_DRAG".into()), ..Op::default() };
        let plain = Op::default();
        let toggle = Op { toggles: true, ..Op::default() };
        let hostile = Op { answers: Some(vec!["INTENT_ATTACK".into()]), ..Op::default() };
        assert_eq!(bind_intents(&drag, &Bind::Item("/obj/item".into())), vec!["INTENT_DROP_ONTO".to_string()]);
        assert_eq!(bind_intents(&plain, &Bind::Hand), vec!["INTENT_USE".to_string()]);
        assert!(bind_intents(&toggle, &Bind::Hand).contains(&"INTENT_TOGGLE".to_string()));
        assert!(!bind_intents(&toggle, &Bind::InHand).contains(&"INTENT_TOGGLE".to_string()));
        assert_eq!(bind_intents(&hostile, &Bind::Hand), vec!["INTENT_ATTACK".to_string()]);
    }

    #[test]
    fn decided_conditions() {
        assert_eq!(eval_cond("(FALSE && TRUE)"), Some(false));
        assert_eq!(eval_cond("FALSE || nameof(x)"), None);
        assert_eq!(eval_cond("TRUE || nameof(x)"), Some(true));
        assert_eq!(eval_cond("!length(list(/obj/a))"), Some(false));
        assert_eq!(eval_cond("length(null)"), Some(false));
        assert_eq!(eval_cond("a == b"), None);
    }

    #[test]
    fn ternaries_take_their_branch() {
        let t = prune_ternaries("list(\n\t(FALSE && TRUE) ? op(\"lid\", in_hand()) : null,\n\t(FALSE || FALSE) ? null : op(\"pour\", at_target()),\n\tx ? op(\"k\") : null)");
        assert!(!t.contains("\"lid\""), "{}", t);
        assert!(t.contains("op(\"pour\", at_target())"), "{}", t);
        assert!(t.contains("x ? op(\"k\") : null"), "{}", t);
        // a null-conditional and a type::var path are not ternaries
        assert_eq!(prune_ternaries("a?.b(/obj/x::y)"), "a?.b(/obj/x::y)");
    }

    #[test]
    fn ifs_keep_their_taken_branch() {
        let t = prune_ifs("\t. = list(op(\"a\"))\n\tif(FALSE)\n\t\t. += op(\"gone\")\n\telse\n\t\t. += op(\"kept\")\n\tif(TRUE) . += op(\"also\")\n\tif(x)\n\t\t. += op(\"maybe\")");
        assert!(!t.contains("gone") && t.contains("kept") && t.contains("also") && t.contains("maybe"), "{}", t);
    }
}
