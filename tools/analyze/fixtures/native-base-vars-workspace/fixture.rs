//! Shared authored sources only; expected rows come from independent original execution.
pub const CASES:&[&str]=&["basic","allowed","homes","hot","hidden","record_noncode"];
pub fn files(case:&str)->Vec<(&'static str,Vec<u8>)>{
 let allow=if case=="allowed"{" // ALLOW(base_vars): this base variable intentionally stores real instance fixture state"}else{""};
 let mut source=format!("#define TRACKED(T,V)\n#define SCHEMA(T,V,S)\n/atom\n    var/tmp/bv_plain = 0{allow}\n    var/tmp/bv_schema = 0\n    var/static/bv_shared = 0\n/obj/bv_fixture\n    var/list/bv_items = list()\n/datum/record\n/datum/record/proc/get_allowed()\n    return\n/datum/record/proc/do_work()\n    return\nSCHEMA(/atom, bv_schema, schema_path(/datum))\n");
 if case=="homes"{source.push_str("TRACKED(/atom, bv_plain)\n");}
 let mut scope=String::from("[lint.base_vars.lists]\nlist_init_exempt_prefixes=[]\nlist_init_exempt_files=[]\nbase_var_home_macros=['TRACKED']\nbase_var_home_relations=[]\nbase_var_home_types=[]\nrecord_accessor_prefixes=['get_','set_']\nhot_ceiling=['2']\n");
 if case=="hot"{scope.push_str("[lint.base_vars.tables.base_var_home_hot]\n'/atom/bv_plain'='read every active tick in code/reader.dm /atom/proc/tick'\n'/atom/bv_missing'='short'\n");}
 let mut files=vec![("deepquarry.dme",b"#include \"code/probe.dm\"\n#include \"maps/record.dm\"\n".to_vec()),("code/probe.dm",source.into_bytes()),("maps/record.dm",b"/datum/record/map/proc/non_code_work() // ALLOW(base_vars): original record methods deliberately never ask this annotation\n    return\n".to_vec()),("tools/ci/lint_scopes.toml",scope.into_bytes())];
 if case=="hidden"{files.push(("code/.hidden/homes.dm",b"TRACKED(/atom, bv_plain)\n/atom\n    var/tmp/hidden_not_compiled = 1 // ALLOW(base_vars): hidden raw declarations are not annotation questions\n".to_vec()));}
 if case=="record_noncode"{files.push(("code/uncompiled.dm",b"/atom\n    var/tmp/uncompiled_question = 1 // ALLOW(base_vars): raw declaration questions include uncompiled source files\n".to_vec()));}
 files
}
