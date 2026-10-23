//! Equivalence checker behaviour on a Dream Maker 516.1687 fixture
//! (tests/fixtures/order_probe.dme; see EQUIVALENCE.md for the runtime probe).
use byond_dmb::bytecode;
use byond_dmb::dmb::Dmb;
use dmb_equiv::permute::{permute, PermuteOptions};
use dmb_equiv::{compare_dmbs, Options, Report};

fn fixture() -> Dmb {
    Dmb::from_bytes(include_bytes!("fixtures/order_probe.dmb")).unwrap()
}

fn compare(a: &Dmb, b: &Dmb) -> Report {
    compare_dmbs(a, None, b, None, &Options::default()).unwrap()
}

fn round_trip(d: &Dmb) -> Dmb {
    Dmb::from_bytes(&d.to_bytes().unwrap()).unwrap()
}

fn categories(r: &Report) -> Vec<(String, usize)> {
    r.categories
        .iter()
        .map(|(k, v)| (k.clone(), v.count))
        .collect()
}

fn string_id(d: &Dmb, text: &[u8]) -> u32 {
    d.strings.iter().position(|s| s.data == text).unwrap() as u32
}

fn proc_index(d: &Dmb, path: &[u8]) -> usize {
    d.procs
        .iter()
        .position(|p| d.string(p.strings[0]) == Some(path))
        .unwrap()
}

#[test]
fn identical_world_is_equivalent() {
    let d = fixture();
    let r = compare(&d, &round_trip(&d));
    assert!(r.equivalent(), "{}", r.render_text());
}

#[test]
fn semantics_preserving_renumbering_is_equivalent() {
    let d = fixture();
    for seed in 1..=8 {
        let p = round_trip(&permute(&d, &PermuteOptions::parse(seed, "safe").unwrap()).unwrap());
        assert_ne!(
            p.to_bytes().unwrap(),
            d.to_bytes().unwrap(),
            "seed {seed} must change bytes"
        );
        let r = compare(&d, &p);
        assert!(r.equivalent(), "seed {seed}\n{}", r.render_text());
    }
}

#[test]
fn unobservable_tables_permute_freely() {
    let d = fixture();
    for tables in [
        "variables",
        "instances",
        "mobs",
        "resources",
        "lists",
        "reverse_decls",
        "reverse_footer",
    ] {
        let p = permute(&d, &PermuteOptions::parse(3, tables).unwrap()).unwrap();
        let r = compare(&d, &round_trip(&p));
        assert!(r.equivalent(), "{tables}\n{}", r.render_text());
    }
}

#[test]
fn observable_orders_are_reported() {
    let d = fixture();
    // DreamDaemon output changes for each of these (EQUIVALENCE.md), so the checker must object.
    for (tables, category) in [
        ("classes", "order.type_table"),
        ("procs", "order.proc_table"),
    ] {
        let p = permute(&d, &PermuteOptions::parse(1, tables).unwrap()).unwrap();
        // typesof()/vars order is runtime-visible, so it gates without --strict-order.
        let r = compare(&d, &round_trip(&p));
        assert!(
            r.categories.contains_key(category),
            "{tables}: {:?}",
            categories(&r)
        );
        // Only order categories: record content is ID independent.
        assert!(
            r.categories.keys().all(|k| k.starts_with("order.")),
            "{tables}: {:?}",
            categories(&r)
        );
    }
    let mut o = PermuteOptions::parse(1, "strings").unwrap();
    o.keep_strings = string_id(&d, b"BLEND_INSET_OVERLAY") as usize + 1;
    let r = compare(&d, &round_trip(&permute(&d, &o).unwrap()));
    assert_eq!(
        categories(&r)
            .iter()
            .map(|c| c.0.as_str())
            .collect::<Vec<_>>(),
        ["order.var_name_strings"],
        "{}",
        r.render_text()
    );
}

