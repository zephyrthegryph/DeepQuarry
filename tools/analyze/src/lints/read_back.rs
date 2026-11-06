//! Shared read-back adapter.
#[cfg(feature = "legacy-sem")]
use std::collections::BTreeSet;

use crate::lint::{Cx, Lint, Meta, Registry, Sink};
use crate::raw_tree_read_back_policy as policy;

struct ReadBack {
    #[cfg(feature = "legacy-sem")]
    p: policy::ReadBack,
}

impl Lint for ReadBack {
    fn meta(&self) -> &Meta {
        &policy::META
    }

    #[cfg(feature = "legacy-sem")]
    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let mut read_back = BTreeSet::new();
        for f in cx.all_files() {
            policy::schema(f, &self.p, |ty| {
                read_back.insert(ty.to_string());
            });
        }
        let decls = crate::sem::decls::Decls::get(cx.tree);
        read_back.extend(decls.markers_named("ACTION").filter_map(|m| policy::action_notice(&m.args)));
        for f in cx.files() {
            policy::judge_file(f, &self.p, &read_back, out);
        }
    }

    #[cfg(not(feature = "legacy-sem"))]
    fn scan_tree(&self, _cx: &Cx, _out: &mut Sink) {
        panic!("read_back requires the captured source policy in a native-only build");
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(ReadBack {
        #[cfg(feature = "legacy-sem")]
        p: policy::ReadBack::new(),
    });
}
