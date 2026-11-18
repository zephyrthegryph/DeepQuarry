//! Port of `tools/ci/sys_rules/dx_manual_transfer.py`: hand-rolled transfers the one-call
//! own_set / own_add / own_put replaces (doc/rewrite/ownership.md section 1.3a).
//!
//!   manual_transfer    an own_* call within a few lines of a take-out call in the same proc
//!   manual_move_adopt  `X.forceMove(H)` right before `own_*(H, "var", X)`

use crate::raw_fixture_policy::PatternApi as _;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;
use crate::util::before_slashes;

use crate::allow_registry_fields::sys_dx_manual_transfer::RULES;

const BEFORE: usize = 5; // lines looked at before an own_* call
const AFTER: usize = 2; // and after it (the take-out written second)

const EXEMPT_PREFIXES: &[&str] = &["code/library/ownership/", "code/library/containers/containment/"];

fn holder(name: &str) -> &str {
    if name == "src" || name.is_empty() {
        "src"
    } else {
        name
    }
}

fn scan_file(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){scan_file_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")}
fn scan_file_using(f:&SourceFile,out:&mut Vec<(&'static str,usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    fixture.check()?;
    if EXEMPT_PREFIXES.iter().any(|p| f.rel.starts_with(p)) {
        return Ok(());
    }
    let own = fixture.pattern(r"\bown_(?:set|add|put)\s*\(\s*([\w.]+)\s*,\s*(?:nameof\([^()]*\)|[^,()]+)\s*,\s*(?:[^,()]+,\s*)?([\w.]+)\s*[,)]",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"\bown_(?:set|add|put)\s*\(\s*([\w.]+)\s*,\s*(?:nameof\([^()]*\)|[^,()]+)\s*,\s*(?:[^,()]+,\s*)?([\w.]+)\s*[,)]"));
    let take_out = fixture.pattern(r"\b(drop_item|drop_from_inventory|unEquip|remove_from_mob|drop_l_hand|drop_r_hand|drop_active_hand|remove_from_storage)\s*\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"\b(drop_item|drop_from_inventory|unEquip|remove_from_mob|drop_l_hand|drop_r_hand|drop_active_hand|remove_from_storage)\s*\("));
    let mv = fixture.pattern(r"([\w.]+)\s*\??\.\s*forceMove\s*\(\s*([\w.]+)\s*\)|([\w.]+)\.loc\s*=\s*([\w.]+)\s*$",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"([\w.]+)\s*\??\.\s*forceMove\s*\(\s*([\w.]+)\s*\)|([\w.]+)\.loc\s*=\s*([\w.]+)\s*$"));
    let code: Vec<&str> = fixture.collect(f.raw().lines().map(before_slashes))?;
    for (i, text) in code.iter().enumerate() {
        let Some(m) = fixture.captures(&own,text)? else { continue };
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
            for mm in fixture.captures_iter(&mv,code[j])? {
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
            fixture.push(out,("manual_transfer", i + 1))?;
        } else if moved {
            fixture.push(out,("manual_move_adopt", i + 1))?;
        }
    }
    Ok(())
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
    selftest_with_fixture(&crate::raw_fixture_policy::Fixture::legacy())
}

fn selftest_with_fixture(fixture: &crate::raw_fixture_policy::Fixture<'_>) -> Result<String, String> {
    let lines: Vec<&str> = fixture.collect(SELFTEST_FIXTURE.split('\n'))?;
    let run = |rel: &str| {
        let f = fixture.file(rel, SELFTEST_FIXTURE)?;
        let mut v = Vec::new();
        scan_file_using(&f,&mut v,fixture)?;
        Ok::<_, String>(v)
    };
    let got = run("code/x.dm")?;
    let at_all = |snippet: &str| -> Result<Vec<usize>,String> { fixture.collect(lines.iter().enumerate().filter(|(_, l)| l.contains(snippet)).map(|(k, _)| k + 1)) };
    let mut transfer: Vec<usize> = fixture.collect(got.iter().filter(|(r, _)| *r == "manual_transfer").map(|(_, n)| *n))?;
    fixture.sort_ord(&mut transfer)?;
    let mut want = fixture.collect([at_all("own_set(src, nameof(src.cell), C)")?[0], at_all("own_add(src, nameof(src.parts), I)")?[0]])?;
    fixture.sort_ord(&mut want)?;
    if transfer != want {
        return Err(fixture.detail(format_args!("dx_manual_transfer selftest: manual_transfer got {:?}, want {:?}", transfer, want))?);
    }
    let adopt: Vec<usize> = fixture.collect(got.iter().filter(|(r, _)| *r == "manual_move_adopt").map(|(_, n)| *n))?;
    if adopt != [at_all("own_set(src, nameof(src.cell), C)")?[1]] {
        return Err(fixture.detail(format_args!("dx_manual_transfer selftest: manual_move_adopt got {:?}", adopt))?);
    }
    if run("code/library/ownership/x.dm")?.iter().any(|(r, _)| *r == "manual_transfer") {
        return Err(fixture.own("dx_manual_transfer selftest: the framework is exempt")?);
    }
    Ok(fixture.own("dx_manual_transfer")?)
}

pub fn register(reg: &mut Registry) {
    register_module(
        reg,
        SysModule { name: crate::allow_registry_fields::sys_dx_manual_transfer::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan_file), fixture_file_scan:Some(scan_file_using), selftest: Some(selftest), fixture_selftest: Some(selftest_with_fixture), py_selftest: true, ..SysModule::DEFAULT },
    );
}
