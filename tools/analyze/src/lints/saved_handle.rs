//! `saved_handle`: a handle written to a save (doc/rewrite/proposals/relations.md D10).
//!
//! Handles are per round and per connection (`ref_token()` is "id:generation"; a client handle names a connection). A save stores ids,
//! ckeys or names; on load a relation re-links by `by =`. The lint rejects an `ref_token()` (or `client_handle()`) result written to a
//! savefile entry (`S[...] <<`, `S[...] =`, `WRITE_FILE`, `to_file`). A hard ban: nothing is baselined.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

static META: Meta = Meta {
    name: "saved_handle",
    group: "",
    label: "saved_handle",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "saved",
        hint: "a handle is per round and per connection: save an id, a ckey or a name, and re-link on load (relations.md D10)",
    }],
    allow: &[],
    lists: &[],
};

struct SavedHandle {
    save: Pat,
}

impl SavedHandle {
    fn new() -> SavedHandle {
        SavedHandle { save: Pat::new(r"(?:\bS\s*\[[^\]]*\]\s*(?:<<|=(?!=))|\b(?:WRITE_FILE|to_file)\s*\()[^\n]*\b(?:ref_token|client_handle)\s*\(") }
    }
}

impl Lint for SavedHandle {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        for (i, line) in f.code().lines().enumerate() {
            if self.save.is_match(line) {
                out.site("saved", i + 1);
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SavedHandle::new());
}
