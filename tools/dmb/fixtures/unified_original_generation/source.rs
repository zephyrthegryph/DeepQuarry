//! Initial source only, shared by independent original and native generators.
pub const CASES:[&str;4]=["real","absent","noninclude","invalid_utf8"];
pub fn guarded_probe(initial:&str)->String{format!("{initial}\n#if DM_BUILD == 1666 && DM_VERSION == 516 && SPACEMAN_DMM\n/datum/probe\n    var/original_context_value\n    proc/original_context_reader()\n        return original_context_value\n/obj/original_generation_item\n    name = \"original generation subject\"\n#else\n#error Original generation requires the genuine original default context\n#endif\n")}
pub fn manifest(case:&str,real:Vec<u8>)->Option<Vec<u8>>{match case{"real"=>Some(real),"absent"=>None,"noninclude"=>Some(b"/datum/ignored_fixed_manifest\n".to_vec()),"invalid_utf8"=>Some(b"\xff#include ignored\n".to_vec()),_=>panic!("unknown initial generation case")}}

/// Synthetic initial cases carry their macro/global declarations in actual CODE.
pub fn synthetic_support(real:&[u8])->String{std::str::from_utf8(real).unwrap().lines().filter(|line|!line.trim_start().starts_with("#include")).map(|line|format!("{line}\n")).collect()}
