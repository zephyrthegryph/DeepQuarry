//! The machine review's lints (rewrite/machines-full): shapes the machine conversions kept finding, as shrink-only ratchets.
//!
//! - `effect_refusal`     an op effect (a proc taking `datum/act/op/A`) that tells the actor why (`to_chat`, `atom_say`, `balloon_alert`,
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
//! Unit tests and the engine's own directories are exempt.

use crate::dm::sys::{register_module, SysModule};
use crate::lint::{Registry, RuleMeta};
use crate::pat;
use crate::tree::SourceFile;

const RULES: &[RuleMeta] = &[
    RuleMeta { name: "effect_refusal", hint: "make the refusal a requirement: needs(req(PROC_REF(x), because = MSG(...))) (final_api.html section 9)" },
    RuleMeta { name: "request_in_effect", hint: "ask with asks(/datum/prompt/x, fields = ...) on the op, read A.answer.value in then() (section 16.13)" },
    RuleMeta { name: "nameof_unrelated", hint: "name a var of the holder's own type (nameof(var)); another type's var is not this holder's to name" },
    RuleMeta { name: "unkeyed_wire_after", hint: "give the timer a key (after(..., key = \"x\")) or make the pulse a timed hold (wires(), hold(..., lasts =))" },
    RuleMeta { name: "manual_push", hint: "write the state through its setter: the push is generated from what it reads (section 7)" },
    RuleMeta { name: "output_side_effect", hint: "outputs (ui_data, draw, appearance) say and play nothing, and a look changes no atom (its own or another's): move it to the op or handler that changes the state, or draw it through the look (look.overlay(), look.light(), look.held_state())" },
    RuleMeta { name: "undef_then_used", hint: "#undef a file-local define after its last use, or define it in __defines" },
];

const EXEMPT_PREFIXES: &[&str] = &["code/modules/unit_tests/", "code/tests/", "code/engine/", "code/__defines/"];

/// The proc a line belongs to: its type path, its name, whether it is an op effect, and whether it is an output.
struct ProcCtx {
    type_path: String,
    name: String,
    effect: bool,
    output: bool,
    /// draw(look) or look_parts(look): the look builder's procs, which change no atom either.
    look: bool,
    told: bool,
}

/// `/a/b/proc/name(args` or `/a/b/name(args` at column 0: (type, name, args).
fn header(line: &str) -> Option<(String, String, String)> {
    let caps = pat!(r"^(/[\w/]+?)/(?:proc/|verb/)?(\w+)\((.*)$").captures(line)?;
    Some((caps.get(1)?.to_string(), caps.get(2)?.to_string(), caps.get(3)?.to_string()))
}

/// A or B is the other's ancestor by path (the parent_type a type declares is not followed).
fn related(a: &str, b: &str) -> bool {
    let pa = format!("{}/", a);
    let pb = format!("{}/", b);
    a == b || pa.starts_with(&pb) || pb.starts_with(&pa)
}

