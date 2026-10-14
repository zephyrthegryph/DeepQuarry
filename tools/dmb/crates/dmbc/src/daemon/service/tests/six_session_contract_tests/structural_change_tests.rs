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
        assert_eq!(
            compare_revision(&shared, &roots),
            initial,
            "reverting the {label} edit must reproduce the initial bytes"
        );
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
    assert_eq!(compare_revision(&shared, &roots), initial);
}

#[test]
fn numeric_default_edits_match_fresh_with_and_without_initial_reads() {
    // Plain numeric default edits take the default patch; a body reading
    // initial() of the edited var must decline it. Both must equal fresh.
    let with_initial = format!(
        "{TREE}/proc/reads_initial()\n    var/datum/base/item = new\n    return initial(item.value)\n"
    );
    for (source, patches) in [(TREE.to_string(), true), (with_initial, false)] {
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
        let applied = crate::body_patch::applied(&roots.manifest(0));
        if patches {
            assert_eq!(applied, 4, "every numeric default edit takes the default patch");
        } else {
            assert_eq!(applied, 0, "initial() of the edited var declines the default patch");
        }
    }
}

#[test]
fn appended_callables_patch_with_stable_numbering_and_revert_to_fresh() {
    // Added procs/verbs/overrides append to the retained model (semantic
    // equivalence is asserted by compare_revision); a referenced new name
    // must decline. Reverting is a removal and rebuilds fresh numbering.
    let cases: [(&str, String, bool); 4] = [
        ("new proc", format!("{TREE}/datum/base/proc/added_probe()\n    return 41\n"), true),
        (
            "new proc above existing bodies",
            TREE.replace("/proc/other()", "/datum/base/proc/early_probe()
    return 7

/proc/other()"),
            true,
        ),
        ("new override of a called proc (declines)", format!("{TREE}/datum/base/child/result()\n    return own\n"), false),
        (
            "referenced new proc",
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
        let before = crate::body_patch::applied(&roots.manifest(0));
        edit_all(&roots, &edited);
        let current = compare_revision(&shared, &roots);
        assert_ne!(current, initial, "{label} must publish new content");
        let applied = crate::body_patch::applied(&roots.manifest(0)) - before;
        assert_eq!(applied, u64::from(patches), "{label}: append patch applied");
        edit_all(&roots, TREE);
        assert_eq!(compare_revision(&shared, &roots), initial, "{label}: revert reproduces initial bytes");
    }
}
