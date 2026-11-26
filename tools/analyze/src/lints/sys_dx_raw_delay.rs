//! Port of `tools/ci/sys_rules/dx_raw_delay.py`: raw decisecond literals in delay arguments
//! (AGENTS.md 3f; dx_conventions.md section 7). The delay argument of a timer or delayed action
//! holds a numeric literal other than 0 that is not scaled by a time define.

use crate::dm::dx::{call_args, match_paren, pick_arg};
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat::Pat;
use crate::tree::SourceFile;
use crate::util::py_rstrip;
use crate::{pat, pat_match};

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "dx_raw_delay",
    hint: "write the delay with a time define (2 SECONDS, 5 MINUTES, 1 TICK), not raw deciseconds (AGENTS.md §3f)",
}];

/// call name -> (positional index of the delay, named argument that can carry it)
const DELAY_ARGS: &[(&str, usize, &str)] = &[
    ("after", 1, "delay"),
    ("om_after", 1, "delay"),
    ("om_after_unique", 1, "delay"),
    ("om_after_replace", 1, "delay"),
    ("om_after_slot", 2, "delay"),
    ("after_slot", 2, "delay"),
    ("look_flash", 2, "duration"),
    ("om_after_realtime", 0, "delay"),
    ("addtimer", 1, "wait"),
    ("do_after", 1, "delay"),
    ("COOLDOWN_START", 2, "cd_time"),
    ("timed_set", 3, "for_time"),
    ("cap_tool", 3, "delay"),
];

const UNITS: &str = r"(?:MILLISECONDS?|DECISECONDS?|SECONDS?|MINUTES?|HOURS?|TICKS?|DAYS?)\b";

fn call_pat() -> &'static Pat {
    static P: std::sync::LazyLock<Pat> = std::sync::LazyLock::new(|| {
        let mut names: Vec<&str> = DELAY_ARGS.iter().map(|d| d.0).collect();
        names.sort();
        Pat::new(&format!(r"(?<![\w./:])({}|cap_\w+)\s*\(", names.join("|")))
    });
    &P
}

fn units_after() -> &'static Pat {
    static P: std::sync::LazyLock<Pat> = std::sync::LazyLock::new(|| Pat::new_match(&format!(r"\s*{}", UNITS)));
    &P
}

/// `blank_scaled_groups`: `expr` with every (...) group followed by a time define blanked.
fn blank_scaled_groups(expr: &str) -> String {
    let mut chars = expr.as_bytes().to_vec();
    for (i, c) in expr.bytes().enumerate() {
        if c != b'(' {
            continue;
        }
        if let Some(end) = match_paren(expr, i) {
            if end > 0 && units_after().is_match(&expr[end + 1..]) {
                for byte in chars.iter_mut().take(end).skip(i + 1) {
                    *byte = b' ';
                }
            }
        }
    }
    String::from_utf8(chars).unwrap_or_else(|_| expr.to_string())
}

/// `raw_literal`: a numeric literal other than 0 not scaled by a unit or used as a factor.
fn raw_literal(expr: &str) -> bool {
    let expr = blank_scaled_groups(expr);
    let number = pat!(r"(?<![\w.])(\d+(?:\.\d+)?(?:e[+-]?\d+)?|\.\d+)(?![\w.])");
    for m in number.captures_iter(&expr) {
        let lit = m.s(1);
        if lit.parse::<f64>().map(|v| v == 0.0).unwrap_or(false) {
            continue;
        }
        let (start, end) = (m.start(0), m.end(0));
        let after = &expr[end..];
        let before = py_rstrip(&expr[..start]);
        if units_after().is_match(after) {
            continue;
        }
        if before.ends_with('*') || before.ends_with('/') || pat_match!(r"\s*\*").is_match(after) {
            continue;
        }
        return true;
    }
    false
}

/// `delays_of`: the delay expressions of one call.
fn delays_of(name: &str, args: &[String]) -> Vec<String> {
    let mut out: Vec<Option<String>> = Vec::new();
    if let Some((_, index, key)) = DELAY_ARGS.iter().find(|d| d.0 == name) {
        let mut got = pick_arg(args, Some(*index), key);
        if got.is_none() && *key != "delay" {
            got = pick_arg(args, None, "delay");
        }
        out.push(got);
    }
    if name.starts_with("cap_") {
        out.push(pick_arg(args, None, "delay"));
        out.push(pick_arg(args, None, "cooldown"));
    }
    out.into_iter().flatten().filter(|d| !d.is_empty()).collect()
}

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    let text = f.text();
    if !["after", "addtimer", "COOLDOWN_START", "timed_set", "cap_", "look_flash"].iter().any(|k| text.contains(k)) {
        return;
    }
    scan_lines(f, out);
}

fn scan_lines(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    for (number, code) in f.clean().numbered() {
        for m in call_pat().captures_iter(code) {
            let Some(args) = call_args(code, m.end(0) - 1) else { continue };
            if args.is_empty() {
                continue;
            }
            if delays_of(m.s(1), &args).iter().any(|d| raw_literal(d)) {
                out.push(("dx_raw_delay", number));
                break;
            }
        }
    }
}

fn selftest() -> Result<String, String> {
    let fixture = [
        "om_after(src, 20, PROC_REF(finish))",
        "om_after(src, 2 SECONDS, PROC_REF(finish))",
        "om_after_slot(src, \"x\", rand(10, 20), PROC_REF(x))",
        "om_after_slot(src, \"x\", rand(1, 2) SECONDS, PROC_REF(x))",
        "timed_set(src, nameof(a), TRUE, for_time = 90 SECONDS / severity)",
        "timed_set(src, nameof(a), TRUE, for_time = 50)",
        "timed_set(src, nameof(a), 5, for_time = duration)",
        "COOLDOWN_START(src, cooldown, 15)",
        "COOLDOWN_START(src, cooldown, base_delay * 2)",
        "after(src, 0, PROC_REF(now))",
        "cap_tool(\"Unbolt\", TOOL_WRENCH, PROC_REF(unbolt), 40)",
        "cap_cover(open_tool = TOOL_CROWBAR, delay = 2 SECONDS)",
        "cap_cover(open_tool = TOOL_CROWBAR, delay = 30)",
        "om_after(src, (base + 5) SECONDS, PROC_REF(x))",
        "om_after(src, delay + 5, PROC_REF(x))",
        "/proc/om_after(datum/E, delay, proc_ref, ...)",
        "addtimer(CALLBACK(src, PROC_REF(x)), 10)",
        "do_after(user, 1.5 SECONDS, target)",
        "after_slot(src, \"x\", 5, PROC_REF(x))",
        "cap_hand(\"Ring\", PROC_REF(ring), cooldown = 30)",
        "cap_hand(\"Ring\", PROC_REF(ring), cooldown = 3 SECONDS)",
        "look_flash(src, \"sparks\", 12)",
    ];
    let f = SourceFile::from_text("x.dm", &fixture.join("\n"));
    let mut v = Vec::new();
    scan_lines(&f, &mut v);
    let got: Vec<usize> = v.into_iter().map(|(_, n)| n).collect();
    let want = vec![1, 3, 6, 8, 11, 13, 15, 17, 19, 20, 22];
    if got != want {
        return Err(format!("dx_raw_delay selftest: got {:?}, want {:?}", got, want));
    }
    Ok("dx_raw_delay".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: "dx_raw_delay", rules: RULES, file_scan: Some(scan_file), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
