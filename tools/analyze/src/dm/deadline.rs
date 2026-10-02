//! Port of the scanner in `tools/ci/check_deadline_polling.py` (`scan_lines`, `strip_comment`), which
//! the sys_lint rule `deadline_poll` (tools/ci/sys_rules/hygiene.py) imports too: a periodic body
//! (`process()`, `periodic_step()`, `machine_step()`, `service_step()`, or an OM behaviour's
//! `tick()`) holding a comparison of `world.time` with a stored deadline.

use crate::pat;
use crate::util::py_strip;

/// A deadline comparison: the periodic proc's path, the 1-based line and the stripped line text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Hit {
    pub proc_path: String,
    pub line: usize,
    pub text: String,
}

fn is_periodic(type_path: &str, name: &str) -> bool {
    name != "tick" || type_path.starts_with("/datum/om/behaviour")
}

/// `strip_comment`: drops a `//` comment outside strings (a `"` toggles unless preceded by `\`).
pub fn strip_comment(line: &str) -> String {
    let chars: Vec<char> = line.chars().collect();
    let mut out = String::new();
    let mut in_str = false;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '"' && (i == 0 || chars[i - 1] != '\\') {
            in_str = !in_str;
        }
        if !in_str && c == '/' && chars.get(i + 1) == Some(&'/') {
            break;
        }
        out.push(c);
        i += 1;
    }
    out
}

fn indent_of(line: &str) -> usize {
    line.chars().count() - line.trim_start_matches('\t').chars().count()
}

/// `scan_lines`: every deadline comparison in a periodic body of `lines` (a file split on `\n`).
pub fn scan_lines(lines: &[&str]) -> Vec<Hit> {
    let top_level = pat!(r"\A(?:(/[\w/]+?)/(?:proc/)?(process|periodic_step|machine_step|service_step|tick)\()");
    let type_block = pat!(r"\A(?:(/[\w/]+)\s*(?://.*)?$)");
    let nested = pat!(r"\A(?:\t(?:proc/)?(process|periodic_step|machine_step|service_step|tick)\()");
    let deadline = pat!(
        r"(?<![\w.])(?:world\.time|REALTIMEOFDAY)\s*(?:>=|<=|>|<)\s*(?!\d)([A-Za-z_][\w.\[\]?]*)|(?<![\w.])([A-Za-z_][\w.\[\]?]*)\s*(?:>=|<=|>|<)\s*(?:world\.time|REALTIMEOFDAY)(?![\w])"
    );
    let mut out = Vec::new();
    let mut current_type: Option<String> = None;
    let mut i = 0;
    while i < lines.len() {
        let line = lines[i];
        let mut proc_path: Option<String> = None;
        let mut body_indent = 0usize;
        let m = top_level.captures(line);
        match m.filter(|m| is_periodic(m.s(1), m.s(2))) {
            Some(m) => {
                proc_path = Some(format!("{}/{}", m.s(1), m.s(2)));
                body_indent = 1;
            }
            None => {
                if let Some(tb) = type_block.captures(line) {
                    current_type = Some(tb.s(1).to_string());
                } else if !line.is_empty() && !(line.starts_with('\t') || line.starts_with(' ') || line.starts_with('#') || line.starts_with("//")) {
                    current_type = None;
                }
                if let Some(cur) = &current_type {
                    if let Some(n) = nested.captures(line) {
                        if is_periodic(cur, n.s(1)) {
                            proc_path = Some(format!("{}/{}", cur, n.s(1)));
                            body_indent = 2;
                        }
                    }
                }
            }
        }
        let Some(proc_path) = proc_path else {
            i += 1;
            continue;
        };
        let mut j = i + 1;
        while j < lines.len() {
            let body = lines[j];
            if !py_strip(body).is_empty() && indent_of(body) < body_indent {
                break;
            }
            let text = strip_comment(body);
            if deadline.is_match(&text) {
                out.push(Hit { proc_path: proc_path.clone(), line: j + 1, text: py_strip(body).to_string() });
            }
            j += 1;
        }
        i = j;
    }
    out
}
