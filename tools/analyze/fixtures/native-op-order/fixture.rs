//! Independent INPUT corpus, not expected native rows.
#[path="../report_configuration.rs"]mod report_configuration;
pub const CASES:&[(&str,&str,bool)]=&[
 ("direct", "CAPABILITIES(/obj/probe, op(\"a\", hand()), op(\"b\", hand()))\n",true),
 ("different_tier", "CAPABILITIES(/obj/probe, op(\"a\", hand()), op(\"b\", hand(), priority(OP_PRIORITY_PART)))\n",false),
 ("same_numeric_tier", "CAPABILITIES(/obj/probe, op(\"a\", hand(), priority(OP_PRIORITY_PART)), op(\"b\", hand(), priority(OP_PRIORITY_PART+0)))\n",true),
 ("relative", "CAPABILITIES(/obj/probe, op(\"a\", hand(), priority(above(\"b\"))), op(\"b\", hand()))\n",true),
 ("relative_allow", "CAPABILITIES(/obj/probe, op(\"a\", hand(), priority(above(\"b\"))), op(\"b\", hand())) // ALLOW(op_order): Fixture intentionally retains the relative ordering form\n",false),
 ("clash_allow", "// ALLOW(op_order): Fixture intentionally retains a real ambiguous pair\nCAPABILITIES(/obj/probe, op(\"a\", hand()), op(\"b\", hand()))\n",false),
 ("exempt_target", "CAPABILITIES(/obj/probe, op(\"a\", hand()), op(\"b\", hand()))\n",false),
 ("capability", "CAPABILITIES(/obj/probe, cover())\n",true),
 ("exempt_constructor", "CAPABILITIES(/obj/probe, cover())\n",true),
 ("selector", "CAPABILITIES(/obj/probe, cover(slot=\"left\"), cover(slot=\"right\"))\n",true),
 ("bundle", "CAPABILITIES(/obj/probe, composed())\n",true),
 ("global_fallback", "CAPABILITIES(/obj/probe, assembled(TRUE))\n",true),
 ("constructor_false", "CAPABILITIES(/obj/probe, assembled(FALSE))\n",false),
 ("mutually_exclusive", "CAPABILITIES(/obj/probe, op(\"a\", hand(), when(req_bool(active))), op(\"b\", hand(), when(not(active))))\n",false),
 ("stance", "CAPABILITIES(/obj/probe, op(\"a\", hand(), stance(I_STAND)), op(\"b\", hand(), stance(I_CROUCH)))\n",false),
 ("specificity", "CAPABILITIES(/obj/probe, op(\"a\", item(/obj/item)), op(\"b\", item(/obj/item/tool)))\n",false),
 ("same_specificity", "CAPABILITIES(/obj/probe, op(\"a\", item(/obj/item/tool)), op(\"b\", stack(/obj/item/tool)))\n",true),
 ("click_order", "CAPABILITIES(/obj/probe, op(\"a\", hand()), op(\"b\", hand()), click_order(BIND_HAND,\"a\",\"b\"))\n",false),
 ("extends", "CAPABILITIES(/obj/probe, op(\"a\", hand()), op(\"b\", hand()), extend(\"a\", passes()))\n",false),
 ("duplicate_key", "CAPABILITIES(/obj/probe, op(\"a\", hand()), op(\"b\", hand()), op(\"a\", gesture(GESTURE_DRAG), hand()))\n",false),
 ("generated_target", "CAPABILITIES(/obj/probe, op(\"a\", hand()), op(\"b\", hand()))\n",false),
 ("generated_constructor", "CAPABILITIES(/obj/probe, generated_bundle())\n",true),
 ("uncompiled", "CAPABILITIES(/obj/probe, op(\"a\", hand()), op(\"b\", hand()))\n",true),
 ("recursive_bundle", "CAPABILITIES(/obj/probe, recursive_bundle())\n",true),
 ("raw_comment", "// CAPABILITIES(/obj/hidden,op(\"a\",hand()),op(\"b\",hand()))\nCAPABILITIES(/obj/probe, op(\"a\", hand()), op(\"b\", hand())) // priority(above(\"gone\"))\n",true),
 ("bom_crlf", "\u{feff}// universal newline fixture\r\nCAPABILITIES(/obj/probe,op(\"a\",hand()),op(\"b\",hand()))\r\n",true),
 ("unicode_substitution", "CAPABILITIES(/obj/probe,cover(slot=\"é漢\"))\n",true),
 ("dme_order_bundle_override", "CAPABILITIES(/obj/probe,composed())\n",true),
 ("dme_order_single_last", "CAPABILITIES(/obj/probe,composed())\n",false),
 ("missing_manifest", "CAPABILITIES(/obj/probe,op(\"a\",hand()),op(\"b\",hand()))\n",true),
];
pub fn files(case:&str,body:&str)->Vec<(String,String)>{
 let mut files=Vec::new();
 let path=if case=="generated_target"{"code/engine/_generated/probe.dm"}else if case=="uncompiled"{"code/uncompiled.dm"}else{"code/probe.dm"};
 files.push((path.into(),body.into()));
 files.push(("code/library/constructors.dm".into(),concat!(
 "CAPABILITY_DEF(cover, \"Cover fixture\", key=slot, slot=null)\n",
 "/datum/capability/def/cover/entries()\n    return list(op(\"a\", hand()), op(\"b\", hand()))\n",
 "/proc/composed()\n    return list(op(\"a\", hand()), op(\"b\", hand()))\n",
 "/proc/assembled(enabled)\n    . = list(op(\"a\", hand()))\n    if(enabled) . += op(\"b\", hand())\n",
 "/proc/recursive_bundle()\n    return list(recursive_bundle(), op(\"a\", hand()), op(\"b\", hand()))\n").into()));
 files.push(("code/engine/_generated/constructors.dm".into(),"/proc/generated_bundle()\n    return list(op(\"a\", hand()), op(\"b\", hand()))\n".into()));
 for n in 0..141{files.push((format!("code/filler/f{n:03}.dm"),format!("// filler {n}\n")));}
 if case.starts_with("dme_order_"){files.push(("code/a.dm".into(),"/proc/composed()\n    return list(op(\"a\",hand()),op(\"b\",hand()))\n".into()));files.push(("code/z.dm".into(),"/proc/composed()\n    return list(op(\"only\",hand()))\n".into()));}
 let mut manifest=String::from("this is not a valid compiled declaration graph\n");
 for(path,_)in &files{if (case!="uncompiled"||path!="code/uncompiled.dm")&&(!case.starts_with("dme_order_")||!(path=="code/a.dm"||path=="code/z.dm")){manifest.push_str(&format!("#include \"{}\"\n",path.replace('/',"\\")));}}
 if case=="dme_order_bundle_override"{manifest.push_str("#include \"code/z.dm\"\n#include \"code/a.dm\"\n");}else if case=="dme_order_single_last"{manifest.push_str("#include \"code/a.dm\"\n#include \"code/z.dm\"\n");}
 if case!="missing_manifest"{files.push(("deepquarry.dme".into(),manifest));}
 let exempt=match case{"exempt_target"=>"code/probe.dm","exempt_constructor"=>"code/library/constructors.dm",_=>"no-match"};
 let overlay=format!("[lint.op_order]\nexempt_files=[\"{exempt}\"]\n");
 files.push(("tools/ci/lint_scopes.toml".into(),report_configuration::with_overlay(&overlay)));
 files.push(("tools/ci/op_order_baseline.txt".into(),String::new()));
 files
}
