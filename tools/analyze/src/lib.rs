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
pub mod frontend;
pub mod incr;
pub mod gens;
pub mod lint;
pub mod lints;
pub mod look_keys;
pub mod parity;
pub mod pat;
pub mod run;
pub mod sem;
pub mod scopes;
pub mod strip;
pub mod tree;
pub mod util;
