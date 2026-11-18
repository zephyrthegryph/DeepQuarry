//! `saved_handle`: a handle written to a save (doc/rewrite/proposals/relations.md D10).
//!
//! Handles are per round and per connection (`handle_of()` is slot + generation; a client handle names a connection). A save stores ids,
//! ckeys or names; on load a relation re-links by `by =`. The lint rejects an `handle_of()` (or `client_handle()`) result written to a
//! savefile entry (`S[...] <<`, `S[...] =`, `WRITE_FILE`, `to_file`). A hard ban: nothing is baselined.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

static META: Meta = Meta {
    name: crate::allow_registry_fields::saved_handle::SCOPE_META_0.name,
    group: crate::allow_registry_fields::saved_handle::SCOPE_META_0.group,
    label: "saved_handle",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "saved",
        hint: "a handle is per round and per connection: save an id, a ckey or a name, and re-link on load (relations.md D10)",
    }],
    allow: crate::allow_registry_fields::saved_handle::ALLOW_0,
    lists: crate::allow_registry_fields::saved_handle::SCOPE_META_0.lists,
};

const SAVED_HANDLE_PATTERN_SOURCES:&[&str]=&[r"(?:\bS\s*\[[^\]]*\]\s*(?:<<|=(?!=))|\b(?:WRITE_FILE|to_file)\s*\()[^\n]*\b(?:handle_of|client_handle)\s*\("];
struct SavedHandle {
    save: Pat,
}

impl SavedHandle {
    fn new() -> SavedHandle {
        SavedHandle { save: Pat::new(SAVED_HANDLE_PATTERN_SOURCES[0]) }
    }
}

impl Lint for SavedHandle {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self,_cx:&Cx,f:&SourceFile,out:&mut Sink){scan_using(f,out,&self.save)}
}

pub fn register(reg: &mut Registry) {
    reg.add(SavedHandle::new());
}

fn scan_using<P:crate::raw_fixture_policy::PatternApi>(f:&SourceFile,out:&mut Sink,save:&P){
        for (i, line) in f.code().lines().enumerate() {
            if save.is_match(line) {
                out.site("saved", i + 1);
            }
        }

}

#[cfg(feature="native-policy")]
struct NativeSavedHandle{legacy:std::sync::OnceLock<SavedHandle>}
#[cfg(feature="native-policy")]
impl Lint for NativeSavedHandle{
 fn meta(&self)->&Meta{&META}
 fn scan_file(&self,cx:&Cx,f:&SourceFile,out:&mut Sink){
  if let Some(fixture)=cx.fixture{
   let p0=fixture.pattern(SAVED_HANDLE_PATTERN_SOURCES[0],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(SAVED_HANDLE_PATTERN_SOURCES[0]));
   scan_using(f,out,&p0)
  }else{self.legacy.get_or_init(SavedHandle::new).scan_file(cx,f,out)}
 }
}
#[cfg(feature="native-policy")]
pub fn register_native(reg:&mut Registry){reg.add(NativeSavedHandle{legacy:std::sync::OnceLock::new()})}
