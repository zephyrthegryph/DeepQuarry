//! `analyze gen declare_ids` and `analyze gen declare` (E1, declarations): what the DM compiler cannot do with a marker.
//!
//! Every declaration marker (`CAPABILITIES`, `CAPABILITY_TYPE`, `CAPABILITY_DEF`, `cap_keys`, `STAGE_DEF`, `SOURCE_DEF`,
//! `STATE_GRAPH`, `STAT`) expands to nothing in DM, so an author gives it no id and no constructor of its own (a marker that spans lines
//! ends each line but the last with DM's backslash, which the generator drops). These two generators read the markers from source and
//! write the DM the engine runs:
//!
//! * `declare_ids` -> `code/engine/_generated/ids.dm`: the ids a marker declares (`STAT_X`, `CAP_X`, `SRC_X`, `STAGE_G_N`, `GRAPH_X`) and
//!   the capability-state ids `cap_keys` declares (`COVER_OPEN`). An id that a hand-written `#define` already gives is left alone. The file
//!   is included early in `deepquarry.dme`, before anything that uses an id.
//! * `declare` -> `code/engine/_generated/declare.dm`: the constructor of each capability (`name(params)`, with the params the marker lists,
//!   so DM checks a call's named arguments), the capability datum's param vars with their defaults, the registration rows the engine reads
//!   at boot (capabilities, state keys, stages, sources, state graphs), the `accessor(holder)` of each state key, and each type's
//!   `declared_entries()`: the entries of its `CAPABILITIES(T, ...)` list, copied as written. The proc is defined on `T`, so `nameof(var)`
//!   and `PROC_REF(x)` resolve against the type, and each entry carries its own line for the explain tools.
//!
//! The entry text is copied except for these rewrites (E4 adds `adjusts(a.b, ...)` and `on_change(nameof(a.b), ...)`, whose paths become text): `link(A::a, B::b)` (DM's `link` is a keyword) becomes `entry_link("A::a", "B::b")`,
//! and `configure(CAP_X, "selector", param = value)` becomes `configure(<constructor of CAP_X>("selector", param = value))`.

use std::collections::BTreeSet;

use crate::sem::gen::{GenCx, GenOut, Generator};

/// The ids a `#define` outside the generated file already gives.
fn defined_elsewhere(cx: &GenCx, out_rel: &str) -> BTreeSet<String> {
    // Per file, cached by content: an edit reads one file.
    let files = cx.tree.select(&crate::tree::CODE_DM);
    let per: Vec<Vec<String>> = crate::incr::facts("gen-defines-per-file", &files, |f| {
        let text = f.text();
        let mut names = Vec::new();
        crate::declare_ids_policy::visit_defines(text, |name| names.push(name.to_owned()));
        names
    });
    let mut set = BTreeSet::new();
    for (f, names) in files.iter().zip(per) {
        if f.rel != out_rel {
            set.extend(names);
        }
    }
    set
}

// ---- ids ----

struct Ids;

impl Generator for Ids {
    fn name(&self) -> &'static str {
        "declare_ids"
    }

    fn output(&self) -> &'static str {
        "ids.dm"
    }

    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let mut builder = crate::declare_ids_policy::Builder::default();
        for name in defined_elsewhere(cx, "code/engine/_generated/ids.dm") {
            builder.define(&name).expect("legacy define");
        }
        for m in &cx.decls().markers {
            if crate::declare_ids_policy::MARKERS.contains(&m.name.as_str()) {
                builder
                    .push(&m.name, &m.rel, m.line, &m.args)
                    .expect("legacy ids marker");
            }
        }
        let generated = builder.finish();
        for d in generated.diags {
            out.diag(&d.rel, d.line, d.msg);
        }
        for line in generated.body.split_terminator('\n') {
            out.line(line);
        }
    }
}

// ---- declare ----

