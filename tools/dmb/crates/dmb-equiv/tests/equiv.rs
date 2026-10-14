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
        diff.detail.starts_with("bytecode differs at stmt 15 "),
        "{}",
        diff.detail
    );
    assert!(
        diff.detail.contains("`JmpLoop L9` vs `Jmp L9`"),
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