#[test]
fn one_variable_default_is_reported_precisely() {
    let d = fixture();
    let mut b = d.clone();
    let zz = string_id(&d, b"zz");
    let var = b.variables.iter_mut().find(|v| v.name == zz).unwrap();
    assert_eq!(var.kind, 42);
    var.value = 4.0f32.to_bits();
    let r = compare(&d, &round_trip(&b));
    assert_eq!(r.total, 1, "{}", r.render_text());
    let diff = &r.categories["type.type_var_decl"].examples[0];
    assert_eq!(diff.path, "/datum/mid");
    assert_eq!(diff.detail, "var zz: flags 0x0 = 1.0 vs flags 0x0 = 4.0");
}

#[test]
fn one_opcode_is_reported_with_its_statement() {
    let d = fixture();
    let mut b = d.clone();
    let p = proc_index(&d, b"/proc/dump");
    let code_list = b.procs[p].code_locals_args[0] as usize;
    let ins = bytecode::decode(&b.lists[code_list]).unwrap();
    let target = ins.iter().find(|i| i.opcode == 0xf8).unwrap().offset; // first JmpLoop
    b.lists[code_list][target] = 0x0f; // Jmp: same shape, no budget check
    let r = compare(&d, &round_trip(&b));
    assert_eq!(r.total, 1, "{}", r.render_text());
    let diff = &r.categories["proc.bytecode"].examples[0];
    assert_eq!(diff.path, "/proc/dump");
    assert!(
        diff.detail.starts_with("bytecode differs at stmt 13 "),
        "{}",
        diff.detail
    );
    assert!(
        diff.detail.contains("`JmpLoop L7` vs `Jmp L7`"),
        "{}",
        diff.detail
    );
}

#[test]
fn one_string_is_reported_at_its_use() {
    let d = fixture();
    let mut b = d.clone();
    let id = string_id(&d, b"types:") as usize;
    b.strings[id].data = b"typez:".to_vec();
    let r = compare(&d, &round_trip(&b));
    assert_eq!(r.total, 1, "{}", r.render_text());
    let diff = &r.categories["proc.bytecode"].examples[0];
    assert_eq!(diff.path, "/proc/dump");
    assert!(
        diff.detail
            .contains("`PushVal \"types:\"` vs `PushVal \"typez:\"`"),
        "{}",
        diff.detail
    );
}

#[test]
fn renumbered_world_with_an_edit_reports_only_the_edit() {
    let d = fixture();
    let mut b = permute(&d, &PermuteOptions::parse(5, "safe").unwrap()).unwrap();
    let id = string_id(&b, b"zz");
    b.variables.iter_mut().find(|v| v.name == id).unwrap().value = 9.0f32.to_bits();
    let r = compare(&d, &round_trip(&b));
    assert_eq!(
        categories(&r),
        [("type.type_var_decl".to_string(), 1)],
        "{}",
        r.render_text()
    );
}

#[test]
fn json_summary_has_counts() {
    let d = fixture();
    let p = permute(&d, &PermuteOptions::parse(1, "classes").unwrap()).unwrap();
    let j = compare(&d, &p).to_json();
    assert_eq!(j["equivalent"], false);
    assert!(
        j["categories"]["order.type_table"]["count"]
            .as_u64()
            .unwrap()
            > 0
    );
}

#[test]
fn invisible_orders_are_reported_but_do_not_gate() {
    let d = fixture();
    let p = round_trip(&permute(&d, &PermuteOptions::parse(2, "reverse_footer").unwrap()).unwrap());
    let r = compare(&d, &p);
    assert!(r.equivalent(), "{}", r.render_text());
    assert!(r.ordering.contains_key("global_footer"), "{:?}", r.ordering);
    let strict = dmb_equiv::compare_dmbs(&d, None, &p, None, &Options { strict_order: true, ..Options::default() }).unwrap();
    assert!(!strict.equivalent());
}

fn with_string(d: &Dmb, from: &[u8], to: &[u8]) -> Dmb {
    let mut b = d.clone();
    let id = string_id(d, from) as usize;
    b.strings[id].data = to.to_vec();
    round_trip(&b)
}

