//! `analyze gen` remembers a converged run (`gen-state.bin`) and shares its outputs between worktrees through a content-addressed
//! store (`DQ_GEN_STORE`): a run whose inputs and outputs are unchanged does nothing, and a tree that meets inputs the store already holds
//! gets the files copied instead of generated. One test, because both are selected with process-wide environment variables.

use std::path::{Path, PathBuf};

fn mtime(p: &Path) -> std::time::SystemTime {
    std::fs::metadata(p).unwrap().modified().unwrap()
}

#[test]
fn gen_returns_at_once_when_nothing_changed_and_restores_from_the_shared_store() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let repo = manifest.parent().unwrap().parent().unwrap();
    let base = std::env::temp_dir().join(format!("dq-gen-memo-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    let tree = base.join("tree");
    // A tree that declares nothing: every generator is clean and writes its (empty) file.
    std::fs::create_dir_all(tree.join("code")).unwrap();
    std::fs::write(tree.join("code/a.dm"), "/obj/thing
	name = \"thing\"
").unwrap();
    std::fs::create_dir_all(tree.join("tools/ci")).unwrap();
    std::fs::copy(repo.join("tools/ci/lint_scopes.toml"), tree.join("tools/ci/lint_scopes.toml")).unwrap();
    let (store, cache) = (base.join("store"), base.join("cache"));
    std::env::set_var("DQ_GEN_STORE", &store);
    std::env::set_var("DQ_ANALYZE_CACHE", &cache);
    let out = tree.join("code/engine/_generated/system_accessors.dm");

    // 1. Generates, records the memo, fills the store.
    let _ = dq_analyze::sem::cli::gen(&[], &tree);
    assert!(out.exists(), "gen wrote nothing");
    assert!(cache.join("gen-state.bin").exists(), "no memo");
    let entries: Vec<_> = std::fs::read_dir(&store).unwrap().filter_map(|e| e.ok()).collect();
    assert_eq!(entries.len(), 1, "the store should hold the one run");
    let written = mtime(&out);

    // 2. Nothing changed: nothing is rewritten.
    std::thread::sleep(std::time::Duration::from_millis(50));
    let _ = dq_analyze::sem::cli::gen(&[], &tree);
    assert_eq!(mtime(&out), written, "an unchanged run rewrote a file");

    // 3. A hand edit of an output is noticed (the memo checks the outputs' digests) and repaired.
    let good = std::fs::read_to_string(&out).unwrap();
    std::fs::write(&out, format!("{}/proc/hand()\n", good)).unwrap();
    let _ = dq_analyze::sem::cli::gen(&[], &tree);
    assert_eq!(std::fs::read_to_string(&out).unwrap().replace("\r\n", "\n"), good.replace("\r\n", "\n"), "the edited output was not regenerated");

    // 4. A new worktree of the same inputs: no outputs, no memo, a fresh analysis cache. The store gives the files back.
    std::fs::remove_dir_all(tree.join("code/engine/_generated")).unwrap();
    std::fs::remove_dir_all(&cache).unwrap();
    let _ = dq_analyze::sem::cli::gen(&[], &tree);
    assert_eq!(std::fs::read_to_string(&out).unwrap().replace("\r\n", "\n"), good.replace("\r\n", "\n"), "the store did not restore the output");
    assert!(cache.join("gen-state.bin").exists(), "the restore left no memo");
    let entries: Vec<_> = std::fs::read_dir(&store).unwrap().filter_map(|e| e.ok()).collect();
    assert_eq!(entries.len(), 1, "the same inputs must not add a second entry");

    // 5. Different inputs are a different entry.
    std::fs::write(tree.join("code/zz_new.dm"), "/obj/zz_new\n").unwrap();
    let _ = dq_analyze::sem::cli::gen(&[], &tree);
    let entries: Vec<_> = std::fs::read_dir(&store).unwrap().filter_map(|e| e.ok()).collect();
    assert_eq!(entries.len(), 2, "changed inputs should be stored apart");
    let _ = std::fs::remove_dir_all(&base);
}
