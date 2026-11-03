//! Initial authored sources only; no expected source/model authority.
pub const CASES:&[&str]=&["basic","shadow","returns","noncode","macro","exempt"];
pub fn files(case:&str)->Vec<(&'static str,Vec<u8>)>{assert!(CASES.contains(&case));let types="/datum/player_holder\n    var/mob/passenger\n/mob/player_child\n";
 let basic="/datum/player_holder/proc/check(mob/P,datum/U,list/mob/L)\n    P.key = 1\n    passenger.ckey = 2\n    usr.key = 3\n    U.key = 4\n    L[1].ckey = 5\n    check(key = 6)\n    check(P.key = 7)\n    P.key += 8\n    (P.key) = 9\n/mob/player_child/proc/direct()\n    key = 10; ckey = 11\n    src.ckey = 12\n";
 let source=match case{
 "shadow"=>"/mob/player_child/proc/check(mob/P)\n    key = 1\n    var/key\n    P.ckey = 2\n    if(P.key = 3)\n        P.key = 4\n    if((P.key = 5))\n        return\n    for(P.key = 6; P.ckey = 7; P.key = 8)\n        P.key = 9\n",
 "returns"=>"/proc/player_mob_result() as /mob\n    return null\n/datum/player_holder/proc/no_hint()\n    return null\n/datum/player_holder/proc/method() as /mob\n    return null\n/datum/player_holder/proc/check(datum/player_holder/H,mob/P,obj/O,turf/T,unknown)\n    player_mob_result().key = 1\n    H.method().key = 2\n    H.player_mob_result().key = 3\n    H.no_hint().key = 4\n    unknown.player_mob_result().key = 5\n    (P ? O : P).key = 6\n    (P ? T : P).key = 7\n    (new /mob()).key = 8\n",
 "macro"=>"#define SET_PLAYER_KEY(M) M.key = 1\n/mob/player_child/proc/check(mob/P)\n    SET_PLAYER_KEY(P)\n    P.ckey = 2\n",
 _=>basic};let config=if case=="exempt"{"[lint.player_link]\nexempt_prefixes=['code/','maps/']\n"}else{""};
 let mut out=vec![("deepquarry.dme",b"#include \"code/types.dm\"\n#include \"code/main.dm\"\n".to_vec()),("code/types.dm",types.as_bytes().to_vec()),("code/main.dm",source.as_bytes().to_vec()),("tools/ci/lint_scopes.toml",config.as_bytes().to_vec())];
 if case=="noncode"{out[0].1.extend_from_slice(b"#include \"maps/player.dm\"\n");out.push(("maps/player.dm",b"/mob/player_child/proc/map_check()\n    key = 42\n".to_vec()));}out
}
