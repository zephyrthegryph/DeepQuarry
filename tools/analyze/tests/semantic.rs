//! Tests of the semantic layer (E5): the reads engine on fixture handlers, ranks and cycles, the
//! generators against goldens, and staleness. The lint fixtures (`fixtures/sem__*/expected.txt`)
//! are held by `fixtures.rs` with every other lint; these tests hold what a findings list cannot
//! show: the exact reads a handler generates, and the generated files.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use dq_analyze::run::{Engine, Options};
use dq_analyze::sem::decls::Decls;
use dq_analyze::sem::gen::{self, GenCx, State};
use dq_analyze::sem::graph::{render_ranks, DepGraph};
use dq_analyze::sem::reads::{Annotations, ReadsEngine};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().parent().unwrap().to_path_buf()
}

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("fixtures").join(name)
}

fn engine_on(dir: &Path) -> Engine {
    let opts = Options { root: dir.to_path_buf(), lints: vec!["sem/keys".to_string()], no_cache: true, raw: true, scopes_from: Some(repo_root()), ..Default::default() };
    Engine::new(dq_analyze::run::registry(), opts).expect("engine")
}

fn keys(set: &dq_analyze::sem::reads::ReadSet) -> BTreeSet<String> {
    set.keys()
}

fn want(items: &[&str]) -> BTreeSet<String> {
    items.iter().map(|s| s.to_string()).collect()
}

#[test]
fn generated_reads_on_fixture_handlers_are_exact() {
    let engine = engine_on(&fixture("sem__reads"));
    let sem = dq_analyze::sem::sem_for(&engine.tree).expect("model");
    let decls = Decls::get(&engine.tree);
    let ann = Annotations::get(&sem, &decls);
    let eng = ReadsEngine::new(&sem, &decls, &ann);
    let apc = "/obj/machinery/apc";

    // A relation hop and a READS_FROM helper followed through its argument.
    assert_eq!(keys(&eng.analyze_handler(apc, "cell_low", "/datum/act/eval")), want(&["cell", "limit", "cell.charge", "cell.maxcharge"]));
    // Context hops: A.actor and A.held are typed hops, subscribed per pending op.
    assert_eq!(keys(&eng.analyze_handler(apc, "actor_busy", "/datum/act/op")), want(&["@actor:pocket", "@actor:stat", "@actor:pocket.charge"]));
    assert_eq!(keys(&eng.analyze_handler(apc, "held_charge", "/datum/act/op")), want(&["@held:charge"]));
    // A system accessor is followed to the system's tracked var; a READS_AS accessor is not followed.
    assert_eq!(keys(&eng.analyze_handler(apc, "night_user", "/datum/act/eval")), want(&["on", "@system:nightshift:nightshift_active"]));
    assert_eq!(keys(&eng.analyze_handler(apc, "accessor_user", "/datum/act/eval")), want(&["PAD_KEY"]));
    // READS_FROM() says a helper reads nothing; a two-argument helper follows only the named one.
    assert_eq!(keys(&eng.analyze_handler(apc, "pure_user", "/datum/act/eval")), want(&["limit"]));
    assert_eq!(keys(&eng.analyze_handler(apc, "two_arg_user", "/datum/act/eval")), want(&["cell", "limit", "cell.charge"]));
    // A same-type helper is followed.
    assert_eq!(keys(&eng.analyze_handler(apc, "calls_ctx_free", "/datum/act/eval")), want(&["cell", "cell.rating"]));
    // Loops and locals add no reads of their own; every read is kept whichever branch it sits in.
    assert_eq!(keys(&eng.analyze_handler(apc, "loops", "/datum/act/eval")), want(&["on"]));
    // A global helper with no annotation is a diagnostic, never a silent miss.
    let bad = eng.analyze_handler(apc, "bad_global", "/datum/act/eval");
    assert!(bad.diags.iter().any(|d| d.rule == "unannotated_global"), "{:?}", bad.diags);
    // vars[] is a diagnostic.
    assert!(eng.analyze_handler(apc, "dynamic", "/datum/act/eval").diags.iter().any(|d| d.rule == "dynamic_read"));
    // A hop through a var that is not a declared relation keeps the read and flags the hop.
    let spare = eng.analyze_handler(apc, "via_spare", "/datum/act/eval");
    assert!(spare.reads.iter().any(|r| r.key() == "spare.charge" && !r.hop_ok));
    assert!(spare.diags.iter().any(|d| d.rule == "hop_not_relation"));
}

