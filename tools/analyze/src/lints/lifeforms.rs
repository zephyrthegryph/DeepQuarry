//! The lifecycle forms' checks (doc/rewrite/final_api.html section 6 "Lifecycle forms"; code/engine/lifeforms/).
//!
//! Two lints:
//!
//! * `lifeforms` (hard): what the forms promise and DM cannot check.
//!   * `make_unknown_param`: `make(/T, ..., name = v)` where neither `/T` nor an ancestor declares `param(nameof(name))` (and `name` is
//!     not one of make()'s own `at`, `by`, `parts`).
//!   * `make_missing_required`: a `make(/T, ...)` that leaves out a `param(..., required = TRUE)` of `/T` or an ancestor.
//!   * `make_parts_without_built_from`: `make(/T, parts = ...)` where `/T` declares no `built_from()`.
//!   * `after_init_bare_new`: `new /T` (or `var/T/x = new`) of a plain datum type that declares `after_init()` (or whose ancestor does).
//!     A plain datum's after_init() is armed only by make() (code/engine/actions/after_init.dm); a bare new never runs it.
//!   * `per_type_write`: a write to a `per_type(nameof(v), ...)` var (`v[...] =`, `v +=`, `v -=`, `v |=`, `v &=`, `v.Add(`, `v.Remove(`,
//!     `v.Cut(`, `v.Insert(`, `v.Swap(`, `v = `) in a proc of the declaring type or a subtype, other than its build proc.
//!   * `allow_matches_form`: an `ALLOW(init/...)`, `ALLOW(lifecycle)` or `ALLOW(sys_usr_outside_verb)` whose reason describes what a form
//!     now declares (a random roll, a constructor argument, a timed or used-up ending, a tooltip, an admin call): the site is converted, not kept.
//! * `escape_hatches` (a hard ban, ceilings 0): the sites the forms replace that remain, by kind. Every
//!   kind is at 0, so its next site fails: that is the hard ban. Kinds: `init_allow` (ALLOW(init/...) keeps), `lifecycle_allow` (ALLOW(lifecycle) keeps), `usr_allow`
//!   (ALLOW(sys_usr_outside_verb) keeps), `qdel_content` (every qdel( outside the engine) and `usr_content` (every `usr` outside the engine
//!   and verb bodies).

use std::collections::{BTreeMap, BTreeSet, HashMap};

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::sem::decls::{matching_paren, split_args, Decls};
use crate::tree::{SourceFile, CODE_DM};

use crate::lifeforms_policy::{META,Declared,calls};
#[cfg(test)]use crate::lifeform_source_policy::form_reasons;
impl Declared{fn build(decls:&Decls)->Self{let mut d=Self::default();for marker in decls.markers_named("CAPABILITIES"){let Some(ty)=marker.args.first()else{continue};d.marker(ty,&marker.args,&marker.rel,marker.line);}d}}

struct Lifeforms;

impl Lint for Lifeforms {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let decls = Decls::get(cx.tree);
        let d = Declared::build(&decls);
        self.constructor_positions(cx, &d, out);
        for f in cx.all_files(){if f.rel.starts_with("code/engine/")||cx.exempt(&f.rel){continue}crate::lifeforms_policy::scan_file(&d,f,&mut|rule,line,message|out.site_in_msg(rule,&f.rel,line,message));}
    }
}

impl Lifeforms {
    /// `param_pos_override` / `param_overrides_nothing` from the declarations, then `ctor_dead_arg` / `ctor_forward_only` on the typed tree
    /// (`sem::ctor_args`).
    fn constructor_positions(&self, cx: &Cx, d: &Declared, out: &mut Sink) {
        let skip=|relative:&str|relative.starts_with("code/engine/")||cx.exempt(relative);
        crate::lifeforms_policy::position_findings(d,&skip,&mut|rule,relative,line,message|out.site_in_msg(rule,relative,line,message));
        let files = cx.all_files();
        let key = crate::incr::ctx_key(&files.iter().map(|f| (f.rel.as_str(), f.fkey)).collect::<Vec<_>>());
        let positions: crate::sem::ctor_args::ParamPositions = d.positions.iter().map(|(t, m)| (t.clone(), m.keys().copied().collect())).collect();
        type Found = Vec<(String, u32, String)>;
        let found: Option<(Found, Found)> = crate::incr::cached("lifeforms-ctor-args", key, || {
            cx.sem().map(|sem| {
                let dead = crate::sem::ctor_args::dead_args(&sem, &positions)
                    .into_iter()
                    .map(|a| {
                        let list = a.dead.iter().map(|p| p.to_string()).collect::<Vec<_>>().join(",");
                        (a.rel, a.line, format!("new {}(loc, ...) passes {} argument(s) after the location; position(s) {} reach no param(pos =) and no New()/Initialize() [ctor-dead {} {} {}]", a.ty, a.passed, list, a.ty, a.passed, list))
                    })
                    .collect();
                let fwd = crate::sem::ctor_args::forward_only(&sem)
                    .into_iter()
                    .map(|o| {
                        let list = o.params.join(",");
                        (o.rel, o.line, format!("{}/{}(): {} only reach ..() [ctor-forward {}]", o.owner, o.name, list, list))
                    })
                    .collect();
                (dead, fwd)
            })
        });
        let Some((dead, fwd)) = found else { return };
        for (rel, line, msg) in dead {
            if !skip(&rel) {
                out.site_in_msg("ctor_dead_arg", &rel, line as usize, msg);
            }
        }
        for (rel, line, msg) in fwd {
            if !skip(&rel) {
                out.site_in_msg("ctor_forward_only", &rel, line as usize, msg);
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Lifeforms);
    crate::lifeform_source_policy::register_allows(reg);
    crate::lifeform_source_policy::register_hatches(reg);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn calls_finds_nested_and_skips_members() {
        let c = calls("x = make(/obj/item/paper, at = src, info = foo(bar)) + P.make(2)");
        let names: Vec<&str> = c.iter().map(|(n, _)| n.as_str()).collect();
        assert_eq!(names, vec!["make", "foo"]);
        assert_eq!(c[0].1, vec!["/obj/item/paper", "at = src", "info = foo(bar)"]);
    }

    #[test]
    fn after_init_bare_new_finds_literal_and_typed_news() {
        let mut d = Declared::default();
        d.after_init.insert("/datum/seed".to_string());
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed/S = new /datum/seed/apple"), Some(("/datum/seed/apple".to_string(), "/datum/seed".to_string())));
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed/S = new"), Some(("/datum/seed".to_string(), "/datum/seed".to_string())));
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed/S = new()"), Some(("/datum/seed".to_string(), "/datum/seed".to_string())));
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed/S = make(/datum/seed)"), None);
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed/S = new type"), None, "a type in a var is the run-time report's");
        assert_eq!(d.after_init_bare_new("\tvar/datum/seed_pile/P = new /datum/seed_pile(O, 1)"), None, "a sibling path is not a subtype");
    }

    #[test]
    fn lineage_is_nearest_first() {
        assert_eq!(Declared::lineage("/obj/item/a"), vec!["/obj/item/a", "/obj/item", "/obj"]);
    }

    #[test]
    fn form_reasons_catch_the_codemods_old_texts() {
        let r = form_reasons();
        let hit = |lint: &str, text: &str| r.iter().any(|(l, p, _)| *l == lint && p.is_match(text));
        assert!(hit("init", "icon_state rolled at random for each instance"));
        assert!(hit("init", "charge is a constructor argument from whoever builds it"));
        assert!(hit("lifecycle", "the flare is used up"));
        assert!(!hit("init", "map edits set the id tag"));
    }
}
