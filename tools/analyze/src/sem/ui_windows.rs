//! The window model shared by the `ui_types` generator and the `ui_actions` lint: which window each `CAPABILITIES` block's type opens
//! (its own `interface("Name")`, else the nearest ancestor's) and which window actions its `ui_act()` ops answer.
//!
//! A type's ops answer in the window its type opens; an ancestor's ops answer in every descendant's window too (the runtime collects a
//! holder's ops from its whole lineage: code/engine/parts/inputs.dm, op_plan_by_ui_action()). A window is `open` when its action set cannot
//! be known from the declarations: it forwards unknown actions to another datum (`interface(forwards =)`), an op answers every action
//! (`ui_act("*")`), or an action name is an expression this model cannot read.

use std::collections::{BTreeMap, BTreeSet, HashMap};

use crate::dm::dx::lineage;
use crate::sem::decls::{Decls, ENTRY_PROC};
use crate::tree::{Select, Tree};

/// One window action an op answers.
pub struct WinAct {
    pub name: String,
    /// The op's `ui_act()` part, as written (the generator types its args).
    pub part: String,
    pub owner: String,
    pub rel: String,
    pub line: u32,
}

/// One window: its declaring type, the actions every holder of it answers, and why its set is open (None: closed, every action known).
pub struct WinModel {
    pub owner: String,
    pub rel: String,
    pub line: u32,
    pub acts: Vec<WinAct>,
    pub open: Option<String>,
    /// The `ui_shape(...)` bodies of the declaring blocks, in order.
    pub shapes: Vec<(String, String)>,
    /// Every type with a CAPABILITIES block that opens this window.
    pub holders: Vec<String>,
    /// The blocks that declare this window with no `ui_shape()` in their own lineage: (type, file, line). Each host carries a shape, so
    /// the data check (dq_tgui_ui_data_fixtures) holds every host's ui_data to it, not only the first one's.
    pub unshaped: Vec<(String, String, u32)>,
}

impl WinModel {
    pub fn names(&self) -> BTreeSet<String> {
        self.acts.iter().map(|a| a.name.clone()).collect()
    }
}

struct Block {
    owner: String,
    rel: String,
    line: u32,
    window: Option<Result<String, ()>>,
    forwards: bool,
    open: Option<String>,
    acts: Vec<WinAct>,
    shapes: Vec<String>,
}

/// `#define NAME "text"` across code/: the text names an op key or a ui_act name may be written as.
pub fn text_defines(tree: &Tree) -> std::sync::Arc<HashMap<String, String>> {
    tree.memo("ui_windows/text_defines", || {
        let mut out = HashMap::new();
        static SEL: Select = Select { roots: &[("code", "dm")], hidden: false };
        for f in tree.select(&SEL) {
            let text = f.text();
            if !text.contains("#define") {
                continue;
            }
            for line in text.lines() {
                let l = line.trim_start();
                let Some(rest) = l.strip_prefix("#define") else { continue };
                let rest = rest.trim_start();
                let Some((name, value)) = rest.split_once(|c: char| c.is_whitespace()) else { continue };
                if !is_ident(name) {
                    continue;
                }
                let v = value.split("//").next().unwrap_or("").trim();
                if v.len() >= 2 && v.starts_with('"') && v.ends_with('"') && !v[1..v.len() - 1].contains('"') && !v.contains('[') {
                    out.insert(name.to_string(), v[1..v.len() - 1].to_string());
                }
            }
        }
        out
    })
}

/// A literal text (or a text define) as its value.
fn text_of(s: &str, defines: &HashMap<String, String>) -> Option<String> {
    let s = s.trim();
    if s.len() >= 2 && s.starts_with('"') && s.ends_with('"') {
        let inner = &s[1..s.len() - 1];
        if inner.contains('[') {
            return None; // an embedded expression
        }
        return Some(inner.to_string());
    }
    if is_ident(s) {
        return defines.get(s).cloned();
    }
    None
}

