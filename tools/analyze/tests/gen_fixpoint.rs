//! `analyze gen` reaches the same files from any starting point: a fresh tree, a tree seeded with stale or empty generated files, and a second run.
//! Stage 1 generators (`tracked_lists`, `deps`, `reads`, `derived_reads`) share one pass; `deps` and `reads` parse a model that includes the
//! `tracked_lists.dm` the same pass rewrites, so this guards that no stage-1 output depends on another stage-1 file's earlier content.
//! The shared store and the memo are off: they would hand back a good run's files and prove nothing.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

const SOURCE: &str = "/datum/look
\tproc/state(x)
\t\treturn
/obj/thing
\tvar/list/items
\tvar/glow = 0
\tvar/hue = 1
/obj/thing/draw(datum/look/look)
\tlook.state(\"x[items]-[glow]\")
/obj/thing/proc/put(x)
\titems += x
\tglow = 1
/obj/thing/proc/tint(h)
\thue = h
";

fn read_all(tree: &Path) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for dir in ["code/engine/_generated", "code/_generated"] {
        if let Ok(rd) = std::fs::read_dir(tree.join(dir)) {
            for e in rd.flatten() {
                if e.path().is_file() {
                    out.insert(format!("{}/{}", dir, e.file_name().to_string_lossy()), std::fs::read_to_string(e.path()).unwrap().replace("\r\n", "\n"));
                }
            }
        }
    }
    out
}

fn make_tree(base: &Path, name: &str, repo: &Path) -> PathBuf {
    let tree = base.join(name);
    std::fs::create_dir_all(tree.join("code")).unwrap();
    std::fs::write(tree.join("code/a.dm"), SOURCE).unwrap();
    std::fs::create_dir_all(tree.join("tools/ci")).unwrap();
    std::fs::copy(repo.join("tools/ci/lint_scopes.toml"), tree.join("tools/ci/lint_scopes.toml")).unwrap();
    tree
}

#[test]
fn gen_output_is_the_same_fresh_seeded_and_on_a_second_run() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let repo = manifest.parent().unwrap().parent().unwrap();
    let base = std::env::temp_dir().join(format!("dq-gen-fixpoint-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    std::env::set_var("DQ_GEN_STORE", "off");
    let fresh = make_tree(&base, "fresh", repo);
    std::env::set_var("DQ_ANALYZE_CACHE", base.join("cache-fresh"));
    let _ = dq_analyze::sem::cli::gen(&[], &fresh);
    let want = read_all(&fresh);
    assert!(want.get("code/engine/_generated/tracked_lists.dm").is_some_and(|t| t.contains("add_items")), "the fixture must make stage 1 write list mutators");

    // A second run on the same tree: nothing changes.
    std::env::set_var("DQ_ANALYZE_CACHE", base.join("cache-second"));
    let _ = dq_analyze::sem::cli::gen(&[], &fresh);
    assert_eq!(read_all(&fresh), want, "a second gen run changed a file");

    // Seeded with stale, empty and half-written generated files, then run twice.
    for (n, seed) in [("stale", "// stale\n"), ("empty", "")].iter().enumerate() {
        let tree = make_tree(&base, &format!("seeded{n}"), repo);
        std::fs::create_dir_all(tree.join("code/engine/_generated")).unwrap();
        std::fs::create_dir_all(tree.join("code/_generated")).unwrap();
        for f in want.keys() {
            std::fs::write(tree.join(f), seed.1).unwrap();
        }
        std::env::set_var("DQ_ANALYZE_CACHE", base.join(format!("cache-seed{n}")));
        let _ = dq_analyze::sem::cli::gen(&[], &tree);
        let first = read_all(&tree);
        assert_eq!(first, want, "a tree seeded with {:?} generated files differs from a fresh one after one run", seed.0);
        let _ = dq_analyze::sem::cli::gen(&[], &tree);
        assert_eq!(read_all(&tree), want, "the second run on a seeded tree changed a file");
    }
    let _ = std::fs::remove_dir_all(&base);
}