fn mapped(a: &Dmb, b: &Dmb, pairs: &[(&str, &str)]) -> Report {
    let opts = Options {
        path_map: pairs
            .iter()
            .map(|(o, n)| (o.to_string(), n.to_string()))
            .collect(),
        ..Options::default()
    };
    compare_dmbs(a, None, b, None, &opts).unwrap()
}

#[test]
fn moved_file_path_is_equivalent_only_with_the_map() {
    let d = fixture();
    let before = with_string(&d, b"types:", b"code/modules/power/cell.dm");
    let after = with_string(&d, b"types:", b"code/content/power/cell.dm");
    assert!(!compare(&before, &after).equivalent());
    let r = mapped(
        &before,
        &after,
        &[("code/modules/power/cell.dm", "code/content/power/cell.dm")],
    );
    assert!(r.equivalent(), "{}", r.render_text());
    assert!(r.notes.iter().any(|n| n.contains("path-map: 1 ")), "{:?}", r.notes);
    // A directory prefix and a path followed by a line number are rewritten too.
    let before = with_string(&d, b"types:", b"code/modules/power/cell.dm:12");
    let after = with_string(&d, b"types:", b"code/content/power/cell.dm:12");
    assert!(mapped(&before, &after, &[("code/modules/power", "code/content/power")]).equivalent());
    assert!(mapped(&before, &after, &[("code/modules/power/cell.dm", "code/content/power/cell.dm")]).equivalent());
    // Backslash paths follow the same map.
    let before = with_string(&d, b"types:", b"code\\modules\\power\\cell.dm");
    let after = with_string(&d, b"types:", b"code\\content\\power\\cell.dm");
    assert!(mapped(&before, &after, &[("code/modules/power/cell.dm", "code/content/power/cell.dm")]).equivalent());
}

#[test]
fn path_map_does_not_hide_other_differences() {
    let d = fixture();
    let pair = [("code/modules/power/cell.dm", "code/content/power/cell.dm")];
    let before = with_string(&d, b"types:", b"code/modules/power/cell.dm");
    // The file was moved somewhere else than the map says.
    let wrong = with_string(&d, b"types:", b"code/content/power/other.dm");
    assert!(!mapped(&before, &wrong, &pair).equivalent());
    // The old path is still present after the move: the map only rewrites the first world.
    assert!(!mapped(&before, &before, &pair).equivalent());
    // A file whose name merely starts with the old one is not the old file.
    let longer = with_string(&d, b"types:", b"code/modules/power/cell.dmx");
    let longer_after = with_string(&d, b"types:", b"code/content/power/cell.dmx");
    assert!(!mapped(&longer, &longer_after, &pair).equivalent());
    // Text after the old path is kept verbatim.
    let b1 = with_string(&d, b"types:", b"code/modules/power/cell.dm:12");
    let a1 = with_string(&d, b"types:", b"code/content/power/cell.dm:13");
    assert!(!mapped(&b1, &a1, &pair).equivalent());
    // An unrelated real change next to a correct map is still reported, and only that one.
    let mut after = with_string(&d, b"types:", b"code/content/power/cell.dm");
    let zz = string_id(&after, b"zz");
    after.variables.iter_mut().find(|v| v.name == zz).unwrap().value = 9.0f32.to_bits();
    let r = mapped(&before, &round_trip(&after), &pair);
    assert_eq!(categories(&r), [("type.type_var_decl".to_string(), 1)], "{}", r.render_text());
    // A changed opcode is not a path.
    let mut b = d.clone();
    let p = proc_index(&d, b"/proc/dump");
    let code_list = b.procs[p].code_locals_args[0] as usize;
    let ins = bytecode::decode(&b.lists[code_list]).unwrap();
    let target = ins.iter().find(|i| i.opcode == 0xf8).unwrap().offset;
    b.lists[code_list][target] = 0x0f;
    assert!(!mapped(&d, &round_trip(&b), &pair).equivalent());
}
