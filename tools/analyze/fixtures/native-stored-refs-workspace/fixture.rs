//! Authored files only, no precomputed policy answer or semantic model.
pub const CASES:&[&str]=&["basic","methods","operators","literal","static","shadow","seeds","raw_relations","schema","settings","macro","noncode","allow","exempt","lists_config","same_line","registry","lifecycle"];
pub const MASTER_COLLECTION_CASES:&[&str]=&["alist_collection","nested_collection"];
pub fn files(case:&str)->Vec<(&'static str,Vec<u8>)>{assert!(CASES.contains(&case)||MASTER_COLLECTION_CASES.contains(&case));let mut types="/datum/holder\n    var/datum/loose\n    var/list/items\n".to_owned();if case=="seeds"{types.push_str("    var/list/datum/seeded\n")}if case=="same_line"{types.push_str("    var/datum/first, second\n")}
 if matches!(case,"registry"|"lifecycle"){types.push_str("    var/datum/forever/kept\n/datum/forever\n")}
 if case=="alist_collection"{types.push_str("    var/alist/methods\n    var/alist/literal\n    var/alist/insert_index_only\n");}
 if case=="nested_collection"{types.push_str("    var/list/keyed\n    var/list/value\n    var/alist/added\n    var/list/unioned\n    var/list/logical\n    var/list/grouped\n    var/icon/scalar\n    var/list/not_added\n");}
 let source=match case{
 "alist_collection"=>"/datum/holder/proc/check(datum/D)\n    methods.Add(D)\n    methods = alist(D)\n    literal = alist(D = null)\n    insert_index_only.Insert(D, null)\n    var/static/alist/persistent\n    persistent.Insert(1, D)\n    var/alist/local\n    local.Add(D)\n",
 "nested_collection"=>"/datum/holder/proc/check(datum/D)\n    keyed[1][D] = null\n    keyed.Add(D)\n    value[1][2] = D\n    added[1][2] += D\n    unioned[1][2] |= D\n    logical[1][2] ||= D\n    (grouped[1])[2] += D\n    scalar[1][2] += D\n    not_added[1][2] += null\n",
 "methods"=>"/datum/holder/proc/check(datum/D)\n    items.Add(D)\n    items.Insert(1,D)\n",
 "operators"=>"/datum/holder/proc/check(datum/D)\n    items[D] = null\n    items |= D\n    items ||= D\n",
 "literal"=>"/datum/holder/proc/check(datum/D)\n    items = list(D = null)\n    items.Add(D)\n",
 "static"=>"/datum/holder/proc/check(datum/D)\n    var/static/list/single\n    single += D\n    var/static/list/first, second\n    first += D\n    second += D\n    for(var/static/list/loop; 0; )\n        loop += D\n",
 "shadow"=>"/datum/holder/proc/check(datum/D)\n    var/list/items\n    items += D\n    src.items += D\n",
 "settings"=>"/datum/holder/proc/check(datum/D)\n    set desc = (items = list(D))\n    items += D\n",
 "macro"=>"#define STORE_ONE(X) items.Add(X)\n/datum/holder/proc/check(datum/D)\n    STORE_ONE(D)\n    items += D\n",
 "noncode"=>"// real map proc provides list write\n",
 _=>"/datum/holder/proc/check(datum/D)\n    items += D\n"};
 let raw=match case{
 "registry"=>"#if 0\nREGISTRY_TYPE(/datum/forever,key)\n#endif\n",
 "lifecycle"=>"#if 0\nLIFECYCLE_KEEP_ALWAYS(/datum/forever)\n#endif\n",
 "raw_relations"=>"#if 0\nCAPABILITIES(/datum/holder)\n    ref_many(nameof(items))\n    param(nameof(loose), keep = FALSE)\n#endif\n",
 "schema"=>"#if 0\nSCHEMA(/datum/holder,items,list_of(schema_path(/datum)))\nSCHEMA(/datum/holder,loose,schema_path(/datum))\n#endif\n",
 _=>"// no extra policy markers\n"};if case=="allow"{types=types.replace("var/datum/loose","var/datum/loose // ALLOW(stored_refs): fixture explicitly models reviewed relation free storage");}
 let config=match case{"exempt"=>"[lint.stored_refs]\nexempt_prefixes=['code/']\n","lists_config"=>"[lint.stored_refs.lists]\nwork_queues=['/datum/holder::items']\nexempt_types=[]\ntransient_types=[]\n",_=>""};let mut out=vec![("deepquarry.dme",b"#include \"code/types.dm\"\n#include \"code/raw.dm\"\n#include \"code/main.dm\"\n".to_vec()),("code/types.dm",types.into_bytes()),("code/raw.dm",raw.as_bytes().to_vec()),("code/main.dm",source.as_bytes().to_vec()),("tools/ci/lint_scopes.toml",config.as_bytes().to_vec())];if case=="noncode"{out[0].1.extend_from_slice(b"#include \"maps/stored.dm\"\n");out.push(("maps/stored.dm",b"/datum/holder/proc/map_store(datum/D)\n    items += D\n/datum/map_decl\n    var/datum/map_reference\n".to_vec()));}out}