#[cfg(test)]
use crate::declare_policy::key_expr;
struct Declare;
impl Generator for Declare {
    fn name(&self) -> &'static str {
        "declare"
    }
    fn output(&self) -> &'static str {
        "declare.dm"
    }
    fn generate(&self, cx: &GenCx, out: &mut GenOut) {
        let markers: Vec<_> = cx
            .decls()
            .markers
            .iter()
            .map(|m| crate::declare_policy::Marker {
                name: &m.name,
                rel: &m.rel,
                line: m.line,
                body: &m.body,
                args: &m.args,
                body_offset: m.body_offset,
                line_starts: &m.line_starts,
            })
            .collect();
        let files = cx.tree.select(&crate::tree::CODE_DM);
        let engine_sources: Vec<_> = files.iter().map(|f| (f.rel.as_str(), f.text())).collect();
        let input = crate::declare_policy::Input {
            markers: &markers,
            engine_sources: &engine_sources,
            budget: None,
            poll: None,
        };
        let generated =
            crate::declare_policy::generate(&input, || Ok(())).expect("legacy declaration policy");
        for d in generated.diags {
            out.diag(&d.rel, d.line, d.msg);
        }
        for line in generated.body.split_terminator('\n') {
            out.line(line);
        }
    }
}
pub fn register(reg: &mut Vec<Box<dyn Generator>>) {
    reg.push(Box::new(Ids));
    reg.push(Box::new(Declare));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::declare_ids_policy::split_opt;
    use crate::sem::gen::render;
    use crate::tree::{SourceFile, Tree};
    use std::path::Path;

    fn gen(files: Vec<(&str, &str)>) -> (String, String, Vec<String>) {
        let tree = Tree::from_files(
            files
                .into_iter()
                .map(|(r, t)| SourceFile::from_text(r, t))
                .collect(),
        );
        let cx = GenCx::new(&tree, Path::new("."));
        let (ids, d1) = render(&Ids, &cx);
        let (decl, d2) = render(&Declare, &cx);
        let diags = d1.into_iter().chain(d2).map(|d| d.msg).collect();
        (ids, decl, diags)
    }

    const SRC: &str = r#"
#define CAP_HAND 5
STAT(/obj/machinery, operable, ALL)
STAT(/mob/living, stun, MAX, units = LIFE_CYCLE)
SOURCE_DEF(vv)
STAGE_DEF(door, frame)
STATE_GRAPH(GRAPH_DOOR, start(STAGE_DOOR_FRAME))
CAPABILITY_TYPE(widget, CAP_WIDGET, /datum/capability/widget, key = label, stacks = BEST(power), label = "main", power = 1)
CAPABILITY_DEF(cover, CAP_HAND)
cap_keys(CAP_WIDGET, ARMED = null, LIT = null)
CAPABILITIES(/obj/thing, \
	widget("a", power = 2), \
	link(/obj/thing::partner, /obj/thing::partner), \
	configure(CAP_WIDGET, "a", power = 9), \
	when(nameof(armed), contributes(STAT_OPERABLE, FALSE)))
"#;

    #[test]
    fn ids_come_from_the_markers_and_leave_hand_defines_alone() {
        let (ids, _, diags) = gen(vec![("code/a.dm", SRC)]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(ids.contains("#define STAT_OPERABLE 100001"), "{}", ids);
        assert!(ids.contains("#define STAT_STUN 100002"), "{}", ids);
        assert!(ids.contains("#define STATUS_STUN STAT_STUN"));
        assert!(ids.contains("#define STAT_STUN_IMMUNE STAT_IMMUNE(STAT_STUN)"));
        assert!(ids.contains("#define CAP_WIDGET 300"));
        assert!(
            !ids.contains("#define CAP_HAND"),
            "a hand-written define is not repeated"
        );
        assert!(ids.contains("#define SRC_VV 1"));
        assert!(ids.contains("#define STAGE_DOOR_FRAME 1"));
        assert!(ids.contains("#define GRAPH_DOOR 1"));
        assert!(ids.contains("#define WIDGET_ARMED CAPKEY_ID(CAP_WIDGET, 1)"));
        assert!(ids.contains("#define WIDGET_LIT CAPKEY_ID(CAP_WIDGET, 2)"));
    }

    #[test]
    fn lifecycle_forms_get_make_a_datum_flag_and_no_native_input_override() {
        let src = "CAPABILITIES(/datum/req, \\\n\tparam(nameof(charge), int()), \\\n\trolls(nameof(x), range_of(1, 2)))\nCAPABILITIES(/obj/screen_thing, \\\n\tclick_on(PROC_REF(clicked)), \\\n\tdrag_over(PROC_REF(dragged)), \\\n\ttooltip(PROC_REF(tip)))\n";
        let (_, decl, diags) = gen(vec![("code/a.dm", src)]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(
            decl.contains(
                "/proc/make(type, at = null, by = null, parts = null, charge = MAKE_UNSET)"
            ),
            "{}",
            decl
        );
        assert!(
            decl.contains("/proc/make_args(charge = MAKE_UNSET)"),
            "{}",
            decl
        );
        assert!(
            decl.contains("/datum/req\n\tlifeform_declared = TRUE"),
            "{}",
            decl
        );
        for native in [
            "Click",
            "DblClick",
            "MouseDrop",
            "MouseDrag",
            "MouseEntered",
            "MouseExited",
        ] {
            assert!(
                !decl.contains(&format!("/obj/screen_thing/{}(", native)),
                "no native mouse override is generated for a declared input ({}): {}",
                native,
                decl
            );
        }
        assert!(!decl.contains("input_declared"), "{}", decl);
        assert!(
            !decl.contains("/obj/screen_thing\n\tlifeform_declared"),
            "an atom runs its forms from Initialize()"
        );
    }

    #[test]
    fn a_plain_datum_after_init_gets_the_datum_flag() {
        let src = "CAPABILITIES(/datum/ripens, \
	after_init(0, then(PROC_REF(ripe))))
CAPABILITIES(/obj/ripens, \
	after_init(0, then(PROC_REF(ripe))))
";
        let (_, decl, diags) = gen(vec![("code/a.dm", src)]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(
            decl.contains("/datum/ripens\n\tlifeform_declared = TRUE"),
            "lifeform_datum_new() takes the make() record that arms it: {}",
            decl
        );
        assert!(
            !decl.contains("/obj/ripens\n\tlifeform_declared"),
            "an atom arms it when its Initialize() returns"
        );
    }

    #[test]
    fn capabilities_get_a_constructor_a_row_and_param_vars() {
        let (_, decl, diags) = gen(vec![("code/a.dm", SRC)]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(
            decl.contains("/datum/capability/widget\n\tvar/label = \"main\"\n\tvar/power = 1\n"),
            "{}",
            decl
        );
        assert!(decl.contains("/proc/widget(label, power)"));
        assert!(decl.contains("return cap_construct(CAP_WIDGET, /datum/capability/widget, list(label, power), \"label, power\")"));
        assert!(decl.contains("return list(CAP_WIDGET, /datum/capability/widget, \"label\", BEST(power), \"widget\", \"label, power\")"));
        assert!(decl.contains("/datum/capdef_decl/c_cover/spec()"));
        assert!(
            decl.contains("/datum/capability/def/cover"),
            "a DEF's datum type is /datum/capability/def/<name>"
        );
    }

    #[test]
    fn a_capabilities_list_becomes_declared_entries_with_a_line_per_entry() {
        let (_, decl, _) = gen(vec![("code/a.dm", SRC)]);
        assert!(decl.contains("/obj/thing/declared_entries(list/into)\n\t..(into)\n\tinto += entry_block(\"code/a.dm\", 11, /obj/thing)"), "{}", decl);
        assert!(
            decl.contains(
                "into += entry_line(12)\n\tinto += list(global.widget(\"a\", power = 2))"
            ),
            "{}",
            decl
        );
        assert!(
            decl.contains("entry_link(\"/obj/thing::partner\", \"/obj/thing::partner\")"),
            "link is rewritten: {}",
            decl
        );
        assert!(
            decl.contains("configure(global.widget(\"a\", power = 9))"),
            "configure(CAP_X, ...) is rewritten to the constructor: {}",
            decl
        );
        assert!(decl.contains("when(nameof(armed), contributes(STAT_OPERABLE, FALSE))"));
        assert!(
            decl.contains(
                "into += entry_line(13)
	into += list(entry_link("
            ),
            "every entry keeps its own line: {}",
            decl
        );
    }

    #[test]
    fn a_sparse_link_end_is_an_expression_not_text() {
        let block = "CAPABILITIES(/obj/thing)
	links(LINK_END(/obj/thing, LK_ONE), LINK_END(/obj/thing, LK_TWO), sparse = TRUE, holds_while = PROC_REF(x))
";
        let (_, decl, diags) = gen(vec![("code/a.dm", block)]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(decl.contains("entry_link(LINK_END(/obj/thing, LK_ONE), LINK_END(/obj/thing, LK_TWO), sparse = TRUE"), "{}", decl);
    }

    #[test]
    fn the_block_form_generates_what_the_legacy_list_does() {
        let bs = char::from(92u8);
        let legacy = format!(
            "CAPABILITIES(/obj/thing, {bs}
	wall(1, 2), {bs}
	link(/obj/thing::partner, /obj/thing::partner), {bs}
	on_change(nameof(terminal.charge), ANY,
		then(PROC_REF(x))))
"
        );
        let block = "CAPABILITIES(/obj/thing)
	wall(1, 2)
	links(/obj/thing::partner, /obj/thing::partner)
	on_change(nameof(terminal.charge), ANY,
		then(PROC_REF(x)))
";
        let (_, a, da) = gen(vec![("code/a.dm", legacy.as_str())]);
        let (_, b, db) = gen(vec![("code/a.dm", block)]);
        assert!(da.is_empty() && db.is_empty(), "{:?} {:?}", da, db);
        assert_eq!(a, b, "the same entries, the same lines");
        assert!(
            b.contains("entry_link(\"/obj/thing::partner\", \"/obj/thing::partner\")"),
            "{}",
            b
        );
        assert!(b.contains("on_change(\"terminal.charge\", ANY"), "{}", b);
    }

    #[test]
    fn one_extend_carries_every_part_of_its_key() {
        let (_, decl, diags) = gen(vec![("code/a.dm", "CAPABILITIES(/obj/thing)
	extend(\"construction.undo:x\", when(COVER_OPEN), priority(above(\"panel.open\")), needs(req(PROC_REF(y))))
")]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(decl.contains("extend(\"construction.undo:x\", when(COVER_OPEN), priority(above(\"panel.open\")), needs(req(PROC_REF(y))))"), "{}", decl);
        assert_eq!(
            decl.matches("extend(").count(),
            1,
            "one entry for the key: {}",
            decl
        );
    }

    #[test]
    fn a_second_capabilities_list_for_a_type_is_reported() {
        let (_, _, diags) = gen(vec![(
            "code/a.dm",
            "CAPABILITIES(/obj/x, a())\nCAPABILITIES(/obj/x, b())\n",
        )]);
        assert_eq!(diags.len(), 1, "{:?}", diags);
        assert!(
            diags[0].contains("second CAPABILITIES list for /obj/x"),
            "{}",
            diags[0]
        );
    }

    #[test]
    fn adjusts_and_on_change_paths_become_text() {
        let (_, decl, diags) = gen(vec![(
            "code/a.dm",
            "CAPABILITIES(/obj/thing, \
	extend(/datum/act/hit, adjusts(packet.amount, scale = 0.5)), \
	on_change(nameof(terminal.charge), ANY, then(PROC_REF(x))), \
	on_change(nameof(on), ENTER, then(PROC_REF(y))))
",
        )]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(
            decl.contains("adjusts(\"packet.amount\", scale = 0.5)"),
            "{}",
            decl
        );
        assert!(
            decl.contains("on_change(\"terminal.charge\", ANY"),
            "{}",
            decl
        );
        assert!(
            decl.contains("on_change(nameof(on), ENTER"),
            "a plain nameof stays: {}",
            decl
        );
    }

    #[test]
    fn a_section_groups_the_entries_after_it_and_names_them() {
        let (_, decl, diags) = gen(vec![(
            "code/a.dm",
            "CAPABILITIES(/obj/thing)
	wall(1, 2)

	section(controls, \"The window and its buttons.\")
	interface(\"Thing\")
	op(\"press\", ui_act(), then(PROC_REF(pressed)))
	section(rules)
	extend(\"press\", needs(req_operable()))
",
        )]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(
            decl.contains("\tinto += entry_line(2)\n\tinto += list(wall(1, 2))"),
            "an entry before any section has none: {}",
            decl
        );
        assert!(decl.contains("\t// section controls: The window and its buttons.\n\tinto += entry_line(5, \"controls\")\n\tinto += list(interface(\"Thing\"))"), "{}", decl);
        assert!(decl.contains("into += entry_line(6, \"controls\")\n\tinto += list(op(\"press\", ui_act(), then(PROC_REF(pressed))))"), "PROC_REF stays: the entries are the type's own: {}", decl);
        assert!(
            decl.contains("\t// section rules\n\tinto += entry_line(8, \"rules\")"),
            "{}",
            decl
        );
        assert!(
            !decl.contains("section("),
            "the header is no entry: {}",
            decl
        );
    }

    #[test]
    fn a_var_assignment_in_a_block_is_reported() {
        let (_, _, diags) = gen(vec![(
            "code/a.dm",
            "CAPABILITIES(/obj/thing)
	wall(1, 2)
	pixel_x = -16
",
        )]);
        assert!(
            diags
                .iter()
                .any(|d| format!("{:?}", d).contains("var assignment")),
            "{:?}",
            diags
        );
    }

    #[test]
    fn bad_sections_are_reported() {
        let (_, _, diags) = gen(vec![(
            "code/a.dm",
            "CAPABILITIES(/obj/thing)
	section(a)
	section(\"b\")
	wall(1)
	section(c, 12)
	section(d)
	wall(2)
	section(d)
	wall(3)
",
        )]);
        let all = diags.join("\n");
        assert!(
            all.contains("section(a) of /obj/thing has no entries"),
            "{}",
            all
        );
        assert!(
            all.contains("`section(\"b\")`: a section header is"),
            "{}",
            all
        );
        assert!(all.contains("`section(c, 12)`"), "{}", all);
        assert!(
            all.contains("section(d) of /obj/thing is declared twice"),
            "{}",
            all
        );
    }

    #[test]
    fn static_entries_leave_the_instance_chain_for_a_registry() {
        let src = "STATIC_ENTRY(loot)
CAPABILITIES(/obj/random/x)
	loot(table = list(/obj/a = 2))
	wall(1, 2)
CAPABILITIES(/obj/random/x/y)
	configure(loot(chance = 5))
";
        let (_, decl, diags) = gen(vec![("code/a.dm", src)]);
        assert!(diags.is_empty(), "{:?}", diags);
        assert!(
            decl.contains(
                "/proc/declared_static_blocks()
	. = list()
	declared_static_blocks_part1(.)"
            ),
            "{}",
            decl
        );
        assert!(decl.contains("	into[/obj/random/x] = list(\"code/a.dm\", 2, list(entry_line(3), global.loot(table = list(/obj/a = 2))))"), "{}", decl);
        assert!(decl.contains("	into[/obj/random/x/y] = list(\"code/a.dm\", 5, list(entry_line(6), configure(global.loot(chance = 5))))"), "{}", decl);
        assert!(
            !decl.contains("into += list(global.loot"),
            "a static entry is not in the instance chain: {}",
            decl
        );
        assert!(
            !decl.contains(
                "configure(global.loot(chance = 5))
	into"
            ),
            "{}",
            decl
        );
        assert!(
            decl.contains("into += list(wall(1, 2))"),
            "an ordinary entry stays: {}",
            decl
        );
    }

    #[test]
    fn option_splitting_and_key_forms() {
        assert_eq!(split_opt("key = name"), Some(("key".into(), "name".into())));
        assert_eq!(split_opt("a == b"), None);
        assert_eq!(key_expr(&Some("name".into())), "\"name\"");
        assert_eq!(key_expr(&Some("NONE".into())), "NONE");
        assert_eq!(key_expr(&None), "NONE");
    }
}
