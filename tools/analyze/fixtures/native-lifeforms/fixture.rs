pub const CASES:&[(&str,&str)]=&[
("make_unknown","/proc/probe(loc)\n    make(/obj/declared, other = 1)\n"),
("make_required","/proc/probe(loc)\n    make(/obj/declared)\n"),
("make_parts","/proc/probe(loc)\n    make(/obj/no_reader, parts = list())\n"),
("make_valid","/proc/probe(loc)\n    make(/obj/declared, value = 1, at = loc, by = loc)\n"),
("after_literal","/proc/probe()\n    new /datum/seed/apple\n"),
("after_typed","/proc/probe()\n    var/datum/seed/seed = new\n"),
("per_type","/obj/table/proc/change()\n    table += 1\n    table.Add(1)\n"),
("per_type_builder","/obj/table/proc/build_table()\n    table += 1\n"),
("position_override","CAPABILITIES(/obj/declared/child, param(nameof(child_value), pos = 1))\n"),
("position_nothing","CAPABILITIES(/obj/no_reader, param(nameof(value), pos = 2, overrides = TRUE))\n"),
("dead_literal","/proc/probe(loc)\n    new /obj/no_reader(loc, 2, null)\n"),
("dead_implicit","/proc/probe(loc)\n    var/obj/no_reader/result = new(loc, 2)\n    return result\n"),
("read_parameter","/proc/probe(loc)\n    new /obj/reads(loc, 2)\n"),
("read_args","/proc/probe(loc)\n    new /obj/args(loc, 2, 3)\n"),
("forward","/obj/forwards/Initialize(mapload, colour)\n    return ..(mapload, colour)\n"),
("parent_grouped","/obj/forwards/Initialize(mapload, colour)\n    return ..(mapload, (colour))\n"),
("parent_dotted","/obj/forwards/Initialize(mapload, colour)\n    return ..(mapload, colour.value)\n"),
("semantic_parent","/obj/alias\n    parent_type = /obj/reads\n/proc/probe(loc)\n    new /obj/alias(loc, 2)\n"),
("same_line_nested","/proc/probe(loc)\n    var/obj/no_reader/result = new(loc, new /obj/no_reader(loc, 2), null)\n    return result\n"),
("static_scope_discards_new","/proc/probe(loc)\n    /obj/no_reader::probe(new /obj/no_reader(loc, 2))\n"),
("interpolated_new","/proc/probe(loc)\n    var/text = \"[new /obj/no_reader(loc, 2)]\"\n    return text\n"),
("grouped_null","/proc/probe(loc)\n    new /obj/no_reader(loc, (null))\n"),
("prefix_parameter","/obj/forwards/Initialize(mapload, colour)\n    return -colour\n"),
("maps","/proc/probe(loc)\n    new /obj/no_reader(loc, 2)\n"),
("allowed","/proc/probe(loc)\n    new /obj/no_reader(loc, 2) // ALLOW(lifeforms): actual old rule deliberately never consults these annotations\n"),
("exempt","/proc/probe(loc)\n    new /obj/no_reader(loc, 2)\n"),
("bom_crlf","\u{feff}/proc/probe(loc)\r\n    new /obj/no_reader(loc, 2)\r\n")
];
pub fn files(case:&str,body:&str)->Vec<(String,String)>{
 let definitions="#define CAPABILITIES(...)\n#define nameof(V) #V\n#define PROC_REF(P) #P\n/datum/seed\n/datum/seed/apple\n/obj/declared\n    var/value\n/obj/declared/child\n    var/child_value\n/obj/no_reader\n    var/value\n/obj/table\n    var/list/table\n/obj/reads/Initialize(mapload, amount)\n    return amount\n/obj/args/Initialize(mapload, ...)\n    return args\n/obj/forwards\n/proc/make(T, at, by, parts, value, other)\n    return null\nCAPABILITIES(/datum/seed, after_init(1))\nCAPABILITIES(/obj/declared, param(nameof(value), required = TRUE, pos = 1))\nCAPABILITIES(/obj/table, per_type(nameof(table), PROC_REF(build_table)))\n";
 let relative=if case=="maps"{"maps/probe.dm"}else{"code/probe.dm"};let overlay=if case=="exempt"{"[lint.lifeforms]\nexempt_files=[\"code/probe.dm\"]\n"}else{""};
 let mut files=vec![("code/definitions.dm".into(),definitions.into()),(relative.into(),body.into()),("tools/ci/lint_scopes.toml".into(),super::report_configuration::with_overlay(overlay))];
 let mut manifest=format!("#include \"code/definitions.dm\"\n#include \"{relative}\"\n");for n in 0..140{let p=format!("code/filler/f{n:03}.dm");files.push((p.clone(),format!("// actual full-source filler {n}\n")));manifest.push_str(&format!("#include \"{p}\"\n"));}files.push(("deepquarry.dme".into(),manifest));files
}
