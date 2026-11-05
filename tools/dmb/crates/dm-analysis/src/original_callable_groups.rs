//! Actual Original type/own-name insertion order and existing group chronology.
//! Ephemeral name dedup DATA only; no copied model, lookup cache or body issuer.
use crate::{policy_body_demand::WorkspaceWork,policy_inputs::PolicyInputs};
use dm_tree::MemberKind;use std::collections::HashSet;
pub fn visit_source_values_using<W:WorkspaceWork>(inputs:&PolicyInputs,work:&mut W,emit:&mut impl FnMut(usize,bool,&mut W)->Result<(),W::Error>)->Result<(),W::Error>{
 visit_archive_source_values_using(inputs.archive(),work,emit)
}
/// Same unique name/value chronology over an explicitly partial-purpose owner.
/// This overload cannot lend a full PolicyInputs or change preparation purpose.
pub fn visit_handlers_source_values_using<W:WorkspaceWork>(inputs:&crate::policy_inputs::HandlersStructuralInputs,work:&mut W,emit:&mut impl FnMut(usize,bool,&mut W)->Result<(),W::Error>)->Result<(),W::Error>{visit_archive_source_values_using(inputs.archive(),work,emit)}
fn visit_archive_source_values_using<W:WorkspaceWork>(archive:&dm_tree::frontend::BodyArchive,work:&mut W,emit:&mut impl FnMut(usize,bool,&mut W)->Result<(),W::Error>)->Result<(),W::Error>{
 work.checkpoint()?;let tree=archive.tree();let profile=tree.checker_builtin_profile().ok_or("original own-name roster requires actual Original profile")?;let _proof=tree.validated_checker_profile(profile).map_err(|_|"original own-name roster profile is foreign")?;let catalog=dm_tree::checker_builtins::pinned_catalog().map_err(|_|"original fixed name roster is unavailable")?;if catalog.profile!=profile{return Err("original fixed name roster differs from source profile".into())}
 for ty in tree.types(){
  work.checkpoint()?;let owner=tree.symbols().text(ty.path).ok_or("original name-roster owner spelling absent")?;let actual_owner=tree.lookup_type(ty.path).ok_or("original name-roster owner identity absent")?;let mut source_names=0usize;for &member in ty.members.iter(){work.checkpoint()?;let node=tree.member(member).ok_or("original name-roster source member absent")?;if node.owner==actual_owner&&matches!(node.kind,MemberKind::Proc|MemberKind::Verb)&&archive.member_location(member).is_some(){source_names+=1;}}if source_names==0{continue}let mut seen=HashSet::new();
  let mut next=|symbol:dm_ir::SymbolId,work:&mut W|->Result<(),W::Error>{
   work.checkpoint()?;if seen.contains(&symbol){return Ok(())}if W::CHECKED&&seen.len()==seen.capacity(){let bound=seen.capacity().checked_mul(8).map(|n|n.max(32)).ok_or_else(||work.overflow())?;let bytes=bound.checked_mul(std::mem::size_of::<dm_ir::SymbolId>()+2*std::mem::size_of::<usize>()).and_then(|n|n.checked_add(256)).ok_or_else(||work.overflow())?;work.temporary(bytes)?;seen.try_reserve(1).map_err(|_|work.allocation_failed())?;if seen.capacity()>bound{return Err(work.allocation_failed())}}
   seen.insert(symbol);let mut own=false;for &member in ty.members.iter(){work.checkpoint()?;let node=tree.member(member).ok_or("original own-name member absent")?;if node.owner==actual_owner&&node.name==symbol&&matches!(node.kind,MemberKind::Proc|MemberKind::Verb)&&archive.member_location(member).is_some(){own=true;break}}if !own{return Ok(())}let name=tree.symbols().text(symbol).or_else(||tree.checker_builtin_spelling(profile,symbol)).ok_or("original own-name spelling absent")?;
   crate::setter_publication_native::visit_archive_own_values_using(archive,owner,name,work,emit)?;Ok(())
  };
  // Existing pinned DSL registration happens before authored definitions. The
  // same catalog rows preserve first-name insertion; Group owns value order.
  for row in catalog.declarations.iter(){work.checkpoint()?;if row.owner==ty.path&&matches!(row.kind,MemberKind::Proc|MemberKind::Verb){next(row.name,work)?;}}
  for &member in ty.members.iter(){work.checkpoint()?;let node=tree.member(member).ok_or("original own-name source member absent")?;if node.owner==actual_owner&&matches!(node.kind,MemberKind::Proc|MemberKind::Verb){next(node.name,work)?;}}
 }
 work.checkpoint()
}
