//! The lint trait and the types every lint shares.
//!
//! A lint is a struct implementing [`Lint`], defined in its own file under `src/lints/` (the
//! build script finds it; there is no registry to edit) with a `pub fn register(reg)`.
//!
//! # Scanning
//! * [`ScanKind::File`]: `scan_file` runs once per in-scope file, in parallel, and its result is
//!   cached on disk keyed by `(file hash, lint, engine build)`. It MUST depend only on that
//!   file's content and `f.rel` (and the lint's scope lists): reading other files makes the cache
//!   wrong. A site is `out.site("rule", line)` (or `site_msg`), and `out.allowed(f, line, "name")`
//!   asks the ALLOW question (and records the annotation as used).
//! * [`ScanKind::Tree`]: `scan_tree` sees every file (cross-file indexes, type trees). Its result
//!   is memoized on the combined hash of every in-scope file, so it only reruns when one changed.
//! * `Both` runs the two; sites are merged.
//!
//! # Reporting
//! The engine, not the lint, applies the ratchet: [`Policy::Sites`] is the fingerprint baseline
//! (`rule<TAB>file<TAB>normalized line`), [`Policy::Hard`] fails on any site, [`Policy::Ceilings`]
//! is a count baseline keyed by `Site::key`. A lint with its own shape sets [`Policy::Custom`] and
//! overrides `finish`.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::scopes::LintScope;
use crate::tree::{Select, SourceFile, Tree};

/// One flagged place. `msg` is the text after the `[lint/rule]` tag; empty means "the source line".
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Site {
    pub rule: String,
    pub rel: String,
    pub line: u32,
    pub msg: String,
    /// Grouping key for [`Policy::Ceilings`] (e.g. `B1:code/x.dm:/obj/foo`); empty otherwise.
    pub key: String,
}

/// An ALLOW annotation that kept a site (for the unused-annotation check).
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct AllowUse {
    pub rel: String,
    pub line: u32,
    pub name: String,
    /// The reason code written on the annotation (`ALLOW(name/CODE)`), "" when none.
    pub code: String,
}

/// What a scan produces.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Sink {
    pub sites: Vec<Site>,
    pub allow_used: Vec<AllowUse>,
    /// Extra summary lines the lint wants printed (e.g. "state schema lint: 12 types, 0 problems").
    pub notes: Vec<String>,
    /// Set by `scan_file`: the file being scanned (so `site` can stamp `rel`).
    #[serde(skip)]
    pub cur: String,
}

impl Sink {
    pub fn new() -> Sink {
        Sink::default()
    }

    /// A site in the file being scanned (`scan_file`).
    pub fn site(&mut self, rule: &str, line: usize) {
        self.sites.push(Site { rule: rule.to_string(), rel: self.cur.clone(), line: line as u32, msg: String::new(), key: String::new() });
    }

    pub fn site_msg(&mut self, rule: &str, line: usize, msg: impl Into<String>) {
        self.sites.push(Site { rule: rule.to_string(), rel: self.cur.clone(), line: line as u32, msg: msg.into(), key: String::new() });
    }

    /// A site in any file (`scan_tree`).
    pub fn site_in(&mut self, rule: &str, rel: &str, line: usize) {
        self.sites.push(Site { rule: rule.to_string(), rel: rel.to_string(), line: line as u32, msg: String::new(), key: String::new() });
    }

    pub fn site_in_msg(&mut self, rule: &str, rel: &str, line: usize, msg: impl Into<String>) {
        self.sites.push(Site { rule: rule.to_string(), rel: rel.to_string(), line: line as u32, msg: msg.into(), key: String::new() });
    }

    pub fn site_keyed(&mut self, rule: &str, rel: &str, line: usize, msg: impl Into<String>, key: impl Into<String>) {
        self.sites.push(Site { rule: rule.to_string(), rel: rel.to_string(), line: line as u32, msg: msg.into(), key: key.into() });
    }

    pub fn note(&mut self, text: impl Into<String>) {
        self.notes.push(text.into());
    }

    /// `allowed(raw_lines, number, lint)`: is line `number` of `f` kept by an annotation for
    /// `lint`? Records the annotation as used when it is.
    pub fn allowed(&mut self, f: &SourceFile, number: usize, lint: &str) -> bool {
        match crate::allow::kept(f, number, lint) {
            Some(k) => {
                self.use_allow(f, k.line, lint, k.code);
                true
            }
            None => false,
        }
    }

    /// Same-line only (`allowed_here`).
    pub fn allowed_here(&mut self, f: &SourceFile, number: usize, lint: &str) -> bool {
        match crate::allow::kept_here(f, number, lint) {
            Some(k) => {
                self.use_allow(f, k.line, lint, k.code);
                true
            }
            None => false,
        }
    }

    fn use_allow(&mut self, f: &SourceFile, at: usize, lint: &str, code: Option<String>) {
        let u = AllowUse { rel: f.rel.clone(), line: at as u32, name: lint.to_string(), code: code.unwrap_or_default() };
        if !self.allow_used.contains(&u) {
            self.allow_used.push(u);
        }
    }
}

/// A rule of a lint: its name (the `[lint/rule]` tag) and the fix hint printed with each new site.
#[derive(Clone, Copy, Debug)]
pub struct RuleMeta {
    pub name: &'static str,
    pub hint: &'static str,
}

