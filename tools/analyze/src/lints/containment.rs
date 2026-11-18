//! Port of `tools/ci/containment_lint.py`: raw writes to `loc` / `contents` (roadmap C1,
//! doc/rewrite/containment.md section 2).
//!
//! Every change of where a movable is goes through the ledger (`forceMove()` and the slot API). A raw
//! write skips it: `X.loc = Y` (and a bare `loc = Y` in a proc), `X.contents += Y` / `-= Y`,
//! `X.contents.Add(Y)` / `.Remove(Y)`. An outright ban (C11): any unannotated site fails, and a
//! site that must stay raw carries `// ALLOW(containment): <reason>`.
//!
//! The Python has no path exemption (it does not call `exempt_path()`): unit tests are scanned.
//!
//! Quirks kept: a `var/.../loc =` declaration is cut out of the line before either pattern runs
//! (which can join the text on either side of it); a `loc =` straight after `(` or `,` is a named
//! argument and skipped; every `contents` match on a line counts, but the ALLOW question is asked
//! once per line, and only for a line that has a site.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};
use crate::util::{py_rstrip, py_strip};

static META: Meta = Meta {
    name: crate::allow_registry_fields::containment::SCOPE_META_0.name,
    group: crate::allow_registry_fields::containment::SCOPE_META_0.group,
    label: "containment",
    legacy: "tools/ci/containment_lint.py",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "raw_writes",
        hint: "use forceMove(), moveToNullspace(), the slot API (code/library/containers/containment/api.dm) or image_anchor(); a justified keep takes `// ALLOW(containment): <reason>`",
    }],
    allow: crate::allow_registry_fields::containment::ALLOW_0,
    lists: crate::allow_registry_fields::containment::SCOPE_META_0.lists,
};

const CONTAINMENT_PATTERN_SOURCES:&[&str]=&[r"(?<![\w])loc\s*=(?!=)",r"(?<![\w])contents\s*(?:\+=|-=|\|=|&=)|(?<![\w])contents\s*\.\s*(?:Add|Remove|Cut|Insert|Swap)\s*\(",r"var/(?:[\w/]+/)?loc\s*="];
struct Containment {
    /// `loc =` not part of ==, !=, <=, >=, and not a longer name (oldloc, T.locs).
    loc_write: Pat,
    contents_write: Pat,
    /// Declarations and named arguments are not writes: `var/turf/loc = ...`.
    declaration: Pat,
}

impl Lint for Containment {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self,_cx:&Cx,f:&SourceFile,out:&mut Sink){scan_using(f,out,&self.loc_write,&self.contents_write,|line|self.declaration.is_match(line).then(||self.declaration.replace_all(line,"")))}

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/containment_lint.py"],
            old_raw: &[&["tools/ci/containment_lint.py", "--report"]],
            blank: &[],
            // `file:line: what`, and some paths hold spaces.
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Containment {
        loc_write: Pat::new(CONTAINMENT_PATTERN_SOURCES[0]),
        contents_write: Pat::new(CONTAINMENT_PATTERN_SOURCES[1]),
        declaration: Pat::new(CONTAINMENT_PATTERN_SOURCES[2]),
    });
}

fn scan_using<P:crate::raw_fixture_policy::PatternApi>(f:&SourceFile,out:&mut Sink,loc_write:&P,contents_write:&P,strip_declaration:impl Fn(&str)->Option<String>){
        for (number, line) in f.code().numbered() {
            // A declaration holds "loc", so this only skips lines nothing can match on.
            if !line.contains("loc") && !line.contains("contents") {
                continue;
            }
            let stripped=strip_declaration(line);
            let line=stripped.as_deref().unwrap_or(line);
            let mut found = 0;
            for m in loc_write.find_iter(line) {
                let before = py_rstrip(&line[..m.start]);
                // A named argument inside a call: `(loc = x` or `, loc = x`.
                if before.ends_with('(') || before.ends_with(',') {
                    continue;
                }
                found += 1;
            }
            let contents: Vec<String> = contents_write.find_iter(line).iter().map(|m| py_strip(m.as_str()).to_string()).collect();
            // Asked only about a line that would otherwise count.
            if (found > 0 || !contents.is_empty()) && !out.allowed(f, number, "containment") {
                for _ in 0..found {
                    out.site_msg("raw_writes", number, "loc =");
                }
                for what in contents {
                    out.site_msg("raw_writes", number, what);
                }
            }
        }

}

#[cfg(feature="native-policy")]
struct NativeContainment{legacy:std::sync::OnceLock<Containment>}
#[cfg(feature="native-policy")]
impl Lint for NativeContainment{
 fn meta(&self)->&Meta{&META}
 fn scan_file(&self,cx:&Cx,f:&SourceFile,out:&mut Sink){
  if let Some(fixture)=cx.fixture{
   use crate::raw_fixture_policy::PatternApi as _;
   let p0=fixture.pattern(CONTAINMENT_PATTERN_SOURCES[0],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(CONTAINMENT_PATTERN_SOURCES[0]));
   let p1=fixture.pattern(CONTAINMENT_PATTERN_SOURCES[1],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(CONTAINMENT_PATTERN_SOURCES[1]));
   let p2=fixture.pattern(CONTAINMENT_PATTERN_SOURCES[2],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(CONTAINMENT_PATTERN_SOURCES[2]));
   scan_using(f,out,&p0,&p1,|line|{
    if !p2.is_match(line){return None}
    match fixture.replace_static(CONTAINMENT_PATTERN_SOURCES[2],line,"",||crate::pat!(CONTAINMENT_PATTERN_SOURCES[2])){Ok(actual)=>Some(actual),Err(message)=>{fixture.note_scan(Err(message));None}}
   })
  }else{self.legacy.get_or_init(||Containment{loc_write:Pat::new(CONTAINMENT_PATTERN_SOURCES[0]),contents_write:Pat::new(CONTAINMENT_PATTERN_SOURCES[1]),declaration:Pat::new(CONTAINMENT_PATTERN_SOURCES[2])}).scan_file(cx,f,out)}
 }
 fn parity(&self)->Option<Parity>{self.legacy.get_or_init(||Containment{loc_write:Pat::new(CONTAINMENT_PATTERN_SOURCES[0]),contents_write:Pat::new(CONTAINMENT_PATTERN_SOURCES[1]),declaration:Pat::new(CONTAINMENT_PATTERN_SOURCES[2])}).parity()}
}
#[cfg(feature="native-policy")]
pub fn register_native(reg:&mut Registry){reg.add(NativeContainment{legacy:std::sync::OnceLock::new()})}
