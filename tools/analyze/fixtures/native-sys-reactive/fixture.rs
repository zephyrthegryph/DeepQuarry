pub const CASES:&[&str]=&["direct","allowed","exempt","maps","auto_tracked","auto_constant","auto_write","auto_set_call","raw_context","raw_relative_invisible","bom_crlf"];
pub fn files(case:&str)->Vec<(String,String)>{
 let definitions="#define TRACKED(T, V)\n#define SETTER(T, V)\n#define PROC_REF(P) #P\n#define TYPE_PROC_REF(T, P) #P\n#define nameof(V) #V\n/datum/look\n/datum/capability\n/proc/timed_set(D, V, N)\n\treturn\n/datum/probe\n\tvar/power = 0\n\tvar/charge = 0\n\tvar/datum/probe/cell\n\tvar/needs\n\tvar/state = 0\n";
 let allow=if case=="allowed"{" // ALLOW(sys_dx_untracked_read): this fixture preserves a deliberately observed foreign dependency"}else{""};
 let mut body=format!("/datum/probe/proc/draw(datum/look/look)\n\treturn cell.power{allow}\n/datum/probe/proc/should_run()\n\tstate = 1\n\treturn cell.charge\n/datum/probe/proc/capabilities()\n\treturn state\n/datum/probe/proc/start_timed()\n\ttimed_set(src, nameof(charge), 1)\n/datum/probe/proc/change_charge()\n\tcharge = 4\n/datum/probe/proc/set_power(value)\n\tpower = value\n");
 if case=="auto_constant"{body="/datum/probe/proc/should_run()\n\treturn cell.power\n".into();}
 if case=="auto_write"{body.push_str("/datum/probe/proc/change_power()\n\tpower = 2\n");}
 if case=="auto_set_call"{body.push_str("/datum/probe/proc/call_setter()\n\tset_power(2)\n");}
 if case=="raw_context"{body.push_str("/datum/probe/proc/look_parts(datum/look/look)\n\tvar/alias = src\n\tvar/context = user\n\treturn alias.cell.power\n/datum/probe/proc/hidden_verbs()\n\treturn cell.type\n");}
 if case=="raw_relative_invisible"{body="/datum/probe\n\tproc/draw(datum/look/look)\n\t\treturn cell.power\n".into();}
 if case=="bom_crlf"{body=format!("\u{feff}{}",body.replace('\n',"\r\n"));}
 let relative=if case=="maps"{"maps/probe.dm"}else{"code/probe.dm"};
 let overlay=if case=="exempt"{"[lint.\"sys/dx_reactive\"]\nexempt_files=[\"code/probe.dm\"]\n"}else{""};
 let mut out=vec![("code/definitions.dm".into(),definitions.into()),(relative.into(),body),("tools/ci/lint_scopes.toml".into(),super::report_configuration::with_overlay(overlay))];
 let mut manifest=format!("#include \"code/definitions.dm\"\n#include \"{relative}\"\n");
 if case.starts_with("auto_"){let path="code/engine/_generated/auto_tracked.dm";let text=if case=="auto_tracked"{"TRACKED(/datum/probe, power)\n"}else{"// actual AUTO exists but has no explicit tracked names\n"};out.push((path.into(),text.into()));manifest.push_str(&format!("#include \"{path}\"\n"));}
 for n in 0..140{let name=format!("code/filler/f{n:03}.dm");out.push((name.clone(),format!("// independent whole-domain filler {n}\n")));manifest.push_str(&format!("#include \"{name}\"\n"));}
 out.push(("deepquarry.dme".into(),manifest));out
}
