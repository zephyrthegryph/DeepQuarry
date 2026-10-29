//! DeepQuarry's lint/analysis engine. See `tools/analyze/README.md`.
//!
//! One load of the source tree ([`tree`]), one comment/string stripping ([`strip`]), one ALLOW
//! implementation ([`allow`]), one baseline implementation ([`baseline`]), one on-disk cache
//! ([`cache`]); every lint is a [`lint::Lint`] in `src/lints/`.

pub mod allow;
pub mod baseline;
#[cfg(feature="legacy-sem")]
pub mod cache;
#[cfg(feature="legacy-sem")]
pub mod codemod;
#[cfg(feature="legacy-sem")]
pub mod codemods;
pub mod dm;
#[cfg(feature="legacy-sem")]
pub mod frontend;
pub mod incr;
#[cfg(feature="legacy-sem")]
pub mod gens;
pub mod lint;
pub mod lints;
#[cfg(feature="legacy-sem")]
pub mod base_vars_dead;
pub mod parity_types;
#[cfg(feature="legacy-sem")]
pub mod parity;
#[cfg(not(feature="legacy-sem"))]
pub use parity_types as parity;
pub mod pat;
#[cfg(feature="legacy-sem")]
pub mod run;
#[cfg(feature="legacy-sem")]
pub mod sem;
pub mod scopes;
#[cfg(feature="legacy-sem")]
pub mod shared;
pub mod strip;
pub mod tree;
#[cfg(feature="native-policy")]
pub mod captured_raw_policy;
#[cfg(feature="native-policy")]
pub mod captured_raw_file;
pub mod util;

pub mod native_policy_roster;
pub const LEGACY_SEMANTICS_ENABLED: bool = cfg!(feature="legacy-sem");

pub mod lifecycle_source;
#[cfg(feature="native-policy")]
pub mod captured_decl_policy;
