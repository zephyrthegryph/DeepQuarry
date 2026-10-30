//! Whole unchanged declaration marker/emitter policy shared by legacy and native.
//! Raw declaration marker projection only: no Decls/Sem/ObjectTree or DM parser.
use crate::{
    declare_ids_policy::{split_opt, Cap},
    raw_marker_policy::{matching_paren, split_args},
    sparse_slots_policy::Output,
};
use std::collections::{BTreeMap, BTreeSet};
pub const MARKERS: &[&str] = &[
    "CAPABILITIES",
    "CAPABILITY_TYPE",
    "CAPABILITY_DEF",
    "cap_keys",
    "STAGE_DEF",
    "SOURCE_DEF",
    "STATE_GRAPH",
    "STATIC_ENTRY",
];
pub struct Marker<'a> {
    pub name: &'a str,
    pub rel: &'a str,
    pub line: u32,
    pub body: &'a str,
    pub args: &'a [String],
    pub body_offset: usize,
    pub line_starts: &'a [u32],
}
impl Marker<'_> {
    pub fn line_at(&self, body_off: usize) -> u32 {
        let abs = (self.body_offset + body_off) as u32;
        match self.line_starts.binary_search(&abs) {
            Ok(i) => i as u32 + 1,
            Err(i) => i as u32,
        }
    }
}
pub struct Input<'a> {
    pub markers: &'a [Marker<'a>],
    pub engine_sources: &'a [(&'a str, &'a str)],
    pub(crate) poll: Option<&'a dyn Fn() -> bool>,
    pub(crate) budget: Option<std::sync::Arc<crate::captured_generator_budget::Budget>>,
}
impl<'a> Input<'a> {
    fn markers<'b>(&'b self, name: &'b str) -> impl Iterator<Item = &'b Marker<'a>> + 'b {
        self.markers
            .iter()
            .take_while(|_| self.poll.map_or(true, |f| f()))
            .filter(move |m| m.name == name)
    }
    fn output(&self) -> Output {
        match &self.budget {
            Some(b) => Output::captured(b.clone()),
            None => Output::default(),
        }
    }
}
pub(crate) fn up(s: &str) -> String {
    s.to_uppercase()
}