/// Every window the declarations open, by name.
pub fn windows(tree: &Tree, decls: &Decls) -> BTreeMap<String, WinModel> {
    let defines = text_defines(tree);
    // The ops each block composes, its capabilities' and bundles' included (lints/op_order.rs reads the same composition).
    let composed: HashMap<(String, u32), Vec<String>> =
        crate::lints::op_order::composed_ops(tree, decls).into_iter().map(|(_, rel, line, ops)| ((rel, line), ops)).collect();
    let bundles: BTreeMap<String, Vec<String>> =
        decls.markers_named(ENTRY_PROC).filter_map(|m| m.args.first().map(|n| (n.trim().to_string(), m.args[1..].to_vec()))).collect();
    let mut blocks: Vec<Block> = Vec::new();
    for m in decls.markers_named("CAPABILITIES") {
        let Some(owner) = m.args.first() else { continue };
        let mut b = Block { owner: owner.trim().to_string(), rel: m.rel.clone(), line: m.line, window: None, forwards: false, open: None, acts: Vec::new(), shapes: Vec::new() };
        let mut list = Vec::new();
        expand_bundles(&m.args[1..], &bundles, &mut list, 0);
        for raw in &list {
            read_entry(&clean(raw), &mut b, defines.as_ref(), false, 0);
        }
        for args in composed.get(&(m.rel.clone(), m.line)).map(|v| v.as_slice()).unwrap_or(&[]) {
            read_entry(&clean(&format!("op({})", args)), &mut b, defines.as_ref(), true, 0);
        }
        blocks.push(b);
    }
    // The window each type declares itself.
    let mut declared: HashMap<String, Result<String, ()>> = HashMap::new();
    for b in &blocks {
        if let Some(w) = &b.window {
            declared.insert(b.owner.clone(), w.clone());
        }
    }
    let window_of = |t: &str| -> Option<Result<String, ()>> { lineage(t).iter().find_map(|a| declared.get(a).cloned()) };
    let mut out: BTreeMap<String, WinModel> = BTreeMap::new();
    for b in &blocks {
        if let Some(Ok(name)) = &b.window {
            let w = out.entry(name.clone()).or_insert_with(|| WinModel { owner: b.owner.clone(), rel: b.rel.clone(), line: b.line, acts: Vec::new(), open: None, shapes: Vec::new(), holders: Vec::new(), unshaped: Vec::new() });
            for s in &b.shapes {
                w.shapes.push((b.owner.clone(), s.clone()));
            }
            if b.forwards && w.open.is_none() {
                w.open = Some(format!("{} forwards its window actions (interface(forwards =))", b.owner));
            }
        }
    }
    // A declaring block whose lineage has no ui_shape(): the window's data is unchecked on that host.
    let shaped: BTreeSet<String> = blocks.iter().filter(|b| !b.shapes.is_empty()).map(|b| b.owner.clone()).collect();
    for b in &blocks {
        // The engine's own test hosts (code/tests/) exercise the window machinery, not a player's window.
        if b.rel.starts_with("code/tests/") {
            continue;
        }
        if let Some(Ok(name)) = &b.window {
            if !lineage(&b.owner).iter().any(|a| shaped.contains(a.as_str())) {
                if let Some(w) = out.get_mut(name) {
                    w.unshaped.push((b.owner.clone(), b.rel.clone(), b.line));
                }
            }
        }
    }
    // Every holder type that opens a window: the declaring types and their subtypes with blocks.
    let holders: Vec<(String, String)> =
        blocks.iter().filter_map(|b| match window_of(&b.owner) { Some(Ok(w)) => Some((b.owner.clone(), w)), _ => None }).collect();
    for (h, w) in &holders {
        if let Some(m) = out.get_mut(w) {
            if !m.holders.contains(h) {
                m.holders.push(h.clone());
            }
        }
    }
    for b in &blocks {
        if b.acts.is_empty() && b.open.is_none() {
            continue;
        }
        // The windows this block's ops answer in: its own type's, and every holder's below it.
        let mut targets: BTreeSet<String> = BTreeSet::new();
        if let Some(Ok(w)) = window_of(&b.owner) {
            targets.insert(w);
        }
        for (h, w) in &holders {
            if lineage(h).iter().any(|a| *a == b.owner) {
                targets.insert(w.clone());
            }
        }
        for t in targets {
            let Some(w) = out.get_mut(&t) else { continue };
            if w.open.is_none() {
                if let Some(why) = &b.open {
                    w.open = Some(why.clone());
                }
            }
            for a in &b.acts {
                if w.acts.iter().any(|x| x.name == a.name) {
                    continue;
                }
                w.acts.push(WinAct { name: a.name.clone(), part: a.part.clone(), owner: a.owner.clone(), rel: a.rel.clone(), line: a.line });
            }
        }
    }
    out
}

