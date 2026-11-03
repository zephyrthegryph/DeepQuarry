//! Authored fixture sources only; old/native answers are independently computed.
pub const CASES:&[&str]=&["basic","shadow","returns","noncode","macro","exempt","settings"];
pub fn files(case:&str)->Vec<(&'static str,Vec<u8>)>{assert!(CASES.contains(&case));let types="/datum/member_holder\n    var/static/danger\n    var/datum/member_holder/next\n/datum/member_child\n    parent_type = /datum/member_holder\n    danger = 4\n";
 let basic="/datum/member_holder/proc/check(datum/member_holder/T,U,list/datum/member_holder/L)\n    T.danger\n    U.danger\n    L[1].danger\n    (new /datum/member_holder()).danger\n    U?.danger\n    src.danger\n";
 let source=match case{
 "shadow"=>"/datum/member_holder/proc/check(datum/member_holder/T)\n    next.danger\n    var/next\n    next.danger\n    T.next.danger\n    T.next = null\n    T.next.danger\n",
 "returns"=>"/proc/member_result() as /datum/member_holder\n    return null\n/datum/member_holder/proc/check(datum/member_holder/T,U)\n    member_result().danger\n    (T ? T : U).danger\n    T.next.danger\n    T.danger\n",
 "macro"=>"#define READ_DANGER(X) X.danger\n/datum/member_holder/proc/check(U)\n    READ_DANGER(U)\n    U.danger\n",
 "settings"=>"/datum/member_holder/proc/check(U)\n    set name = U.danger\n    set desc = call(U.danger)()\n    U.danger\n",
 "noncode"=>"/datum/member_holder/proc/check(U)\n    U.outside_static\n",
 _=>basic};let config=if case=="exempt"{"[lint.untyped_member]\nexempt_prefixes=['code/']\n"}else{""};let mut out=vec![("deepquarry.dme",b"#include \"code/types.dm\"\n#include \"code/main.dm\"\n".to_vec()),("code/types.dm",types.as_bytes().to_vec()),("code/main.dm",source.as_bytes().to_vec()),("tools/ci/lint_scopes.toml",config.as_bytes().to_vec())];if case=="noncode"{out[0].1.extend_from_slice(b"#include \"maps/member.dm\"\n");out.push(("maps/member.dm",b"/datum/noncode_static\n    var/static/outside_static\n    proc/check(U)\n        U.outside_static\n".to_vec()));}out
}
