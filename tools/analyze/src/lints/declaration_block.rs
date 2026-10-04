//! A declaration marker is a block: `CAPABILITIES(T)` / `STATE_GRAPH(graph)` is a header and its entries are the indented statements
//! under it. The old backslash-continued list (`CAPABILITIES(T, \` ... or entries on the marker's own line) no longer compiles, so a
//! branch written before the block form gets this message instead of a compile break.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::{SourceFile, CODE_DM};

const TWO_HINT: &str = "a type has one CAPABILITIES block: move this block's entries under the first one (a codemod that adds a declaration appends to the existing block)";
const HINT: &str = "write the entries as indented statements under the header (CAPABILITIES(T) then one entry per line); `python tools/dx/codemods/capabilities_block.py` converts a file";

static META: Meta = Meta {
    name: "declaration_block",
    group: "",
    label: "declaration_block",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Both,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "backslash_list", hint: HINT }, RuleMeta { name: "two_blocks", hint: TWO_HINT }],
    allow: &[],
    lists: &[],
};

struct DeclarationBlock;

impl Lint for DeclarationBlock {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        self.two_blocks(cx, out);
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

impl DeclarationBlock {
    fn two_blocks(&self, cx: &Cx, out: &mut Sink) {
        let head = crate::pat_match!(r"^CAPABILITIES\((/[\w/]+)\)");
        let mut first: std::collections::HashMap<String, (String, usize)> = std::collections::HashMap::new();
        for f in cx.all_files() {
            if !f.rel.ends_with(".dm") || f.rel.starts_with("code/engine/_generated/") {
                continue;
            }
            for (number, line) in f.raw().numbered() {
                let Some(m) = head.captures(line) else { continue };
                let ty = m.s(1).to_string();
                match first.get(&ty) {
                    None => {
                        first.insert(ty, (f.rel.clone(), number));
                    }
                    Some((rel, at)) => out.site_in_msg("two_blocks", &f.rel, number, format!("{} already has a CAPABILITIES block at {}:{}", ty, rel, at)),
                }
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(DeclarationBlock);
}
