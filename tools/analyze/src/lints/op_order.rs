//! Compatibility registration delegates the SAME unique op composition judge.
use crate::lint::{Cx,Lint,Meta,Registry,Sink};
use crate::{op_order_policy as policy,tree::SourceFile,sem::decls::Decls};
struct OpOrder;
impl Lint for OpOrder {
 fn meta(&self)->&Meta{&policy::META}
 fn scan_file(&self,_:&Cx,f:&SourceFile,out:&mut Sink){policy::relative_priority(f,|number|{if !out.allowed(f,number,"op_order"){out.site_keyed("relative_priority",&f.rel,number,f.line(number).trim().to_string(),"relative_priority");}})}
 fn scan_tree(&self,cx:&Cx,out:&mut Sink){
  let decls=Decls::get(cx.tree);let files=cx.all_files().into_iter().map(policy::file_facts).collect::<Vec<_>>();
  let markers=decls.markers.iter().map(|m|policy::Marker{name:&m.name,relative:&m.rel,line:m.line,args:&m.args}).collect::<Vec<_>>();
  let model=policy::Model::from_owned_facts(files,&markers);
  for m in markers.iter().filter(|m|m.name=="CAPABILITIES"){
   if cx.exempt(m.relative)||m.relative.starts_with("code/engine/_generated/"){continue}
   for clash in model.judge(m.args){
    if let Some(f)=cx.tree.get(m.relative){if out.allowed(f,m.line as usize,"op_order"){continue}}
    out.site_keyed("unordered_clash",m.relative,m.line as usize,clash.message,clash.key);
   }
  }
 }
}
pub fn register(reg:&mut Registry){reg.add(OpOrder)}
