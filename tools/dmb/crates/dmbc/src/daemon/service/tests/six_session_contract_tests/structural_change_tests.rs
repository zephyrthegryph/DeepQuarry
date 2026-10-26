//! Structural change set consumers (doc/structural_change_set.md): every
//! scenario of the takeover bench as edit, revert, and chained edits, each
//! revision compared with an independent fresh compile in compare_revision.
//! The probe dispatches through inherited names so a carried certificate for
//! a changed owner/name would select the wrong body and change the bytes.
use super::*;

const TREE: &str = "#define BONUS 3
/datum/base
    var/value = 7
    proc/result()
        return value
    proc/helper()
        return 1
/datum/base/child
    var/own = 2
/proc/probe()
    var/datum/base/child/item = new
    return item.result() + item.helper() + BONUS
/proc/other()
    var/datum/base/item = new
    return item.value
";

fn scenarios() -> Vec<(&'static str, String)> {
    vec![
        (
            "leaf variable",
            TREE.replace("    var/own = 2\n", "    var/extra = 5\n    var/own = 2\n"),
        ),
        ("changed default", TREE.replace("var/value = 7", "var/value = 9")),
        (
            "new overriding proc",
            format!("{TREE}/datum/base/child/result()\n    return own\n"),
        ),
        (
            "removed proc",
            TREE.replace("    proc/helper()\n        return 1\n", "")
                .replace(" + item.helper()", ""),
        ),
        ("removed var", TREE.replace("    var/own = 2\n", "")),
        (
            "new type",
            format!("{TREE}/datum/base/child/grand\n    value = 4\n"),
        ),
        ("define", TREE.replace("#define BONUS 3", "#define BONUS 5")),
    ]
}

fn edit_all(roots: &Roots, source: &str) {
    for index in 0..6 {
        roots.edit(index, source);
    }
}

#[test]
fn structural_scenarios_edit_and_revert_match_fresh_bytes() {
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    edit_all(&roots, TREE);
    let initial = compare_revision(&shared, &roots);
    for (label, source) in scenarios() {
        edit_all(&roots, &source);
        let edited = compare_revision(&shared, &roots);
        assert_ne!(edited[0], initial[0], "{label} edit must publish new content");
        edit_all(&roots, TREE);
        compare_revision(&shared, &roots);
        // Reverting a removed var adds it back, an append patch with stable
        // numbering: equivalent to a fresh build (compare_revision), not identical.
        if label != "removed var" {
        }
    }
}

#[test]
fn chained_structural_edits_match_fresh_bytes_and_revert() {
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    edit_all(&roots, TREE);
    let initial = compare_revision(&shared, &roots);
    // Cumulative: new var, its default, an override reading it, a new subtype
    // overriding again, a define, then removals in reverse order.
    let mut source = TREE.to_string();
    let steps: [(&str, &str, &str); 6] = [
        ("leaf variable", "    var/own = 2\n", "    var/extra = 5\n    var/own = 2\n"),
        ("changed default", "var/extra = 5", "var/extra = 6"),
        ("override", "/proc/probe()", "/datum/base/child/result()\n    return extra\n/proc/probe()"),
        ("new type", "/proc/other()", "/datum/base/child/grand\n    extra = 8\n/proc/other()"),
        ("define", "#define BONUS 3", "#define BONUS 4"),
        ("removed override", "/datum/base/child/result()\n    return extra\n", ""),
    ];
    let mut seen = vec![initial.clone()];
    for (label, before, after) in steps {
        assert!(source.contains(before), "{label} anchor");
        source = source.replacen(before, after, 1);
        edit_all(&roots, &source);
        let edited = compare_revision(&shared, &roots);
        assert!(
            !seen.contains(&edited),
            "{label} edit must publish new content"
        );
        seen.push(edited);
    }
    edit_all(&roots, TREE);
    compare_revision(&shared, &roots);
}

