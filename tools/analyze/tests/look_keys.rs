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
    plan_of_files(dm, &[])
}

/// As `plan_of`, with extra files (path relative to the tree root, text) beside `code/look.dm`.
fn plan_of_files(dm: &str, extra: &[(&str, &str)]) -> BTreeMap<String, (String, String)> {
    let dir = tempfile::tempdir().expect("tempdir");
    let code = dir.path().join("code");
    std::fs::create_dir_all(&code).unwrap();
    std::fs::write(code.join("look.dm"), dm).unwrap();
    for (rel, text) in extra {
        let f = dir.path().join(rel);
        std::fs::create_dir_all(f.parent().unwrap()).unwrap();
        std::fs::write(f, text).unwrap();
    }
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

#[test]
fn look_keys_global_salt_is_the_look_builder_only() {
    let builder = "code/engine/present/appearance_builder.dm";
    let unrelated = [("code/engine/present/messages.dm", "/proc/a_message()
	return 1
"), ("code/modules/unit_tests/dq_look_pins.dm", "/proc/a_pin()
	return 1
")];
    let base = plan_of_files(&fixture_dm(), &[(builder, "/proc/build_look()
	return 1
")]);
    let other_engine = plan_of_files(&fixture_dm(), &[(builder, "/proc/build_look()
	return 1
"), unrelated[0], unrelated[1]]);
    assert_eq!(base, other_engine, "an unrelated engine or pin-test edit moved a key");
    let edited = plan_of_files(&fixture_dm(), &[(builder, "/proc/build_look()
	return 2
")]);
    assert_ne!(base["/obj/plain_thing"].0, edited["/obj/plain_thing"].0, "a look-builder edit left the keys alone");
}
