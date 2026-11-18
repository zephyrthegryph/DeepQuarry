//! The machine review's lints (rewrite/machines-full): shapes the machine conversions kept finding, as shrink-only ratchets.
//!
//! - `effect_refusal`     an op effect (a proc taking `datum/act/op/A`) that tells the actor why (`to_chat`, `atom_say`, `balloon_alert`, `act_message`,
//!                        `A.reason =`) and then returns `OP_REFUSED`: the refusal is a requirement (`needs(req(...))`), not a message
//!                        and a return at the head of the effect.
//! - `request_in_effect`  `open_request()` inside an op effect: the op asks with `asks()` (a workflow step), so the answer resumes the op.
//! - `nameof_unrelated`   `nameof(/type::var)` naming a type that is neither the proc's own type, an ancestor nor a descendant of it
//!                        (by path): the var is not the holder's.
//! - `unkeyed_wire_after` an `after()` with no `key =` in a wire or pulse handler: a second pulse stacks a second timer; a keyed one
//!                        replaces it (or the wire is a timed hold, wires()).
//! - `manual_push`        a hand call of `push_to_rust()` or the legacy `changed(E, channel)`: the push is generated, once per frame, from
//!                        the state it reads.
//! - `output_side_effect` an output (`ui_data`, `draw`, an `appearance_*` proc) that speaks or plays a sound (`to_chat`, `atom_say`,
//!                        `playsound`, `play_sfx`, `balloon_alert`); and a look (`draw(look)`, a chain's `look_parts(look)`) that changes an atom
//!                        (`update_icon`, `update_held_icon`, `update_inv_*`, `regenerate_icons`, `add_overlay`, `cut_overlay(s)`, `set_light`,
//!                        `forceMove`, on src or through another object). Outputs are read whenever a window or the look refreshes, and the
//!                        look is applied by the engine.
//! - `undef_then_used`    a `#undef X` followed, in the same file, by a use of X that no later `#define X` covers.
//!
//! `effect_refusal` does not flag `return OP_REFUSED` inside an `if(... ACT_REFUSED_BY(x))` block (it relays an ACT_ATTEMPT hook's
//! veto, section 8) or in the block of an `act_cancel(` (the commit failed after the action began): neither is
//! known before the effect runs, so neither can be a requirement.
//!
//! Unit tests and the engine's own directories are exempt.

use crate::raw_fixture_policy::PatternApi as _;
use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;

use crate::allow_registry_fields::sys_dx_review::RULES;

const EXEMPT_PREFIXES: &[&str] = &["code/tests/unit_tests/", "code/tests/", "code/engine/", "code/__defines/", "code/defines/engine/", "code/defines/library/", "code/defines/host/", "code/defines/base/", "code/defines/content/"];

/// The proc a line belongs to: its type path, its name, whether it is an op effect, and whether it is an output.
struct ProcCtx<'a> {
    type_path: &'a str,
    name: &'a str,
    effect: bool,
    output: bool,
    /// draw(look) or look_parts(look): the look builder's procs, which change no atom either.
    look: bool,
    told: bool,
    /// Indent of an `if(... ACT_REFUSED_BY(x) ...)` whose block is open: a refusal there relays the hook's veto (the doc's commit-time veto).
    relay_indent: Option<usize>,
    /// Indent of the block an `act_cancel(` ran in: the commit failed (a link did not take, the mob did not arrive) and the act was cancelled.
    cancel_indent: Option<usize>,
}

/// Leading tabs of a line (DM source here is tab-indented).
fn indent_of(code: &str) -> usize {
    code.chars().take_while(|c| *c == '\t').count()
}

/// `/a/b/proc/name(args` or `/a/b/name(args` at column 0: (type, name, args).
fn header_using<'a>(line:&'a str,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<Option<(&'a str,&'a str,&'a str)>,String>{
    let Some(caps) = fixture.captures(&fixture.pattern(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\((.*)$",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\((.*)$")),line)? else{return Ok(None)};
    Ok(caps.get(1).zip(caps.get(2)).zip(caps.get(3)).map(|((owner,name),args)|(owner,name,args)))
}

/// A or B is the other's ancestor by path (the parent_type a type declares is not followed).
fn related(a: &str, b: &str) -> bool {
    a == b || a.strip_prefix(b).is_some_and(|tail|tail.starts_with('/')) || b.strip_prefix(a).is_some_and(|tail|tail.starts_with('/'))
}

