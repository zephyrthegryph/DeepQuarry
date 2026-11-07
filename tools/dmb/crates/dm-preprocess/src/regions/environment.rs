//! Structurally shared exact expansion environments. Each binding owns its
//! replacement and definition origin once; snapshots retain only persistent roots.
use super::{DefinitionOrigin, macro_trace_view::OriginalMacroAuthor, original_define_history::HistoryPurpose};
use crate::{Macro, MacroLookup};
use crate::macro_expansion::{OriginalMacroDefinition,OriginalMacroRows,OriginalMacroText,OriginalMacroValue,OriginalMacroTextValue,OriginalMacroDoc};
use crate::macro_expansion::{OriginalMacroToken,OriginalMacroOrigin};
use dm_syntax::SettingAdmission;
use std::io;
use std::sync::Arc;

#[derive(Clone, Debug)]
pub(super) struct Binding {
    definition: Arc<Macro>,
    original:Option<Arc<OriginalDefinitionProduct>>,
    origin: Option<DefinitionOrigin>,
    previous: Option<Arc<Binding>>,
    previous_digest:u128,
}

// Original macro stacks can be arbitrarily deep. Release uniquely owned links
// iteratively; shared persistent snapshots retain their actual old chain.
impl Drop for Binding { fn drop(&mut self) {
    let mut previous=self.previous.take();
    while let Some(owner)=previous { match Arc::try_unwrap(owner) {
        Ok(mut binding)=>previous=binding.previous.take(),Err(_)=>break,
    }}
}}
// The diagnostic structural diff observes allocation ownership, not macro meaning.
// Fresh equal-content bindings must be visited because they retain distinct heaps.
impl PartialEq for Binding {
    fn eq(&self, other: &Self) -> bool {
        std::ptr::eq(self, other)
    }
}
impl Eq for Binding {}
impl Binding {
    fn definition_origin(&self) -> Option<&DefinitionOrigin> {
        self.original.as_deref().and_then(OriginalDefinitionProduct::projected_definition)
            .and_then(|definition| definition.origin()).or(self.origin.as_ref())
    }
}


/// Immutable actual definition-time parser DATA supplied by SAME native source
/// owner. Not a source/EOF/model receipt. The only dictionary remains bindings.
/// Arc/im global allocator geometry remains existing opaque native boundary;
/// all product buffers and fixed coordination are admitted before allocation.
pub(super) struct OriginalDefinitionName(DefinitionNameStorage);

enum DefinitionNameStorage {
    Physical(PhysicalDefinitionName),
    // Exactly one separately funded row. Keep the actual wide origin,
    // frame and spelling when they cannot be reconstructed losslessly.
    Wide(Vec<WideDefinitionName>),
}

struct PhysicalDefinitionName {
    start: u32,
    end: u32,
    line: u32,
    column: u32,
    occurrence: u32,
    frame: crate::regions::OriginalLexicalFrameIdentity,
}

struct WideDefinitionName {
    origin: OriginalMacroOrigin,
    spelling: OriginalMacroTextValue<'static>,
    lexical_frame: Option<crate::regions::OriginalLexicalFrameIdentity>,
}

impl OriginalDefinitionName {
    fn capture(
        name: WideDefinitionName,
        lexical_span: Option<dm_syntax::Span>,
        credit: &mut dm_syntax::SettingRootLease,
        a: &SettingAdmission<'_>,
    ) -> io::Result<Self> {
        let origin = name.origin;
        let physical = || {
            let frame = name.lexical_frame.as_ref()?;
            let OriginalMacroTextValue::Source(spelling) = &name.spelling else { return None };
            if origin.invocation || lexical_span != Some(origin.physical)
                || !frame.acquisition().source_text()
                    .matches_retained_subview(origin.physical.range(), spelling)
            {
                return None;
            }
            Some(PhysicalDefinitionName {
                start: u32::try_from(origin.physical.start).ok()?,
                end: u32::try_from(origin.physical.end).ok()?,
                line: u32::try_from(origin.line).ok()?,
                column: u32::try_from(origin.byte_column?).ok()?,
                occurrence: u32::try_from(origin.occurrence).ok()?,
                frame: frame.clone(),
            })
        };
        if let Some(physical) = physical() {
            return Ok(Self(DefinitionNameStorage::Physical(physical)));
        }
        a.grow(credit, std::mem::size_of::<WideDefinitionName>())
            .map_err(|error| a.take_operational_error().unwrap_or(error))?;
        let mut row = crate::macro_expansion::empty_exact(1, a)?;
        row.push(name);
        Ok(Self(DefinitionNameStorage::Wide(row)))
    }

    pub(super) fn origin(&self) -> OriginalMacroOrigin {
        match &self.0 {
            DefinitionNameStorage::Physical(name) => OriginalMacroOrigin {
                physical: dm_syntax::Span::new(name.start as usize, name.end as usize),
                line: name.line as usize,
                byte_column: Some(name.column as usize),
                occurrence: name.occurrence as usize,
                invocation: false,
            },
            DefinitionNameStorage::Wide(row) => row[0].origin,
        }
    }

    pub(super) fn spelling(&self) -> &str {
        match &self.0 {
            DefinitionNameStorage::Physical(name) => name.frame.acquisition().source_text().as_str()
                .get(name.start as usize..name.end as usize)
                .expect("checked physical definition-name subview"),
            DefinitionNameStorage::Wide(row) => row[0].spelling.get(),
        }
    }

    pub(super) fn lexical_frame(&self) -> Option<&crate::regions::OriginalLexicalFrameIdentity> {
        match &self.0 {
            DefinitionNameStorage::Physical(name) => Some(&name.frame),
            DefinitionNameStorage::Wide(row) => row[0].lexical_frame.as_ref(),
        }
    }

