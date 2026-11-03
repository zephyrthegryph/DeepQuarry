pub const CASES:&[&str]=&["unknown","raw","registry","kinds","contradiction","globals","subtype","allow","exempt","string_bug","malformed","clean","large_menu","large_generated","large_members"];
pub fn files(case:&str)->Vec<(&'static str,String)>{
 let mut rows:Vec<(&'static str,String)>=vec![("maps/ignored.dm","/obj/map_only/proc/x()\n    own_set(src, nameof(missing), null)\n".into()),("code/.hidden.dm","/obj/hidden/proc/x()\n    own_set(src, nameof(missing), null)\n".into())];
 if matches!(case,"large_menu"|"large_generated"|"large_members"){
  let mut source=String::from("/obj/holder\n    var/obj/child\n");
  if case=="large_menu"{let row=format!("    // {}\n","captured menu argument text é漢 ".repeat(90));while source.len()<1_550_277{source.push_str(&row);}}
  else if case=="large_generated"{let mut i=0;while source.len()<9_609_633{source.push_str(&format!("/obj/holder/proc/generated_{i:06}()\n    return null\n"));i+=1;}}
  else{for i in 0..8192{source.push_str(&format!("    var/obj/member_{i:05}\n"));}}
  rows.push(("code/main.dm",source));return rows;
 }
 let source=match case{
 "unknown"=>"/obj/holder/proc/x()\n    own_set(src, nameof(missing), null)\n",
 "raw"=>"/obj/holder\n    var/obj/child\n    var/list/children\n/obj/holder/proc/x(obj/item/new_child)\n    child = new /obj/item\n    children += new_child\n    LAZYADD(children, new_child)\n    CALLBACK(src, PROC_REF(x))\n",
 "registry"=>"REGISTRY_TYPE(/datum/book, main)\n/obj/holder\n    var/datum/book/entry\n/obj/holder/ownership()\n    . += owns(nameof(entry), OWN_QDEL)\n/obj/holder/proc/x()\n    own_set(src, nameof(entry), null)\n",
 "kinds"=>"/obj/holder\n    var/obj/child\n/obj/holder/ownership()\n    . += owns(nameof(child), OWN_QDEL)\n/obj/holder/sub/relations()\n    . += rel_one(nameof(child))\n",
 "contradiction"=>"/obj/holder\n    var/obj/child\n/obj/holder/ownership()\n    . += owns(nameof(child), OWN_QDEL)\n/obj/holder/proc/x()\n    own_set(src, nameof(child), null)\n    rel_link(src, nameof(child), null)\n    shared_set(src, nameof(child), null)\n",
 "globals"=>"GLOBAL_DATUM(known, /obj/item)\n/obj/holder/proc/x()\n    own_set(GLOB, nameof(known), null)\n    own_set(GLOB, nameof(unknown), null)\n",
 "subtype"=>"/obj/holder/sub\n    var/obj/child\n/obj/holder/proc/x()\n    own_set(src, nameof(child), null)\n    own_set(src, nameof(missing), null)\n",
 "allow"=>"/obj/holder\n    var/obj/child\n/obj/holder/proc/x()\n    child = new /obj/item // ALLOW(ownership): world.Export() is a blocking external call\n    CALLBACK(src, PROC_REF(x)) // ALLOW(ownership): world.Export() is a blocking external call\n",
 "exempt"=>"/obj/holder\n    var/obj/child\n/obj/holder/proc/x()\n    child = new /obj/item\n    own_set(src, nameof(missing), null)\n",
 "string_bug"=>"/obj/holder/proc/x()\n    own_set(src, \"missing\", null)\n    \u{8}own_set(src, \"missing\", null)\n",
 "malformed"=>"#if MALFORMED(\n/obj/holder/proc/x(\n    own_set(src, nameof(missing), null)\n",
 "clean"=>"/obj/holder\n    var/obj/child\n/obj/holder/proc/x()\n    own_set(src, nameof(child), null)\n",
 _=>panic!("unknown ownership fixture")};rows.push(("code/main.dm",source.into()));if case=="exempt"{rows.push(("tools/ci/lint_scopes.toml","[lint.ownership]\nexempt_files=[\"code/main.dm\"]\n".into()));}if case=="malformed"{rows.push(("deepquarry.dme","#include \"file-that-does-not-exist.dm\"\n".into()));}for i in 0..140{let name=Box::leak(format!("code/filler{i:03}.dm").into_boxed_str());rows.push((name,"// complete physical CODE EOF coverage\n".into()));}rows}