fn scan_lines(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    let mut ctx: Option<ProcCtx> = None;
    let mut block_type: Option<String> = None;
    let mut undefs: Vec<(String, usize)> = Vec::new();
    for (number, code) in f.code().numbered() {
        // ---- the #undef rule works on the whole file ----
        if let Some(c) = pat!(r"^\s*#undef\s+(\w+)").captures(code) {
            undefs.push((c.s(1).to_string(), number));
            continue;
        }
        if let Some(c) = pat!(r"^\s*#define\s+(\w+)").captures(code) {
            let name = c.s(1);
            undefs.retain(|(n, _)| n != name);
            continue;
        }
        for (name, _) in &undefs {
            if code.contains(name.as_str()) && crate::pat::Pat::new(&format!(r"(?<![\w]){}(?![\w])", name)).is_match(code) {
                out.push(("undef_then_used", number));
                break;
            }
        }

        // ---- where the line is ----
        let at_col0 = !code.is_empty() && !code.starts_with(|c: char| c.is_whitespace());
        if at_col0 {
            ctx = None;
            block_type = None;
            if let Some(c) = pat!(r"^CAPABILITIES\((/[\w/]+)\)").captures(code) {
                block_type = Some(c.s(1).to_string());
            } else if let Some((type_path, name, args)) = header(code) {
                let effect = args.contains("datum/act/op/");
                let look = matches!(name.as_str(), "draw" | "look_parts") && args.contains("look");
                let output = look || matches!(name.as_str(), "ui_data" | "tgui_data" | "appearance_overlays" | "appearance_state");
                ctx = Some(ProcCtx { type_path, name, effect, output, look, told: false });
            }
            continue;
        }
        let owner = ctx.as_ref().map(|c| c.type_path.clone()).or_else(|| block_type.clone());

        // nameof(/type::var) of a type unrelated to the holder: an accessor on src, or an entry of the type's own block (a relation's
        // other end, back = ..., names the other type's var and is fine)
        if let Some(owner) = owner {
            if code.contains("nameof(/") {
                let found = if ctx.is_some() {
                    pat!(r"\w+\(\s*src\s*,\s*nameof\((/[\w/]+)::\w+\)").captures_iter(code)
                } else {
                    pat!(r"(?<!back = )nameof\((/[\w/]+)::\w+\)").captures_iter(code)
                };
                for c in found {
                    let named = c.s(1);
                    if !related(named, &owner) && !named.starts_with("/datum/capability") && !owner.starts_with("/datum/capability") {
                        out.push(("nameof_unrelated", number));
                        break;
                    }
                }
            }
        }

        // a hand push
        if pat!(r"(?<![\w.:/])push_to_rust\(\)|(?<![\w.:/])changed\(\s*\w+\s*,\s*CHANGE_").is_match(code) {
            out.push(("manual_push", number));
        }

        let Some(c) = ctx.as_mut() else { continue };
        if c.effect {
            if pat!(r"(?<![\w.])open_request\(").is_match(code) {
                out.push(("request_in_effect", number));
            }
            if pat!(r"(?<![\w])(to_chat|atom_say|balloon_alert)\(|\bA\.reason\s*=").is_match(code) {
                c.told = true;
            }
            if c.told && pat!(r"\breturn\s+OP_REFUSED\b").is_match(code) {
                out.push(("effect_refusal", number));
            }
        }
        if c.output && pat!(r"(?<![\w.])(to_chat|atom_say|playsound|play_sfx|balloon_alert)\(").is_match(code) {
            out.push(("output_side_effect", number));
        } else if c.look
            && pat!(r"(?<![\w.])((?:[A-Za-z_]\w*(?:\(\))?\s*\??\.\s*)*)(update_icon|update_held_icon|update_inv_\w+|regenerate_icons|add_overlay|cut_overlays?|set_light|set_light_on|forceMove)\s*\(")
                .captures_iter(code)
                .iter()
                .any(|m| !m.s(1).trim_start().starts_with("look"))
        {
            out.push(("output_side_effect", number));
        }
        if (c.name.contains("pulse") || c.name.contains("wire")) && pat!(r"(?<![\w.])after\(").is_match(code) && !code.contains("key =") && !code.contains("key=") {
            out.push(("unkeyed_wire_after", number));
        }
    }
}

fn scan_file(f: &SourceFile, out: &mut Vec<(&'static str, usize)>) {
    if EXEMPT_PREFIXES.iter().any(|p| f.rel.starts_with(p)) {
        return;
    }
    scan_lines(f, out);
}

fn selftest() -> Result<String, String> {
    let fixture = [
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
        "\tlook.light(2, 1)",                                   // 24 fine
    ];
    let f = SourceFile::from_text("code/x.dm", &fixture.join("\n"));
    let mut v = Vec::new();
    scan_lines(&f, &mut v);
    let mut got: Vec<(&str, usize)> = v;
    got.sort_by_key(|(_, n)| *n);
    let want = vec![
        ("effect_refusal", 4),
        ("request_in_effect", 5),
        ("nameof_unrelated", 6),
        ("unkeyed_wire_after", 9),
        ("manual_push", 11),
        ("output_side_effect", 13),
        ("undef_then_used", 17),
        ("output_side_effect", 22),
        ("output_side_effect", 23),
    ];
    if got != want {
        return Err(format!("dx_review selftest: got {:?}", got));
    }
    let t = SourceFile::from_text("code/modules/unit_tests/x.dm", "/obj/a/proc/b(datum/act/op/A)\n\topen_request(A, x)");
    let mut v2 = Vec::new();
    scan_file(&t, &mut v2);
    if !v2.is_empty() {
        return Err("dx_review selftest: unit tests are exempt".to_string());
    }
    Ok("dx_review".to_string())
}

pub fn register(reg: &mut Registry) {
    register_module(reg, SysModule { name: "dx_review", rules: RULES, file_scan: Some(scan_file), selftest: Some(selftest), ..SysModule::DEFAULT });
}
