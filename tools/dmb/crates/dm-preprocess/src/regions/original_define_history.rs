//! Actual old define-history DATA, not a second expansion environment. Entries
//! alias the SAME typed immutable products removed/finalized from Binding.
use super::environment::{OriginalDefinitionProduct,MacroEnvironment};
use crate::macro_expansion::{OriginalPagedMacroRows as Rows,OriginalMacroText as Text,OriginalMacroOrigin as Origin};
use dm_syntax::{SettingAdmission,SettingRootLease};use std::{io,sync::Arc};
#[derive(Clone,Copy,Debug)]pub(super) enum OriginalDefineHistoryEnd{Undef(Origin),Final{ordinal:usize}}
struct Entry{name:Text,product:Arc<OriginalDefinitionProduct>,end:OriginalDefineHistoryEnd}

#[derive(Clone, Copy, Eq, PartialEq)]
pub(super) enum HistoryPurpose { Full, Diagnostic }

struct UndefMark {
    name: Text,
    authored: Option<Origin>,
    ended: Origin,
}

enum Storage {
    Full(Rows<Entry>),
    Diagnostic { removed: Rows<UndefMark>, final_epochs: usize, final_authored: usize },
}
// Removed epochs are appended in encounter order. Current stack epochs
// follow in their existing visit order and keep their terminal ordinals.
// Funding one page at a time avoids an EOF-sized overlapping Vec growth.
pub(super) struct OriginalDefineHistory{storage:Storage,finalized:bool,failed:bool,domain:SettingRootLease}
#[cfg(test)]
pub(super) struct OriginalDefineHistoryEntry<'a>{pub(super) name:&'a str,pub(super) defined_at:Option<Origin>,pub(super) end:OriginalDefineHistoryEnd,pub(super) product:&'a OriginalDefinitionProduct}
impl OriginalDefineHistory{
 #[cfg(test)]
 pub(super) fn new(a:&SettingAdmission<'_>)->io::Result<Self>{
    Self::with_purpose(HistoryPurpose::Full, a)
 }
 pub(super) fn with_purpose(purpose:HistoryPurpose,a:&SettingAdmission<'_>)->io::Result<Self>{
    let storage = match purpose {
        HistoryPurpose::Full => Storage::Full(Rows::new(a)?),
        HistoryPurpose::Diagnostic => Storage::Diagnostic {
            removed: Rows::new(a)?, final_epochs: 0, final_authored: 0,
        },
    };
    Ok(Self{storage,finalized:false,failed:false,domain:a.reserve(0).map_err(|e|a.take_operational_error().unwrap_or(e))?})
 }
 pub(super) fn is_full(&self)->bool { matches!(&self.storage, Storage::Full(_)) }
 fn check(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{if self.failed||self.finalized{return Err(io::ErrorKind::InvalidInput.into())}let result=if !a.matches_lease_domain(&self.domain){Err(io::ErrorKind::InvalidInput.into())}else{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))};if result.is_err(){self.failed=true}result}
 fn owned_name(name:&str,a:&SettingAdmission<'_>)->io::Result<Text>{
    let mut text=Text::new(a)?;
    text.push_str(name,a)?;
    Ok(text)
 }
 pub(super) fn record_undef_using(&mut self,name:&str,removed:Arc<OriginalDefinitionProduct>,completed:Origin,a:&SettingAdmission<'_>)->io::Result<()>{
    self.check(a)?;
    let result=(||match &mut self.storage {
        Storage::Full(rows) => rows.push(Entry {
            name:Self::owned_name(name,a)?, product:removed, end:OriginalDefineHistoryEnd::Undef(completed),
        },a),
        Storage::Diagnostic{removed:rows,..} => {
            let authored=removed.definition_name().map(|token|token.origin());
            // Every already-emitted trace owns its independent author and
            // location; no full removed replacement/doc payload is needed.
            drop(removed);
            rows.push(UndefMark{name:Self::owned_name(name,a)?,authored,ended:completed},a)
        }
    })();
    if result.is_err(){self.failed=true}
    result
 }
 /// Full history keeps exact live epoch products and terminal ordinals.
 /// Restricted diagnostics instead validate the same live epoch visitation
 /// and keep counts. Neither form supplies primary delivery/physical EOF.
 pub(super) fn capture_current_using(&mut self,environment:&MacroEnvironment,a:&SettingAdmission<'_>)->io::Result<()>{
    self.check(a)?;
    let mut ordinal=0usize;
    let result=match &mut self.storage {
        Storage::Full(rows) => environment.visit_original_stack_owners_using(a,|name,product|{
            ordinal=ordinal.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
            rows.push(Entry{name:Self::owned_name(name,a)?,product:Arc::clone(product),end:OriginalDefineHistoryEnd::Final{ordinal}},a)
        }),
        Storage::Diagnostic{final_epochs,final_authored,..} => environment.visit_original_stack_owners_using(a,|_,product|{
            *final_epochs=final_epochs.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
            if product.definition_name().is_some(){
                *final_authored=final_authored.checked_add(1).ok_or(io::ErrorKind::OutOfMemory)?;
            }
            Ok(())
        }),
    };
    if result.is_err(){self.failed=true}else{self.finalized=true}
    result
 }
 pub(super) fn is_finalized_by(&self,a:&SettingAdmission<'_>)->bool{!self.failed&&self.finalized&&a.matches_lease_domain(&self.domain)}
 #[cfg(debug_assertions)]
 pub(super) fn trace_original_products(&self)->(usize,usize,usize,super::environment::OriginalProductCensus){
  let mut name_capacity=0usize;
  let mut products=super::environment::OriginalProductCensus::default();
  let mut count=0;
  let capacity=match &self.storage {
    Storage::Full(rows)=>{
        for row in rows.iter(){
            count+=1;
            row.name.visit_allocation(|_,n|name_capacity=name_capacity.saturating_add(n));
            products.note(&row.product);
        }
        rows.trace_allocation_bytes()
    }
    Storage::Diagnostic{removed,..}=>{
        for row in removed.iter(){
            count+=1;
            row.name.visit_allocation(|_,n|name_capacity=name_capacity.saturating_add(n));
        }
        removed.trace_allocation_bytes()
    }
  };
  (count,capacity,name_capacity,products)
 }
 #[cfg(test)]
 pub(super) fn entries(&self)->impl Iterator<Item=OriginalDefineHistoryEntry<'_>>{
    let Storage::Full(rows)=&self.storage else{panic!("diagnostic history cannot issue full epoch products")};
    rows.iter().map(|row|OriginalDefineHistoryEntry{name:row.name.as_str(),defined_at:row.product.definition_name().map(|token|token.origin()),end:row.end,product:&row.product})
 }
 #[cfg(test)]
 pub(super) fn diagnostic_marks(&self)->(impl Iterator<Item=(&str,Option<Origin>,Origin)>,usize,usize){
    let Storage::Diagnostic{removed,final_epochs,final_authored}=&self.storage else{panic!("full history is not compact diagnostic storage")};
    (removed.iter().map(|row|(row.name.as_str(),row.authored,row.ended)),*final_epochs,*final_authored)
 }
}