    #[cfg(test)]
    pub(super) fn uses_physical_storage(&self) -> bool {
        matches!(&self.0, DefinitionNameStorage::Physical(_))
    }
}
#[path="original_replacement_roster.rs"]
mod replacement_roster;
struct RetainedDefinition{parameters:Option<Vec<OriginalMacroText>>,variadic:bool,replacement:replacement_roster::Replacement}
pub(super) struct OriginalDefinitionProduct{name:Option<OriginalDefinitionName>,projected:Option<Arc<OriginalMacroAuthor>>,definition:RetainedDefinition,docs:Vec<OriginalMacroDoc<'static>>,digest:u128,_credit:dm_syntax::SettingRootLease}

/// Sealed row buffers never outlive their product. Transfer actual allocation
/// ownership and credit together without copying rows, consolidating their
/// leases only at that ownership boundary.
fn retain_product_rows<T>(
    rows: OriginalMacroRows<T>, credit: &mut dm_syntax::SettingRootLease,
    a: &SettingAdmission<'_>,
) -> io::Result<Vec<T>> {
    let (rows, mut prior) = rows.into_parts();
    if let Err(error) = a.absorb(credit, &mut prior) {
        drop(rows);
        return Err(error);
    }
    Ok(rows)
}
fn visit_product_rows<T>(rows: &Vec<T>, mut visit: impl FnMut(usize,usize)) {
    let bytes = rows.capacity() * std::mem::size_of::<T>();
    if bytes != 0 { visit(rows.as_ptr() as usize, bytes); }
}
// Failure telemetry only. Direct buffers are exclusive to the product;
// SourceText and lexical frames are counted as references, never charged here.
#[cfg(debug_assertions)]
#[derive(Debug,Default)]
pub(super) struct OriginalProductCensus {
 exclusive_products:usize,
 exclusive_wrapper_reserved:usize,
 exclusive_replacement_capacity:usize,
 exclusive_parameter_row_capacity:usize,
 exclusive_doc_row_capacity:usize,
 exclusive_wide_name_row_capacity:usize,
 exclusive_owned_text_capacity:usize,
 physical_name_references:usize,
 wide_name_references:usize,
 shared_product_references:usize,
 shared_direct_bytes_per_reference_upper:usize,
 source_text_references:usize,
 lexical_frame_references:usize,
}
#[cfg(debug_assertions)]
impl OriginalProductCensus {
 pub(super) fn note(&mut self,product:&Arc<OriginalDefinitionProduct>){
  fn add(total:&mut usize,n:usize){*total=total.saturating_add(n)}
  fn text(value:&OriginalMacroTextValue<'_>,bytes:&mut usize,source_refs:&mut usize){
   match value {
    OriginalMacroTextValue::Owned(text)=>text.visit_allocation(|_,n|add(bytes,n)),
    OriginalMacroTextValue::Source(_)=>add(source_refs,1),
    OriginalMacroTextValue::Borrowed(_)=>{}
   }
  }
  fn token(token:&OriginalMacroToken<'_>,bytes:&mut usize,source_refs:&mut usize,frame_refs:&mut usize){
   if let Some(value)=original_value_text(&token.value){text(value,bytes,source_refs)}
   if let Some(raw)=&token.raw_spelling{text(raw,bytes,source_refs)}
   add(frame_refs,usize::from(token.lexical_frame.is_some()));
  }
  let mut replacement=0;
  let mut params=0;
  let mut docs=0;
  let mut wide_name=0;
  let mut owned_text=0;
  product.definition.replacement.visit_allocation(|_,n|replacement=n);
  for value in product.definition.replacement.wide(){token(value,&mut owned_text,&mut self.source_text_references,&mut self.lexical_frame_references);}
  if let Some(parameters)=&product.definition.parameters{
   visit_product_rows(parameters,|_,n|params=n);
   for parameter in parameters.as_slice(){parameter.visit_allocation(|_,n|add(&mut owned_text,n));}
  }
  if let Some(name)=&product.name{
   match &name.0 {
    DefinitionNameStorage::Physical(_) => add(&mut self.physical_name_references,1),
    DefinitionNameStorage::Wide(row) => {
     add(&mut self.wide_name_references,1);
     visit_product_rows(row,|_,n|wide_name=n);
     text(&row[0].spelling,&mut owned_text,&mut self.source_text_references);
    }
   }
   add(&mut self.lexical_frame_references,usize::from(name.lexical_frame().is_some()));
  }
  visit_product_rows(&product.docs,|_,n|docs=n);
  for doc in product.docs.as_slice(){
   text(&doc.text,&mut owned_text,&mut self.source_text_references);
   add(&mut self.lexical_frame_references,usize::from(doc.lexical_frame.is_some()));
  }
  let wrapper=OriginalDefinitionProduct::wrapper_bytes();
  if Arc::strong_count(product)==1{
   add(&mut self.exclusive_products,1);
   add(&mut self.exclusive_wrapper_reserved,wrapper);
   add(&mut self.exclusive_replacement_capacity,replacement);
   add(&mut self.exclusive_parameter_row_capacity,params);
   add(&mut self.exclusive_doc_row_capacity,docs);
   add(&mut self.exclusive_wide_name_row_capacity,wide_name);
   add(&mut self.exclusive_owned_text_capacity,owned_text);
  }else{
   add(&mut self.shared_product_references,1);
   for bytes in [wrapper,replacement,params,docs,wide_name,owned_text]{add(&mut self.shared_direct_bytes_per_reference_upper,bytes);}
  }
 }
}
impl std::fmt::Debug for OriginalDefinitionProduct{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OriginalDefinitionProduct").field("parameters",&self.definition.parameters.as_ref().map(|p|p.len())).field("tokens",&self.definition.replacement.len()).finish_non_exhaustive()}}
fn original_poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
fn original_hash_text(hash:&mut xxhash_rust::xxh3::Xxh3,text:&str,a:&SettingAdmission<'_>)->io::Result<()>{hash.update(&(text.len()as u64).to_le_bytes());for chunk in text.as_bytes().chunks(1024){original_poll(a)?;hash.update(chunk);}Ok(())}
fn original_value_text<'a,'s>(value:&'a OriginalMacroValue<'s>)->Option<&'a OriginalMacroTextValue<'s>>{match value{OriginalMacroValue::DocComment{text,..}=>Some(text),OriginalMacroValue::Ident{spelling,..}|OriginalMacroValue::String(spelling)|OriginalMacroValue::Resource(spelling)|OriginalMacroValue::InterpBegin(spelling)|OriginalMacroValue::InterpPart(spelling)|OriginalMacroValue::InterpEnd(spelling)=>Some(spelling),_=>None}}
impl OriginalDefinitionProduct{
 fn wrapper_bytes()->usize{
  original_allocation::arc_bytes(std::alloc::Layout::new::<Self>()).expect("known Original product Arc layout")
 }
 /// DATA constructor only. Caller MUST supply actual definition-time lexical
 /// product, never a later String relex or private reconstructed dictionary.
 pub(super) fn from_actual_product_using(definition:OriginalMacroDefinition<'static>,a:&SettingAdmission<'_>)->io::Result<Arc<Self>>{Self::from_actual_product_with_docs_using(definition,OriginalMacroRows::new(a)?,a)}
 /// SAME Binding retains actual drained/following definition docs, in order.
 /// Invocations borrow this product before raw argument demand can change state.
 pub(super) fn from_actual_product_with_docs_using(definition:OriginalMacroDefinition<'static>,docs:OriginalMacroRows<OriginalMacroDoc<'static>>,a:&SettingAdmission<'_>)->io::Result<Arc<Self>>{
  Self::from_product_with_name_using(None,None,definition,docs,HistoryPurpose::Full,a)
 }
 /// Keep the SAME issued #define spelling, point and lexical-frame owner.
 /// Physical identifier whitespace and replacement-token-only fields have
 /// no definition-name consumer. Bootstrap still has no physical name.
 pub(super) fn from_named_actual_product_using(name:OriginalMacroToken<'static>,definition:OriginalMacroDefinition<'static>,docs:OriginalMacroRows<OriginalMacroDoc<'static>>,origin:Option<DefinitionOrigin>,purpose:HistoryPurpose,a:&SettingAdmission<'_>)->io::Result<Arc<Self>>{
  original_poll(a)?;if !matches!(name.value,OriginalMacroValue::Ident{..})||name.origin.byte_column.is_none()||name.origin.line==0{return Err(io::Error::new(io::ErrorKind::Unsupported,"actual Original definition-name point is unissued"))}
  if name.lexical_frame.as_ref().is_some_and(|frame|!frame.admitted_by(a)){return Err(io::ErrorKind::InvalidInput.into())}
  let OriginalMacroValue::Ident{spelling,..}=name.value else{unreachable!("checked actual definition name")};
  let pending=WideDefinitionName{origin:name.origin,spelling,lexical_frame:name.lexical_frame};
  Self::from_product_with_name_using(Some((pending,name.lexical_span)),origin,definition,docs,purpose,a)
 }
 fn from_product_with_name_using(name:Option<(WideDefinitionName,Option<dm_syntax::Span>)>,origin:Option<DefinitionOrigin>,definition:OriginalMacroDefinition<'static>,docs:OriginalMacroRows<OriginalMacroDoc<'static>>,purpose:HistoryPurpose,a:&SettingAdmission<'_>)->io::Result<Arc<Self>>{
  original_poll(a)?;let mut credit=a.reserve(Self::wrapper_bytes()).map_err(|e|a.take_operational_error().unwrap_or(e))?;
  let name=name.map(|(pending,span)|OriginalDefinitionName::capture(pending,span,&mut credit,a)).transpose()?;
  let mut hash=xxhash_rust::xxh3::Xxh3::new();hash.update(b"actual-original-definition-token-data-v1");hash.update(&[u8::from(definition.variadic)]);match &definition.parameters{None=>hash.update(&[0]),Some(params)=>{hash.update(&[1]);hash.update(&(params.len()as u64).to_le_bytes());for name in params.as_slice(){original_hash_text(&mut hash,name.as_str(),a)?;}}}
  hash.update(&(definition.replacement.len()as u64).to_le_bytes());for token in definition.replacement.as_slice(){original_poll(a)?;hash.update(&[u8::from(token.punctuation_close),token.string_mode as u8]);match &token.value{
   OriginalMacroValue::DocComment{kind,text}=>{let kind=match kind{dm_syntax::OriginalCommentKind::None=>0,dm_syntax::OriginalCommentKind::LineFollowing=>1,dm_syntax::OriginalCommentKind::LineEnclosing=>2,dm_syntax::OriginalCommentKind::BlockFollowing=>3,dm_syntax::OriginalCommentKind::BlockEnclosing=>4};hash.update(&[10,kind]);original_hash_text(&mut hash,text.get(),a)?;},
   OriginalMacroValue::Ident{spelling,whitespace}=>{hash.update(&[0,u8::from(*whitespace)]);original_hash_text(&mut hash,spelling.get(),a)?;},
   OriginalMacroValue::Int(n)=>{hash.update(&[1]);hash.update(&n.to_le_bytes());},OriginalMacroValue::Float(n)=>{hash.update(&[2]);hash.update(&n.to_bits().to_le_bytes());},
   OriginalMacroValue::String(text)=>{hash.update(&[3]);original_hash_text(&mut hash,text.get(),a)?;},OriginalMacroValue::Resource(text)=>{hash.update(&[4]);original_hash_text(&mut hash,text.get(),a)?;},
   OriginalMacroValue::InterpBegin(text)=>{hash.update(&[5]);original_hash_text(&mut hash,text.get(),a)?;},OriginalMacroValue::InterpPart(text)=>{hash.update(&[6]);original_hash_text(&mut hash,text.get(),a)?;},OriginalMacroValue::InterpEnd(text)=>{hash.update(&[7]);original_hash_text(&mut hash,text.get(),a)?;},OriginalMacroValue::Punct(text)=>{hash.update(&[8]);original_hash_text(&mut hash,text,a)?;},OriginalMacroValue::Eof=>hash.update(&[9]),
  }match token.raw_spelling(){None=>hash.update(&[0]),Some(text)=>{hash.update(&[1]);original_hash_text(&mut hash,text,a)?;}}match token.lexical_span{Some(span)=>{hash.update(&[1]);hash.update(&(span.start as u64).to_le_bytes());hash.update(&(span.end as u64).to_le_bytes());},None=>hash.update(&[0])};hash.update(&(token.origin.physical.start as u64).to_le_bytes());hash.update(&(token.origin.physical.end as u64).to_le_bytes());hash.update(&(token.origin.line as u64).to_le_bytes());hash.update(&(token.origin.occurrence as u64).to_le_bytes());hash.update(&[u8::from(token.origin.invocation)]);
  // Actual frame identity is authenticated by current owner BEFORE use; it is
  // never hashed as meaning or inferred from this semantic DATA digest.
  }
  hash.update(&(docs.len()as u64).to_le_bytes());for doc in docs.as_slice(){original_poll(a)?;let kind=match doc.kind{dm_syntax::OriginalCommentKind::None=>0,dm_syntax::OriginalCommentKind::LineFollowing=>1,dm_syntax::OriginalCommentKind::LineEnclosing=>2,dm_syntax::OriginalCommentKind::BlockFollowing=>3,dm_syntax::OriginalCommentKind::BlockEnclosing=>4};hash.update(&[kind]);original_hash_text(&mut hash,doc.text.get(),a)?;match doc.lexical_span{Some(span)=>{hash.update(&[1]);hash.update(&(span.start as u64).to_le_bytes());hash.update(&(span.end as u64).to_le_bytes());},None=>hash.update(&[0])};hash.update(&(doc.origin.physical.start as u64).to_le_bytes());hash.update(&(doc.origin.physical.end as u64).to_le_bytes());hash.update(&(doc.origin.line as u64).to_le_bytes());hash.update(&(doc.origin.occurrence as u64).to_le_bytes());hash.update(&[u8::from(doc.origin.invocation)]);}
  let digest=hash.digest128();original_poll(a)?;
  let OriginalMacroDefinition{parameters,variadic,replacement}=definition;
  let replacement=replacement_roster::Replacement::capture(replacement,name.as_ref(),&mut credit,a)?;
  let parameters=parameters.map(|rows|retain_product_rows(rows,&mut credit,a)).transpose()?;
  let before_docs=credit.bytes();
  let mut docs=retain_product_rows(docs,&mut credit,a)?;
  if purpose==HistoryPurpose::Diagnostic{
   // The exact ordered doc payload already contributed to the SAME digest.
   // Its physical contents cannot be requested through diagnostic history.
   // Drop the actual rows (and their child owners) before refunding the Vec.
   let doc_row_bytes=credit.bytes()-before_docs;
   drop(std::mem::take(&mut docs));
   if doc_row_bytes!=0 {
    a.shrink(&mut credit,doc_row_bytes).map_err(|error|a.take_operational_error().unwrap_or(error))?;
   }
  }
  let definition=RetainedDefinition{parameters,variadic,replacement};
  let projected=origin.map(|origin| {
   let issued_name=name.as_ref().ok_or(io::ErrorKind::InvalidData)?.spelling();
   OriginalMacroAuthor::new_using(issued_name,Some(origin),a)
  }).transpose()?;
  Ok(Arc::new(Self{name,projected,definition,docs,digest,_credit:credit}))
 }
 pub(super) fn definition_name(&self)->Option<&OriginalDefinitionName>{self.name.as_ref()}
 pub(super) fn projected_definition(&self)->Option<&Arc<OriginalMacroAuthor>>{self.projected.as_ref()}
 #[cfg(test)]
 pub(super) fn uses_compact_replacement(&self)->bool{self.definition.replacement.is_compact()}
 pub(super) fn docs(&self)->&[OriginalMacroDoc<'static>]{self.docs.as_slice()}
 pub(super) fn cloned_docs_using(&self,a:&SettingAdmission<'_>)->io::Result<OriginalMacroRows<OriginalMacroDoc<'static>>>{original_poll(a)?;if !a.matches_lease_domain(&self._credit){return Err(io::Error::new(io::ErrorKind::InvalidInput,"original definition docs have another resource host"))}let mut out=OriginalMacroRows::new(a)?;for doc in self.docs.as_slice(){out.push(doc.duplicate(a)?,a)?;}Ok(out)}
 pub(super) fn cloned_definition_using(&self,a:&SettingAdmission<'_>)->io::Result<OriginalMacroDefinition<'static>>{
  original_poll(a)?;if !a.matches_lease_domain(&self._credit){return Err(io::Error::new(io::ErrorKind::InvalidInput,"original definition product has another native resource host"))}
  let parameters=match &self.definition.parameters{None=>None,Some(params)=>{let mut out=OriginalMacroRows::new(a)?;for name in params.as_slice(){let mut text=OriginalMacroText::new(a)?;text.push_str(name.as_str(),a)?;out.push(text,a)?;}Some(out)}};
  let replacement=self.definition.replacement.duplicate_using(self.name.as_ref(),a)?;
  Ok(OriginalMacroDefinition{parameters,variadic:self.definition.variadic,replacement})
 }
 /// Resource-only inventory, addresses cannot prove source/frame authority.
 /// Source views retain SAME acquisition-backed allocation and are visited as
 /// views, never counted as newly owned text or reconstructed/reencoded bytes.
 pub(super) fn visit_owned_storage(&self,mut visit:impl FnMut(usize,usize)){
  if let Some(projected)=&self.projected{projected.visit_storage(|address,_,bytes|visit(address,bytes));}
  visit_product_rows(&self.docs,&mut visit);for doc in self.docs.as_slice(){if let OriginalMacroTextValue::Owned(text)=&doc.text{text.visit_allocation(&mut visit);}}
  if let Some(params)=&self.definition.parameters{visit_product_rows(params,&mut visit);for name in params.as_slice(){name.visit_allocation(&mut visit);}}
  if let Some(OriginalDefinitionName(DefinitionNameStorage::Wide(row)))=&self.name {
   visit_product_rows(row,&mut visit);
   if let OriginalMacroTextValue::Owned(text)=&row[0].spelling{text.visit_allocation(&mut visit);}
  }
  self.definition.replacement.visit_allocation(&mut visit);for token in self.definition.replacement.wide(){for text in [original_value_text(&token.value),token.raw_spelling.as_ref()].into_iter().flatten(){if let OriginalMacroTextValue::Owned(text)=text{text.visit_allocation(&mut visit);}}}
 }
 pub(super) fn visit_source_views(&self,mut visit:impl FnMut(&crate::SourceText)){
  for doc in self.docs.as_slice(){if let OriginalMacroTextValue::Source(text)=&doc.text{visit(text);}}
  // A physical name borrows bytes from its lexical frame, reported below.
  // Only the wide branch can actually retain an extra SourceText view.
  if let Some(OriginalDefinitionName(DefinitionNameStorage::Wide(row)))=&self.name {
   if let OriginalMacroTextValue::Source(text)=&row[0].spelling{visit(text);}
  }
  for token in self.definition.replacement.wide(){for text in [original_value_text(&token.value),token.raw_spelling.as_ref()].into_iter().flatten(){if let OriginalMacroTextValue::Source(text)=text{visit(text);}}}
 }
 pub(super) fn visit_lexical_frames(&self,mut visit:impl FnMut(&crate::regions::OriginalLexicalFrameIdentity)){
  for doc in self.docs.as_slice(){if let Some(frame)=&doc.lexical_frame{visit(frame);}}
  if let Some(frame)=self.name.as_ref().and_then(OriginalDefinitionName::lexical_frame){visit(frame);}
  for token in self.definition.replacement.wide(){if let Some(frame)=&token.lexical_frame{visit(frame);}}
 }
 fn matches_name(&self,name:&str,a:&SettingAdmission<'_>)->io::Result<bool>{original_poll(a)?;Ok(self.name.as_ref().is_none_or(|actual|actual.spelling()==name))}
 fn matches_definition(&self,definition:&Macro,a:&SettingAdmission<'_>)->io::Result<bool>{original_poll(a)?;if self.definition.variadic!=definition.variadic{return Ok(false)}Ok(match(&self.definition.parameters,&definition.parameters){(None,None)=>true,(Some(actual),Some(names))if actual.len()==names.len()=>{for(actual,name)in actual.as_slice().iter().zip(names){original_poll(a)?;if actual.as_str()!=name{return Ok(false)}}true},_=>false})}
}
impl MacroEnvironment{
 /// Actual one-time initial product issuance on SAME Binding map. The current
 /// final configuration table has already applied default/caller precedence.
 /// A nonphysical factory uses genuine SAME token/value kernels once per entry;
 /// there is no source-frame forgery, String lookup fallback, second dictionary,
 /// or extra shadow definition epoch. Native initialization remains unchanged.
 /// The owner funds existing Arc/im coordination (the same opaque boundary as
 /// ordinary insert). This method admits every new product/buffer via a.
 pub(super) fn install_original_initial_using(&mut self,environment:crate::InitialEnvironment,final_macros:&std::collections::BTreeMap<String,Macro>,caller_defines:&std::collections::BTreeMap<String,String>,a:&SettingAdmission<'_>,factory:&mut dyn FnMut(crate::initial_environment::OriginalInitialDefinition<'_>,&SettingAdmission<'_>)->io::Result<OriginalMacroDefinition<'static>>)->io::Result<()>{
  original_poll(a)?;if !self.bindings.is_empty(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original initial product issuance requires the actual empty environment"))}
  let mut next=Self::default();
  crate::initial_environment::visit_original_bootstrap_using(environment,final_macros,caller_defines,a,&mut|input|{
   let name=input.name();let metadata=input.metadata();let definition=factory(input,a)?;
   for token in definition.replacement.as_slice(){original_poll(a)?;if token.lexical_frame.is_some()||token.lexical_span.is_some()||token.origin.invocation{return Err(io::Error::new(io::ErrorKind::InvalidInput,"nonphysical initial definition contains a fabricated physical lexical event or invocation"))}}
   let product=OriginalDefinitionProduct::from_actual_product_using(definition,a)?;
   next.insert_original_stacked_using(name,metadata.clone(),None,product,a)
  })?;
  original_poll(a)?;*self=next;Ok(())
 }
 /// Original token data is installed atomically on SAME binding/map epoch as
 /// ordinary metadata. Native insert/stack paths stay byte-equivalent without
 /// an Original product. Caller funds existing persistent-map coordination.
 /// SAME pinned DefineMap stack: source define pushes, undef pops one epoch.
 pub(super) fn insert_original_stacked_using(&mut self,name:&str,definition:Macro,origin:Option<DefinitionOrigin>,product:Arc<OriginalDefinitionProduct>,a:&SettingAdmission<'_>)->io::Result<()>{
  self.insert_original_stacked_before_commit_using(name,definition,origin,product,a,||Ok(()))
 }
 pub(super) fn insert_original_stacked_before_commit_using(
  &mut self,name:&str,definition:Macro,origin:Option<DefinitionOrigin>,product:Arc<OriginalDefinitionProduct>,
  a:&SettingAdmission<'_>,before_commit:impl FnOnce()->io::Result<()>,
 )->io::Result<()>{
  original_poll(a)?;if !a.matches_lease_domain(&product._credit)||!product.matches_name(name,a)?||!product.matches_definition(&definition,a)?{return Err(io::Error::new(io::ErrorKind::InvalidInput,"actual Original product/metadata/resource host differs"))}
  let previous=self.bindings.get(name).cloned();let previous_digest=previous.as_ref().map_or(0,|old|binding_digest(name,old));let binding=Arc::new(Binding{definition:Arc::new(definition),original:Some(product),origin,previous,previous_digest});let next=binding_digest(name,&binding);original_poll(a)?;
  before_commit()?;
  self.bindings.insert(Arc::from(name),binding);self.fingerprint^=previous_digest;self.fingerprint^=next;Ok(())
 }
 /// Loan the SAME actual Binding product for retained history. Arc cloning
 /// allocates no payload and is never a second macro lookup dictionary.
 pub(super) fn original_current_owner_using(&self,name:&str,a:&SettingAdmission<'_>)->io::Result<Option<Arc<OriginalDefinitionProduct>>>{original_poll(a)?;match self.bindings.get(name){None=>Ok(None),Some(binding)=>{let product=binding.original.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"current binding has no actual Original product"))?;if !a.matches_lease_domain(&product._credit){return Err(io::ErrorKind::InvalidInput.into())}Ok(Some(Arc::clone(product)))}}}
 pub(super) fn visit_original_stack_owners_using(&self,a:&SettingAdmission<'_>,mut visit:impl FnMut(&str,&Arc<OriginalDefinitionProduct>)->io::Result<()>)->io::Result<()>{for(name,binding)in &self.bindings{let mut current=Some(binding);while let Some(row)=current{original_poll(a)?;let product=row.original.as_ref().ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"stack binding has no actual Original product"))?;if !a.matches_lease_domain(&product._credit){return Err(io::ErrorKind::InvalidInput.into())}visit(name,product)?;current=row.previous.as_ref();}}Ok(())}
 #[cfg(debug_assertions)]
 pub(super) fn trace_original_products(&self)->OriginalProductCensus{
  let mut census=OriginalProductCensus::default();
  for(_,binding)in &self.bindings{
   let mut current=Some(binding);
   while let Some(binding)=current{
    if let Some(product)=&binding.original{census.note(product);}
    current=binding.previous.as_ref();
   }
  }
  census
 }
 pub(super) fn actual_original_product(&self,name:&str)->io::Result<Option<&OriginalDefinitionProduct>>{match self.bindings.get(name){None=>Ok(None),Some(binding)=>binding.original.as_deref().map(Some).ok_or_else(||io::Error::new(io::ErrorKind::Unsupported,"actual current macro binding has no issued Original definition tokens"))}}
 pub(super) fn visit_original_products_while(&self,mut visit:impl FnMut(&Arc<str>,usize,usize,&OriginalDefinitionProduct)->bool){for(name,binding)in &self.bindings{let mut current=Some(binding);while let Some(binding)=current{if let Some(product)=&binding.original{let fixed=OriginalDefinitionProduct::wrapper_bytes();if !visit(name,Arc::as_ptr(product)as usize,fixed,product){break}}current=binding.previous.as_ref();}}}
}

#[derive(Clone, Debug, Default)]
pub struct MacroEnvironment {
    bindings: im::OrdMap<Arc<str>, Arc<Binding>>,
    /// Order independent digest of every binding (name, definition, origin), kept up to date by
    /// `insert` and `remove`: two environments with equal length and fingerprint hold the same
    /// bindings, which lets a planner prove an incoming state unchanged without comparing maps.
    fingerprint: u128,
}
/// Digest of one binding: its name, the whole definition and the definition site.
fn binding_digest(name: &str, binding: &Binding) -> u128 {
    use xxhash_rust::xxh3::Xxh3;
    let mut hash = Xxh3::new();
    hash.update(&(name.len() as u64).to_le_bytes());
    hash.update(name.as_bytes());
    let definition = &*binding.definition;
    match &definition.parameters {
        None => hash.update(&[0]),
        Some(parameters) => {
            hash.update(&[1]);
            hash.update(&(parameters.len() as u64).to_le_bytes());
            for parameter in parameters {
                hash.update(&(parameter.len() as u64).to_le_bytes());
                hash.update(parameter.as_bytes());
            }
        }
    }
    hash.update(&[u8::from(definition.variadic)]);
    hash.update(&(definition.replacement.len() as u64).to_le_bytes());
    hash.update(definition.replacement.as_bytes());
    match binding.definition_origin() {
        None => hash.update(&[0]),
        Some(origin) => {
            hash.update(&[1]);
            let path = origin.path.as_os_str().as_encoded_bytes();
            hash.update(&(path.len() as u64).to_le_bytes());
            hash.update(path);
            hash.update(&(origin.source_span.start as u64).to_le_bytes());
            hash.update(&(origin.source_span.end as u64).to_le_bytes());
            hash.update(&(origin.source_line as u64).to_le_bytes());
        }
    }
    if let Some(original)=&binding.original{hash.update(b"original-definition-token-product-v1");hash.update(&original.digest.to_le_bytes());}
    if binding.previous.is_some(){hash.update(b"original-definition-stack-v1");hash.update(&binding.previous_digest.to_le_bytes());}
    hash.digest128()
}
/// The bindings in which one environment differs from another (`MacroEnvironment::delta_from`): each name with the
/// binding it has (`None`: undefined), sorted by name. Applied to the other environment it gives the first.
#[derive(Clone, Debug, Default)]
pub(super) struct EnvDelta(Vec<(Arc<str>, Option<Arc<Binding>>)>);
impl EnvDelta {
    pub(super) fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
    pub(super) fn len(&self) -> usize {
        self.0.len()
    }
    pub(super) fn names(&self) -> Arc<[Arc<str>]> {
        self.0.iter().map(|(name, _)| Arc::clone(name)).collect()
    }
    pub(super) fn contains(&self, name: &str) -> bool {
        self.0.binary_search_by(|(entry, _)| entry.as_ref().cmp(name)).is_ok()
    }
}
impl MacroEnvironment {
    /// This environment with `delta`'s bindings set (or removed).
    pub(super) fn apply(&self, delta: &EnvDelta) -> Self {
        let mut out = self.clone();
        for (name, binding) in &delta.0 {
            if let Some(old) = out.bindings.remove(name.as_ref()) {
                out.fingerprint ^= binding_digest(name, &old);
            }
            if let Some(binding) = binding {
                out.fingerprint ^= binding_digest(name, binding);
                out.bindings.insert(Arc::clone(name), Arc::clone(binding));
            }
        }
        out
    }
    /// The bindings (by content: definition and definition site) in which `self` differs from `base`, so that
    /// `base.apply(&delta)` holds the same bindings as `self`; `None` when more than `limit` differ.
    pub(super) fn delta_from(&self, base: &Self, limit: usize) -> Option<EnvDelta> {
        let mut out = Vec::new();
        for difference in base.bindings.diff(&self.bindings) {
            let entry = match difference {
                im::ordmap::DiffItem::Add(name, binding) => (Arc::clone(name), Some(Arc::clone(binding))),
                im::ordmap::DiffItem::Update { old, new } => {
                    if binding_digest(old.0, old.1) == binding_digest(new.0, new.1) {
                        continue;
                    }
                    (Arc::clone(new.0), Some(Arc::clone(new.1)))
                }
                im::ordmap::DiffItem::Remove(name, _) => (Arc::clone(name), None),
            };
            out.push(entry);
            if out.len() > limit {
                return None;
            }
        }
        out.sort_by(|a, b| a.0.cmp(&b.0));
        Some(EnvDelta(out))
    }
    /// Digest of every binding; equal digests and lengths mean equal environments (a 128-bit
    /// collision aside, which `DMB_FRONTEND_VERIFY` would expose by comparing against a full pass).
    pub fn fingerprint(&self) -> u128 {
        self.fingerprint
    }
    /// Whether both environments hold the same bindings, definitions and definition sites.
    pub fn same_bindings(&self, other: &Self) -> bool {
        self.shares_storage_with(other)
            || (self.len() == other.len() && self.fingerprint == other.fingerprint)
    }
    /// Exact persistent-root sharing, for opt-in diagnostics without cloning maps.
    pub fn shares_storage_with(&self, other: &Self) -> bool {
        self.bindings.ptr_eq(&other.bindings)
    }

    /// Borrow retained payloads; opaque persistent-map node capacity is not exposed.
    /// The binding address and inline size permit deduplication across snapshots.
    pub fn visit_storage(&self,mut visitor:impl FnMut(&Arc<str>,usize,usize,&Arc<Macro>,Option<&DefinitionOrigin>)){
        self.visit_storage_while(|name,address,bytes,definition,origin|{visitor(name,address,bytes,definition,origin);true});
    }
    /// Returning false means this exact binding was already counted, so its
    /// shared older chain can stop without another roster or pointer index.
    pub fn visit_storage_while(&self,mut visitor:impl FnMut(&Arc<str>,usize,usize,&Arc<Macro>,Option<&DefinitionOrigin>)->bool){
        for(name,binding)in &self.bindings{let mut current=Some(binding);while let Some(binding)=current{if !visitor(name,Arc::as_ptr(binding)as usize,std::mem::size_of::<Binding>(),&binding.definition,binding.definition_origin()){break}current=binding.previous.as_ref();}}
    }
    pub fn visit_storage_difference(&self,previous:&Self,mut visitor:impl FnMut(&Arc<str>,usize,usize,&Arc<Macro>,Option<&DefinitionOrigin>)){
        self.visit_storage_difference_while(previous,|name,address,bytes,definition,origin|{visitor(name,address,bytes,definition,origin);true});
    }
    pub fn visit_storage_difference_while(&self,previous:&Self,mut visitor:impl FnMut(&Arc<str>,usize,usize,&Arc<Macro>,Option<&DefinitionOrigin>)->bool){
        for difference in previous.bindings.diff(&self.bindings){let(name,binding)=match difference{im::ordmap::DiffItem::Add(name,binding)=>(name,binding),im::ordmap::DiffItem::Update{new,..}=>new,im::ordmap::DiffItem::Remove(_,_)=>continue};let old=previous.bindings.get(name.as_ref());let mut current=Some(binding);while let Some(binding)=current{if old.is_some_and(|old|Arc::ptr_eq(old,binding)){break}if !visitor(name,Arc::as_ptr(binding)as usize,std::mem::size_of::<Binding>(),&binding.definition,binding.definition_origin()){break}current=binding.previous.as_ref();}}
    }
    pub(super) fn insert(
        &mut self,
        name: &str,
        definition: Macro,
        origin: Option<DefinitionOrigin>,
    ) {
        let binding = Arc::new(Binding {
            definition: Arc::new(definition),
            original:None,
            origin,
            previous:None,previous_digest:0,
        });
        self.fingerprint ^= binding_digest(name, &binding);
        if let Some(old) = self.bindings.insert(Arc::from(name), binding) {
            self.fingerprint ^= binding_digest(name, &old);
        }
    }
    pub(super) fn insert_stacked(&mut self,name:&str,definition:Macro,origin:Option<DefinitionOrigin>){
        let previous=self.bindings.remove(name);
        let previous_digest=previous.as_ref().map_or(0,|old|binding_digest(name,old));self.fingerprint^=previous_digest;
        let binding=Arc::new(Binding{definition:Arc::new(definition),original:None,origin,previous,previous_digest});
        self.fingerprint^=binding_digest(name,&binding);self.bindings.insert(Arc::from(name),binding);
    }
    pub(super) fn remove_stacked(&mut self,name:&str){
        if let Some(old)=self.bindings.remove(name){self.fingerprint^=binding_digest(name,&old);
            if let Some(previous)=&old.previous{self.fingerprint^=binding_digest(name,previous);self.bindings.insert(Arc::from(name),Arc::clone(previous));}
        }
    }
    pub(super) fn remove(&mut self, name: &str) {
        if let Some(old) = self.bindings.remove(name) {
            self.fingerprint ^= binding_digest(name, &old);
        }
    }
    pub fn definition_origin(&self, name: &str) -> Option<&DefinitionOrigin> {
        self.bindings.get(name)?.definition_origin()
    }
    pub fn shared_definition(&self, name: &str) -> Option<Arc<Macro>> {
        self.bindings
            .get(name)
            .map(|binding| Arc::clone(&binding.definition))
    }
    pub fn len(&self) -> usize {
        self.bindings.len()
    }
    pub fn is_empty(&self) -> bool {
        self.bindings.is_empty()
    }
}
impl MacroLookup for MacroEnvironment {
    fn get_key_value(&self, name: &str) -> Option<(&str, &Macro)> {
        self.bindings
            .get_key_value(name)
            .map(|(key, binding)| (key.as_ref(), binding.definition.as_ref()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn storage_diff_visits_new_equal_content_allocations_and_ignores_removed_bindings() {
        let definition = || Macro {
            parameters: None,
            variadic: false,
            replacement: "same".into(),
        };
        let mut environment = MacroEnvironment::default();
        environment.insert("OLD", definition(), None);
        environment.insert("KEEP", definition(), None);
        let previous = environment.clone();
        let mut unchanged = 0;
        environment.visit_storage_difference(&previous, |_, _, _, _, _| unchanged += 1);
        assert_eq!(unchanged, 0);
        environment.insert("KEEP", definition(), None);
        environment.insert("NEW", definition(), None);
        environment.remove("OLD");
        let mut changed = Vec::new();
        environment.visit_storage_difference(&previous, |name, binding, _, definition, _| {
            changed.push((name.to_string(), binding, Arc::as_ptr(definition) as usize));
        });
        assert_eq!(
            changed
                .iter()
                .map(|entry| entry.0.as_str())
                .collect::<Vec<_>>(),
            vec!["KEEP", "NEW"]
        );
        previous.visit_storage(|name, binding, _, definition, _| {
            if name.as_ref() == "KEEP" {
                assert_ne!(changed[0].1, binding);
                assert_ne!(changed[0].2, Arc::as_ptr(definition) as usize);
            }
        });
        assert_eq!(previous.get("KEEP"), environment.get("KEEP"));
    }
    #[test]
    fn fingerprint_follows_bindings_not_history() {
        let definition = |text: &str| Macro {
            parameters: None,
            variadic: false,
            replacement: text.into(),
        };
        let origin = |line| DefinitionOrigin {
            path: Arc::new(std::path::PathBuf::from("a.dm")),
            source_span: dm_syntax::Span::new(0, 4),
            source_line: line,
        };
        let mut left = MacroEnvironment::default();
        let mut right = MacroEnvironment::default();
        left.insert("A", definition("1"), Some(origin(1)));
        left.insert("B", definition("2"), None);
        right.insert("B", definition("2"), None);
        right.insert("A", definition("9"), None);
        right.insert("A", definition("1"), Some(origin(1)));
        assert!(left.same_bindings(&right));
        assert_eq!(left.fingerprint(), right.fingerprint());
        right.insert("A", definition("1"), Some(origin(2)));
        assert!(!left.same_bindings(&right), "a moved definition site differs");
        right.insert("A", definition("1"), Some(origin(1)));
        right.insert("C", definition("3"), None);
        assert!(!left.same_bindings(&right));
        right.remove("C");
        assert!(left.same_bindings(&right));
        left.remove("A");
        left.remove("B");
        assert_eq!(left.fingerprint(), MacroEnvironment::default().fingerprint());
    }
    #[test]
    fn snapshots_share_replacement_bodies_and_freeze_definition_epochs() {
        let mut env = MacroEnvironment::default();
        env.insert(
            "LARGE",
            Macro {
                parameters: None,
                variadic: false,
                replacement: "body".repeat(16384),
            },
            None,
        );
        let first = env.clone();
        assert!(first.shares_storage_with(&env));
        env.insert(
            "OTHER",
            Macro {
                parameters: None,
                variadic: false,
                replacement: "2".into(),
            },
            None,
        );
        let second = env.clone();
        assert!(!first.shares_storage_with(&second));
        let retained = |snapshot: &MacroEnvironment| {
            let mut result = None;
            snapshot.visit_storage(|name, binding, _, definition, _| {
                if name.as_ref() == "LARGE" {
                    result = Some((binding, Arc::as_ptr(definition) as usize));
                }
            });
            result.unwrap()
        };
        assert_eq!(retained(&first), retained(&second));
        assert!(std::ptr::eq(
            first.get("LARGE").unwrap(),
            second.get("LARGE").unwrap()
        ));
        env.insert(
            "LARGE",
            Macro {
                parameters: None,
                variadic: false,
                replacement: "new".into(),
            },
            None,
        );
        env.remove("OTHER");
        assert_eq!(first.get("LARGE").unwrap().replacement.len(), 65536);
        assert_eq!(second.get("OTHER").unwrap().replacement, "2");
        assert_eq!(env.get("LARGE").unwrap().replacement, "new");
        assert!(env.get("OTHER").is_none());
    }
}

#[cfg(test)]mod original_stack_tests{
 use super::*;
 fn value(n:usize)->Macro{Macro{parameters:None,variadic:false,replacement:n.to_string()}}
 #[test]fn original_stack_retains_each_actual_binding_and_drops_deep_unique_history_iteratively(){
  let mut environment=MacroEnvironment::default();for i in 0..8192{environment.insert_stacked("X",value(i),None);}let mut count=0;environment.visit_storage(|_,_,_,_,_|count+=1);assert_eq!(count,8192);let before=environment.fingerprint();let retained=environment.clone();environment.remove_stacked("X");assert_eq!(environment.get("X").unwrap().replacement,"8190");assert_eq!(retained.get("X").unwrap().replacement,"8191");assert_ne!(environment.fingerprint(),before);drop(retained);drop(environment);
 }
    #[test]fn original_history_census_stops_at_actual_already_counted_pop_ancestors(){
        let mut environment=MacroEnvironment::default();for i in 0..128{environment.insert_stacked("A",Macro{parameters:None,variadic:false,replacement:i.to_string()},None);}
        let mut seen=std::collections::HashSet::new();let mut calls=0;environment.visit_storage_while(|_,address,_,_,_|{calls+=1;seen.insert(address)});assert_eq!(seen.len(),128);
        for _ in 0..128{let prior=environment.clone();environment.remove_stacked("A");environment.visit_storage_difference_while(&prior,|_,address,_,_,_|{calls+=1;seen.insert(address)});}
        assert_eq!(seen.len(),128);assert!(calls<=256,"history pop revisited a whole counted chain: {calls}");assert!(environment.is_empty());
    }
}

#[cfg(test)]mod original_product_tests{
 use super::*;use crate::macro_expansion::{OriginalMacroToken,OriginalMacroOrigin};use std::sync::atomic::{AtomicUsize,Ordering};
 fn test_initial_shape(input:crate::initial_environment::OriginalInitialDefinition<'_>,a:&SettingAdmission<'_>)->io::Result<OriginalMacroDefinition<'static>>{let parameters=match &input.metadata().parameters{None=>None,Some(names)=>{let mut rows=OriginalMacroRows::new(a)?;for name in names{let mut text=OriginalMacroText::new(a)?;text.push_str(name,a)?;rows.push(text,a)?;}Some(rows)}};Ok(OriginalMacroDefinition{parameters,variadic:input.metadata().variadic,replacement:OriginalMacroRows::new(a)?})}
 fn native(value:&str)->Macro{Macro{parameters:None,variadic:false,replacement:value.into()}}
 fn product(n:i32,a:&SettingAdmission<'_>)->Arc<OriginalDefinitionProduct>{let mut replacement=OriginalMacroRows::new(a).unwrap();replacement.push(OriginalMacroToken{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,value:OriginalMacroValue::Int(n),raw_spelling:None,origin:OriginalMacroOrigin{physical:dm_syntax::Span::new(7,8),line:2,byte_column:None,occurrence:0,invocation:false}},a).unwrap();OriginalDefinitionProduct::from_actual_product_using(OriginalMacroDefinition{parameters:None,variadic:false,replacement},a).unwrap()}
 #[cfg(debug_assertions)]
 #[test]
 fn failed_macro_census_separates_direct_unique_storage_from_shared_product_references(){
  let used=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  let mut env=MacroEnvironment::default();
  let one=product(1,&a);
  let held=Arc::clone(&one);
  env.insert_original_stacked_using("A",native("1"),None,one,&a).unwrap();
  env.insert_original_stacked_using("A",native("2"),None,product(2,&a),&a).unwrap();
  let before=used.load(Ordering::Acquire);
  let census=env.trace_original_products();
  assert_eq!(census.exclusive_products,1);
  assert_eq!(census.shared_product_references,1);
  let mut replacement_bytes=0;
  held.definition.replacement.visit_allocation(|_,bytes|replacement_bytes=bytes);
  assert_eq!(census.exclusive_replacement_capacity,replacement_bytes);
  assert!(census.shared_direct_bytes_per_reference_upper>census.exclusive_replacement_capacity);
  assert_eq!(census.lexical_frame_references,0);
  assert_eq!(used.load(Ordering::Acquire),before);
  drop(held);
  let census=env.trace_original_products();
  assert_eq!(census.exclusive_products,2);
  assert_eq!(census.shared_product_references,0);
  drop(env);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn same_binding_original_epochs_stack_and_undef_restore_exact_native_fingerprint_without_parallel_dictionary(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut env=MacroEnvironment::default();env.insert_stacked("A",native("1"),None);let native_hash=env.fingerprint();assert!(env.actual_original_product("missing").unwrap().is_none());assert_eq!(env.actual_original_product("A").unwrap_err().kind(),io::ErrorKind::Unsupported);env.insert_original_stacked_using("A",native("2"),None,product(2,&a),&a).unwrap();assert_ne!(env.fingerprint(),native_hash);let snapshot=env.clone();let address=snapshot.actual_original_product("A").unwrap().unwrap()as *const _ as usize;env.insert_original_stacked_using("A",native("3"),None,product(3,&a),&a).unwrap();env.remove_stacked("A");assert_eq!(env.fingerprint(),snapshot.fingerprint());assert_eq!(env.actual_original_product("A").unwrap().unwrap()as *const _ as usize,address);env.remove_stacked("A");assert_eq!(env.fingerprint(),native_hash);assert!(env.actual_original_product("A").is_err());assert!(snapshot.actual_original_product("A").unwrap().is_some());drop((env,snapshot));assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn actual_first_io_before_original_binding_install_keeps_previous_map_epoch_and_credit_recovers(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut env=MacroEnvironment::default();env.insert_stacked("A",native("1"),None);let snapshot=env.clone();let original=product(2,&a);let fault=||Err(io::Error::from_raw_os_error(1450));let failed=SettingAdmission::new(&used,1<<20,&fault);let error=env.insert_original_stacked_using("A",native("2"),None,original,&failed).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert!(env.shares_storage_with(&snapshot));assert_eq!(env.fingerprint(),snapshot.fingerprint());assert!(env.actual_original_product("A").is_err());assert_eq!(used.load(Ordering::Acquire),0);env.insert_original_stacked_using("A",native("2"),None,product(2,&a),&a).unwrap();drop((env,snapshot));assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]
 fn fallible_metadata_reconciliation_cannot_replace_an_existing_macro_epoch(){
  let used=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  let mut env=MacroEnvironment::default();
  env.insert_original_stacked_using("A",native("1"),None,product(1,&a),&a).unwrap();
  let old=env.clone();
  let error=env.insert_original_stacked_before_commit_using("A",native("2"),None,product(2,&a),&a,
   ||Err(io::Error::from_raw_os_error(1450))).unwrap_err();
  assert_eq!(error.raw_os_error(),Some(1450));
  assert!(env.shares_storage_with(&old));
  assert_eq!(env.fingerprint(),old.fingerprint());
  drop((env,old));
  assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]
 fn diagnostic_macro_docs_release_physical_rows_after_the_same_digest() {
  let used=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&used,8<<20,&||Ok(()));
  let make=|text:&str,purpose|{
   let mut bytes=OriginalMacroText::new(&a).unwrap();
   bytes.push_str(text,&a).unwrap();
   let mut docs=OriginalMacroRows::new(&a).unwrap();
   docs.push_definition_row(OriginalMacroDoc{
    kind:dm_syntax::OriginalCommentKind::LineFollowing,text:OriginalMacroTextValue::Owned(bytes),
    origin:OriginalMacroOrigin{physical:dm_syntax::Span::new(1,17),line:3,byte_column:Some(2),occurrence:4,invocation:false},
    lexical_frame:None,lexical_span:None,
   },&a).unwrap();
   let definition=OriginalMacroDefinition{parameters:None,variadic:false,replacement:OriginalMacroRows::new(&a).unwrap()};
   OriginalDefinitionProduct::from_product_with_name_using(None,None,definition,docs,purpose,&a).unwrap()
  };
  let full=make("actual doc",HistoryPurpose::Full);
  let retained=used.load(Ordering::Acquire);
  let compact=make("actual doc",HistoryPurpose::Diagnostic);
  assert_eq!(used.load(Ordering::Acquire)-retained,OriginalDefinitionProduct::wrapper_bytes());
  assert_eq!(compact.digest,full.digest);
  assert!(compact.docs().is_empty());
  assert_eq!(full.docs()[0].text.get(),"actual doc");
  assert_eq!(full.docs()[0].origin.line,3);
  let changed=make("other doc",HistoryPurpose::Diagnostic);
  assert_ne!(changed.digest,compact.digest);
  drop((full,compact,changed));
  assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]
 fn completed_macro_product_moves_funded_rows_without_cloning_or_double_census() {
  let used=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&used,8<<20,&||Ok(()));
  let mut parameters=OriginalMacroRows::new(&a).unwrap();
  let mut text=OriginalMacroText::new(&a).unwrap();
  text.push_str("actual",&a).unwrap();
  parameters.push_definition_row(text,&a).unwrap();
  let parameter_pointer=parameters.as_slice().as_ptr();
  let mut docs=OriginalMacroRows::new(&a).unwrap();
  docs.push_definition_row(OriginalMacroDoc{
   kind:dm_syntax::OriginalCommentKind::LineFollowing,text:OriginalMacroTextValue::Borrowed("doc"),
   origin:OriginalMacroOrigin{physical:dm_syntax::Span::new(0,3),line:1,byte_column:None,occurrence:0,invocation:false},
   lexical_frame:None,lexical_span:None,
  },&a).unwrap();
  let doc_pointer=docs.as_slice().as_ptr();
  let mut replacement=OriginalMacroRows::new(&a).unwrap();
  replacement.push_definition_row(OriginalMacroToken{
   string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,
   value:OriginalMacroValue::Int(5),raw_spelling:None,
   origin:OriginalMacroOrigin{physical:dm_syntax::Span::new(4,5),line:1,byte_column:None,occurrence:0,invocation:false},
  },&a).unwrap();
  let replacement_pointer=replacement.as_slice().as_ptr();
  let original=OriginalMacroDefinition{parameters:Some(parameters),variadic:false,replacement};
  let before=used.load(Ordering::Acquire);
  let product=OriginalDefinitionProduct::from_actual_product_with_docs_using(original,docs,&a).unwrap();
  assert_eq!(product.definition.parameters.as_ref().unwrap().as_ptr(),parameter_pointer);
  assert_eq!(product.docs().as_ptr(),doc_pointer);
  assert_eq!(product.definition.replacement.wide().as_ptr(),replacement_pointer);
  assert_eq!(used.load(Ordering::Acquire),before+OriginalDefinitionProduct::wrapper_bytes());
  assert_eq!(product._credit.bytes(),OriginalDefinitionProduct::wrapper_bytes()
    +std::mem::size_of::<OriginalMacroText>()+std::mem::size_of::<OriginalMacroDoc>()
    +std::mem::size_of::<OriginalMacroToken>());
  #[cfg(debug_assertions)]
  {
   let mut census=OriginalProductCensus::default();
   census.note(&product);
   assert_eq!(census.exclusive_wrapper_reserved,OriginalDefinitionProduct::wrapper_bytes());
   assert_eq!(census.exclusive_doc_row_capacity,std::mem::size_of::<OriginalMacroDoc>());
  }
  let alias=product.clone();
  drop(product);
  assert_eq!(used.load(Ordering::Acquire),before+OriginalDefinitionProduct::wrapper_bytes());
  drop(alias);
  assert_eq!(used.load(Ordering::Acquire),0);
 }

 #[test]
 fn transferring_macro_product_rows_keeps_first_io_and_foreign_counter_funded() {
  let counter=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&counter,1<<20,&||Ok(()));
  let mut credit=a.reserve(0).unwrap();
  let make=||{
   let mut rows=OriginalMacroRows::new(&a).unwrap();
   rows.push_definition_row(1u32,&a).unwrap();
   rows
  };
  let stopped=SettingAdmission::new(&counter,1<<20,&||Err(io::Error::from_raw_os_error(1450)));
  assert_eq!(retain_product_rows(make(),&mut credit,&stopped).unwrap_err().raw_os_error(),Some(1450));
  assert_eq!(counter.load(Ordering::Acquire),0);
  let foreign_counter=Arc::new(AtomicUsize::new(0));
  let foreign=SettingAdmission::new(&foreign_counter,1<<20,&||Ok(()));
  assert_eq!(retain_product_rows(make(),&mut credit,&foreign).unwrap_err().kind(),io::ErrorKind::InvalidInput);
  assert_eq!(counter.load(Ordering::Acquire),0);
  assert_eq!(foreign_counter.load(Ordering::Acquire),0);
 }
 #[test]fn definition_copy_before_argument_demand_keeps_its_real_owned_credit_after_environment_drop(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut env=MacroEnvironment::default();env.insert_original_stacked_using("A",native("7"),None,product(7,&a),&a).unwrap();let copied=env.actual_original_product("A").unwrap().unwrap().cloned_definition_using(&a).unwrap();drop(env);assert!(used.load(Ordering::Acquire)>0);assert!(matches!(copied.replacement.as_slice()[0].value,OriginalMacroValue::Int(7)));drop(copied);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn actual_definition_docs_share_same_binding_epoch_and_clones_retain_funded_values(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut docs=OriginalMacroRows::new(&a).unwrap();let mut text=OriginalMacroText::new(&a).unwrap();text.push_str("actual prior documentation",&a).unwrap();docs.push(OriginalMacroDoc{kind:dm_syntax::OriginalCommentKind::LineFollowing,text:OriginalMacroTextValue::Owned(text),origin:OriginalMacroOrigin{physical:dm_syntax::Span::new(2,9),line:1,byte_column:None,occurrence:4,invocation:false},lexical_frame:None,lexical_span:None},&a).unwrap();let definition=OriginalMacroDefinition{parameters:None,variadic:false,replacement:OriginalMacroRows::new(&a).unwrap()};let product=OriginalDefinitionProduct::from_actual_product_with_docs_using(definition,docs,&a).unwrap();let mut env=MacroEnvironment::default();env.insert_original_stacked_using("DOC",native(""),None,product,&a).unwrap();let snapshot=env.clone();let cloned=env.actual_original_product("DOC").unwrap().unwrap().cloned_docs_using(&a).unwrap();env.remove_stacked("DOC");assert!(env.actual_original_product("DOC").unwrap().is_none());assert_eq!(snapshot.actual_original_product("DOC").unwrap().unwrap().docs()[0].text.get(),"actual prior documentation");drop((env,snapshot));assert!(used.load(Ordering::Acquire)>0);assert_eq!(cloned.as_slice()[0].origin.occurrence,4);drop(cloned);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn actual_initial_table_walk_issues_each_final_default_and_caller_binding_once_with_no_hidden_shadow_epoch(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,4<<20,&||Ok(()));let mut finals=std::collections::BTreeMap::new();crate::initial_environment::install(crate::InitialEnvironment::OriginalChecker0290,&mut finals);finals.insert("TRUE".into(),native("7"));finals.insert("CALLER".into(),native("99"));let caller=std::collections::BTreeMap::from([("TRUE".to_owned(),"7".to_owned()),("CALLER".to_owned(),"99".to_owned())]);let mut seen=std::collections::BTreeMap::new();let mut env=MacroEnvironment::default();
  env.install_original_initial_using(crate::InitialEnvironment::OriginalChecker0290,&finals,&caller,&a,&mut|input,a|{*seen.entry(input.name().to_owned()).or_insert(0usize)+=1;assert_eq!(input.replacement_text(),finals[input.name()].replacement);let parameters=match &input.metadata().parameters{None=>None,Some(names)=>{let mut rows=OriginalMacroRows::new(a)?;for name in names{let mut text=OriginalMacroText::new(a)?;text.push_str(name,a)?;rows.push(text,a)?;}Some(rows)}};Ok(OriginalMacroDefinition{parameters,variadic:input.metadata().variadic,replacement:OriginalMacroRows::new(a)?})}).unwrap();
  assert_eq!(seen.len(),105);assert!(seen.values().all(|n|*n==1));assert_eq!(env.get("TRUE").unwrap().replacement,"7");assert!(env.actual_original_product("TRUE").unwrap().is_some());let mut count=0;env.visit_storage(|_,_,_,_,_|count+=1);assert_eq!(count,105);env.remove_stacked("TRUE");assert!(env.get("TRUE").is_none(),"bootstrap must not invent a second hidden default epoch");assert!(env.actual_original_product("missing").unwrap().is_none());drop(env);assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn initial_factory_io_or_forged_physical_product_preserves_empty_environment_and_fresh_issuance_recovers(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut finals=std::collections::BTreeMap::new();crate::initial_environment::install(crate::InitialEnvironment::OriginalChecker0290,&mut finals);finals.insert("FIRST".into(),native("1"));finals.insert("SECOND".into(),native("2"));let caller=std::collections::BTreeMap::from([("FIRST".to_owned(),"1".to_owned()),("SECOND".to_owned(),"2".to_owned())]);let mut env=MacroEnvironment::default();let mut calls=0;
  assert_eq!(env.install_original_initial_using(crate::InitialEnvironment::OriginalChecker0290,&finals,&caller,&a,&mut|_,a|{calls+=1;if calls==2{return Err(io::Error::from_raw_os_error(1450))}Ok(OriginalMacroDefinition{parameters:None,variadic:false,replacement:OriginalMacroRows::new(a)?})}).unwrap_err().raw_os_error(),Some(1450));assert!(env.is_empty());assert_eq!(used.load(Ordering::Acquire),0);
  assert_eq!(env.install_original_initial_using(crate::InitialEnvironment::OriginalChecker0290,&finals,&caller,&a,&mut|_,a|{let mut replacement=OriginalMacroRows::new(a)?;replacement.push(OriginalMacroToken{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:Some(dm_syntax::Span::new(0,1)),value:OriginalMacroValue::Int(1),raw_spelling:None,origin:OriginalMacroOrigin{physical:dm_syntax::Span::default(),line:0,byte_column:None,occurrence:0,invocation:false}},a)?;Ok(OriginalMacroDefinition{parameters:None,variadic:false,replacement})}).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert!(env.is_empty());assert_eq!(used.load(Ordering::Acquire),0);
  env.install_original_initial_using(crate::InitialEnvironment::OriginalChecker0290,&finals,&caller,&a,&mut|input,a|test_initial_shape(input,a)).unwrap();assert!(env.actual_original_product("SECOND").unwrap().is_some());let before=env.fingerprint();assert_eq!(env.install_original_initial_using(crate::InitialEnvironment::OriginalChecker0290,&finals,&caller,&a,&mut|_,_|panic!("nonempty environment must not demand factory")).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(env.fingerprint(),before);drop(env);assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[cfg(test)]mod original_name_point_data_tests{
 use super::*;use std::sync::atomic::{AtomicUsize,Ordering};
 #[test]
 fn compact_definition_name_retains_same_physical_spelling_and_frame(){
  let used=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  let lease=crate::SourceAcquisitionLease::from_raw_original_bytes(b"#define ORIGINAL 1\n".to_vec(),17u64);
  let frame=crate::regions::OriginalLexicalFrameIdentity::issue(lease.clone(),&a).unwrap();
  let span=dm_syntax::Span::new(8,16);
  let spelling=lease.source_text().checked_view(span.range()).unwrap();
  let origin=OriginalMacroOrigin{physical:span,line:1,byte_column:Some(9),occurrence:3,invocation:false};
  let token=OriginalMacroToken{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:Some(frame.clone()),lexical_span:Some(span),raw_spelling:None,value:OriginalMacroValue::Ident{spelling:OriginalMacroTextValue::Source(spelling.clone()),whitespace:true},origin};
  let definition=OriginalMacroDefinition{parameters:None,variadic:false,replacement:OriginalMacroRows::new(&a).unwrap()};
  let product=OriginalDefinitionProduct::from_named_actual_product_using(token,definition,OriginalMacroRows::new(&a).unwrap(),None,HistoryPurpose::Full,&a).unwrap();
  let name=product.definition_name().unwrap();
  assert_eq!(name.origin(),origin);
  assert!(name.uses_physical_storage());
  assert_eq!(name.spelling(),"ORIGINAL");
  assert_eq!(name.spelling().as_ptr(),spelling.as_str().as_ptr());
  assert_eq!(product._credit.bytes(),OriginalDefinitionProduct::wrapper_bytes());
  #[cfg(target_pointer_width="64")]
  assert!(OriginalDefinitionProduct::wrapper_bytes()<=192,"at least 64 bytes below the prior 256-byte wrapper");
  let mut views=0;
  product.visit_source_views(|_|views+=1);
  let mut frames=0;
  product.visit_lexical_frames(|actual|{assert!(actual.same_frame(&frame));frames+=1});
  assert_eq!((views,frames),(0,1));
  drop((product,frame,lease,spelling));
  assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]
 fn foreign_equal_spelling_keeps_the_exact_funded_wide_name_and_current_frame() {
  let used=Arc::new(AtomicUsize::new(0));
  let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
  let lease=crate::SourceAcquisitionLease::from_raw_original_bytes(b"NAME".to_vec(),17u64);
  let separate=crate::SourceAcquisitionLease::from_raw_original_bytes(b"NAME".to_vec(),18u64);
  let frame=crate::regions::OriginalLexicalFrameIdentity::issue(lease.clone(),&a).unwrap();
  let span=dm_syntax::Span::new(0,4);
  let spelling=separate.source_text().checked_view(span.range()).unwrap();
  let origin=OriginalMacroOrigin{physical:span,line:1,byte_column:Some(1),occurrence:0,invocation:false};
  let make=|a:&SettingAdmission<'_>| {
   let token=OriginalMacroToken{string_mode:dm_syntax::OriginalStringMode::Unknown,
    punctuation_close:false,lexical_frame:Some(frame.clone()),lexical_span:Some(span),raw_spelling:None,
    value:OriginalMacroValue::Ident{spelling:OriginalMacroTextValue::Source(spelling.clone()),whitespace:false},origin};
   let definition=OriginalMacroDefinition{parameters:None,variadic:false,replacement:OriginalMacroRows::new(a)?};
   OriginalDefinitionProduct::from_named_actual_product_using(token,definition,OriginalMacroRows::new(a)?,None,HistoryPurpose::Full,a)
  };
  let before=used.load(Ordering::Acquire);
  let exact=OriginalDefinitionProduct::wrapper_bytes()+std::mem::size_of::<WideDefinitionName>();
  let denied=SettingAdmission::new(&used,before+exact-1,&||Ok(()));
  assert_eq!(make(&denied).unwrap_err().kind(),io::ErrorKind::OutOfMemory);
  assert_eq!(used.load(Ordering::Acquire),before);
  let limit=SettingAdmission::new(&used,before+exact,&||Ok(()));
  let product=make(&limit).unwrap();
  assert_eq!(used.load(Ordering::Acquire),before+exact);
  let name=product.definition_name().unwrap();
  assert!(!name.uses_physical_storage());
  assert_eq!(name.origin(),origin);
  assert!(name.lexical_frame().unwrap().same_frame(&frame));
  let mut views=0;
  product.visit_source_views(|view|{assert!(view.same_view(&spelling));views+=1;});
  assert_eq!(views,1);
  let mut owned=0;
  product.visit_owned_storage(|_,n|owned+=n);
  assert_eq!(owned,std::mem::size_of::<WideDefinitionName>());
  drop((product,spelling,frame,lease,separate));
  assert_eq!(used.load(Ordering::Acquire),0);
 }
 #[test]fn named_product_location_data_is_independent_of_replacement_and_initial_absence(){
  let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let make=||OriginalMacroDefinition{parameters:None,variadic:false,replacement:OriginalMacroRows::new(&a).unwrap()};
  let initial=OriginalDefinitionProduct::from_actual_product_using(make(),&a).unwrap();assert!(initial.definition_name().is_none());
  let origin=OriginalMacroOrigin{physical:dm_syntax::Span::new(31,35),line:7,byte_column:Some(9),occurrence:2,invocation:true};let name=OriginalMacroToken{string_mode:dm_syntax::OriginalStringMode::Unknown,punctuation_close:false,lexical_frame:None,lexical_span:None,raw_spelling:None,value:OriginalMacroValue::Ident{spelling:OriginalMacroTextValue::Borrowed("NAME"),whitespace:false},origin};
  let product=OriginalDefinitionProduct::from_named_actual_product_using(name,make(),OriginalMacroRows::new(&a).unwrap(),None,HistoryPurpose::Full,&a).unwrap();assert_eq!(product.definition_name().unwrap().origin(),origin);
  assert_eq!(product.definition_name().unwrap().spelling(),"NAME");
  assert!(std::mem::size_of::<Option<OriginalDefinitionName>>()<std::mem::size_of::<Option<OriginalMacroToken<'static>>>());
  assert!(!product.definition_name().unwrap().uses_physical_storage());
  assert_eq!(product._credit.bytes(),OriginalDefinitionProduct::wrapper_bytes()+std::mem::size_of::<WideDefinitionName>());
  assert_eq!(product.definition.replacement.len(),0);let mut env=MacroEnvironment::default();let metadata=Macro{parameters:None,variadic:false,replacement:String::new()};assert_eq!(env.insert_original_stacked_using("OTHER",metadata,None,product.clone(),&a).unwrap_err().kind(),io::ErrorKind::InvalidInput);assert_eq!(env.len(),0);drop((env,product,initial));assert_eq!(used.load(Ordering::Acquire),0);
 }
}

#[path="original_environment_allocation.rs"]
mod original_allocation;
pub(super) use original_allocation::{OriginalEnvironment, OriginalEnvironmentRead, OriginalFinalMacros};