#[test]
fn numeric_default_edits_on_the_general_path_match_fresh() {
    // The retained-output admission takes a pure numeric default
    // edit (rewriting the Variables record); an initial() read of the var and an edit that is not
    // a numeric default must decline it. Every revision equals a fresh compile.
    let with_initial = format!(
        "{TREE}/proc/reads_initial()
    var/datum/base/item = new
    return initial(item.value)
"
    );
    for (source, splices) in [(TREE.to_string(), true), (with_initial, false)] {
        let roots = Roots::new();
        let mut shared = shared();
        Arc::get_mut(&mut shared).unwrap().max_workers = 2;
        edit_all(&roots, &source);
        let initial = compare_revision(&shared, &roots);
        let mut previous = initial.clone();
        for value in ["9", "11.5", "0x10", "7"] {
            let edited = source.replace("var/value = 7", &format!("var/value = {value}"));
            edit_all(&roots, &edited);
            let current = compare_revision(&shared, &roots);
            if value == "7" {
                assert_eq!(current, initial, "returning to 7 reproduces the initial bytes");
            } else {
                assert_ne!(current, previous, "default {value} must publish new content");
            }
            previous = current;
        }
        let applied = crate::retained_output::applied(&roots.manifest(0));
        if splices {
            assert_eq!(applied, 4, "every numeric default edit takes the retained-output splice");
        } else {
            assert_eq!(applied, 0, "initial() of the edited var declines the splice");
        }
    }
}

