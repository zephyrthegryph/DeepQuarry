//! Unique original op_order composition/condition judge and per-file DATA.
//! Extracted from the frozen original; no semantic model or alternate scanner.
use std::collections::{BTreeMap,BTreeSet,HashMap,HashSet};
use crate::lint::{Meta,Policy,RuleMeta,ScanKind};
use crate::tree::{SourceFile,CODE_DM};
use crate::raw_marker_policy::{matching_paren,strip_comments_keep_strings};
const H_CLASH: &str = "order them once in the composing bundle's click_order() (code/engine/parts/plan.dm), or give one a different input, tier or a when() exclusive of the other's";
const H_REL: &str = "declare the order once where the ops are composed (click_order() in the bundle), not per type: this count only falls";

pub static META: Meta = Meta {
    name: crate::allow_registry_fields::op_order::SCOPE_META_0.name,
    group: crate::allow_registry_fields::op_order::SCOPE_META_0.group,
    label: "op_order",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Both,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "unordered_clash", hint: H_CLASH }, RuleMeta { name: "relative_priority", hint: H_REL }],
    allow: crate::allow_registry_fields::op_order::ALLOW_0,
    lists: crate::allow_registry_fields::op_order::SCOPE_META_0.lists,
};


/// Neutral rows issued by the SAME original constructor/global-proc scanner.
/// No source view, coverage receipt, semantic model or filesystem path is retained.
#[derive(Default,Clone)]
pub struct FileFacts {
    entries: HashMap<String,String>,
    procs: HashMap<String,(Vec<String>,String)>,
}
pub fn file_facts_using(f:&SourceFile, gate:&dyn Gate)->FileFacts {
    if !gate.checkpoint(){return FileFacts::default();}

    if f.rel.starts_with("code/engine/_generated/"){return FileFacts::default()}
    let mut entries=HashMap::new();
    let mut procs=HashMap::new();
    let text = f.text();
            if !text.contains("entries()") && !text.contains("/proc/") {
                return FileFacts::default();
            }
            let stripped=match crate::raw_marker_policy::strip_comments_keep_strings_using(text,&mut GateControl(gate)){Ok(value)=>value,Err(())=>return FileFacts::default()};
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
                if cur.is_some()&&gate.checked()&&!gate.reserve(line.len().checked_mul(4).and_then(|n|n.checked_add(64))){return FileFacts::default()}
        if !gate.checkpoint(){return FileFacts::default();}
                if !line.is_empty() && !line.starts_with(|c: char| c.is_whitespace()) {
                    flush(&mut cur, &mut body);
                    if let Some(m) = gate.captures_pattern(r"^(/datum/[\w/]+)/entries\(\)",line,||crate::pat_match!(r"^(/datum/[\w/]+)/entries\(\)")) {
                        if gate.checked()&&!gate.reserve(m.s(1).len().checked_mul(4).and_then(|n|n.checked_add(4096))){return FileFacts::default()}cur = Some((true, m.s(1).to_string(), Vec::new()));
                    } else if let Some(m) = gate.captures_pattern(r"^/proc/(\w+)\(([^)]*)\)",line,||crate::pat_match!(r"^/proc/(\w+)\(([^)]*)\)")) {
                        if gate.checked()&&!gate.reserve(m.s(1).len().checked_add(m.s(2).len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(4096))){return FileFacts::default()}
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

    FileFacts{entries,procs}
}
#[derive(Clone,Copy)]
pub struct Marker<'a>{pub name:&'a str,pub relative:&'a str,pub line:u32,pub args:&'a [String]}
pub struct Clash {pub message:String,pub key:String}
// ---- the model ----

/// A capability's constructor: its op prefix, its params in order (with defaults), the selector param and the body of its entries().
struct CapDef {
    prefix: String,
    params: Vec<(String, String)>,
    selector: Option<String>,
    body: String,
}

pub struct Model {
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
    fn text_bytes(&self)->usize{match self{Self::Hand|Self::InHand=>0,Self::Tool(s)|Self::Item(s)|Self::Stack(s)=>s.len()}}
    fn describe_using(&self, gate:&dyn Gate) -> String {
    if !gate.checkpoint(){return String::new();}
    if gate.checked()&&!gate.reserve(Some(match self{Bind::Hand|Bind::InHand=>128,Bind::Tool(s)|Bind::Item(s)|Bind::Stack(s)=>s.len().saturating_mul(2).saturating_add(128)})){return String::new();}

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

fn unquote_using(s: &str, gate:&dyn Gate) -> Option<String> {
    if !gate.checkpoint(){return None;}
    if gate.checked()&&!gate.reserve(s.len().checked_mul(2).and_then(|n|n.checked_add(64))){return None;}

    let t = s.trim();
    t.strip_prefix('"').and_then(|x| x.strip_suffix('"')).map(|x| x.to_string())
}

/// `name(` at `at` in `text`: the call's name and its argument text, or None.
fn call_at_using(text: &str, at: usize, gate:&dyn Gate) -> Option<(String, usize, usize)> {
    if !gate.checkpoint(){return None;}
    if gate.checked()&&!gate.reserve(text.len().checked_mul(2).and_then(|n|n.checked_add(64))){return None;}

    let b = text.as_bytes();
    let mut e = at;
    while e < b.len() && (b[e].is_ascii_alphanumeric() || b[e] == b'_') {
        if !gate.checkpoint(){return None;}
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
fn calls_using(text: &str, gate:&dyn Gate) -> Vec<(String, String)> {
    if !gate.checkpoint(){return Vec::new();}

    let b = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    let mut in_str = false;
    while i < b.len() {
        if !gate.checkpoint(){return Vec::new();}
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
            if let Some((name, open, close)) = call_at_using(text, i, gate) {
                if gate.checked()&&!gate.reserve(name.len().checked_add(close-open).and_then(|n|n.checked_mul(2)).and_then(|n|n.checked_add(128))){return Vec::new()}
                if out.len()==out.capacity(){let goal=out.capacity().saturating_mul(2).max(4);if gate.checked()&&!gate.reserve(goal.checked_mul(std::mem::size_of::<(String,String)>()).and_then(|n|n.checked_add(128))){return Vec::new()}if out.try_reserve_exact(goal-out.len()).is_err(){gate.allocation_failed();return Vec::new()}}
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
        if !gate.checkpoint(){return Vec::new();}
                i += 1;
            }
            continue;
        }
        i += 1;
    }
    out
}

/// Replaces whole identifiers of `subst` in `text` (not a call name, not a member, not the name of a named argument, not inside a string).
fn substitute_using(text: &str, subst: &HashMap<String, String>, gate:&dyn Gate) -> String {
    if !gate.checkpoint(){return String::new();}
    if gate.checked()&&!gate.reserve(text.len().checked_mul(subst.values().map(|s|s.len()).max().unwrap_or(1).max(2)).and_then(|n|n.checked_mul(3)).and_then(|n|n.checked_add(128))){return String::new();}

    if subst.is_empty() {
        return text.to_string();
    }
    let b = text.as_bytes();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    let mut in_str = false;
    while i < b.len() {
        if !gate.checkpoint(){return String::new();}
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
        if !gate.checkpoint(){return String::new();}
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
fn bind_args_using(params: &[(String, String)], args_text: &str, gate:&dyn Gate) -> HashMap<String, String> {
    if !gate.checkpoint(){return HashMap::new();}
    if gate.checked()&&!gate.reserve(params.iter().try_fold(args_text.len(),|n,(p,d)|n.checked_add(p.len())?.checked_add(d.len())) .and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(4096))){return HashMap::new();}

    let mut map: HashMap<String, String> = params.iter().map(|(p, d)| (p.clone(), d.clone())).collect();
    let mut pos = 0;
    for a in split_args_using(args_text, gate) {
        if !gate.checkpoint(){return HashMap::new();}
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
pub fn from_facts<'a>(files:impl IntoIterator<Item=&'a FileFacts>,markers:&[Marker<'_>])->Model{Self::from_facts_using(files.into_iter().cloned(),markers,&Unchecked)}
    pub fn from_owned_facts(files:impl IntoIterator<Item=FileFacts>,markers:&[Marker<'_>])->Model{Self::from_facts_using(files,markers,&Unchecked)}
pub fn judge(&self,args:&[String])->Vec<Clash>{self.judge_using(args,&Unchecked)}

    /// Merge file facts in original all_files order, and marker rows in the
    /// original Decls DME/file/line order. Last definitions still win.
    pub fn from_facts_using(files:impl IntoIterator<Item=FileFacts>,markers:&[Marker<'_>], gate:&dyn Gate)->Model {
    if !gate.checkpoint(){return Model{caps:HashMap::new(),bundles:HashMap::new(),procs:HashMap::new()};}

        let mut entries=HashMap::new();let mut procs=HashMap::new();
        for file in files {
            if !gate.checkpoint(){return Model{caps:HashMap::new(),bundles:HashMap::new(),procs:HashMap::new()}}
            for(name,body)in file.entries{if gate.checked()&&!gate.reserve(Some(4096)){return Model{caps:HashMap::new(),bundles:HashMap::new(),procs:HashMap::new()}}entries.insert(name,body);}
            for(name,body)in file.procs{if gate.checked()&&!gate.reserve(Some(4096)){return Model{caps:HashMap::new(),bundles:HashMap::new(),procs:HashMap::new()}}procs.insert(name,body);}
        }
        if gate.checked()&&!gate.reserve(markers.iter().try_fold(0usize,|n,m|m.args.iter().try_fold(n,|n,s|n.checked_add(s.len().checked_mul(4)?)?.checked_add(256))).and_then(|n|n.checked_add(markers.len().checked_mul(4096)?))){return Model{caps:HashMap::new(),bundles:HashMap::new(),procs:HashMap::new()}}
        let mut caps = HashMap::new();
        for m in markers.iter().filter(|m| m.name == "CAPABILITY_TYPE" || m.name == "CAPABILITY_DEF") {
        if !gate.checkpoint(){return Model{caps:HashMap::new(),bundles:HashMap::new(),procs:HashMap::new()};}
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
        if !gate.checkpoint(){return Model{caps:HashMap::new(),bundles:HashMap::new(),procs:HashMap::new()};}
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
            if gate.checked()&&!gate.reserve(entries.get(&datum).map_or(Some(64),|s|s.len().checked_mul(2).and_then(|n|n.checked_add(64)))){return Model{caps:HashMap::new(),bundles:HashMap::new(),procs:HashMap::new()}}
            let body = entries.get(&datum).cloned().unwrap_or_default();
            caps.insert(name.clone(), CapDef { prefix, params, selector, body });
        }
        let mut bundles=HashMap::new();
        for m in markers.iter().filter(|m|m.name==crate::raw_marker_policy::ENTRY_PROC){
            if !gate.checkpoint(){return Model{caps:HashMap::new(),bundles:HashMap::new(),procs:HashMap::new()}}
            if let Some(n)=m.args.first(){bundles.insert(n.trim().to_string(),m.args[1..].join(", "));}
        }
        Model { caps, bundles, procs }
    }

    /// Adds what `text` (an entry, or a body of entries) brings to `comp`: op keys get `prefix`.
    fn expand_using(&self, text: &str, prefix: &str, subst: &HashMap<String, String>, comp: &mut Composition, seen: &mut HashSet<String>, depth: usize, gate:&dyn Gate) {
    if !gate.checkpoint(){return;}
    if gate.checked()&&!gate.reserve(text.len().checked_add(prefix.len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(4096))){return;}

        if depth > 8 {
            return;
        }
        let text = substitute_using(text, subst, gate);
        // a constructor's params decide some of its entries: `lid ? op(...) : null`, `if(by_hand)`
        let text = if subst.is_empty() { text } else { prune_ifs_using(&prune_ternaries_using(&text, gate), gate) };
        // a local `var/list/x = list(...)` of a body stands for its value where it is named
        let mut locals = HashMap::new();
        for c in gate.captures_pattern_rows(r"var/list/(\w+)\s*=\s*",&text,||crate::pat!(r"var/list/(\w+)\s*=\s*")) {
        if !gate.checkpoint(){return;}
            let start = c.end(0);
            if let Some((name, open, close)) = call_at_using(&text, start, gate) {
                locals.insert(c.s(1).to_string(), format!("{}({})", name, &text[open..close]));
            }
        }
        let text = if locals.is_empty() { text } else { substitute_using(&text, &locals, gate) };
        for (name, args) in calls_using(&text, gate) {
        if !gate.checkpoint(){return;}
            match name.as_str() {
                "op" => {
                    if let Some(op) = self.parse_op_using(&args, prefix, 0, gate) {
                        if !comp.ops.contains_key(&op.key) {
                            comp.order.push(op.key.clone());
                        }
                        comp.ops.insert(op.key.clone(), op);
                    }
                }
                "stages" => {
                    // one op per stage_step() (code/library/structures/stages.dm)
                    let staged=match crate::raw_marker_policy::stages_op_args_controlled(&args,&mut GateControl(gate)){Ok(value)=>value,Err(())=>return};
                    for op_args in staged {
        if !gate.checkpoint(){return;}
                        if let Some(op) = self.parse_op_using(&op_args, prefix, 0, gate) {
                            if !comp.ops.contains_key(&op.key) {
                                comp.order.push(op.key.clone());
                            }
                            comp.ops.insert(op.key.clone(), op);
                        }
                    }
                }
                "extend" => {
                    let parts = split_args_using(&args, gate);
                    let Some(target) = parts.first() else { continue };
                    let keys: Vec<String> = if let Some(k) = unquote_using(target, gate) {
                        vec![k]
                    } else if let Some(inner) = target.strip_prefix("list(").and_then(|t| t.strip_suffix(')')) {
                        split_args_using(inner, gate).iter().filter_map(|k| unquote_using(k, gate)).collect()
                    } else {
                        Vec::new()
                    };
                    if !keys.is_empty() {
                        comp.extends.push((keys, parts[1..].to_vec()));
                    }
                }
                "click_order" => {
                    let parts = split_args_using(&args, gate);
                    let Some(input) = parts.first() else { continue };
                    let input = match input.trim() {
                        "BIND_HAND" => "hand".to_string(),
                        "BIND_IN_HAND" => "in_hand".to_string(),
                        "BIND_ITEM" => "item".to_string(),
                        other => other.to_string(),
                    };
                    let mut ranks = Vec::new();
                    for p in &parts[1..] {
        if !gate.checkpoint(){return;}
                        if let Some(k) = unquote_using(p, gate) {
                            ranks.push(vec![k]);
                        } else if let Some(inner) = p.strip_prefix("list(").and_then(|t| t.strip_suffix(')')) {
                            ranks.push(split_args_using(inner, gate).iter().filter_map(|k| unquote_using(k, gate)).collect());
                        }
                    }
                    comp.chains.push((input, ranks));
                }
                _ => {
                    if let Some(cap) = self.caps.get(&name) {
                        let bound = bind_args_using(&cap.params, &args, gate);
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
                            self.expand_using(&cap.body, &pre, &bound, comp, seen, depth + 1, gate);
                        }
                    } else if let Some(body) = self.bundles.get(&name).filter(|_| args.trim().is_empty()) {
                        if seen.insert(format!("bundle|{}", name)) {
                            self.expand_using(body, prefix, &HashMap::new(), comp, seen, depth + 1, gate);
                        }
                    } else if let Some((params, body)) = self.procs.get(&name) {
                        // a named bundle (a global proc returning entries): its ops are the type's own
                        if body.contains("op(") || body.contains("extend(") || body.contains("click_order(") {
                            let pdefs: Vec<(String, String)> = params.iter().map(|p| (p.clone(), "null".to_string())).collect();
                            let bound = bind_args_using(&pdefs, &args, gate);
                            let sig = format!("{}|{}", name, args);
                            if seen.insert(sig) {
                                self.expand_using(body, prefix, &bound, comp, seen, depth + 1, gate);
                            }
                        }
                    }
                }
            }
        }
    }

    /// An op(...) call's model, or None when it has no physical input we compare (a window button, a menu entry).
    fn parse_op_using(&self, args: &str, prefix: &str, depth: usize, gate:&dyn Gate) -> Option<Op> {
    if !gate.checkpoint(){return None;}
    if gate.checked()&&!gate.reserve(args.len().checked_add(prefix.len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(4096))){return None;}

        let parts = split_args_using(args, gate);
        let key = unquote_using(parts.first()?, gate)?;
        let mut op = Op { key: format!("{}{}", prefix, key), ..Op::default() };
        let mut yields_part = false;
        let mut take_out = false;
        for p in &parts[1..] {
        if !gate.checkpoint(){return None;}
            self.read_part_using(p, &mut op, &mut yields_part, &mut take_out, depth, gate);
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
                tier_name_using(tier, gate)
            }
        };
        Some(op)
    }

    fn read_part_using(&self, part: &str, op: &mut Op, yields_part: &mut bool, take_out: &mut bool, depth: usize, gate:&dyn Gate) {
    if !gate.checkpoint(){return;}
    if gate.checked()&&!gate.reserve(part.len().checked_mul(128).and_then(|n|n.checked_add(4096))){return;}

        let p = part.trim();
        let Some((name, open, close)) = call_at_using(p, 0, gate) else { return };
        let inner = &p[open..close];
        let first = split_args_using(inner, gate).first().cloned().unwrap_or_default();
        let none = |v: &str| v.is_empty() || v == "NONE" || v == "null";
        match name.as_str() {
            "hand" => op.binds.push(Bind::Hand),
            "in_hand" => op.binds.push(Bind::InHand),
            "tool" | "any_of_tools" => {
                for q in split_args_using(inner, gate) {
        if !gate.checkpoint(){return;}
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
                for q in split_args_using(inner, gate) {
        if !gate.checkpoint(){return;}
                    self.read_part_using(&q, op, yields_part, take_out, depth, gate);
                }
            }
            other => {
                if apply_select_using(other, inner, op, gate) {
                    return;
                }
                // a part bundle (force_pry(), component_swap(T)): a global proc returning parts
                if depth < 4 {
                    if let Some((_, body)) = self.procs.get(other) {
                        if let Some(at) = body.find("return ") {
                            let ret = body[at + 7..].trim();
                            if let Some((n2, o2, c2)) = call_at_using(ret, 0, gate) {
                                if n2 == "list" {
                                    for q in split_args_using(&ret[o2..c2], gate) {
        if !gate.checkpoint(){return;}
                                        self.read_part_using(&q, op, yields_part, take_out, depth + 1, gate);
                                    }
                                } else {
                                    self.read_part_using(&ret[..=c2], op, yields_part, take_out, depth + 1, gate);
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
fn apply_select_using(name: &str, inner: &str, op: &mut Op, gate:&dyn Gate) -> bool {
    if !gate.checkpoint(){return false;}
    if gate.checked()&&!gate.reserve(inner.len().checked_mul(128).and_then(|n|n.checked_add(4096))){return false;}

    let first = split_args_using(inner, gate).first().cloned().unwrap_or_default();
    match name {
        "priority" => {
            if let Some(rest) = first.strip_prefix("above(").or_else(|| first.strip_prefix("below(")) {
                op.rel = unquote_using(rest.trim_end_matches(')'), gate);
            } else if first.starts_with("OP_PRIORITY_") {
                op.explicit_tier = Some(compact_using(&first, gate));
                op.tier = compact_using(&first, gate);
            }
        }
        "when" => {
            for c in split_args_using(inner, gate) {
        if !gate.checkpoint(){return false;}
                add_cond_using(op, &compact_using(&c, gate), gate);
            }
        }
        "answers" => op.answers = Some(split_args_using(inner, gate).iter().map(|s| s.trim().to_string()).collect()),
        "hostile" => {
            op.answers = Some(vec!["INTENT_ATTACK".to_string()]);
            op.hostile = true;
        }
        "gesture" => op.gesture = Some(first.trim().to_string()),
        "stance" => op.stances = stance_set_using(inner, gate),
        "toggles" | "toggles_hold" => op.toggles = true,
        "presents" => op.presents = true,
        "passes" => op.passes = true,
        _ => return false,
    }
    true
}

/// `s` is `name(...)` with the call closing at its last character: the argument text, or None.
fn whole_call_using<'a>(s: &'a str, name: &str, gate:&dyn Gate) -> Option<&'a str> {
    if !gate.checkpoint(){return None;}

    let rest = s.strip_prefix(name)?;
    if !rest.starts_with('(') || matching_paren(s, name.len()) != Some(s.len() - 1) {
        return None;
    }
    Some(&s[name.len() + 1..s.len() - 1])
}

/// The stances a stance(...) / req_stance(...) argument list names, or None when one is not a literal I_X.
fn stance_set_using(inner: &str, gate:&dyn Gate) -> Option<BTreeSet<String>> {
    if !gate.checkpoint(){return None;}
    if gate.checked()&&!gate.reserve(inner.len().checked_mul(128).and_then(|n|n.checked_add(4096))){return None;}

    let mut out = BTreeSet::new();
    for a in split_args_using(inner, gate) {
        if !gate.checkpoint(){return None;}
        let a = a.trim();
        if let Some(l) = whole_call_using(a, "list", gate) {
            out.extend(stance_set_using(l, gate)?);
        } else if a.starts_with("I_") && a.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            out.insert(a.to_string());
        } else if !a.is_empty() {
            return None;
        }
    }
    Some(out)
}

/// Adds one when() condition: a conjunction is split into its conjuncts, a stance condition narrows the op's stances.
fn add_cond_using(op: &mut Op, c: &str, gate:&dyn Gate) {
    if !gate.checkpoint(){return;}
    if gate.checked()&&!gate.reserve(c.len().checked_mul(128).and_then(|n|n.checked_add(4096))){return;}

    if let Some(inner) = whole_call_using(c, "all_of", gate) {
        for part in split_args_using(inner, gate) {
        if !gate.checkpoint(){return;}
            add_cond_using(op, &compact_using(&part, gate), gate);
        }
        return;
    }
    if let Some(set) = whole_call_using(c, "req_stance", gate).and_then(|value|stance_set_using(value, gate)) {
        op.stances = Some(match op.stances.take() {
            Some(prev) => prev.intersection(&set).cloned().collect(),
            None => set,
        });
        return;
    }
    op.conds.push(norm_cond_using(c, gate));
}

/// One condition in a canonical spelling, so two spellings of one test compare equal: req_bool(X) is X, req_is(K) is K, req_is(K, FALSE) is
/// not(K), and a double negation cancels.
fn norm_cond_using(c: &str, gate:&dyn Gate) -> String {
    if !gate.checkpoint(){return String::new();}
    if gate.checked()&&!gate.reserve(c.len().checked_mul(8).and_then(|n|n.checked_add(512))){return String::new();}

    let c = c.trim();
    if let Some(inner) = whole_call_using(c, "not", gate) {
        let n = norm_cond_using(inner, gate);
        return match whole_call_using(&n, "not", gate) {
            Some(back) => back.to_string(),
            None => format!("not({})", n),
        };
    }
    if let Some(inner) = whole_call_using(c, "req_is", gate) {
        let args: Vec<String> = split_args_using(inner, gate).into_iter().filter(|a| !a.contains('=') || a.contains("==")).collect();
        if let Some(key) = args.first() {
            match args.get(1).map(|v| v.as_str()) {
                Some("FALSE") | Some("0") => return format!("not({})", norm_cond_using(key, gate)),
                None | Some("TRUE") | Some("1") => return norm_cond_using(key, gate),
                _ => {}
            }
        }
    }
    if let Some(inner) = whole_call_using(c, "req_stage", gate) {
        // req_stage(K, v): K is exactly v; two of one K with different values exclude each other (cond_negates)
        let args: Vec<String> = split_args_using(inner, gate).into_iter().filter(|a| !a.contains('=') || a.contains("==")).collect();
        if let (Some(key), Some(value)) = (args.first(), args.get(1)) {
            return format!("stage({})=={}", compact_using(key, gate), compact_using(value, gate));
        }
    }
    if let Some(inner) = whole_call_using(c, "req_actor_kind", gate) {
        // req_actor_kind(types, because =, not = TRUE): the kinds are the test, `not = TRUE` negates it, the reason is no part of the condition.
        let args = split_args_using(inner, gate);
        let mut types: Option<String> = None;
        let mut negated = false;
        for a in &args {
        if !gate.checkpoint(){return String::new();}
            let a = a.trim();
            if let Some((name, value)) = a.split_once('=') {
                if name.trim() == "not" {
                    negated = matches!(value.trim(), "TRUE" | "1");
                }
            } else if types.is_none() {
                types = Some(compact_using(a, gate));
            }
        }
        if let Some(t) = types {
            let base = format!("actor_kind({})", t);
            return if negated { format!("not({})", base) } else { base };
        }
    }
    if let Some(inner) = whole_call_using(c, "req_bool", gate) {
        let args = split_args_using(inner, gate);
        if args.len() == 1 {
            return norm_cond_using(&args[0], gate);
        }
    }
    c.to_string()
}

/// The value of a tier expression (OP_PRIORITY_X, OP_PRIORITY_X+n, OP_PRIORITY_X-n, a number), or None.
fn tier_value_using(expr: &str, gate:&dyn Gate) -> Option<i64> {
    if !gate.checkpoint(){return None;}
    if gate.checked()&&!gate.reserve(expr.len().checked_mul(4).and_then(|n|n.checked_add(128))){return None;}

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
    for ch in compact_using(expr, gate).chars().chain(std::iter::once('+')) {
        if !gate.checkpoint(){return None;}
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

fn tier_name_using(v: i64, gate:&dyn Gate) -> String {
    if !gate.checkpoint(){return String::new();}
    if gate.checked()&&!gate.reserve(Some(128)){return String::new();}

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

fn same_tier_using(a: &str, b: &str, gate:&dyn Gate) -> bool {
    if !gate.checkpoint(){return false;}

    match (tier_value_using(a, gate), tier_value_using(b, gate)) {
        (Some(x), Some(y)) => x == y,
        _ => a == b,
    }
}

/// The intents an op answers through one of its bindings (resolve.dm, op_answers): answers() when written, else a pinned gesture's, else
/// INTENT_USE (and INTENT_TOGGLE for a toggling hand op; INTENT_PRESENT alone for presents()).
fn bind_intents_using(op: &Op, b: &Bind, gate:&dyn Gate) -> Vec<String> {
    if !gate.checkpoint(){return Vec::new();}
    if gate.checked()&&!gate.reserve(op.answers.as_ref().map_or(Some(512),|rows|rows.iter().try_fold(rows.len().checked_mul(4*std::mem::size_of::<String>())?,|n,s|n.checked_add(s.len().checked_mul(2)?)?.checked_add(128))).and_then(|n|n.checked_add(op.gesture.as_ref().map_or(0,String::len).checked_mul(2)?))){return Vec::new();}

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
fn eval_cond_using(s: &str, gate:&dyn Gate) -> Option<bool> {
    if !gate.checkpoint(){return None;}

    let toks = cond_tokens_using(s, gate)?;
    let mut i = 0;
    let v = cond_or_using(&toks, &mut i, gate)?;
    if i != toks.len() {
        return None;
    }
    v
}

/// Tokens: operators ("!", "&&", "||", "(", ")", "==", "!=") and whole terms (a call with its arguments, a word, a number, a string, a path).
fn cond_tokens_using(s: &str, gate:&dyn Gate) -> Option<Vec<String>> {
    if !gate.checkpoint(){return None;}
    if gate.checked()&&!gate.reserve(s.len().checked_mul(4*std::mem::size_of::<String>()).and_then(|n|n.checked_add(s.len().checked_mul(2)?)).and_then(|n|n.checked_add(128))){return None;}

    let b = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        if !gate.checkpoint(){return None;}
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
        if !gate.checkpoint(){return None;}
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
        if !gate.checkpoint(){return None;}
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
fn cond_or_using(t: &[String], i: &mut usize, gate:&dyn Gate) -> Option<Option<bool>> {
    if !gate.checkpoint(){return None;}

    let mut v = cond_and_using(t, i, gate)?;
    while t.get(*i).map(|x| x == "||").unwrap_or(false) {
        if !gate.checkpoint(){return None;}
        *i += 1;
        let r = cond_and_using(t, i, gate)?;
        v = match (v, r) {
            (Some(true), _) | (_, Some(true)) => Some(true),
            (Some(false), Some(false)) => Some(false),
            _ => None,
        };
    }
    Some(v)
}

fn cond_and_using(t: &[String], i: &mut usize, gate:&dyn Gate) -> Option<Option<bool>> {
    if !gate.checkpoint(){return None;}

    let mut v = cond_unary_using(t, i, gate)?;
    while t.get(*i).map(|x| x == "&&").unwrap_or(false) {
        if !gate.checkpoint(){return None;}
        *i += 1;
        let r = cond_unary_using(t, i, gate)?;
        v = match (v, r) {
            (Some(false), _) | (_, Some(false)) => Some(false),
            (Some(true), Some(true)) => Some(true),
            _ => None,
        };
    }
    Some(v)
}

fn cond_unary_using(t: &[String], i: &mut usize, gate:&dyn Gate) -> Option<Option<bool>> {
    if !gate.checkpoint(){return None;}
    if gate.checked()&&!gate.reserve(t.get(*i).map_or(Some(64),|s|s.len().checked_mul(2).and_then(|n|n.checked_add(64)))){return None;}

    let tok = t.get(*i)?.clone();
    *i += 1;
    let v = match tok.as_str() {
        "!" => return cond_unary_using(t, i, gate).map(|v| v.map(|b| !b)),
        "(" => {
            let v = cond_or_using(t, i, gate)?;
            if t.get(*i).map(|x| x.as_str()) != Some(")") {
                return None;
            }
            *i += 1;
            v
        }
        ")" | "&&" | "||" | "==" | "!=" => return None,
        term => term_truth_using(term, gate),
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

fn term_truth_using(term: &str, gate:&dyn Gate) -> Option<bool> {
    if !gate.checkpoint(){return None;}

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
    if term.starts_with('/') || whole_call_using(term, "list", gate).is_some() {
        return Some(true);
    }
    if let Some(inner) = whole_call_using(term, "length", gate) {
        let inner = inner.trim();
        if inner == "null" {
            return Some(false);
        }
        if let Some(items) = whole_call_using(inner, "list", gate) {
            return Some(split_args_using(items, gate).iter().any(|a| !a.trim().is_empty()));
        }
    }
    None
}

/// The bounds of each `cond ? a : b` at one nesting level whose condition is decided, replaced by the branch it takes. Undecided ones stay.
fn prune_ternaries_using(text: &str, gate:&dyn Gate) -> String {
    if !gate.checkpoint(){return String::new();}
    if gate.checked()&&!gate.reserve(text.len().checked_mul(2).and_then(|n|n.checked_add(128))){return String::new();}

    let mut text = text.to_string();
    let mut from = 0;
    'scan: loop {
        if !gate.checkpoint(){return String::new();}
        let b = text.as_bytes();
        let mut in_str = false;
        let mut q = None;
        let mut i = from;
        while i < b.len() {
        if !gate.checkpoint(){return String::new();}
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
        if !gate.checkpoint(){return String::new();}
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
        if !gate.checkpoint(){return String::new();}
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
        let Some(truth) = eval_cond_using(cond, gate) else { continue };
        let branch = if truth { &text[q + 1..colon] } else { &text[colon + 1..end] };
        if gate.checked()&&!gate.reserve(text.len().checked_mul(6).and_then(|n|n.checked_add(256))){return String::new()}
        let branch = branch.trim().to_string();
        let prefix_ws = if start > 0 && !text[..start].ends_with(char::is_whitespace) { " " } else { "" };
        text = format!("{}{}{}{}", &text[..start], prefix_ws, branch, &text[end..]);
        from = start;
    }
    text
}

/// Drops the statements of an `if(cond)` whose condition is decided false (keeping its else), or the else of one decided true.
fn prune_ifs_using(text: &str, gate:&dyn Gate) -> String {
    if !gate.checkpoint(){return String::new();}
    if gate.checked()&&!gate.reserve(text.len().checked_mul(96).and_then(|n|n.checked_add(4096))){return String::new();}

    let lines: Vec<&str> = text.split('\n').collect();
    let indent = |l: &str| l.len() - l.trim_start().len();
    let mut out: Vec<String> = Vec::with_capacity(lines.len());
    let mut i = 0;
    while i < lines.len() {
        if !gate.checkpoint(){return String::new();}
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
        if !gate.checkpoint(){return String::new();}
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
        if !gate.checkpoint(){return String::new();}
                    k += 1;
                }
                else_body = lines[j + 1..k].iter().map(|s| s.to_string()).collect();
            } else {
                else_body = vec![format!("{}{}", &lines[j][..ind], erest)];
            }
        }
        match eval_cond_using(cond, gate) {
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

fn compact_using(s: &str, gate:&dyn Gate) -> String {
    if !gate.checkpoint(){return String::new();}
    if gate.checked()&&!gate.reserve(s.len().checked_mul(4).and_then(|n|n.checked_add(64))){return String::new();}

    s.chars().filter(|c| !c.is_whitespace()).collect()
}

fn key_matches_using(key: &str, pattern: &str, gate:&dyn Gate) -> bool {
    if !gate.checkpoint(){return false;}

    match pattern.strip_suffix('*') {
        Some(pre) => key.starts_with(pre),
        None => key == pattern,
    }
}

/// Does a held thing that fits `a` also fit `b`? Same tool quality, or item types where one is the other or its ancestor (item(/obj/item)
/// takes any item, tools included).
fn overlap_using(a: &Bind, b: &Bind, gate:&dyn Gate) -> Option<String> {
    if !gate.checkpoint(){return None;}
    if gate.checked()&&!gate.reserve(Some(a.text_bytes()).and_then(|n|n.checked_add(b.text_bytes())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(512))){return None;}

    let sub = |x: &str, y: &str| x == y || x.starts_with(&format!("{}/", y)) || y.starts_with(&format!("{}/", x));
    match (a, b) {
        (Bind::Hand, Bind::Hand) | (Bind::InHand, Bind::InHand) => Some(a.describe_using(gate)),
        (Bind::Tool(x), Bind::Tool(y)) if x == y => Some(a.describe_using(gate)),
        (Bind::Item(x), Bind::Item(y)) | (Bind::Stack(x), Bind::Stack(y)) | (Bind::Item(x), Bind::Stack(y)) | (Bind::Stack(x), Bind::Item(y)) if sub(x, y) => {
            Some(format!("{} / {}", a.describe_using(gate), b.describe_using(gate)))
        }
        (Bind::Item(x), Bind::Tool(_)) | (Bind::Tool(_), Bind::Item(x)) if x == "/obj/item" => Some(format!("{} / {}", a.describe_using(gate), b.describe_using(gate))),
        _ => None,
    }
}

/// Two normalized conditions (`norm_cond`) that cannot both hold: c against not(c), and graph stages that do not meet.
fn cond_negates_using(a: &str, b: &str, gate:&dyn Gate) -> bool {
    if !gate.checkpoint(){return false;}
    if gate.checked()&&!gate.reserve(a.len().checked_add(b.len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(4096))){return false;}

    if b == format!("not({})", a) || a == format!("not({})", b) {
        return true;
    }
    // req_stage(K, a) against req_stage(K, b), a != b
    if let (Some((ka, va)), Some((kb, vb))) = (a.strip_prefix("stage(").and_then(|s| s.split_once(")==")), b.strip_prefix("stage(").and_then(|s| s.split_once(")=="))) {
        return ka == kb && va != vb;
    }
    // req_graph_at(list(S...)) against one with none of its stages
    if let (Some(x), Some(y)) = (whole_call_using(a, "req_graph_at", gate), whole_call_using(b, "req_graph_at", gate)) {
        let stages = |v: &str| -> Option<BTreeSet<String>> {
            let first = split_args_using(v, gate).into_iter().next()?;
            let first = first.trim();
            let items = whole_call_using(first, "list", gate).map(|value|split_args_using(value, gate)).unwrap_or_else(|| vec![first.to_string()]);
            Some(items.into_iter().map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
        };
        if let (Some(sx), Some(sy)) = (stages(x), stages(y)) {
            return sx.is_disjoint(&sy);
        }
    }
    false
}

impl Composition {
    fn apply_extends_using(&mut self, gate:&dyn Gate) {
    if !gate.checkpoint(){return;}

        for (keys, parts) in std::mem::take(&mut self.extends) {
        if !gate.checkpoint(){return;}
            for k in keys {
        if !gate.checkpoint(){return;}
                let Some(op) = self.ops.get_mut(&k) else { continue };
                for p in &parts {
        if !gate.checkpoint(){return;}
                    let p = p.trim();
                    let Some((name, open, close)) = call_at_using(p, 0, gate) else { continue };
                    apply_select_using(&name, &p[open..close], op, gate);
                }
            }
        }
    }

    /// A click order puts one of the two above the other for an input both take.
    fn chain_orders_using(&self, a: &Op, b: &Op, gate:&dyn Gate) -> bool {
    if !gate.checkpoint(){return false;}

        for (input, ranks) in &self.chains {
        if !gate.checkpoint(){return false;}
            let takes = |o: &Op| o.binds.iter().any(|x| match x {
                Bind::Hand => input == "hand",
                Bind::InHand => input == "in_hand",
                Bind::Item(_) | Bind::Stack(_) => input == "item",
                Bind::Tool(q) => q == input,
            });
            if !takes(a) || !takes(b) {
                continue;
            }
            let rank = |o: &Op| ranks.iter().position(|r| r.iter().any(|p| key_matches_using(&o.key, p, gate)));
            if let (Some(x), Some(y)) = (rank(a), rank(b)) {
                if x != y {
                    return true;
                }
            }
        }
        false
    }

    fn clashes_using(&self, gate:&dyn Gate) -> Vec<(Op, Op, String)> {
    if !gate.checkpoint(){return Vec::new();}

        if gate.checked()&&!gate.reserve(self.order.len().checked_mul(2*std::mem::size_of::<&Op>()).and_then(|n|n.checked_add(128))){return Vec::new()}
        let ops: Vec<&Op> = self.order.iter().filter_map(|k| self.ops.get(k)).collect();
        let mut out = Vec::new();
        let mut reported: BTreeSet<(String, String)> = BTreeSet::new();
        for i in 0..ops.len() {
        if !gate.checkpoint(){return Vec::new();}
            for j in i + 1..ops.len() {
        if !gate.checkpoint(){return Vec::new();}
                let (a, b) = (ops[i], ops[j]);
                if !same_tier_using(&a.tier, &b.tier, gate) || a.passes || b.passes {
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
                if a.conds.iter().any(|x| b.conds.iter().any(|y| cond_negates_using(x, y, gate))) {
                    continue;
                }
                if self.chain_orders_using(a, b, gate) {
                    continue;
                }
                let mut input = None;
                // two bindings meet when they take one held thing and answer an intent in common (plan.dm, op_plans_clash); binding
                // specificity orders two held-item bindings of different specificity (an item type narrower than /obj/item, then a tool
                // quality, then a broad item: resolve.dm, op_binding_specificity), so only an equal pair is unordered
                'outer: for x in &a.binds {
                    for y in &b.binds {
        if !gate.checkpoint(){return Vec::new();}
                        let (sx, sy) = (x.specificity(), y.specificity());
                        if sx != 0 && sy != 0 && sx != sy {
                            continue;
                        }
                        let (ix, iy) = (bind_intents_using(a, x, gate), bind_intents_using(b, y, gate));
                        if !ix.iter().any(|i| iy.contains(i)) {
                            continue;
                        }
                        if let Some(d) = overlap_using(x, y, gate) {
                            input = Some(d);
                            break 'outer;
                        }
                    }
                }
                let Some(input) = input else { continue };
                if gate.checked()&&!gate.reserve(a.storage_bytes().and_then(|n|n.checked_add(b.storage_bytes()?)).and_then(|n|n.checked_add(input.len())).and_then(|n|n.checked_mul(2)).and_then(|n|n.checked_add(4096))){return Vec::new()}
                if reported.insert((a.key.clone(), b.key.clone())) {
                    if out.len()==out.capacity(){let goal=out.capacity().saturating_mul(2).max(4);if gate.checked()&&!gate.reserve(goal.checked_mul(std::mem::size_of::<(Op,Op,String)>()).and_then(|n|n.checked_add(128))){return Vec::new()}if out.try_reserve_exact(goal-out.len()).is_err(){gate.allocation_failed();return Vec::new()}}
                    out.push((a.clone(), b.clone(), input));
                }
            }
        }
        out
    }
}


impl Model {
    pub fn judge_using(&self,args:&[String], gate:&dyn Gate)->Vec<Clash>{
    if !gate.checkpoint(){return Vec::new();}

        let Some(ty)=args.first()else{return Vec::new()};
        let mut comp=Composition::default();let mut seen=HashSet::new();
        for entry in args.iter().skip(1){if !gate.checkpoint(){return Vec::new()}self.expand_using(entry,"",&HashMap::new(),&mut comp,&mut seen,0, gate);}
        comp.apply_extends_using(gate);
        let mut found=Vec::new();
        for(a,b,input)in comp.clashes_using(gate){
            if !gate.checkpoint(){return Vec::new()}
            if gate.checked()&&!gate.reserve(ty.len().checked_add(a.key.len()).and_then(|n|n.checked_add(b.key.len())).and_then(|n|n.checked_add(input.len())).and_then(|n|n.checked_add(a.tier.len())).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(512))){return Vec::new()}
            if found.len()==found.capacity(){let goal=found.capacity().saturating_mul(2).max(4);if gate.checked()&&!gate.reserve(goal.checked_mul(std::mem::size_of::<Clash>()).and_then(|n|n.checked_add(128))){return Vec::new()}if found.try_reserve_exact(goal-found.len()).is_err(){gate.allocation_failed();return Vec::new()}}
            found.push(Clash{message:format!("{}: ops \"{}\" and \"{}\" both answer {} at tier {} with no order between them",ty,a.key,b.key,input,a.tier.trim_start_matches("OP_PRIORITY_")),key:format!("unordered_clash:{}",ty)});
        }
        found
    }
}
pub fn relative_priority_using(f:&SourceFile,mut emit:impl FnMut(usize)->bool, gate:&dyn Gate){
    if !gate.checkpoint(){return;}

    if f.rel.starts_with("code/engine/_generated/"){return}
    for(number,line)in f.clean().numbered(){if !gate.checkpoint(){return}if gate.matches_pattern(r"\bpriority\(\s*(?:above|below)\(",line,||crate::pat!(r"\bpriority\(\s*(?:above|below)\("))&&!emit(number){return}}
}
pub fn file_facts(f:&SourceFile)->FileFacts{file_facts_using(f,&Unchecked)}
pub fn relative_priority(f:&SourceFile,mut emit:impl FnMut(usize)){relative_priority_using(f,|line|{emit(line);true},&Unchecked)}

/// Operation-local resource control only: no source/EOF/model authority.
pub use crate::key_policy_control::{Gate,Controlled};
struct Unchecked;
impl Gate for Unchecked{fn checked(&self)->bool{false}fn checkpoint(&self)->bool{true}fn reserve(&self,_:Option<usize>)->bool{true}fn allocation_failed(&self){}}
fn split_args_using(source:&str,gate:&dyn Gate)->Vec<String>{
 if !gate.checkpoint(){return Vec::new()}let mut out=Vec::new();
 for value in crate::raw_marker_policy::argument_slices(source){
  if gate.checked()&&!gate.reserve(value.len().checked_mul(2).and_then(|n|n.checked_add(128))){return Vec::new()}
  if out.len()==out.capacity(){let goal=out.capacity().saturating_mul(2).max(4);if gate.checked()&&!gate.reserve(goal.checked_mul(std::mem::size_of::<String>()).and_then(|n|n.checked_add(128))){return Vec::new()}if out.try_reserve_exact(goal-out.len()).is_err(){gate.allocation_failed();return Vec::new()}}
  out.push(value.to_owned());
 }out
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn calls_skip_inside_ops() {
        let c = calls_using("list(op(\"a\", tool(TOOL_X)), wires(kind), extend(\"a\", priority(above(\"b\"))))", &Unchecked);
        let names: Vec<&str> = c.iter().map(|(n, _)| n.as_str()).collect();
        assert_eq!(names, vec!["list", "op", "wires", "extend"]);
    }

    #[test]
    fn substitute_skips_calls_and_named_args() {
        let mut m = HashMap::new();
        m.insert("wires".to_string(), "/datum/wires/apc".to_string());
        assert_eq!(substitute_using("wires(wires, wires = wires)", &m, &Unchecked), "wires(/datum/wires/apc, wires = /datum/wires/apc)");
    }

    #[test]
    fn overlap_of_items() {
        assert!(overlap_using(&Bind::Item("/obj/item".into()), &Bind::Item("/obj/item/pen".into()), &Unchecked).is_some());
        assert!(overlap_using(&Bind::Item("/obj/item/pen".into()), &Bind::Item("/obj/item/paper".into()), &Unchecked).is_none());
        assert!(overlap_using(&Bind::Tool("TOOL_X".into()), &Bind::Tool("TOOL_Y".into()), &Unchecked).is_none());
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
        assert!(cond_negates_using("PANEL_OPEN", "not(PANEL_OPEN)", &Unchecked));
        assert!(cond_negates_using(&norm_cond_using("req_is(K)", &Unchecked), &norm_cond_using("req_is(K,FALSE)", &Unchecked), &Unchecked));
        assert!(cond_negates_using(&norm_cond_using("req_bool(PROC_REF(x))", &Unchecked), &norm_cond_using("not(PROC_REF(x))", &Unchecked), &Unchecked));
        assert!(!cond_negates_using(&norm_cond_using("req(PROC_REF(x))", &Unchecked), &norm_cond_using("not(PROC_REF(x))", &Unchecked), &Unchecked), "a null-or-reason requirement is not its callback's boolean truth");
        assert!(cond_negates_using(&norm_cond_using("not(not(A))", &Unchecked), &norm_cond_using("not(A)", &Unchecked), &Unchecked));
        assert!(cond_negates_using("req_graph_at(list(S1,S2))", "req_graph_at(list(S3))", &Unchecked));
        assert!(!cond_negates_using("req_graph_at(list(S1,S2))", "req_graph_at(list(S2))", &Unchecked));
        assert!(!cond_negates_using("A", "B", &Unchecked));
    }

    #[test]
    fn conjunctions_and_stances() {
        let mut op = Op::default();
        add_cond_using(&mut op, "all_of(nameof(x),req_stance(list(I_HELP,I_GRAB)))", &Unchecked);
        assert_eq!(op.conds, vec!["nameof(x)".to_string()]);
        assert_eq!(op.stances.unwrap().into_iter().collect::<Vec<_>>(), vec!["I_GRAB".to_string(), "I_HELP".to_string()]);
        assert!(stance_set_using("I_HURT, CAP_PROC(x)", &Unchecked).is_none());
    }

    #[test]
    fn tiers_by_value() {
        assert_eq!(tier_value_using("OP_PRIORITY_PART - 1", &Unchecked), Some(9));
        assert_eq!(tier_value_using("OP_PRIORITY_SUBVERT+1", &Unchecked), Some(51));
        assert!(same_tier_using("OP_PRIORITY_NORMAL+10", "OP_PRIORITY_PART", &Unchecked));
        assert!(!same_tier_using("OP_PRIORITY_PART-1", "OP_PRIORITY_PART", &Unchecked));
    }

    #[test]
    fn intents_of_bindings() {
        let drag = Op { gesture: Some("GESTURE_DRAG".into()), ..Op::default() };
        let plain = Op::default();
        let toggle = Op { toggles: true, ..Op::default() };
        let hostile = Op { answers: Some(vec!["INTENT_ATTACK".into()]), ..Op::default() };
        assert_eq!(bind_intents_using(&drag, &Bind::Item("/obj/item".into()), &Unchecked), vec!["INTENT_DROP_ONTO".to_string()]);
        assert_eq!(bind_intents_using(&plain, &Bind::Hand, &Unchecked), vec!["INTENT_USE".to_string()]);
        assert!(bind_intents_using(&toggle, &Bind::Hand, &Unchecked).contains(&"INTENT_TOGGLE".to_string()));
        assert!(!bind_intents_using(&toggle, &Bind::InHand, &Unchecked).contains(&"INTENT_TOGGLE".to_string()));
        assert_eq!(bind_intents_using(&hostile, &Bind::Hand, &Unchecked), vec!["INTENT_ATTACK".to_string()]);
    }

    #[test]
    fn click_orders_cover_item_and_in_hand_bindings() {
        let op = |key: &str, bind: Bind| Op { key: key.to_string(), binds: vec![bind], ..Op::default() };
        let mut comp = Composition::default();
        comp.chains.push(("item".to_string(), vec![vec!["stock".to_string()], vec!["open_with_item".to_string()]]));
        comp.chains.push(("in_hand".to_string(), vec![vec!["invoke".to_string()], vec!["skin".to_string()]]));
        assert!(comp.chain_orders_using(&op("stock", Bind::Item("/obj/item".into())), &op("open_with_item", Bind::Item("/obj/item".into())), &Unchecked));
        assert!(comp.chain_orders_using(&op("invoke", Bind::InHand), &op("skin", Bind::InHand), &Unchecked));
        assert!(!comp.chain_orders_using(&op("invoke", Bind::Hand), &op("skin", Bind::Hand), &Unchecked), "an order is for the input it names");
    }

    #[test]
    fn decided_conditions() {
        assert_eq!(eval_cond_using("(FALSE && TRUE)", &Unchecked), Some(false));
        assert_eq!(eval_cond_using("FALSE || nameof(x)", &Unchecked), None);
        assert_eq!(eval_cond_using("TRUE || nameof(x)", &Unchecked), Some(true));
        assert_eq!(eval_cond_using("!length(list(/obj/a))", &Unchecked), Some(false));
        assert_eq!(eval_cond_using("length(null)", &Unchecked), Some(false));
        assert_eq!(eval_cond_using("a == b", &Unchecked), None);
    }

    #[test]
    fn ternaries_take_their_branch() {
        let t = prune_ternaries_using("list(\n\t(FALSE && TRUE) ? op(\"lid\", in_hand()) : null,\n\t(FALSE || FALSE) ? null : op(\"pour\", at_target()),\n\tx ? op(\"k\") : null)", &Unchecked);
        assert!(!t.contains("\"lid\""), "{}", t);
        assert!(t.contains("op(\"pour\", at_target())"), "{}", t);
        assert!(t.contains("x ? op(\"k\") : null"), "{}", t);
        // a null-conditional and a type::var path are not ternaries
        assert_eq!(prune_ternaries_using("a?.b(/obj/x::y)", &Unchecked), "a?.b(/obj/x::y)");
    }

    #[test]
    fn ifs_keep_their_taken_branch() {
        let t = prune_ifs_using("\t. = list(op(\"a\"))\n\tif(FALSE)\n\t\t. += op(\"gone\")\n\telse\n\t\t. += op(\"kept\")\n\tif(TRUE) . += op(\"also\")\n\tif(x)\n\t\t. += op(\"maybe\")", &Unchecked);
        assert!(!t.contains("gone") && t.contains("kept") && t.contains("also") && t.contains("maybe"), "{}", t);
    }
}

impl Op{fn storage_bytes(&self)->Option<usize>{
 let mut n=std::mem::size_of::<Self>().checked_add(self.key.capacity())?.checked_add(self.tier.capacity())?.checked_add(self.binds.len().checked_mul(2*std::mem::size_of::<Bind>())?)?.checked_add(self.conds.len().checked_mul(2*std::mem::size_of::<String>())?)?;
 for b in &self.binds{n=n.checked_add(b.text_bytes())?;}for s in &self.conds{n=n.checked_add(s.len())?;}
 for s in [&self.explicit_tier,&self.gesture,&self.rel].into_iter().flatten(){n=n.checked_add(s.len())?;}
 if let Some(v)=&self.answers{n=n.checked_add(v.len().checked_mul(2*std::mem::size_of::<String>())?)?;for s in v{n=n.checked_add(s.len())?;}}
 if let Some(v)=&self.stances{for s in v{n=n.checked_add(4096)?.checked_add(s.len())?;}}Some(n)
}}
impl FileFacts {pub(crate) fn storage_bytes(&self)->Option<usize>{
 let mut n=self.entries.capacity().checked_mul(4*std::mem::size_of::<(String,String)>())?.checked_add(self.procs.capacity().checked_mul(4*std::mem::size_of::<(String,(Vec<String>,String))>())?)?;
 for(k,v)in &self.entries{n=n.checked_add(k.capacity())?.checked_add(v.capacity())?;}
 for(k,(p,v))in &self.procs{n=n.checked_add(k.capacity())?.checked_add(v.capacity())?.checked_add(p.capacity().checked_mul(std::mem::size_of::<String>())?)?;for s in p{n=n.checked_add(s.capacity())?;}}
 Some(n)
}}

struct GateControl<'a>(&'a dyn Gate);
impl crate::key_policy_control::Control for GateControl<'_>{
 type Error=();const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),()>{if self.0.checkpoint(){Ok(())}else{Err(())}}
 fn reserve(&mut self,n:usize)->Result<(),()>{if self.0.reserve(Some(n)){Ok(())}else{Err(())}}
 fn overflow(&mut self){self.0.reserve(None);}
 fn allocation_failed(&mut self){self.0.allocation_failed();}
}
#[cfg(test)]mod actual_operation_controls{
 use super::*;use std::{cell::Cell,io};use crate::key_policy_control::Control;
 struct Work<'a>{polls:&'a Cell<usize>,fail:usize,left:usize}
 impl Control for Work<'_>{type Error=io::Error;const CHECKED:bool=true;
 fn checkpoint(&mut self)->io::Result<()>{let n=self.polls.get()+1;self.polls.set(n);if n==self.fail{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}}
 fn reserve(&mut self,n:usize)->io::Result<()>{self.left=self.left.checked_sub(n).ok_or(io::ErrorKind::OutOfMemory)?;Ok(())}
 fn overflow(&mut self)->io::Error{io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->io::Error{io::ErrorKind::OutOfMemory.into()}}
 #[test]fn first_mid_composition_io_is_durable_and_never_delivers_partial_clashes(){
  let count=Cell::new(0);let gate=Controlled::new(Work{polls:&count,fail:32,left:64*1024*1024});
  let marker=vec!["/obj/probe".into(),format!("list({})",(0..128).map(|n|format!("op(\"op{n}\",hand())")).collect::<Vec<_>>().join(","))];
  let model=Model::from_facts(&[],&[]);let result=model.judge_using(&marker,&gate);let at=count.get();assert_eq!(at,32);assert!(!gate.checkpoint());assert_eq!(count.get(),at);
  assert_eq!(gate.finish(result).err().unwrap().raw_os_error(),Some(1450));
  let count=Cell::new(0);let gate=Controlled::new(Work{polls:&count,fail:usize::MAX,left:64*1024*1024});let small=vec!["/obj/probe".into(),"op(\"a\",hand())".into(),"op(\"b\",hand())".into()];let result=model.judge_using(&small,&gate);let result=gate.finish(result).unwrap();assert_eq!(result.len(),1);
 }
 #[test]fn actual_denial_precedes_all_unfunded_rows_and_fresh_work_recovers(){
  let count=Cell::new(0);let gate=Controlled::new(Work{polls:&count,fail:usize::MAX,left:0});let value=calls_using("list(op(\"a\",hand()))",&gate);assert_eq!(gate.finish(value).err().unwrap().kind(),io::ErrorKind::OutOfMemory);
  let count=Cell::new(0);let gate=Controlled::new(Work{polls:&count,fail:usize::MAX,left:1024*1024});let value=calls_using("list(op(\"a\",hand()))",&gate);assert_eq!(gate.finish(value).unwrap().len(),2);
 }
}