fn scan_lines(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){
    scan_lines_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")
}
fn scan_lines_using(f:&SourceFile,out:&mut Vec<(&'static str,usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    fixture.check()?;
    let mut ctx: Option<ProcCtx<'_>> = None;
    let mut block_type: Option<&str> = None;
    let mut undefs: Vec<(&str, usize)> = Vec::new();
    for (number, code) in f.code().numbered() {
        // ---- the #undef rule works on the whole file ----
        if let Some(c) = fixture.captures(&fixture.pattern(r"^\s*#undef\s+(\w+)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^\s*#undef\s+(\w+)")),code)? {
            fixture.push(&mut undefs,(c.s(1), number))?;
            continue;
        }
        if let Some(c) = fixture.captures(&fixture.pattern(r"^\s*#define\s+(\w+)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^\s*#define\s+(\w+)")),code)? {
            let name = c.s(1);
            undefs.retain(|(n, _)| *n != name);
            continue;
        }
        for (name, _) in &undefs {
            if code.contains(*name) && fixture.find_iter(&fixture.pattern(r"\w+",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"\w+")),code)?.iter().any(|word|word.as_str()==*name) {
                fixture.push(out,("undef_then_used", number))?;
                break;
            }
        }

        // ---- where the line is ----
        let at_col0 = !code.is_empty() && !code.starts_with(|c: char| c.is_whitespace());
        if at_col0 {
            ctx = None;
            block_type = None;
            if let Some(c) = fixture.captures(&fixture.pattern(r"^CAPABILITIES(?:_PART)?\((/[\w/]+)[,)]",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^CAPABILITIES(?:_PART)?\((/[\w/]+)[,)]")),code)? {
                block_type = Some(c.s(1));
            } else if let Some((type_path, name, args)) = header_using(code,fixture)? {
                let effect = args.contains("datum/act/op/");
                let look = matches!(name, "draw" | "look_parts") && args.contains("look");
                let output = look || matches!(name, "ui_data" | "tgui_data" | "appearance_overlays" | "appearance_state");
                ctx = Some(ProcCtx { type_path, name, effect, output, look, told: false, relay_indent: None, cancel_indent: None });
            }
            continue;
        }
        let owner = ctx.as_ref().map(|c| c.type_path).or(block_type);

        // nameof(/type::var) of a type unrelated to the holder: an accessor on src, or an entry of the type's own block (a relation's
        // other end, back = ..., names the other type's var and is fine; so does target_key =, the id var of the keyed targets)
        if let Some(owner) = owner {
            if code.contains("nameof(/") {
                let found = if ctx.is_some() {
                    fixture.captures_iter(&fixture.pattern(r"\w+\(\s*src\s*,\s*nameof\((/[\w/]+)::\w+\)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"\w+\(\s*src\s*,\s*nameof\((/[\w/]+)::\w+\)")),code)?
                } else {
                    fixture.captures_iter(&fixture.pattern(r"(?<!back = )(?<!target_key = )nameof\((/[\w/]+)::\w+\)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<!back = )(?<!target_key = )nameof\((/[\w/]+)::\w+\)")),code)?
                };
                for c in found {
                    let named = c.s(1);
                    if !related(named, &owner) && !named.starts_with("/datum/capability") && !owner.starts_with("/datum/capability") {
                        fixture.push(out,("nameof_unrelated", number))?;
                        break;
                    }
                }
            }
        }

        // a hand push
        if fixture.pattern(r"(?<![\w.:/])push_to_rust\(\)|(?<![\w.:/])changed\(\s*\w+\s*,\s*CHANGE_",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w.:/])push_to_rust\(\)|(?<![\w.:/])changed\(\s*\w+\s*,\s*CHANGE_")).is_match(code) {
            fixture.push(out,("manual_push", number))?;
        }

        let Some(c) = ctx.as_mut() else { continue };
        if c.effect {
            if fixture.pattern(r"(?<![\w.])open_request\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w.])open_request\(")).is_match(code) {
                fixture.push(out,("request_in_effect", number))?;
            }
            if fixture.pattern(r"(?<![\w])(to_chat|atom_say|balloon_alert|act_message)\(|\bA\.reason\s*=",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w])(to_chat|atom_say|balloon_alert|act_message)\(|\bA\.reason\s*=")).is_match(code) {
                c.told = true;
            }
            let indent = indent_of(code);
            if c.relay_indent.is_some_and(|r| indent <= r) {
                c.relay_indent = None;
            }
            if c.cancel_indent.is_some_and(|k| indent < k) {
                c.cancel_indent = None;
            }
            if fixture.pattern(r"^\s*(?:if|else if)\(.*\bACT_REFUSED_BY\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^\s*(?:if|else if)\(.*\bACT_REFUSED_BY\(")).is_match(code) {
                c.relay_indent = Some(indent);
            }
            if fixture.pattern(r"(?<![\w.])act_cancel\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w.])act_cancel\(")).is_match(code) {
                c.cancel_indent = Some(indent);
            }
            // A refusal that relays an ACT_ATTEMPT hook's veto, or follows an act_cancel in its own block, is the doc's commit-time
            // veto or a failed commit: it cannot be a requirement, because it is known only when the effect runs.
            let relayed = c.relay_indent.is_some_and(|r| indent > r) || c.cancel_indent == Some(indent);
            if c.told && !relayed && fixture.pattern(r"\breturn\s+OP_REFUSED\b",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"\breturn\s+OP_REFUSED\b")).is_match(code) {
                fixture.push(out,("effect_refusal", number))?;
            }
        }
        if c.output && fixture.pattern(r"(?<![\w.])(to_chat|atom_say|playsound|play_sfx|balloon_alert)\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w.])(to_chat|atom_say|playsound|play_sfx|balloon_alert)\(")).is_match(code) {
            fixture.push(out,("output_side_effect", number))?;
        } else if c.look
            && fixture.captures_iter(&fixture.pattern(r"(?<![\w.])((?:[A-Za-z_]\w*(?:\(\))?\s*\??\.\s*)*)(update_icon|update_held_icon|update_inv_\w+|regenerate_icons|add_overlay|cut_overlays?|set_light|set_light_on|forceMove)\s*\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w.])((?:[A-Za-z_]\w*(?:\(\))?\s*\??\.\s*)*)(update_icon|update_held_icon|update_inv_\w+|regenerate_icons|add_overlay|cut_overlays?|set_light|set_light_on|forceMove)\s*\(")),code)?
                .iter()
                .any(|m| !m.s(1).trim_start().starts_with("look"))
        {
            fixture.push(out,("output_side_effect", number))?;
        }
        if (c.name.contains("pulse") || c.name.contains("wire")) && fixture.pattern(r"(?<![\w.])after\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w.])after\(")).is_match(code) && !code.contains("key =") && !code.contains("key=") {
            fixture.push(out,("unkeyed_wire_after", number))?;
        }
    }
    Ok(())
}

