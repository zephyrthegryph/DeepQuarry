//! `analyze gen declare_ids` and `analyze gen declare` (E1, declarations): what the DM compiler cannot do with a marker.
//!
//! Every declaration marker (`CAPABILITIES`, `CAPABILITY_TYPE`, `CAPABILITY_DEF`, `cap_keys`, `STAGE_DEF`, `SOURCE_DEF`,
//! `STATE_GRAPH`, `STAT`) expands to nothing in DM, so an author gives it no id and no constructor of its own (a marker that spans lines
//! ends each line but the last with DM's backslash, which the generator drops). These two generators read the markers from source and
//! write the DM the engine runs:
//!
//! * `declare_ids` -> `code/engine/_generated/ids.dm`: the ids a marker declares (`STAT_X`, `CAP_X`, `SRC_X`, `STAGE_G_N`, `GRAPH_X`) and
//!   the capability-state ids `cap_keys` declares (`COVER_OPEN`). An id that a hand-written `#define` already gives is left alone. The file
//!   is included early in `deepquarry.dme`, before anything that uses an id.
//! * `declare` -> `code/engine/_generated/declare.dm`: the constructor of each capability (`name(params)`, with the params the marker lists,
//!   so DM checks a call's named arguments), the capability datum's param vars with their defaults, the registration rows the engine reads
//!   at boot (capabilities, state keys, stages, sources, state graphs), the `accessor(holder)` of each state key, and each type's
//!   `declared_entries()`: the entries of its `CAPABILITIES(T, ...)` list, copied as written. The proc is defined on `T`, so `nameof(var)`
//!   and `PROC_REF(x)` resolve against the type, and each entry carries its own line for the explain tools.
//!
//! The entry text is copied except for these rewrites (E4 adds `adjusts(a.b, ...)` and `on_change(nameof(a.b), ...)`, whose paths become text): `link(A::a, B::b)` (DM's `link` is a keyword) becomes `entry_link("A::a", "B::b")`,
//! and `configure(CAP_X, "selector", param = value)` becomes `configure(<constructor of CAP_X>("selector", param = value))`.

use std::collections::{BTreeMap, BTreeSet};

use crate::sem::decls::{matching_paren, split_args, Marker};
use crate::sem::gen::{GenCx, GenOut, Generator};

/// Generated capability ids start here, above the ids a hand-written define gives and below the tag ids.
const CAP_BASE: u32 = 300;
/// Stat ids start here: far above any number a contribution's constant value will be.
const STAT_BASE: u32 = 100_000;

fn up(s: &str) -> String {
    s.to_uppercase()
}

/// `name = value` at the top level of an argument (an identifier, then `=` that is not `==`).
fn split_opt(arg: &str) -> Option<(String, String)> {
    let b = arg.as_bytes();
    let mut i = 0;
    while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
        i += 1;
    }
    if i == 0 {
        return None;
    }
    let rest = arg[i..].trim_start();
    let rest = rest.strip_prefix('=')?;
    if rest.starts_with('=') {
        return None;
    }
    Some((arg[..i].to_string(), rest.trim().to_string()))
}

/// Collapses a multi-line expression onto one line (comments are already blanked in marker text).
fn one_line(s: &str) -> String {
    // A marker the preprocessor sees continues its lines with a trailing backslash: that is not part of the expression.
    s.replace("\\\r\n", " ").replace("\\\n", " ").split_whitespace().collect::<Vec<_>>().join(" ")
}

