//! `analyze gen ui_types` -> `tgui/packages/tgui/interfaces/generated/<Window>.d.ts`, one file per window an entry list declares.
//!
//! The E5 generator for the UI shape (doc/rewrite/final_api.html, section 13 "UI", section 15 "Tests", E0 proof 10): a type that declares
//! `interface("Window", ...)` and `ui_shape(var, ...)` in its `CAPABILITIES` list gets the TypeScript types of the window. The data type has one
//! field per name `ui_shape` lists, typed from the tracked var's schema (`TRACKED_SCHEMA(T, var, schema)` or `SCHEMA(T, var, schema)`), and the
//! doc comment on the field is the schema's own range text ("num 0..MAX_PUMP_PRESSURE step 1"), the text `schema_range_text()` returns at runtime,
//! so the two cannot disagree (proof 10 compares them). The actions type has one entry per `ui_act()` op of the list, with its `arg()`s typed the
//! same way. The generated TypeScript type of a numeric field stays `number`: the range is documentation, not a brand.
//!
//! These files live beside the ones `tools/build/lib/ui_types.ts` writes from the legacy UI tables; that script leaves a file that carries this
//! generator's header alone.

use std::collections::BTreeMap;

use crate::sem::gen::{GenCx, GenOut, Generator};

/// Where the files go (relative to the repo root).
pub const UI_TYPES_OUT: &str = "tgui/packages/tgui/interfaces/generated";

struct UiTypes;

impl Generator for UiTypes {
    fn name(&self) -> &'static str {
        "ui_types"
    }

    /// No DM file: the output is the TypeScript files of `files()`.
    fn output(&self) -> &'static str {
        ""
    }

    fn generate(&self, _cx: &GenCx, _out: &mut GenOut) {}

    fn files(&self, cx: &GenCx, out: &mut GenOut) -> Vec<(String, String)> {
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
        let bundles: BTreeMap<String, Vec<String>> = cx.markers(crate::sem::decls::ENTRY_PROC).filter_map(|m| m.args.first().map(|n| (n.trim().to_string(), m.args[1..].to_vec()))).collect();
        let mut windows: BTreeMap<String, Window> = BTreeMap::new();
        for m in cx.markers("CAPABILITIES") {
            let Some(owner) = m.args.first() else { continue };
            let mut window_name: Option<String> = None;
            let mut fields: Vec<(String, Option<String>)> = Vec::new();
            let mut acts: Vec<Act> = Vec::new();
            let mut list: Vec<String> = Vec::new();
            expand_bundles(&m.args[1..], &bundles, &mut list, 0);
            for raw in list.iter() {
                let entry = clean(raw);
                let Some((fname, body)) = call_of(&entry) else { continue };
                match fname {
                    "interface" => {
                        let parts = split_top(body);
                        if let Some(first) = parts.first() {
                            window_name = Some(first.trim().trim_matches('"').to_string());
                        }
                    }
                    "ui_shape" => {
                        for part in split_top(body) {
                            if let Some((name, schema)) = part.split_once('=').filter(|(n, _)| is_ident(n.trim())) {
                                fields.push((name.trim().to_string(), Some(schema.trim().to_string())));
                            } else if is_ident(part.trim()) {
                                fields.push((part.trim().to_string(), None));
                            }
                        }
                    }
                    "op" => {
                        let parts = split_top(body);
                        let Some(key) = parts.first().map(|k| k.trim().trim_matches('"').to_string()) else { continue };
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
                out.diag(&m.rel, m.line, format!("interface(\"{}\") of {} declares no ui_shape() and no ui_act() op: nothing to type", name, owner));
                continue;
            }
            let w = windows.entry(name.clone()).or_insert_with(|| Window { owner: owner.clone(), rel: m.rel.clone(), line: m.line, fields: Vec::new(), acts: Vec::new() });
            for (fname, explicit) in fields {
                if w.fields.iter().any(|f| f.name == fname) {
                    continue;
                }
                let schema = explicit.or_else(|| schemas.get(&(owner.clone(), fname.clone())).cloned());
                if schema.is_none() {
                    out.diag(&m.rel, m.line, format!("ui_shape({}) of {}: `{}` has no schema (TRACKED_SCHEMA or SCHEMA) to type it from", fname, owner, fname));
                }
                w.fields.push(Field { name: fname, schema });
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
                        arg.schema = schemas.get(&(owner.clone(), from.clone())).cloned();
                        if arg.schema.is_none() {
                            out.diag(&m.rel, m.line, format!("arg(\"{}\", from = nameof({})) of {}: `{}` has no schema", arg.name, from, owner, from));
                        }
                    }
                }
            }
        }
        let mut files = Vec::new();
        for (name, w) in &windows {
            files.push((format!("{}/{}.d.ts", UI_TYPES_OUT, name), render_window(name, w)));
        }
        files
    }
}