#[test]
fn requirement_protocol_preserves_reads_and_validates_each_callback_return_shape() {
    let engine = engine_on(&fixture("sem__requirement_protocol"));
    let analysis = dq_analyze::sem::handlers::analyzed(&engine.tree).expect("requirement handlers analyzed");
    let handler = |name: &str| analysis.handlers.iter().find(|handler| handler.h.proc == name).expect("fixture callback resolved");
    for name in ["null_answer", "bare_answer", "text_answer", "datum_answer", "old_boolean", "old_reason"] {
        assert!(handler(name).proc_found, "{} resolves", name);
        assert!(handler(name).returns.is_empty(), "{}: {:?}", name, handler(name).returns);
    }
    for name in ["boolean_answer", "list_answer", "old_text"] {
        assert_eq!(handler(name).returns.len(), 1, "{} has one invalid return", name);
    }
    assert_eq!(handler("old_boolean").h.role, dq_analyze::sem::hooks::Role::BooleanRequirement);
    assert_eq!(handler("old_reason").h.role, dq_analyze::sem::hooks::Role::Reason);
    for name in ["text_answer", "old_boolean"] {
        let reads = handler(name).set.as_ref().expect("callback reads analyzed");
        assert!(reads.reads.iter().any(|read| read.var == "available"), "{} keeps tracked reads", name);
    }
}

#[test]
fn a_cycle_is_named_and_has_no_order() {
    let engine = engine_on(&fixture("sem__reads"));
    let sem = dq_analyze::sem::sem_for(&engine.tree).expect("model");
    let decls = Decls::get(&engine.tree);
    let ann = Annotations::get(&sem, &decls);
    let eng = ReadsEngine::new(&sem, &decls, &ann);
    let g = DepGraph::from_derives(&sem, &eng);
    let cycles = g.cycles();
    assert_eq!(cycles.len(), 1, "{:?}", cycles);
    assert!(cycles[0].iter().any(|n| n.ends_with("::derived_a")) && cycles[0].iter().any(|n| n.ends_with("::derived_b")));
    assert!(g.ranks().is_err(), "a cycle has no evaluation order");
}

#[test]
fn ranks_follow_the_golden() {
    let dir = fixture("sem__ranks");
    let engine = engine_on(&dir);
    let sem = dq_analyze::sem::sem_for(&engine.tree).expect("model");
    let decls = Decls::get(&engine.tree);
    let ann = Annotations::get(&sem, &decls);
    let eng = ReadsEngine::new(&sem, &decls, &ann);
    let g = DepGraph::from_derives(&sem, &eng);
    assert!(g.cycles().is_empty());
    let actual = render_ranks(&g.ranks().expect("acyclic"));
    assert_eq!(actual, golden_or_bless(&dir, "ranks.golden", &actual));
}

#[test]
fn a_handlers_rank_is_one_past_the_deepest_derived_value_it_reads() {
    let dir = fixture("sem__ranks");
    let (text, diags) = gen_text(&dir, "reads");
    assert_eq!(diags, 0);
    assert!(text.contains("\"/obj/machinery/chain::ready\" = list(3,"), "{}", text);
    assert!(text.contains("\"/obj/machinery/chain::raw\" = list(0,"), "{}", text);
    assert_eq!(text, golden_or_bless(&dir, "generated_reads.golden", &text));
}

fn gen_text(dir: &Path, name: &str) -> (String, usize) {
    let engine = engine_on(dir);
    let cx = GenCx::new(&engine.tree, dir);
    let g = gen::registry().into_iter().find(|g| g.name() == name).expect("generator");
    let (text, diags) = gen::render(g.as_ref(), &cx);
    (text, diags.len())
}

/// The golden's text. `BLESS_GOLDENS=1 cargo test` rewrites it from the current output (review the diff).
fn golden_or_bless(dir: &Path, file: &str, actual: &str) -> String {
    if std::env::var("BLESS_GOLDENS").is_ok() {
        std::fs::write(dir.join(file), actual).unwrap();
    }
    std::fs::read_to_string(dir.join(file)).unwrap_or_else(|_| panic!("missing golden {} (BLESS_GOLDENS=1 writes it)", file)).replace("\r\n", "\n")
}

