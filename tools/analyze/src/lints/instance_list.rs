//! InstanceList delegates lexical facts/final ordering to one shared policy.
use std::collections::{BTreeSet,HashMap,HashSet};
use crate::{dm::{ownership_index as oi,singletons::is_singleton,walk::walk_order},incr,lint::{Cx,Lint,Meta,Registry,Sink},parity::Parity,tree::SourceFile};
use crate::instance_list_policy::{BASELINE,LINT,META,Facts,Judged,facts_of};
#[cfg(test)]use crate::instance_list_policy::{scan_decls,strip_comment};
struct InstanceList;

impl Lint for InstanceList {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let all = cx.all_files();
        let facts: Vec<Facts> = oi::sharded_facts("instance-list-facts", &all, facts_of);
        // `singleton_types`: the exact types a `GLOBAL_DATUM_INIT(...)` creates anywhere under `code/`
        // (never `/datum`); only the two root prefixes ever exempt one in practice (see its docs).
        let mut globals: BTreeSet<String> = BTreeSet::new();
        for x in &facts {
            globals.extend(x.globals.iter().cloned());
        }
        globals.remove("/datum");
        let globals: HashSet<String> = globals.into_iter().collect();
        let mut sorted: Vec<&String> = globals.iter().collect();
        sorted.sort();
        let key = incr::ctx_key(&sorted);
        let by_rel: HashMap<&str, &Facts> = all.iter().zip(facts.iter()).map(|(f, x)| (f.rel.as_str(), x)).collect();
        // `found.setdefault(f"{type_path}/{var_name}", f"{rel}:{number}")`, files in os.walk order.
        let files = walk_order(&cx.files());
        let judged: Vec<Judged> = oi::sharded_keyed("instance-list-judge", key, &files, |f| {
            let mut sink = Sink::new();
            let mut j = Judged::default();
            if let Some(x) = by_rel.get(f.rel.as_str()) {
                for (type_path, var_name, number) in &x.decls {
                    if is_singleton(type_path, &globals) || sink.allowed(f, *number as usize, LINT) {
                        continue;
                    }
                    j.decls.push((type_path.clone(), var_name.clone(), *number));
                }
            }
            j.uses = sink.allow_used;
            j
        });
        let output=std::cell::RefCell::new(out);crate::instance_list_policy::finish_using(files.iter().zip(judged.iter()).map(|(file,judged)|(file.rel.as_str(),judged)),&mut crate::key_policy_control::Compatibility,&mut|value,_|{let mut out=output.borrow_mut();if !out.allow_used.contains(value){out.allow_used.push(value.clone());}Ok(())},&mut|_,relative,line,_|{output.borrow_mut().site_in(LINT,relative,line as usize);Ok(())}).unwrap_or_else(|never|match never{});
    }

    fn parity(&self) -> Option<Parity> {
        let mut p = Parity::ratchet(&["tools/ci/instance_list_lint.py"], &[BASELINE]);
        p.update = Some(&["tools/ci/instance_list_lint.py", "--update"]);
        p.seed = Some(&["tools/ci/instance_list_lint.py", "--seed"]);
        Some(p)
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(InstanceList);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decls(text: &str) -> Vec<(String, String, usize)> {
        scan_decls(&SourceFile::from_text("code/a.dm", text))
    }

    #[test]
    fn strip_comment_respects_strings() {
        assert_eq!(strip_comment("a = 1 // c"), "a = 1");
        assert_eq!(strip_comment("a = \"x//y\" // c"), "a = \"x//y\"");
        assert_eq!(strip_comment("a = \"x\\\"//y\""), "a = \"x\\\"//y\"");
        assert_eq!(strip_comment("a = 'x' // c  "), "a = 'x'");
        assert_eq!(strip_comment("no comment   "), "no comment");
    }

    #[test]
    fn reads_blocks_procs_and_depth_zero_paths() {
        let got = decls(
            "/obj/a\n\tvar/list/x = list()\n\tvar/static/list/y = list()\n\tvar\n\t\tlist/z = list()\n\t\tstatic/list/w = list()\n\tproc/p()\n\t\tvar/list/inproc = list()\n\tvar/list/after = new\n/obj/b/var/list/c = list()\n/obj/b/var/list/c2 = new\n/obj/b/var/list/c3[4]\n/obj/b/var/static/list/d = new\n/obj/b/var/staticky/list/e = new\n",
        );
        let names: Vec<String> = got.iter().map(|(t, n, l)| format!("{}/{}:{}", t, n, l)).collect();
        // A depth-0 declaration with parentheses is read as a top-level proc (quirk), and the
        // modifier test there is a substring test.
        assert_eq!(names, ["/obj/a/x:2", "/obj/a/z:5", "/obj/a/after:9", "/obj/b/c2:11", "/obj/b/c3:12"]);
    }

    #[test]
    fn spaces_do_not_indent_and_comments_hide() {
        assert!(decls("/obj/a\n var/list/x = list()\n").is_empty());
        assert!(decls("/obj/a\n\t/*\n\tvar/list/x = list()\n\t*/\n\t// var/list/y = list()\n").is_empty());
        assert_eq!(decls("/obj/a {\n\tvar/list/x = list()\n").len(), 1);
    }
}
