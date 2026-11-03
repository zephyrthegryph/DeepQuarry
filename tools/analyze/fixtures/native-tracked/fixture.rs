//! Shared authored initial DM bytes, never produced findings or model answers.
pub const CASES:&[&str]=&["basic","construction","maps_tests","raw_quirks","configured","procedure_references","macro_headers"];
pub fn files(case:&str)->Option<Vec<(String,Vec<u8>)>>{if !CASES.contains(&case){return None}let definitions=br#"#define TRACKED(T,V)
#define SETTER(T,V)
#define STAT(T,V,...)
#define CAPABILITIES(T) T/proc/capability_entries()
#define PROC_REF(P) #P
#define LAZYADD(L,V)
#define LAZYREMOVE(L,V)
#define LAZYSET(L,K,V)
#define LAZYCLEARLIST(L)
/proc/setup(handler)
    return
/proc/derive(a,b)
    return a
"#;let declarations=br#"/obj/box
    var/plain = 0
    var/list/items
    var/list/parts
    var/obj/array_items[2]
    var/score = 0
    var/derived_value = 0
    var/raw_quirk = 0
TRACKED(/obj/box, plain)
SETTER(/obj/box, items)
TRACKED(/obj/box, array_items)
STAT(/obj/box, score, sum)
/obj/box/proc/set_plain(value)
    plain = value
/obj/box/proc/set_items(value)
    items = value
/obj/box/proc/derived()
    . += derive(nameof(derived_value), nameof(plain))
"#;let basic=br#"/obj/box/proc/probe(obj/box/B)
    plain = 2
    src.plain += 3
    B.plain++
    LAZYADD(items, 1)
    items.Add(2)
    items[1] = 4
    array_items[1] = B
    derived_value = 5
    var/plain = 1
    plain = 7
    src.plain = 9
/obj/box/sub/proc/change()
    plain--
/obj/box/proc/allowed()
    plain = 1 // ALLOW(tracked): the authored fixture retains this intentional write
"#;let construction=br#"CAPABILITIES(/obj/box)
    setup(PROC_REF(build_up))
/obj/box/proc/build_up()
    plain = 1
/obj/box/sub/proc/build_up()
    plain = 2
/obj/unrelated/proc/build_up()
    var/plain = 0
    plain = 3
/obj/box/proc/Initialize(mapload, obj/box/Other)
    plain = 1
    src.plain += 1
    LAZYADD(items, 2)
    Other.plain = 3
    for(var/obj/box/P in parts)
        P.plain = 4
    for(var/obj/box/R in range(1))
        R.plain = 5
/obj/box/proc/after_setup()
    plain = 6
"#;let map=br#"/obj/box/proc/map_change()
    plain = 1
    items.Remove(2)
"#;let tests=br#"/obj/box/proc/test_change()
    plain = 1
    score = 2
    items[1] = 3
"#;let quirky=br#"/*
TRACKED(/obj/box, raw_quirk)
*/
/obj/box/proc/quirky(obj/box/B)
    raw_quirk = 4
    var/items = list()
    items.Add(1)
    src.items.Add(2)
    B.items[2] = 3
    var/text = "raw_quirk = 100"
    // raw_quirk = 101
/obj/box/proc/call_names()
    list(plain = 1)
    image(loc = null, plain = 2)
    if(plain == 1)
        return plain
"#;let references=br#"/obj/box/proc/reference_target(plain)
    return plain
/obj/box/proc/reference_arguments()
    src::reference_target(
        plain = 2
    )
    src::reference_target(
        list(
            plain = 3
        )
    )
    list(
        plain = 4
    )
    ::global_target(
        plain = 5
    )
    ::global_target(list(
        plain = 6
    ))
    var/Target = /obj/box
    new Target(
        plain = 7
    )
    new src.type(list(
        plain = 8
    ))
    new /obj/box{
        plain = list(
            plain = 9
        )
    }(
        plain = 10
    )
    /obj/box{
        plain = list(
            plain = 11
        )
    }
/proc/global_target(value)
    return value
"#;let mut rows=vec![("code/__defines/fixture.dm".to_string(),definitions.to_vec()),("code/decls.dm".to_string(),declarations.to_vec()),("code/probe.dm".to_string(),basic.to_vec())];match case{"macro_headers"=>rows.push(("code/macro_headers.dm".into(),b"#define MAKE_SETTER(T) ##T/proc/set_macro(value) { plain = value }\nMAKE_SETTER(/obj/box)\n".to_vec())),"procedure_references"=>rows.push(("code/reference_arguments.dm".into(),references.to_vec())),"construction"=>rows.push(("code/construction.dm".into(),construction.to_vec())),"maps_tests"=>{rows.push(("maps/probe.dm".into(),map.to_vec()));rows.push(("code/tests/probe.dm".into(),tests.to_vec()));},"raw_quirks"=>rows.push(("code/quirks.dm".into(),quirky.to_vec())),_=>()};let config=if case=="configured"{b"[lint.tracked]\nexempt_files = [\"code/probe.dm\"]\n".as_slice()}else{b"[lint.tracked]\nexempt_prefixes = [\"code/tests/\", \"code/modules/unit_tests/\", \"code/modules/benchmarks/\"]\n".as_slice()};rows.push(("tools/ci/lint_scopes.toml".into(),config.to_vec()));let mut included:Vec<&str>=rows.iter().filter(|(name,_)|name.ends_with(".dm")).map(|(name,_)|name.as_str()).collect();included.sort_by_key(|name|(!name.starts_with("code/__defines/"),*name));let manifest=included.iter().map(|name|format!("#include \"{}\"\n",name)).collect::<String>();rows.push(("deepquarry.dme".into(),manifest.into_bytes()));Some(rows)}
