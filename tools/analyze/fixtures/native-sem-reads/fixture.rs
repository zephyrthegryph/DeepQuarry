//! Shared initial source only; no native answers or golden rows.
pub const CASES:&[&str]=&["basic","allowed","published","hop_cycle","accessor_only_published","accessor_only_gap"];
pub fn files(case:&str)->Option<Vec<(String,Vec<u8>)>>{if !CASES.contains(&case){return None}let mut rows=vec![
("code/modules/apc/apc.dm".to_owned(),include_bytes!("basic/code/modules/apc/apc.dm").to_vec()),
("code/modules/apc/engine.dm".to_owned(),include_bytes!("basic/code/modules/apc/engine.dm").to_vec()),
("code/modules/apc/helpers.dm".to_owned(),include_bytes!("basic/code/modules/apc/helpers.dm").to_vec()),
("code/__defines/engine.dm".to_owned(),include_bytes!("basic/code/__defines/engine.dm").to_vec()),
];
for(relative,bytes)in &mut rows{if relative=="code/modules/apc/apc.dm"{let mut text=String::from_utf8(std::mem::take(bytes)).unwrap();match case{
"allowed"=>{text=text.replace("return mode == 2","return mode == 2 // ALLOW(reads): this deliberately mutable field is sampled by the fixture");},
"published"|"accessor_only_published"=>{text=text.replace("PUBLISH_CHANGE(src, PAD_KEY)","PUBLISH_CHANGE(src, PAD_KEY)\n\tPUBLISH_CHANGE(src, SECRET_KEY)");},
"hop_cycle"=>{text=text.replace("var/b_in = 0","var/b_in = 0\n\tvar/obj/machinery/loop/next");text=text.replace("/obj/machinery/loop/proc/derive_derived_a()","REL(/obj/machinery/loop, next)\n/obj/machinery/loop/proc/derive_derived_a()");text=text.replace("return derived_a * 2","return next ? next.derived_a * 2 : 0");},
_=>{}}if matches!(case,"accessor_only_published"|"accessor_only_gap"){let start=text.find("CAPABILITIES(/obj/machinery/apc,").unwrap();let end=start+text[start..].find("when(PROC_REF(loops)))").unwrap()+"when(PROC_REF(loops)))".len();text.replace_range(start..end,"");}*bytes=text.into_bytes();}}
rows.sort_by(|a,b|a.0.cmp(&b.0));let manifest=rows.iter().map(|(relative,_)|format!("#include \"{}\"\n",relative.replace('/',"\\"))).collect::<String>();rows.push(("deepquarry.dme".to_owned(),manifest.into_bytes()));Some(rows)}