fn read_entry(entry: &str, b: &mut Block, defines: &HashMap<String, String>, ops: bool, depth: usize) {
    let Some((fname, body)) = call_of(entry) else { return };
    match fname {
        "interface" => {
            let parts = split_top(body);
            b.window = Some(match parts.first().and_then(|f| text_of(f, defines)) {
                Some(n) => Ok(n),
                None => Err(()), // named by a var of the host (window_var =)
            });
            b.forwards = parts.iter().skip(1).any(|p| p.trim_start().starts_with("forwards"));
        }
        "ui_shape" => b.shapes.push(body.to_string()),
        "op" if ops => {
            let parts = split_top(body);
            let Some(key_raw) = parts.first() else { return };
            let key = text_of(key_raw, defines);
            for p in parts.iter().skip(1) {
                let Some(ui) = find_ui_act(p) else { continue };
                let (_, ubody) = call_of(&ui).unwrap();
                let first = split_top(ubody).into_iter().next().map(|s| s.trim().to_string()).unwrap_or_default();
                let named = if first.is_empty() || call_of(&first).is_some() { None } else { Some(first.clone()) };
                let name = match &named {
                    Some(n) => text_of(n, defines),
                    None => key.clone(),
                };
                match name {
                    Some(n) if n == "*" => {
                        b.open.get_or_insert_with(|| format!("{} has an op that answers every action (ui_act(\"*\"))", b.owner));
                    }
                    Some(n) => b.acts.push(WinAct { name: n, part: ui.clone(), owner: b.owner.clone(), rel: b.rel.clone(), line: b.line }),
                    None => {
                        b.open.get_or_insert_with(|| format!("{} names a window action by an expression ({})", b.owner, named.as_deref().unwrap_or(key_raw.trim())));
                    }
                }
            }
        }
        _ => {
            // section(name, "doc", entries...), configure(...), when(...): the entries inside.
            if depth < 4 {
                for inner in split_top(body) {
                    read_entry(&clean(&inner), b, defines, ops, depth + 1);
                }
            }
        }
    }
}

/// The `ui_act(...)` call an op part is or wraps (`inputs(hand(), ui_act(...))`).
fn find_ui_act(part: &str) -> Option<String> {
    let (name, body) = call_of(part)?;
    if name == "ui_act" {
        return Some(part.trim().to_string());
    }
    if name == "inputs" || name == "binds" {
        for inner in split_top(body) {
            if let Some(a) = find_ui_act(&inner) {
                return Some(a);
            }
        }
    }
    None
}

/// The entries with each `name()` of an entry proc replaced by the proc's entries (nested ones too).
pub fn expand_bundles(entries: &[String], bundles: &BTreeMap<String, Vec<String>>, out: &mut Vec<String>, depth: usize) {
    for raw in entries {
        let entry = clean(raw);
        if depth < 8 {
            if let Some((name, body)) = call_of(&entry) {
                if body.trim().is_empty() {
                    if let Some(inner) = bundles.get(name) {
                        expand_bundles(inner, bundles, out, depth + 1);
                        continue;
                    }
                }
            }
        }
        out.push(raw.clone());
    }
}

/// A marker argument as one line: the backslash that continued the previous line and the line breaks inside it are not part of the expression.
pub fn clean(s: &str) -> String {
    let joined: String = s.chars().map(|c| if c == '\\' { ' ' } else { c }).collect();
    joined.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// "name(body)" -> (name, body), when the whole text is one call.
pub fn call_of(s: &str) -> Option<(&str, &str)> {
    let s = s.trim();
    let open = s.find('(')?;
    if !s.ends_with(')') {
        return None;
    }
    let name = s[..open].trim();
    if !is_ident(name) {
        return None;
    }
    // The closing paren must close this call (not `a(x) + b(y)`).
    let body = &s[open + 1..s.len() - 1];
    let mut depth = 0i32;
    let mut in_str = false;
    for c in body.chars() {
        match c {
            '"' => in_str = !in_str,
            '(' if !in_str => depth += 1,
            ')' if !in_str => {
                depth -= 1;
                if depth < 0 {
                    return None;
                }
            }
            _ => {}
        }
    }
    Some((name, body))
}

pub fn is_ident(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') && !s.chars().next().unwrap().is_ascii_digit()
}

/// Splits at top-level commas (not inside (), [] or a string).
pub fn split_top(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut in_str = false;
    let mut cur = String::new();
    let mut prev = ' ';
    for c in s.chars() {
        if in_str {
            cur.push(c);
            if c == '"' && prev != '\\' {
                in_str = false;
            }
            prev = c;
            continue;
        }
        match c {
            '"' => {
                in_str = true;
                cur.push(c);
            }
            '(' | '[' | '{' => {
                depth += 1;
                cur.push(c);
            }
            ')' | ']' | '}' => {
                depth -= 1;
                cur.push(c);
            }
            ',' if depth == 0 => {
                out.push(cur.trim().to_string());
                cur.clear();
            }
            _ => cur.push(c),
        }
        prev = c;
    }
    if !cur.trim().is_empty() {
        out.push(cur.trim().to_string());
    }
    out
}
