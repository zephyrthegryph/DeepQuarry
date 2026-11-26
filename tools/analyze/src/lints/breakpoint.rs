//! Port of `tools/ci/breakpoint_lint.py` (damage.md section 6, roadmap D4).
//!
//! Machines break through one base `/obj/machinery/atom_break()`. Fails on any `set_broken()`
//! definition, and on an `atom_break()` / `atom_fix()` override whose body only sets flags (calls the
//! parent, sets or clears BROKEN, updates the icon, returns).
//!
//! Quirks kept from the Python: the "base definitions this lint protects" set holds the `/proc/`
//! spelling (`/atom/proc/atom_break`) but the comparison key is built as `owner/proc` WITHOUT the
//! `proc/` segment (`/atom/atom_break`), so the base definitions are never skipped; an override
//! with an empty body counts as "only sets flags" (`all([])`); `modular_chomp/` is still scanned
//! when it exists (the Python's SCAN_DIRS).

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{Select, SourceFile};
use crate::util::py_strip;

static META: Meta = Meta {
    name: "breakpoint",
    group: "",
    label: "breakpoint",
    legacy: "tools/ci/breakpoint_lint.py",
    // os.walk over SCAN_DIRS = ["code", "modular_chomp"]: dot-files included.
    select: Select { roots: &[("code", "dm"), ("modular_chomp", "dm")], hidden: true },
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "set_broken", hint: "call atom_break() (damage.md section 6)" },
        RuleMeta { name: "flag_only_override", hint: "delete the override: the base /obj/machinery atom_break()/atom_fix() already does that" },
    ],
    allow: &[],
    lists: &[],
};

const BASES: &[&str] = &["/atom/proc/atom_break", "/atom/proc/atom_fix", "/obj/machinery/atom_break", "/obj/machinery/atom_fix"];

struct Breakpoint {
    flag_only: Vec<Pat>,
}

impl Breakpoint {
    fn new() -> Breakpoint {
        let pats = [
            r"^\.\s*=\s*\.\.\(.*\)$",
            r"^\.\.\(.*\)$",
            r"^(src\.)?stat\s*(\|=|&=\s*~|\^=)\s*\(?BROKEN\)?$",
            r"^(src\.)?update_icon\(\)$",
            r"^return(\s+\.)?$",
            r"^if\s*\(\s*!?\s*\.\s*\)$",
            r"^if\s*\(\s*!?\s*\(?\s*stat\s*&\s*BROKEN\s*\)?\s*\)$",
            r"^(set_broken|atom_break|atom_fix)\(\)$",
        ];
        Breakpoint { flag_only: pats.iter().map(|p| Pat::new_match(p)).collect() }
    }
}

/// `body_lines`: the code lines of the proc whose definition is `lines[start]` (0-based).
fn body_lines<'a>(lines: &[&'a str], start: usize) -> Vec<&'a str> {
    let mut out = Vec::new();
    for line in &lines[start + 1..] {
        if py_strip(line).is_empty() {
            continue;
        }
        if !(line.starts_with('\t') || line.starts_with(' ')) {
            break;
        }
        let code = py_strip(line.split("//").next().unwrap_or(""));
        if !code.is_empty() {
            out.push(code);
        }
    }
    out
}

impl Lint for Breakpoint {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let def_re = crate::pat_match!(r"(/[\w/]*?)/(?:proc/|verb/)?(set_broken|atom_break|atom_fix)\s*\(");
        let lines = f.raw().lines_vec();
        for (index, line) in lines.iter().enumerate() {
            let Some(m) = def_re.captures(line) else { continue };
            let (owner, proc_) = (m.s(1), m.s(2));
            let full = format!("{}/{}", owner, proc_);
            if BASES.contains(&full.as_str()) {
                continue;
            }
            let number = index + 1;
            if proc_ == "set_broken" {
                out.site_msg("set_broken", number, format!("{}() defines set_broken(); call atom_break() (damage.md section 6)", full));
                continue;
            }
            let body = body_lines(&lines, index);
            if body.iter().all(|code| self.flag_only.iter().any(|p| p.is_match(code))) {
                out.site_msg(
                    "flag_only_override",
                    number,
                    format!("{}() only sets flags; the base /obj/machinery/{}() does that, so delete the override", full, proc_),
                );
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/breakpoint_lint.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Breakpoint::new());
}
