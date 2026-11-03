//! Port of `tools/ci/state_schema_lint.py`'s shared scanner: the structure parser other lints
//! import (`base_vars_lint`, `lifecycle_lint`, `scheduler_lints`, `derived_reads_lint`,
//! `ownership_lint`). `code_only` is [`crate::strip::code_only`] (`SourceFile::code()`).
//!
//! * [`Schema::get`]: one parse of every file, memoized per run: [`Schema::decls`] (the Python
//!   `parse()` decls), [`Schema::latent`] (`latent_safe =` per type), [`Schema::codecs`]
//!   (`parse_codec_keys`) and [`Schema::registry`] (`REGISTRY_TYPES`).
//! * [`chain`], [`ancestors`], [`Schema::effective_latent`], [`Schema::has_codec`],
//!   [`Schema::safe_types`].
//! * [`OwnershipKinds`]: `ownership_kind(owner, name)` (declared kind, or inferred from accessor
//!   writes), built on [`crate::dm::ownership_index::Index`].
//!
//! The Python walked `glob.glob` order; files are parsed here in path order. That only changes
//! which of two declarations of the same var on the same type is listed first.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use crate::dm::ownership_index::{self as oi, Index};
use crate::tree::{SourceFile, Tree, View};
use crate::util::under;
use crate::{pat, pat_match};

pub use crate::state_schema_data::{Var,Schema,ancestors,chain,parse_file,parse_codec_keys_file,MODIFIERS,UNSAVED,REF_ROOTS,DEF_TYPES,BASE_TYPES,REGISTRY_FILE};
use crate::state_schema_data::push_var;

/// `REGISTRY_TYPES`: every `REGISTRY_TYPE(/path, ...)` row of `registry_types.dm`, then `/decl`.
pub fn registry_types(tree: &Tree) -> Vec<String> {
    let mut found = Vec::new();
    if let Some(f) = tree.get(REGISTRY_FILE) {
        for line in f.raw().lines() {
            if let Some(m) = pat_match!(r"^REGISTRY_TYPE\(\s*(/[\w/]+)\s*,").captures(line) {
                found.push(m.s(1).to_string());
            }
        }
    }
    found.push("/decl".to_string());
    found
}

/// One file's contribution to the [`Schema`] (cached per file by content).
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct SchemaFacts {
    /// `(owner, name, mods, vtype, is_list, line)` in the file's declaration order per owner
    decls: Vec<(String, String, Vec<String>, String, bool, u32)>,
    latent: Vec<(String, bool)>,
    codecs: Vec<(String, Vec<String>)>,
}

/// One file's accessor usage and default-child declarations (`OwnershipKinds`).
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct KindFacts {
    /// `(var name, kind index into KIND_NAMES)`, sorted and distinct
    usage: Vec<(String, u8)>,
}

const KIND_NAMES: [&str; 4] = ["OWN", "REL", "PROTO", "SHARED"];

impl Schema {
    pub fn get(tree: &Tree, files: &[&SourceFile]) -> Arc<Schema> {
        let mut h = blake3::Hasher::new();
        h.update(b"state-schema");
        for f in files {
            h.update(&f.fkey.to_le_bytes());
        }
        let key = h.finalize().to_hex().to_string();
        tree.memo(&key, || Schema::build(tree, files))
    }

    pub fn build(tree: &Tree, files: &[&SourceFile]) -> Schema {
        let facts: Vec<SchemaFacts> =
            oi::sharded_facts("schema-facts-type-metadata-v2", files, |f| {
                let mut decls: HashMap<String, Vec<Var>> = HashMap::new();
                let mut latent: HashMap<String, bool> = HashMap::new();
                parse_file(&f.rel, f.code(), &mut decls, &mut latent);
                let mut codecs: HashMap<String, HashSet<String>> = HashMap::new();
                parse_codec_keys_file(f.raw().text.as_str(), &mut codecs);
                let mut out = SchemaFacts::default();
                let mut owners: Vec<&String> = decls.keys().collect();
                owners.sort();
                for o in owners {
                    for v in &decls[o] {
                        out.decls.push((
                            o.clone(),
                            v.name.clone(),
                            v.mods.iter().cloned().collect(),
                            v.vtype.clone(),
                            v.is_list,
                            v.line as u32,
                        ));
                    }
                }
                out.latent = latent.into_iter().collect();
                out.latent.sort();
                for (o, keys) in codecs {
                    let mut ks: Vec<String> = keys.into_iter().collect();
                    ks.sort();
                    out.codecs.push((o, ks));
                }
                out.codecs.sort();
                out
            });
        let mut s = Schema {
            registry: registry_types(tree),
            ..Schema::default()
        };
        for (f, x) in files.iter().zip(facts) {
            for (owner, name, mods, vtype, is_list, line) in x.decls {
                push_var(
                    &mut s.decls,
                    &owner,
                    (name, mods.into_iter().collect(), vtype, is_list),
                    &f.rel,
                    line as usize,
                );
            }
            for (t, v) in x.latent {
                s.latent.insert(t, v);
            }
            for (o, keys) in x.codecs {
                s.codecs.entry(o).or_default().extend(keys);
            }
        }
        s
    }

}

/// `ownership_kind(owner, name)`: the declared ownership kind of a var, or the kind inferred from
/// accessor writes (`own_*` / `rel_*` / `proto_*` / `shared_set`), or None.
#[derive(Debug)]
pub struct OwnershipKinds {
    pub idx: Arc<Index>,
    /// var name -> kinds it is written through (`OWN`, `REL`, `PROTO`, `SHARED`)
    pub usage: HashMap<String, BTreeSet<&'static str>>,
    /// `(type, var)` declared in a `CAPABILITIES(/type)` block: `owns_one` / `owns_many` are `OWN`, `ref_one` / `ref_many` are `REL`.
    pub declared: HashMap<(String, String), &'static str>,
}

