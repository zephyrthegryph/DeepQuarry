//! Port of `tools/ci/sys_rules/dx_string_names.py`: var names passed as string literals
//! (doc/rewrite/dx_conventions.md, design review section 7). Every accessor that takes a var name
//! takes it as `nameof(...)`. The accessors and their name positions are read from the tree
//! (global procs `own_*` / `rel_*` / `om_set` / `timed_*` / `time_left` with a `var_name`,
//! `from_var` or `dest_var` parameter, or `name` for `om_set`); `ACCESSORS` is the fallback when
//! the tree has none.

use std::collections::HashMap;

use crate::dm::dx::{call_arg_spans, DxIndex, Proc};
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::{SourceFile, Tree};
use crate::pat_match;

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "dx_string_names",
    hint: "pass the var name as nameof(var), never a string literal (dx_conventions.md; design review §7)",
}];

/// name -> positional indexes of var-name arguments (fallback when the tree defines none).
const ACCESSORS: &[(&str, &[usize])] = &[
    ("own_set", &[1]),
    ("own_add", &[1]),
    ("own_remove", &[1]),
    ("own_take", &[1]),
    ("own_clear", &[1]),
    ("own_put", &[1]),
    ("own_take_member", &[1]),
    ("own_take_all", &[1]),
    ("own_values", &[1]),
    ("own_transfer", &[1, 3]),
    ("own_move", &[2]),
    ("rel_set", &[1]),
    ("rel_add", &[1]),
    ("rel_remove", &[1]),
    ("rel_clear", &[1]),
    ("rel_targets", &[1]),
    ("om_set", &[1]),
    ("timed_set", &[1]),
    ("time_left", &[1]),
    ("timed_cancel", &[1]),
];

const NAME_PARAMS: &[&str] = &["var_name", "from_var", "dest_var"];

type Accessors = HashMap<String, Vec<usize>>;

fn fallback() -> Accessors {
    ACCESSORS.iter().map(|(n, idx)| (n.to_string(), idx.to_vec())).collect()
}

/// `accessors_from`: `{name: indexes}` for every global accessor proc with a var-name parameter.
fn accessors_from(procs: &[Proc]) -> Accessors {
    let name_re = pat_match!(r"(?:own_\w+|rel_\w+|om_set|timed_\w+|time_left)$");
    let mut out = Accessors::new();
    for proc in procs {
        if !proc.is_global() || !name_re.is_match(&proc.name) {
            continue;
        }
        let om_set = proc.name == "om_set";
        let idx: Vec<usize> =
            proc.params.iter().enumerate().filter(|(_, p)| NAME_PARAMS.contains(&p.as_str()) || (om_set && p.as_str() == "name")).map(|(k, _)| k).collect();
        if !idx.is_empty() {
            out.insert(proc.name.clone(), idx);
        }
    }
    out
}

/// `call_pattern`: `(?<![\w./:])(a|b|...)\s*\(` over the sorted accessor names.
fn call_pattern(accessors: &Accessors) -> Pat {
    let mut names: Vec<&str> = accessors.keys().map(|s| s.as_str()).collect();
    names.sort();
    Pat::new(&format!(r"(?<![\w./:])({})\s*\(", names.join("|")))
}

/// `scan_file` of the Python: a call whose var-name argument, in the raw text, is a string literal.
fn scan_lines(f: &SourceFile, accessors: &Accessors, pattern: &Pat, out: &mut Vec<(&'static str, usize)>) {
    let named_arg = pat_match!(r"\s*([A-Za-z_]\w*)\s*=(?!=)");
    let string_arg = pat_match!(r#"\s*(?:"|\{")"#);
    let raw = f.raw();
    for (number, code) in f.clean().numbered() {
        let rawline = raw.line(number);
        for m in pattern.captures_iter(code) {
            // Definitions (`/proc/own_set(`) are excluded by the lookbehind on "/".
            let Some(spans) = call_arg_spans(code, m.end(0) - 1) else { continue };
            let positional: Vec<&(usize, usize)> = spans.iter().filter(|sp| !named_arg.is_match(code.get(sp.0..sp.1).unwrap_or(""))).collect();
            let mut hit = false;
            for index in &accessors[m.s(1)] {
                if *index < positional.len() {
                    let (start, end) = *positional[*index];
                    // Argument boundaries come from the sanitized text; the literal check from the raw text.
                    if string_arg.is_match(rawline.get(start..end).unwrap_or("")) {
                        hit = true;
                        break;
                    }
                }
            }
            if hit {
                out.push(("dx_string_names", number));
                break;
            }
        }
    }
}

fn scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let idx = DxIndex::get(tree, files);
    let mut accessors = accessors_from(&idx.procs);
    if accessors.is_empty() {
        accessors = fallback();
    }
    let pattern = call_pattern(&accessors);
    let mut out = Vec::new();
    for f in files {
        let text = f.text();
        if !text.contains("own_") && !text.contains("rel_") && !text.contains("om_set") && !text.contains("time") {
            continue;
        }
        let mut v = Vec::new();
        scan_lines(f, &accessors, &pattern, &mut v);
        out.extend(v.into_iter().map(|(r, n)| (r, f.rel.clone(), n)));
    }
    out
}

fn selftest() -> Result<String, String> {
    let fixture = [
        r#"own_set(src, "beaker", I)"#,
        "own_set(src, nameof(beaker), I)",
        r#"timed_set(get_holder(x, "a"), "emp", TRUE)"#,
        r#"rel_add(src, "[slot]_link", T)"#,
        "om_set(E, name, value)",
        "/proc/own_set(datum/holder, var_name, datum/value)",
        r#"// own_set(src, "x", I)"#,
        r#"to_chat(user, "own_set(src, \"x\", I)")"#,
        r#"time_left(src, "cooldown")"#,
        r#"own_transfer(src, nameof(a), dest, "b")"#,
        r#"own_transfer(src, nameof(a), dest, nameof(b), member = "x")"#,
    ];
    let f = SourceFile::from_text("x.dm", &fixture.join("\n"));
    let acc = fallback();
    let pat = call_pattern(&acc);
    let mut v = Vec::new();
    scan_lines(&f, &acc, &pat, &mut v);
    let got: Vec<usize> = v.into_iter().map(|(_, n)| n).collect();
    if got != vec![1, 3, 4, 9, 10] {
        return Err(format!("dx_string_names selftest: got {:?}", got));
    }
    // The accessor table is read from the tree's global procs.
    let a = SourceFile::from_text(
        "a.dm",
        "/proc/own_widget(datum/holder, var_name, datum/value)\n\treturn\n/proc/own_key(datum/D)\n\treturn\n/obj/proc/own_set(var_name)\n\treturn\n/proc/om_set(datum/E, name, value)\n\treturn",
    );
    let tree = Tree::from_files(vec![a]);
    let files = vec![tree.get("a.dm").unwrap()];
    let idx = DxIndex::get(&tree, &files);
    let got = accessors_from(&idx.procs);
    let mut want = Accessors::new();
    want.insert("own_widget".to_string(), vec![1]);
    want.insert("om_set".to_string(), vec![1]);
    if got != want {
        return Err(format!("dx_string_names selftest: accessors {:?}", got));
    }
    Ok("dx_string_names".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: "dx_string_names", rules: RULES, files_scan: Some(scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
