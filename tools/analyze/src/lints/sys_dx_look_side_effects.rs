//! Port of `tools/ci/sys_rules/dx_look_side_effects.py`: appearance outputs write no state and
//! play no sounds (G12; doc/rewrite/look.md section 3). `appearance_overlays()` and any proc a
//! `DECLARE_APPEARANCE_PROC(...)` row names are held to dx_reactive's `reactive_writes` test.

use std::collections::HashSet;

use crate::dm::dx::DxIndex;
use crate::dm::dx_reactive::{member_writer, reactive_writes, writer_call};
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::tree::{SourceFile, Tree};
use crate::{pat, pat_match};

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "dx_appearance_side_effect",
    hint: "appearance procs (appearance_overlays, DECLARE_APPEARANCE_PROC rows; draw() is dx_reactive_write's) write no state and play no sound: move it to the handler or setter that changes the state (G12)",
}];

/// The proc names one file's `DECLARE_APPEARANCE_PROC(...)` rows name (per-file facts, cached by content).
fn names_in_file(f: &SourceFile) -> Vec<String> {
    let row = pat!(r"\bDECLARE_APPEARANCE_PROC\s*\(\s*/[\w/]+\s*,\s*(?:TYPE_PROC_REF\(\s*[/\w]+\s*,\s*(\w+)\s*\)|PROC_REF\(\s*(\w+)\s*\))");
    let mut out: Vec<String> = Vec::new();
    for line in f.clean().lines() {
        if !line.contains("DECLARE_APPEARANCE_PROC") {
            continue;
        }
        for m in row.captures_iter(line) {
            out.push(if m.matched(1) { m.s(1) } else { m.s(2) }.to_string());
        }
    }
    out.sort();
    out.dedup();
    out
}

/// `appearance_proc_names`: `ALWAYS` plus every proc a DECLARE_APPEARANCE_PROC row names.
fn appearance_proc_names(files: &[&SourceFile]) -> HashSet<String> {
    let mut names: HashSet<String> = HashSet::new();
    names.insert("appearance_overlays".to_string());
    for per_file in crate::incr::facts("sys-dx-look-names", files, names_in_file) {
        names.extend(per_file);
    }
    names
}

fn has_writer_call(text: &str) -> bool {
    writer_call().is_match(text) || member_writer().is_match(text)
}

fn scan(tree: &Tree, files: &[&SourceFile]) -> Vec<(&'static str, String, usize)> {
    let mut out = Vec::new();
    let idx = DxIndex::get(tree, files);
    let names = appearance_proc_names(files);
    // `icon_state = "x"` / `src.overlays += y`: the proc's own output, not a side effect.
    let appearance_write = pat_match!(
        r"\s*(?:src\s*\.\s*)?(?:icon_state|icon|overlays|underlays|color|alpha|layer|plane|transform|pixel_x|pixel_y|pixel_w|pixel_z)\s*(?:=(?!=)|\+=|-=|\|=)"
    );
    for proc in &idx.procs {
        if !names.contains(&proc.name) || proc.path == "/atom" || proc.path == "/datum" {
            continue;
        }
        let lines = proc.lines(tree);
        for number in reactive_writes(proc, tree) {
            let text = lines.iter().find(|(n, _)| *n == number).map(|(_, t)| *t).unwrap_or("");
            if appearance_write.is_match(text) && !has_writer_call(text) {
                continue;
            }
            out.push(("dx_appearance_side_effect", proc.rel.clone(), number));
        }
    }
    out
}

const FIXTURE: &str = "
/obj/machinery/vent/appearance_overlays()
\tvar/list/parts = list()
\tparts += \"on\"
\ticon_state = \"vent\"
\tif(welded)
\t\tplaysound(src, 'sound/weld.ogg', 50)
\tlast_state = \"on\"
\treturn parts

/obj/machinery/quiet/appearance_overlays()
\tvar/list/parts = list()
\tparts += \"idle\"
\treturn parts

DECLARE_APPEARANCE_PROC(/obj/machinery/custom, TYPE_PROC_REF(/obj/machinery/custom, custom_look), list())

/obj/machinery/custom/proc/custom_look()
\ticon_state = \"custom\"
\ton = TRUE
\treturn list()
";

fn selftest() -> Result<String, String> {
    let lines: Vec<&str> = FIXTURE.split('\n').collect();
    let tree = Tree::from_files(vec![SourceFile::from_text("code/fixture.dm", FIXTURE)]);
    let files = vec![tree.get("code/fixture.dm").unwrap()];
    let mut got: Vec<usize> = scan(&tree, &files).into_iter().map(|(_, _, n)| n).collect();
    got.sort();
    let bad = ["\t\tplaysound(src, 'sound/weld.ogg', 50)", "\tlast_state = \"on\"", "\ton = TRUE"];
    let mut want: Vec<usize> = bad.iter().map(|t| lines.iter().position(|l| l == t).map(|k| k + 1).unwrap_or(0)).collect();
    want.sort();
    if got != want {
        return Err(format!("dx_look_side_effects selftest: got {:?}, want {:?}", got, want));
    }
    Ok("true".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: "dx_look_side_effects", rules: RULES, files_scan: Some(scan), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
