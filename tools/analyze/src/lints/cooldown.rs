//! Port of `tools/ci/cooldown_lint.py`: raw `world.time` cooldown compares
//! (doc/rewrite/object_model_core.md sec 16, "Rate-limit something").
//!
//! Counts the hand-rolled form: a line that compares `world.time` with something. Not counted, when
//! the line reads one of these: a var named for a point in time (`*_at`, `*_until`, ...), a list slot read by a literal key or index, a reagent's
//! `data` slot under `code/modules/reagents`, a compare against a bare constant. Skipped: `#` lines
//! and the `exempt_prefixes` in `lint_scopes.toml`.
//!
//! Quirks kept: the compare is tried on the `code_only` view, whose line numbers can drift from the raw
//! file after an unbalanced quote, and the fingerprint text is the raw line at that number; the Python read files with
//! `errors="ignore"` (invalid bytes dropped) where the engine's text has U+FFFD.

use std::collections::BTreeSet;


use crate::dm::pylines::recorded_into;
use crate::incr;
use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use crate::parity::{ParseKind, Parity};

use crate::raw_tree_cooldown_policy as policy;
struct Cooldown{p:policy::Patterns}

impl Lint for Cooldown {
    fn meta(&self) -> &Meta {
        &policy::META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files=cx.files();let found=recorded_into(out,||incr::keyed("cooldown-judge",incr::ctx_key(&BTreeSet::<String>::new()),&files,|f|policy::judge(f,&self.p,|number|crate::dm::sys::kept_recorded(f,number,"cooldown"))));for(f,lines)in files.iter().zip(found){for line in lines{out.site_in("raw_compare",&f.rel,line as usize)}}
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/cooldown_lint.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::Tagged,
            update: Some(&["tools/ci/cooldown_lint.py", "--update"]),
            seed: Some(&["tools/ci/cooldown_lint.py", "--seed"]),
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Cooldown { p: policy::Patterns::new() });
}

#[cfg(feature="native-policy")]
struct NativeCooldown{legacy:std::sync::OnceLock<Cooldown>}
#[cfg(feature="native-policy")]
impl Lint for NativeCooldown{
 fn meta(&self)->&Meta{&policy::META}
 fn scan_tree(&self,cx:&Cx,out:&mut Sink){
  let Some(fixture)=cx.fixture else{return self.legacy.get_or_init(||Cooldown{p:policy::Patterns::new()}).scan_tree(cx,out)};
  let patterns=match policy::native_patterns(fixture){Ok(actual)=>actual,Err(error)=>{fixture.note_scan(Err(error));return}};
  let files=cx.files();
  let result=recorded_into(out,||->Result<Vec<Vec<u32>>,String>{
   let mut found=Vec::new();
   for file in &files{let rows=fixture.cooldown_lines(file,&patterns,|number|crate::dm::sys::kept_recorded(file,number,"cooldown"))?;fixture.push(&mut found,rows)?;}
   Ok(found)
  });
  match result{Ok(found)=>for(file,rows)in files.iter().zip(found){for line in rows{out.site_in("raw_compare",&file.rel,line as usize)}},Err(error)=>fixture.note_scan(Err(error))}
 }
 fn parity(&self)->Option<Parity>{self.legacy.get_or_init(||Cooldown{p:policy::Patterns::new()}).parity()}
}
#[cfg(feature="native-policy")]
pub fn register_native(reg:&mut Registry){reg.add(NativeCooldown{legacy:std::sync::OnceLock::new()})}
