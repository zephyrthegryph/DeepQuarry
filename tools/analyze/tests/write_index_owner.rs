//! The write index is keyed by the type that declares the var: a write of `cd` on one type is no write of an unrelated type's `cd`, a write
//! through a typed receiver reaches the declaring type and its subtypes, and a write through a receiver that cannot be typed stays
//! conservative (every var of that name) and is listed.

use std::path::PathBuf;

use dq_analyze::run::{Engine, Options};
use dq_analyze::sem::reads::WriteIndex;

const SOURCE: &str = "/obj/a
\tvar/cd = 0
\tvar/hue = 0
\tvar/idle = 0
/obj/a/sub
/obj/b
\tvar/cd = 0
\tvar/hue = 0
\tvar/idle = 0
/obj/b/proc/start()
\tcd = 5
/obj/c/proc/poke(obj/a/target)
\ttarget.idle = 1
/obj/d/proc/blind(thing)
\tthing.hue = 1
/obj/e/proc/local_only()
\tvar/cd = 0
\tcd = 2
/obj/f
\tvar/obj/a/held
/obj/f/proc/through_field()
\theld.cd = 3
";

#[test]
fn writes_are_keyed_by_the_declaring_type() {
    let base = std::env::temp_dir().join(format!("dq-write-index-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    std::fs::create_dir_all(base.join("code")).unwrap();
    std::fs::create_dir_all(base.join("tools/ci")).unwrap();
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf();
    std::fs::copy(repo.join("tools/ci/lint_scopes.toml"), base.join("tools/ci/lint_scopes.toml")).unwrap();
    std::fs::write(base.join("code/a.dm"), SOURCE).unwrap();
    let opts = Options { root: base.clone(), lints: vec!["sem/keys".to_string()], no_cache: true, raw: true, scopes_from: Some(repo), ..Default::default() };
    let engine = Engine::new(dq_analyze::run::registry(), opts).expect("engine");
    let sem = dq_analyze::sem::sem_for(&engine.tree).expect("model");
    let w = WriteIndex::build(&sem);
    let on = |t: &str, v: &str| w.is_written_on(&sem, t, v);

    // `cd = 5` in /obj/b writes b's cd. Only b's: another type's var of the same name is not written by it...
    // ... except through the typed field `held.cd = 3`, which reaches /obj/a's cd and its subtype's view of it.
    assert!(on("/obj/b", "cd"));
    assert!(on("/obj/a", "cd"));
    assert!(on("/obj/a/sub", "cd"), "a subtype sees its parent's var written");

    // Typed receiver, other direction: `target.idle = 1` writes /obj/a's idle and not /obj/b's.
    assert!(on("/obj/a", "idle"));
    assert!(on("/obj/a/sub", "idle"));
    assert!(!on("/obj/b", "idle"), "the same name on an unrelated type is not written");

    // An untyped receiver is conservative for every var of the name, and reported.
    assert!(on("/obj/a", "hue") && on("/obj/b", "hue"));
    assert!(w.untyped().contains("hue"));
    assert!(!w.untyped().contains("idle") && !w.untyped().contains("cd"));
    let _ = std::fs::remove_dir_all(&base);
}

#[test]
fn removing_the_only_writer_of_a_name_untracks_the_other_types() {
    // The reverse direction: the tree where nothing writes /obj/a's var but an unrelated type's same-named var is written.
    let base = std::env::temp_dir().join(format!("dq-write-index-rev-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&base);
    std::fs::create_dir_all(base.join("code")).unwrap();
    std::fs::create_dir_all(base.join("tools/ci")).unwrap();
    let repo = PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf();
    std::fs::copy(repo.join("tools/ci/lint_scopes.toml"), base.join("tools/ci/lint_scopes.toml")).unwrap();
    std::fs::write(base.join("code/a.dm"), "/obj/a\n\tvar/print_cooldown = 60\n/obj/lib\n\tvar/print_cooldown = 0\n/obj/lib/proc/print()\n\tsrc.print_cooldown = world.time\n").unwrap();
    let opts = Options { root: base.clone(), lints: vec!["sem/keys".to_string()], no_cache: true, raw: true, scopes_from: Some(repo), ..Default::default() };
    let engine = Engine::new(dq_analyze::run::registry(), opts).expect("engine");
    let sem = dq_analyze::sem::sem_for(&engine.tree).expect("model");
    let w = WriteIndex::build(&sem);
    assert!(w.is_written_on(&sem, "/obj/lib", "print_cooldown"));
    assert!(!w.is_written_on(&sem, "/obj/a", "print_cooldown"), "a constant is not made reactive by a same-named var elsewhere");
    assert!(w.untyped().is_empty());
    let _ = std::fs::remove_dir_all(&base);
}