#[test]
fn the_reads_generator_matches_its_golden() {
    let dir = fixture("sem__reads");
    let (text, diags) = gen_text(&dir, "reads");
    // The fixture's unannotated/dynamic handlers are the generator's diagnostics too.
    assert!(diags >= 2, "diags {}", diags);
    assert_eq!(text, golden_or_bless(&dir, "generated_reads.golden", &text));
}

#[test]
fn the_system_accessor_generator_matches_its_golden_and_names_bad_accessors() {
    let dir = fixture("sem__keys");
    let (text, diags) = gen_text(&dir, "system_accessors");
    assert_eq!(diags, 2, "lamps_dim (no var) and ghost_value (no system)");
    assert_eq!(text, golden_or_bless(&dir, "generated_system_accessors.golden", &text));
}

#[test]
fn a_stale_generated_file_fails_the_check_and_a_rewrite_freshens_it() {
    let src = fixture("sem__keys");
    let tmp = std::env::temp_dir().join(format!("dq-gen-stale-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&tmp);
    copy_dir(&src, &tmp);
    let engine = engine_on(&tmp);
    let names = vec!["system_accessors".to_string()];
    // Missing file: stale.
    let r = gen::run(&tmp, &engine.tree, &names, true);
    assert_eq!(r[0].state, State::Stale);
    // Written.
    let r = gen::run(&tmp, &engine.tree, &names, false);
    assert_eq!(r[0].state, State::Written);
    let r = gen::run(&tmp, &engine.tree, &names, true);
    assert_eq!(r[0].state, State::Fresh);
    // A hand edit makes it stale again.
    let path = tmp.join(gen::OUT_DIR).join("system_accessors.dm");
    let mut text = std::fs::read_to_string(&path).unwrap();
    text.push_str("/proc/hand_written()\n\treturn 1\n");
    std::fs::write(&path, text).unwrap();
    let r = gen::run(&tmp, &engine.tree, &names, true);
    assert_eq!(r[0].state, State::Stale);
    let _ = std::fs::remove_dir_all(&tmp);
}

fn copy_dir(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).unwrap();
    for e in std::fs::read_dir(from).unwrap() {
        let e = e.unwrap();
        let p = e.path();
        let dest = to.join(e.file_name());
        if p.is_dir() {
            copy_dir(&p, &dest);
        } else {
            std::fs::copy(&p, &dest).unwrap();
        }
    }
}

#[test]
fn a_tree_that_declares_no_handler_is_never_parsed_by_the_semantic_lints() {
    let tmp = std::env::temp_dir().join(format!("dq-no-handlers-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&tmp);
    std::fs::create_dir_all(tmp.join("code")).unwrap();
    std::fs::write(tmp.join("code/a.dm"), "STAT(/atom, density, TOP)
SOURCE_DEF(status)
/obj/thing
	name = \"x\"
").unwrap();
    let engine = engine_on(&tmp);
    assert!(dq_analyze::sem::handlers::analyzed(&engine.tree).is_none());
    let _ = std::fs::remove_dir_all(&tmp);
}

#[test]
fn the_ui_types_generator_writes_the_typescript_of_a_declared_window() {
    let dir = fixture("sem__ui");
    let engine = engine_on(&dir);
    let cx = GenCx::new(&engine.tree, &dir);
    let g = gen::registry().into_iter().find(|g| g.name() == "ui_types").expect("generator");
    let mut out = gen::GenOut::default();
    let files = g.files(&cx, &mut out);
    assert!(out.diags.is_empty(), "{:?}", out.diags);
    assert_eq!(files.len(), 1, "one window, one file");
    assert_eq!(files[0].0, "tgui/packages/tgui/interfaces/generated/PumpDemo.d.ts");
    let text = &files[0].1;
    assert!(text.contains("/** num 0..MAX_PUMP_PRESSURE step 1 */\n  target_pressure: number;"), "{}", text);
    assert!(text.contains("mode: 'off' | 'on' | 'syphon';"), "{}", text);
    assert!(text.contains("power: Record<string, never>;"), "{}", text);
    assert_eq!(text, &golden_or_bless(&dir, "PumpDemo.d.ts.golden", text));
}
