//! Port of `tools/ci/sys_rules/dx_manual_transfer.py`: hand-rolled transfers the one-call
//! own_set / own_add / own_put replaces (doc/rewrite/ownership.md section 1.3a).
//!
//!   manual_transfer    an own_* call within a few lines of a take-out call in the same proc
//!   manual_move_adopt  `X.forceMove(H)` right before `own_*(H, "var", X)`

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

const RULES: &[RuleMeta] = &[
    RuleMeta {
        name: "manual_transfer",
        hint: "own_set/own_add/own_put(holder, nameof(holder.var), item, user = user): one call takes it out of the hand, slot or storage (ownership.md §1.3a)",
    },
    RuleMeta {
        name: "manual_move_adopt",
        hint: "own_set/own_add/own_put(holder, nameof(holder.var), item, into = TRUE) moves it in itself (ownership.md §1.3a)",
    },
];

const BEFORE: usize = 5; // lines looked at before an own_* call
const AFTER: usize = 2; // and after it (the take-out written second)

const EXEMPT_PREFIXES: &[&str] = &["code/datums/ownership/", "code/datums/containment/"];

fn holder(name: &str) -> &str {
    if name == "src" || name.is_empty() {
        "src"
    } else {
        name
    }
}

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    if EXEMPT_PREFIXES.iter().any(|p| f.rel.starts_with(p)) {
        return;
    }
    let own = pat!(r"\bown_(?:set|add|put)\s*\(\s*([\w.]+)\s*,\s*(?:nameof\([^()]*\)|[^,()]+)\s*,\s*(?:[^,()]+,\s*)?([\w.]+)\s*[,)]");
    let take_out = pat!(r"\b(drop_item|drop_from_inventory|unEquip|remove_from_mob|drop_l_hand|drop_r_hand|drop_active_hand|remove_from_storage)\s*\(");
    let mv = pat!(r"([\w.]+)\s*\??\.\s*forceMove\s*\(\s*([\w.]+)\s*\)|([\w.]+)\.loc\s*=\s*([\w.]+)\s*$");
    let code: Vec<&str> = f.raw().lines().map(before_slashes).collect();
    for (i, text) in code.iter().enumerate() {
        let Some(m) = own.captures(text) else { continue };
        let hold = holder(m.s(1));
        let value = m.s(2);
        let mut took = false;
        let mut moved = false;
        // range(i - 1, max(-1, i - BEFORE - 1), -1)
        let low = i.saturating_sub(BEFORE);
        let mut j = i;
        while j > low {
            j -= 1;
            if code[j].starts_with('/') {
                break; // the proc header: another proc above
            }
            if take_out.is_match(code[j]) {
                took = true;
            }
            for mm in mv.captures_iter(code[j]) {
                let what = if mm.matched(1) { mm.s(1) } else { mm.s(3) };
                let where_ = holder(if mm.matched(2) { mm.s(2) } else { mm.s(4) });
                if what == value && where_ == hold {
                    moved = true;
                }
            }
        }
        for line in code.iter().take((i + AFTER + 1).min(code.len())).skip(i + 1) {
            if line.starts_with('/') {
                break;
            }
            if take_out.is_match(line) {
                took = true;
            }
        }
        if took {
            out.push(("manual_transfer", i + 1));
        } else if moved {
            out.push(("manual_move_adopt", i + 1));
        }
    }
}

const SELFTEST_FIXTURE: &str = "/obj/machinery/charger/proc/insert_cell(mob/user, obj/item/cell/C)
\tif(!user.drop_item())
\t\treturn
\town_set(src, nameof(src.cell), C)
/obj/machinery/charger/proc/move_then_adopt(obj/item/cell/C)
\tC.forceMove(src)
\town_set(src, nameof(src.cell), C)
/obj/machinery/charger/proc/one_call(mob/user, obj/item/cell/C)
\town_set(src, nameof(src.cell), C, user = user)
/obj/machinery/charger/proc/take_after(mob/user, obj/item/I)
\town_add(src, nameof(src.parts), I)
\tuser.unEquip(I)
/obj/machinery/charger/proc/other_thing(obj/item/cell/C, obj/item/D)
\tD.forceMove(src)
\town_set(src, nameof(src.cell), C)
";

fn selftest() -> Result<String, String> {
    let lines: Vec<&str> = SELFTEST_FIXTURE.split('\n').collect();
    let run = |rel: &str| {
        let f = SourceFile::from_text(rel, SELFTEST_FIXTURE);
        let mut v = Vec::new();
        scan_file(&f, &mut v);
        v
    };
    let got = run("code/x.dm");
    let at_all = |snippet: &str| -> Vec<usize> { lines.iter().enumerate().filter(|(_, l)| l.contains(snippet)).map(|(k, _)| k + 1).collect() };
    let mut transfer: Vec<usize> = got.iter().filter(|(r, _)| *r == "manual_transfer").map(|(_, n)| *n).collect();
    transfer.sort();
    let mut want = vec![at_all("own_set(src, nameof(src.cell), C)")[0], at_all("own_add(src, nameof(src.parts), I)")[0]];
    want.sort();
    if transfer != want {
        return Err(format!("dx_manual_transfer selftest: manual_transfer got {:?}, want {:?}", transfer, want));
    }
    let adopt: Vec<usize> = got.iter().filter(|(r, _)| *r == "manual_move_adopt").map(|(_, n)| *n).collect();
    if adopt != vec![at_all("own_set(src, nameof(src.cell), C)")[1]] {
        return Err(format!("dx_manual_transfer selftest: manual_move_adopt got {:?}", adopt));
    }
    if run("code/datums/ownership/x.dm").iter().any(|(r, _)| *r == "manual_transfer") {
        return Err("dx_manual_transfer selftest: the framework is exempt".to_string());
    }
    Ok("dx_manual_transfer".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: "dx_manual_transfer", rules: RULES, file_scan: Some(scan_file), selftest: Some(selftest), py_selftest: true, ..SysModule::DEFAULT },
    );
}
