//! Initial source data, with no native answers or generated output stubs.
pub const CASES:&[&str]=&["lexical_rules","global_fields","allow_phase_order","last_writer_and_exempt_index"];
pub fn files(case:&str)->Option<Vec<(&'static str,Vec<u8>)>>{if !CASES.contains(&case){return None}let mut files=vec![("p.dme",b"#include \"code/probe.dm\"\n".to_vec()),("code/probe.dm",b"/proc/probe()\n    return 1\n".to_vec()),("tools/ci/lint_scopes.toml",Vec::new())];match case{
 "lexical_rules"=>files.push(("code/raw.dm",br#"/proc/raw_rules()
    om_task_timed(a,b,c,d,e,list(1,2,3))
    use_tool(done_args=list(1,2,3))
    om_set_var(src, x, 1)
    vars["x"] = 1
    TIMER_COOLDOWN_START(src,key,1)
    BUCKLED(src)
    vg_world_watch_probe(src)
    om_world_publish("key")
    om_prompt(src)
    om_task_start(a,b,c,list(1))
    SSreactor.fire()
    om_relation_of(src)
"#.to_vec())),
 "global_fields"=>{files.push(("code/fields.dm",b"OM_FIELD(/datum/probe, charge, 0, CHANNEL)\nGLOBAL_DATUM_INIT(shared, /datum/probe)\n/datum/probe\n    var/charge\n    proc/set_charge(value)\n        charge=value\n    proc/raw()\n        charge=1\n/proc/global_write()\n    GLOB.shared.charge=2\n".to_vec()));files.push(("code/unit_tests/raw.dm",b"/datum/probe/proc/test_write()\n    charge=3\n    om_set_var(src,x,1)\n".to_vec()));},
 "allow_phase_order"=>files.push(("code/both.dm",b"OM_FIELD(/datum/probe, charge, 0, CHANNEL)\n/datum/probe/proc/raw()\n    om_set_var(src,x,1) // ALLOW(api): this exact old alternative is retained for the source fixture\n    charge=1 // ALLOW(api): this direct old field write is retained for the source fixture\n    vars[\"x\"]=1; charge=2 // ALLOW(api): one annotation is independently used by both policy phases\n    charge=3\n".to_vec())),
 "last_writer_and_exempt_index"=>{files.push(("code/a-declared.dm",b"OM_FIELD(/datum/first, charge, 0, CHANNEL)\n/datum/holder\n    var/datum/first/member\n".to_vec()));files.push(("code/z-last.dm",b"/datum/holder\n    var/datum/second/member\n/datum/first/proc/raw()\n    charge=1\n/datum/holder/proc/raw()\n    member.charge=2\n".to_vec()));files[2].1=b"[lint.api]\nexempt_files=[\"code/a-declared.dm\"]\n".to_vec();},_=>return None}Some(files)}
