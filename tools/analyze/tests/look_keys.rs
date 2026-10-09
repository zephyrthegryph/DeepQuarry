//! `analyze look-keys` on a fixture tree: the key moves when the draw closure moves, not otherwise; probes follow reads
//! into callees; a dynamic var access makes the probes `*`.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use dq_analyze::look_keys::{plan, PlanOpts};
use dq_analyze::run::{Engine, Options};

fn fixture_dm() -> String {
    let p = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("fixtures/look_keys/code/look.dm");
    std::fs::read_to_string(p).expect("fixture").replace("\r\n", "\n")
}

/// type -> (key, probes) of a tree whose single file is `dm`.
fn plan_of(dm: &str) -> BTreeMap<String, (String, String)> {
    let dir = tempfile::tempdir().expect("tempdir");
    let code = dir.path().join("code");
    std::fs::create_dir_all(&code).unwrap();
    std::fs::write(code.join("look.dm"), dm).unwrap();
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf();
    let opts = Options { root: dir.path().to_path_buf(), lints: vec!["sem/keys".to_string()], no_cache: true, raw: true, scopes_from: Some(repo), ..Default::default() };
    let engine = Engine::new(dq_analyze::run::registry(), opts).expect("engine");
    let p = plan(&engine.tree, Path::new(dir.path()), &PlanOpts::default(), None).expect("plan");
    p.rows.into_iter().map(|r| (r.ty, (r.key, r.probes))).collect()
}

#[test]
fn look_keys_skip_abstract_types_and_list_concrete_ones() {
    let rows = plan_of(&fixture_dm());
    assert!(!rows.contains_key("/obj/base_thing"), "abstract type listed");
    for t in ["/obj/base_thing/door", "/obj/dynamic_thing", "/obj/plain_thing"] {
        assert!(rows.contains_key(t), "{} missing from {:?}", t, rows.keys().collect::<Vec<_>>());
    }
}

#[test]
fn look_keys_key_changes_with_a_closure_proc_body() {
    let base = plan_of(&fixture_dm());
    let edited = plan_of(&fixture_dm().replace("overlays += \"tint\"", "overlays += \"tint2\""));
    assert_ne!(base["/obj/base_thing/door"].0, edited["/obj/base_thing/door"].0, "a callee of update_icon changed");
    let edited = plan_of(&fixture_dm().replace("overlays += \"open\"", "overlays += \"opened\""));
    assert_ne!(base["/obj/base_thing/door"].0, edited["/obj/base_thing/door"].0, "update_icon changed");
    // a var initial value is part of the key
    let edited = plan_of(&fixture_dm().replace("\topen = 1", "\topen = 0"));
    assert_ne!(base["/obj/base_thing/door"].0, edited["/obj/base_thing/door"].0, "an initial value changed");
    assert_eq!(base["/obj/plain_thing"].0, edited["/obj/plain_thing"].0, "an unrelated type kept its key");
}

#[test]
fn look_keys_key_ignores_unrelated_procs_comments_and_reflow() {
    let base = plan_of(&fixture_dm());
    let unrelated = plan_of(&fixture_dm().replace("\treturn 1\n", "\treturn 2\n"));
    assert_eq!(base, unrelated, "an unrelated proc moved a key");
    let comment = plan_of(&fixture_dm().replace("\toverlays.Cut()\n", "\t// a new comment\n\n\toverlays.Cut() // trailing\n/* block */\n"));
    assert_eq!(base, comment, "a comment or blank line moved a key");
}

#[test]
fn look_keys_probes_follow_reads_into_callees() {
    let rows = plan_of(&fixture_dm());
    let probes: Vec<&str> = rows["/obj/base_thing/door"].1.split(',').collect();
    assert!(probes.contains(&"open"), "direct read: {:?}", probes);
    assert!(probes.contains(&"tint"), "read in draw_tint(), a callee: {:?}", probes);
    assert!(!probes.contains(&"unused"), "a var no closure proc names: {:?}", probes);
    assert!(!probes.contains(&"*"));
    // A type with no draw procs of its own reads nothing of its own vars.
    assert!(!rows["/obj/plain_thing"].1.split(',').any(|p| p == "level"), "{:?}", rows["/obj/plain_thing"]);
}

#[test]
fn look_keys_dynamic_var_access_makes_probes_unknown() {
    let rows = plan_of(&fixture_dm());
    assert_eq!(rows["/obj/dynamic_thing"].1, "*");
    assert_ne!(rows["/obj/base_thing/door"].1, "*");
}

