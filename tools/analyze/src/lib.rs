//! DeepQuarry's lint/analysis engine. See `tools/analyze/README.md`.
//!
//! One load of the source tree ([`tree`]), one comment/string stripping ([`strip`]), one ALLOW
//! implementation ([`allow`]), one baseline implementation ([`baseline`]), one on-disk cache
//! ([`cache`]); every lint is a [`lint::Lint`] in `src/lints/`.

pub mod allow;
pub mod baseline;
pub mod cache;
pub mod codemod;
pub mod codemods;
pub mod dm;
pub mod dreamchecker;
pub mod frontend;
pub mod incr;
pub mod gens;
pub mod lint;
pub mod lints;
pub mod base_vars_dead;
pub mod parity;
pub mod pat;
pub mod run;
pub mod sem;
pub mod scopes;
pub mod shared;
pub mod strip;
pub mod tree;
pub mod util;
pub mod warm;

/// What a warm worker reads before its request (`warm`): the cache configuration, the stored model with every body decoded, and the
/// walk store. All of it is what an ordinary run of `root` would read first; none of it depends on the tree's current content.
pub fn prewarm(root: &std::path::Path) {
    let Ok(scopes) = scopes::Scopes::load(&root.join("tools").join("ci").join("lint_scopes.toml")) else { return };
    let _cache = cache::Cache::open(root, &scopes.hash, true);
    std::thread::scope(|s| {
        s.spawn(sem::walk_cache::prewarm);
        sem::model_store::prewarm();
    });
}
