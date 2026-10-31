//! Whole original ui_types raw marker/bundle/schema policy. No semantic model.
use crate::{
    captured_generator_budget::{Budget, BudgetedText},
    declare_policy::Marker,
    sparse_slots_policy::Output,
};
use std::{collections::BTreeMap, sync::Arc};
pub const UI_TYPES_OUT: &str = "tgui/packages/tgui/interfaces/generated";
pub const MARKERS: &[&str] = &["CAPABILITIES", "SCHEMA", "TRACKED_SCHEMA"];
pub struct Input<'a> {
    pub markers: &'a [Marker<'a>],
    pub(crate) budget: Option<Arc<Budget>>,
    pub(crate) poll: Option<&'a dyn Fn() -> bool>,
}
impl<'a> Input<'a> {
    fn markers<'b>(&'b self, name: &'b str) -> impl Iterator<Item = &'b Marker<'a>> + 'b {
        self.markers
            .iter()
            .take_while(|_| self.poll.map_or(true, |f| f()))
            .filter(move |m| m.name == name)
    }
    fn charge(&self, n: usize) -> bool {
        self.poll.map_or(true, |f| f())
            && self.budget.as_ref().map_or(true, |b| b.charge(n).is_ok())
    }
}
pub struct Files {
    pub files: Vec<(String, String)>,
    pub diags: Vec<crate::sparse_slots_policy::Diagnostic>,
}
pub fn generate(cx: &Input<'_>) -> Result<Files, String> {
    let mut out = match &cx.budget {
        Some(b) => Output::captured(b.clone()),
        None => Output::default(),
    };
    if let Some(b) = &cx.budget {
        for m in cx.markers {
            let width = m.args.iter().try_fold(
                m.rel
                    .len()
                    .checked_add(m.body.len())
                    .ok_or("ui marker width overflow")?,
                |n, a| n.checked_add(a.len()).ok_or("ui marker width overflow"),
            )?;
            b.charge(
                width
                    .checked_add(m.args.len().checked_mul(128).ok_or("ui args overflow")?)
                    .and_then(|n| n.checked_mul(512))
                    .and_then(|n| n.checked_add(4096))
                    .ok_or("ui marker accounting overflow")?,
            )?;
        }
    }
    // The schemas: (type, var) -> the schema expression as written.
    let mut schemas: BTreeMap<(String, String), String> = BTreeMap::new();
    for name in ["TRACKED_SCHEMA", "SCHEMA"] {
        for m in cx.markers(name) {
            if let (Some(t), Some(v), Some(s)) = (m.args.first(), m.args.get(1), m.args.get(2)) {
                schemas.insert((t.clone(), v.clone()), s.clone());
            }
        }
    }
    // Entry procs (a global proc returning a list of entries): a CAPABILITIES entry `name()` stands for them.
    let bundles: BTreeMap<String, Vec<String>> = cx
        .markers(crate::raw_entry_proc_policy::ENTRY_PROC)
        .filter_map(|m| {
            m.args
                .first()
                .map(|n| (n.trim().to_string(), m.args[1..].to_vec()))
        })
        .collect();
    let mut windows: BTreeMap<String, Window> = BTreeMap::new();
    let mut empty: Vec<(String, u32, String, String)> = Vec::new();
    for m in cx.markers("CAPABILITIES") {
        let Some(owner) = m.args.first() else {
            continue;
        };
        let mut window_name: Option<String> = None;
        let mut forwards = false;
        let mut fields: Vec<(String, Option<String>)> = Vec::new();
        let mut acts: Vec<Act> = Vec::new();
        let mut list: Vec<String> = Vec::new();
        expand_bundles(&m.args[1..], &bundles, &mut list, 0, cx);
        for raw in list.iter() {
            let entry = clean(raw);
            let Some((fname, body)) = call_of(&entry) else {
                continue;
            };
            match fname {
                "interface" => {
                    let parts = split_top(body);
                    // A window named by a var of the host (window_var =, each subtype its own) has no name to type here.
                    if let Some(first) = parts.first().filter(|f| f.trim().starts_with('"')) {
                        window_name = Some(first.trim().trim_matches('"').to_string());
                    }
                    forwards = parts
                        .iter()
                        .skip(1)
                        .any(|p| p.trim_start().starts_with("forwards"));
                }
                "ui_shape" => {
                    for part in split_top(body) {
                        if let Some((name, schema)) =
                            part.split_once('=').filter(|(n, _)| is_ident(n.trim()))
                        {
                            fields.push((name.trim().to_string(), Some(schema.trim().to_string())));
                        } else if is_ident(part.trim()) {
                            fields.push((part.trim().to_string(), None));
                        }
                    }
                }
                "op" => {
                    let parts = split_top(body);
                    let Some(key) = parts
                        .first()
                        .map(|k| k.trim().trim_matches('"').to_string())
                    else {
                        continue;
                    };
                    for p in parts.iter().skip(1) {
                        if let Some(act) = ui_act_of(p, &key) {
                            acts.push(act);
                        }
                    }
                }
                _ => {}
            }
        }
        let Some(name) = window_name else { continue };
        if fields.is_empty() && acts.is_empty() {
            // A window that forwards its buttons and declares nothing of its own (the sleeper console) shows its target's window, typed there.
            if forwards {
                continue;
            }
            // A subtype that declares an inherited window again (its own tgui state) is typed where the window's buttons are; judged after
            // every block is read.
            empty.push((m.rel.to_owned(), m.line, name, owner.clone()));
            continue;
        }
        let w = windows.entry(name.clone()).or_insert_with(|| Window {
            owner: owner.clone(),
            rel: m.rel.to_owned(),
            line: m.line,
            fields: Vec::new(),
            acts: Vec::new(),
        });
        for (fname, explicit) in fields {
            if w.fields.iter().any(|f| f.name == fname) {
                continue;
            }
            let schema = explicit.or_else(|| {
                schemas
                    .get(&(owner.clone(), fname.clone()))
                    .and_then(|s| clone_schema(cx, s))
            });
            if schema.is_none() {
                out.diag(&m.rel, m.line, format_args!("ui_shape({}) of {}: `{}` has no schema (TRACKED_SCHEMA or SCHEMA) to type it from", fname, owner, fname));
            }
            w.fields.push(Field {
                name: fname,
                schema,
            });
        }
        for act in acts {
            if w.acts.iter().any(|a| a.name == act.name) {
                continue;
            }
            w.acts.push(act);
        }
        // Resolve each action argument's `from = nameof(v)` against the owner's schemas.
        for act in &mut w.acts {
            for arg in &mut act.args {
                if let Some(from) = arg.from.clone() {
                    arg.schema = schemas
                        .get(&(owner.clone(), from.clone()))
                        .and_then(|s| clone_schema(cx, s));
                    if arg.schema.is_none() {
                        out.diag(
                            &m.rel,
                            m.line,
                            format_args!(
                                "arg(\"{}\", from = nameof({})) of {}: `{}` has no schema",
                                arg.name, from, owner, from
                            ),
                        );
                    }
                }
            }
        }
    }
    for (rel, line, name, owner) in empty {
        if !windows.contains_key(&name) {
            out.diag(&rel, line, format_args!("interface(\"{}\") of {} declares no ui_shape() and no ui_act() op: nothing to type", name, owner));
        }
    }
    let mut files = Vec::new();
    for (name, w) in &windows {
        if !cx.poll.map_or(true, |f| f()) {
            return Err("ui generator operation stopped".into());
        }
        if let Some(b) = &cx.budget {
            if !b.row(&mut files) {
                return Err("ui file roster allocation denied".into());
            }
        }
        let (path, text) = if let Some(b) = &cx.budget {
            let mut path = BudgetedText::new(b);
            use std::fmt::Write;
            write!(path, "{}/{}.d.ts", UI_TYPES_OUT, name)
                .map_err(|_| "ui output path allocation denied")?;
            let mut text = BudgetedText::new(b);
            write_window(name, w, &mut text, cx).map_err(|_| "ui output allocation denied")?;
            (path.finish()?, text.finish()?)
        } else {
            let mut text = String::new();
            write_window(name, w, &mut text, cx).expect("String writer");
            (format!("{}/{}.d.ts", UI_TYPES_OUT, name), text)
        };
        files.push((path, text));
    }
    if let Some(b) = &cx.budget {
        b.require()?;
    }
    if !cx.poll.map_or(true, |f| f()) {
        return Err("ui generator operation stopped".into());
    }
    Ok(Files {
        files,
        diags: out.diags,
    })
}
/// The entries with each `name()` of an entry proc replaced by the proc's entries (nested ones too).
pub(crate) fn expand_bundles(
    entries: &[String],
    bundles: &BTreeMap<String, Vec<String>>,
    out: &mut Vec<String>,
    depth: usize,
    cx: &Input<'_>,
) {
    for raw in entries {
        if schema_work(raw, cx).is_err() {
            return;
        }
        if !cx.charge(raw.len().saturating_add(128).saturating_mul(512)) {
            return;
        }
        if out.len() >= crate::captured_generator_budget::MAX_ROWS {
            if let Some(b) = &cx.budget {
                b.deny();
                return;
            }
        }
        let entry = clean(raw);
        if depth < 8 {
            if let Some((name, body)) = call_of(&entry) {
                if body.trim().is_empty() {
                    if let Some(inner) = bundles.get(name) {
                        expand_bundles(inner, bundles, out, depth + 1, cx);
                        continue;
                    }
                }
            }
        }
        out.push(raw.clone());
    }
}