// ---------------------------------------------------------------------------------------------------------------------
// The incremental path: an edit that leaves the structure alone gives the rows a full computation gives.

const DME: &str = "#include \"code/look.dm\"\n#include \"code/draw.dm\"\n#include \"code/other.dm\"\n#include \"code/helpers.dm\"\n";
const HELPERS: &str = "/proc/gameplay_helper()\n\treturn 1\n";
const DRAW: &str = "/obj/base_thing/proc/draw_extra()\n\tif(open)\n\t\toverlays += \"extra\"\n";
const OTHER: &str = "/obj/other_thing\n\tvar/n = 0\n\n/obj/other_thing/Bump()\n\tn += 1\n\treturn 1\n";

fn incremental_look() -> String {
    fixture_dm().replace("\tdraw_tint()\n", "\tdraw_tint()\n\tdraw_extra()\n")
}

fn write_tree(dir: &Path, look: &str, draw: &str, other: &str) {
    write_tree_h(dir, look, draw, other, HELPERS);
}

fn write_tree_h(dir: &Path, look: &str, draw: &str, other: &str, helpers: &str) {
    std::fs::create_dir_all(dir.join("code")).unwrap();
    std::fs::write(dir.join("code/helpers.dm"), helpers).unwrap();
    std::fs::write(dir.join("deepquarry.dme"), DME).unwrap();
    std::fs::write(dir.join("code/look.dm"), look).unwrap();
    std::fs::write(dir.join("code/draw.dm"), draw).unwrap();
    std::fs::write(dir.join("code/other.dm"), other).unwrap();
}

fn plan_at(dir: &Path, cache: Option<&Path>) -> (BTreeMap<String, (String, String)>, String) {
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf();
    let opts = Options { root: dir.to_path_buf(), lints: vec!["sem/keys".to_string()], no_cache: true, raw: true, scopes_from: Some(repo), ..Default::default() };
    let engine = Engine::new(dq_analyze::run::registry(), opts).expect("engine");
    let p = plan(&engine.tree, dir, &PlanOpts::default(), cache).expect("plan");
    (p.rows.into_iter().map(|r| (r.ty, (r.key, r.probes))).collect(), p.mode)
}

