//! Port of `tools/ci/cache_lint.py`: shared caches go through `DECLARE_SHARED_CACHE`
//! (doc/rewrite/caching.md).
//!
//! A hand-rolled keyed cache (a `var/static/list/...cache...`, a global `GLOBAL_LIST_*(...cache...)` or
//! a top-level `var/list/...cache...`) has its own key format, no invalidation, no stats and no mutation
//! guard. Typecaches (names containing `typecache`) are not caches in this sense. A justified keep
//! carries `// ALLOW(cache): <reason>`. Ceiling 0: any site fails.
//!
//! Quirks kept: the Python used `Path.rglob` (dot-files and dot-directories included: `hidden: true`)
//! and `read_text(errors="ignore").splitlines()`, so a form feed, `\x0b`, `\x1c`-`\x1e`, NEL and the
//! Unicode line/paragraph separators also break lines, line numbers (and the ALLOW lookup) follow that,
//! and an invalid UTF-8 byte is dropped, not replaced; the patterns run on the text before the first
//! `//` (strings are not stripped, block comments are not handled); a line has at most one site, from
//! the first pattern that matches, and a match of a typecache or an ALLOW ends the line (so a second
//! cache on the same line is never seen).

use std::borrow::Cow;

use crate::lint::{AllowUse, Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::pat::Pat;
use crate::tree::{Select, SourceFile};
use crate::util::{before_slashes, py_lstrip, py_strip};

use crate::cache_policy::{META,py_splitlines};
struct Cache;

fn text_ignoring_bad_bytes(f: &SourceFile) -> Cow<'_, str> {
    let text = f.text();
    if !text.contains('\u{FFFD}') {
        return Cow::Borrowed(text);
    }
    match std::fs::read(&f.abs) {
        Ok(bytes) => {
            let mut s = String::with_capacity(bytes.len());
            for chunk in bytes.utf8_chunks() {
                s.push_str(chunk.valid());
            }
            Cow::Owned(crate::util::universal_newlines(s))
        }
        Err(_) => Cow::Borrowed(text),
    }
}

impl Lint for Cache {
    fn meta(&self) -> &Meta {
        &META
    }

fn scan_file(&self,_cx:&Cx,f:&SourceFile,out:&mut Sink){let text=text_ignoring_bad_bytes(f);let output=std::cell::RefCell::new(out);crate::cache_policy::judge_using(&text,&mut crate::key_policy_control::Compatibility,&mut|at,code,_|{let mut out=output.borrow_mut();let value=AllowUse{rel:f.rel.clone(),line:at as u32,name:"cache".into(),code:code.unwrap_or_default()};if !out.allow_used.contains(&value){out.allow_used.push(value);}Ok(())},&mut|number,message,_|{output.borrow_mut().site_msg("hand_rolled",number,message);Ok(())}).unwrap_or_else(|never|match never{})}

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/cache_lint.py"],
            old_raw: &[],
            blank: &[],
            // `  file:line text`, and some paths hold spaces.
            parse: ParseKind::FileLineAny,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg:&mut Registry){reg.add(Cache);}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splitlines_matches_python() {
        assert_eq!(py_splitlines("a\nb\n"), vec!["a", "b"]);
        assert_eq!(py_splitlines("a\x0bb\u{2028}c\u{85}d\x0ce"), vec!["a", "b", "c", "d", "e"]);
        assert_eq!(py_splitlines("\n\nx"), vec!["", "", "x"]);
        assert!(py_splitlines("").is_empty());
    }

    fn scan(text: &str) -> Sink<'static> {
        let tree = crate::tree::Tree::from_files(vec![]);
        let scope = crate::scopes::LintScope::default();
        let cx = Cx { fixture:None, tree: &tree, meta: &META, scope: &scope };
        let f = SourceFile::from_text("code/modules/x.dm", text);
        let mut out = Sink::new();
        out.cur = f.rel.clone();
        let mut reg = Registry::default();
        register(&mut reg);
        reg.lints[0].scan_file(&cx, &f, &mut out);
        out
    }

    #[test]
    fn allow_follows_the_splitlines_numbering() {
        // The form feed splits the first physical line in two: the ALLOW is its own line, the site the next.
        let out = scan("// ALLOW(cache): the typecache of this module is rebuilt on reload\x0cvar/list/a_cache\nvar/list/b_cache\n");
        assert_eq!(out.sites.len(), 1, "{:?}", out.sites);
        assert_eq!(out.sites[0].line, 3);
        assert_eq!(out.allow_used.len(), 1);
        assert_eq!(out.allow_used[0].line, 1);
    }

    #[test]
    fn a_typecache_match_hides_the_rest_of_the_line() {
        let out = scan("var/static/list/typecache_a = list() ; var/static/list/b_cache\nvar/static/list/b_cache; var/static/list/typecache_a\n");
        assert_eq!(out.sites.len(), 1);
        assert_eq!(out.sites[0].line, 2);
    }
}