struct Field {
    name: String,
    schema: Option<String>,
}

struct Arg {
    name: String,
    schema: Option<String>,
    from: Option<String>,
}

struct Act {
    name: String,
    args: Vec<Arg>,
}

struct Window {
    owner: String,
    rel: String,
    line: u32,
    fields: Vec<Field>,
    acts: Vec<Act>,
}

fn write_window(
    name: &str,
    w: &Window,
    s: &mut impl std::fmt::Write,
    cx: &Input<'_>,
) -> std::fmt::Result {
    s.write_str("// GENERATED by tools/analyze: `analyze gen ui_types`. Do not edit by hand; edit the declarations it reads.\n")?;
    write!(s,"// Window {}: the ui_shape() and ui_act() ops of {} ({}:{}); not committed: every build regenerates it (`analyze gen`).\n\n", name, w.owner, w.rel, w.line)?;
    write!(s, "export type {}Data = {{\n", name)?;
    for f in &w.fields {
        if let Some(schema) = &f.schema {
            schema_work(schema, cx)?;
        }
        match &f.schema {
            Some(schema) => {
                write!(s, "  /** {} */\n", describe(schema))?;
                write!(s, "  {}: {};\n", f.name, ts_type(schema))?;
            }
            None => write!(s, "  {}: unknown;\n", f.name)?,
        }
    }
    s.write_str("};\n\n")?;
    write!(s, "export type {}Actions = {{\n", name)?;
    for a in &w.acts {
        if a.args.is_empty() {
            write!(s, "  {}: Record<string, never>;\n", quote_key(&a.name))?;
            continue;
        }
        write!(s, "  {}: {{\n", quote_key(&a.name))?;
        for arg in &a.args {
            if let Some(schema) = &arg.schema {
                schema_work(schema, cx)?;
            }
            match &arg.schema {
                Some(schema) => {
                    write!(s, "    /** {} */\n", describe(schema))?;
                    write!(s, "    {}: {};\n", arg.name, ts_type(schema))?;
                }
                None => write!(s, "    {}: unknown;\n", arg.name)?,
            }
        }
        s.write_str("  };\n")?;
    }
    s.write_str("};\n")?;
    Ok(())
}