/// The entries with each `name()` of an entry proc replaced by the proc's entries (nested ones too).
fn expand_bundles(entries: &[String], bundles: &BTreeMap<String, Vec<String>>, out: &mut Vec<String>, depth: usize) {
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

fn render_window(name: &str, w: &Window) -> String {
    let mut s = String::new();
    s.push_str("// GENERATED by tools/analyze: `analyze gen ui_types`. Do not edit by hand; edit the declarations it reads.\n");
    s.push_str(&format!("// Window {}: the ui_shape() and ui_act() ops of {} ({}:{}); CI fails when this file is stale (`analyze gen --check`).\n\n", name, w.owner, w.rel, w.line));
    s.push_str(&format!("export type {}Data = {{\n", name));
    for f in &w.fields {
        match &f.schema {
            Some(schema) => {
                s.push_str(&format!("  /** {} */\n", describe(schema)));
                s.push_str(&format!("  {}: {};\n", f.name, ts_type(schema)));
            }
            None => s.push_str(&format!("  {}: unknown;\n", f.name)),
        }
    }
    s.push_str("};\n\n");
    s.push_str(&format!("export type {}Actions = {{\n", name));
    for a in &w.acts {
        if a.args.is_empty() {
            s.push_str(&format!("  {}: Record<string, never>;\n", quote_key(&a.name)));
            continue;
        }
        s.push_str(&format!("  {}: {{\n", quote_key(&a.name)));
        for arg in &a.args {
            match &arg.schema {
                Some(schema) => {
                    s.push_str(&format!("    /** {} */\n", describe(schema)));
                    s.push_str(&format!("    {}: {};\n", arg.name, ts_type(schema)));
                }
                None => s.push_str(&format!("    {}: unknown;\n", arg.name)),
            }
        }
        s.push_str("  };\n");
    }
    s.push_str("};\n");
    s
}

fn quote_key(k: &str) -> String {
    if is_ident(k) {
        k.to_string()
    } else {
        format!("'{}'", k)
    }
}

/// A marker argument as one line: the backslash that continued the previous line and the line breaks inside it are not part of the expression.
fn clean(s: &str) -> String {
    let joined: String = s.chars().map(|c| if c == '\\' { ' ' } else { c }).collect();
    joined.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// The `ui_act(...)` an op part is, if it is one: the window action's name (the first argument when it is text, else the op key) and its args.
fn ui_act_of(part: &str, key: &str) -> Option<Act> {
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
        let Some(("arg", abody)) = call_of(p) else { continue };
        let aparts = split_top(abody);
        let Some(aname) = aparts.first().map(|a| a.trim().trim_matches('"').to_string()) else { continue };
        let mut schema = None;
        let mut from = None;
        for rest in aparts.iter().skip(1) {
            let rest = rest.trim();
            if let Some(v) = rest.strip_prefix("from") {
                let v = v.trim_start().trim_start_matches('=').trim();
                from = v.strip_prefix("nameof(").and_then(|x| x.strip_suffix(')')).map(|x| x.trim().to_string());
            } else {
                schema = Some(rest.to_string());
            }
        }
        args.push(Arg { name: aname, schema, from });
    }
    Some(Act { name: action, args })
}

/// "name(body)" -> (name, body), when the whole text is one call.
fn call_of(s: &str) -> Option<(&str, &str)> {
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

fn is_ident(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') && !s.chars().next().unwrap().is_ascii_digit()
}

/// Splits at top-level commas (not inside (), [] or a string).
fn split_top(s: &str) -> Vec<String> {
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
fn schema_parts(expr: &str) -> (String, Vec<String>) {
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
            let range = if min.is_empty() && max.is_empty() { String::new() } else { format!(" {}..{}", min, max) };
            let step = if step.is_empty() { String::new() } else { format!(" step {}", step) };
            format!("{}{}{}", kind, range, step)
        }
        "text" => {
            let max = args.iter().find(|a| !a.contains('=') && !a.trim().is_empty()).map(|a| a.trim().to_string());
            match max {
                Some(m) => format!("text max {}", m),
                None => "text".to_string(),
            }
        }
        _ => kind,
    }
}

/// The TypeScript type of a schema.
fn ts_type(expr: &str) -> String {
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
                .map(|(_, body)| split_top(body).into_iter().filter(|x| x.trim().starts_with('"')).map(|x| format!("'{}'", x.trim().trim_matches('"'))).collect())
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

fn paren_union(t: &str) -> String {
    if t.contains(" | ") {
        format!("({})", t)
    } else {
        t.to_string()
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(UiTypes));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_range_text_is_the_runtime_text() {
        assert_eq!(describe("num(0, MAX_PUMP_PRESSURE, step = 1)"), "num 0..MAX_PUMP_PRESSURE step 1");
        assert_eq!(describe("int(0, 10)"), "int 0..10");
        assert_eq!(describe("int(1)"), "int 1..");
        assert_eq!(describe("int()"), "int");
        assert_eq!(describe("schema_text(8)"), "text max 8");
        assert_eq!(describe("bool()"), "bool");
    }

    #[test]
    fn schemas_become_typescript_types() {
        assert_eq!(ts_type("num(0, 5)"), "number");
        assert_eq!(ts_type("enum(list(\"off\", \"on\"))"), "'off' | 'on'");
        assert_eq!(ts_type("list_of(int(0, 3))"), "number[]");
        assert_eq!(ts_type("schema_text(8)"), "string");
    }

    #[test]
    fn calls_split_at_the_top_level() {
        assert_eq!(split_top("\"a,b\", f(1, 2), x = [3, 4]"), vec!["\"a,b\"", "f(1, 2)", "x = [3, 4]"]);
        assert_eq!(call_of("op(\"x\", hand())"), Some(("op", "\"x\", hand()")));
    }
}
