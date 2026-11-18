//! `ref_text`: a stored `REF()` / `\ref[]` text names an entity by a string nothing clears or checks
//! (doc/rewrite/proposals/relations.md D9).
//!
//! A REF text may be built and resolved inside one request (a Topic href `?src=[REF(src)]`). It is never stored: a var, a list member or
//! key, a deferred argument holds a relation (possibly `weak = TRUE`) in content, or an `handle_of()` token in data.
//!
//! Rules:
//! * `stored`: a `REF(...)` result assigned to a var, added to a list, or used as a list key.
//! * `ref_macro`: a `\ref[...]` text in code (hrefs are most of them; the rest are unclassified), a ratchet that only falls.
//!
//! Engine tables that key their own staleness by REF text are exempt by path (`[lint.ref_text] exempt_prefixes`), as are tests.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

const H_STORED: &str = "do not store a REF() text: hold a relation (ref_one / ref_many, weak = TRUE when only a null check is needed) in content, or a handle_of() token in data; \
build and resolve a REF text inside one request only. doc/rewrite/proposals/relations.md D9";
const H_MACRO: &str = "a \\ref[] text is built and resolved inside one request (a Topic href); anything that outlives the request holds a relation or a handle_of() token. \
doc/rewrite/proposals/relations.md D9";

static META: Meta = Meta {
    name: crate::allow_registry_fields::ref_text::SCOPE_META_0.name,
    group: crate::allow_registry_fields::ref_text::SCOPE_META_0.group,
    label: "ref_text",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "stored", hint: H_STORED }, RuleMeta { name: "ref_macro", hint: H_MACRO }],
    allow: crate::allow_registry_fields::ref_text::ALLOW_0,
    lists: crate::allow_registry_fields::ref_text::SCOPE_META_0.lists,
};

const REF_TEXT_PATTERN_SOURCES:&[&str]=&[r"(?<![=!<>])(?:\+|\||-)?=(?!=)\s*REF\(",r"\[\s*REF\([^\]]*\)\s*\]\s*(?:\+|\||-)?=(?!=)",r"\b(?:LAZYADD|LAZYOR|LAZYSET|LAZYINITLIST)\s*\([^,()]+,\s*REF\(",r"\.(?:Add|Insert)\([^()]*\bREF\(",r"\blist\([^)]*\bREF\([^)]*\)\s*=[^=]",r"\\ref\["];
struct RefText {
    stored: Vec<Pat>,
    macro_: Pat,
}

impl RefText {
    fn new() -> RefText {
        RefText {
            stored: vec![
                // var = REF(x), var += REF(x), var |= REF(x), var/x = REF(x)
                Pat::new(REF_TEXT_PATTERN_SOURCES[0]),
                // L[REF(x)] = ...
                Pat::new(REF_TEXT_PATTERN_SOURCES[1]),
                // LAZYADD(L, REF(x)) and the other list macros, L.Add(REF(x)), list(REF(x) = v)
                Pat::new(REF_TEXT_PATTERN_SOURCES[2]),
                Pat::new(REF_TEXT_PATTERN_SOURCES[3]),
                Pat::new(REF_TEXT_PATTERN_SOURCES[4]),
            ],
            macro_: Pat::new(REF_TEXT_PATTERN_SOURCES[5]),
        }
    }
}

impl Lint for RefText {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self,_cx:&Cx,f:&SourceFile,out:&mut Sink){scan_using(f,out,&self.stored,&self.macro_)}
}

pub fn register(reg: &mut Registry) {
    reg.add(RefText::new());
}

fn scan_using<P:crate::raw_fixture_policy::PatternApi>(f:&SourceFile,out:&mut Sink,stored:&[P],macro_:&P){
        let code = f.code();
        let raw = f.raw();
        for (i, line) in code.lines().enumerate() {
            let n = i + 1;
            let t = line.trim_start();
            if t.starts_with('#') || t.is_empty() {
                continue;
            }
            if stored.iter().any(|p| p.is_match(line)) {
                out.site("stored", n);
                continue;
            }
            // \ref[ sits inside a string, which the code view blanks: look at the raw line, skipping comment lines.
            let r = raw.line(n);
            let rt = r.trim_start();
            if !rt.starts_with("//") && !rt.starts_with('*') && macro_.is_match(r) {
                out.site("ref_macro", n);
            }
        }

}

#[cfg(feature="native-policy")]
struct NativeRefText{legacy:std::sync::OnceLock<RefText>}
#[cfg(feature="native-policy")]
impl Lint for NativeRefText{
 fn meta(&self)->&Meta{&META}
 fn scan_file(&self,cx:&Cx,f:&SourceFile,out:&mut Sink){
  if let Some(fixture)=cx.fixture{
   let p0=fixture.pattern(REF_TEXT_PATTERN_SOURCES[0],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(REF_TEXT_PATTERN_SOURCES[0]));
   let p1=fixture.pattern(REF_TEXT_PATTERN_SOURCES[1],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(REF_TEXT_PATTERN_SOURCES[1]));
   let p2=fixture.pattern(REF_TEXT_PATTERN_SOURCES[2],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(REF_TEXT_PATTERN_SOURCES[2]));
   let p3=fixture.pattern(REF_TEXT_PATTERN_SOURCES[3],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(REF_TEXT_PATTERN_SOURCES[3]));
   let p4=fixture.pattern(REF_TEXT_PATTERN_SOURCES[4],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(REF_TEXT_PATTERN_SOURCES[4]));
   let p5=fixture.pattern(REF_TEXT_PATTERN_SOURCES[5],crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(REF_TEXT_PATTERN_SOURCES[5]));
   scan_using(f,out,&[p0,p1,p2,p3,p4],&p5)
  }else{self.legacy.get_or_init(RefText::new).scan_file(cx,f,out)}
 }
}
#[cfg(feature="native-policy")]
pub fn register_native(reg:&mut Registry){reg.add(NativeRefText{legacy:std::sync::OnceLock::new()})}