fn quote(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

/// The ids a `#define` outside the generated file already gives.
fn defined_elsewhere(cx: &GenCx, out_rel: &str) -> BTreeSet<String> {
    let mut set = BTreeSet::new();
    for f in cx.tree.select(&crate::tree::CODE_DM) {
        if f.rel == out_rel {
            continue;
        }
        let text = f.text();
        if !text.contains("#define") {
            continue;
        }
        for line in text.lines() {
            let t = line.trim_start();
            if let Some(rest) = t.strip_prefix('#') {
                let rest = rest.trim_start();
                if let Some(rest) = rest.strip_prefix("define") {
                    let name: String = rest.trim_start().chars().take_while(|c| c.is_alphanumeric() || *c == '_').collect();
                    if !name.is_empty() {
                        set.insert(name);
                    }
                }
            }
        }
    }
    set
}

struct Cap {
    name: String,
    id: String,
    ty: String,
    key: Option<String>,
    stacks: Option<String>,
    params: Vec<(String, Option<String>)>,
    /// prefix = "name": the op key prefix, when it is not the constructor's name (a library constructor that cannot take the final name yet).
    prefix: Option<String>,
    rel: String,
    line: u32,
    is_def: bool,
}

fn capabilities(cx: &GenCx, out: &mut GenOut) -> Vec<Cap> {
    let mut caps = Vec::new();
    for m in cx.decls().markers.iter().filter(|m| m.name == "CAPABILITY_TYPE" || m.name == "CAPABILITY_DEF") {
        let is_def = m.name == "CAPABILITY_DEF";
        let need = if is_def { 2 } else { 3 };
        if m.args.len() < need {
            out.diag(&m.rel, m.line, format!("{} needs (name, CAP_X{}, ...)", m.name, if is_def { "" } else { ", /datum/capability/x" }));
            continue;
        }
        let name = m.args[0].clone();
        let id = m.args[1].clone();
        let ty = if is_def { format!("/datum/capability/def/{}", name) } else { m.args[2].clone() };
        let mut cap = Cap { name, id, ty, key: None, stacks: None, params: Vec::new(), prefix: None, rel: m.rel.clone(), line: m.line, is_def };
        for a in &m.args[need..] {
            match split_opt(a) {
                Some((k, v)) if k == "key" => cap.key = Some(v),
                Some((k, v)) if k == "stacks" => cap.stacks = Some(v),
                Some((k, v)) if k == "prefix" => cap.prefix = Some(v.trim().trim_matches('"').to_string()),
                Some((k, v)) => cap.params.push((k, Some(v))),
                None => {
                    if a.chars().all(|c| c.is_alphanumeric() || c == '_') && !a.is_empty() {
                        cap.params.push((a.clone(), None));
                    } else {
                        out.diag(&m.rel, m.line, format!("capability {}: `{}` is neither key =, stacks = nor param = default", cap.name, a));
                    }
                }
            }
        }
        caps.push(cap);
    }
    caps.sort_by(|a, b| a.name.cmp(&b.name));
    caps
}

/// The key option as a DM expression: a bare identifier names a param (a text), NONE stays NONE.
fn key_expr(key: &Option<String>) -> String {
    match key {
        None => "NONE".to_string(),
        Some(k) if k == "NONE" => "NONE".to_string(),
        Some(k) if k.starts_with('"') => k.clone(),
        Some(k) if k.chars().all(|c| c.is_alphanumeric() || c == '_') => quote(k),
        Some(k) => k.clone(),
    }
}

// ---- ids ----

struct Ids;

impl Generator for Ids {
    fn name(&self) -> &'static str {
        "declare_ids"
    }

    fn output(&self) -> &'static str {
        "ids.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let defined = defined_elsewhere(cx, "code/engine/_generated/ids.dm");
        let caps = capabilities(cx, out);
        let mut stats: BTreeMap<String, bool> = BTreeMap::new(); // NAME -> is a status
        for m in cx.markers("STAT") {
            if let Some(n) = m.args.get(1) {
                let is_status = m.args.iter().skip(3).any(|a| split_opt(a).map(|(k, _)| k == "units").unwrap_or(false));
                *stats.entry(up(n)).or_insert(false) |= is_status;
            }
        }
        let sources: BTreeSet<String> = cx.markers("SOURCE_DEF").filter_map(|m| m.args.first().map(|n| up(n))).collect();
        let stages: BTreeSet<String> = cx.markers("STAGE_DEF").filter_map(|m| match (m.args.first(), m.args.get(1)) {
            (Some(g), Some(n)) => Some(format!("{}_{}", up(g), up(n))),
            _ => None,
        }).collect();
        let graphs: BTreeSet<String> = cx.markers("STATE_GRAPH").filter_map(|m| m.args.first().cloned()).collect();

        out.doc("Stat ids: STAT_<NAME> for each STAT(T, name, ...), from 100001. A status (units =) also has STATUS_<NAME> and STAT_<NAME>_IMMUNE.");
        for (i, (name, status)) in stats.iter().enumerate() {
            let id = format!("STAT_{}", name);
            if !defined.contains(&id) {
                out.line(format!("#define {} {}", id, STAT_BASE + 1 + i as u32));
            }
            if *status {
                out.line(format!("#define STATUS_{} STAT_{}", name, name));
                out.line(format!("#define STAT_{}_IMMUNE STAT_IMMUNE(STAT_{})", name, name));
            }
        }
        out.blank();
        out.doc("Capability ids: the CAP_X of each CAPABILITY_TYPE/DEF whose id no hand-written define gives, from 300.");
        let mut next = CAP_BASE;
        let mut seen = BTreeSet::new();
        let mut ids: Vec<&String> = caps.iter().map(|c| &c.id).collect();
        ids.sort();
        for id in ids {
            if !seen.insert(id.clone()) {
                continue;
            }
            if !defined.contains(id) {
                out.line(format!("#define {} {}", id, next));
                next += 1;
            }
        }
        out.blank();
        out.doc("Source ids: SRC_<NAME> for each SOURCE_DEF(name).");
        for (i, name) in sources.iter().enumerate() {
            let id = format!("SRC_{}", name);
            if !defined.contains(&id) {
                out.line(format!("#define {} {}", id, i + 1));
            }
        }
        out.blank();
        out.doc("Build stage ids: STAGE_<GROUP>_<NAME> for each STAGE_DEF(group, name).");
        for (i, name) in stages.iter().enumerate() {
            let id = format!("STAGE_{}", name);
            if !defined.contains(&id) {
                out.line(format!("#define {} {}", id, i + 1));
            }
        }
        out.blank();
        out.doc("State graph ids: the GRAPH_X of each STATE_GRAPH(GRAPH_X, ...).");
        for (i, name) in graphs.iter().enumerate() {
            if !defined.contains(name) {
                out.line(format!("#define {} {}", name, i + 1));
            }
        }
        out.blank();
        out.doc("Capability state ids: <CAPNAME>_<KEY> for each key of a cap_keys(CAP_X, KEY = ..., ...), bit 1 first.");
        let by_id: BTreeMap<&String, &String> = caps.iter().map(|c| (&c.id, &c.name)).collect();
        let mut keys: Vec<(String, String, usize)> = Vec::new();
        for m in cx.markers("cap_keys") {
            let Some(cap_id) = m.args.first() else { continue };
            let cap_name = by_id.get(cap_id).map(|n| up(n)).unwrap_or_else(|| cap_id.trim_start_matches("CAP_").to_string());
            let mut bit = 0;
            for a in m.args.iter().skip(1) {
                if let Some((k, _)) = split_opt(a) {
                    bit += 1;
                    if bit > 24 {
                        out.diag(&m.rel, m.line, format!("cap_keys({}): more than 24 keys; a state word holds at most 24", cap_id));
                        break;
                    }
                    keys.push((format!("{}_{}", cap_name, up(&k)), cap_id.clone(), bit));
                }
            }
        }
        keys.sort();
        for (id, cap_id, bit) in keys {
            if !defined.contains(&id) {
                out.line(format!("#define {} CAPKEY_ID({}, {})", id, cap_id, bit));
            }
        }
    }
}

// ---- declare ----

