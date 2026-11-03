//! Port of `tools/ci/latent_lint.py` (roadmap C5, doc/rewrite/containment.md section 4.4).
//!
//! Holders with latent contents (`latent_contents = TRUE` in the type block) keep some of what they
//! hold as ledger entries, so a raw walk over their `contents` misses things. This flags raw walks in
//! procs of a latent holder type (or subtype) and raw walks through a variable typed as a holder.
//! `// ALLOW(latent): <reason>` keeps a site.
//!
//! Quirks kept from the Python: it reads files with `read().splitlines()` (so form feeds, `\x1c`..`\x1e`,
//! NEL and the Unicode line/paragraph separators also break lines, and there is no final empty line)
//! and `errors="ignore"` (the engine's text is lossy-replace, which only matters next to a bad byte);
//! an ALLOW line skips the whole line, header bookkeeping included; the `typed` variable names are
//! matched with a regex per name.

use std::collections::{BTreeMap, BTreeSet, HashSet};


use crate::dm::pylines::{allowed_in_recorded,recorded_into};
use crate::incr;
use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use crate::parity::Parity;

use crate::raw_tree_latent_policy as policy;
use policy::{META,BASELINE};
struct Latent;

impl Lint for Latent {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.files();
        let facts = incr::facts("latent-facts", &files, policy::facts_of);
        let mut holder_set: BTreeSet<String> = BTreeSet::new();
        let mut eager_set: BTreeSet<String> = BTreeSet::new();
        let mut legacy = 0usize;
        for fa in &facts {
            holder_set.extend(fa.holders.iter().cloned());
            eager_set.extend(fa.eager.iter().cloned());
            legacy += fa.legacy as usize;
        }
        let holders: HashSet<String> = holder_set.iter().cloned().collect();
        let eager: HashSet<String> = eager_set.iter().cloned().collect();
        let key = incr::ctx_key(&(&holder_set, &eager_set));
        let results = recorded_into(out, || incr::keyed("latent-judge", key, &files, |f| policy::judge(f,&holders,&eager,|lines,number|allowed_in_recorded(f,lines,number,"latent"))));

        let mut where_: BTreeMap<&str, Vec<u32>> = BTreeMap::new();
        for (f, sites) in files.iter().zip(results) {
            if !sites.is_empty() {
                where_.insert(f.rel.as_str(), sites);
            }
        }
        let total: usize = where_.values().map(|v| v.len()).sum();
        for (rel, nums) in &where_ {
            for n in nums {
                out.site_in("raw_walks", rel, *n as usize);
            }
        }
        out.note(format!(
            "latent lint: {} latent holder roots ({} opted out), {} sites in {} files, {} legacy contents loops tree-wide",
            holders.len(),
            eager.len(),
            total,
            where_.len(),
            legacy
        ));
    }

    fn parity(&self) -> Option<Parity> {
        let mut p = Parity::ratchet(&["tools/ci/latent_lint.py"], &[BASELINE]);
        p.update = Some(&["tools/ci/latent_lint.py", "--update"]);
        p.seed = Some(&["tools/ci/latent_lint.py", "--seed"]);
        Some(p)
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(Latent);
}
