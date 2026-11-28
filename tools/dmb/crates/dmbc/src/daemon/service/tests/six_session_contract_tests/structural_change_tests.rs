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
        // Every table is numbered in fresh order, so the revert reproduces the initial bytes.
        let reverted = compare_revision(&shared, &roots);
        assert_eq!(reverted[0], initial[0], "{label}: revert must reproduce the initial bytes");
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
fn added_callables_and_vars_compose_in_fresh_order_and_revert() {
    // An added proc, verb, override or var composes the whole program: its new keys take their fresh positions in the
    // procedure and string tables (`typesof(/T/proc)` and `vars` iterate those orders), so the retained output is
    // byte-identical to a fresh compile, never appended at the end of the tables. Reverting reproduces the initial bytes.
    let cases: [(&str, String); 9] = [
        ("new var", TREE.replace("    var/own = 2
", "    var/own = 2
    var/added_probe = 5
")),
        ("new null var", TREE.replace("    var/own = 2
", "    var/own = 2
    var/added_nil
")),
        ("new tmp var", TREE.replace("    var/own = 2
", "    var/own = 2
    var/tmp/added_tmp = 6
")),
        (
            "new var between declared vars",
            TREE.replace("    var/value = 7
", "    var/value = 7
    var/added_mid = 9
    var/added_two
"),
        ),
        (
            "referenced new var",
            TREE.replace("    var/value = 7
", "    var/value = 7
    var/added_ref = 1
").replace("return item.value
", "return item.value + item.added_ref
"),
        ),
        ("new proc", format!("{TREE}/datum/base/proc/added_probe()\n    return 41\n")),
        (
            "new proc above existing bodies",
            TREE.replace("/proc/other()", "/datum/base/proc/early_probe()
    return 7

/proc/other()"),
        ),
        ("new override of a called proc", format!("{TREE}/datum/base/child/result()\n    return own\n")),
        (
            "referenced new proc with a new caller that constructs",
            format!("{TREE}/datum/base/proc/used_probe()\n    return 2\n/proc/caller()\n    var/datum/base/item = new\n    return item.used_probe()\n"),
        ),
    ];
    for (label, edited) in cases {
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
        assert_eq!(applied, 0, "{label}: a declaration add never patches the retained output");
        edit_all(&roots, TREE);
        let reverted = compare_revision(&shared, &roots);
        assert_eq!(reverted, initial, "{label}: revert must reproduce the initial bytes");
    }
}

#[test]
fn body_patches_resume_after_declaration_adds_that_compose_fresh() {
    // Body patches splice code rows into the retained image; an added var or proc between them composes the whole
    // program in fresh order (byte-identical to a fresh compile), and the next body edit patches against that output.
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
    for (label, source, patches) in [
        ("first body patch", body_one.as_str(), true),
        ("second body patch", body_two.as_str(), true),
        ("add a var after body patches", appended_var.as_str(), false),
        ("body patch after the add", body_after.as_str(), true),
        ("add a proc after body patches", appended_proc.as_str(), false),
    ] {
        edit_all(&roots, source);
        compare_revision(&shared, &roots);
        count += u64::from(patches);
        assert_eq!(applied(&roots), count, "{label}: patched {patches}");
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
    // Building on each lane's stored base is `variant_spill_tests::lanes_with_different_declarations_build_on_their_own_stored_base`.
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
fn added_callables_referenced_by_edited_bodies_match_fresh_bytes() {
    // A new proc that existing bodies call composes the whole program (fresh procedure order); a later string literal
    // added to a calling body is a body patch. Every revision must be equivalent to a fresh compile.
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    edit_all(&roots, TREE);
    compare_revision(&shared, &roots);
    let mut source = TREE.to_string();
    // The first root procedure (probe) registers its literals first and never patches; the edits
    // touch the other bodies.
    let steps: [(&str, &str, &str, bool); 3] = [
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
            false,
        ),
        (
            "global proc called by an edited body",
            "    return item.value + item.added_bonus()
",
            "    return added_twice(item.value) + item.added_bonus()
/proc/added_twice(x)
    return x * 2
",
            false,
        ),
        (
            // A literal no string takes the place of moves every later string: the whole program composes.
            "new string in the calling body",
            "return added_twice(item.value)",
            "return added_twice(item.value) + length(\"fresh text\")",
            false,
        ),
    ];
    for (label, before, after, patches) in steps {
        assert!(source.contains(before), "{label} anchor");
        source = source.replacen(before, after, 1);
        let applied = crate::retained_output::applied(&roots.manifest(0));
        edit_all(&roots, &source);
        compare_revision(&shared, &roots);
        assert_eq!(
            crate::retained_output::applied(&roots.manifest(0)),
            applied + u64::from(patches),
            "{label}: patched {patches}"
        );
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
    // The added type takes its source position in the class table (`typesof()` order), as a fresh build numbers it.
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

#[derive(Clone, Copy, PartialEq)]
enum Step {
    /// A body edit: a body patch (a replaced literal takes the old one's table slot).
    Patch,
    /// An edit that composes the whole program: a declaration added or removed, or a literal added or dropped (later
    /// strings move).
    Compose,
    /// Either (blank lines above a type: code motion when the program text outside bodies compares equal).
    Any,
}

#[test]
fn edit_sequence_matches_a_fresh_compile_at_every_step() {
    // The edit kinds of tools/dmb/scripts/incremental_equiv_sequence.sh on a small tree, forward and reverted: every
    // retained output is byte-identical to a fresh compile, whether it was patched or composed.
    let base = format!(
        "{TREE}/proc/words()\n    return list(\"q-alpha\", \"q-shared\")\n/proc/more()\n    return list(\"q-shared\", \"q-omega\")\n"
    );
    let steps: Vec<(&str, Step, Box<dyn Fn(&str) -> String>)> = vec![
        ("body edit", Step::Patch, Box::new(|s: &str| s.replacen("        return 1\n", "        return 5\n", 1))),
        ("line shift", Step::Any, Box::new(|s: &str| s.replacen("/datum/base\n", "\n\n/datum/base\n", 1))),
        ("string literal", Step::Patch, Box::new(|s: &str| s.replacen("\"q-alpha\"", "\"q-beta\"", 1))),
        ("second literal edit", Step::Patch, Box::new(|s: &str| s.replacen("\"q-omega\"", "\"q-psi\"", 1))),
        ("literal added", Step::Compose, Box::new(|s: &str| s.replacen("\"q-beta\",", "\"q-beta\", \"q-added\",", 1))),
        ("literal shared with another proc", Step::Compose, Box::new(|s: &str| s.replacen("\"q-added\"", "\"q-psi\"", 1))),
        (
            "new var between declared vars",
            Step::Compose,
            Box::new(|s: &str| s.replacen("    var/value = 7\n", "    var/value = 7\n    var/added_mid = 9\n", 1)),
        ),
        (
            "new proc above existing bodies",
            Step::Compose,
            Box::new(|s: &str| s.replacen("/proc/other()", "/datum/base/proc/early_probe()\n    return 7\n/proc/other()", 1)),
        ),
        ("removed var", Step::Compose, Box::new(|s: &str| s.replacen("    var/own = 2\n", "", 1))),
        (
            "removed proc",
            Step::Compose,
            Box::new(|s: &str| s.replacen("    proc/helper()\n        return 5\n", "", 1).replacen(" + item.helper()", "", 1)),
        ),
    ];
    let roots = Roots::new();
    let mut shared = shared();
    Arc::get_mut(&mut shared).unwrap().max_workers = 2;
    edit_all(&roots, &base);
    let initial = compare_revision(&shared, &roots);
    let mut states = vec![base.clone()];
    for (_, _, edit) in &steps {
        let next = edit(states.last().unwrap());
        assert_ne!(&next, states.last().unwrap(), "every step edits the tree");
        states.push(next);
    }
    let applied = |roots: &Roots| crate::retained_output::applied(&roots.manifest(0));
    let run = |label: String, kind: Step, source: &str| {
        let before = applied(&roots);
        edit_all(&roots, source);
        let outputs = compare_revision(&shared, &roots);
        match kind {
            Step::Patch => assert!(applied(&roots) > before, "{label}: a body edit patches"),
            Step::Compose => assert_eq!(applied(&roots), before, "{label}: composes the whole program"),
            Step::Any => {}
        }
        outputs
    };
    for (index, (label, kind, _)) in steps.iter().enumerate() {
        run(label.to_string(), *kind, &states[index + 1]);
    }
    for (index, (label, kind, _)) in steps.iter().enumerate().rev() {
        run(format!("revert {label}"), *kind, &states[index]);
    }
    run("new var again".into(), Step::Compose, &states[7]);
    let last = run("revert to the initial tree".into(), Step::Compose, &base);
    assert_eq!(last, initial, "the initial tree must reproduce the initial bytes");
}
