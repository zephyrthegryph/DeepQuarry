//! Port of `tools/ci/cap_bits_lint.py`: the cap_state bit registry check
//! (code/__defines/cap_bits.dm; dx_conventions.md section 2).
//!
//! Fails when a `CAP_*` bit is defined outside the registry file, two bits share a value, or a bit
//! reaches `1<<24` (DM's safe bitwise range); also rejects raw writes to `cap_state` outside the
//! framework (`cap_set()` is the writer). No baseline and no ALLOW: any problem fails.
//!
//! Quirk kept: the "shares bit" message goes to the later file in the walk. The Python walked
//! `glob.glob` order (the OS directory order); the engine walks files sorted by path, so for a
//! collision between files the flagged side can differ from a Windows run of the Python.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::incr;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat;
use crate::scopes::LintScope;
use crate::tree::{SourceFile, CODE_DM};
use crate::util::{before_slashes, starts_with_any};

static META: Meta = Meta {
    name: "cap_bits",
    group: "",
    label: "cap_bits",
    legacy: "tools/ci/cap_bits_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "outside_registry", hint: "allocate the bit in code/__defines/cap_bits.dm" },
        RuleMeta { name: "bit_range", hint: "a cap bit must stay below 1<<24" },
        RuleMeta { name: "bit_shared", hint: "every CAP_* bit needs its own value" },
        RuleMeta { name: "raw_write", hint: "write cap_state through cap_set()" },
    ],
    allow: &[],
    lists: &["registry", "writers", "write_exempt_prefixes"],
};

struct CapBits;

/// What one line of a file contributes: a `#define CAP_x (1<<n)` and/or a raw `cap_state` write.
#[derive(Serialize, Deserialize, PartialEq)]
struct Ev {
    line: u32,
    define: Option<(String, u128)>,
    raw_write: bool,
}

#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Facts {
    events: Vec<Ev>,
}