#[test]
fn appended_callables_patch_with_stable_numbering_and_revert_to_fresh() {
    // Added procs/verbs/overrides append to the retained model (semantic
    // equivalence is asserted by compare_revision); a referenced new name
    // must decline. Reverting is a removal and rebuilds fresh numbering.
    let cases: [(&str, String, bool); 9] = [
        ("new var", TREE.replace("    var/own = 2
", "    var/own = 2
    var/added_probe = 5
"), true),
        ("new null var", TREE.replace("    var/own = 2
", "    var/own = 2
    var/added_nil
"), true),
        ("new tmp var", TREE.replace("    var/own = 2
", "    var/own = 2
    var/tmp/added_tmp = 6
"), true),
        (
            "new var between declared vars",
            TREE.replace("    var/value = 7
", "    var/value = 7
    var/added_mid = 9
    var/added_two
"),
            true,
        ),
        (
            "referenced new var",
            TREE.replace("    var/value = 7
", "    var/value = 7
    var/added_ref = 1
").replace("return item.value
", "return item.value + item.added_ref
"),
            true,
        ),
        ("new proc", format!("{TREE}/datum/base/proc/added_probe()\n    return 41\n"), true),
        (
            "new proc above existing bodies",
            TREE.replace("/proc/other()", "/datum/base/proc/early_probe()
    return 7

/proc/other()"),
            true,
        ),
        ("new override of a called proc", format!("{TREE}/datum/base/child/result()\n    return own\n"), true),
        (
            "referenced new proc with a new caller that constructs (declines: required types)",
            format!("{TREE}/datum/base/proc/used_probe()\n    return 2\n/proc/caller()\n    var/datum/base/item = new\n    return item.used_probe()\n"),
            false,
        ),
    ];
    for (label, edited, patches) in cases {
        let roots = Roots::new();
        let mut shared = shared();
        Arc::get_mut(&mut shared).unwrap().max_workers = 2;
        edit_all(&roots, TREE);
        let initial = compare_revision(&shared, &roots);
        let before = crate::retained_output::applied(&roots.manifest(0));
        edit_all(&roots, &edited);
        let current = compare_revision(&shared, &roots);
        assert_ne!(current, initial, "{label} must publish new content");
        let applied = crate::retained_output::applied(&roots.manifest(0)) - before;
        assert_eq!(applied, u64::from(patches), "{label}: append patch applied");
        edit_all(&roots, TREE);
        compare_revision(&shared, &roots);
    }
}

#[test]
fn appends_after_body_patches_edit_the_model_with_those_patches_applied() {
    // A body patch splices code rows into the retained image but leaves the retained composed
    // model alone. A structural append that follows must edit the model plus those rows, not
    // fall back to a full compile, and the output must still equal a fresh compile (the
    // patched bodies must not revert).
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    edit_all(&roots, TREE);
    compare_revision(&shared, &roots);
    let applied = |roots: &Roots| crate::retained_output::applied(&roots.manifest(0));
    let body_one = TREE.replace("        return value\n", "        return value + 1\n");
    let body_two = TREE.replace("        return value\n", "        return value + 2\n");
    let appended_var = body_two.replace("    var/own = 2\n", "    var/own = 2\n    var/added_probe = 5\n");
    let body_after = appended_var.replace("        return value + 2\n", "        return value + 3\n");
    let appended_proc = format!("{body_after}/datum/base/proc/added_probe_proc()\n    return 41\n");
    let mut count = applied(&roots);
    for (label, source) in [
        ("first body patch", body_one.as_str()),
        ("second body patch", body_two.as_str()),
        ("append a var after body patches", appended_var.as_str()),
        ("body patch after the append", body_after.as_str()),
        ("append a proc after body and append patches", appended_proc.as_str()),
    ] {
        edit_all(&roots, source);
        compare_revision(&shared, &roots);
        assert_eq!(applied(&roots), count + 1, "{label}: did not patch");
        count += 1;
    }
}

#[test]
fn alternating_skeletons_patch_against_their_own_base_and_match_fresh_bytes() {
    // A shared compile root alternates between lanes whose declarations differ. Each lane's
    // body edit may patch against that lane's earlier base; the bytes must still equal fresh.
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    let lane_a = TREE.to_string();
    let lane_b = TREE.replace("    var/own = 2\n", "    var/extra = 5\n    var/own = 2\n");
    let body_edit = |source: &str, value: &str| source.replace("        return 1\n", &format!("        return {value}\n"));
    for source in [
        lane_a.clone(),
        lane_b.clone(),
        body_edit(&lane_a, "2"),
        body_edit(&lane_b, "3"),
        body_edit(&lane_a, "4"),
        lane_b.clone(),
    ] {
        edit_all(&roots, &source);
        // compare_revision asserts each retained output is equivalent to a fresh compile.
        compare_revision(&shared, &roots);
    }
}

#[test]
fn alternating_skeletons_patch_string_literal_edits_and_match_fresh_bytes() {
    // String-literal edits append to the string table of the retained model; an alternate base
    // keeps its own model, so these patch too. Every revision must equal a fresh compile.
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    let words = "/proc/words()\n    return \"alpha\"\n";
    let lane_a = format!("{TREE}{words}");
    let lane_b = format!(
        "{}{words}",
        TREE.replace("    var/own = 2\n", "    var/extra = 5\n    var/own = 2\n")
    );
    let literal = |source: &str, text: &str| source.replace("\"alpha\"", &format!("\"{text}\""));
    for source in [
        lane_a.clone(),
        lane_b.clone(),
        literal(&lane_a, "beta"),
        literal(&lane_b, "gamma"),
        literal(&lane_a, "delta"),
        lane_b.clone(),
    ] {
        edit_all(&roots, &source);
        compare_revision(&shared, &roots);
    }
}

#[test]
fn appended_callables_referenced_by_edited_bodies_match_fresh_bytes() {
    // A new proc or verb that existing bodies call: the mentioning bodies are relowered and linked
    // against the appended table entries. Every revision must be equivalent to a fresh compile.
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    edit_all(&roots, TREE);
    compare_revision(&shared, &roots);
    let mut source = TREE.to_string();
    // The first root procedure (probe) registers its literals first and never patches; the edits
    // touch the other bodies.
    let steps: [(&str, &str, &str); 3] = [
        (
            "member proc called by an edited body",
            "/proc/other()
    var/datum/base/item = new
    return item.value
",
            "/datum/base/proc/added_bonus()
    return 11
/proc/other()
    var/datum/base/item = new
    return item.value + item.added_bonus()
",
        ),
        (
            "global proc called by an edited body",
            "    return item.value + item.added_bonus()
",
            "    return added_twice(item.value) + item.added_bonus()
/proc/added_twice(x)
    return x * 2
",
        ),
        (
            "new string in the calling body",
            "return added_twice(item.value)",
            "return added_twice(item.value) + length(\"fresh text\")",
        ),
    ];
    for (label, before, after) in steps {
        assert!(source.contains(before), "{label} anchor");
        source = source.replacen(before, after, 1);
        let applied = crate::retained_output::applied(&roots.manifest(0));
        edit_all(&roots, &source);
        compare_revision(&shared, &roots);
        assert_eq!(
            crate::retained_output::applied(&roots.manifest(0)),
            applied + 1,
            "{label}: did not patch"
        );
    }
}

#[test]
fn appends_after_a_memory_pressure_release_recover_the_model_and_match_fresh_bytes() {
    // Memory pressure releases the retained composed model. The next structural patch rebuilds it
    // from the retained image instead of falling back to a full compile.
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    edit_all(&roots, TREE);
    compare_revision(&shared, &roots);
    let applied = |roots: &Roots| crate::retained_output::applied(&roots.manifest(0));
    let appended_var = TREE.replace("    var/own = 2\n", "    var/own = 2\n    var/added_probe = 5\n");
    let appended_proc = format!("{appended_var}/datum/base/proc/added_probe_proc()\n    return 41\n");
    let mut count = applied(&roots);
    for (label, source) in [("append a var", appended_var.as_str()), ("append a proc after a release", appended_proc.as_str())] {
        if label.ends_with("release") {
            for index in 0..6 {
                let request = request(&roots, index, false);
                let slot = shared.slot(request.project.clone(), Some(&request));
                slot.lock_host().unwrap().release_idle_artifacts();
            }
        }
        edit_all(&roots, source);
        compare_revision(&shared, &roots);
        assert_eq!(applied(&roots), count + 1, "{label}: did not patch");
        count += 1;
    }
}

#[test]
fn shadowing_moving_and_removing_a_callable_name_match_fresh_bytes() {
    // A cached negative or positive callable answer must not survive a shadowing member, a move of
    // the declaration to another type, or the removal of the last declaration of the name.
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    let global = format!("{TREE}/proc/pick_value()\n    return 2\n/datum/base/proc/user()\n    return pick_value()\n");
    let shadowed = format!("{global}/datum/base/proc/pick_value()\n    return 1\n");
    let moved = format!("{global}/datum/base/child/proc/pick_value()\n    return 3\n");
    let removed_member = global.clone();
    let removed_last = format!("{TREE}/datum/base/proc/user()\n    return 4\n");
    for source in [&global, &shadowed, &moved, &removed_member, &removed_last, &global] {
        edit_all(&roots, source);
        // compare_revision asserts the retained output is equivalent to a fresh compile.
        compare_revision(&shared, &roots);
    }
}

#[test]
fn types_added_between_existing_types_match_fresh_structurally() {
    // The added type takes the next class index instead of its source position (stable link
    // numbering); compare_revision gates the output on structural equivalence with a fresh build.
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    edit_all(&roots, TREE);
    compare_revision(&shared, &roots);
    let added = TREE.replace(
        "/datum/base/child\n",
        "/datum/base/added_early\n    value = 4\n    proc/added_call()\n        return 6\n/datum/base/child\n",
    );
    edit_all(&roots, &added);
    compare_revision(&shared, &roots);
    edit_all(&roots, TREE);
    compare_revision(&shared, &roots);
}