pub(crate) fn quote_key(k: &str) -> String {
    if is_ident(k) {
        k.to_string()
    } else {
        format!("'{}'", k)
    }
}

/// A marker argument as one line: the backslash that continued the previous line and the line breaks inside it are not part of the expression.
pub(crate) fn clean(s: &str) -> String {
    let joined: String = s.chars().map(|c| if c == '\\' { ' ' } else { c }).collect();
    joined.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The `ui_act(...)` an op part is, if it is one: the window action's name (the first argument when it is text, else the op key) and its args.
pub(crate) fn ui_act_of(part: &str, key: &str) -> Option<Act> {
    let (name, body) = call_of(part)?;
    let parts = if name == "ui_act" {
        split_top(body)
    } else if name == "inputs" || name == "binds" {
        // inputs(hand(), ui_act(...)): look inside.
        for inner in split_top(body) {
            if let Some(a) = ui_act_of(&inner, key) {
                return Some(a);
            }
        }
        return None;
    } else {
        return None;
    };
    let mut action = key.to_string();
    let mut args = Vec::new();
    for (i, p) in parts.iter().enumerate() {
        let p = p.trim();
        if i == 0 && p.starts_with('"') {
            action = p.trim_matches('"').to_string();
            continue;
        }
        let Some(("arg", abody)) = call_of(p) else {
            continue;
        };
        let aparts = split_top(abody);
        let Some(aname) = aparts
            .first()
            .map(|a| a.trim().trim_matches('"').to_string())
        else {
            continue;
        };
        let mut schema = None;
        let mut from = None;
        for rest in aparts.iter().skip(1) {
            let rest = rest.trim();
            if let Some(v) = rest.strip_prefix("from") {
                let v = v.trim_start().trim_start_matches('=').trim();
                from = v
                    .strip_prefix("nameof(")
                    .and_then(|x| x.strip_suffix(')'))
                    .map(|x| x.trim().to_string());
            } else {
                schema = Some(rest.to_string());
            }
        }
        args.push(Arg {
            name: aname,
            schema,
            from,
        });
    }
    Some(Act { name: action, args })
}

/// "name(body)" -> (name, body), when the whole text is one call.
pub(crate) fn call_of(s: &str) -> Option<(&str, &str)> {
    let s = s.trim();
    let open = s.find('(')?;
    if !s.ends_with(')') {
        return None;
    }
    let name = s[..open].trim();
    if !is_ident(name) {
        return None;
    }
    Some((name, &s[open + 1..s.len() - 1]))
}

pub(crate) fn is_ident(s: &str) -> bool {
    !s.is_empty()
        && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
        && !s.chars().next().unwrap().is_ascii_digit()
}

/// Splits at top-level commas (not inside (), [] or a string).
pub(crate) fn split_top(s: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut in_str = false;
    let bytes: Vec<char> = s.chars().collect();
    let mut cur = String::new();
    for (i, c) in bytes.iter().enumerate() {
        match c {
            '"' if i == 0 || bytes[i - 1] != '\\' => {
                in_str = !in_str;
                cur.push(*c);
            }
            '(' | '[' if !in_str => {
                depth += 1;
                cur.push(*c);
            }
            ')' | ']' if !in_str => {
                depth -= 1;
                cur.push(*c);
            }
            ',' if !in_str && depth == 0 => {
                out.push(cur.trim().to_string());
                cur.clear();
            }
            _ => cur.push(*c),
        }
    }
    let last = cur.trim().to_string();
    if !last.is_empty() {
        out.push(last);
    }
    out
}

/// The kind of a schema expression ("num", "int", "schema_text" -> "text", ...) and its top-level arguments.
pub(crate) fn schema_parts(expr: &str) -> (String, Vec<String>) {
    match call_of(expr) {
        Some((name, body)) => {
            let kind = match name {
                "schema_text" => "text",
                "schema_ref" => "ref",
                "schema_path" => "path",
                other => other,
            };
            (kind.to_string(), split_top(body))
        }
        None => (expr.trim().to_string(), Vec::new()),
    }
}

/// The range text of a schema, as `schema_describe()` prints it at runtime ("num 0..MAX_PUMP_PRESSURE step 1").
pub fn describe(expr: &str) -> String {
    let (kind, args) = schema_parts(expr);
    match kind.as_str() {
        "int" | "num" => {
            let mut min = String::new();
            let mut max = String::new();
            let mut step = String::new();
            let mut positional = 0;
            for a in &args {
                if let Some((n, v)) = a.split_once('=').filter(|(n, _)| is_ident(n.trim())) {
                    match n.trim() {
                        "min" => min = v.trim().to_string(),
                        "max" => max = v.trim().to_string(),
                        "step" => step = v.trim().to_string(),
                        _ => {}
                    }
                } else {
                    positional += 1;
                    match positional {
                        1 => min = a.trim().to_string(),
                        2 => max = a.trim().to_string(),
                        3 if kind == "num" => step = a.trim().to_string(),
                        _ => {}
                    }
                }
            }
            let range = if min.is_empty() && max.is_empty() {
                String::new()
            } else {
                format!(" {}..{}", min, max)
            };
            let step = if step.is_empty() {
                String::new()
            } else {
                format!(" step {}", step)
            };
            format!("{}{}{}", kind, range, step)
        }
        "text" => {
            let max = args
                .iter()
                .find(|a| !a.contains('=') && !a.trim().is_empty())
                .map(|a| a.trim().to_string());
            match max {
                Some(m) => format!("text max {}", m),
                None => "text".to_string(),
            }
        }
        _ => kind,
    }
}

/// The TypeScript type of a schema.
pub(crate) fn ts_type(expr: &str) -> String {
    let (kind, args) = schema_parts(expr);
    match kind.as_str() {
        "bool" => "boolean".into(),
        "int" | "num" | "flags" => "number".into(),
        "text" | "path" | "ref" => "string".into(),
        "enum" => {
            // enum(list("a", "b")): a union of the literals; anything else is a string.
            let lits: Vec<String> = args
                .first()
                .and_then(|a| call_of(a))
                .filter(|(n, _)| *n == "list")
                .map(|(_, body)| {
                    split_top(body)
                        .into_iter()
                        .filter(|x| x.trim().starts_with('"'))
                        .map(|x| format!("'{}'", x.trim().trim_matches('"')))
                        .collect()
                })
                .unwrap_or_default();
            if lits.is_empty() {
                "string".into()
            } else {
                lits.join(" | ")
            }
        }
        "list_of" => match args.first() {
            Some(inner) => format!("{}[]", paren_union(&ts_type(inner))),
            None => "unknown[]".into(),
        },
        "map_of" => match (args.first(), args.get(1)) {
            (Some(_), Some(v)) => format!("Record<string, {}>", ts_type(v)),
            _ => "Record<string, unknown>".into(),
        },
        "row" => "Record<string, unknown>".into(),
        _ => "unknown".into(),
    }
}

pub(crate) fn paren_union(t: &str) -> String {
    if t.contains(" | ") {
        format!("({})", t)
    } else {
        t.to_string()
    }
}

fn schema_work(expr: &str, cx: &Input<'_>) -> std::fmt::Result {
    if cx.budget.is_none() {
        return Ok(());
    }
    let mut depth = 0usize;
    let mut peak = 0usize;
    for c in expr.chars() {
        match c {
            '(' | '[' | '{' => {
                depth = depth.checked_add(1).ok_or(std::fmt::Error)?;
                peak = peak.max(depth)
            }
            ')' | ']' | '}' => depth = depth.saturating_sub(1),
            _ => {}
        }
    }
    if peak > 128 {
        cx.budget.as_ref().unwrap().deny();
        return Err(std::fmt::Error);
    }
    let bytes = expr
        .len()
        .checked_add(1)
        .and_then(|n| n.checked_mul(peak + 1))
        .and_then(|n| n.checked_mul(512))
        .and_then(|n| n.checked_add(4096))
        .ok_or(std::fmt::Error)?;
    if !cx.charge(bytes) {
        return Err(std::fmt::Error);
    }
    Ok(())
}

// A single original schema can feed MANY independently retained action arguments.
// Admit each actual retained clone before allocation, not merely its source once.
fn clone_schema(cx: &Input<'_>, schema: &str) -> Option<String> {
    if !cx.charge(schema.len().saturating_mul(2).saturating_add(64)) {
        return None;
    }
    Some(schema.to_owned())
}

