pub const CASES:&[&str]=&["global","signature","virtual","parent","builtin","before_first","generated","neutral","inactive","maps","exempt"];
pub fn files(case:&str)->Vec<(&'static str,String)>{let(engine,library)=match case{
 "global"=>("/proc/entry()\n    ordinary_helper()\n","/proc/ordinary_helper()\n    return 1\n"),
 "signature"=>("/datum/engine_owner\n/datum/engine_owner/proc/entry(datum/downstream/typed)\n    var/datum/downstream/local\n    typed.helper()\n","/datum/downstream\n/datum/downstream/proc/helper()\n    return\n"),
 "virtual"=>("/datum/interface\n/datum/interface/proc/hook()\n    return\n/proc/entry(datum/implementation/x)\n    x.hook()\n","/datum/implementation\n    parent_type = /datum/interface\n/datum/implementation/hook()\n    return\n"),
 "parent"=>("/datum/engine_child\n    parent_type = /datum/external_parent\n/datum/engine_child/proc/check()\n    ..()\n","/datum/external_parent\n/datum/external_parent/proc/check()\n    return\n"),
 "builtin"=>("/proc/entry(obj/x)\n    x.New()\n","/atom/proc/New()\n    return\n"),
 "before_first"=>("#define CAPABILITIES(T) /datum/later\nCAPABILITIES(helper())\n    var/value = 1\n/datum/later/proc/helper()\n    return\n","/proc/helper()\n    return\n"),
 "generated"=>("/proc/entry(datum/downstream/x)\n    return x\n","/datum/downstream\n"),
 "neutral"=>("/proc/entry(datum/downstream/x)\n    return x\n","/datum/downstream\n"),
 "inactive"=>("#if 0\n/datum/downstream\n#endif\n/proc/entry(datum/downstream/x)\n    return x\n","/datum/downstream\n"),
 "maps"=>("/proc/entry(datum/map_type/x)\n    return x\n","/datum/placeholder\n"),
 "exempt"=>("/proc/entry()\n    ordinary_helper()\n","/proc/ordinary_helper()\n    return\n"),
 _=>panic!("unknown engine fixture")};let mut rows=vec![("code/engine/probe.dm",engine.to_owned()),("code/library/arbitrary.dm",library.to_owned())];if case=="generated"{rows.push(("code/engine/_generated/reopen.dm","/datum/downstream\n".into()));}if case=="neutral"{rows.push(("code/_helpers/neutral.dm","/datum/downstream\n".into()));}if case=="maps"{rows.push(("maps/native.dm","/datum/map_type\n".into()));}if case=="exempt"{rows.push(("tools/ci/lint_scopes.toml","[lint.engine_layering]\nexempt_files=[\"code/engine/probe.dm\"]\n".into()));}let mut dme=String::new();for(path,_)in &rows{if path.ends_with(".dm"){dme.push_str(&format!("#include \"{path}\"\n"));}}rows.push(("deepquarry.dme",dme));for i in 0..140{let name=Box::leak(format!("code/filler{i:03}.dm").into_boxed_str());rows.push((name,"// raw provenance complete EOF\n".into()));}rows}