/// `name = value` at the top level of an argument (an identifier, then `=` that is not `==`).
/// Collapses a multi-line expression onto one line (comments are already blanked in marker text).
pub(crate) fn one_line(s: &str) -> String {
    // A marker the preprocessor sees continues its lines with a trailing backslash: that is not part of the expression.
    s.replace("\\\r\n", " ")
        .replace("\\\n", " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

pub(crate) fn quote(s: &str) -> String {
    format!("\"{}\"", s.replace('\\', "\\\\").replace('"', "\\\""))
}

/// The key option as a DM expression: a bare identifier names a param (a text), NONE stays NONE.
pub(crate) fn key_expr(key: &Option<String>) -> String {
    match key {
        None => "NONE".to_string(),
        Some(k) if k == "NONE" => "NONE".to_string(),
        Some(k) if k.starts_with('"') => k.clone(),
        Some(k) if k.chars().all(|c| c.is_alphanumeric() || c == '_') => quote(k),
        Some(k) => k.clone(),
    }
}

fn capabilities(cx: &Input<'_>, out: &mut Output) -> Vec<Cap> {
    let mut caps = Vec::new();
    let mut diagnostics = cx.output();
    for m in cx
        .markers
        .iter()
        .take_while(|_| cx.poll.map_or(true, |f| f()))
        .filter(|m| m.name == "CAPABILITY_TYPE" || m.name == "CAPABILITY_DEF")
    {
        if let Some(cap) = crate::declare_ids_policy::parse_capability(
            &m.name,
            &m.rel,
            m.line,
            &m.args,
            &mut diagnostics,
        ) {
            caps.push(cap);
        }
    }
    for d in diagnostics.diags {
        out.diag(&d.rel, d.line, d.msg);
    }
    caps.sort_by(|a, b| a.name.cmp(&b.name));
    caps
}

/// Replaces every call `name(...)` (not a member or a longer name) in `text` by `f(args)`.
pub(crate) fn rewrite_calls(text: &str, name: &str, f: &dyn Fn(&[String]) -> String) -> String {
    let mut out = String::new();
    let b = text.as_bytes();
    let mut i = 0;
    while i < text.len() {
        let rest = &text[i..];
        if rest.starts_with(name) && rest[name.len()..].trim_start().starts_with('(') {
            let before_ok = i == 0
                || !(b[i - 1].is_ascii_alphanumeric()
                    || b[i - 1] == b'_'
                    || b[i - 1] == b'.'
                    || b[i - 1] == b'/');
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
pub(crate) fn global_constructors(cx: &Input<'_>, caps: &[Cap]) -> BTreeSet<String> {
    let mut set: BTreeSet<String> = caps.iter().map(|c| c.name.clone()).collect();
    set.extend(static_kinds(cx));
    // `every` keeps its legacy body in code/datums/reactions (the system form) and dispatches a capability's every(interval, then(...)) to the engine.
    set.insert("every".to_string());
    for &(rel, text) in cx.engine_sources {
        if cx.poll.is_some_and(|f| !f()) {
            break;
        }
        if !rel.starts_with("code/engine/") {
            continue;
        }
        for line in text.lines() {
            if let Some(rest) = line.strip_prefix("/proc/") {
                let name: String = rest
                    .chars()
                    .take_while(|c| c.is_alphanumeric() || *c == '_')
                    .collect();
                if !name.is_empty() && rest[name.len()..].trim_start().starts_with('(') {
                    set.insert(name);
                }
            }
        }
    }
    set
}

/// The entry kinds that are read without an instance: `STATIC_ENTRY(loot)` in DM names a constructor `loot(...)` whose entries a
/// CAPABILITIES block may carry, but which are not part of the type's instance table (the library reads them at world setup,
/// before the first map load, from `declared_static_blocks()`).
pub(crate) fn static_kinds(cx: &Input<'_>) -> BTreeSet<String> {
    cx.markers("STATIC_ENTRY")
        .filter_map(|m| m.args.first().map(|a| a.trim().to_string()))
        .filter(|a| !a.is_empty())
        .collect()
}

/// The name of the call a text opens with (`loot(...)` is `loot`), or None.
pub(crate) fn leading_call(t: &str) -> Option<&str> {
    let t = t.trim_start();
    let end = t.find(|c: char| !(c.is_alphanumeric() || c == '_'))?;
    if end == 0 || !t[end..].trim_start().starts_with('(') {
        return None;
    }
    Some(&t[..end])
}

/// Whether a CAPABILITIES entry is of a static kind: `loot(...)`, or `configure(loot(...))` changing what a supertype declared.
pub(crate) fn is_static_entry(raw: &str, kinds: &BTreeSet<String>) -> bool {
    if kinds.is_empty() {
        return false;
    }
    let t = one_line(raw);
    match leading_call(&t) {
        Some("configure") => {
            let open = t.find('(').unwrap_or(0);
            leading_call(&t[open + 1..])
                .map(|n| kinds.contains(n))
                .unwrap_or(false)
        }
        Some(name) => kinds.contains(name),
        None => false,
    }
}

/// Writes every call of a global constructor in `text` as `global.name(...)` (not a member call, not a longer name, not inside a string).
pub(crate) fn qualify_globals(text: &str, names: &BTreeSet<String>) -> String {
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
            let prev_ok = i == 0
                || !(b[i - 1].is_ascii_alphanumeric()
                    || b[i - 1] == b'_'
                    || b[i - 1] == b'.'
                    || b[i - 1] == b'/');
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
pub(crate) fn entry_text(raw: &str, caps: &[Cap], globals: &BTreeSet<String>) -> String {
    let mut t = one_line(raw);
    // `link` (the legacy spelling) and `links` (the block form: `link` is a BYOND reserved word): both become entry_link() with the ends as text.
    for call in ["link", "links"] {
        t = rewrite_calls(&t, call, &|a| {
            // An end is the text of `/type::var`. A sparse end names no var (links(LINK_END(/mob/living, LK_X), ..., sparse = TRUE)): it is already an
            // expression that gives that text, so it is copied as it is.
            let end = |i: usize| {
                let s = a.get(i).map(|s| s.as_str()).unwrap_or("");
                if s.is_empty() || s.contains("::") {
                    quote(s)
                } else {
                    s.to_string()
                }
            };
            let mut parts = vec![end(0), end(1)];
            parts.extend(a.iter().skip(2).cloned());
            format!("entry_link({})", parts.join(", "))
        });
    }
    // adjusts(packet.amount, ...): the field path is text (DM has no value for `packet.amount` outside the action's own context).
    t = rewrite_calls(&t, "adjusts", &|a| {
        let Some(first) = a.first() else {
            return "adjusts()".to_string();
        };
        let mut parts = vec![if first.starts_with('"') {
            first.clone()
        } else {
            quote(first)
        }];
        parts.extend(a.iter().skip(1).cloned());
        format!("adjusts({})", parts.join(", "))
    });
    // on_change(nameof(terminal.charge), ANY, ...): nameof() of a path gives only the last name, so the whole path is text.
    t = rewrite_calls(&t, "on_change", &|a| {
        let Some(first) = a.first() else {
            return "on_change()".to_string();
        };
        let mut parts: Vec<String> = a.to_vec();
        if let Some(inner) = first
            .strip_prefix("nameof(")
            .and_then(|s| s.strip_suffix(')'))
        {
            if inner.contains('.') {
                parts[0] = quote(inner.trim());
            }
        }
        format!("on_change({})", parts.join(", "))
    });
    t = rewrite_calls(&t, "configure", &|a| {
        let Some(first) = a.first() else {
            return "configure()".to_string();
        };
        match caps.iter().find(|c| &c.id == first) {
            Some(cap) => format!("configure({}({}))", cap.name, a[1..].join(", ")),
            None => format!("configure({})", a.join(", ")),
        }
    });
    qualify_globals(&t, globals)
}

/// Byte offset of each top-level argument of a marker body, in order (the args are `split_args(body)`).
pub(crate) fn arg_offsets(body: &str, args: &[String]) -> Vec<usize> {
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

/// The entries of the static kinds (`STATIC_ENTRY`), by type: the library reads them at world setup without making an instance of the type
/// (a map-time resolver and a loot table belong to a type that is never made). Each row is the block's file, the line of the block, and its
/// static entries with their own lines, in order; a type that declares none has no row.
pub(crate) fn static_blocks(
    cx: &Input<'_>,
    out: &mut Output,
    caps: &[Cap],
    globals: &BTreeSet<String>,
    statics: &BTreeSet<String>,
) {
    out.doc("declared_static_blocks(): type -> list(file, line, entries) for the entries of the static kinds (STATIC_ENTRY), read without an instance.");
    // Rows go into numbered part procs of at most 150 rows (one proc of every row is past DM's proc size limit).
    let mut rows: Vec<Vec<String>> = Vec::new();
    if !statics.is_empty() {
        let mut lists: Vec<&Marker> = cx.markers("CAPABILITIES").collect();
        lists.sort_by(|a, b| {
            (a.args.first(), &a.rel, a.line).cmp(&(b.args.first(), &b.rel, b.line))
        });
        for m in lists {
            let Some(ty) = m.args.first() else { continue };
            let offsets = arg_offsets(&m.body, &m.args);
            let mut parts: Vec<String> = Vec::new();
            for (i, a) in m.args.iter().enumerate().skip(1) {
                if a.is_empty() || !is_static_entry(a, statics) {
                    continue;
                }
                parts.push(format!("entry_line({})", m.line_at(offsets[i])));
                parts.push(entry_text(a, caps, globals));
            }
            if parts.is_empty() {
                continue;
            }
            let test_only = crate::generator_test_scope::test_only(&m.rel);
            let mut row: Vec<String> = Vec::new();
            if test_only {
                row.push(crate::generator_test_scope::TEST_GUARD.to_string());
            }
            row.push(format!("	// CAPABILITIES({}) at {}:{}", ty, m.rel, m.line));
            row.push(format!(
                "	into[{}] = list({}, {}, list({}))",
                ty.trim(),
                quote(&m.rel),
                m.line,
                parts.join(", ")
            ));
            if test_only {
                row.push("#endif".to_string());
            }
            rows.push(row);
        }
    }
    let chunks: Vec<&[Vec<String>]> = rows.chunks(150).collect();
    out.line("/proc/declared_static_blocks()");
    out.line("	. = list()");
    for i in 0..chunks.len() {
        out.line_fmt(format_args!("	declared_static_blocks_part{}(.)", i + 1));
    }
    out.blank();
    for (i, chunk) in chunks.iter().enumerate() {
        out.line_fmt(format_args!(
            "/proc/declared_static_blocks_part{}(list/into)",
            i + 1
        ));
        for row in chunk.iter() {
            for l in row {
                out.line(l.clone());
            }
        }
        out.blank();
    }
}

/// The keyed relations the CAPABILITIES lists declare (`ref_one(nameof(v), /type, by = nameof(id))`): the type the holder finds and the id var both
/// sides carry. A type is a keyed target whichever side builds its table first, so the table of a target built before any holder's (a door
/// placed before its button) must already know its key: the engine reads this list once, ahead of the first table.
pub(crate) fn keyed_targets(cx: &Input<'_>, out: &mut Output) {
    use std::cell::RefCell;
    let rows: RefCell<BTreeMap<String, (String, bool)>> = RefCell::new(BTreeMap::new());
    for m in cx.markers("CAPABILITIES") {
        let test_only = crate::generator_test_scope::test_only(&m.rel);
        for a in m.args.iter().skip(1) {
            for name in ["ref_one", "ref_many"] {
                rewrite_calls(a, name, &|args| {
                    let ty = args.get(1).filter(|t| split_opt(t).is_none()).cloned();
                    // `target_key` names the id var of the target when it differs from the holder's `by`.
                    let named = |name: &str| {
                        args.iter()
                            .filter_map(|x| split_opt(x))
                            .find(|(k, _)| k == name)
                            .map(|(_, v)| v)
                    };
                    let by = named("target_key").or_else(|| named("by"));
                    if let (Some(ty), Some(by)) = (ty, by) {
                        let var = by
                            .trim()
                            .strip_prefix("nameof(")
                            .and_then(|s| s.strip_suffix(')'))
                            .unwrap_or(by.trim())
                            .trim();
                        // nameof(/type::var): the target's var, when the holder type has none of that name.
                        let var = var.rsplit("::").next().unwrap_or(var).to_string();
                        rows.borrow_mut()
                            .insert(ty.trim().to_string(), (var, test_only));
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
            out.line(crate::generator_test_scope::TEST_GUARD);
        }
        out.line_fmt(format_args!("	.[{}] = {}", ty, quote(var)));
        if *test_only {
            out.line("#endif");
        }
    }
    out.blank();
}

/// The accessors of the weak references (`ref_one/ref_many(nameof(v), /type, weak = TRUE)`, relations proposal D5): the var holds a handle, so
/// `v()` on the holder type resolves it (weak_get(): the datum or null, or the live members of a many). Generated, so no site writes its own.
pub(crate) fn weak_accessors(cx: &Input<'_>, out: &mut Output) {
    use std::cell::RefCell;
    let rows: RefCell<BTreeMap<(String, String), (Option<String>, bool, bool)>> =
        RefCell::new(BTreeMap::new());
    for m in cx.markers("CAPABILITIES") {
        let Some(holder) = m.args.first().map(|t| t.trim().to_string()) else {
            continue;
        };
        let test_only = crate::generator_test_scope::test_only(&m.rel);
        for a in m.args.iter().skip(1) {
            for name in ["ref_one", "ref_many"] {
                rewrite_calls(a, name, &|args| {
                    let weak = args
                        .iter()
                        .filter_map(|x| split_opt(x))
                        .any(|(k, v)| k == "weak" && v.trim() == "TRUE");
                    if !weak {
                        return String::new();
                    }
                    let Some(var) = args.first().and_then(|v| nameof_inner(v.trim())) else {
                        return String::new();
                    };
                    let ty = args
                        .get(1)
                        .filter(|t| split_opt(t).is_none())
                        .map(|t| t.trim().to_string())
                        .filter(|t| t.starts_with('/'));
                    rows.borrow_mut()
                        .insert((holder.clone(), var), (ty, name == "ref_many", test_only));
                    String::new()
                });
            }
        }
    }
    let rows = rows.into_inner();
    if rows.is_empty() {
        return;
    }
    out.doc("The weak references' accessors (ref_one/ref_many(weak = TRUE)): the var holds a handle; v() reads the live target, or null.");
    for ((holder, var), (ty, many, test_only)) in &rows {
        if *test_only {
            out.line(crate::generator_test_scope::TEST_GUARD);
        }
        match (many, ty) {
            (false, Some(t)) => out.line_fmt(format_args!("{}/proc/{}() as {}", holder, var, t)),
            (true, _) => out.line_fmt(format_args!("{}/proc/{}() as /list", holder, var)),
            _ => out.line_fmt(format_args!("{}/proc/{}()", holder, var)),
        }
        out.line_fmt(format_args!("\treturn weak_get(src, {})", quote(var)));
        if *test_only {
            out.line("#endif");
        }
    }
    out.blank();
}

/// The declarations of the files in one half of the tree: the engine and the game (`test_only` false), or the test fixtures.
pub(crate) fn section(
    cx: &Input<'_>,
    out: &mut Output,
    caps: &[Cap],
    globals: &BTreeSet<String>,
    statics: &BTreeSet<String>,
    test_only: bool,
) {
    let in_half = |rel: &str| crate::generator_test_scope::test_only(&rel) == test_only;
    // Capabilities: the datum's param vars, the constructor, the registration row.
    for cap in caps.iter().filter(|c| in_half(&c.rel)) {
        out.doc_fmt(format_args!(
            "{}({}, {}) at {}:{}",
            if cap.is_def {
                "CAPABILITY_DEF"
            } else {
                "CAPABILITY_TYPE"
            },
            cap.name,
            cap.id,
            cap.rel,
            cap.line
        ));
        if !cap.params.is_empty() {
            out.line(&cap.ty);
            for (p, d) in &cap.params {
                if let Some(d) = d {
                    out.line_fmt(format_args!("\tvar/{} = {}", p, one_line(d)));
                }
            }
        }
        let names: Vec<String> = cap.params.iter().map(|(p, _)| p.clone()).collect();
        out.line_fmt(format_args!("/proc/{}({})", cap.name, names.join(", ")));
        out.line_fmt(format_args!("\tRETURN_TYPE({})", cap.ty));
        out.line_fmt(format_args!(
            "\treturn cap_construct({}, {}, list({}), {})",
            cap.id,
            cap.ty,
            names.join(", "),
            quote(&names.join(", "))
        ));
        out.line_fmt(format_args!("/datum/capdef_decl/c_{}/spec()", cap.name));
        out.line_fmt(format_args!(
            "\treturn list({}, {}, {}, {}, {}, {})",
            cap.id,
            cap.ty,
            key_expr(&cap.key),
            cap.stacks.clone().unwrap_or_else(|| "STACK".to_string()),
            quote(cap.prefix.as_deref().unwrap_or(&cap.name)),
            quote(&names.join(", "))
        ));
        out.blank();
    }
    // State keys.
    let by_id: BTreeMap<&String, &String> = caps.iter().map(|c| (&c.id, &c.name)).collect();
    for m in cx.markers("cap_keys").filter(|m| in_half(&m.rel)) {
        let Some(cap_id) = m.args.first() else {
            continue;
        };
        let cap_name = by_id
            .get(cap_id)
            .map(|n| n.to_string())
            .unwrap_or_else(|| cap_id.trim_start_matches("CAP_").to_lowercase());
        let mut rows = Vec::new();
        let mut accessors = Vec::new();
        for a in m.args.iter().skip(1) {
            if let Some((k, v)) = split_opt(a) {
                rows.push(format!("{} = {}", k, one_line(&v)));
                accessors.push(k);
            }
        }
        out.doc_fmt(format_args!("cap_keys({}) at {}:{}", cap_id, m.rel, m.line));
        out.line_fmt(format_args!("/datum/cap_keys_decl/k_{}/spec()", cap_name));
        out.line_fmt(format_args!(
            "\treturn list({}, list({}))",
            cap_id,
            rows.join(", ")
        ));
        for k in accessors {
            out.line_fmt(format_args!("/// The state key {} of {}, read on a holder (a granted capability with several selectors names the selector).", k, cap_name));
            out.line_fmt(format_args!(
                "/proc/{}_{}(datum/holder, selector)",
                cap_name,
                k.to_lowercase()
            ));
            out.line_fmt(format_args!(
                "\treturn cap_key_get(holder, {}_{}, selector)",
                up(&cap_name),
                up(&k)
            ));
        }
        out.blank();
    }
    // Stages, sources, graphs.
    for m in cx.markers("STAGE_DEF").filter(|m| in_half(&m.rel)) {
        if let (Some(g), Some(n)) = (m.args.first(), m.args.get(1)) {
            out.line_fmt(format_args!("/datum/stage_def/{}_{}/spec()", g, n));
            out.line_fmt(format_args!(
                "\treturn list(STAGE_{}_{}, {}, {})",
                up(g),
                up(n),
                quote(g),
                quote(n)
            ));
        }
    }
    for m in cx.markers("SOURCE_DEF").filter(|m| in_half(&m.rel)) {
        if let Some(n) = m.args.first() {
            out.line_fmt(format_args!("/datum/source_def/{}/spec()", n));
            out.line_fmt(format_args!("\treturn list(SRC_{}, {})", up(n), quote(n)));
        }
    }
    for m in cx.markers("STATE_GRAPH").filter(|m| in_half(&m.rel)) {
        let Some(g) = m.args.first() else { continue };
        let entries: Vec<String> = m
            .args
            .iter()
            .skip(1)
            .map(|a| qualify_globals(&one_line(a), globals))
            .collect();
        out.doc_fmt(format_args!("STATE_GRAPH({}) at {}:{}", g, m.rel, m.line));
        out.line_fmt(format_args!(
            "/datum/graph_decl/g_{}/spec()",
            g.to_lowercase()
        ));
        out.line_fmt(format_args!("\treturn list({}, {})", g, entries.join(", ")));
    }
    out.blank();
    // CAPABILITIES(T, entries...): the type's declared_entries().
    let mut lists: Vec<&Marker> = cx
        .markers("CAPABILITIES")
        .filter(|m| in_half(&m.rel))
        .collect();
    lists.sort_by(|a, b| (a.args.first(), &a.rel, a.line).cmp(&(b.args.first(), &b.rel, b.line)));
    for w in lists.windows(2) {
        if w[0].args.first() == w[1].args.first() {
            out.diag(&w[1].rel, w[1].line, format_args!("a second CAPABILITIES list for {} (the first is at {}:{}): one composition root per type", w[1].args.first().cloned().unwrap_or_default(), w[0].rel, w[0].line));
        }
    }
    for m in lists {
        let Some(ty) = m.args.first() else {
            out.diag(&m.rel, m.line, "CAPABILITIES(T, entries...) needs a type");
            continue;
        };
        let offsets = arg_offsets(&m.body, &m.args);
        out.doc_fmt(format_args!("CAPABILITIES({}) at {}:{}", ty, m.rel, m.line));
        out.line_fmt(format_args!("{}/declared_entries(list/into)", ty));
        out.line("\t..(into)");
        out.line_fmt(format_args!(
            "\tinto += entry_block({}, {}, {})",
            quote(&m.rel),
            m.line,
            ty
        ));
        // table_build() marks the chain it asks for: a block whose table is already compiled is not read, so its constructors are not run again.
        out.line_fmt(format_args!("\tif(declare_block_skipped(into, {}))", ty));
        out.line("\t\treturn");
        // section(name, "doc") opens a section: the entries after it, to the next section or the block's end, are the type's own
        // entries like any other, and each carries the section's name with its file:line (Explain Type and Interaction print both).
        let mut current: Option<(String, u32, usize)> = None; // name, line, entries so far
        let mut seen_sections: BTreeMap<String, u32> = BTreeMap::new();
        let close_section = |cur: &Option<(String, u32, usize)>, out: &mut Output| {
            if let Some((name, line, 0)) = cur {
                out.diag(
                    &m.rel,
                    *line,
                    format_args!("section({}) of {} has no entries", name, ty),
                );
            }
        };
        for (i, a) in m.args.iter().enumerate().skip(1) {
            if a.is_empty() || is_static_entry(a, &statics) {
                continue;
            }
            let line = m.line_at(offsets[i]);
            if is_var_assignment(a) {
                out.diag(&m.rel, line, format_args!("`{}` is a var assignment inside the CAPABILITIES block of {}: the block holds entries only, so the type's vars would be lost; put the CAPABILITIES block after the type's var lines", one_line(a), ty));
                continue;
            }
            if let Some(parts) = section_parts(a) {
                close_section(&current, out);
                let name = parts
                    .first()
                    .map(|p| p.trim().to_string())
                    .unwrap_or_default();
                let ok_name = !name.is_empty()
                    && name.chars().all(|c| c.is_alphanumeric() || c == '_')
                    && !name.starts_with(|c: char| c.is_ascii_digit());
                let ok_doc = parts.len() <= 2
                    && parts
                        .get(1)
                        .map(|d| d.trim().starts_with('"'))
                        .unwrap_or(true);
                if !(ok_name && ok_doc) {
                    out.diag(&m.rel, line, format_args!("`{}`: a section header is section(name) or section(name, \"doc\") with name an identifier", one_line(a)));
                    current = None;
                    continue;
                }
                if let Some(first) = seen_sections.insert(name.clone(), line) {
                    out.diag(
                        &m.rel,
                        line,
                        format_args!(
                            "section({}) of {} is declared twice (first at line {})",
                            name, ty, first
                        ),
                    );
                }
                let doc = parts
                    .get(1)
                    .map(|d| format!(": {}", one_line(d.trim().trim_matches('"'))))
                    .unwrap_or_default();
                out.line_fmt(format_args!("\t// section {}{}", name, doc));
                current = Some((name, line, 0));
                continue;
            }
            match current.as_mut() {
                Some((name, _, n)) => {
                    *n += 1;
                    out.line_fmt(format_args!(
                        "\tinto += entry_line({}, {})",
                        line,
                        quote(name)
                    ));
                }
                None => out.line_fmt(format_args!("\tinto += entry_line({})", line)),
            }
            out.line_fmt(format_args!(
                "\tinto += list({})",
                entry_text(a, caps, globals)
            ));
        }
        close_section(&current, out);
        out.blank();
    }
    lifeform_type_extras(cx, out, &in_half);
}

/// Whether a block line is `name = value` (a var override that fell into a CAPABILITIES block) and not an entry call.
pub(crate) fn is_var_assignment(arg: &str) -> bool {
    let t = arg.trim_start();
    let end = t
        .find(|c: char| !(c.is_alphanumeric() || c == '_'))
        .unwrap_or(t.len());
    if end == 0 {
        return false;
    }
    let rest = t[end..].trim_start();
    rest.starts_with('=') && !rest.starts_with("==")
}

/// The first argument of a `nameof(x)` text: `x`.
pub(crate) fn nameof_inner(arg: &str) -> Option<String> {
    let t = arg.trim();
    t.strip_prefix("nameof(")
        .and_then(|s| s.strip_suffix(')'))
        .map(|s| s.trim().to_string())
}

/// Whether a type path names an atom (its instances initialize through Initialize(), not New()).
pub(crate) fn is_atom_path(ty: &str) -> bool {
    ["/atom", "/obj", "/mob", "/turf", "/area"]
        .iter()
        .any(|p| ty == *p || ty.starts_with(&format!("{}/", p)))
}

/// The calls a block names, by constructor name (a quick scan: a name followed by `(`, outside strings).
pub(crate) fn block_calls(args: &[String], name: &str) -> Vec<Vec<String>> {
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
/// - a non-atom type whose block names a form (a type-level every() is one: lifeform_datum_new() arms it; so is factors(), whose table lifeform_datum_new() puts on the entity its relation names; after_init() is one too: lifeform_datum_new() takes the make() record that arms it), or an owns_one/owns_many with starts =, gets `lifeform_declared = TRUE`, so /datum/New() runs it;
///
/// A type whose block names click_on(), double_click_on(), drag_onto(), drag_over(), hover() or tooltip() gets NO native override: BYOND's mouse
/// callbacks are overridden only in code/engine/kernel/entry.dm, and the input resolver finds the declared entry in the type tables when the event
/// resolves (the `mouse_override` lint rejects any other definition).
pub(crate) fn lifeform_type_extras(
    cx: &Input<'_>,
    out: &mut Output,
    in_half: &dyn Fn(&str) -> bool,
) {
    const FORMS: &[&str] = &[
        "rolls",
        "preset",
        "param",
        "built_from",
        "registry",
        "radio_listen",
        "per_type",
        "variants",
        "initial_contents",
        "knows",
        "starts_as",
        "derives",
        "lives_while",
        "on_ending",
        "modes",
        "every",
        "keeps_if",
        "setup",
        "name_prefix",
        "factors",
        "after_init",
    ];
    let mut lists: Vec<&Marker> = cx
        .markers("CAPABILITIES")
        .filter(|m| in_half(&m.rel))
        .collect();
    lists.sort_by(|a, b| (a.args.first(), &a.rel, a.line).cmp(&(b.args.first(), &b.rel, b.line)));
    for m in lists {
        let Some(ty) = m.args.first() else { continue };
        let ty = ty.trim();
        if !is_atom_path(ty) && ty.starts_with("/datum") {
            let mut declared = FORMS.iter().any(|f| !block_calls(&m.args, f).is_empty());
            // hud_element(..., when = X) is an owns_one with starts = when(X, T).
            for (owns, key) in [
                ("owns_one", "starts"),
                ("owns_many", "starts"),
                ("hud_element", "when"),
            ] {
                if block_calls(&m.args, owns).iter().any(|a| {
                    a.iter()
                        .any(|x| split_opt(x).map(|(k, _)| k == key).unwrap_or(false))
                }) {
                    declared = true;
                }
            }
            if declared {
                out.doc_fmt(format_args!(
                    "{} declares a lifecycle form ({}:{}): /datum/New() runs it.",
                    ty, m.rel, m.line
                ));
                out.line(ty);
                out.line("\tlifeform_declared = TRUE");
            }
        }
    }
}

/// make(type, at =, by =, parts =, name = value...) and make_args(name = value...): their named parameters are every name a param() declares,
/// so DM checks a call's names; the bodies are the engine's (code/engine/lifeforms/params.dm). `analyze` checks each call against the made type.
pub(crate) fn make_procs(cx: &Input<'_>, out: &mut Output) {
    const RESERVED: &[&str] = &["type", "at", "by", "parts", "given", "src", "usr", "args"];
    let mut names: BTreeSet<String> = BTreeSet::new();
    for m in cx.markers("CAPABILITIES") {
        for call in block_calls(&m.args, "param") {
            let Some(first) = call.first() else { continue };
            let Some(name) = nameof_inner(first) else {
                out.diag(
                    &m.rel,
                    m.line,
                    format_args!("param({}): the var is nameof(var)", first),
                );
                continue;
            };
            if RESERVED.contains(&name.as_str()) {
                out.diag(
                    &m.rel,
                    m.line,
                    format_args!(
                        "param(nameof({})): `{}` is one of make()'s own parameters; rename the var",
                        name, name
                    ),
                );
                continue;
            }
            names.insert(name);
        }
    }
    let params: Vec<String> = names
        .iter()
        .map(|n| format!("{} = MAKE_UNSET", n))
        .collect();
    let tail = if params.is_empty() {
        String::new()
    } else {
        format!(", {}", params.join(", "))
    };
    out.doc("make(type, at =, by =, parts =, name = value...): a new instance with its params set before init (code/engine/lifeforms/params.dm).");
    out.line_fmt(format_args!(
        "/proc/make(type, at = null, by = null, parts = null{})",
        tail
    ));
    out.line("\tvar/list/given = list()");
    for n in &names {
        out.line_fmt(format_args!("\tif({} != MAKE_UNSET)", n));
        out.line_fmt(format_args!("\t\tgiven[{}] = {}", quote(n), n));
    }
    out.line("\treturn make_build(type, at, by, parts, given)");
    out.doc(
        "make_args(name = value...): the params of what a starts = makes (OWNER is the holder).",
    );
    out.line_fmt(format_args!("/proc/make_args({})", params.join(", ")));
    out.line("\tvar/list/given = list()");
    for n in &names {
        out.line_fmt(format_args!("\tif({} != MAKE_UNSET)", n));
        out.line_fmt(format_args!("\t\tgiven[{}] = {}", quote(n), n));
    }
    out.line("\treturn make_args_build(given)");
    out.blank();
}

/// The arguments of a `section(...)` header entry, or None when the entry is not one.
pub(crate) fn section_parts(entry: &str) -> Option<Vec<String>> {
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

/// Admit the finite legacy temporary/retained overlap BEFORE policy transforms.
/// W sums original body/argument/path/raw-engine widths; C bounds configure
/// occurrences and D the largest actual constructor spelling. Each rewrite
/// consumes disjoint matched ranges. Link/adjusts/on_change quote expansion,
/// fixed call spelling and final global qualification conservatively fit
/// 1024*(W+C*D). At most eight simultaneous row/parts/text contexts retain a
/// transformed entry; the final factor2 covers old/new geometric String growth.
/// The original delimiter count separately bounds split_args String slots
/// (<=72W for its three-vector-capacity overlap), one_line words and small
/// BTree coordination; these fit the same conservative envelope, plus16KiB
/// per marker for empty arguments/fixed rows. Output itself remains separately
/// admitted for EVERY actual fmt chunk. This is no RSS/CPU or whole-tree claim.
fn admit_temporaries(cx: &Input<'_>) -> Result<(), String> {
    let Some(b) = &cx.budget else { return Ok(()) };
    let result = (|| -> Result<(), String> {
        let mut width = 1usize;
        let mut replaces = 0usize;
        let mut constructor = 1usize;
        for m in cx.markers {
            width = width
                .checked_add(m.name.len())
                .and_then(|n| n.checked_add(m.rel.len()))
                .and_then(|n| n.checked_add(m.body.len()))
                .ok_or("declare temporary width overflow")?;
            if matches!(m.name, "CAPABILITY_TYPE" | "CAPABILITY_DEF") {
                constructor = constructor.max(m.args.first().map_or(0, String::len));
            }
            for a in m.args {
                width = width
                    .checked_add(a.len())
                    .ok_or("declare argument width overflow")?;
                replaces = replaces
                    .checked_add(a.match_indices("configure").count())
                    .ok_or("declare replacement count overflow")?;
            }
        }
        for &(rel, text) in cx.engine_sources {
            width = width
                .checked_add(rel.len())
                .and_then(|n| n.checked_add(text.len()))
                .ok_or("declare engine width overflow")?;
        }
        let expanded = replaces
            .checked_mul(constructor)
            .and_then(|n| n.checked_add(width))
            .ok_or("declare expansion width overflow")?;
        b.charge(
            expanded
                .checked_mul(16384)
                .and_then(|n| {
                    cx.markers
                        .len()
                        .checked_mul(16384)
                        .and_then(|m| n.checked_add(m))
                })
                .ok_or("declare temporary admission overflow")?,
        )
    })();
    if result.is_err() {
        b.deny();
    }
    result
}
pub fn generate(
    cx: &Input<'_>,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Output, String> {
    checkpoint()?;
    admit_temporaries(cx)?;
    if let Some(b) = &cx.budget {
        b.require()?;
    }
    let mut out = cx.output();
    let caps = capabilities(cx, &mut out);
    checkpoint()?;
    let globals = global_constructors(cx, &caps);
    let statics = static_kinds(cx);
    checkpoint()?;
    section(cx, &mut out, &caps, &globals, &statics, false);
    checkpoint()?;
    let mut tests = cx.output();
    section(cx, &mut tests, &caps, &globals, &statics, true);
    checkpoint()?;
    if !tests.body.trim().is_empty() {
        out.line(crate::generator_test_scope::TEST_GUARD);
        out.blank();
        out.line(tests.body.trim_end());
        out.blank();
        out.line("#endif");
    }
    keyed_targets(cx, &mut out);
    checkpoint()?;
    weak_accessors(cx, &mut out);
    checkpoint()?;
    static_blocks(cx, &mut out, &caps, &globals, &statics);
    checkpoint()?;
    make_procs(cx, &mut out);
    checkpoint()?;
    for d in std::mem::take(&mut tests.diags) {
        out.diag(&d.rel, d.line, d.msg);
    }
    if let Some(b) = &cx.budget {
        b.require()?;
    }
    checkpoint()?;
    Ok(out)
}

#[cfg(test)]
mod captured_tests {
    use super::*;
    #[test]
    fn denied_policy_temporary_work_never_starts_output_or_capability_clones() {
        let budget = crate::captured_generator_budget::Budget::new(64).unwrap();
        let args = vec!["cover".to_owned(), "CAP_COVER".to_owned()];
        let marker = Marker {
            name: "CAPABILITY_DEF",
            rel: "code/probe.dm",
            line: 1,
            body: "cover,CAP_COVER",
            args: &args,
            body_offset: 0,
            line_starts: &[0],
        };
        let rows = [marker];
        let input = Input {
            markers: &rows,
            engine_sources: &[],
            budget: Some(budget.clone()),
            poll: None,
        };
        assert!(generate(&input, || Ok(())).is_err());
        assert!(budget.denied());
    }
    #[test]
    fn actual_output_growth_denial_after_temporary_admission_is_not_empty_success() {
        let probe = crate::captured_generator_budget::Budget::new(1024 * 1024).unwrap();
        let input = Input {
            markers: &[],
            engine_sources: &[],
            budget: Some(probe.clone()),
            poll: None,
        };
        admit_temporaries(&input).unwrap();
        let exact = crate::captured_generator_budget::Budget::new(probe.used() + 1).unwrap();
        let denied = Input {
            markers: &[],
            engine_sources: &[],
            budget: Some(exact.clone()),
            poll: None,
        };
        assert!(generate(&denied, || Ok(())).is_err());
        assert!(exact.denied());
    }
    #[test]
    fn marker_poll_failure_cannot_publish_partial_generated_text() {
        let args = vec!["cover".to_owned(), "CAP_COVER".to_owned()];
        let rows = [Marker {
            name: "CAPABILITY_DEF",
            rel: "code/x.dm",
            line: 1,
            body: "cover,CAP_COVER",
            args: &args,
            body_offset: 0,
            line_starts: &[0],
        }];
        let called = std::cell::Cell::new(0usize);
        let stopped = std::cell::Cell::new(false);
        let poll = || {
            let n = called.get() + 1;
            called.set(n);
            if n >= 5 {
                stopped.set(true);
                false
            } else {
                true
            }
        };
        let input = Input {
            markers: &rows,
            engine_sources: &[],
            budget: None,
            poll: Some(&poll),
        };
        let outcome = generate(&input, || {
            if stopped.get() {
                Err("actual original operation refused".into())
            } else {
                Ok(())
            }
        });
        assert_eq!(outcome.unwrap_err(), "actual original operation refused");
        assert!(called.get() >= 5);
    }
    #[test]
    fn original_argument_line_mapping_keeps_block_replacement_coordinates() {
        let args = vec!["/datum/x".to_owned(), "op()".to_owned()];
        let m = Marker {
            name: "CAPABILITIES",
            rel: "code/x.dm",
            line: 1,
            body: "/datum/x,\n op()",
            args: &args,
            body_offset: 13,
            line_starts: &[0, 24],
        };
        assert_eq!(m.line_at(12), 2);
    }
}
