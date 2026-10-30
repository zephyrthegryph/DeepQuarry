//! Independent raw old CLI transcripts; ONLY complete target groups may permute.
//! No producer row sorting, note normalization, whitespace trimming or dedup.
use super::*;
use dm_analysis::checker_effects::{TARGET_GROUP_ORDER_CONTRACT, EFFECT_PHASE_ORDER};
use std::collections::BTreeMap;

/// Preserve raw message/note whitespace and bare CR. Change ONLY oracle Windows
/// transport CRLF and the fixture filename printed before ", line ".
fn fixture_filename(text: &str) -> String {
    let transport = decode_oracle_transport(text);
    let mut out = String::new();
    for line in transport.split_inclusive('\n') {
        if !line.starts_with("- ") {
            if let Some(at) = line.find(", line ") {
                out.push_str("@FIXTURE@"); out.push_str(&line[at..]); continue;
            }
        }
        out.push_str(line);
    }
    out
}
#[derive(Debug, Eq, PartialEq)]
struct TargetGroups(Vec<(usize, BTreeMap<String, String>)>);
/// This comparator never sorts individual rows/notes. It preserves every byte
/// INSIDE each contiguous target group, and rejects split/repeated groups or
/// reversed family phases. BTreeMap compares only the whole-group permutation.
fn target_groups(text: &str) -> TargetGroups {
    let text = fixture_filename(text);
    let mut phases: Vec<(usize, BTreeMap<String, String>)> = Vec::new();
    let mut active: Option<(usize, String, String)> = None;
    let finish = |active: &mut Option<(usize,String,String)>, phases: &mut Vec<(usize,BTreeMap<String,String>)>| {
        if let Some((phase,key,bytes)) = active.take() {
            if phases.last().is_none_or(|p|p.0 != phase) {
                assert!(phases.last().is_none_or(|p|p.0 < phase), "family/prelude order is NOT permutation-normalized");
                phases.push((phase,BTreeMap::new()));
            }
            assert!(phases.last_mut().unwrap().1.insert(key,bytes).is_none(), "a target group cannot be split or revisited");
        }
    };
    for row in text.split_inclusive("\n\n") {
        assert!(row.ends_with("\n\n"), "full original diagnostic row terminator must survive");
        let (header,body) = row.split_once('\n').expect("header");
        assert!(header.starts_with("@FIXTURE@, line "));
        let message = body.split_once('\n').unwrap().0;
        let phase = if message.contains("SpacemanDMM_should_not_sleep") || message.contains("override child proc that sleeps") { 1 }
            else if message.contains("impure operations") { 2 }
            else { panic!("unclassified body/prelude diagnostic must be explicitly admitted, never sorted: {message}") };
        if active.as_ref().is_some_and(|a|a.0 == phase && a.1 == header) {
            active.as_mut().unwrap().2.push_str(row);
        } else { finish(&mut active,&mut phases); active=Some((phase,header.into(),row.into())); }
    }
    finish(&mut active,&mut phases);
    TargetGroups(phases)
}
fn native_transcript(snapshot: &SourceSnapshot, input: &Arc<EffectInput>, family: &str) -> String {
    let mut text = String::new();
    // Original whole-checker phase order, not whichever report was requested first.
    if family == "both" {
        let pure=snapshot.native_purity_report(input,&env(),None,&snapshot.tree).unwrap();
        for row in pure.iter().filter(|r|r.registration_tag.is_none()) { text.push_str(&render(std::slice::from_ref(row))); }
        let sleep=snapshot.native_sleep_report(input,&env(),None,&snapshot.tree).unwrap();
        text.push_str(&render(&sleep));
        for row in pure.iter().filter(|r|r.registration_tag.is_some()) { text.push_str(&render(std::slice::from_ref(row))); }
    } else if family=="sleep" {
        text.push_str(&render(&snapshot.native_sleep_report(input,&env(),None,&snapshot.tree).unwrap()));
    } else { text.push_str(&render(&snapshot.native_purity_report(input,&env(),None,&snapshot.tree).unwrap())); }
    text
}
fn case(name: &str, family: &str, source: &str, config: &[u8], references: [&str;4], expected_rows: usize) {
    assert_eq!(EFFECT_PHASE_ORDER,["body_immediate","must_not_sleep","must_be_pure"]);
    assert!(TARGET_GROUP_ORDER_CONTRACT.contains("whole_target_group_permutation"));
    let config=(!config.is_empty()).then_some(config);
    let(snapshot,reads)=fixture(source,config);let input=snapshot.native_purity_input(&snapshot.tree).unwrap();
    let db=snapshot.native_raw_queries.as_ref().unwrap();
    let actual=native_transcript(&snapshot,&input,family);
    assert_eq!(actual.matches("@FIXTURE@, line ").count(),expected_rows,"actual independently observed old row coverage: {name}");
    let grouped=target_groups(&actual);
    for (i,reference) in references.iter().enumerate() {
        assert_eq!(grouped,target_groups(reference),"{name} old run{i}; normalization={TARGET_GROUP_ORDER_CONTRACT}; only WHOLE target groups may permute, never inner rows/notes");
    }
    let counts=(17..=22).map(|k|db.db().stats(dm_query::Kind(k)).computed).collect::<Vec<_>>();
    let parsed=db.db().stats(dm_query::Kind(4)).computed;let io=reads.load(Ordering::Relaxed);
    assert_eq!(db.db().stats(dm_query::Kind(18)).computed,1,"both reports share original EffectPlan, no duplicate callgraph");
    assert_eq!(native_transcript(&snapshot,&input,family),actual,"native authored target order deterministic on warm read");
    assert_eq!((17..=22).map(|k|db.db().stats(dm_query::Kind(k)).computed).collect::<Vec<_>>(),counts);
    assert_eq!(db.db().stats(dm_query::Kind(4)).computed,parsed);assert_eq!(reads.load(Ordering::Relaxed),io);
    match name {
        "sleep-shared-spawn" => { assert!(actual.contains("/proc/second sets")); assert!(!actual.contains("/proc/first sets"),"spawn-first visited suppression is per-target; second must still report same shared callee"); }
        "sleep-waitfor-exempt" => { assert!(actual.contains("/proc/own_exempt sets")); assert!(actual.contains("/proc/own_waitfor sets")); assert!(!actual.contains("blocking proc /proc/exempt")); assert!(!actual.contains("blocking proc /proc/asynchronous")); }
        "configuration-off" => assert!(actual.is_empty(),"configured family suppression applies to every target"),
        _ => (),
    }
}
#[test]
fn multiple_targets_match_all_independent_whole_group_oracles_and_reuse_same_plan() {
    macro_rules! run { ($name:literal,$family:literal,$count:literal) => {case($name,$family,
        include_str!(concat!("../../../fixtures/unified_checks/effect_multi_target/",$name,"/probe.dme")),
        include_bytes!(concat!("../../../fixtures/unified_checks/effect_multi_target/",$name,"/checker.toml")),[
        include_str!(concat!("../../../fixtures/unified_checks/effect_multi_target/",$name,"/reference-0.stderr")),
        include_str!(concat!("../../../fixtures/unified_checks/effect_multi_target/",$name,"/reference-1.stderr")),
        include_str!(concat!("../../../fixtures/unified_checks/effect_multi_target/",$name,"/reference-2.stderr")),
        include_str!(concat!("../../../fixtures/unified_checks/effect_multi_target/",$name,"/reference-3.stderr"))],$count)}; }
    run!("purity-shared","purity",3);run!("purity-inherited","purity",2);
    run!("sleep-shared-spawn","sleep",1);run!("sleep-waitfor-exempt","sleep",5);
    run!("both-families","both",4);run!("configuration-off","purity",0);
}
#[test]
fn oracle_normalizer_accepts_only_complete_target_groups_and_preserves_rows_notes_and_phases() {
    let a="@FIXTURE@, line 1, column 1:\nerror: a does impure operations\n- 2:3: note one\n- 4:5: note two\n\n";
    let a2="@FIXTURE@, line 1, column 1:\nerror: a calls c which has override child proc that does impure operations d\n- 6:7: note three\n\n";
    let b="@FIXTURE@, line 8, column 1:\nerror: b does impure operations\n- 9:2: other\n\n";
    let sleep="@FIXTURE@, line 10, column 1:\nerror: s sets SpacemanDMM_should_not_sleep but calls blocking built-in(s)\n- 11:2: sleep() called here\n\n";
    assert_eq!(target_groups(&format!("{a}{a2}{b}")),target_groups(&format!("{b}{a}{a2}")));
    assert_ne!(target_groups(&format!("{a}{a2}{b}")),target_groups(&format!("{a2}{a}{b}")),"rows within group never sorted");
    assert_ne!(target_groups(a),target_groups(&a.replace("- 2:3: note one\n- 4:5: note two","- 4:5: note two\n- 2:3: note one")),"notes never sorted");
    assert_ne!(target_groups(a),target_groups(&a.replace("note one","note  one")),"whitespace never trimmed");
    assert!(std::panic::catch_unwind(||target_groups(&format!("{a}{b}{a2}"))).is_err(),"split/revisited groups refuse");
    assert!(std::panic::catch_unwind(||target_groups(&format!("{a}{sleep}"))).is_err(),"family order cannot permute");
    assert_eq!(target_groups(&format!("{sleep}{a}")),target_groups(&format!("{sleep}{a}")));
}