#[test]
fn look_keys_incremental_rows_equal_a_full_computation() {
    let dir = tempfile::tempdir().expect("tempdir");
    let cache = dir.path().join("cache/look-keys.bin");
    let root = dir.path();
    write_tree(root, &incremental_look(), DRAW, OTHER);
    let (first, mode) = plan_at(root, Some(&cache));
    assert_eq!(mode, "full");
    assert!(first.contains_key("/obj/base_thing/door") && first.contains_key("/obj/other_thing"), "{:?}", first.keys().collect::<Vec<_>>());
    let (again, mode) = plan_at(root, Some(&cache));
    assert_eq!(mode, "cached");
    assert_eq!(first, again);

    // 1. a proc no closure reaches, in a file no row depends on and in a type's own file (its vars are unchanged): no parse.
    write_tree_h(root, &incremental_look(), DRAW, OTHER, &HELPERS.replace("return 1", "return 2"));
    let (rows, mode) = plan_at(root, Some(&cache));
    assert!(mode.starts_with("incremental: no row holds"), "{}", mode);
    assert_eq!(rows, first, "an unrelated edit moved a key");
    write_tree_h(root, &incremental_look(), DRAW, &OTHER.replace("n += 1", "n += 2"), &HELPERS.replace("return 1", "return 2"));
    let (rows, mode) = plan_at(root, Some(&cache));
    assert!(mode.starts_with("incremental: no row holds"), "{}", mode);
    assert_eq!(rows, plan_at(root, None).0, "edit of a proc outside every closure");
    assert_eq!(rows, first, "an unrelated edit moved a key");
    // a var value in the type's own file does move it
    write_tree_h(root, &incremental_look(), DRAW, &OTHER.replace("n += 1", "n += 2").replace("var/n = 0", "var/n = 5"), &HELPERS.replace("return 1", "return 2"));
    let (rows, mode) = plan_at(root, Some(&cache));
    assert!(mode.starts_with("incremental: 1 of"), "{}", mode);
    assert_eq!(rows, plan_at(root, None).0, "var value edit");
    assert_ne!(rows["/obj/other_thing"].0, first["/obj/other_thing"].0, "a var value is part of the key");
    write_tree_h(root, &incremental_look(), DRAW, &OTHER.replace("n += 1", "n += 2"), &HELPERS.replace("return 1", "return 2"));
    let (rows, _) = plan_at(root, Some(&cache));
    assert_eq!(rows, first, "back to the first values");

    // 2. a callee of update_icon: the rows that reach it are recomputed, the others kept.
    write_tree(root, &incremental_look(), &DRAW.replace("\"extra\"", "\"extra2\""), &OTHER.replace("n += 1", "n += 2"));
    let (rows, mode) = plan_at(root, Some(&cache));
    assert!(mode.starts_with("incremental: ") && !mode.starts_with("incremental: no row holds"), "{}", mode);
    let full = plan_at(root, None).0;
    assert_eq!(rows, full, "closure edit");
    assert_ne!(rows["/obj/base_thing/door"].0, first["/obj/base_thing/door"].0, "the key did not move");
    assert_eq!(rows["/obj/plain_thing"], first["/obj/plain_thing"]);

    // 3. a comment: cosmetic.
    write_tree(root, &incremental_look(), &format!("// note\n{}", DRAW.replace("\"extra\"", "\"extra2\"")), &OTHER.replace("n += 1", "n += 2"));
    let (rows, mode) = plan_at(root, Some(&cache));
    assert!(mode.starts_with("incremental: no row holds"), "{}", mode);
    assert_eq!(rows, full);

    // 4. a var initial value in a file with abstract_type lines: its footprint rows are recomputed.
    write_tree(root, &incremental_look().replace("\topen = 1", "\topen = 0"), &DRAW.replace("\"extra\"", "\"extra2\""), &OTHER.replace("n += 1", "n += 2"));
    let (rows, mode) = plan_at(root, Some(&cache));
    assert!(mode.starts_with("incremental: ") && !mode.starts_with("incremental: no row holds"), "{}", mode);
    assert_eq!(rows, plan_at(root, None).0, "initial value edit");

    // 4b. a var assigned to an existing type from a file that never mentioned it: the type's row moves.
    let before = plan_at(root, None).0;
    write_tree_h(
        root,
        &incremental_look().replace("\topen = 1", "\topen = 0"),
        &DRAW.replace("\"extra\"", "\"extra2\""),
        &OTHER.replace("n += 1", "n += 2"),
        &format!("{}\n/obj/other_thing/icon_state = \"lit\"\n", HELPERS),
    );
    let (rows, mode) = plan_at(root, Some(&cache));
    assert!(mode.starts_with("incremental: 1 of"), "{}", mode);
    assert_eq!(rows, plan_at(root, None).0, "an override from another file");
    assert_ne!(rows["/obj/other_thing"].0, before["/obj/other_thing"].0, "the override did not move the key");
    write_tree(root, &incremental_look().replace("\topen = 1", "\topen = 0"), &DRAW.replace("\"extra\"", "\"extra2\""), &OTHER.replace("n += 1", "n += 2"));
    let (rows, _) = plan_at(root, Some(&cache));
    assert_eq!(rows, before, "removing the override restores the key");

    // 5. structure changes recompute everything: a new proc, a new type, an abstract_type line.
    let draw = format!("{}\n/obj/base_thing/proc/brand_new()\n\treturn 3\n", DRAW);
    write_tree(root, &incremental_look().replace("\topen = 1", "\topen = 0"), &draw, &OTHER);
    let (rows, mode) = plan_at(root, Some(&cache));
    assert_eq!(mode, "full", "a new proc must recompute everything");
    assert_eq!(rows, plan_at(root, None).0);
    write_tree(root, &incremental_look().replace("\topen = 1", "\topen = 0"), &draw, &format!("{}\n/obj/another_thing\n\tvar/n = 0\n", OTHER));
    let (rows, mode) = plan_at(root, Some(&cache));
    assert_eq!(mode, "full", "a new type must recompute everything");
    assert!(rows.contains_key("/obj/another_thing"));
    write_tree(root, &incremental_look().replace("\topen = 1", "\topen = 0").replace("abstract_type = /obj/base_thing", "abstract_type = /obj/dynamic_thing"), &draw, &format!("{}\n/obj/another_thing\n\tvar/n = 0\n", OTHER));
    let (rows, mode) = plan_at(root, Some(&cache));
    assert_eq!(mode, "full", "an abstract_type change must recompute everything");
    assert_eq!(rows, plan_at(root, None).0);
}
