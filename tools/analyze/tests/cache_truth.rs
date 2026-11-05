//! The analyzer's answer does not depend on which caches are warm. The tree has a `deepquarry.dme`, so the model comes from the model
//! store (`sem/model_store.rs`), the one cache whose reuse the first `analyze gen` pass of a fresh tree exercises: pass 1 parses a model
//! while the generated files do not exist yet (the `.dme` includes them, the preprocessor registers none), and pass 2 must not reuse that
//! model once they do. A store that compares only the files it registered serves the model without them, and every generator that reads
//! the model (`auto_tracked`, `plans`, `reads`, ...) then writes less than an uncached run does.
//!
//! Compared: an uncached run (model store, walk cache and body facts off), a fresh tree with every cache on, a second run (warm), and a
//! tree whose cache was filled by a different version of the sources (stale).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

const GENERATED: &[&str] = &["actions", "auto_tracked", "declare", "deps", "ids", "plans", "reads", "stats", "system_accessors", "tracked_lists"];

const SOURCE: &str = "/datum/look
\tproc/state(x)
\t\treturn
/obj/thing
\tvar/list/items
\tvar/glow = 0
\tvar/hue = 1
\tvar/cooldown = 0
/obj/thing/draw(datum/look/look)
\tlook.state(\"x[items]-[glow]-[cooldown]\")
/obj/thing/proc/put(x)
\titems += x
\tglow = 1
/obj/thing/proc/tint(h)
\thue = h
/obj/other/proc/start()
\tcooldown = 5
";

const OTHER_SOURCE: &str = "/datum/look
\tproc/state(x)
\t\treturn
/obj/thing
\tvar/hue = 1
/obj/thing/draw(datum/look/look)
\tlook.state(\"x[hue]\")
";

fn make_tree(base: &Path, name: &str, repo: &Path, source: &str) -> PathBuf {
    let tree = base.join(name);
    std::fs::create_dir_all(tree.join("code")).unwrap();
    std::fs::write(tree.join("code/a.dm"), source).unwrap();
    let mut dme = String::from("#include \"code/a.dm\"
");
    for g in GENERATED {
        dme.push_str(&format!("#include \"code/engine/_generated/{g}.dm\"
"));
    }
    dme.push_str("#include \"code/_generated/reads.dm\"
");
    std::fs::write(tree.join("deepquarry.dme"), dme).unwrap();
    std::fs::create_dir_all(tree.join("tools/ci")).unwrap();
    std::fs::copy(repo.join("tools/ci/lint_scopes.toml"), tree.join("tools/ci/lint_scopes.toml")).unwrap();
    tree
}

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

fn generate(tree: &Path, cache: &Path) -> BTreeMap<String, String> {
    std::env::set_var("DQ_ANALYZE_CACHE", cache);
    let _ = dq_analyze::sem::cli::gen(&[], tree);
    read_all(tree)
}

#[test]
fn gen_output_does_not_depend_on_the_caches() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let repo = manifest.parent().unwrap().parent().unwrap();
    let base = std::env::temp_dir().join(format!("dq-cache-truth-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    std::env::set_var("DQ_GEN_STORE", "off");
    std::env::set_var("DQ_ANALYZE_SHARED_CACHE", "off");

    // The truth: nothing is kept between passes.
    std::env::set_var("DQ_MODEL_STORE", "off");
    std::env::set_var("DQ_WALK_CACHE", "off");
    std::env::set_var("DQ_BODY_FACTS", "off");
    let plain = make_tree(&base, "plain", repo, SOURCE);
    let want = generate(&plain, &base.join("cache-plain"));
    assert!(want.get("code/engine/_generated/tracked_lists.dm").is_some_and(|t| t.contains("add_items")), "the fixture must make stage 1 write list mutators");
    std::env::remove_var("DQ_MODEL_STORE");
    std::env::remove_var("DQ_WALK_CACHE");
    std::env::remove_var("DQ_BODY_FACTS");

    // A fresh tree with every cache on.
    let fresh = make_tree(&base, "fresh", repo, SOURCE);
    let cache = base.join("cache-fresh");
    assert_eq!(generate(&fresh, &cache), want, "a fresh tree with the caches on differs from the uncached run");
    // The same tree again with the cache the first run left (warm), and after its generated files are deleted.
    assert_eq!(generate(&fresh, &cache), want, "a warm second run differs");
    let _ = std::fs::remove_dir_all(fresh.join("code/engine/_generated"));
    let _ = std::fs::remove_dir_all(fresh.join("code/_generated"));
    assert_eq!(generate(&fresh, &cache), want, "a warm cache over deleted generated files differs");

    // A cache filled by other sources, then the sources this test means.
    let stale = make_tree(&base, "stale", repo, OTHER_SOURCE);
    let stale_cache = base.join("cache-stale");
    let other = generate(&stale, &stale_cache);
    assert_ne!(other, want, "the stale fixture must differ from the real one");
    std::fs::write(stale.join("code/a.dm"), SOURCE).unwrap();
    assert_eq!(generate(&stale, &stale_cache), want, "a cache filled by other sources changed the answer");

    // The same cache directory copied to a new tree whose generated files do not exist (a seeded worktree).
    let seeded = make_tree(&base, "seeded", repo, SOURCE);
    let seeded_cache = base.join("cache-seeded");
    copy_dir(&stale_cache, &seeded_cache);
    assert_eq!(generate(&seeded, &seeded_cache), want, "a seeded cache over a fresh tree changed the answer");
    let _ = std::fs::remove_dir_all(&base);
}

fn copy_dir(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).unwrap();
    for e in std::fs::read_dir(from).unwrap().flatten() {
        let p = e.path();
        if p.is_file() {
            std::fs::copy(&p, to.join(e.file_name())).unwrap();
        }
    }
}
