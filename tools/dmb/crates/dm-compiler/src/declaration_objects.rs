//! Owner adapters over the shared typed ObjectWitness operation engine.
//! Unsupported declarations are explicit derivation steps, preserving side effects.
use std::{cell::RefCell,collections::HashMap,sync::Arc};
use super::declaration_operations;
use dm_syntax::Item;
use std::sync::atomic::{AtomicUsize,Ordering};
static REUSED:AtomicUsize=AtomicUsize::new(0);static DERIVED:AtomicUsize=AtomicUsize::new(0);
pub(super) fn stats()->(usize,usize) {(REUSED.load(Ordering::Relaxed),DERIVED.load(Ordering::Relaxed))}
struct OwnerObject {plans:HashMap<String,Arc<declaration_operations::Plan>>}
thread_local! {static ACTIVE:RefCell<Option<Arc<OwnerObject>>>=const {RefCell::new(None)};}
pub(super) struct OwnerScope(Option<Arc<OwnerObject>>);
impl Drop for OwnerScope {fn drop(&mut self) {ACTIVE.with(|active|*active.borrow_mut()=self.0.take());}}
pub(super) fn activate(item:&Item)->OwnerScope {
 let plans=declaration_operations::owner_plans(item.header.trim(),item.children.iter().filter(|child|declaration_operations::eligible(&child.header)).map(|child|child.header.clone()));
 let object=Arc::new(OwnerObject {plans});OwnerScope(ACTIVE.with(|active|active.replace(Some(object))))
}
pub(super) fn current_plan(key:&str)->Option<Arc<declaration_operations::Plan>> {ACTIVE.with(|active|active.borrow().as_ref()?.plans.get(key).cloned())}

pub(super) fn replay_members(item:&Item,plan:&super::default_plans::OwnerDeclarationPlan,class:u32,image:&mut impl dm_output::assembly::AssemblyImage,strings:&mut crate::bootstrap::StringIndex,resources:&std::collections::HashMap<String,u32>,metadata:&mut crate::bootstrap::TypeMetadataState,pending:&mut Vec<crate::bootstrap::PendingDynamic>)->Result<bool,String> {
 let ready=ACTIVE.with(|active| {let active=active.borrow();let Some(active)=active.as_ref()else{return false;};
  item.children.iter().filter(|child|matches!(child.kind,dm_syntax::ItemKind::Var|dm_syntax::ItemKind::Unknown|dm_syntax::ItemKind::Statement)&&!child.header.trim().starts_with("parent_type")).all(|child|{
   let key=declaration_operations::key(item.header.trim(),&child.header);
   active.plans.get(&key).is_some_and(|plan|declaration_operations::closed_owner_plan(plan,resources))
  })
 });
 if !ready {DERIVED.fetch_add(1,Ordering::Relaxed);return Ok(false);}
 let is_const=|child:&Item|child.kind==dm_syntax::ItemKind::Var&&child.header.split('=').next().is_some_and(|header|header.split('/').any(|part|part.trim()=="const"));
 for index in &plan.const_indexes {let child=&item.children[*index];if !declaration_operations::replay(&child.header,class,image,strings,resources,Some(&mut *metadata),pending)? {return Err("closed owner constant recipe unexpectedly rejected".into());}}
 for child in &item.children {if is_const(child)||child.header.trim().starts_with("parent_type") {continue;}
  if matches!(child.kind,dm_syntax::ItemKind::Var|dm_syntax::ItemKind::Unknown|dm_syntax::ItemKind::Statement) {
   if !declaration_operations::replay(&child.header,class,image,strings,resources,Some(&mut *metadata),pending)? {return Err("closed owner member recipe unexpectedly rejected".into());}
  }
 }REUSED.fetch_add(1,Ordering::Relaxed);Ok(true)
}
