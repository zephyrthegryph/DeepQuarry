//! The generic-systems lint family (`tools/ci/sys_lint.py` and `tools/ci/sys_rules/*.py`).
//!
//! The Python ran one module per system over every `.dm` under `code/` and `maps/` (unit tests and
//! benchmarks exempt), applied `// ALLOW(sys_<rule>): reason`, and ratcheted each module against
//! `tools/ci/sys_baseline/<module>.txt`. Here each module is its own [`crate::lint::Lint`]
//! (`sys/<module>`, group `sys`) built from a [`SysModule`] by [`register_module`], so a module is
//! one small file `src/lints/sys_<module>.rs`:
//!
//! ```ignore
//! pub fn register(reg: &mut Registry) {
//!     register_module(reg, SysModule { name: "emag", rules: RULES, file_scan: Some(scan_file), ..SysModule::DEFAULT });
//! }
//! ```
//!
//! A module scans per file (`file_scan`, cached on disk per file) when its rules only look at one
//! file, or sees the whole set (`files_scan`) when it needs cross-file state. Return rule names
//! exactly as in the module's `RULES`; the wrapper applies ALLOW (`sys_<rule>`, plus the module's
//! `allow_extra` aliases, unless the rule is in `no_allow`) and the baseline.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::{SourceFile, Tree, CODE_MAPS_DM};

/// `(rule, 1-based line)` found in one file.
pub type FileScan = fn(&SourceFile, &mut Vec<(&'static str, usize)>);
/// `(rule, file, line)` found across `files` (already filtered of exempt paths).
pub type FilesScan = fn(&Tree, &[&SourceFile]) -> Vec<(&'static str, String, usize)>;

#[derive(Clone, Copy)]
pub struct SysModule {
    /// The module name: `emag` for `tools/ci/sys_rules/emag.py` / `tools/ci/sys_baseline/emag.txt`.
    pub name: &'static str,
    /// The module's `RULES`: rule name and fix hint.
    pub rules: &'static [RuleMeta],
    /// ALLOW names the module accepts besides `sys_<rule>` (`ALLOW_NAMES` in the Python).
    pub allow_extra: &'static [&'static str],
    /// When non-empty, the `allow_extra` aliases keep only these rules (appearance: `sys_update_icon`
    /// keeps `update_icon_override` and no other rule); empty means every rule.
    pub allow_extra_rules: &'static [&'static str],
    /// Rules that take no ALLOW annotation (`NO_ALLOW`).
    pub no_allow: &'static [&'static str],
    pub file_scan: Option<FileScan>,
    pub files_scan: Option<FilesScan>,
    /// The module's fixture tests (`selftest()` in the Python).
    pub selftest: Option<fn() -> Result<String, String>>,
    /// Whether the Python module has a `selftest()` (parity runs `sys_lint.py --selftest --only`).
    pub py_selftest: bool,
}

impl SysModule {
    pub const DEFAULT: SysModule = SysModule {
        name: "",
        rules: &[],
        allow_extra: &[],
        allow_extra_rules: &[],
        no_allow: &[],
        file_scan: None,
        files_scan: None,
        selftest: None,
        py_selftest: false,
    };
}

struct SysLint {
    module: SysModule,
    meta: Meta,
}

fn leak<T: ?Sized>(b: Box<T>) -> &'static T {
    Box::leak(b)
}

pub fn register_module(reg: &mut Registry, module: SysModule) {
    let name: &'static str = leak(format!("sys/{}", module.name).into_boxed_str());
    let baseline: &'static str = leak(format!("tools/ci/sys_baseline/{}.txt", module.name).into_boxed_str());
    let header: &'static [&'static str] = leak(
        vec![leak(
            format!("sys_lint baseline for tools/ci/sys_rules/{}.py (doc/rewrite/systems.md); shrink-only, target 0", module.name).into_boxed_str(),
        )]
        .into_boxed_slice(),
    );
    let mut allow: Vec<&'static str> = module
        .rules
        .iter()
        .map(|r| leak(format!("sys_{}", r.name).into_boxed_str()) as &'static str)
        .collect();
    for a in module.allow_extra {
        allow.push(leak(format!("sys_{}", a).into_boxed_str()));
    }
    let scan = match (module.file_scan.is_some(), module.files_scan.is_some()) {
        (true, true) => ScanKind::Both,
        (true, false) => ScanKind::File,
        _ => ScanKind::Tree,
    };
    let meta = Meta {
        name,
        group: "sys",
        label: name,
        legacy: "tools/ci/sys_lint.py",
        select: CODE_MAPS_DM,
        scan,
        policy: Policy::Sites { baseline, header, banned: &[] },
        rules: module.rules,
        allow: leak(allow.into_boxed_slice()),
        lists: &[],
    };
    reg.add(SysLint { module, meta });
}

