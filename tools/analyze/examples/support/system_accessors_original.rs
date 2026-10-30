//! `analyze gen system_accessors` -> `code/engine/_generated/system_accessors.dm`.
//!
//! `SYSTEM_ACCESSOR(system, name, nameof(var))` (declared in `code/contracts/accessors/`) is the
//! only way content reads a system's private state. This emits the accessor proc:
//! `name()` returns `var` of the system's singleton, so a call is a plain typed read, and the
//! reads engine follows a call of it to that var (`ReadKind::System`), which is how a stat that
//! calls `night_shift_active()` is marked when `night` changes. A fourth argument, a type path, makes the accessor typed:
//! `SYSTEM_ACCESSOR(ticker, ticker_mode, nameof(mode), /datum/game_mode)` emits `/proc/ticker_mode() as /datum/game_mode`, so a
//! caller reads a field through it (`ticker_mode().name`) where the system's var held an object.

use std::collections::HashSet;

use crate::pat;
use crate::sem::gen::{GenCx, GenOut, Generator};
const SYSTEM_INSTANCE: &str = "GLOB.{system}_service";
const TEST_GUARD: &str = "#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)";
fn test_only(rel: &str) -> bool {
    ["code/tests/", "code/modules/unit_tests/"]
        .iter()
        .any(|d| rel.starts_with(d))
}
fn system_types(system: &str) -> Vec<String> {
    vec![
        format!("/datum/world_service/{}", system),
        format!("/datum/system/{}", system),
    ]
}
use std::collections::HashMap;

struct SystemAccessors;

impl Generator for SystemAccessors {
    fn name(&self) -> &'static str {
        "system_accessors"
    }

    fn output(&self) -> &'static str {
        "system_accessors.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        // A system declared with SYSTEM_DEF(x) is read through its `SSx` global; a legacy world service through its GLOB var.
        let sys_def = crate::pat!(r"(?m)^\s*SYSTEM_DEF\((\w+)\)");
        // Per file, cached by content: an edit reads one file.
        let files = cx.tree.select(&crate::tree::CODE_DM);
        let per: Vec<Vec<String>> = crate::incr::facts("gen-system-defs", &files, |f| {
            if !f.text().contains("SYSTEM_DEF(") {
                return Vec::new();
            }
            sys_def
                .captures_iter(f.text())
                .into_iter()
                .map(|c| c.s(1).to_string())
                .collect()
        });
        let sys_defs: HashSet<String> = per.into_iter().flatten().collect();
        let instance = |system: &str| -> String {
            if sys_defs.contains(system) {
                format!("SS{}", system)
            } else {
                SYSTEM_INSTANCE.replace("{system}", system)
            }
        };
        let mut rows: Vec<(String, String, String, String, u32, Option<String>)> = Vec::new();
        for m in cx.markers("SYSTEM_ACCESSOR") {
            let (Some(system), Some(name), Some(key)) =
                (m.args.first(), m.args.get(1), m.args.get(2))
            else {
                out.diag(
                    &m.rel,
                    m.line,
                    "SYSTEM_ACCESSOR(system, name, nameof(var)) needs three arguments",
                );
                continue;
            };
            let Some(var) = key
                .trim()
                .strip_prefix("nameof(")
                .and_then(|s| s.strip_suffix(')'))
                .map(|s| s.trim().to_string())
            else {
                out.diag(
                    &m.rel,
                    m.line,
                    format!(
                        "accessor `{}`: the third argument is nameof(var), not `{}`",
                        name, key
                    ),
                );
                continue;
            };
            let (_, vars) = system_vars(cx.tree, system);
            if !vars.contains(&var) {
                out.diag(
                    &m.rel,
                    m.line,
                    format!(
                        "accessor `{}`: system `{}` has no var `{}` (looked at {})",
                        name,
                        system,
                        var,
                        system_types(system).join(", ")
                    ),
                );
                continue;
            }
            let typed = match m.args.get(3).map(|t| t.trim().to_string()) {
                None => None,
                Some(t)
                    if t.starts_with('/')
                        && t[1..]
                            .chars()
                            .all(|c| c.is_alphanumeric() || c == '_' || c == '/') =>
                {
                    Some(t)
                }
                Some(t) => {
                    out.diag(
                        &m.rel,
                        m.line,
                        format!(
                            "accessor `{}`: the fourth argument is the var's type path, not `{}`",
                            name, t
                        ),
                    );
                    continue;
                }
            };
            rows.push((
                name.clone(),
                system.clone(),
                var,
                m.rel.clone(),
                m.line,
                typed,
            ));
        }
        rows.sort();
        for w in rows.windows(2) {
            if w[0].0 == w[1].0 {
                out.diag(
                    &w[1].3,
                    w[1].4,
                    format!(
                        "accessor `{}` is declared twice (also {}:{})",
                        w[0].0, w[0].3, w[0].4
                    ),
                );
            }
        }
        rows.dedup_by(|a, b| a.0 == b.0);
        // An accessor declared in a test-only file (`test_only`) exists only in a test build.
        let (tests, content): (Vec<_>, Vec<_>) = rows.into_iter().partition(|r| test_only(&r.3));
        let emit =
            |out: &mut GenOut, rows: Vec<(String, String, String, String, u32, Option<String>)>| {
                for (name, system, var, rel, line, typed) in rows {
                    match &typed {
                        Some(t) => {
                            out.doc(format!("SYSTEM_ACCESSOR({}, {}, nameof({}), {}) at {}:{}: the {} system's `{}`, read as a typed var.", system, name, var, t, rel, line, system, var));
                            out.line(format!("/proc/{}() as {}", name, t));
                            out.line(format!("	RETURN_TYPE({})", t));
                        }
                        None => {
                            out.doc(format!("SYSTEM_ACCESSOR({}, {}, nameof({})) at {}:{}: the {} system's `{}`, read as a plain var.", system, name, var, rel, line, system, var));
                            out.line(format!("/proc/{}()", name));
                        }
                    }
                    out.line(format!("	return {}?.{}", instance(&system), var));
                    out.blank();
                }
            };
        emit(out, content);
        if !tests.is_empty() {
            out.line(TEST_GUARD);
            out.blank();
            emit(out, tests);
            out.line("#endif");
        }
    }
}

pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(SystemAccessors));
}

use crate::tree::{SourceFile, Tree};
use crate::util::{py_lstrip, py_rstrip, py_strip};
fn system_vars(tree: &Tree, system: &str) -> (bool, std::collections::HashSet<String>) {
    let types = system_types(system);
    let files = tree
        .select(&crate::tree::CODE_DM)
        .into_iter()
        .filter(|file| {
            let code = &file.code().text;
            let plain =
                !system.is_empty() && system.chars().all(|c| c.is_alphanumeric() || c == '_');
            if !plain {
                return types.iter().any(|t| code.contains(t));
            }
            ["/datum/world_service/", "/datum/system/"]
                .iter()
                .any(|prefix| {
                    let mut from = 0;
                    while let Some(i) = code[from..].find(prefix) {
                        let start = from + i + prefix.len();
                        let run: String = code[start..]
                            .chars()
                            .take_while(|c| c.is_alphanumeric() || *c == '_')
                            .collect();
                        if run.starts_with(system) {
                            return true;
                        }
                        from = start;
                    }
                    false
                })
        })
        .collect::<Vec<_>>();
    let table = original_type_vars(&files);
    let mut vars = std::collections::HashSet::new();
    let mut known = false;
    for ty in &types {
        if let Some(v) = table.get(ty) {
            known = true;
            vars.extend(v.iter().cloned());
        } else if files
            .iter()
            .any(|f| f.code().text.lines().any(|line| line.trim_end() == ty))
        {
            known = true;
        }
    }
    (known, vars)
}
fn original_type_vars(files: &[&SourceFile]) -> HashMap<String, HashSet<String>> {
    let mut table: HashMap<String, HashSet<String>> = HashMap::new();
    for f in files {
        let clean = f.clean();
        let mut current: Option<String> = None;
        let mut group_indent: Option<usize> = None;
        for line in clean.lines() {
            if let Some(m) =
                pat!(r"^(/[\w/]+?)/var/(?:(?:global|static|tmp|const|final)/)*(?:[\w/]+/)?(\w+)\b")
                    .captures(line)
            {
                table
                    .entry(m.s(1).to_string())
                    .or_default()
                    .insert(m.s(2).to_string());
                current = None;
                continue;
            }
            if let Some(h) = pat!(r"^(/[\w/]+)\s*$").captures(py_rstrip(line)) {
                current = Some(h.s(1).to_string());
                group_indent = None;
                continue;
            }
            // SYSTEM_DEF(x) declares /datum/system/x through a macro: its indented body is that type's block.
            if let Some(h) = pat!(r"^SYSTEM_DEF\((\w+)\)\s*$").captures(py_rstrip(line)) {
                current = Some(format!("/datum/system/{}", h.s(1)));
                group_indent = None;
                continue;
            }
            if !line.is_empty() && !line.starts_with([' ', '\t']) {
                current = None;
                continue;
            }
            let Some(cur) = &current else { continue };
            if let Some(gi) = group_indent {
                let indent = line.len() - py_lstrip(line).len();
                if !py_strip(line).is_empty() && indent > gi {
                    let t = py_strip(line);
                    let last = if !line.contains('=') {
                        t.rsplit('/').next().unwrap_or("")
                    } else {
                        py_strip(line.split('=').next().unwrap_or(""))
                            .rsplit('/')
                            .next()
                            .unwrap_or("")
                    };
                    if let Some(name) = pat!(r"\A[A-Za-z_]\w*").find(last) {
                        table
                            .entry(cur.clone())
                            .or_default()
                            .insert(name.as_str().to_string());
                    }
                    continue;
                }
                group_indent = None;
            }
            if let Some(g) = pat!(r"^(\s+)var\s*$").captures(line) {
                group_indent = Some(g.s(1).len());
                continue;
            }
            if let Some(v) = pat!(r"^\s+var/(?:[\w/]+/)?(\w+)\s*(?:=|$|\bas\b)").captures(line) {
                table
                    .entry(cur.clone())
                    .or_default()
                    .insert(v.s(1).to_string());
            }
        }
    }
    table
}