#[derive(Clone, Copy, Debug)]
pub enum Policy {
    /// Fingerprint ratchet over `tools/ci/<baseline>` (`allow_annotations.check_sites`).
    Sites {
        baseline: &'static str,
        header: &'static [&'static str],
        /// Rules with no baseline at all (an outright ban): every site is new.
        banned: &'static [&'static str],
    },
    /// Count ceilings keyed by `Site::key` (`name count` lines).
    Ceilings { baseline: &'static str, header: &'static [&'static str] },
    /// Any site fails; nothing is baselined.
    Hard,
    /// The lint's `finish` decides.
    Custom,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScanKind {
    File,
    Tree,
    Both,
}

/// The static description of a lint.
#[derive(Clone, Debug)]
pub struct Meta {
    /// Unique name (`scheduler`, `sys/emag`); what `--lint` matches.
    pub name: &'static str,
    /// Optional group (`sys`): `--lint sys` runs every lint in it.
    pub group: &'static str,
    /// The `[label/rule]` tag in output (the old lint's label).
    pub label: &'static str,
    /// The legacy script (parity harness, docs): `tools/ci/scheduler_lints.py`.
    pub legacy: &'static str,
    pub select: Select,
    pub scan: ScanKind,
    pub policy: Policy,
    pub rules: &'static [RuleMeta],
    /// ALLOW names this lint reads (for annotation validation); usually `[label]`.
    pub allow: &'static [&'static str],
    /// Keys the lint reads from its `lint_scopes.toml` section (validated at startup).
    pub lists: &'static [&'static str],
}

impl Meta {
    pub fn rule(&self, name: &str) -> Option<&RuleMeta> {
        self.rules.iter().find(|r| r.name == name)
    }
}

/// Everything a scan may look at.
pub struct Cx<'a> {
    pub tree: &'a Tree,
    pub meta: &'a Meta,
    pub scope: &'a LintScope,
}

impl<'a> Cx<'a> {
    /// In-scope files minus the lint's configured exemptions, sorted by path.
    pub fn files(&self) -> Vec<&'a SourceFile> {
        self.tree.select(&self.meta.select).into_iter().filter(|f| !self.scope.exempt(&f.rel)).collect()
    }

    /// In-scope files including exempt ones (for an index that must see everything).
    pub fn all_files(&self) -> Vec<&'a SourceFile> {
        self.tree.select(&self.meta.select)
    }

    pub fn exempt(&self, rel: &str) -> bool {
        self.scope.exempt(rel)
    }

    /// A named list from this lint's scope section.
    pub fn list(&self, key: &str) -> &'a [String] {
        self.scope.list(key)
    }
}

/// A finished run of one lint, ready for the policy to judge.
#[derive(Clone, Debug, Default)]
pub struct Run {
    pub sites: Vec<Site>,
    pub notes: Vec<String>,
}

impl Run {
    /// Sites grouped by rule in `meta.rules` order (every rule present, possibly empty).
    pub fn by_rule<'a>(&'a self, meta: &Meta) -> Vec<(&'static str, Vec<&'a Site>)> {
        let mut map: BTreeMap<&str, Vec<&Site>> = BTreeMap::new();
        for s in &self.sites {
            map.entry(s.rule.as_str()).or_default().push(s);
        }
        let mut out = Vec::new();
        for r in meta.rules {
            out.push((r.name, map.remove(r.name).unwrap_or_default()));
        }
        out
    }
}

pub trait Lint: Send + Sync {
    fn meta(&self) -> &Meta;

    /// Per-file scan. See the module docs for the purity contract.
    fn scan_file(&self, _cx: &Cx, _f: &SourceFile, _out: &mut Sink) {}

    /// Whole-tree scan.
    fn scan_tree(&self, _cx: &Cx, _out: &mut Sink) {}

    /// Custom judgement for [`Policy::Custom`]: print into `text`, return true on failure.
    fn finish(&self, _cx: &Cx, _run: &Run, _text: &mut String) -> bool {
        false
    }

    /// An extra check after the policy judged (a stale generated file, say): print into `text`,
    /// return true to fail. Runs for every policy except [`Policy::Custom`].
    fn post_judge(&self, _cx: &Cx, _run: &Run, _text: &mut String) -> bool {
        false
    }

    /// Custom baseline rewrite for [`Policy::Custom`].
    fn update_baseline(&self, _cx: &Cx, _run: &Run, _mode: crate::baseline::Mode) -> std::io::Result<String> {
        Ok(String::new())
    }

    /// Fixture tests (the old `--selftest`). Err carries the failure.
    fn selftest(&self) -> Result<String, String> {
        Ok(String::new())
    }

    /// How `analyze parity` compares this lint with its legacy script (None = not comparable).
    fn parity(&self) -> Option<crate::parity::Parity> {
        None
    }
}

/// The set of lints, in the order `check_ratchets.sh` ran them.
#[derive(Default)]
pub struct Registry {
    pub lints: Vec<Box<dyn Lint>>,
}

impl Registry {
    pub fn add(&mut self, lint: impl Lint + 'static) {
        self.lints.push(Box::new(lint));
    }

    pub fn find(&self, name: &str) -> Option<&dyn Lint> {
        self.lints.iter().find(|l| l.meta().name == name).map(|b| b.as_ref())
    }
}