fn scan_file(f:&SourceFile,out:&mut Vec<(&'static str,usize)>){
    scan_file_using(f,out,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy scanner has no admission refusal")
}
fn scan_file_using(f:&SourceFile,out:&mut Vec<(&'static str,usize)>,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<(),String>{
    if EXEMPT_PREFIXES.iter().any(|p| f.rel.starts_with(p)) {
        return Ok(());
    }
    scan_lines_using(f,out,fixture)?;
    Ok(())
}

fn selftest() -> Result<String, String> {
    selftest_with_fixture(&crate::raw_fixture_policy::Fixture::legacy())
}

fn selftest_with_fixture(fixture: &crate::raw_fixture_policy::Fixture<'_>) -> Result<String, String> {
    let fixture_lines = [
        "/obj/machinery/x/proc/vend(datum/act/op/A)",          // 1
        "\tif(!ready)",                                         // 2
        "\t\tto_chat(A.actor, \"no\")",                         // 3
        "\t\treturn OP_REFUSED",                                // 4 effect_refusal
        "\topen_request(A, /datum/prompt/text)",                // 5 request_in_effect
        "\trel_set(src, nameof(/obj/item/card::name), x)",      // 6 nameof_unrelated
        "\trel_set(owner, nameof(/mob::hud_used), src)",        // 7 another entity's var: fine
        "/obj/machinery/x/proc/pulse_wire(datum/act/A)",        // 8
        "\tafter(src, 5 SECONDS, PROC_REF(reset))",             // 9 unkeyed_wire_after
        "\tafter(src, 5 SECONDS, PROC_REF(reset), key = \"r\")", // 10
        "\tpush_to_rust()",                                     // 11 manual_push
        "/obj/machinery/x/ui_data(datum/act/eval/A)",           // 12
        "\tto_chat(world, \"x\")",                              // 13 output_side_effect
        "#define FOO 1",                                        // 14
        "#undef FOO",                                           // 15
        "/proc/bar()",                                          // 16
        "\treturn FOO",                                         // 17 undef_then_used
        "/obj/machinery/x/proc/fine(datum/act/op/A)",           // 18
        "\treturn OP_REFUSED",                                  // 19 nothing told: fine
        "/obj/item/x/draw(datum/look/look)",                    // 20
        "\tlook.overlay(\"a\")",                                // 21 the look: fine
        "\tholder.update_inv_l_hand()",                         // 22 output_side_effect: another atom
        "\tloc.update_icon()",                                  // 23 output_side_effect
        "\tlook.glow(2, 1)",                                    // 24 fine
        "/obj/x/proc/relay(datum/act/op/A)",                    // 25
        "\tvar/B = ACT_ATTEMPT(src, buckle, A.actor)",          // 26
        "\tif(ACT_REFUSED_BY(B))",                              // 27
        "\t\tA.reason = /datum/msg/op/not_available",           // 28
        "\t\treturn OP_REFUSED",                                // 29 a hook's veto relayed: fine
        "\tif(!linked)",                                        // 30
        "\t\tact_cancel(B)",                                    // 31
        "\t\tA.reason = /datum/msg/op/failed",                  // 32
        "\t\treturn OP_REFUSED",                                // 33 failed commit after act_cancel: fine
        "\tif(!ready)",                                         // 34
        "\t\tA.reason = /datum/msg/op/failed",                  // 35
        "\t\treturn OP_REFUSED",                                // 36 effect_refusal: the block is past the relay
        "/obj/item/x/proc/milk(datum/act/op/A)",               // 37
        "\tact_message(A.actor, A.target, others = \"x\")",    // 38
        "\treturn OP_REFUSED",                                 // 39 effect_refusal: told through act_message()
    ];
    let f = fixture.file("code/x.dm", &fixture.join(&fixture_lines,"\n")?)?;
    let mut v = Vec::new();
    scan_lines_using(&f,&mut v,fixture)?;
    let got: Vec<(&str,usize)> = fixture.stable_by_key(v,|(_,n)|*n)?;
    let want = [
        ("effect_refusal", 4),
        ("request_in_effect", 5),
        ("nameof_unrelated", 6),
        ("unkeyed_wire_after", 9),
        ("manual_push", 11),
        ("output_side_effect", 13),
        ("undef_then_used", 17),
        ("output_side_effect", 22),
        ("output_side_effect", 23),
        ("effect_refusal", 36),
        ("effect_refusal", 39),
    ];
    if got != want {
        return Err(fixture.detail(format_args!("dx_review selftest: got {:?}", got))?);
    }
    let t = fixture.file("code/tests/unit_tests/x.dm", "/obj/a/proc/b(datum/act/op/A)\n\topen_request(A, x)")?;
    let mut v2 = Vec::new();
    scan_file_using(&t,&mut v2,fixture)?;
    if !v2.is_empty() {
        return Err(fixture.own("dx_review selftest: unit tests are exempt")?);
    }
    Ok(fixture.own("dx_review")?)
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: crate::allow_registry_fields::sys_dx_review::SCOPE_MODULE_NAME, rules: RULES, file_scan: Some(scan_file), fixture_file_scan:Some(scan_file_using), selftest: Some(selftest), fixture_selftest: Some(selftest_with_fixture), ..SysModule::DEFAULT });
}

#[cfg(test)]mod borrowed_review_controls{
 use super::*;
 #[test]fn actual_captured_undef_names_match_the_old_unicode_word_boundary_expression(){
  let names=["FOO","_A2","Å","中","a\u{301}","a\u{200c}b"];
  let rows=["FOO","FOO_BAR","xFOO","FOOx","(FOO)","Å","xÅ","(中)","a\u{301}","a\u{301}_","a\u{200c}b","a\u{200c}b!",""];
  for name in names{
   // These are precisely the nonempty Unicode-word names the actual #undef
   // capture admits. No arbitrary regex source is accepted as a name.
   assert!(crate::pat::Pat::new_full(r"\w+").is_match(name));
   let old=crate::pat::Pat::new(&format!(r"(?<![\w]){}(?![\w])",name));
   for row in rows{
    let new=row.contains(name)&&crate::pat!(r"\w+").find_iter(row).iter().any(|word|word.as_str()==name);
    assert_eq!(old.is_match(row),new,"name={name:?}, row={row:?}");
   }
  }
 }
 #[test]fn borrowed_path_ancestry_preserves_exact_old_slash_prefix_semantics(){
  for a in ["","/","/datum","/datum/","/datum/a","/datum/ab","/datum//a","/Å/中"]{
   for b in ["","/","/datum","/datum/","/datum/a","/datum/ab","/datum//a","/Å/中"]{
    let pa=format!("{a}/");let pb=format!("{b}/");
    assert_eq!(related(a,b),a==b||pa.starts_with(&pb)||pb.starts_with(&pa),"{a:?} {b:?}");
   }
  }
 }
}
