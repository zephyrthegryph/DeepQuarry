use super::*;
use crate::{
    lint::{Meta, RuleMeta, ScanKind, Sink},
    scopes::LintScope,
    tree::{Select, SourceFile, Tree},
};
use std::sync::atomic::{AtomicUsize, Ordering};
#[path = "../../dmb/shared/test_scratch.rs"]
mod test_scratch;
struct Probe {
    meta: Meta,
    custom: AtomicUsize,
    post: AtomicUsize,
}
impl Probe {
    fn new(policy: Policy) -> Self {
        Self {
            meta: Meta {
                name: "probe",
                group: "",
                label: "probe",
                legacy: "",
                select: Select::dm(&[("code/", "dm")]),
                scan: ScanKind::File,
                policy,
                rules: &[
                    RuleMeta {
                        name: "first",
                        hint: "use the native form",
                    },
                    RuleMeta {
                        name: "second",
                        hint: "",
                    },
                ],
                allow: &[],
                lists: &[],
            },
            custom: AtomicUsize::new(0),
            post: AtomicUsize::new(0),
        }
    }
}
impl Lint for Probe {
    fn meta(&self) -> &Meta {
        &self.meta
    }
    fn finish_raw(&self, _: &Cx, run: &Run, text: &mut String, raw: bool) -> bool {
        self.custom.fetch_add(1, Ordering::Relaxed);
        write!(text, "custom {} {}\n", run.sites.len(), raw).unwrap();
        !run.sites.is_empty()
    }
    fn post_judge(&self, _: &Cx, _: &Run, text: &mut String) -> bool {
        self.post.fetch_add(1, Ordering::Relaxed);
        text.push_str("post\n");
        false
    }
}
fn tree_run() -> (Tree, Run) {
    let tree = Tree::from_files(vec![
        SourceFile::from_text("code/a.dm", "native_a()\n"),
        SourceFile::from_text("code/b.dm", "native_b()\n"),
    ]);
    let mut sink = Sink::new();
    sink.site_in("first", "code/b.dm", 1);
    sink.site_in_msg("first", "code/a.dm", 1, "authored reason");
    (
        tree,
        Run {
            sites: sink.sites,
            notes: vec!["summary before judgement".into()],
        },
    )
}
#[test]
fn shared_judge_keeps_notes_changed_filter_rule_and_source_order() {
    let (tree, run) = tree_run();
    let probe = Probe::new(Policy::Hard);
    let scope = LintScope::default();
    let cx = Cx {
        tree: &tree,
        meta: probe.meta(),
        scope: &scope,
    };
    let (failed, text) = judge(&probe, &cx, &run, Path::new(""), &None, false);
    assert!(failed);
    assert_eq!(text,"summary before judgement\nprobe: first 2 FAIL\ncode/b.dm:1: [probe/first] native_b() -- use the native form\ncode/a.dm:1: [probe/first] authored reason -- use the native form\nprobe: second 0 OK\npost\n");
    let changed = Some(HashSet::from(["code/a.dm".into()]));
    let (_, filtered) = judge(&probe, &cx, &run, Path::new(""), &changed, false);
    assert!(filtered.starts_with("summary before judgement\nprobe: first 1 FAIL\n"));
    assert!(!filtered.contains("code/b.dm:"));
    assert_eq!(probe.post.load(Ordering::Relaxed), 2);
}
#[test]
fn shared_judge_ceiling_raw_and_custom_keep_distinct_protocols() {
    let (tree, run) = tree_run();
    let probe = Probe::new(Policy::Hard);
    let mut scope = LintScope::default();
    scope.ceilings.insert("first".into(), 2);
    let cx = Cx {
        tree: &tree,
        meta: probe.meta(),
        scope: &scope,
    };
    let (failed, text) = judge(&probe, &cx, &run, Path::new(""), &None, false);
    assert!(!failed);
    assert!(text.contains("(ceiling 2)  ok"));
    assert!(!text.contains("code/b.dm:"));
    assert!(judge(&probe, &cx, &run, Path::new(""), &None, true).0);
    let custom = Probe::new(Policy::Custom);
    let cx = Cx {
        tree: &tree,
        meta: custom.meta(),
        scope: &scope,
    };
    let (failed, text) = judge(
        &custom,
        &cx,
        &run,
        Path::new(""),
        &Some(HashSet::new()),
        true,
    );
    assert!(!failed);
    assert_eq!(text, "summary before judgement\ncustom 0 true\n");
    assert_eq!(custom.custom.load(Ordering::Relaxed), 1);
    assert_eq!(custom.post.load(Ordering::Relaxed), 0);
}
#[test]
fn shared_judge_sites_uses_existing_fingerprint_and_raw_ignores_it() {
    let (tree, run) = tree_run();
    let root = test_scratch::dir("shared-policy-judge");
    std::fs::write(
        root.join("baseline.txt"),
        "first\tcode/b.dm\tnative_b()\nfirst\tcode/a.dm\tnative_a()\n",
    )
    .unwrap();
    let probe = Probe::new(Policy::Sites {
        baseline: "baseline.txt",
        header: &[],
        banned: &[],
    });
    let scope = LintScope::default();
    let cx = Cx {
        tree: &tree,
        meta: probe.meta(),
        scope: &scope,
    };
    assert!(!judge(&probe, &cx, &run, &root, &None, false).0);
    let (failed, text) = judge(&probe, &cx, &run, &root, &None, true);
    assert!(failed);
    assert!(text.contains("code/b.dm:1:"));
    // Sites reports use fingerprint source text; Hard reports use Site.msg.
    assert!(text.contains("native_a()"));
    assert!(!text.contains("authored reason"));
}
