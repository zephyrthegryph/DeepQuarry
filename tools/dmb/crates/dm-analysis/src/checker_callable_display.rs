//! Borrowed spelling projection shared by the original effect and directive judges.
use dm_ir::ProcedureIdentity;
use dm_tree::{SemanticTree,MemberKind};
pub(crate) struct CallableDisplay<'a>{owner:&'a str,name:&'a str,occurrence:usize,count:usize}
impl std::fmt::Display for CallableDisplay<'_>{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{let owner=if self.owner=="/"{""}else{self.owner};if self.count>1{write!(f,"{owner}/proc/{}[{}/{}]",self.name,self.occurrence,self.count)}else{write!(f,"{owner}/proc/{}",self.name)}}}
pub(crate) fn original<'a,E:From<String>+From<&'static str>>(tree:&'a SemanticTree,id:ProcedureIdentity,mut reserve_scan:impl FnMut(usize)->Result<(),E>,mut checkpoint:impl FnMut()->Result<(),E>)->Result<CallableDisplay<'a>,E>{
 let owner=tree.symbols().text(id.owner).ok_or("purity owner spelling absent")?;let name=tree.symbols().text(id.name).ok_or("purity callable spelling absent")?;
 let owner_id=tree.lookup_type(id.owner).ok_or("effect display owner index absent")?;let roster=&tree.type_node(owner_id).ok_or("effect display owner absent")?.members;
 reserve_scan(roster.len())?;let mut count=0usize;
 for member in roster.iter(){checkpoint()?;let member=tree.member(*member).ok_or("effect display indexed member absent")?;if member.owner!=owner_id{return Err("effect display original owner roster mismatch".into())}if member.name==id.name&&matches!(member.kind,MemberKind::Proc|MemberKind::Verb){count+=1;}}
 Ok(CallableDisplay{owner,name,occurrence:id.occurrence as usize,count})
}