/// One file's events. `writers` / `write_exempt` decide `raw_write`, a function of the file's path.
fn facts_of(f: &SourceFile, writers: &[String], write_exempt: &[String]) -> Facts {
    let rel = f.rel.as_str();
    let mut events = Vec::new();
    for (number, line) in f.raw().numbered() {
        let mut define = None;
        if let Some(m) = pat!(r"^\s*#define\s+(CAP_[A-Z0-9_]+)\s+\(1\s*<<\s*(\d+)\)").captures(line) {
            let shift: u128 = m.s(2).parse().unwrap_or(u128::MAX);
            define = Some((m.s(1).to_string(), shift));
        }
        let code = pat!(r#""[^"]*""#).replace_all(before_slashes(line), "\"\"");
        let mut raw_write = false;
        if pat!(r"\bcap_state\s*(\|=|&=|\^=|=(?!=))").is_match(&code) && !writers.iter().any(|w| w == rel) && !starts_with_any(rel, write_exempt) {
            let var_line = pat!(r"^\s*var/").is_match(&code);
            let tab_assign = pat!(r"^\t+cap_state\s*=").is_match(&code);
            // `A or B and C` in the Python: `and` binds tighter.
            let type_default = (var_line || (tab_assign && !code.contains('/'))) && pat!(r"^\tcap_state\s*=").is_match(&code);
            // a type default (`cap_state = CAP_X` under a type) is configuration, not a write
            raw_write = !type_default;
        }
        if define.is_some() || raw_write {
            events.push(Ev { line: number as u32, define, raw_write });
        }
    }
    Facts { events }
}

/// The findings, from every file's events in file order (the shared `seen` table is the only
/// cross-file state).
fn assemble(files: &[&SourceFile], facts: &[Facts], registry: &[String], out: &mut Sink) {
    let registry_path = registry.first().map(|s| s.as_str()).unwrap_or("");
    let mut seen: HashMap<u128, String> = HashMap::new();
    for (f, fa) in files.iter().zip(facts) {
        let rel = f.rel.as_str();
        for ev in &fa.events {
            let number = ev.line as usize;
            if let Some((name, shift)) = &ev.define {
                if rel != registry_path {
                    out.site_in_msg("outside_registry", rel, number, format!("{} is allocated outside {}", name, registry_path));
                }
                if *shift >= 24 {
                    out.site_in_msg("bit_range", rel, number, format!("{} uses bit {} (max 23)", name, shift));
                }
                if let Some(prev) = seen.get(shift) {
                    out.site_in_msg("bit_shared", rel, number, format!("{} shares bit {} with {}", name, shift, prev));
                }
                seen.insert(*shift, name.to_string());
            }
            if ev.raw_write {
                out.site_in_msg("raw_write", rel, number, "write cap_state through cap_set()");
            }
        }
    }
}

/// Uncached check (the selftest's entry).
fn check(files: &[&SourceFile], registry: &[String], writers: &[String], write_exempt: &[String], out: &mut Sink) {
    let facts: Vec<Facts> = files.iter().map(|f| facts_of(f, writers, write_exempt)).collect();
    assemble(files, &facts, registry, out);
}

impl Lint for CapBits {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let (writers, write_exempt) = (cx.list("writers"), cx.list("write_exempt_prefixes"));
        let ctx = incr::ctx_key(&(writers, write_exempt));
        let facts = incr::keyed("cap_bits-facts", ctx, &files, |f| facts_of(f, writers, write_exempt));
        assemble(&files, &facts, cx.list("registry"), out);
        let n = out.sites.len();
        out.note(format!("cap_bits_lint: {} problem(s)", n));
    }

    fn selftest(&self) -> Result<String, String> {
        const REG: &str = "code/__defines/cap_bits.dm";
        let files = vec![
            SourceFile::from_text(REG, "#define CAP_A (1<<0)\n#define CAP_B (1<<1)\n"),
            SourceFile::from_text(
                "code/x.dm",
                "#define CAP_C (1<<1)\n/obj/x\n\tcap_state = CAP_A\n/obj/x/proc/y()\n\tcap_state |= CAP_B\n",
            ),
            SourceFile::from_text("code/y.dm", "#define CAP_D (1<<30)\n"),
        ];
        let mut scope = LintScope::default();
        scope.lists.insert("registry".into(), vec![REG.into()]);
        scope.lists.insert("writers".into(), vec!["code/datums/capabilities/capabilities.dm".into()]);
        scope.lists.insert("write_exempt_prefixes".into(), vec!["code/modules/unit_tests/".into()]);
        let refs: Vec<&SourceFile> = files.iter().collect();
        let mut out = Sink::new();
        check(&refs, scope.list("registry"), scope.list("writers"), scope.list("write_exempt_prefixes"), &mut out);
        let has = |pred: &dyn Fn(&crate::lint::Site) -> bool| out.sites.iter().any(pred);
        if !has(&|s| s.msg.contains("outside") && s.msg.contains("CAP_C")) {
            return Err("missing 'outside' for CAP_C".into());
        }
        if !has(&|s| s.msg.contains("shares bit 1")) {
            return Err("missing 'shares bit 1'".into());
        }
        if !has(&|s| s.msg.contains("max 23")) {
            return Err("missing 'max 23'".into());
        }
        if !has(&|s| s.rel == "code/x.dm" && s.line == 5 && s.msg.contains("cap_set")) {
            return Err("missing the raw write at x.dm:5".into());
        }
        if has(&|s| s.rel == "code/x.dm" && s.line == 3) {
            return Err("x.dm:3 is a type default and must not be flagged".into());
        }
        Ok(String::new())
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/cap_bits_lint.py"],
            old_raw: &[&["tools/ci/cap_bits_lint.py"]],
            blank: &[],
            parse: ParseKind::FileLine,
            update: None,
            seed: None,
            files: &[],
            selftest: Some(&["tools/ci/cap_bits_lint.py", "--selftest"]),
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(CapBits);
}