thread_local! {
    static EXTRA_USED: std::cell::RefCell<Vec<crate::lint::AllowUse>> = const { std::cell::RefCell::new(Vec::new()) };
}

/// `allow::kept` for a module that asks an ALLOW question inside its own scan (outside the
/// wrapper's `sys_<rule>` check, e.g. `ALLOW(cooldown)`): records the annotation as used, so the
/// unused-ALLOW check sees it. The wrapper moves the records into the scan's `Sink`.
pub fn kept_recorded(f: &SourceFile, number: usize, name: &str) -> bool {
    match crate::allow::kept(f, number, name) {
        Some(k) => {
            EXTRA_USED.with(|e| {
                let u = crate::lint::AllowUse { rel: f.rel.clone(), line: k.line as u32, name: name.to_string(), code: k.code.unwrap_or_default() };
                let mut e = e.borrow_mut();
                if !e.contains(&u) {
                    e.push(u);
                }
            });
            true
        }
        None => false,
    }
}

fn drain_extra(out: &mut Sink) {
    EXTRA_USED.with(|e| {
        for u in e.borrow_mut().drain(..) {
            if !out.allow_used.contains(&u) {
                out.allow_used.push(u);
            }
        }
    });
}

impl SysLint {
    fn kept(&self, out: &mut Sink, f: &SourceFile, rule: &str, line: usize) -> bool {
        if self.module.no_allow.contains(&rule) {
            return false;
        }
        if out.allowed(f, line, &format!("sys_{}", rule)) {
            return true;
        }
        // An aliased ALLOW name (appearance: `sys_update_icon` also keeps its sys_* rule).
        if !self.module.allow_extra_rules.is_empty() && !self.module.allow_extra_rules.contains(&rule) {
            return false;
        }
        self.module.allow_extra.iter().any(|a| out.allowed(f, line, &format!("sys_{}", a)))
    }
}

impl Lint for SysLint {
    fn meta(&self) -> &Meta {
        &self.meta
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let Some(scan) = self.module.file_scan else { return };
        let mut found = Vec::new();
        scan(f, &mut found);
        drain_extra(out);
        for (rule, line) in found {
            if !self.kept(out, f, rule, line) {
                out.site(rule, line);
            }
        }
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(scan) = self.module.files_scan else { return };
        let files = cx.files();
        let found = scan(cx.tree, &files);
        drain_extra(out);
        for (rule, rel, line) in found {
            match cx.tree.get(&rel) {
                Some(f) => {
                    if !self.kept(out, f, rule, line) {
                        out.site_in(rule, &rel, line);
                    }
                }
                None => out.site_in(rule, &rel, line),
            }
        }
    }

    fn selftest(&self) -> Result<String, String> {
        match self.module.selftest {
            Some(t) => t(),
            None => Ok(String::new()),
        }
    }

    fn parity(&self) -> Option<Parity> {
        let m = self.module.name;
        // The argument vectors must be 'static; leak the few small ones per module.
        let only: &'static [&'static str] = leak(vec!["tools/ci/sys_lint.py", "--only", m].into_boxed_slice());
        let report: &'static [&'static str] = leak(vec!["tools/ci/sys_lint.py", "--report", "--only", m].into_boxed_slice());
        let update: &'static [&'static str] = leak(vec!["tools/ci/sys_lint.py", "--update", "--only", m].into_boxed_slice());
        let seed: &'static [&'static str] = leak(vec!["tools/ci/sys_lint.py", "--seed", m].into_boxed_slice());
        let selftest: &'static [&'static str] = leak(vec!["tools/ci/sys_lint.py", "--selftest", "--only", m].into_boxed_slice());
        let files: &'static [&'static str] =
            leak(vec![leak(format!("tools/ci/sys_baseline/{}.txt", m).into_boxed_str()) as &'static str].into_boxed_slice());
        let raw: &'static [&'static [&'static str]] = leak(vec![report].into_boxed_slice());
        Some(Parity {
            old: only,
            old_raw: raw,
            blank: &[],
            parse: ParseKind::Report,
            update: Some(update),
            seed: Some(seed),
            files,
            selftest: if self.module.py_selftest { Some(selftest) } else { None },
        })
    }
}

/// `line and not line[0].isspace()`: a non-empty line whose first character is not whitespace.
pub fn col0(line: &str) -> bool {
    line.chars().next().map(|c| !crate::util::is_py_space(c)).unwrap_or(false)
}

/// `_in_family` / `_resolvable`: `path` or one of its ancestors (cut at the last `/`, stopping at
/// a cut index <= 0) is in `roots`.
pub fn in_family(path: &str, roots: &std::collections::HashSet<String>) -> bool {
    let mut path = path;
    while !path.is_empty() {
        if roots.contains(path) {
            return true;
        }
        match path.rfind('/') {
            Some(cut) if cut > 0 => path = &path[..cut],
            _ => return false,
        }
    }
    false
}