impl OwnershipKinds {
    pub fn get(tree: &Tree, files: &[&SourceFile]) -> Arc<OwnershipKinds> {
        let mut h = blake3::Hasher::new();
        h.update(b"ownership-kinds");
        for f in files {
            h.update(&f.fkey.to_le_bytes());
        }
        let key = h.finalize().to_hex().to_string();
        tree.memo(&key, || OwnershipKinds::build(tree, files))
    }

    pub fn build(tree: &Tree, files: &[&SourceFile]) -> OwnershipKinds {
        let idx = Index::get(tree, files);
        let facts: Vec<KindFacts> = oi::sharded_facts("schema-kinds-facts", files, |f| {
            let raw = f.raw();
            let mut usage: BTreeSet<(String, u8)> = BTreeSet::new();
            for m in oi::ACCESSOR.captures_iter(&raw.text) {
                let func = m.s(1);
                let kind = if func.starts_with("own_") {
                    0
                } else if func.starts_with("rel_") {
                    1
                } else if func.starts_with("proto_") {
                    2
                } else {
                    3
                };
                usage.insert((m.s(3).to_string(), kind));
            }
            KindFacts {
                usage: usage.into_iter().collect(),
            }
        });
        let mut usage: HashMap<String, BTreeSet<&'static str>> = HashMap::new();
        for x in facts {
            for (name, kind) in x.usage {
                usage
                    .entry(name)
                    .or_default()
                    .insert(KIND_NAMES[kind as usize]);
            }
        }
        // The declared form: the entries of CAPABILITIES(T) blocks (sem::decls reads the blocks, backslash form and block form alike).
        // hud_element(nameof(x), T) is an owns_one on the hud; hud_element(..., owned = FALSE) a ref_one.
        // profile(nameof(x), /datum/record/T) is an owns_one (code/engine/declare/profiles.dm).
        let entry = crate::state_schema_data::ownership_entry_pattern().expect("ownership entry pattern");
        let mut declared: HashMap<(String, String), &'static str> = HashMap::new();
        for m in crate::sem::decls::Decls::get(tree).markers_named("CAPABILITIES") {
            let Some(ty) = m.args.first() else { continue };
            crate::state_schema_data::visit_ownership_entries(&entry,&m.body,|name,kind|{declared.entry((ty.clone(),name.to_owned())).or_insert(kind);});
        }
        OwnershipKinds {
            idx,
            usage,
            declared,
        }
    }

    pub fn kind(&self, owner: &str, name: &str) -> Option<String> {
        for p in oi::parents(owner) {
            if let Some(kind) = self.declared.get(&(p, name.to_string())) {
                return Some(kind.to_string());
            }
        }
        if let Some((_, d)) = self.idx.decl(owner, name) {
            return Some(d.macro_name.clone());
        }
        self.usage
            .get(name)
            .and_then(|k| k.iter().next())
            .map(|k| k.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chain_adds_implicit_roots() {
        assert_eq!(
            chain("/obj/item"),
            ["/datum", "/atom", "/atom/movable", "/obj", "/obj/item"]
        );
        assert_eq!(chain("/turf/x"), ["/datum", "/atom", "/turf", "/turf/x"]);
        assert_eq!(chain("/atom/movable"), ["/datum", "/atom", "/atom/movable"]);
        assert_eq!(chain("/datum/a"), ["/datum", "/datum/a"]);
        assert_eq!(chain("/client"), ["/client"]);
    }

    #[test]
    fn parse_reads_vars_blocks_and_latent() {
        let f = SourceFile::from_text(
            "code/a.dm",
            "/obj/thing\n\tlatent_safe = TRUE\n\tvar/datum/a = null\n\tvar/tmp\n\t\tobj/b\n\t\tlist/mob/c = list()\n\tvar/static/list/d\n/obj/thing/sub\n\tlatent_safe = FALSE\n",
        );
        let mut decls = HashMap::new();
        let mut latent = HashMap::new();
        parse_file(&f.rel, f.code(), &mut decls, &mut latent);
        let v = &decls["/obj/thing"];
        assert_eq!(v.len(), 4);
        assert!(v[0].saved() && v[0].holds_ref());
        assert!(!v[1].saved() && !v[2].saved() && v[2].is_list && v[2].vtype == "/mob");
        assert!(!v[3].saved());
        assert_eq!(latent["/obj/thing"], true);
        assert_eq!(latent["/obj/thing/sub"], false);
    }

    #[test]
    fn parse_inherited_latent_metadata_registration() {
        let f = SourceFile::from_text(
            "code/a.dm",
            concat!(
                "/datum/type_metadata_registry/register_defaults()\n",
                "\tregister(/obj/thing, TYPE_META_LATENT_SAFE, TRUE)\n",
                "\tregister(/obj/thing/sub, TYPE_META_LATENT_SAFE, FALSE)\n",
                "\tregister(/obj/other, TYPE_META_SLOT_HOOKS, TRUE)\n",
                "/proc/unrelated()\n",
                "\tregister(/obj/ignored, TYPE_META_LATENT_SAFE, TRUE)\n"
            ),
        );
        let mut decls = HashMap::new();
        let mut latent = HashMap::new();
        parse_file(&f.rel, f.code(), &mut decls, &mut latent);
        assert_eq!(latent.len(), 2);
        assert!(latent["/obj/thing"]);
        assert!(!latent["/obj/thing/sub"]);
        let schema = Schema {
            latent,
            ..Schema::default()
        };
        assert!(schema.effective_latent("/obj/thing/child"));
        assert!(!schema.effective_latent("/obj/thing/sub/child"));
    }
}
