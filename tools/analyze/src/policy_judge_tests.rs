use super::*;
#[path="policy_judge_original.rs"]mod original_policy;
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
    let cx = Cx { fixture:None,
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
    let cx = Cx { fixture:None,
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
    let cx = Cx { fixture:None,
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
    let cx = Cx { fixture:None,
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

struct DeliveredSource;
impl crate::baseline::SiteText for DeliveredSource {
    fn site_text(&self,rel:&str,line:usize)->String {
        match (rel,line) { ("code/a.dm",1)=>"native_a()".into(),("code/b.dm",1)=>"native_b()".into(),_=>String::new() }
    }
}
#[test]
fn delivered_source_report_matches_entire_legacy_judgement_for_all_standard_policies(){
    let (tree,run)=tree_run();let root=test_scratch::dir("delivered-report-policies");
    std::fs::write(root.join("sites.txt"),"first\tcode/gone.dm\told()\n").unwrap();
    std::fs::write(root.join("counts.txt"),"first 1\nsecond 0\n").unwrap();
    for policy in [Policy::Hard,Policy::Sites{baseline:"sites.txt",header:&[],banned:&["second"]},Policy::Ceilings{baseline:"counts.txt",header:&[]}] {
        let probe=Probe::new(policy);
        for ceiling in [false,true] {
            let mut scope=LintScope::default();if ceiling{scope.ceilings.insert("first".into(),1);}
            let cx=Cx{ fixture:None,tree:&tree,meta:probe.meta(),scope:&scope};
            for raw in [false,true] {for changed in [None,Some(HashSet::from(["code/a.dm".into()])),Some(HashSet::new())] {
                let expected=original_policy::judge(&probe,&cx,&run,&root,&changed,raw);
                let actual=judge_report(probe.meta(),&scope,&DeliveredSource,&run,&root,&changed,raw,
                    |_,_,_|panic!("standard policies never use custom callback"),
                    |_,text|{text.push_str("post\n");false});
                assert_eq!(actual,expected,"complete report/failure bit/notes/order/ceilings/raw/changed policy must match");
            }}
        }
    }
}
#[test]
fn delivered_source_custom_and_post_protocols_remain_explicit_and_distinct(){
    let (tree,run)=tree_run();let scope=LintScope::default();let probe=Probe::new(Policy::Custom);
    let cx=Cx{ fixture:None,tree:&tree,meta:probe.meta(),scope:&scope};
    for changed in [None,Some(HashSet::new())] {
        let expected=original_policy::judge(&probe,&cx,&run,Path::new(""),&changed,true);
        let actual=judge_report(probe.meta(),&scope,&DeliveredSource,&run,Path::new(""),&changed,true,
            |filtered,text,raw|{writeln!(text,"custom {} {}",filtered.sites.len(),raw).unwrap();!filtered.sites.is_empty()},
            |_,_|panic!("custom already owns finish protocol"));
        assert_eq!(actual,expected);
    }
}

struct CapturedBaselineWork;
impl crate::policy_finish::admitted::Work for CapturedBaselineWork {
    fn checkpoint(&self) -> std::io::Result<()> { Ok(()) }
    fn reserve(&self, _: usize) -> std::io::Result<()> { Ok(()) }
    fn overflow(&self) -> std::io::Error { std::io::ErrorKind::OutOfMemory.into() }
}

#[test]
fn captured_ci_baselines_match_independent_original_without_live_reads() {
    let oracle = test_scratch::dir("captured-ci-oracle");
    let unrelated = test_scratch::dir("captured-ci-unrelated");
    let tree = Tree::from_files(vec![SourceFile::from_text(
        "code/item.dm", "src.set_power(5)\nset_power(7)\n",
    )]);
    let mut sink = Sink::new();
    sink.site_in("init_lines", "code/item.dm", 1);
    sink.site_in("init_lines", "code/item.dm", 2);
    let mut run = Run { sites: sink.sites, notes: vec!["authored note".into()] };
    run.sites[0].key = "admitted".into();
    run.sites[1].key = "new".into();
    let scope = LintScope::default();
    for (policy, fixtures) in [
        (Policy::Sites { baseline: "policy.txt", header: &[], banned: &[] }, [
            "init_lines\tcode/item.dm\tpower = 5\r\ninit_lines\tcode/item.dm\tset_power(7)\rinit_lines\tcode/gone.dm\tx = 1\n",
            "init_lines\tcode/item.dm\tpower = 5\n",
        ]),
        (Policy::Ceilings { baseline: "policy.txt", header: &[] }, [
            "admitted 0\radmitted 1 # last duplicate wins\r\nnew 1\nstale 2\n",
            "admitted 1\nnew 0\nstale 2\n",
        ]),
    ] {
        let mut probe = Probe::new(policy);
        probe.meta.rules = &[RuleMeta { name: "init_lines", hint: "use the native form" }];
        let cx = Cx { fixture:None, tree: &tree, meta: probe.meta(), scope: &scope };
        for (ordinal, text) in fixtures.into_iter().enumerate() {
            std::fs::write(oracle.join("policy.txt"), text).unwrap();
            std::fs::write(unrelated.join("policy.txt"), "different current bytes").unwrap();
            let expected = original_policy::judge(&probe, &cx, &run, &oracle, &None, false);
            assert_eq!(expected.0, ordinal == 1, "positive control must genuinely pass");
            let actual = crate::policy_finish::admitted::judge_captured_baseline(
                probe.meta(), &scope, &tree, &run, &unrelated, Some(text.as_bytes()),
                &CapturedBaselineWork, |_, out| { out.push_str("post\n"); false },
            ).unwrap();
            assert_eq!(actual, expected);
        }
        std::fs::write(oracle.join("policy.txt"), [0xff]).unwrap();
        let expected = original_policy::judge(&probe, &cx, &run, &oracle, &None, false);
        for absent in [None, Some(&[0xff][..])] {
            let actual = crate::policy_finish::admitted::judge_captured_baseline(
                probe.meta(), &scope, &tree, &run, &unrelated, absent,
                &CapturedBaselineWork, |_, out| { out.push_str("post\n"); false },
            ).unwrap();
            assert_eq!(actual, expected);
        }
    }
}
