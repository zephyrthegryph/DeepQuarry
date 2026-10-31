//! Port of `tools/ci/sys_rules/dx_raw_overlays.py`: raw overlay writes outside the look builder
//! (design review M9). `add_overlay(` / `cut_overlay(` / `cut_overlays(` / `overlays +=` /
//! `overlays -=` outside the look builder. A hard ban: the baseline is empty. The engine files that compile looks to overlays are
//! exempt by path in `[lint."sys/dx_raw_overlays"]` of tools/ci/lint_scopes.toml.

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;

const RULES: &[RuleMeta] = &[RuleMeta {
    name: "dx_raw_overlays",
    hint: "draw the layer in draw(datum/look/look) (look.overlay/glow/gauge), not a raw overlay write (design review M9)",
}];

/// `scan_file` of the Python: one site per sanitized line with a raw overlay write.
fn scan_lines(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    let raw = pat!(r"(?<![\w/])(?:add_overlay|cut_overlays?)\s*\(|(?<![\w/])overlays\s*[-+]=");
    for (number, code) in f.clean().numbered() {
        // Both alternatives need the word "overlay" in the line.
        if code.contains("overlay") && raw.is_match(code) {
            out.push(("dx_raw_overlays", number));
        }
    }
}

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    scan_lines(f, out);
}

fn selftest() -> Result<String, String> {
    let fixture = [
        "add_overlay(\"lights\")",
        "A.cut_overlay(old)",
        "overlays += image(icon, \"x\")",
        "src.overlays -= glow",
        "cut_overlays()",
        "look.overlay(\"lights\")",
        "// add_overlay(x)",
        "/atom/proc/add_overlay(list/add_overlays, priority)",
        "var/list/my_overlays = list()",
        "add_overlay_lighting(src, 3, 1)",
        "overlays == null",
    ];
    let f = SourceFile::from_text("x.dm", &fixture.join("\n"));
    let mut v = Vec::new();
    scan_lines(&f, &mut v);
    let got: Vec<usize> = v.into_iter().map(|(_, n)| n).collect();
    if got != vec![1, 2, 3, 4, 5] {
        return Err(format!("dx_raw_overlays selftest: got {:?}", got));
    }
    Ok("dx_raw_overlays".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: "dx_raw_overlays", rules: RULES, file_scan: Some(scan_file), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
