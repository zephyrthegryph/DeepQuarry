//! The door-gate ratchet (doc/rewrite/final_api.html section 8 "Spaces and doors").
//!
//! Things behind covers and panels work by physical paths: an op, slot or graph placed `at(SPACE_X)` is reachable only through open doors,
//! a latch or a protrusion holds a door, a staged space exists from its construction stage, a slot's `fits =` says what it accepts. This lint
//! counts the hand-written gates the path system replaces, so their number can only fall:
//!
//!   when_door      `when(COVER_OPEN)`, `when(PANEL_OPEN)`, `when(nameof(opened))`, `when(nameof(panel_open))`: an op silenced while a door is
//!                  shut (an op of the outside that works while it is shut, `when(cond_not(nameof(opened)))`, is not a path and is not counted)
//!   req_door       `req_is(COVER_OPEN, ...)`, `req_is(PANEL_OPEN, ...)`, `req_panel_closed()`: a door's state as a requirement
//!                  (a cover's own `req_is(COVER_REMOVED, FALSE)` is its state, not a path, and is not counted)
//!   req_built_put  `req_built(...)` on a line that puts something in (an `.insert` op key, `put_in`): a staged slot written by hand;
//!                  the op key is a string, so this part reads the raw line
//!
//! Over the `code_only` view of every `.dm` under `code/`. A site kept by `// ALLOW(door_gates): <reason>` does not count.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

static META: Meta = Meta {
    name: "door_gates",
    group: "",
    label: "door_gates",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Sites {
        baseline: "tools/ci/door_gates_baseline.txt",
        header: &[
            "Hand-written door gates (final_api section 8, spaces and doors). rule<TAB>file<TAB>normalized line.",
            "`analyze check --lint door_gates` fails on a site not listed here. A site with",
            "`// ALLOW(door_gates): <reason>` doesn't count.",
            "Shrink-only: after a sweep, `analyze baseline --update --lint door_gates`.",
        ],
        banned: &[],
    },
    rules: &[
        RuleMeta {
            name: "when_door",
            hint: "place the op in the space the door closes: at(SPACE_X) (code/engine/library/spaces.dm); a closed door sets it aside for another candidate and refuses with its reason when nothing else answers",
        },
        RuleMeta {
            name: "req_door",
            hint: "a door that must be open: at(SPACE_X); one that must be shut: req_closed(SPACE_X); a door that must not move: latch() or protrudes()",
        },
        RuleMeta {
            name: "req_built_put",
            hint: "a slot that exists only from a construction stage sits in a staged space: space(SPACE_X, from_stage = STAGE_Y, missing = MSG(...))",
        },
    ],
    allow: &["door_gates"],
    lists: &[],
};

struct DoorGates {
    when_door: Pat,
    req_door: Pat,
    req_built: Pat,
    puts: Pat,
}

impl Lint for DoorGates {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if f.rel.starts_with("code/engine/_generated/") {
            return; // the generator's copy of a declaration; the site is counted where it is written
        }
        for (no, line) in f.code().numbered() {
            let rule = if self.when_door.is_match(line) {
                Some("when_door")
            } else if self.req_door.is_match(line) {
                Some("req_door")
            } else if self.req_built.is_match(line) && self.puts.is_match(f.line(no)) {
                // The put is named by the op key, a string (`"cell_bay.cell.insert"`), which the code view blanks: read it raw.
                Some("req_built_put")
            } else {
                None
            };
            if let Some(rule) = rule {
                if !out.allowed(f, no, "door_gates") {
                    out.site(rule, no);
                }
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(DoorGates {
        when_door: Pat::new(r"\bwhen\(\s*(cond_(all|any)\(\s*)?(COVER_OPEN\b|PANEL_OPEN\b|nameof\(\s*(panel_open|opened)\s*\)\s*\))"),
        req_door: Pat::new(r"\breq_is\(\s*(COVER_OPEN\b|PANEL_OPEN\b|nameof\(\s*panel_open\s*\))|\breq_panel_closed\("),
        req_built: Pat::new(r"\breq_built\("),
        puts: Pat::new(r"\.insert\b|\bput_in\("),
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tree::Tree;

    #[test]
    fn counts_the_hand_written_gates() {
        let tree = Tree::from_files(vec![]);
        let scope = crate::scopes::LintScope::default();
        let cx = Cx { tree: &tree, meta: &META, scope: &scope };
        let f = SourceFile::from_text(
            "code/a.dm",
            "\textend(\"cell_bay.cell.take\", when(COVER_OPEN))\n\top(\"x\", hand(), at(SPACE_PANEL))\n\tneeds(req_panel_closed())\n\textend(\"cell_bay.cell.insert\", needs(req_built(STAGE_X)))\n\tlook_layer(L, when = PANEL_OPEN)\n",
        );
        let mut out = Sink::new();
        out.cur = f.rel.clone();
        let mut reg = Registry::default();
        register(&mut reg);
        reg.lints[0].scan_file(&cx, &f, &mut out);
        let lines: Vec<u32> = out.sites.iter().map(|s| s.line).collect();
        assert_eq!(lines, vec![1, 3, 4]);
    }
}
