//! The door-gate ratchet (doc/rewrite/final_api.html section 8 "Spaces and doors").
//!
//! Things behind covers and panels work by physical paths: an op, slot or graph placed `at(SPACE_X)` is reachable only through open doors,
//! a latch or a protrusion holds a door, a staged space exists from its construction stage, a slot's `fits =` says what it accepts. This lint
//! counts the hand-written gates the path system replaces, so their number can only fall:
//!
//!   when_door      `when(COVER_OPEN)`, `when(PANEL_OPEN)`, `when(nameof(opened))`, `when(nameof(panel_open))`: an op silenced while a door is
//!                  shut (an op of the outside that works while it is shut, `when(not(nameof(opened)))`, is not a path and is not counted)
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
    name: crate::allow_registry_fields::door_gates::SCOPE_META_0.name,
    group: crate::allow_registry_fields::door_gates::SCOPE_META_0.group,
    label: "door_gates",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
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
    allow: crate::allow_registry_fields::door_gates::ALLOW_0,
    lists: crate::allow_registry_fields::door_gates::SCOPE_META_0.lists,
};

const DOOR_PATTERN_SOURCES:&[&str]=&[r"\bwhen\(\s*(cond_(all|any)\(\s*)?(COVER_OPEN\b|PANEL_OPEN\b|nameof\(\s*(panel_open|opened)\s*\)\s*\))",r"\breq_is\(\s*(COVER_OPEN\b|PANEL_OPEN\b|nameof\(\s*panel_open\s*\))|\breq_panel_closed\(",r"\breq_built\(",r"\.insert\b|\bput_in\("];
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

    fn scan_file(&self,_cx:&Cx,f:&SourceFile,out:&mut Sink){scan_using(f,out,&self.when_door,&self.req_door,&self.req_built,&self.puts)}
}

pub fn register(reg: &mut Registry) {
    reg.add(DoorGates {
        when_door: Pat::new(DOOR_PATTERN_SOURCES[0]),
        req_door: Pat::new(DOOR_PATTERN_SOURCES[1]),
        req_built: Pat::new(DOOR_PATTERN_SOURCES[2]),
        puts: Pat::new(DOOR_PATTERN_SOURCES[3]),
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
        let cx = Cx { fixture:None, tree: &tree, meta: &META, scope: &scope };
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

fn scan_using<P:crate::raw_fixture_policy::PatternApi>(f:&SourceFile,out:&mut Sink,when_door:&P,req_door:&P,req_built:&P,puts:&P){
        if f.rel.starts_with("code/engine/_generated/") {
            return; // the generator's copy of a declaration; the site is counted where it is written
        }
        for (no, line) in f.code().numbered() {
            let rule = if when_door.is_match(line) {
                Some("when_door")
            } else if req_door.is_match(line) {
                Some("req_door")
            } else if req_built.is_match(line) && puts.is_match(f.line(no)) {
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

#[cfg(feature="native-policy")]
struct NativeDoorGates{legacy:std::sync::OnceLock<DoorGates>}
#[cfg(feature="native-policy")]
impl Lint for NativeDoorGates{
 fn meta(&self)->&Meta{&META}
 fn scan_file(&self,cx:&Cx,f:&SourceFile,out:&mut Sink){
  if let Some(fixture)=cx.fixture{
   let when_door=fixture.pattern(DOOR_PATTERN_SOURCES[0],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(DOOR_PATTERN_SOURCES[0]));
   let req_door=fixture.pattern(DOOR_PATTERN_SOURCES[1],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(DOOR_PATTERN_SOURCES[1]));
   let req_built=fixture.pattern(DOOR_PATTERN_SOURCES[2],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(DOOR_PATTERN_SOURCES[2]));
   let puts=fixture.pattern(DOOR_PATTERN_SOURCES[3],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(DOOR_PATTERN_SOURCES[3]));
   scan_using(f,out,&when_door,&req_door,&req_built,&puts)
  }else{self.legacy.get_or_init(||DoorGates{when_door:Pat::new(DOOR_PATTERN_SOURCES[0]),req_door:Pat::new(DOOR_PATTERN_SOURCES[1]),req_built:Pat::new(DOOR_PATTERN_SOURCES[2]),puts:Pat::new(DOOR_PATTERN_SOURCES[3])}).scan_file(cx,f,out)}
 }
}
#[cfg(feature="native-policy")]
pub fn register_native(reg:&mut Registry){reg.add(NativeDoorGates{legacy:std::sync::OnceLock::new()})}
