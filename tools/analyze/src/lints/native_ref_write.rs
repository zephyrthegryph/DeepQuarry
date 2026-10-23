//! `native_ref_write`: a raw write to a BYOND built-in that holds references (doc/rewrite/proposals/relations.md D11).
//!
//! `vis_contents`, `client.images` and `client.screen` hold atoms and images the collector cannot see through; they become relation ends the
//! engine declares on the base types, written only through its verbs. Until those land, every raw `+=` / `-=` / `=` / `.Add()` / `.Remove()`
//! / `.Cut()` on them outside the engine is counted here: a shrink-only ratchet (`tools/ci/native_ref_write_baseline.txt`), then a ban.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "write vis_contents / client.images / client.screen through the engine's verbs once they land (relations proposal D11); a new raw write is \
not accepted. doc/rewrite/proposals/relations.md D11";

static META: Meta = Meta {
    name: "native_ref_write",
    group: "",
    label: "native_ref_write",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Sites {
        baseline: "tools/ci/native_ref_write_baseline.txt",
        header: &[
            "Raw writes of BYOND built-ins that hold references: vis_contents, client.images, client.screen (doc/rewrite/proposals/relations.md D11).",
            "rule<TAB>file<TAB>normalized line. Shrink-only: after a sweep run `analyze baseline --update --lint native_ref_write`.",
        ],
        banned: &["raw_write"],
    },
    rules: &[RuleMeta { name: "raw_write", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct NativeRefWrite {
    pats: Vec<Pat>,
}

impl NativeRefWrite {
    fn new() -> NativeRefWrite {
        NativeRefWrite {
            pats: vec![
                Pat::new(r"\b(?:vis_contents|images|screen)\s*(?:\+|-|\|)?=(?!=)"),
                Pat::new(r"\b(?:vis_contents|images|screen)\.(?:Add|Remove|Cut|Insert)\("),
            ],
        }
    }
}

impl Lint for NativeRefWrite {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        for (i, line) in f.code().lines().enumerate() {
            let t = line.trim_start();
            if t.starts_with('#') || t.starts_with("var/") || t.contains("var/list/") {
                continue;
            }
            // `images` and `screen` are common local names: count them only on a client (a `.client.` / `client.` / `C.` receiver chain
            // that names a client is not typed here, so a bare `images +=` inside a /client proc counts too).
            if self.pats.iter().any(|p| p.is_match(line)) {
                let is_vis = line.contains("vis_contents");
                let is_client = line.contains("client.images") || line.contains("client.screen") || line.contains("client?.images") || line.contains("client?.screen");
                if is_vis || is_client {
                    out.site("raw_write", i + 1);
                }
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(NativeRefWrite::new());
}