/// Replaces every call `name(...)` (not a member or a longer name) in `text` by `f(args)`.
fn rewrite_calls(text: &str, name: &str, f: &dyn Fn(&[String]) -> String) -> String {
    let mut out = String::new();
    let b = text.as_bytes();
    let mut i = 0;
    while i < text.len() {
        let rest = &text[i..];
        if rest.starts_with(name) && rest[name.len()..].trim_start().starts_with('(') {
            let before_ok = i == 0 || !(b[i - 1].is_ascii_alphanumeric() || b[i - 1] == b'_' || b[i - 1] == b'.' || b[i - 1] == b'/');
            if before_ok {
                let open = i + name.len() + rest[name.len()..].find('(').unwrap();
                if let Some(close) = matching_paren(text, open) {
                    let args = split_args(&text[open + 1..close]);
                    out.push_str(&f(&args));
                    i = close + 1;
                    continue;
                }
            }
        }
        let ch = text[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}


/// Names of the global procs the declaration forms are: every `/proc/name(` of the engine (code/engine/), with the capability constructors
/// the markers declare. A declaration is written in a type's own `declared_entries()`, where an unqualified `cooldown(...)` would resolve to
/// the type's own `cooldown` proc (an `/obj/item/telecube/proc/cooldown()` captures the part constructor): the generator therefore writes
/// each call as `global.name(...)`, which only the global proc can answer.
fn global_constructors(cx: &GenCx, caps: &[Cap]) -> BTreeSet<String> {
    let mut set: BTreeSet<String> = caps.iter().map(|c| c.name.clone()).collect();
    // `every` keeps its legacy body in code/datums/reactions (the system form) and dispatches a capability's every(interval, then(...)) to the engine.
    set.insert("every".to_string());
    for f in cx.tree.select(&crate::tree::CODE_DM) {
        if !f.rel.starts_with("code/engine/") {
            continue;
        }
        for line in f.text().lines() {
            if let Some(rest) = line.strip_prefix("/proc/") {
                let name: String = rest.chars().take_while(|c| c.is_alphanumeric() || *c == '_').collect();
                if !name.is_empty() && rest[name.len()..].trim_start().starts_with('(') {
                    set.insert(name);
                }
            }
        }
    }
    set
}

/// Writes every call of a global constructor in `text` as `global.name(...)` (not a member call, not a longer name, not inside a string).
fn qualify_globals(text: &str, names: &BTreeSet<String>) -> String {
    let b = text.as_bytes();
    let mut out = String::with_capacity(text.len() + 16);
    let mut i = 0;
    while i < text.len() {
        let c = b[i];
        if c == b'"' {
            // a string literal: copied whole, escapes included
            let mut j = i + 1;
            while j < text.len() && b[j] != b'"' {
                if b[j] == b'\\' {
                    j += 1;
                }
                j += 1;
            }
            let end = (j + 1).min(text.len());
            out.push_str(&text[i..end]);
            i = end;
            continue;
        }
        if c.is_ascii_alphabetic() || c == b'_' {
            let mut j = i;
            while j < text.len() && (b[j].is_ascii_alphanumeric() || b[j] == b'_') {
                j += 1;
            }
            let ident = &text[i..j];
            let prev_ok = i == 0 || !(b[i - 1].is_ascii_alphanumeric() || b[i - 1] == b'_' || b[i - 1] == b'.' || b[i - 1] == b'/');
            let called = text[j..].trim_start().starts_with('(');
            if prev_ok && called && names.contains(ident) {
                out.push_str("global.");
            }
            out.push_str(ident);
            i = j;
            continue;
        }
        let ch = text[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

/// One entry of a CAPABILITIES list, as DM.
fn entry_text(raw: &str, caps: &[Cap], globals: &BTreeSet<String>) -> String {
    let mut t = one_line(raw);
    // `link` (the legacy spelling) and `links` (the block form: `link` is a BYOND reserved word): both become entry_link() with the ends as text.
    for call in ["link", "links"] {
        t = rewrite_calls(&t, call, &|a| {
            let mut parts = vec![quote(a.first().map(|s| s.as_str()).unwrap_or("")), quote(a.get(1).map(|s| s.as_str()).unwrap_or(""))];
            parts.extend(a.iter().skip(2).cloned());
            format!("entry_link({})", parts.join(", "))
        });
    }
    // adjusts(packet.amount, ...): the field path is text (DM has no value for `packet.amount` outside the action's own context).
    t = rewrite_calls(&t, "adjusts", &|a| {
        let Some(first) = a.first() else { return "adjusts()".to_string() };
        let mut parts = vec![if first.starts_with('"') { first.clone() } else { quote(first) }];
        parts.extend(a.iter().skip(1).cloned());
        format!("adjusts({})", parts.join(", "))
    });
    // on_change(nameof(terminal.charge), ANY, ...): nameof() of a path gives only the last name, so the whole path is text.
    t = rewrite_calls(&t, "on_change", &|a| {
        let Some(first) = a.first() else { return "on_change()".to_string() };
        let mut parts: Vec<String> = a.to_vec();
        if let Some(inner) = first.strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')) {
            if inner.contains('.') {
                parts[0] = quote(inner.trim());
            }
        }
        format!("on_change({})", parts.join(", "))
    });
    t = rewrite_calls(&t, "configure", &|a| {
        let Some(first) = a.first() else { return "configure()".to_string() };
        match caps.iter().find(|c| &c.id == first) {
            Some(cap) => format!("configure({}({}))", cap.name, a[1..].join(", ")),
            None => format!("configure({})", a.join(", ")),
        }
    });
    qualify_globals(&t, globals)
}

/// Byte offset of each top-level argument of a marker body, in order (the args are `split_args(body)`).
fn arg_offsets(body: &str, args: &[String]) -> Vec<usize> {
    let mut at = 0;
    let mut out = Vec::new();
    for a in args {
        let mut pos = body[at..].find(a.as_str()).map(|p| at + p).unwrap_or(at);
        at = pos + a.len();
        // The text of an argument may open with the backslash that continued the previous line.
        let bytes = body.as_bytes();
        while pos < at && (bytes[pos].is_ascii_whitespace() || bytes[pos] == b'\\') {
            pos += 1;
        }
        out.push(pos);
    }
    out
}

struct Declare;

impl Generator for Declare {
    fn name(&self) -> &'static str {
        "declare"
    }

    fn output(&self) -> &'static str {
        "declare.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let caps = capabilities(cx, out);
        let globals = global_constructors(cx, &caps);
        section(cx, out, &caps, &globals, false);
        // What the test fixtures declare (files under code/tests/ and code/modules/unit_tests/, see `test_only`) is compiled in test builds only.
        let mut tests = GenOut::default();
        section(cx, &mut tests, &caps, &globals, true);
        if !tests.text().trim().is_empty() {
            out.line(crate::sem::gen::TEST_GUARD);
            out.blank();
            out.line(tests.text().trim_end());
            out.blank();
            out.line("#endif");
        }
        keyed_targets(cx, out);
        make_procs(cx, out);
        for d in std::mem::take(&mut tests.diags) {
            out.diag(&d.rel, d.line, d.msg);
        }
    }
}

/// The keyed relations the CAPABILITIES lists declare (`ref_one(nameof(v), /type, by = nameof(id))`): the type the holder finds and the id var both
/// sides carry. A type is a keyed target whichever side builds its table first, so the table of a target built before any holder's (a door
/// placed before its button) must already know its key: the engine reads this list once, ahead of the first table.
fn keyed_targets(cx: &GenCx, out: &mut GenOut) {
    use std::cell::RefCell;
    let rows: RefCell<BTreeMap<String, (String, bool)>> = RefCell::new(BTreeMap::new());
    for m in cx.markers("CAPABILITIES") {
        let test_only = crate::sem::gen::test_only(&m.rel);
        for a in m.args.iter().skip(1) {
            for name in ["ref_one", "ref_many"] {
                rewrite_calls(a, name, &|args| {
                    let ty = args.get(1).filter(|t| split_opt(t).is_none()).cloned();
                    let by = args.iter().filter_map(|x| split_opt(x)).find(|(k, _)| k == "by").map(|(_, v)| v);
                    if let (Some(ty), Some(by)) = (ty, by) {
                        let var = by.trim().strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')).unwrap_or(by.trim()).trim().to_string();
                        rows.borrow_mut().insert(ty.trim().to_string(), (var, test_only));
                    }
                    String::new()
                });
            }
        }
    }
    let rows = rows.into_inner();
    out.doc("declared_keyed_targets(): target type -> the id var a keyed relation (by =) matches it on, read once before the first ownership table.");
    out.line("/proc/declared_keyed_targets()");
    out.line("	. = list()");
    for (ty, (var, test_only)) in &rows {
        if *test_only {
            out.line(crate::sem::gen::TEST_GUARD);
        }
        out.line(format!("	.[{}] = {}", ty, quote(var)));
        if *test_only {
            out.line("#endif");
        }
    }
    out.blank();
}

/// The declarations of the files in one half of the tree: the engine and the game (`test_only` false), or the test fixtures.
fn section(cx: &GenCx, out: &mut GenOut, caps: &[Cap], globals: &BTreeSet<String>, test_only: bool) {
    let in_half = |rel: &str| crate::sem::gen::test_only(&rel) == test_only;
        // Capabilities: the datum's param vars, the constructor, the registration row.
        for cap in caps.iter().filter(|c| in_half(&c.rel)) {
            out.doc(format!("{}({}, {}) at {}:{}", if cap.is_def { "CAPABILITY_DEF" } else { "CAPABILITY_TYPE" }, cap.name, cap.id, cap.rel, cap.line));
            if !cap.params.is_empty() {
                out.line(&cap.ty);
                for (p, d) in &cap.params {
                    if let Some(d) = d {
                        out.line(format!("\tvar/{} = {}", p, one_line(d)));
                    }
                }
            }
            let names: Vec<String> = cap.params.iter().map(|(p, _)| p.clone()).collect();
            out.line(format!("/proc/{}({})", cap.name, names.join(", ")));
            out.line(format!("\tRETURN_TYPE({})", cap.ty));
            out.line(format!("\treturn cap_construct({}, {}, list({}), {})", cap.id, cap.ty, names.join(", "), quote(&names.join(", "))));
            out.line(format!("/datum/capdef_decl/c_{}/spec()", cap.name));
            out.line(format!("\treturn list({}, {}, {}, {}, {}, {})", cap.id, cap.ty, key_expr(&cap.key), cap.stacks.clone().unwrap_or_else(|| "STACK".to_string()), quote(cap.prefix.as_deref().unwrap_or(&cap.name)), quote(&names.join(", "))));
            out.blank();
        }
        // State keys.
        let by_id: BTreeMap<&String, &String> = caps.iter().map(|c| (&c.id, &c.name)).collect();
        for m in cx.markers("cap_keys").filter(|m| in_half(&m.rel)) {
            let Some(cap_id) = m.args.first() else { continue };
            let cap_name = by_id.get(cap_id).map(|n| n.to_string()).unwrap_or_else(|| cap_id.trim_start_matches("CAP_").to_lowercase());
            let mut rows = Vec::new();
            let mut accessors = Vec::new();
            for a in m.args.iter().skip(1) {
                if let Some((k, v)) = split_opt(a) {
                    rows.push(format!("{} = {}", k, one_line(&v)));
                    accessors.push(k);
                }
            }
            out.doc(format!("cap_keys({}) at {}:{}", cap_id, m.rel, m.line));
            out.line(format!("/datum/cap_keys_decl/k_{}/spec()", cap_name));
            out.line(format!("\treturn list({}, list({}))", cap_id, rows.join(", ")));
            for k in accessors {
                out.line(format!("/// The state key {} of {}, read on a holder (a granted capability with several selectors names the selector).", k, cap_name));
                out.line(format!("/proc/{}_{}(datum/holder, selector)", cap_name, k.to_lowercase()));
                out.line(format!("\treturn cap_key_get(holder, {}_{}, selector)", up(&cap_name), up(&k)));
            }
            out.blank();
        }
        // Stages, sources, graphs.
        for m in cx.markers("STAGE_DEF").filter(|m| in_half(&m.rel)) {
            if let (Some(g), Some(n)) = (m.args.first(), m.args.get(1)) {
                out.line(format!("/datum/stage_def/{}_{}/spec()", g, n));
                out.line(format!("\treturn list(STAGE_{}_{}, {}, {})", up(g), up(n), quote(g), quote(n)));
            }
        }
        for m in cx.markers("SOURCE_DEF").filter(|m| in_half(&m.rel)) {
            if let Some(n) = m.args.first() {
                out.line(format!("/datum/source_def/{}/spec()", n));
                out.line(format!("\treturn list(SRC_{}, {})", up(n), quote(n)));
            }
        }
        for m in cx.markers("STATE_GRAPH").filter(|m| in_half(&m.rel)) {
            let Some(g) = m.args.first() else { continue };
            let entries: Vec<String> = m.args.iter().skip(1).map(|a| qualify_globals(&one_line(a), globals)).collect();
            out.doc(format!("STATE_GRAPH({}) at {}:{}", g, m.rel, m.line));
            out.line(format!("/datum/graph_decl/g_{}/spec()", g.to_lowercase()));
            out.line(format!("\treturn list({}, {})", g, entries.join(", ")));
        }
        out.blank();
        // CAPABILITIES(T, entries...): the type's declared_entries().
        let mut lists: Vec<&Marker> = cx.markers("CAPABILITIES").filter(|m| in_half(&m.rel)).collect();
        lists.sort_by(|a, b| (a.args.first(), &a.rel, a.line).cmp(&(b.args.first(), &b.rel, b.line)));
        for w in lists.windows(2) {
            if w[0].args.first() == w[1].args.first() {
                out.diag(&w[1].rel, w[1].line, format!("a second CAPABILITIES list for {} (the first is at {}:{}): one composition root per type", w[1].args.first().cloned().unwrap_or_default(), w[0].rel, w[0].line));
            }
        }
        for m in lists {
            let Some(ty) = m.args.first() else {
                out.diag(&m.rel, m.line, "CAPABILITIES(T, entries...) needs a type");
                continue;
            };
            let offsets = arg_offsets(&m.body, &m.args);
            out.doc(format!("CAPABILITIES({}) at {}:{}", ty, m.rel, m.line));
            out.line(format!("{}/declared_entries(list/into)", ty));
            out.line("\t..(into)");
            out.line(format!("\tinto += entry_block({}, {}, {})", quote(&m.rel), m.line, ty));
            // section(name, "doc") opens a section: the entries after it, to the next section or the block's end, are the type's own
            // entries like any other, and each carries the section's name with its file:line (Explain Type and Interaction print both).
            let mut current: Option<(String, u32, usize)> = None; // name, line, entries so far
            let mut seen_sections: BTreeMap<String, u32> = BTreeMap::new();
            let close_section = |cur: &Option<(String, u32, usize)>, out: &mut GenOut| {
                if let Some((name, line, 0)) = cur {
                    out.diag(&m.rel, *line, format!("section({}) of {} has no entries", name, ty));
                }
            };
            for (i, a) in m.args.iter().enumerate().skip(1) {
                if a.is_empty() {
                    continue;
                }
                let line = m.line_at(offsets[i]);
                if let Some(parts) = section_parts(a) {
                    close_section(&current, out);
                    let name = parts.first().map(|p| p.trim().to_string()).unwrap_or_default();
                    let ok_name = !name.is_empty() && name.chars().all(|c| c.is_alphanumeric() || c == '_') && !name.starts_with(|c: char| c.is_ascii_digit());
                    let ok_doc = parts.len() <= 2 && parts.get(1).map(|d| d.trim().starts_with('"')).unwrap_or(true);
                    if !(ok_name && ok_doc) {
                        out.diag(&m.rel, line, format!("`{}`: a section header is section(name) or section(name, \"doc\") with name an identifier", one_line(a)));
                        current = None;
                        continue;
                    }
                    if let Some(first) = seen_sections.insert(name.clone(), line) {
                        out.diag(&m.rel, line, format!("section({}) of {} is declared twice (first at line {})", name, ty, first));
                    }
                    let doc = parts.get(1).map(|d| format!(": {}", one_line(d.trim().trim_matches('"')))).unwrap_or_default();
                    out.line(format!("\t// section {}{}", name, doc));
                    current = Some((name, line, 0));
                    continue;
                }
                match current.as_mut() {
                    Some((name, _, n)) => {
                        *n += 1;
                        out.line(format!("\tinto += entry_line({}, {})", line, quote(name)));
                    }
                    None => out.line(format!("\tinto += entry_line({})", line)),
                }
                out.line(format!("\tinto += list({})", entry_text(a, caps, globals)));
            }
            close_section(&current, out);
            out.blank();
        }
        lifeform_type_extras(cx, out, &in_half);
}

/// The first argument of a `nameof(x)` text: `x`.
fn nameof_inner(arg: &str) -> Option<String> {
    let t = arg.trim();
    t.strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')).map(|s| s.trim().to_string())
}

/// Whether a type path names an atom (its instances initialize through Initialize(), not New()).
fn is_atom_path(ty: &str) -> bool {
    ["/atom", "/obj", "/mob", "/turf", "/area"].iter().any(|p| ty == *p || ty.starts_with(&format!("{}/", p)))
}

/// The calls a block names, by constructor name (a quick scan: a name followed by `(`, outside strings).
fn block_calls(args: &[String], name: &str) -> Vec<Vec<String>> {
    use std::cell::RefCell;
    let found: RefCell<Vec<Vec<String>>> = RefCell::new(Vec::new());
    for a in args.iter().skip(1) {
        rewrite_calls(a, name, &|inner| {
            found.borrow_mut().push(inner.to_vec());
            String::new()
        });
    }
    found.into_inner()
}

/// The lifecycle forms (code/engine/lifeforms/) a type's block needs the generator for:
/// - a non-atom type whose block names a form, or an owns_one/owns_many with starts =, gets `lifeform_declared = TRUE`, so /datum/New() runs it;
/// - a type whose block names click_on(), drag_onto(), drag_over(), hover() or tooltip() gets the native override that reads `usr` (the engine's,
///   here) and hands the engine the actor: Click(), MouseDrop(), MouseDrag(), MouseEntered()/MouseExited().
fn lifeform_type_extras(cx: &GenCx, out: &mut GenOut, in_half: &dyn Fn(&str) -> bool) {
    const FORMS: &[&str] = &["rolls", "param", "built_from", "registry", "radio_listen", "per_type", "initial_contents", "knows", "starts_as", "derives", "lives_while", "on_ending"];
    let mut lists: Vec<&Marker> = cx.markers("CAPABILITIES").filter(|m| in_half(&m.rel)).collect();
    lists.sort_by(|a, b| (a.args.first(), &a.rel, a.line).cmp(&(b.args.first(), &b.rel, b.line)));
    for m in lists {
        let Some(ty) = m.args.first() else { continue };
        let ty = ty.trim();
        if !is_atom_path(ty) && ty.starts_with("/datum") {
            let mut declared = FORMS.iter().any(|f| !block_calls(&m.args, f).is_empty());
            for owns in ["owns_one", "owns_many"] {
                if block_calls(&m.args, owns).iter().any(|a| a.iter().any(|x| split_opt(x).map(|(k, _)| k == "starts").unwrap_or(false))) {
                    declared = true;
                }
            }
            if declared {
                out.doc(format!("{} declares a lifecycle form ({}:{}): /datum/New() runs it.", ty, m.rel, m.line));
                out.line(ty);
                out.line("\tlifeform_declared = TRUE");
            }
        }
        if !is_atom_path(ty) {
            continue;
        }
        let click = !block_calls(&m.args, "click_on").is_empty();
        let drag = !block_calls(&m.args, "drag_onto").is_empty();
        let drag_over = !block_calls(&m.args, "drag_over").is_empty();
        let hover = !block_calls(&m.args, "hover").is_empty();
        let tip = !block_calls(&m.args, "tooltip").is_empty();
        if click {
            out.doc(format!("click_on() of {} ({}:{}): the native click hands the engine its actor.", ty, m.rel, m.line));
            out.line(format!("{}/Click(location, control, params)", ty));
            out.line("\tif(input_dispatch(src, usr, INPUT_CLICK_ON, params, null, FALSE, list(\"location\" = location, \"control\" = control, \"params\" = params)))");
            out.line("\t\treturn");
            out.line("\t. = ..()");
            out.line("\tinput_fell(src)");
        }
        if drag {
            out.doc(format!("drag_onto() of {} ({}:{}): the native drop hands the engine its actor.", ty, m.rel, m.line));
            out.line(format!("{}/MouseDrop(over_object, src_location, over_location, src_control, over_control, params)", ty));
            out.line("\tif(input_dispatch(src, usr, INPUT_DRAG_ONTO, params, over_object, FALSE, list(\"over_object\" = over_object, \"src_location\" = src_location, \"over_location\" = over_location, \"src_control\" = src_control, \"over_control\" = over_control, \"params\" = params)))");
            out.line("\t\treturn");
            out.line("\t. = ..()");
            out.line("\tinput_fell(src)");
        }
        if drag_over {
            out.doc(format!("drag_over() of {} ({}:{}): the native drag hands the engine its actor.", ty, m.rel, m.line));
            out.line(format!("{}/MouseDrag(over_object, src_location, over_location, src_control, over_control, params)", ty));
            out.line("\tif(input_dispatch(src, usr, INPUT_DRAG_OVER, params, over_object, FALSE, list(\"over_object\" = over_object, \"src_location\" = src_location, \"over_location\" = over_location, \"src_control\" = src_control, \"over_control\" = over_control, \"params\" = params)))");
            out.line("\t\treturn");
            out.line("\t. = ..()");
            out.line("\tinput_fell(src)");
        }
        if hover || tip {
            out.doc(format!("hover()/tooltip() of {} ({}:{}): the native mouse-over hands the engine its actor.", ty, m.rel, m.line));
            for (native, entered) in [("MouseEntered", "TRUE"), ("MouseExited", "FALSE")] {
                out.line(format!("{}/{}(location, control, params)", ty, native));
                if tip {
                    out.line(format!("\tinput_tooltip(src, usr, {}, params)", entered));
                }
                if hover {
                    out.line(format!("\tinput_dispatch(src, usr, INPUT_HOVER, params, null, {}, list(\"location\" = location, \"control\" = control, \"params\" = params))", entered));
                }
                out.line("\t. = ..()");
                out.line("\tinput_fell(src)");
            }
        }
        if click || drag || drag_over || hover || tip {
            out.blank();
        }
    }
}

/// make(type, at =, by =, parts =, name = value...) and make_args(name = value...): their named parameters are every name a param() declares,
/// so DM checks a call's names; the bodies are the engine's (code/engine/lifeforms/params.dm). `analyze` checks each call against the made type.
fn make_procs(cx: &GenCx, out: &mut GenOut) {
    const RESERVED: &[&str] = &["type", "at", "by", "parts", "given", "src", "usr", "args"];
    let mut names: BTreeSet<String> = BTreeSet::new();
    for m in cx.markers("CAPABILITIES") {
        for call in block_calls(&m.args, "param") {
            let Some(first) = call.first() else { continue };
            let Some(name) = nameof_inner(first) else {
                out.diag(&m.rel, m.line, format!("param({}): the var is nameof(var)", first));
                continue;
            };
            if RESERVED.contains(&name.as_str()) {
                out.diag(&m.rel, m.line, format!("param(nameof({})): `{}` is one of make()'s own parameters; rename the var", name, name));
                continue;
            }
            names.insert(name);
        }
    }
    let params: Vec<String> = names.iter().map(|n| format!("{} = MAKE_UNSET", n)).collect();
    let tail = if params.is_empty() { String::new() } else { format!(", {}", params.join(", ")) };
    out.doc("make(type, at =, by =, parts =, name = value...): a new instance with its params set before init (code/engine/lifeforms/params.dm).");
    out.line(format!("/proc/make(type, at = null, by = null, parts = null{})", tail));
    out.line("\tvar/list/given = list()");
    for n in &names {
        out.line(format!("\tif({} != MAKE_UNSET)", n));
        out.line(format!("\t\tgiven[{}] = {}", quote(n), n));
    }
    out.line("\treturn make_build(type, at, by, parts, given)");
    out.doc("make_args(name = value...): the params of what a starts = makes (OWNER is the holder).");
    out.line(format!("/proc/make_args({})", params.join(", ")));
    out.line("\tvar/list/given = list()");
    for n in &names {
        out.line(format!("\tif({} != MAKE_UNSET)", n));
        out.line(format!("\t\tgiven[{}] = {}", quote(n), n));
    }
    out.line("\treturn make_args_build(given)");
    out.blank();
}

/// The arguments of a `section(...)` header entry, or None when the entry is not one.
fn section_parts(entry: &str) -> Option<Vec<String>> {
    let t = entry.trim();
    let rest = t.strip_prefix("section")?.trim_start();
    if !rest.starts_with('(') {
        return None;
    }
    let open = t.len() - rest.len();
    let close = matching_paren(t, open)?;
    if !t[close + 1..].trim().is_empty() {
        return None;
    }
    Some(split_args(&t[open + 1..close]))
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Ids));
    reg.push(Box::new(Declare));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sem::gen::render;
    use crate::tree::{SourceFile, Tree};
    use std::path::Path;

    fn gen(files: Vec<(&str, &str)>) -> (String, String, Vec<String>) {
        let tree = Tree::from_files(files.into_iter().map(|(r, t)| SourceFile::from_text(r, t)).collect());
        let cx = GenCx::new(&tree, Path::new("."));
        let (ids, d1) = render(&Ids, &cx);
        let (decl, d2) = render(&Declare, &cx);
        let diags = d1.into_iter().chain(d2).map(|d| d.msg).collect();
        (ids, decl, diags)
    }

    const SRC: &str = r#"
#define CAP_HAND 5
STAT(/obj/machinery, operable, ALL)
STAT(/mob/living, stun, MAX, units = LIFE_CYCLE)
SOURCE_DEF(vv)
STAGE_DEF(door, frame)
STATE_GRAPH(GRAPH_DOOR, start(STAGE_DOOR_FRAME))
CAPABILITY_TYPE(widget, CAP_WIDGET, /datum/capability/widget, key = label, stacks = BEST(power), label = "main", power = 1)
CAPABILITY_DEF(cover, CAP_HAND)
cap_keys(CAP_WIDGET, ARMED = null, LIT = null)
CAPABILITIES(/obj/thing, \
	widget("a", power = 2), \
	link(/obj/thing::partner, /obj/thing::partner), \
	configure(CAP_WIDGET, "a", power = 9), \
	when(nameof(armed), contributes(STAT_OPERABLE, FALSE)))
"#;

    #[test]
    fn ids_come_from_the_markers_and_leave_hand_defines_alone() {
        let (ids, _, diags) = gen(vec![("code/a.dm", SRC)]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(ids.contains("#define STAT_OPERABLE 100001"), "{}", ids);
        assert!(ids.contains("#define STAT_STUN 100002"), "{}", ids);
        assert!(ids.contains("#define STATUS_STUN STAT_STUN"));
        assert!(ids.contains("#define STAT_STUN_IMMUNE STAT_IMMUNE(STAT_STUN)"));
        assert!(ids.contains("#define CAP_WIDGET 300"));
        assert!(!ids.contains("#define CAP_HAND"), "a hand-written define is not repeated");
        assert!(ids.contains("#define SRC_VV 1"));
        assert!(ids.contains("#define STAGE_DOOR_FRAME 1"));
        assert!(ids.contains("#define GRAPH_DOOR 1"));
        assert!(ids.contains("#define WIDGET_ARMED CAPKEY_ID(CAP_WIDGET, 1)"));
        assert!(ids.contains("#define WIDGET_LIT CAPKEY_ID(CAP_WIDGET, 2)"));
    }

    #[test]
    fn lifecycle_forms_get_make_a_datum_flag_and_native_input() {
        let src = "CAPABILITIES(/datum/req, \\\n\tparam(nameof(charge), int()), \\\n\trolls(nameof(x), range_of(1, 2)))\nCAPABILITIES(/obj/screen_thing, \\\n\tclick_on(PROC_REF(clicked)), \\\n\tdrag_over(PROC_REF(dragged)), \\\n\ttooltip(PROC_REF(tip)))\n";
        let (_, decl, diags) = gen(vec![("code/a.dm", src)]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(decl.contains("/proc/make(type, at = null, by = null, parts = null, charge = MAKE_UNSET)"), "{}", decl);
        assert!(decl.contains("/proc/make_args(charge = MAKE_UNSET)"), "{}", decl);
        assert!(decl.contains("/datum/req\n\tlifeform_declared = TRUE"), "{}", decl);
        assert!(decl.contains("/obj/screen_thing/Click(location, control, params)\n\tif(input_dispatch(src, usr, INPUT_CLICK_ON, params, null, FALSE, list("), "{}", decl);
        assert!(decl.contains("/obj/screen_thing/MouseEntered(location, control, params)\n\tinput_tooltip(src, usr, TRUE, params)"), "{}", decl);
        assert!(decl.contains("/obj/screen_thing/MouseDrag(over_object, src_location, over_location, src_control, over_control, params)\n\tif(input_dispatch(src, usr, INPUT_DRAG_OVER, params, over_object, FALSE, list("), "{}", decl);
        assert!(!decl.contains("/obj/screen_thing\n\tlifeform_declared"), "an atom runs its forms from Initialize()");
    }

    #[test]
    fn capabilities_get_a_constructor_a_row_and_param_vars() {
        let (_, decl, diags) = gen(vec![("code/a.dm", SRC)]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(decl.contains("/datum/capability/widget\n\tvar/label = \"main\"\n\tvar/power = 1\n"), "{}", decl);
        assert!(decl.contains("/proc/widget(label, power)"));
        assert!(decl.contains("return cap_construct(CAP_WIDGET, /datum/capability/widget, list(label, power), \"label, power\")"));
        assert!(decl.contains("return list(CAP_WIDGET, /datum/capability/widget, \"label\", BEST(power), \"widget\", \"label, power\")"));
        assert!(decl.contains("/datum/capdef_decl/c_cover/spec()"));
        assert!(decl.contains("/datum/capability/def/cover"), "a DEF's datum type is /datum/capability/def/<name>");
    }

    #[test]
    fn a_capabilities_list_becomes_declared_entries_with_a_line_per_entry() {
        let (_, decl, _) = gen(vec![("code/a.dm", SRC)]);
        assert!(decl.contains("/obj/thing/declared_entries(list/into)\n\t..(into)\n\tinto += entry_block(\"code/a.dm\", 11, /obj/thing)"), "{}", decl);
        assert!(decl.contains("into += entry_line(12)\n\tinto += list(global.widget(\"a\", power = 2))"), "{}", decl);
        assert!(decl.contains("entry_link(\"/obj/thing::partner\", \"/obj/thing::partner\")"), "link is rewritten: {}", decl);
        assert!(decl.contains("configure(global.widget(\"a\", power = 9))"), "configure(CAP_X, ...) is rewritten to the constructor: {}", decl);
        assert!(decl.contains("when(nameof(armed), contributes(STAT_OPERABLE, FALSE))"));
        assert!(decl.contains("into += entry_line(13)
	into += list(entry_link("), "every entry keeps its own line: {}", decl);
    }

    #[test]
    fn the_block_form_generates_what_the_legacy_list_does() {
        let bs = char::from(92u8);
        let legacy = format!("CAPABILITIES(/obj/thing, {bs}
	wall(1, 2), {bs}
	link(/obj/thing::partner, /obj/thing::partner), {bs}
	on_change(nameof(terminal.charge), ANY,
		then(PROC_REF(x))))
");
        let block = "CAPABILITIES(/obj/thing)
	wall(1, 2)
	links(/obj/thing::partner, /obj/thing::partner)
	on_change(nameof(terminal.charge), ANY,
		then(PROC_REF(x)))
";
        let (_, a, da) = gen(vec![("code/a.dm", legacy.as_str())]);
        let (_, b, db) = gen(vec![("code/a.dm", block)]);
        assert!(da.is_empty() && db.is_empty(), "{:?} {:?}", da, db);
        assert_eq!(a, b, "the same entries, the same lines");
        assert!(b.contains("entry_link(\"/obj/thing::partner\", \"/obj/thing::partner\")"), "{}", b);
        assert!(b.contains("on_change(\"terminal.charge\", ANY"), "{}", b);
    }

    #[test]
    fn one_extend_carries_every_part_of_its_key() {
        let (_, decl, diags) = gen(vec![("code/a.dm", "CAPABILITIES(/obj/thing)
	extend(\"construction.undo:x\", when(COVER_OPEN), priority(above(\"panel.open\")), needs(req(PROC_REF(y))))
")]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(decl.contains("extend(\"construction.undo:x\", when(COVER_OPEN), priority(above(\"panel.open\")), needs(req(PROC_REF(y))))"), "{}", decl);
        assert_eq!(decl.matches("extend(").count(), 1, "one entry for the key: {}", decl);
    }

    #[test]
    fn a_second_capabilities_list_for_a_type_is_reported() {
        let (_, _, diags) = gen(vec![("code/a.dm", "CAPABILITIES(/obj/x, a())\nCAPABILITIES(/obj/x, b())\n")]);
        assert_eq!(diags.len(), 1, "{:?}", diags);
        assert!(diags[0].contains("second CAPABILITIES list for /obj/x"), "{}", diags[0]);
    }

    #[test]
    fn adjusts_and_on_change_paths_become_text() {
        let (_, decl, diags) = gen(vec![("code/a.dm", "CAPABILITIES(/obj/thing, \
	extend(/datum/act/hit, adjusts(packet.amount, scale = 0.5)), \
	on_change(nameof(terminal.charge), ANY, then(PROC_REF(x))), \
	on_change(nameof(on), ENTER, then(PROC_REF(y))))
")]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(decl.contains("adjusts(\"packet.amount\", scale = 0.5)"), "{}", decl);
        assert!(decl.contains("on_change(\"terminal.charge\", ANY"), "{}", decl);
        assert!(decl.contains("on_change(nameof(on), ENTER"), "a plain nameof stays: {}", decl);
    }

    #[test]
    fn a_section_groups_the_entries_after_it_and_names_them() {
        let (_, decl, diags) = gen(vec![("code/a.dm", "CAPABILITIES(/obj/thing)
	wall(1, 2)

	section(controls, \"The window and its buttons.\")
	interface(\"Thing\")
	op(\"press\", ui_act(), then(PROC_REF(pressed)))
	section(rules)
	extend(\"press\", needs(req_operable()))
")]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(decl.contains("\tinto += entry_line(2)\n\tinto += list(wall(1, 2))"), "an entry before any section has none: {}", decl);
        assert!(decl.contains("\t// section controls: The window and its buttons.\n\tinto += entry_line(5, \"controls\")\n\tinto += list(interface(\"Thing\"))"), "{}", decl);
        assert!(decl.contains("into += entry_line(6, \"controls\")\n\tinto += list(op(\"press\", ui_act(), then(PROC_REF(pressed))))"), "PROC_REF stays: the entries are the type's own: {}", decl);
        assert!(decl.contains("\t// section rules\n\tinto += entry_line(8, \"rules\")"), "{}", decl);
        assert!(!decl.contains("section("), "the header is no entry: {}", decl);
    }

    #[test]
    fn bad_sections_are_reported() {
        let (_, _, diags) = gen(vec![("code/a.dm", "CAPABILITIES(/obj/thing)
	section(a)
	section(\"b\")
	wall(1)
	section(c, 12)
	section(d)
	wall(2)
	section(d)
	wall(3)
")]);
        let all = diags.join("\n");
        assert!(all.contains("section(a) of /obj/thing has no entries"), "{}", all);
        assert!(all.contains("`section(\"b\")`: a section header is"), "{}", all);
        assert!(all.contains("`section(c, 12)`"), "{}", all);
        assert!(all.contains("section(d) of /obj/thing is declared twice"), "{}", all);
    }

    #[test]
    fn option_splitting_and_key_forms() {
        assert_eq!(split_opt("key = name"), Some(("key".into(), "name".into())));
        assert_eq!(split_opt("a == b"), None);
        assert_eq!(key_expr(&Some("name".into())), "\"name\"");
        assert_eq!(key_expr(&Some("NONE".into())), "NONE");
        assert_eq!(key_expr(&None), "NONE");
    }
}
