//! Shared initial source bytes only, never native answers or expected output.
pub const CASES:&[&str]=&["basic","configured","order","bom","invalid_manifest"];
pub fn files(case:&str)->Option<Vec<(&'static str,&'static [u8])>>{
 let mut rows=vec![("p.dme",include_bytes!("basic/p.dme").as_slice()),("code/0000.dm",include_bytes!("basic/code/0000.dm").as_slice())];
 match case{
  "basic"|"configured"=>{
   rows.extend([
    ("code/modules/keys/ids.dm",include_bytes!("basic/code/modules/keys/ids.dm").as_slice()),
    ("code/modules/keys/systems.dm",include_bytes!("basic/code/modules/keys/systems.dm").as_slice()),
    ("code/modules/keys/things.dm",include_bytes!("basic/code/modules/keys/things.dm").as_slice()),
    ("code/modules/unit_tests/t.dm",include_bytes!("basic/code/modules/unit_tests/t.dm").as_slice()),
   ]);if case=="configured"{rows.push(("tools/ci/lint_scopes.toml",include_bytes!("configured/tools/ci/lint_scopes.toml").as_slice()));}
  },
  "order"|"bom"|"invalid_manifest"=>{
   rows.extend([("code/a_order.dm",include_bytes!("order/code/a_order.dm").as_slice()),("code/z_order.dm",include_bytes!("order/code/z_order.dm").as_slice())]);
   rows.push(("deepquarry.dme",match case{"bom"=>include_bytes!("bom/deepquarry.dme").as_slice(),"invalid_manifest"=>b"#include \"code/z_order.dm\"\n#include \"code/a_order.dm\"\n// invalid strict UTF8: \xff\n",_=>include_bytes!("order/deepquarry.dme").as_slice()}));
  },_=>return None,
 }Some(rows)
}
