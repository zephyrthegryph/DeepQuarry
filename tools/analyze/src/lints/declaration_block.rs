//! A declaration marker is a block: `CAPABILITIES(T)` / `STATE_GRAPH(graph)` is a header and its entries are the indented statements
//! under it. The old backslash-continued list (`CAPABILITIES(T, \` ... or entries on the marker's own line) no longer compiles, so a
//! branch written before the block form gets this message instead of a compile break.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "write the entries as indented statements under the header (CAPABILITIES(T) then one entry per line); `python tools/dx/codemods/capabilities_block.py` converts a file";

static META: Meta = Meta {
    name: "declaration_block",
    group: "",
    label: "declaration_block",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "backslash_list", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct DeclarationBlock;

impl Lint for DeclarationBlock {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let head = crate::pat_match!(r"^(CAPABILITIES|STATE_GRAPH)\(");
        let inline = crate::pat_match!(r"^(?:CAPABILITIES|STATE_GRAPH)\([^,()]*,");
        for (number, line) in f.raw().numbered() {
            if !head.is_match(line) {
                continue;
            }
            let t = line.trim_end();
            if t.ends_with('\\')|| inline.is_match(line) {
                out.site_msg("backslash_list", number, format!("{} is written as a backslash list", line.split('(').next().unwrap_or("")));
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(DeclarationBlock);
}
