//! Port of `tools/ci/registry_lint.py` (roadmap L3, doc/rewrite/state.md sections 7 and 10).
//!
//! No new ad-hoc global lists of instances: an object that adds itself to a global list
//! (`GLOB.x += src`, `|= src`, `.Add(src)`, `.Insert(..., src)`, `GLOB.x[key] = src`) or declares
//! `GLOBAL_LIST_BOILERPLATE()` fails unless the line carries `// ALLOW(registry): <reason>`.
//!
//! Quirks kept from the Python: the scan runs on the raw text up to the first `//` (so a string
//! holding `//` hides the rest of the line, and a hit inside a string counts); a line with several
//! hits yields one site each; the ALLOW question is asked only for a line that has a hit. The old
//! "N kept sites" summary count is not reproduced.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::{Select, SourceFile};
use crate::util::before_slashes;

const HINT: &str = "declare REGISTRY_MEMBERSHIP() instead (code/__defines/registries.dm)";

static META: Meta = Meta {
    name: "registry",
    group: "",
    label: "registry",
    legacy: "tools/ci/registry_lint.py",
    // os.walk: dot-files and dot-directories included.
    select: Select { roots: &[("code", "dm")], hidden: true },
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "self_add", hint: HINT }],
    allow: &["registry"],
    lists: &[],
};

struct RegistryLint;

impl Lint for RegistryLint {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let self_add = crate::pat!(
            r"\bGLOB\.(\w+)\s*(?:\+=|\|=)\s*src\b|\bGLOB\.(\w+)\.(?:Add|Insert)\((?:[^()]*,\s*)?src\)|\bGLOB\.(\w+)\[[^\]]*\]\s*=\s*src\b"
        );
        let boilerplate = crate::pat_match!(r"\s*GLOBAL_LIST_BOILERPLATE\(\s*(\w+)\s*,");
        for (number, line) in f.raw().numbered() {
            let code = before_slashes(line);
            let mut hits: Vec<String> = Vec::new();
            for m in self_add.captures_iter(code) {
                let g = m.get(1).filter(|s| !s.is_empty()).or(m.get(2).filter(|s| !s.is_empty())).or(m.get(3).filter(|s| !s.is_empty()));
                hits.push(g.unwrap_or("").to_string());
            }
            if let Some(m) = boilerplate.captures(code) {
                hits.push(m.s(1).to_string());
            }
            if !hits.is_empty() && out.allowed(f, number, "registry") {
                continue;
            }
            for hit in hits {
                out.site_msg("self_add", number, format!("objects add themselves to GLOB.{}", hit));
            }
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/registry_lint.py"],
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
    reg.add(RegistryLint);
}
