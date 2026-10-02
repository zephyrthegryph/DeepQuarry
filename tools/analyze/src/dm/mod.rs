//! Shared DM-source helpers: the structure scanners several lints used to import from each other
//! (`_dx_dm.py`, `state_schema_lint.py`, `ownership_lint.py`, `field_write_lint.py`).
//!
//! Every `*.rs` (or `x/mod.rs`) in this folder is declared by build.rs, like the lints: add a file
//! here for a helper two or more lints share; there is no list to edit.

include!(concat!(env!("OUT_DIR"), "/dm_gen.rs"));
