//! Immutable relative declaration syntax and checked current offset bindings.
//! Exact source-key admission remains the responsibility of the owning store.
use super::{internal, BodySyntaxFailure};
use dm_syntax::{Item, ItemKind, OriginalCommittedItems, OriginalItems, Span};
#[cfg(test)]
#[path = "../../../shared/test_scratch.rs"]
mod header_test_scratch;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, OnceLock};
#[path = "frontend_relative_arena.rs"]
mod arena;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BindingError {
    InvalidRelativeSpan,
    OffsetOverflow,
    SourceLengthMismatch,
    ForeignOriginalHeaderOwner,
}
#[derive(Debug)]
pub struct RelativeSyntax {
    items: arena::Arena,
    source_len: usize,
    max_end: usize,
    bodies: Vec<RelativeBody>,
    // Source-code facts only. Original-file authority remains per issued mapping.
    primary_headers: OnceLock<Result<Arc<[(usize, Option<usize>, u8)]>, BindingError>>,
    primary_header_reissues: AtomicUsize,
    // Last: AST/body buffers free before the shared primary parser reservation.
    original_headers: Option<Arc<crate::procedure::OriginalProcedureHeaders>>,
    // LAST: intrinsic grant covers the added field and actual storage owner.
    code_storage:Option<Arc<OrdinaryCodeStorage>>,
}

struct OrdinaryCodeStorage{
 demand:bool,slots:Option<Arc<dm_syntax::AdmittedOrdinalSlots<BodyCodeIdentity>>>,
 // LAST: both actual owner Arc and containing RelativeSyntax fixed delta.
 fixed:dm_syntax::SettingRootLease,
}
impl std::fmt::Debug for OrdinaryCodeStorage{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("OrdinaryCodeStorage").field("demand",&self.demand).field("slots",&self.slots).field("funded_bytes",&self.fixed.bytes()).finish()}}
impl OrdinaryCodeStorage{
 fn new(a:Option<&dm_syntax::SettingAdmission<'_>>,demand:bool)->Result<Option<Arc<Self>>,BindingError>{
  let Some(a)=a else{return if demand{Err(BindingError::InvalidRelativeSpan)}else{Ok(None)}};
  // This pregrant exists on EVERY admitted constructor, including eager None
  // slots. Portable no-admission construction remains explicitly unqualified.
  a.checkpoint().map_err(|_|BindingError::InvalidRelativeSpan)?;
  let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<Self>()).map_err(|_|BindingError::InvalidRelativeSpan)?;
  let bytes=layout.pad_to_align().size().checked_add(std::mem::size_of::<Option<Arc<Self>>>()).ok_or(BindingError::InvalidRelativeSpan)?;
  let fixed=a.reserve(bytes).map_err(|_|BindingError::InvalidRelativeSpan)?;
  let slots=if demand{Some(dm_syntax::AdmittedOrdinalSlots::new_shared(a,0).map_err(|_|BindingError::InvalidRelativeSpan)?)}else{None};
  Ok(Some(Arc::new(Self{demand,slots,fixed})))
 }
}
/// Exact source-capture capability. Only this parser-owned producer can mint it.
pub struct BodyCodeIdentity {
    // This SAME owner follows every strong CodeArc and resource-only weak loan.
    allocation_credit:Arc<BodyCodeWeakAllocation>,
}
// The existing Code credit owner also holds its actual weak locator. A weak
// loan aliases this one allocation rather than adding two pointers to each
// consumer. Its Weak remains first and real resource lease remains LAST.
struct BodyCodeWeakAllocation {
    code: std::sync::Weak<BodyCodeIdentity>,
    credit: OnceLock<dm_syntax::SettingRootLease>,
}
impl BodyCodeWeakAllocation {
    fn get(&self)->Option<&dm_syntax::SettingRootLease>{self.credit.get()}
    fn set(&self,credit:dm_syntax::SettingRootLease)->Result<(),dm_syntax::SettingRootLease>{self.credit.set(credit)}
}
/// Resource-only weak code locator. It preserves standard Weak liveness;
/// retaining this value cannot keep code or any source/model/AST alive.
#[derive(Clone)]
pub struct BodyCodeWeak {
    credit: Arc<BodyCodeWeakAllocation>,
}
impl std::fmt::Debug for BodyCodeWeak { fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{std::fmt::Debug::fmt(&self.credit.code,f)} }
impl BodyCodeWeak {
    pub fn upgrade(&self)->Option<Arc<BodyCodeIdentity>>{self.credit.code.upgrade()}
    pub fn strong_count(&self)->usize{self.credit.code.strong_count()}
    pub fn as_ptr(&self)->*const BodyCodeIdentity{self.credit.code.as_ptr()}
    pub fn ptr_eq(&self,other:&Self)->bool{std::sync::Weak::ptr_eq(&self.credit.code,&other.credit.code)}
    pub fn matches(&self,other:&Arc<BodyCodeIdentity>)->bool{self.credit.code.as_ptr()==Arc::as_ptr(other)}
    pub fn visit_allocation_storage(&self,visit:&mut dyn FnMut(usize,usize,usize)){
        let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<BodyCodeIdentity>()).expect("actual Code Arc layout");
        visit(self.credit.code.as_ptr() as usize,if self.credit.code.strong_count()>0{std::mem::size_of::<BodyCodeIdentity>()}else{0},layout.pad_to_align().size());
        let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<BodyCodeWeakAllocation>()).expect("actual Code credit Arc layout");visit(Arc::as_ptr(&self.credit) as usize,std::mem::size_of::<BodyCodeWeakAllocation>(),layout.pad_to_align().size());if let Some(credit)=self.credit.get(){credit.visit_counter_storage(|p,n|visit(p,n,n));}
    }
}
impl BodyCodeIdentity {
    pub fn downgrade(code:&Arc<Self>)->BodyCodeWeak{BodyCodeWeak{credit:Arc::clone(&code.allocation_credit)}}
}
// SAME Code allocation identity is lent by Arc itself during its actual
// construction. No numeric key, source span or equal-value comparison binds it.
fn body_code_with_credit(credit:OnceLock<dm_syntax::SettingRootLease>)->Arc<BodyCodeIdentity>{
    Arc::new_cyclic(move|code|BodyCodeIdentity{allocation_credit:Arc::new(BodyCodeWeakAllocation{code:code.clone(),credit})})
}

/// Actual early producer allocation only. This is not a source/current frame.
/// The actual CodeArc owns its exact allocation grant intrinsically through
/// every existing capture/convergence/query/product owner.
pub(super) struct CommittedBodyCodeIssue<'producer>{
 pub(super) identity:Arc<BodyCodeIdentity>,
 pub(super) header:Span,pub(super) body:Span,
 pub(super) producer:&'producer dm_syntax::OriginalPrimaryProducerIdentity,
}
// Keep the original first error latched while a BindingError-only caller
// crosses the legacy Option boundary. The direct IO entry below still returns
// the actual error payload to its existing callers.
fn funded_body_code_preserving_error(a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Arc<BodyCodeIdentity>>{
 a.checkpoint()?;
 let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<BodyCodeIdentity>()).map_err(|_|std::io::ErrorKind::OutOfMemory)?;
 let(lease_layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<BodyCodeWeakAllocation>()).map_err(|_|std::io::ErrorKind::OutOfMemory)?;
 let bytes=layout.pad_to_align().size().checked_add(lease_layout.pad_to_align().size()).ok_or(std::io::ErrorKind::OutOfMemory)?;
 Ok(body_code_with_credit(OnceLock::from(a.reserve(bytes)?)))
}
fn funded_body_code(a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Arc<BodyCodeIdentity>>{
 let pending=funded_body_code_preserving_error(a);
 if let Some(actual)=a.take_operational_error(){return Err(actual)}pending
}
pub(super) fn issue_committed_body_code<'producer>(input:&dm_syntax::OriginalCommittedBodyInput<'_,'_>,producer:&'producer dm_syntax::OriginalPrimaryProducerIdentity,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<CommittedBodyCodeIssue<'producer>>{
 if !input.literal_facts().admitted_by(a)||!producer.same_producer(input.primary_producer()){return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"early code has no actual primary resource loan"))}
 let identity=funded_body_code(a)?;Ok(CommittedBodyCodeIssue{identity,header:input.item().header_span,body:input.item().span,producer})
}
fn ordinary_body_code(a:Option<&dm_syntax::SettingAdmission<'_>>)->Result<Arc<BodyCodeIdentity>,BindingError>{match a{None=>Ok(body_code_with_credit(OnceLock::new())),Some(a)=>funded_body_code_preserving_error(a).map_err(|_proxy|BindingError::InvalidRelativeSpan)}}

#[derive(Debug)]
struct RelativeBody {
    code: Option<Arc<BodyCodeIdentity>>,
    path: Arc<[usize]>,
    span: Span,
    settings: Arc<[Span]>,
    stored_candidates: bool,
    settings_owner: Option<Arc<dm_ir::ProcedureMetadata>>,
    setting_footprints: Option<Arc<[crate::procedure::header_input::SettingFootprint]>>,
}
fn capture_bodies(
    items: OriginalItems<'_>,
    source: &str,
    path: &mut Vec<usize>,
    output: &mut Vec<RelativeBody>,
    owners: &std::collections::BTreeMap<usize, Arc<dm_ir::ProcedureMetadata>>,
    headers: Option<&crate::procedure::OriginalProcedureHeaders>,
    admission:Option<&dm_syntax::SettingAdmission<'_>>,
    ordinary_demand:bool,
)->Result<(),BindingError> {
    for (index, item) in items.iter().enumerate() {
        path.push(index);
        if matches!(item.kind(), ItemKind::Proc | ItemKind::Verb) {
            let mut settings = Vec::new();
            // Existing public setting_context_origins inventories EVERY
            // descendant header, including zero-setting bodies. This is not
            // another metadata extraction or expression parse.
            setting_spans_in_items(item.children(), &mut settings);
            output.push(RelativeBody {
                code: match headers{Some(headers)=>match headers.committed_body_code(item.span()).map_err(|_|BindingError::InvalidRelativeSpan)?{Some(actual)=>Some(actual),None if ordinary_demand=>None,None=>Some(ordinary_body_code(admission)?)},None if ordinary_demand=>None,None=>Some(ordinary_body_code(admission)?)},
                path: path.clone().into(),
                span: item.span(),
                settings: settings.into(),
                settings_owner: owners.get(&item.span().start).and_then(|owner| {
                    if let Some(headers) = headers {
                        headers
                            .settings_footprints(item.span(), owner)
                            .ok()
                            .map(|_| Arc::clone(owner))
                    } else {
                        let mut symbols = dm_ir::SymbolTable::default();
                        crate::settings::extract_settings_in_items(item.children(), &mut symbols)
                            .ok()
                            .filter(|nodes| nodes.as_ref() == owner.settings.as_ref())
                            .map(|_| Arc::clone(owner))
                    }
                }),
                setting_footprints: headers.and_then(|headers| {
                    owners.get(&item.span().start).and_then(|owner| {
                        headers
                            .settings_footprints(item.span(), owner)
                            .ok()
                            .flatten()
                            .cloned()
                    })
                }),
                stored_candidates: crate::procedure_statics::may_contain_stored_declarations(
                    &source[item.span().range()],
                ),
            });
        } else {
            capture_bodies(item.children(), source, path, output, owners, headers,admission,ordinary_demand)?;
        }
        path.pop();
    }
    Ok(())
}
pub(super) fn setting_spans_in_items(items:OriginalItems<'_>, output:&mut Vec<Span>){
    for item in items.iter(){output.push(item.header_span());setting_spans_in_items(item.children(),output);}
}
pub(crate) struct CurrentBodyRecipe<'a> {
    relative: &'a RelativeBody,
    relative_owner:&'a RelativeSyntax,
    ordinal:usize,
    offset: usize,
    root_prefix: usize,
    headers: Option<&'a Arc<crate::procedure::OriginalProcedureHeaders>>,
}
impl CurrentBodyRecipe<'_> {
    #[cfg(debug_assertions)]
    pub(crate) fn checker_body_profile(&self) -> bool {
        self.headers.is_some_and(|headers| headers.checker_body_profile())
    }

    pub(crate) fn source_window(&self)->Result<Span,&'static str>{let source=self.headers.ok_or("actual original header owner unissued")?;let end=self.offset.checked_add(source.abi_source_len()).ok_or("current original source window overflows")?;Ok(Span::new(self.offset,end))}
    pub(crate) fn parse_native_owned_admitted(&self,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Option<dm_syntax::AdmittedProcedureWithOrigins>>{
      match self.headers{Some(headers)=>headers.parse_body_owned_admitted(self.relative.span,self.offset,a),None=>Ok(None)}
    }
    pub(crate) fn parse_native_admitted(&self,a:&dm_syntax::SettingAdmission<'_>)
      ->std::io::Result<(Result<dm_syntax::ProcedureWithOrigins,dm_syntax::Diagnostic>,bool)>{
      match self.headers{
        Some(headers)=>headers.parse_body_admitted_with_native_consumption(self.relative.span,self.offset,a),
        None=>Ok((self.parse_original(),false)),
      }
    }
    pub(crate) fn parse_original_admitted(&self,a:&dm_syntax::SettingAdmission<'_>)
        ->std::io::Result<Result<dm_syntax::ProcedureWithOrigins,dm_syntax::Diagnostic>> {
        match self.headers {
            Some(headers) => headers.parse_body_admitted(self.relative.span,self.offset,a),
            None => Ok(self.parse_original()),
        }
    }
    pub(crate) fn parse_original(&self)->Result<dm_syntax::ProcedureWithOrigins,dm_syntax::Diagnostic>{self.headers.ok_or_else(||dm_syntax::Diagnostic{span:self.span(),kind:dm_syntax::DiagnosticKind::Unsupported,message:"original declaration token input is unissued".into()})?.parse_body(self.relative.span,self.offset)}

    pub(crate) fn code_identity(&self) -> Arc<BodyCodeIdentity> {
        self.issued_code().expect("unissued native demand Code requires checked ordinal realization")
    }
    pub(crate) fn issued_code(&self)->Option<Arc<BodyCodeIdentity>>{self.relative_owner.issued_body_code(self.ordinal)}
    pub(crate) fn issued_code_for_binding(&self)->std::io::Result<Option<Arc<BodyCodeIdentity>>>{self.relative_owner.issued_body_code_for_binding(self.ordinal)}
    pub(crate) fn code_identity_admitted(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<Arc<BodyCodeIdentity>,BodySyntaxFailure>{self.relative_owner.body_code_admitted(self.ordinal,a)}
    pub(crate) fn settings_owner(&self) -> Option<Arc<dm_ir::ProcedureMetadata>> {
        self.relative.settings_owner.clone()
    }
    /// Relative original-chunk coordinates. Current offset and exact code/owner
    /// binding remain on this recipe; these are not standalone frame authority.
    pub(crate) fn setting_footprints(
        &self,
    ) -> Option<&Arc<[crate::procedure::header_input::SettingFootprint]>> {
        self.relative.setting_footprints.as_ref()
    }
    pub(crate) fn original_body_span(&self) -> Span {
        self.relative.span
    }
    pub(crate) fn setting_headers(
        &self,
    ) -> Option<&Arc<crate::procedure::OriginalProcedureHeaders>> {
        self.headers
    }
    pub(crate) fn offset(&self) -> usize {
        self.offset
    }
    pub(crate) fn stored_candidates(&self) -> bool {
        self.relative.stored_candidates
    }
    pub(crate) fn span(&self) -> Span {
        Span::new(
            self.relative.span.start + self.offset,
            self.relative.span.end + self.offset,
        )
    }
    pub(crate) fn path(&self) -> Arc<[usize]> {
        let mut path = self.relative.path.to_vec();
        path[0] += self.root_prefix;
        path.into()
    }
    pub(crate) fn settings(&self) -> impl Iterator<Item = Span> + '_ {
        self.relative
            .settings
            .iter()
            .map(|span| Span::new(span.start + self.offset, span.end + self.offset))
    }
}
impl RelativeSyntax {
    /// Mint once from root-relative parser output, validating every byte span.
    #[cfg(test)]
    pub(crate) fn capture(items: Vec<Item>, source: &str) -> Result<Self, BindingError> {
        Self::capture_shared(items, Arc::from(source))
    }
    #[cfg(test)]
    pub(crate) fn capture_shared(items: Vec<Item>, source: Arc<str>) -> Result<Self, BindingError> {
        Self::capture_with_settings(items, source.into(), &Default::default())
    }
    pub(crate) fn capture_with_settings(
        items: Vec<Item>,
        source: dm_preprocess::SourceText,
        owners: &std::collections::BTreeMap<usize, Arc<dm_ir::ProcedureMetadata>>,
    ) -> Result<Self, BindingError> {
        Self::capture_with_settings_headers(items, source, owners, None)
    }
    pub(crate) fn capture_with_settings_headers(
        items: Vec<Item>,
        source: dm_preprocess::SourceText,
        owners: &std::collections::BTreeMap<usize, Arc<dm_ir::ProcedureMetadata>>,
        original_headers: Option<Arc<crate::procedure::OriginalProcedureHeaders>>,
    ) -> Result<Self, BindingError> {Self::capture_with_settings_headers_using(items,source,owners,original_headers,None)}
    pub(super) fn capture_with_settings_headers_using(items:Vec<Item>,source:dm_preprocess::SourceText,owners:&std::collections::BTreeMap<usize,Arc<dm_ir::ProcedureMetadata>>,original_headers:Option<Arc<crate::procedure::OriginalProcedureHeaders>>,admission:Option<&dm_syntax::SettingAdmission<'_>>)->Result<Self,BindingError>{Self::capture_with_settings_headers_mode(items,source,owners,original_headers,admission,false)}
    pub(super) fn capture_with_settings_headers_mode(items:Vec<Item>,source:dm_preprocess::SourceText,owners:&std::collections::BTreeMap<usize,Arc<dm_ir::ProcedureMetadata>>,original_headers:Option<Arc<crate::procedure::OriginalProcedureHeaders>>,admission:Option<&dm_syntax::SettingAdmission<'_>>,ordinary_demand:bool)->Result<Self,BindingError>{
        if original_headers
            .as_ref()
            .is_some_and(|h| !h.same_source(&source))
        {
            return Err(BindingError::ForeignOriginalHeaderOwner);
        }
        let code_storage=OrdinaryCodeStorage::new(admission,ordinary_demand)?;
        let view=OriginalItems::from_items(&items);
        let max_end=Self::validate_items(view,&source)?;
        if let Some(headers) = original_headers.as_ref() {
            headers.reissue_settings_if_missing(&items,owners).map_err(|_|BindingError::ForeignOriginalHeaderOwner)?;
        }
        let (bodies,primary_headers)=Self::collect_metadata(view,&source,owners,original_headers.as_deref(),admission,ordinary_demand)?;
        let source_len=source.len();
        Ok(Self{items:arena::Arena::capture(items,source),source_len,max_end,bodies,primary_headers,
            primary_header_reissues:AtomicUsize::new(0),original_headers,code_storage})
    }
    pub(super) fn adopt_original_items(
        items: OriginalCommittedItems, source: dm_preprocess::SourceText,
        owners: &std::collections::BTreeMap<usize, Arc<dm_ir::ProcedureMetadata>>,
        original_headers: Arc<crate::procedure::OriginalProcedureHeaders>,
        admission:&dm_syntax::SettingAdmission<'_>,
    )->Result<Self,BindingError>{Self::adopt_original_items_mode(items,source,owners,original_headers,admission,false)}
    pub(super) fn adopt_original_items_mode(items:OriginalCommittedItems,source:dm_preprocess::SourceText,owners:&std::collections::BTreeMap<usize,Arc<dm_ir::ProcedureMetadata>>,original_headers:Arc<crate::procedure::OriginalProcedureHeaders>,admission:&dm_syntax::SettingAdmission<'_>,ordinary_demand:bool)->Result<Self,BindingError>{
        let code_storage=OrdinaryCodeStorage::new(Some(admission),ordinary_demand)?;
        if !original_headers.same_source(&source){return Err(BindingError::ForeignOriginalHeaderOwner)}
        let view=items.view_for_same_source(&source).map_err(|_|BindingError::InvalidRelativeSpan)?;
        let max_end=Self::validate_items(view,&source)?;
        // The checked adapter already installed these exact owners. The
        // compact Original path cannot invoke the portable reissuer.
        original_headers.require_issued_settings_items(view,owners).map_err(|_|BindingError::ForeignOriginalHeaderOwner)?;
        let (bodies,primary_headers)=Self::collect_metadata(view,&source,owners,Some(&original_headers),Some(admission),ordinary_demand)?;
        let source_len=source.len();
        Ok(Self{items:arena::Arena::Original{items,source},source_len,max_end,bodies,primary_headers,
            primary_header_reissues:AtomicUsize::new(0),original_headers:Some(original_headers),code_storage})
    }
    pub(crate) fn ordinary_code_demand(&self)->bool{self.code_storage.as_ref().is_some_and(|s|s.demand)}
    fn issued_body_code(&self,ordinal:usize)->Option<Arc<BodyCodeIdentity>>{let body=self.bodies.get(ordinal)?;body.code.as_ref().cloned().or_else(||self.code_storage.as_ref()?.slots.as_ref()?.issued(ordinal))}
    fn issued_body_code_for_binding(&self,ordinal:usize)->std::io::Result<Option<Arc<BodyCodeIdentity>>>{let Some(body)=self.bodies.get(ordinal)else{return Ok(None)};if let Some(code)=&body.code{return Ok(Some(Arc::clone(code)))}match self.code_storage.as_ref().and_then(|owner|owner.slots.as_ref()){Some(slots)=>slots.issued_for_binding(ordinal),None=>Ok(None)}}
    fn body_code_admitted(&self,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>)->Result<Arc<BodyCodeIdentity>,BodySyntaxFailure>{
      a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
      let storage=self.code_storage.as_ref().ok_or_else(||BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"ordinary Code has no actual admitted storage owner")))?;
      if !a.matches_lease_domain(&storage.fixed){return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"ordinary Code metadata belongs to another admission domain")))}
      let body=self.bodies.get(ordinal).ok_or_else(||BodySyntaxFailure::Syntax(internal("ordinary Code ordinal absent")))?;
      if let Some(code)=&body.code{return Ok(Arc::clone(code))}
      let slots=storage.slots.as_ref().ok_or_else(||BodySyntaxFailure::Syntax(internal("eager Code is unexpectedly unissued")))?;
      slots.get_or_create(self.bodies.len(),ordinal,a,||funded_body_code_preserving_error(a).map_err(BodySyntaxFailure::Operational)).map_err(|failure|match failure{
       dm_syntax::OrdinalSlotFailure::Value(actual)=>actual,
       dm_syntax::OrdinalSlotFailure::Admission(actual)=>BodySyntaxFailure::Operational(actual),
      })
    }
    fn validate_items(items:OriginalItems<'_>,source:&str)->Result<usize,BindingError>{
        fn validate(items:OriginalItems<'_>,source:&str,max_end:&mut usize)->Result<(),BindingError>{
            for item in items.iter(){
                for span in [item.span(),item.header_span()]{
                    if source.get(span.range()).is_none(){return Err(BindingError::InvalidRelativeSpan)}
                    *max_end=(*max_end).max(span.end);
                }
                if let Some(at)=item.declaration_cursor(){
                    if at>=source.len()||!source.is_char_boundary(at){return Err(BindingError::InvalidRelativeSpan)}
                    *max_end=(*max_end).max(at+1);
                }
                validate(item.children(),source,max_end)?;
            }
            Ok(())
        }
        let mut max_end=0;
        validate(items,source,&mut max_end)?;
        Ok(max_end)
    }
    fn collect_metadata(
        items: OriginalItems<'_>, source: &str,
        owners: &std::collections::BTreeMap<usize, Arc<dm_ir::ProcedureMetadata>>,
        original_headers: Option<&crate::procedure::OriginalProcedureHeaders>,
        admission:Option<&dm_syntax::SettingAdmission<'_>>,ordinary_demand:bool,
    )->Result<(Vec<RelativeBody>,OnceLock<Result<Arc<[(usize,Option<usize>,u8)]>,BindingError>>),BindingError>{
        let mut bodies=Vec::new();
        capture_bodies(items,source,&mut Vec::new(),&mut bodies,owners,original_headers,admission,ordinary_demand)?;
        fn issued(items:OriginalItems<'_>,parent:Option<u8>,out:&mut Vec<(usize,Option<usize>,u8)>){
            for item in items.iter(){
                if matches!(item.kind(),ItemKind::Proc|ItemKind::Verb){continue}
                let(flags,context)=dm_syntax::inherit_header_qualifiers(item.checker_qualifiers(),parent);
                out.push((item.header_span().start,item.declaration_cursor(),flags));
                issued(item.children(),context,out);
            }
        }
        let primary_headers=OnceLock::new();
        let mut headers=Vec::new();
        issued(items,None,&mut headers);
        if headers.iter().any(|row|row.1.is_some()){
            headers.sort_unstable();
            headers.dedup();
            let _=primary_headers.set(Ok(headers.into()));
        }
        Ok((bodies,primary_headers))
    }
    fn primary_headers(&self, reissue: bool) -> Option<&Arc<[(usize, Option<usize>, u8)]>> {
        if reissue {
            self.primary_headers.get_or_init(|| {
                self.primary_header_reissues.fetch_add(1, Ordering::Relaxed);
                let source = self
                    .shared_source()
                    .ok_or(BindingError::InvalidRelativeSpan)?;
                fn headers(
                    item: ItemView<'_>,
                    parent: Option<usize>,
                    out: &mut Vec<dm_syntax::PrimaryHeaderInput>,
                ) {
                    if matches!(item.kind(), ItemKind::Proc | ItemKind::Verb) {
                        return;
                    }
                    let index = out.len();
                    out.push(dm_syntax::PrimaryHeaderInput {
                        span: item.header_span(),
                        parent,
                        has_children: item.children().len() != 0,
                    });
                    for child in item.children() {
                        headers(child, Some(index), out);
                    }
                }
                let mut spans = Vec::new();
                for item in self.items.roots() {
                    headers(ItemView { item, offset: 0 }, None, &mut spans);
                }
                let mut rows = dm_syntax::primary_header_facts(source, &spans)
                    .map_err(|_| BindingError::InvalidRelativeSpan)?;
                rows.sort_unstable();
                rows.dedup();
                if rows.windows(2).any(|pair| {
                    pair[0].0 == pair[1].0 && (pair[0].1 != pair[1].1 || pair[0].2 != pair[1].2)
                }) {
                    return Err(BindingError::InvalidRelativeSpan);
                }
                Ok(rows.into())
            });
        }
        self.primary_headers.get()?.as_ref().ok()
    }
    pub(super) fn adopt_primary_headers(&self, other: &Self) {
        if self.shared_source().is_none() || self.shared_source() != other.shared_source() {
            return;
        }
        if let Some(Ok(rows)) = other.primary_headers.get() {
            let _ = self.primary_headers.set(Ok(Arc::clone(rows)));
        }
    }
    /// Compatibility materialization for a demanded standalone consumer.
    pub fn materialize_relative_items(&self) -> Vec<Item> {
        self.items
            .roots()
            .map(|item| ItemView { item, offset: 0 }.materialize())
            .collect()
    }
    /// Overflow fallback backing, exposed only for borrowed storage accounting.
    pub fn wide_relative_items(&self) -> Option<&Arc<[Item]>> {
        self.items.wide_items()
    }
    pub fn shared_source(&self) -> Option<&dm_preprocess::SourceText> {
        self.items.source()
    }
    pub fn visit_settings_owners(&self, mut visit: impl FnMut(&Arc<dm_ir::ProcedureMetadata>)) {
        if let Some(headers) = self.original_headers.as_ref() {
            headers.visit_setting_owners(&mut visit);
        }
        for body in &self.bodies {
            if let Some(owner) = &body.settings_owner {
                visit(owner);
            }
        }
    }
    pub fn visit_item_storage(&self, visit: impl FnMut(usize, usize, usize)) {
        self.items.visit_storage(visit);
    }
    pub fn visit_body_storage(&self, mut visit: impl FnMut(usize, usize, usize)) {
        self.visit_original_header_storage(&mut visit);
        if let Some(Ok(rows)) = self.primary_headers.get() {
            let bytes = std::mem::size_of_val(rows.as_ref());
            visit(rows.as_ptr() as usize, bytes, bytes);
        }
        visit(
            self.bodies.as_ptr() as usize,
            self.bodies.len() * std::mem::size_of::<RelativeBody>(),
            self.bodies.capacity() * std::mem::size_of::<RelativeBody>(),
        );
        if let Some(storage)=&self.code_storage{
            let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<OrdinaryCodeStorage>()).expect("actual Code storage Arc layout");
            visit(Arc::as_ptr(storage)as usize,std::mem::size_of::<OrdinaryCodeStorage>(),layout.pad_to_align().size());storage.fixed.visit_counter_storage(|p,n|visit(p,n,n));
            if let Some(slots)=&storage.slots{slots.visit_storage(&mut visit).expect("quiescent Code storage census");slots.visit_issued(&mut|_,code|code.visit_allocation_storage(&mut visit)).expect("quiescent Code row census");}
        }
        for body in &self.bodies {
            if let Some(code)=&body.code{code.visit_allocation_storage(&mut visit);}

            visit(
                body.path.as_ptr() as usize,
                std::mem::size_of_val(body.path.as_ref()),
                std::mem::size_of_val(body.path.as_ref()),
            );
            visit(
                body.settings.as_ptr() as usize,
                std::mem::size_of_val(body.settings.as_ref()),
                std::mem::size_of_val(body.settings.as_ref()),
            );
        }
    }
    /// New input payload only; source bytes share this RelativeSyntax's existing
    /// SourceText owner. Pointer dedup is the caller's live-owner census job.
    /// Checked producer reuse requires this SAME original header completion and
    /// resource domain. This test alone never admits a current source/frame.
    pub(crate) fn initializer_admission_matches(
        &self,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> std::io::Result<bool> {
        match &self.original_headers {
            Some(headers) => headers.initializer_admission_matches(a),
            None => {
                a.checkpoint()
                    .map_err(|proxy| a.take_operational_error().unwrap_or(proxy))?;
                Ok(false)
            }
        }
    }
    pub fn visit_setting_roots(&self, mut visit: impl FnMut(&dm_syntax::SettingExpression)) {
        if let Some(headers) = &self.original_headers {
            headers.visit_initializer_roots(&mut visit);
            headers.visit_default_roots(&mut visit);
            headers.visit_setting_roots(&mut visit);
        }
    }
    pub fn visit_original_header_storage(&self, visit: impl FnMut(usize, usize, usize)) {
        self.visit_original_header_storage_with_backing_filter(visit, &mut |_| false);
    }
    pub(super) fn visit_original_header_storage_with_backing_filter(&self, visit: impl FnMut(usize, usize, usize), skip:&mut dyn FnMut(&dyn std::any::Any)->bool) {
        if let Some(headers) = &self.original_headers {
            headers.visit_storage_with_backing_filter(visit, skip);
        }
    }
    pub(super) fn original_shared_span_tokens(&self) -> Option<&dm_syntax::SharedSpanTokens> {
        self.original_headers.as_ref()?.shared_span_tokens()
    }
    pub(super) fn visit_original_header_storage_classified(&self, a:&dm_syntax::SettingAdmission<'_>, visit:impl FnMut(usize,usize,usize,bool), skip:&mut dyn FnMut(&dyn std::any::Any)->bool) {
        if let Some(headers)=&self.original_headers {
            headers.visit_storage_classified(Some(a),visit,skip);
        }
    }
    /// Wide arena fallback can have no shared_source; this still exposes the
    /// SAME original recipe source to the existing pointer-deduplicated census.
    pub fn visit_original_header_source(&self, mut visit: impl FnMut(&dm_preprocess::SourceText)) {
        if let Some(headers) = &self.original_headers {
            headers.visit_source(&mut visit);
        }
    }
    /// The caller has already checked the immutable exact source key. This is
    /// a coordinate certificate, not a replacement for source authentication.
    pub(crate) fn bind(
        self: &Arc<Self>,
        source_len: usize,
        offset: usize,
    ) -> Result<CurrentSyntaxChunk, BindingError> {
        if source_len != self.source_len {
            return Err(BindingError::SourceLengthMismatch);
        }
        let end = offset
            .checked_add(self.max_end)
            .ok_or(BindingError::OffsetOverflow)?;
        // Semantic declaration origins use u32 coordinates; preserve the existing
        // unsupported/overflow path rather than narrowing an unchecked offset.
        if u32::try_from(end).is_err() {
            return Err(BindingError::OffsetOverflow);
        }
        Ok(CurrentSyntaxChunk {
            relative: Arc::clone(self),
            offset,
        })
    }
}
#[derive(Clone, Debug)]
pub struct CurrentSyntaxChunk {
    relative: Arc<RelativeSyntax>,
    offset: usize,
}
impl CurrentSyntaxChunk {
    pub fn shared_relative(&self) -> &Arc<RelativeSyntax> {
        &self.relative
    }
    pub fn offset(&self) -> usize {
        self.offset
    }
    pub fn len(&self) -> usize {
        self.relative.items.roots().len()
    }
    pub fn is_empty(&self) -> bool {
        self.relative.items.roots().len() == 0
    }
    pub fn items(&self) -> impl ExactSizeIterator<Item = ItemView<'_>> + DoubleEndedIterator {
        self.relative.items.roots().map(|item| ItemView {
            item,
            offset: self.offset,
        })
    }
    fn item(&self, index: usize) -> Option<ItemView<'_>> {
        self.relative.items.roots().nth(index).map(|item| ItemView {
            item,
            offset: self.offset,
        })
    }
}
#[derive(Clone, Copy, Debug)]
pub struct ItemView<'a> {
    item: arena::Ref<'a>,
    offset: usize,
}
impl PartialEq for ItemView<'_> {
    fn eq(&self, other: &Self) -> bool {
        self.kind() == other.kind()
            && self.header() == other.header()
            && self.span() == other.span()
            && self.header_span() == other.header_span()
            && self.item.indent() == other.item.indent()
            && self.children().eq(other.children())
    }
}
impl Eq for ItemView<'_> {}
impl<'a> ItemView<'a> {
    pub fn offset(self) -> usize {
        self.offset
    }
    pub fn same_node(self, other: ItemView<'_>) -> bool {
        self.item.same(other.item) && self.offset == other.offset
    }
    pub fn same_relative_node(self, other: ItemView<'_>) -> bool {
        self.item.same(other.item)
    }
    pub fn kind(self) -> ItemKind {
        self.item.kind()
    }
    pub fn header(self) -> &'a str {
        self.item.header()
    }
    pub fn relative_span(self) -> Span {
        self.item.span()
    }
    pub fn span(self) -> Span {
        let span = self.item.span();
        Span::new(span.start + self.offset, span.end + self.offset)
    }
    pub fn declaration_cursor(self) -> Option<usize> {
        self.item.declaration_cursor()?.checked_add(self.offset)
    }
    pub fn header_span(self) -> Span {
        let span = self.item.header_span();
        Span::new(span.start + self.offset, span.end + self.offset)
    }
    pub fn children(self) -> impl ExactSizeIterator<Item = ItemView<'a>> + DoubleEndedIterator {
        self.item.children().map(move |item| ItemView {
            item,
            offset: self.offset,
        })
    }
    pub fn child(self, index: usize) -> Option<Self> {
        self.item.children().nth(index).map(|item| Self {
            item,
            offset: self.offset,
        })
    }
    /// Materialize only this requested subtree; ordinary traversal stays borrowed.
    pub fn materialize(self) -> Item {
        Item {
            kind: self.kind(),
            header: self.header().to_owned(),
            span: self.span(),
            header_span: self.header_span(),
            declaration_cursor: self.declaration_cursor(),
            checker_qualifiers: self.item.checker_qualifiers(),
            original_outer_terminator: self.item.original_outer_terminator(),
            indent: self.item.indent(),
            children: self.children().map(Self::materialize).collect(),
        }
    }
    /// Standalone ABI adapters historically receive root-relative coordinates.
    pub fn materialize_relative(self) -> Item {
        Self { offset: 0, ..self }.materialize()
    }
}
/// Borrowed original token input only. Construction is private to the SAME
/// current declaration/body-code owner; this is not a copied semantic model.
pub(crate) struct OriginalSettingTokenInput<'a> {
    pub(crate) literal_owner:&'a crate::procedure::OriginalProcedureHeaders,
    pub(crate) source: &'a str,
    pub(crate) tokens: dm_syntax::TokenWindow<'a>,
    pub(crate) original_owner: &'a Arc<dm_ir::ProcedureMetadata>,
    pub(crate) ordinal: usize,
    pub(crate) header: Span,
    pub(crate) value: Span,
    pub(crate) offset: usize,
    pub(crate) slots: &'a dm_syntax::SettingExpressionSlots,
    pub(crate) original_value: Span,
}
pub(crate) struct OriginalInitializerTokenInput<'a> {
    pub(crate) dimension:bool,
    pub(crate) dimension_index:usize,
    pub(crate) dimension_count:usize,
    pub(crate) owner: &'a Arc<crate::procedure::OriginalProcedureHeaders>,
    pub(crate) source: &'a dm_preprocess::SourceText,
    pub(crate) tokens: dm_syntax::TokenWindow<'a>,
    pub(crate) value: Span,
    pub(crate) ordinal: usize,
    pub(crate) count: usize,
    pub(crate) offset: usize,
    pub(crate) slots: &'a dm_syntax::SettingExpressionSlots,
}
pub(crate) struct OriginalInitializerDimensionTokens<'source>{
 owner:&'source Arc<crate::procedure::OriginalProcedureHeaders>,views:crate::procedure::ArrayDimensions<'source>,ordinal:usize,count:usize,offset:usize,next:usize,finished:bool,
}
impl<'source> OriginalInitializerDimensionTokens<'source>{
 pub(crate) fn next_input(&mut self,array:&dm_ir::ArrayDeclaration,symbols:&dm_ir::SymbolTable)->Result<Option<(usize,Option<OriginalInitializerTokenInput<'source>>)>,String>{
  if self.finished{return Ok(None)}
  let view=match self.views.next(){Some(Ok(view))=>view,Some(Err(error))=>{self.finished=true;return Err(error)},None=>{self.finished=true;return if self.next==array.dimensions.len(){Ok(None)}else{Err("dimension source count differs from original metadata".into())}}};
  let index=self.next;self.next+=1;let expression=array.dimensions.get(index).ok_or("original dimension source has extra suffix")?;
  let value=self.owner.dimension_tokens_view(view,expression.as_ref(),symbols)?;
  Ok(Some((index,value.map(|(source,tokens,value)|OriginalInitializerTokenInput{dimension:true,dimension_index:index,dimension_count:array.dimensions.len(),owner:self.owner,source,tokens,value,ordinal:self.ordinal,count:self.count,offset:self.offset,slots:self.owner.initializer_slots()}))))
 }
}
pub(crate) struct OriginalReturnTokenInput<'a> {
    pub(crate) literal_owner:&'a crate::procedure::OriginalProcedureHeaders,
    pub(crate) source: &'a str,
    pub(crate) tokens: dm_syntax::TokenWindow<'a>,
    pub(crate) original_value: Span,
    pub(crate) ordinal: usize,
    pub(crate) count: usize,
    pub(crate) offset: usize,
    pub(crate) slots: &'a dm_syntax::SettingExpressionSlots,
}
#[derive(Clone, Debug)]
pub struct DeclarationSyntax {
    chunks: Arc<[CurrentSyntaxChunk]>,
    prefix: Arc<[usize]>,
    len: usize,
    ordered_chunks: bool,
}
impl DeclarationSyntax {
    /// Expanded-text offsets where each grammar chunk starts and ends. The parser lexes every chunk
    /// on its own, so no token continues across one of these offsets.
    pub fn chunk_boundaries(&self) -> Vec<usize> {
        self.chunks
            .iter()
            .flat_map(|chunk| [chunk.offset, chunk.offset + chunk.relative.source_len])
            .collect()
    }
    /// Exact current parser header context. Procedure executable children are
    /// deliberately excluded from declaration authority.
    pub fn declaration_header_at(&self, offset: usize) -> Option<ItemKind> {
        fn search<'a>(
            len: usize,
            item: &dyn Fn(usize) -> Option<ItemView<'a>>,
            offset: usize,
        ) -> Option<ItemKind> {
            let (mut low, mut high) = (0, len);
            while low < high {
                let mid = low + (high - low) / 2;
                if item(mid)?.header_span().start <= offset {
                    low = mid + 1;
                } else {
                    high = mid;
                }
            }
            let node = item(low.checked_sub(1)?)?;
            if node.header_span().start == offset {
                return matches!(
                    node.kind(),
                    ItemKind::Type | ItemKind::Var | ItemKind::Proc | ItemKind::Verb
                )
                .then_some(node.kind());
            }
            if offset >= node.span().end || !matches!(node.kind(), ItemKind::Type | ItemKind::Var) {
                return None;
            }
            search(node.children().len(), &|index| node.child(index), offset)
        }
        if !self.ordered_chunks {
            return None;
        }
        let index = self
            .chunks
            .partition_point(|chunk| chunk.offset <= offset)
            .checked_sub(1)?;
        let chunk = &self.chunks[index];
        if offset.checked_sub(chunk.offset)? >= chunk.relative.source_len {
            return None;
        }
        search(chunk.len(), &|index| chunk.item(index), offset)
    }
    pub fn declaration_cursor_at(&self, offset: usize) -> Option<usize> {
        self.declaration_cursor(offset, false)
    }
    /// Rich policy preparation may request this EXISTING native token query
    /// once after portable restore. Ordinary compilation never triggers it.
    pub fn declaration_cursor_at_for_policy(&self, offset: usize) -> Option<usize> {
        self.declaration_cursor(offset, true)
    }
    fn declaration_cursor(&self, offset: usize, reissue: bool) -> Option<usize> {
        if !self.ordered_chunks {
            return None;
        }
        let index = self
            .chunks
            .partition_point(|chunk| chunk.offset <= offset)
            .checked_sub(1)?;
        let chunk = &self.chunks[index];
        let relative = offset.checked_sub(chunk.offset)?;
        if relative >= chunk.relative.source_len {
            return None;
        }
        let rows = chunk.relative.primary_headers(reissue)?;
        let row = rows.get(rows.partition_point(|row| row.0 < relative))?;
        if row.0 != relative {
            return None;
        }
        row.1?.checked_add(chunk.offset)
    }
    pub fn declaration_checker_qualifiers_at_for_policy(&self, offset: usize) -> Option<u8> {
        if !self.ordered_chunks {
            return None;
        }
        let index = self
            .chunks
            .partition_point(|chunk| chunk.offset <= offset)
            .checked_sub(1)?;
        let chunk = &self.chunks[index];
        let relative = offset.checked_sub(chunk.offset)?;
        if relative >= chunk.relative.source_len {
            return None;
        }
        let rows = chunk.relative.primary_headers(true)?;
        let row = rows.get(rows.partition_point(|row| row.0 < relative))?;
        (row.0 == relative && row.2 != dm_syntax::UNKNOWN_HEADER_QUALIFIERS).then_some(row.2)
    }
    /// Native captured-body path: exact current chunk/body/code before borrowing
    /// any original token range. Matching bytes or member IDs are insufficient.
    pub(crate) fn original_body_recipe(&self,span:Span,code:&Arc<BodyCodeIdentity>)->Result<CurrentBodyRecipe<'_>,dm_syntax::Diagnostic>{self.original_body_recipe_checked(span,code).map_err(|error|match error{BodySyntaxFailure::Syntax(source)=>dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:source.message},BodySyntaxFailure::Operational(actual)=>dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:actual.to_string()}})}
    pub(crate) fn original_body_recipe_checked(&self,span:Span,code:&Arc<BodyCodeIdentity>)->Result<CurrentBodyRecipe<'_>,BodySyntaxFailure>{
     let recipe=self.original_body_recipe_using(span,None).map_err(|error|BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,error.message)))?;
     let actual=recipe.issued_code_for_binding().map_err(BodySyntaxFailure::Operational)?;
     if !actual.as_ref().is_some_and(|actual|Arc::ptr_eq(actual,code)){return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"original body token range/code owner differs")))}Ok(recipe)
    }
    /// Header-only current recipe: exact issued chunk/body span/header owner,
    /// without forcing or certifying a BODY Code identity/product.
    pub(super) fn original_header_recipe(&self,span:Span)->Result<CurrentBodyRecipe<'_>,dm_syntax::Diagnostic>{let recipe=self.original_body_recipe_using(span,None)?;if recipe.headers.is_none(){return Err(dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:"actual original header owner is unissued".into()})}Ok(recipe)}
    pub(crate) fn original_body_recipe_using<'a>(
        &'a self,
        span: Span,
        code: Option<&Arc<BodyCodeIdentity>>,
    ) -> Result<CurrentBodyRecipe<'a>, dm_syntax::Diagnostic> {
        let fail = |message: &str| dm_syntax::Diagnostic {
            span,
            kind: dm_syntax::DiagnosticKind::Unsupported,
            message: message.into(),
        };
        if !self.ordered_chunks {
            return Err(fail("original body token chunks are unordered"));
        }
        let index = self
            .chunks
            .partition_point(|c| c.offset <= span.start)
            .checked_sub(1)
            .ok_or_else(|| fail("original body token chunk missing"))?;
        let chunk = &self.chunks[index];
        let relative = Span::new(
            span.start
                .checked_sub(chunk.offset)
                .ok_or_else(|| fail("original body before chunk"))?,
            span.end
                .checked_sub(chunk.offset)
                .ok_or_else(|| fail("original body before chunk"))?,
        );
        let n = chunk
            .relative
            .bodies
            .partition_point(|b| b.span.start < relative.start);
        let body = chunk
            .relative
            .bodies
            .get(n)
            .filter(|b| b.span == relative && code.is_none_or(|code|chunk.relative.issued_body_code(n).is_some_and(|actual|Arc::ptr_eq(&actual,code))))
            .ok_or_else(|| fail("original body token range/code owner differs"))?;
        Ok(CurrentBodyRecipe {
            relative: body,relative_owner:&chunk.relative,ordinal:n,
            offset: chunk.offset,
            root_prefix: self.prefix[index],
            headers: chunk.relative.original_headers.as_ref(),
        })
    }
    // Header/reader DATA loans below are callable only through the existing
    // private current frontend/archive. They validate the SAME original chunk,
    // exact body span and actual Header owner, but certify no BODY product or
    // Code. Query/parser entrypoints above continue requiring actual Code.
    /// Borrow the existing producer resource owner for failure diagnostics.
    /// This lends no source grant and never constructs or reparses an Item.
    pub(crate) fn original_committed_products_for_trace(&self,span:Span)->Option<&Arc<super::committed_bodies::CommittedHeaderProducts>>{
        self.original_header_recipe(span).ok()?.headers?.committed_products()
    }
    pub(crate) fn original_committed_items_for_trace(&self,span:Span)->Option<&OriginalCommittedItems>{
        let recipe=self.original_header_recipe(span).ok()?;
        match &recipe.relative_owner.items{arena::Arena::Original{items,..}=>Some(items),_=>None}
    }
    pub(crate) fn original_body_tokens_header_only(&self,span:Span)->Result<crate::procedure::header_input::OriginalBodyTokens<'_>,String>{let recipe=self.original_header_recipe(span).map_err(|error|error.message)?;recipe.headers.ok_or("original body primary token owner unissued")?.body_tokens(recipe.relative.span,recipe.offset).map_err(str::to_owned)}
    pub(crate) fn original_formal_notice_rows_header_only<'a>(&'a self,span:Span)->Result<impl Iterator<Item=Result<(crate::OriginalFormalNotice,Option<&'a str>),String>>+'a,String>{
        let recipe=self.original_header_recipe(span).map_err(|error|error.message)?;let headers=recipe.headers.ok_or("actual original formal header owner unavailable")?;let offset=recipe.offset;let rows=headers.formal_notices_for(recipe.relative.span).map_err(str::to_owned)?;
        Ok(rows.map(move|notice|{let text=headers.formal_notice_text(notice).map_err(str::to_owned)?;let current=notice.checked_shift(offset).map_err(|error|error.to_string())?;Ok((current,text))}))
    }
    pub(crate) fn original_reader_commit_registration_header_only(&self,span:Span)->Result<Option<dm_preprocess::regions::OriginalNoticeRegistration>,String>{
        let recipe=self.original_header_recipe(span).map_err(|error|error.message)?;
        let headers=recipe.headers.ok_or("actual reader header owner unissued")?;
        headers.optional_reader_body_commit_registration(recipe.relative.span)
    }
    pub(crate) fn original_formal_notice_registration_rows_header_only<'a>(&'a self,span:Span)->Result<impl Iterator<Item=Result<(crate::OriginalFormalNotice,Option<&'a str>,Option<dm_preprocess::regions::OriginalNoticeRegistration>),String>>+'a,String>{
        let recipe=self.original_header_recipe(span).map_err(|error|error.message)?;let headers=recipe.headers.ok_or("actual original formal header owner unavailable")?;let offset=recipe.offset;let rows=headers.formal_notices_for(recipe.relative.span).map_err(str::to_owned)?;
        Ok(rows.map(move|notice|{let text=headers.formal_notice_text(notice).map_err(str::to_owned)?;let registration=headers.optional_formal_notice_registration(notice).map_err(str::to_owned)?.cloned();let current=notice.checked_shift(offset).map_err(|error|error.to_string())?;Ok((current,text,registration))}))
    }
    pub(super) fn requires_admitted_original_header_parameters_header_only(
      &self,span:Span,
    )->Result<bool,BodySyntaxFailure>{
      let recipe=self.original_header_recipe(span).map_err(|error|internal(&error.message))?;
      let headers=recipe.headers.ok_or_else(||internal("actual parameter header owner is unissued"))?;
      Ok(headers.lazy_body_parameters())
    }
    pub(super) fn original_header_parameters_header_only<'a>(&'a self,span:Span)->Result<(&'a dm_syntax::SharedParameterSignature,dm_syntax::SyntaxProjection),dm_syntax::Diagnostic>{
      let recipe=self.original_header_recipe(span)?;
      let fail=|message:&str|dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:message.into()};
      let headers=recipe.headers.ok_or_else(||fail("actual parameter header owner is unissued"))?;
      let parameters=headers.parameter_signature(recipe.relative.span).map_err(fail)?;
      let original=Span::new(0,headers.abi_source_len());let current=recipe.source_window().map_err(fail)?;
      let projection=dm_syntax::SyntaxProjection::new(original,current).map_err(|_|fail("actual parameter source projection differs"))?;
      Ok((parameters,projection))
    }
    pub(super) fn with_original_header_parameters_admitted_header_only<T>(
      &self, span: Span, a: &dm_syntax::SettingAdmission<'_>,
      consume: impl FnOnce(&dm_syntax::ParameterSignature,dm_syntax::SyntaxProjection)->Result<T,BodySyntaxFailure>,
    )->Result<T,BodySyntaxFailure>{
      let recipe=self.original_header_recipe(span).map_err(|error|internal(&error.message))?;
      let headers=recipe.headers.ok_or_else(||internal("actual parameter header owner is unissued"))?;
      let parameters=headers.parameter_signature_admitted(recipe.relative.span,a).map_err(BodySyntaxFailure::Operational)?;
      let original=Span::new(0,headers.abi_source_len());
      let current=recipe.source_window().map_err(internal)?;
      let projection=dm_syntax::SyntaxProjection::new(original,current).map_err(|_|internal("actual parameter source projection differs"))?;
      consume(&parameters,projection)
    }
    pub(crate) fn original_callable_opening_header_only(&self,span:Span)->Result<usize,String>{
        let recipe=self.original_header_recipe(span).map_err(|e|e.message)?;
        let input=recipe.headers.ok_or("callable header original token input unissued")?;
        input.callable_opening(recipe.relative.span,recipe.offset)
    }
    pub(crate) fn original_body_tokens(&self,span:Span,code:&Arc<BodyCodeIdentity>)->Result<crate::procedure::header_input::OriginalBodyTokens<'_>,String>{let recipe=self.original_body_recipe(span,code).map_err(|error|error.message)?;recipe.headers.ok_or("original body primary token owner unissued")?.body_tokens(recipe.relative.span,recipe.offset).map_err(str::to_owned)}
    pub(crate) fn original_formal_notice_rows<'a>(&'a self,span:Span,code:&Arc<BodyCodeIdentity>)->Result<impl Iterator<Item=Result<(crate::OriginalFormalNotice,Option<&'a str>),String>>+'a,String>{
        let recipe=self.original_body_recipe(span,code).map_err(|error|error.message)?;let headers=recipe.headers.ok_or("actual original formal header owner unavailable")?;let offset=recipe.offset;let rows=headers.formal_notices_for(recipe.relative.span).map_err(str::to_owned)?;
        Ok(rows.map(move|notice|{let text=headers.formal_notice_text(notice).map_err(str::to_owned)?;let current=notice.checked_shift(offset).map_err(|error|error.to_string())?;Ok((current,text))}))
    }
    pub(crate) fn original_reader_commit_registration(&self,span:Span,code:&Arc<BodyCodeIdentity>)->Result<Option<dm_preprocess::regions::OriginalNoticeRegistration>,String>{
        let recipe=self.original_body_recipe(span,code).map_err(|error|error.message)?;
        let headers=recipe.headers.ok_or("actual reader header owner unissued")?;
        headers.optional_reader_body_commit_registration(recipe.relative.span)
    }
    pub(crate) fn original_reader_end_registration(&self)->Result<Option<dm_preprocess::regions::OriginalNoticeRegistration>,String>{self.original_reader_frontier_using(false)}
    pub(crate) fn original_parser_reader_frontier_registration(&self)->Result<Option<dm_preprocess::regions::OriginalNoticeRegistration>,String>{self.original_reader_frontier_using(true)}
    fn original_reader_frontier_using(&self,parser_frontier:bool)->Result<Option<dm_preprocess::regions::OriginalNoticeRegistration>,String>{
        let mut end:Option<dm_preprocess::regions::OriginalNoticeRegistration>=None;let mut absent=false;
        for chunk in self.chunks.iter(){
            let Some(headers)=chunk.relative.original_headers.as_ref() else{absent=true;continue};
            let current=if parser_frontier{headers.optional_parser_reader_frontier_registration()}else{headers.optional_reader_end_registration()?};let Some(current)=current else{absent=true;continue};
            if let Some(previous)=&end{if previous.compare_same_source(&current).map_err(|error|error.to_string())?==std::cmp::Ordering::Greater{return Err("actual reader end registrations are not monotone".into())}}
            end=Some(current);
        }
        if absent&&end.is_some(){return Err("actual reader end registration coverage is partial".into())}Ok(end)
    }
    pub(crate) fn original_formal_notice_registration_rows<'a>(&'a self,span:Span,code:&Arc<BodyCodeIdentity>)->Result<impl Iterator<Item=Result<(crate::OriginalFormalNotice,Option<&'a str>,Option<dm_preprocess::regions::OriginalNoticeRegistration>),String>>+'a,String>{
        let recipe=self.original_body_recipe(span,code).map_err(|error|error.message)?;let headers=recipe.headers.ok_or("actual original formal header owner unavailable")?;let offset=recipe.offset;let rows=headers.formal_notices_for(recipe.relative.span).map_err(str::to_owned)?;
        Ok(rows.map(move|notice|{let text=headers.formal_notice_text(notice).map_err(str::to_owned)?;let registration=headers.optional_formal_notice_registration(notice).map_err(str::to_owned)?.cloned();let current=notice.checked_shift(offset).map_err(|error|error.to_string())?;Ok((current,text,registration))}))
    }
    pub(super) fn requires_admitted_original_header_parameters(
      &self,span:Span,code:&Arc<BodyCodeIdentity>,
    )->Result<bool,BodySyntaxFailure>{
      let recipe=self.original_body_recipe(span,code).map_err(|error|internal(&error.message))?;
      let headers=recipe.headers.ok_or_else(||internal("actual parameter header owner is unissued"))?;
      Ok(headers.lazy_body_parameters())
    }
    pub(super) fn original_header_parameters<'a>(&'a self,span:Span,code:&Arc<BodyCodeIdentity>)->Result<(&'a dm_syntax::SharedParameterSignature,dm_syntax::SyntaxProjection),dm_syntax::Diagnostic>{
      let recipe=self.original_body_recipe(span,code)?;
      let fail=|message:&str|dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:message.into()};
      let headers=recipe.headers.ok_or_else(||fail("actual parameter header owner is unissued"))?;
      let parameters=headers.parameter_signature(recipe.relative.span).map_err(fail)?;
      let original=Span::new(0,headers.abi_source_len());let current=recipe.source_window().map_err(fail)?;
      let projection=dm_syntax::SyntaxProjection::new(original,current).map_err(|_|fail("actual parameter source projection differs"))?;
      Ok((parameters,projection))
    }
    pub(super) fn with_original_header_parameters_admitted<T>(
      &self, span: Span, code: &Arc<BodyCodeIdentity>, a: &dm_syntax::SettingAdmission<'_>,
      consume: impl FnOnce(&dm_syntax::ParameterSignature,dm_syntax::SyntaxProjection)->Result<T,BodySyntaxFailure>,
    )->Result<T,BodySyntaxFailure>{
      let recipe=self.original_body_recipe(span,code).map_err(|error|internal(&error.message))?;
      let headers=recipe.headers.ok_or_else(||internal("actual parameter header owner is unissued"))?;
      let parameters=headers.parameter_signature_admitted(recipe.relative.span,a).map_err(BodySyntaxFailure::Operational)?;
      let original=Span::new(0,headers.abi_source_len());
      let current=recipe.source_window().map_err(internal)?;
      let projection=dm_syntax::SyntaxProjection::new(original,current).map_err(|_|internal("actual parameter source projection differs"))?;
      consume(&parameters,projection)
    }
    pub(crate) fn original_callable_opening(&self,span:Span,code:&Arc<BodyCodeIdentity>)->Result<usize,String>{
        let recipe=self.original_body_recipe(span,code).map_err(|e|e.message)?;
        let input=recipe.headers.ok_or("callable header original token input unissued")?;
        input.callable_opening(recipe.relative.span,recipe.offset)
    }
    pub(crate) fn parse_original_procedure(
        &self,
        span: Span,
        code: &Arc<BodyCodeIdentity>,
    ) -> Result<dm_syntax::ProcedureWithOrigins, dm_syntax::Diagnostic> {
        let recipe = self.original_body_recipe(span, code)?;
        recipe.parse_original()
    }
    /// Authenticate original current source inputs without demanding any body or
    /// setting expression grammar. The native frontend still validates its
    /// actual occurrence and selected runtime metadata before using this seam.
    pub(super) fn abi_root_owner<'a>(&'a self,span:Span,code:&Arc<BodyCodeIdentity>)->Result<(&'a Arc<crate::procedure::OriginalProcedureHeaders>,Span),dm_syntax::Diagnostic>{let recipe=self.original_body_recipe(span,code)?;recipe.headers.map(|owner|(owner,recipe.relative.span)).ok_or_else(||dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:"ABI original header owner unavailable".into()})}
    pub(super) fn cached_abi_root(&self,span:Span,code:&Arc<BodyCodeIdentity>,ordinal:usize,count:usize,returns:bool,a:&dm_syntax::SettingAdmission<'_>)->Result<dm_syntax::SettingExpression,dm_syntax::SettingSyntaxFailure>{
      let recipe=self.original_body_recipe(span,code).map_err(dm_syntax::SettingSyntaxFailure::Syntax)?;
      let fail=|message:&str|dm_syntax::SettingSyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,message));
      let headers=recipe.headers.ok_or_else(||fail("ABI original header owner unavailable"))?;let owner=recipe.relative.settings_owner.as_ref().ok_or_else(||fail("ABI original metadata owner unavailable"))?;
      let root=headers.cached_abi_root(recipe.relative.span,owner,ordinal,count,returns,a)?;
      root.project_current(recipe.offset,headers.abi_source_len()).map_err(dm_syntax::SettingSyntaxFailure::Operational)
    }
    pub(crate) fn original_body_expression(&self,body:Span,code:&Arc<BodyCodeIdentity>,source:&str,offset:usize,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Option<dm_syntax::ParsedExpr>>{
      self.original_body_expression_with_native_facts(body,code,source,offset,a).map(|value|value.map(|(parsed,_)|parsed))
    }
    pub(crate) fn original_body_expression_with_native_facts(&self,body:Span,code:&Arc<BodyCodeIdentity>,source:&str,offset:usize,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Option<(dm_syntax::ParsedExpr,Option<dm_syntax::NativeExpressionParserFacts>)>>{
      let recipe=self.original_body_recipe_checked(body,code).map_err(|error|match error{BodySyntaxFailure::Operational(actual)=>actual,BodySyntaxFailure::Syntax(source)=>std::io::Error::new(std::io::ErrorKind::InvalidData,source.message)})?;
      let original=offset.checked_sub(recipe.offset).ok_or(std::io::ErrorKind::InvalidInput)?;
      let headers=recipe.headers.ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"original BODY expression header owner is unissued"))?;
      headers.original_body_expression_with_native_facts(source,original,a)
    }
    pub(crate) fn setting_token_input<'a>(
        &'a self,
        span: Span,
        code: &Arc<BodyCodeIdentity>,
        ordinal: usize,
    ) -> Result<OriginalSettingTokenInput<'a>, dm_syntax::Diagnostic> {
        let recipe = self.original_body_recipe(span, code)?;
        let fail = |message: &str| dm_syntax::Diagnostic {
            span,
            kind: dm_syntax::DiagnosticKind::Unsupported,
            message: message.into(),
        };
        let input = recipe
            .headers
            .ok_or_else(|| fail("original setting token owner unavailable"))?;
        let owner = recipe
            .relative
            .settings_owner
            .as_ref()
            .ok_or_else(|| fail("original setting metadata owner unavailable"))?;
        let footprint = recipe
            .relative
            .setting_footprints
            .as_ref()
            .and_then(|rows| rows.get(ordinal))
            .ok_or_else(|| fail("original setting footprint ordinal unavailable"))?;
        let (source, tokens) = input
            .setting_value_tokens(recipe.relative.span, owner, footprint)
            .map_err(|message| fail(&message))?;
        let slots = input
            .setting_root_slots(recipe.relative.span, owner, footprint)
            .map_err(|message| fail(&message))?;
        let header = Span::new(
            footprint.header.start + recipe.offset,
            footprint.header.end + recipe.offset,
        );
        let value = Span::new(
            footprint.value.start + recipe.offset,
            footprint.value.end + recipe.offset,
        );
        Ok(OriginalSettingTokenInput {
            literal_owner:input,
            source,
            tokens,
            original_owner: owner,
            ordinal,
            header,
            value,
            offset: recipe.offset,
            slots,
            original_value: footprint.value,
        })
    }
    pub(crate) fn return_annotation_token_input<'a>(
        &'a self,
        span: Span,
        code: &Arc<BodyCodeIdentity>,
        fragment: &dm_ir::SymbolicExpression,
        selected: &dm_ir::ProcedureMetadata,
        symbols: &dm_ir::SymbolTable,
    ) -> Result<OriginalReturnTokenInput<'a>, dm_syntax::Diagnostic> {
        let recipe = self.original_body_recipe(span, code)?;
        let fail = |message: String| dm_syntax::Diagnostic {
            span,
            kind: dm_syntax::DiagnosticKind::Unsupported,
            message,
        };
        let headers = recipe
            .headers
            .ok_or_else(|| fail("original return token owner unavailable".into()))?;
        let owner = recipe
            .relative
            .settings_owner
            .as_ref()
            .ok_or_else(|| fail("original return metadata owner unavailable".into()))?;
        if owner.signature.return_annotation != selected.signature.return_annotation {
            return Err(fail(
                "selected return annotation differs from original metadata".into(),
            ));
        }
        let (source, tokens, value, ordinal, count, slots) = headers
            .return_fragment(recipe.relative.span, owner, fragment, symbols)
            .map_err(fail)?;
        Ok(OriginalReturnTokenInput {
            literal_owner:headers,
            source,
            tokens,
            original_value: value,
            ordinal,
            count,
            slots,
            offset: recipe.offset,
        })
    }
    fn initializer_token_source<'a>(&'a self,cursor:usize)->Result<(&'a Arc<crate::procedure::OriginalProcedureHeaders>,Span,ItemKind,usize,usize,usize),String>{
        fn search<'a>(chunk: &'a CurrentSyntaxChunk, cursor: usize) -> Option<ItemView<'a>> {
            // Existing immutable arena coordinates only. Deep declaration
            // nesting consumes no recursive stack, allocation or second index.
            let mut parent: Option<ItemView<'a>> = None;
            loop {
                let len = parent.map_or_else(|| chunk.len(), |node| node.children().len());
                let get = |i| parent.map_or_else(|| chunk.item(i), |node| node.child(i));
                let (mut low, mut high) = (0, len);
                while low < high {
                    let mid = low + (high - low) / 2;
                    if get(mid)?.header_span().start <= cursor {
                        low = mid + 1
                    } else {
                        high = mid
                    }
                }
                let node = get(low.checked_sub(1)?)?;
                // A no-RHS declaration is issued at its actual terminator,
                // which may lie at or beyond the textual header end. Exact
                // primary cursor identity covers that case without admitting
                // an arbitrary point outside the original header.
                if node.declaration_cursor() == Some(cursor)
                    || (node.header_span().start <= cursor && cursor < node.header_span().end)
                {
                    return Some(node);
                }
                // The last child's genuine terminator may equal its ancestor's
                // textual extent. Descend at equality; only the leaf's exact
                // issued declaration_cursor can authorize that boundary.
                if cursor > node.span().end
                    || !matches!(node.kind(), ItemKind::Type | ItemKind::Var)
                {
                    return None;
                }
                parent = Some(node);
            }
        }
        if !self.ordered_chunks {
            return Err("original initializer chunks unordered".into());
        }
        let index = self
            .chunks
            .partition_point(|c| c.offset <= cursor)
            .checked_sub(1)
            .ok_or("original initializer chunk unavailable")?;
        let chunk = &self.chunks[index];
        let node = search(chunk, cursor).ok_or("original initializer declaration unavailable")?;
        if node.declaration_cursor() != Some(cursor)
            || !matches!(
                node.kind(),
                ItemKind::Var | ItemKind::Unknown | ItemKind::Statement
            )
        {
            return Err("initializer has no original primary variable declaration node".into());
        }
        let headers = chunk
            .relative
            .original_headers
            .as_ref()
            .ok_or("original initializer token owner unavailable")?;
        let (ordinal,count)=match node.item.root_slot(){
            Some(fallback)=>headers.initializer_slot_coordinate(node.item.header_span(),fallback)?,
            None if node.item.is_original()=>headers.required_initializer_slot_coordinate(node.item.header_span())?,
            None=>return Err("initializer primary arena coordinate is unissued".into()),
        };
        Ok((headers,node.item.header_span(),node.kind(),ordinal,count,chunk.offset))
    }
    pub(crate) fn initializer_dimension_cursor(&self,cursor:usize)->Result<OriginalInitializerDimensionTokens<'_>,String>{
        let (owner,header,_,ordinal,count,offset)=self.initializer_token_source(cursor)?;
        Ok(OriginalInitializerDimensionTokens{owner,views:owner.initializer_dimension_views(header)?,ordinal,count,offset,next:0,finished:false})
    }
    /// None proves an actual original primary header with no authored RHS.
    /// Source/token/metadata failures remain Err and cannot trigger inheritance.
    pub(crate) fn initializer_constant_location(&self,cursor:usize)->Result<usize,String>{let(headers,header,_,_,_,offset)=self.initializer_token_source(cursor)?;match headers.initializer_assignment_token(header)?{Some(token)=>token.start.checked_add(offset).ok_or_else(||"initializer saved token coordinate overflow".into()),None=>Ok(cursor)}}
    pub(crate) fn initializer_has_authored_value(&self,cursor:usize)->Result<bool,String>{let(headers,header,kind,_,_,_)=self.initializer_token_source(cursor)?;headers.has_authored_initializer(header,kind==ItemKind::Var)}
    pub(crate) fn initializer_token_input_if_authored<'a>(&'a self,cursor:usize,expression:&dm_ir::SymbolicExpression,symbols:&dm_ir::SymbolTable)->Result<Option<OriginalInitializerTokenInput<'a>>,String>{
        let(headers,header,kind,_,_,_)=self.initializer_token_source(cursor)?;
        if !headers.has_authored_initializer(header,kind==ItemKind::Var)?{return Ok(None)}
        self.initializer_token_input(cursor,expression,symbols).map(Some)
    }
    pub(crate) fn initializer_token_input<'a>(&'a self,cursor:usize,expression:&dm_ir::SymbolicExpression,symbols:&dm_ir::SymbolTable)->Result<OriginalInitializerTokenInput<'a>,String>{self.initializer_token_input_inner(cursor,expression,symbols,None)}
    pub(crate) fn initializer_dimension_token_input<'a>(&'a self,cursor:usize,index:usize,count:usize,expression:&dm_ir::SymbolicExpression,symbols:&dm_ir::SymbolTable)->Result<OriginalInitializerTokenInput<'a>,String>{self.initializer_token_input_inner(cursor,expression,symbols,Some((index,count)))}
    fn initializer_token_input_inner<'a>(
        &'a self,
        cursor: usize,
        expression: &dm_ir::SymbolicExpression,
        symbols: &dm_ir::SymbolTable,
        dimension:Option<(usize,usize)>,
    ) -> Result<OriginalInitializerTokenInput<'a>, String> {
        let (headers,header,kind,ordinal,count,offset)=self.initializer_token_source(cursor)?;
        let (source,tokens,value)=match dimension{
          Some((index,count))=>headers.initializer_dimension_tokens(header,index,count,expression,symbols)?,
          None=>headers.initializer_tokens(header,kind==ItemKind::Var,expression,symbols)?,
        };
        Ok(OriginalInitializerTokenInput {
            dimension:dimension.is_some(),
            dimension_index:dimension.map_or(0,|pair|pair.0),
            dimension_count:dimension.map_or(0,|pair|pair.1),
            owner: headers,
            source,
            tokens,
            value,
            ordinal,
            count,
            offset,
            slots: headers.initializer_slots(),
        })
    }
    /// Called only by the original native body parser under its SAME stack
    /// admission. No host/query/gate/revision call occurs at this leaf.
    pub(crate) fn setting_statement_expression_with_native_observation(
        &self,
        body: Span,
        code: &Arc<BodyCodeIdentity>,
        statement: &Item,
        admission: &dm_syntax::SettingAdmission<'_>,
    ) -> Result<(String,String,dm_syntax::SettingExpression,Option<dm_syntax::NativeExpressionParserFacts>),dm_syntax::SettingSyntaxFailure>
    {
        let syntax = |message: &str| {
            dm_syntax::SettingSyntaxFailure::Syntax(dm_syntax::Diagnostic {
                span: statement.header_span,
                kind: dm_syntax::DiagnosticKind::Unsupported,
                message: message.into(),
            })
        };
        let recipe = self
            .original_body_recipe(body, code)
            .map_err(dm_syntax::SettingSyntaxFailure::Syntax)?;
        let headers = recipe
            .setting_headers()
            .ok_or_else(|| syntax("original setting header owner unavailable"))?;
        let owner = recipe
            .relative
            .settings_owner
            .as_ref()
            .ok_or_else(|| syntax("original setting metadata owner unavailable"))?;
        let footprints = recipe
            .setting_footprints()
            .ok_or_else(|| syntax("original setting footprint roster unavailable"))?;
        let offset = recipe.offset();
        let start = statement
            .header_span
            .start
            .checked_sub(offset)
            .ok_or_else(|| syntax("setting statement precedes original chunk"))?;
        let end = statement
            .header_span
            .end
            .checked_sub(offset)
            .ok_or_else(|| syntax("setting statement ends before original chunk"))?;
        let footprint = footprints
            .binary_search_by_key(&start, |row| row.header.start)
            .ok()
            .and_then(|i| footprints.get(i))
            .filter(|row| row.header == Span::new(start, end))
            .ok_or_else(|| syntax("setting statement has no exact original directive footprint"))?;
        let (source, tokens) = headers
            .setting_value_tokens(recipe.original_body_span(), owner, footprint)
            .map_err(|e| syntax(&e))?;
        if source.get(footprint.header.range()) != Some(statement.header.as_str()) {
            return Err(syntax(
                "setting statement text differs from its original token owner",
            ));
        }
        let (attribute, relation) = headers
            .setting_statement_parts(recipe.original_body_span(), owner, footprint)
            .map_err(|e| syntax(&e))?;
        let slots = headers
            .setting_root_slots(recipe.original_body_span(), owner, footprint)
            .map_err(|e| syntax(&e))?;
        let(original,native) = slots
            .obtain_with_native_observation(footprint.ordinal, owner.settings.len(), admission, || {
                tokens.with_dense_using(admission,|dense|Ok(dm_syntax::prepare_setting_expression_with_original_literal_facts_and_native_observation(source,dense,footprint.value,admission,headers.original_literal_facts()?))).map_err(dm_syntax::SettingSyntaxFailure::Operational)?
            })
            .map_err(|failure| match failure {
                dm_syntax::SettingSyntaxFailure::Syntax(mut error) => {
                    let projected = error
                        .span
                        .start
                        .checked_add(offset)
                        .zip(error.span.end.checked_add(offset));
                    if let Some((start, end)) = projected {
                        error.span = Span::new(start, end);
                        dm_syntax::SettingSyntaxFailure::Syntax(error)
                    } else {
                        admission.record_operational_error(std::io::Error::new(
                            std::io::ErrorKind::InvalidInput,
                            "setting syntax error projection overflow",
                        ));
                        dm_syntax::SettingSyntaxFailure::Operational(
                            std::io::ErrorKind::InvalidInput.into(),
                        )
                    }
                }
                other => other,
            })?;
        let current = original
            .project_current(offset, source.len())
            .map_err(dm_syntax::SettingSyntaxFailure::Operational)?;
        Ok((attribute.to_owned(),relation.to_owned(),current,native))
    }
    pub(crate) fn ordinary_code_demand(&self)->bool{!self.chunks.is_empty()&&self.chunks.iter().all(|chunk|chunk.relative.ordinary_code_demand())}
    pub(crate) fn body_recipes(&self) -> impl Iterator<Item = CurrentBodyRecipe<'_>> {
        self.chunks
            .iter()
            .zip(self.prefix.iter())
            .flat_map(|(chunk, &root_prefix)| {
                chunk
                    .relative
                    .bodies
                    .iter().enumerate()
                    .map(move |(ordinal,relative)| CurrentBodyRecipe {
                        relative,relative_owner:&chunk.relative,ordinal,
                        offset: chunk.offset,
                        root_prefix,
                        headers: chunk.relative.original_headers.as_ref(),
                    })
            })
    }
    pub(crate) fn new(chunks: Vec<CurrentSyntaxChunk>) -> Result<Self, BindingError> {
        // Public compatibility binding may supply unsorted/overlapping chunks.
        // Preserve iteration but decline coordinate authority for that topology.
        let ordered_chunks = chunks.windows(2).all(|pair| {
            pair[0]
                .offset
                .checked_add(pair[0].relative.source_len)
                .is_some_and(|end| end <= pair[1].offset)
        });
        let mut prefix = Vec::with_capacity(chunks.len());
        let mut len = 0usize;
        for chunk in &chunks {
            prefix.push(len);
            len = len
                .checked_add(chunk.len())
                .ok_or(BindingError::OffsetOverflow)?;
        }
        Ok(Self {
            chunks: chunks.into(),
            prefix: prefix.into(),
            len,
            ordered_chunks,
        })
    }
    pub(super) fn first_original_outer_block_using<E>(&self,checkpoint:&dyn Fn()->Result<(),E>)->Result<Result<Option<usize>,&'static str>,E>{
     let mut first=None;for chunk in self.chunks.iter(){checkpoint()?;let Some(headers)=chunk.relative.original_headers.as_ref()else{return Ok(Err("actual original declaration header owner absent"))};if let Some(at)=headers.first_outer_block(){let Some(at)=at.checked_add(chunk.offset)else{return Ok(Err("outer terminator current source projection overflow"))};first=Some(first.map_or(at,|old:usize|old.min(at)));}}
     checkpoint()?;Ok(Ok(first))
    }
    pub fn chunks(&self) -> &Arc<[CurrentSyntaxChunk]> {
        &self.chunks
    }
    pub fn root_prefix(&self) -> &Arc<[usize]> {
        &self.prefix
    }
    pub fn len(&self) -> usize {
        self.len
    }
    pub fn is_empty(&self) -> bool {
        self.len == 0
    }
    pub fn item(&self, index: usize) -> Option<ItemView<'_>> {
        if index >= self.len {
            return None;
        }
        let chunk = self
            .prefix
            .partition_point(|&begin| begin <= index)
            .checked_sub(1)?;
        self.chunks[chunk].item(index - self.prefix[chunk])
    }
    pub fn item_path(&self, path: &[usize]) -> Option<ItemView<'_>> {
        let (&root, children) = path.split_first()?;
        let mut item = self.item(root)?;
        for &child in children {
            item = item.child(child)?;
        }
        Some(item)
    }
    pub fn items(&self) -> DeclarationItems<'_> {
        DeclarationItems {
            syntax: self,
            front: 0,
            back: self.len,
            front_chunk: 0,
            back_chunk: self.chunks.len().saturating_sub(1),
        }
    }
}
pub struct DeclarationItems<'a> {
    syntax: &'a DeclarationSyntax,
    front: usize,
    back: usize,
    front_chunk: usize,
    back_chunk: usize,
}
impl<'a> Iterator for DeclarationItems<'a> {
    type Item = ItemView<'a>;
    fn next(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        let index = self.front;
        self.front += 1;
        while self.syntax.prefix[self.front_chunk] + self.syntax.chunks[self.front_chunk].len()
            <= index
        {
            self.front_chunk += 1;
        }
        self.syntax.chunks[self.front_chunk].item(index - self.syntax.prefix[self.front_chunk])
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        let remaining = self.back - self.front;
        (remaining, Some(remaining))
    }
}
impl DoubleEndedIterator for DeclarationItems<'_> {
    fn next_back(&mut self) -> Option<Self::Item> {
        if self.front == self.back {
            return None;
        }
        self.back -= 1;
        while self.syntax.prefix[self.back_chunk] > self.back {
            self.back_chunk -= 1;
        }
        self.syntax.chunks[self.back_chunk].item(self.back - self.syntax.prefix[self.back_chunk])
    }
}
impl ExactSizeIterator for DeclarationItems<'_> {}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compact_views_preserve_setting_values_errors_and_current_coordinates() {
        for source in [
            "/proc/run()\n    if(1)\n        set waitfor = 0\n    else\n        set name = \"alternate\"\n",
            "/proc/run()\n    set waitfor = 0\n        return 1\n",
        ] {
            let parsed=dm_syntax::parse(source);
            let old=parsed.items.clone();
            let relative=Arc::new(RelativeSyntax::capture(parsed.items,source).unwrap());
            let current=relative.bind(source.len(),37).unwrap();
            let body=current.items().next().unwrap();
            let mut before=dm_ir::SymbolTable::default();
            let mut after=dm_ir::SymbolTable::default();
            assert_eq!(crate::settings::extract_settings(&old[0].children,&mut before),crate::settings::extract_settings_view(body,&mut after));
            assert_eq!(before.ordered(),after.ordered());
            assert_eq!(body.materialize_relative(),old[0]);
            assert_eq!(body.span().start,old[0].span.start+37);
            assert_eq!(body.header_span().start,old[0].header_span.start+37);
        }
    }
    #[test]
    fn borrowed_chunks_translate_nested_spans_and_keep_relative_nodes_shared() {
        let source = "/datum/example\n    var/value = 1\n    proc/read()\n        return value\n";
        let parsed = dm_syntax::parse(source);
        let original = parsed.items.clone();
        let relative = Arc::new(RelativeSyntax::capture(parsed.items, source).unwrap());
        let first = relative.bind(source.len(), 0).unwrap();
        let shifted = relative.bind(source.len(), 107).unwrap();
        assert!(Arc::ptr_eq(
            first.shared_relative(),
            shifted.shared_relative()
        ));
        let syntax = DeclarationSyntax::new(vec![first, shifted]).unwrap();
        assert_eq!(syntax.len(), 2);
        assert_eq!(
            syntax.item_path(&[1, 1]).unwrap().header(),
            original[0].children[1].header
        );
        let child = syntax.item_path(&[1, 1]).unwrap();
        assert_eq!(child.span().start, original[0].children[1].span.start + 107);
        assert_eq!(
            child.materialize().children[0].span.start,
            original[0].children[1].children[0].span.start + 107
        );
        assert_eq!(relative.materialize_relative_items(), original);
        assert!(syntax.item(2).is_none());
        assert!(syntax.item_path(&[1, 100]).is_none());
        let mut items = syntax.items();
        assert_eq!(items.next().unwrap().span().start, 0);
        assert_eq!(items.next_back().unwrap().span().start, 107);
        assert_eq!(items.len(), 0);
    }
    #[test]
    fn body_candidate_facts_rebind_without_rescanning_current_source() {
        let source = "/proc/plain()\n    return \"static\"\n/proc/stored()\n    var/static/value = 1\n    return value\n";
        let parsed = dm_syntax::parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty());
        let relative = Arc::new(RelativeSyntax::capture(parsed.items, source).unwrap());
        let syntax = DeclarationSyntax::new(vec![
            relative.bind(source.len(), 0).unwrap(),
            relative.bind(source.len(), 200).unwrap(),
        ])
        .unwrap();
        let candidates = syntax
            .body_recipes()
            .map(|recipe| recipe.stored_candidates())
            .collect::<Vec<_>>();
        assert_eq!(candidates, [false, true, false, true]);
    }
    #[test]
    fn body_recipes_share_syntax_and_rebind_paths_settings_and_coordinates() {
        let source = "/datum/example\n    proc/read()\n        set waitfor = 0\n        return 1\n/proc/other()\n    return 2\n";
        let parsed = dm_syntax::parse_declaration_skeleton(source);
        assert!(parsed.diagnostics.is_empty());
        let relative = Arc::new(RelativeSyntax::capture(parsed.items, source).unwrap());
        let syntax = DeclarationSyntax::new(vec![
            relative.bind(source.len(), 0).unwrap(),
            relative.bind(source.len(), 200).unwrap(),
        ])
        .unwrap();
        let recipes = syntax.body_recipes().collect::<Vec<_>>();
        assert_eq!(recipes.len(), 4);
        for recipe in &recipes {
            let path = recipe.path();
            let item = syntax.item_path(&path).unwrap();
            assert!(matches!(item.kind(), ItemKind::Proc | ItemKind::Verb));
            assert_eq!(recipe.span(), item.span());
        }
        assert_eq!(recipes[0].path().as_ref(), &[0, 0]);
        assert_eq!(recipes[2].path().as_ref(), &[2, 0]);
        let first = recipes[0].settings().collect::<Vec<_>>();
        let shifted = recipes[2].settings().collect::<Vec<_>>();
        assert_eq!(first.len(), 1);
        assert_eq!(shifted[0].start, first[0].start + 200);
        assert_eq!(shifted[0].end, first[0].end + 200);
        assert!(source[first[0].range()].contains("waitfor"));
        assert!(Arc::ptr_eq(
            syntax.chunks()[0].shared_relative(),
            syntax.chunks()[1].shared_relative()
        ));
    }
    #[test]
    fn bindings_reject_overflow_foreign_lengths_and_non_utf8_span_boundaries() {
        let source = "/datum/ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â©\n";
        let mut items = dm_syntax::parse_declaration_skeleton(source).items;
        let relative = Arc::new(RelativeSyntax::capture(items.clone(), source).unwrap());
        assert!(matches!(
            relative.bind(source.len(), usize::MAX),
            Err(BindingError::OffsetOverflow)
        ));
        assert!(matches!(
            relative.bind(source.len() + 1, 0),
            Err(BindingError::SourceLengthMismatch)
        ));
        items[0].header_span.end -= 1;
        assert!(matches!(
            RelativeSyntax::capture(items, source),
            Err(BindingError::InvalidRelativeSpan)
        ));
    }
    #[test]
    fn empty_chunks_do_not_change_global_root_ordinals() {
        let empty = Arc::new(RelativeSyntax::capture(vec![], "").unwrap());
        let source = "/datum/a\n";
        let nonempty = Arc::new(
            RelativeSyntax::capture(dm_syntax::parse_declaration_skeleton(source).items, source)
                .unwrap(),
        );
        let syntax = DeclarationSyntax::new(vec![
            empty.bind(0, 0).unwrap(),
            nonempty.bind(source.len(), 13).unwrap(),
            empty.bind(0, 20).unwrap(),
        ])
        .unwrap();
        assert_eq!(syntax.item(0).unwrap().span().start, 13);
        assert_eq!(syntax.items().count(), 1);
        let mut reversed = syntax.items();
        assert_eq!(reversed.next_back().unwrap().span().start, 13);
        assert!(reversed.next().is_none());
        let syntax = DeclarationSyntax::new(vec![
            empty.bind(0, 0).unwrap(),
            nonempty.bind(source.len(), 13).unwrap(),
            empty.bind(0, 20).unwrap(),
            nonempty.bind(source.len(), 27).unwrap(),
            empty.bind(0, 40).unwrap(),
            nonempty.bind(source.len(), 51).unwrap(),
            empty.bind(0, 80).unwrap(),
        ])
        .unwrap();
        let mut mixed = syntax.items();
        assert_eq!(mixed.next_back().unwrap().span().start, 51);
        assert_eq!(mixed.next().unwrap().span().start, 13);
        assert_eq!(mixed.next_back().unwrap().span().start, 27);
        assert!(mixed.next().is_none());
        assert!(mixed.next_back().is_none());
    }
}

#[cfg(test)]
mod header_lookup_tests {
    use super::*;
    #[test]
    fn issued_declaration_headers_exclude_executable_calls_and_rebind_chunks() {
        let source = "/datum/a\n    proc/run()\n        for(var/i=0; i<1; i++)\n            foo()\n        foo()\n    verb/act()\n        foo()\n/proc/top()\n    foo()\n/var/value=1\n";
        let parsed = dm_syntax::parse(source);
        let relative = Arc::new(RelativeSyntax::capture(parsed.items, source).unwrap());
        let shift = source.len() + 30;
        let syntax = DeclarationSyntax::new(vec![
            relative.bind(source.len(), 0).unwrap(),
            relative.bind(source.len(), shift).unwrap(),
        ])
        .unwrap();
        for base in [0, shift] {
            for (text, kind) in [
                ("/datum/a", ItemKind::Type),
                ("proc/run()", ItemKind::Proc),
                ("verb/act()", ItemKind::Verb),
                ("/proc/top()", ItemKind::Proc),
                ("/var/value", ItemKind::Var),
            ] {
                let offset = base + source.find(text).unwrap();
                assert_eq!(syntax.declaration_header_at(offset), Some(kind));
                assert_eq!(syntax.declaration_header_at(offset + 1), None);
            }
            for (offset, _) in source.match_indices("foo()") {
                assert_eq!(syntax.declaration_header_at(base + offset), None);
            }
            assert_eq!(
                syntax.declaration_header_at(base + source.find("for(").unwrap()),
                None
            );
        }
        assert_eq!(syntax.declaration_header_at(source.len() + 2), None);
        assert_eq!(syntax.declaration_header_at(usize::MAX), None);
    }
    #[test]
    fn foreign_chunk_topology_cannot_issue_header_context() {
        let source = "/proc/top()\n    return 1\n";
        let relative =
            Arc::new(RelativeSyntax::capture(dm_syntax::parse(source).items, source).unwrap());
        for offsets in [[40, 0], [0, 1]] {
            let syntax = DeclarationSyntax::new(
                offsets
                    .into_iter()
                    .map(|offset| relative.bind(source.len(), offset).unwrap())
                    .collect(),
            )
            .unwrap();
            for offset in offsets {
                assert_eq!(syntax.declaration_header_at(offset), None);
            }
        }
    }
    #[test]
    fn native_primary_headers_private_warm_queries_do_not_relex() {
        let source = "/datum/header\n    var/value = 1\n";
        let parsed = dm_syntax::parse_declaration_skeleton(source);
        let relative = Arc::new(RelativeSyntax::capture(parsed.items, source).unwrap());
        let syntax = DeclarationSyntax::new(vec![relative.bind(source.len(), 0).unwrap()]).unwrap();
        let at = source.find("var/value").unwrap();
        assert_eq!(syntax.declaration_cursor_at(at), source.find('='));
        assert_eq!(
            syntax.declaration_cursor_at_for_policy(at),
            source.find('=')
        );
        assert_eq!(relative.primary_header_reissues.load(Ordering::Relaxed), 0);
    }
    #[test]
    fn portable_primary_headers_cold_process_reissue_once_then_share() {
        const CHILD: &str = "DMB_PRIMARY_HEADER_REISSUE_CHILD";
        const SOURCE: &str = "/datum/header\n    var/value =\n        list(1,2)\n";
        if let Some(path) = std::env::var_os(CHILD) {
            // This fresh process has NEVER called the native declaration parser.
            let bytes = std::fs::read(path).unwrap();
            let (items, errors, _) =
                super::super::parserwire::decode_with_facts(&bytes, SOURCE).unwrap();
            assert!(errors.is_empty());
            let relative = Arc::new(RelativeSyntax::capture(items, SOURCE).unwrap());
            let syntax =
                DeclarationSyntax::new(vec![relative.bind(SOURCE.len(), 0).unwrap()]).unwrap();
            let at = SOURCE.find("var/value").unwrap();
            assert_eq!(
                syntax.declaration_cursor_at(at),
                None,
                "portable hints cannot self-certify"
            );
            assert_eq!(
                relative.primary_header_reissues.load(Ordering::Relaxed),
                0,
                "ordinary compile is unchanged"
            );
            assert_eq!(
                syntax.declaration_cursor_at_for_policy(at),
                SOURCE.find('=')
            );
            assert_eq!(relative.primary_header_reissues.load(Ordering::Relaxed), 1);
            let shifted =
                DeclarationSyntax::new(vec![relative.bind(SOURCE.len(), 91).unwrap()]).unwrap();
            assert_eq!(
                shifted.declaration_cursor_at_for_policy(at + 91),
                SOURCE.find('=').map(|at| at + 91)
            );
            assert_eq!(
                syntax.declaration_cursor_at(at),
                SOURCE.find('='),
                "subsequent compile shares the same native fact"
            );
            assert_eq!(
                relative.primary_header_reissues.load(Ordering::Relaxed),
                1,
                "no second primary token pass"
            );
            let headers = relative.primary_headers(false).unwrap();
            let pointer = headers.as_ptr() as usize;
            let bytes = std::mem::size_of_val(headers.as_ref());
            let mut charged = false;
            relative.visit_body_storage(|p, _, capacity| {
                if p == pointer {
                    assert_eq!(capacity, bytes);
                    charged = true;
                }
            });
            assert!(charged, "lazy source fact backing is included in census");
            return;
        }
        let path = header_test_scratch::dir("primary-header-cold-process").join("declarations.bin");
        let parsed = dm_syntax::parse_declaration_skeleton(SOURCE);
        assert!(parsed.diagnostics.is_empty());
        let encoded =
            super::super::parserwire::encode_with_facts(&parsed.items, &[], 0, None).unwrap();
        std::fs::write(&path, encoded).unwrap();
        drop(parsed);
        let status=std::process::Command::new(std::env::current_exe().unwrap())
            .arg("--exact").arg("frontend::relative_declarations::tests::portable_primary_headers_cold_process_reissue_once_then_share")
            .arg("--nocapture").env(CHILD,&path).status().unwrap();
        assert!(status.success());
    }
}

#[cfg(test)]
mod primary_qualifier_roundtrip_tests {
    use super::*;
    #[test]
    fn cold_and_portable_shared_header_facts_preserve_scoped_qualifiers() {
        let source = "/datum/owner\n    var/SpacemanDMM_private/\n        datum/value = null\n        plain\n    var/SpacemanDMM_protected/other\n    var/SpacemanDMM_private\n";
        let parsed = dm_syntax::parse(source);
        assert!(parsed.diagnostics.is_empty());
        let encoded =
            super::super::parserwire::encode_with_facts(&parsed.items, &[], 0, None).unwrap();
        let cold = Arc::new(RelativeSyntax::capture(parsed.items, source).unwrap());
        let (portable, errors, _) =
            super::super::parserwire::decode_with_facts(&encoded, source).unwrap();
        assert!(errors.is_empty());
        let warm = Arc::new(RelativeSyntax::capture(portable, source).unwrap());
        assert!(
            warm.primary_headers(false).is_none(),
            "portable qualifier/cursor hints cannot seed an issued roster"
        );
        assert_eq!(warm.primary_header_reissues.load(Ordering::Relaxed), 0);

        let cold_syntax =
            DeclarationSyntax::new(vec![cold.bind(source.len(), 0).unwrap()]).unwrap();
        let warm_syntax =
            DeclarationSyntax::new(vec![warm.bind(source.len(), 0).unwrap()]).unwrap();
        for (header, flags) in [
            ("datum/value", dm_syntax::CHECKER_VAR_PRIVATE),
            ("plain", dm_syntax::CHECKER_VAR_PRIVATE),
            (
                "var/SpacemanDMM_protected/other",
                dm_syntax::CHECKER_VAR_PROTECTED,
            ),
            ("var/SpacemanDMM_private\n", 0),
        ] {
            let at = source.find(header).unwrap();
            assert_eq!(
                cold_syntax.declaration_checker_qualifiers_at_for_policy(at),
                Some(flags)
            );
            assert_eq!(
                warm_syntax.declaration_checker_qualifiers_at_for_policy(at),
                Some(flags)
            );
        }
        assert_eq!(cold.primary_header_reissues.load(Ordering::Relaxed), 0);
        assert_eq!(warm.primary_header_reissues.load(Ordering::Relaxed), 1);
        let (_, count, bytes) = (
            0usize,
            warm.primary_headers(true).unwrap().len(),
            std::mem::size_of_val(warm.primary_headers(true).unwrap().as_ref()),
        );
        assert!(count > 0 && bytes > 0);
    }
}

#[cfg(test)]
mod original_setting_context_roster_tests {
    use super::*;
    #[test]
    fn original_footprints_preserve_all_context_headers_including_zero_setting_bodies() {
        for source in [
   "/proc/check()\n    if(1)\n        set waitfor = 0\n    else\n        return 1\n    return 2\n",
   "/proc/check()\n    if(1)\n        return 1\n    else\n        return 2\n",
  ]{
   // Full structural primary input retains executable context headers;
   // the skeleton producer intentionally compacts them. No Expr/body parser.
   let parsed=dm_syntax::parse(source);assert!(parsed.diagnostics.is_empty());
   let input=crate::procedure::OriginalProcedureHeaders::from_primary(source.to_owned().into(),&parsed.items,0,parsed.tokens.into_iter().map(|token| dm_syntax::SpanToken { kind: token.kind, span: token.span }).collect()).unwrap();
   let ast=dm_syntax::AstFile{items:parsed.items,..Default::default()};
   let (facts,_receipt)=crate::adapter::from_ast_with_source_headers(&ast,dm_ir::SymbolTable::default(),dm_ir::FileId(0),0,0,source,&input,0).unwrap();
   let mut owners=std::collections::BTreeMap::new();
   for (fact,origin) in facts.skeletons.iter().zip(&facts.origins){if let crate::Skeleton::Member{metadata,..}=fact{if let Some(owner)=metadata.procedure.as_ref(){owners.insert(origin.span.start as usize,owner.clone());}}}
   let mut expected=Vec::new();crate::settings::setting_spans(&ast.items[0].children,&mut expected);
   let relative=RelativeSyntax::capture_with_settings_headers(ast.items.clone(),{let mut value=None;input.visit_source(|source|value=Some(source.clone()));value.unwrap()},&owners,Some(input.clone())).unwrap();
   let body=&relative.bodies[0];let recipe=CurrentBodyRecipe{relative:body,relative_owner:&relative,ordinal:0,offset:0,root_prefix:0,headers:Some(&input)};
   assert_eq!(recipe.settings().collect::<Vec<_>>(),expected);assert!(expected.len()>1);
   if body.settings_owner.as_ref().unwrap().settings.is_empty(){assert!(recipe.setting_footprints().is_none());assert!(!recipe.settings().collect::<Vec<_>>().is_empty());}
  }
    }
}

#[cfg(test)]
mod callable_namespace_recipe_tests {
    use super::*;
    #[test]
    fn relative_callable_recipe_binds_real_leaf_below_final_namespace() {
        for source in [
            "/datum/flags\n    proc/final\n        probe()\n            set SpacemanDMM_should_not_override = 1\n",
            "/datum/flags\n    proc\n        final\n            probe()\n                set SpacemanDMM_should_not_override = 1\n",
            "/datum/flags\n    verb\n        present()\n            set name = \"Present\"\n",
        ] {
            let parsed = dm_syntax::parse_declaration_skeleton(source);
            assert!(parsed.diagnostics.is_empty(), "{source:?}");
            let text: dm_preprocess::SourceText = Arc::<str>::from(source).into();
            let headers = crate::procedure::OriginalProcedureHeaders::from_primary(
                text.clone(), &parsed.items, 0, parsed.tokens,
            ).unwrap();
            // Exercise the same adapter that issues the actual metadata owner.
            // The original-header recipe deliberately rejects an empty owners map.
            let ast=dm_syntax::AstFile{items:parsed.items,..Default::default()};
            let (facts,_receipt)=crate::adapter::from_ast_with_source_headers(
                &ast,dm_ir::SymbolTable::default(),dm_ir::FileId(0),0,0,source,&headers,0,
            ).unwrap();
            let mut owners=std::collections::BTreeMap::new();
            for(fact,origin)in facts.skeletons.iter().zip(&facts.origins){
                if let crate::Skeleton::Member{metadata,..}=fact{
                    if let Some(owner)=metadata.procedure.as_ref(){owners.insert(origin.span.start as usize,owner.clone());}
                }
            }
            let relative = Arc::new(RelativeSyntax::capture_with_settings_headers(
                ast.items, text, &owners, Some(headers),
            ).unwrap());
            assert_eq!(relative.bodies.len(), 1, "{source:?}");
            let body = &relative.bodies[0];
            let expected = source.find("probe()").or_else(|| source.find("present()")).unwrap();
            assert_eq!(body.span.start, expected, "{source:?}");
            assert_eq!(body.settings.len(), 1, "{source:?}");
            assert!(source[body.settings[0].range()].starts_with("set "));
            assert!(relative.bind(source.len(), 0).is_ok());
        }
    }
}

/// Request scratch over the existing previous publication's actual claimed
/// contributions. This is not a source tree, a parser, or a persistent cache.
pub(super) struct BodyCodeCandidates{rows:Vec<BodyCandidate>,lease:dm_syntax::SettingRootLease}
struct BodyCandidate{hash:u64,syntax:Arc<RelativeSyntax>,ordinal:usize}

/// The live Original stream already built the current recipes. Try the
/// corresponding old slot before allocating a search index for moved bodies.
pub(super) struct OriginalBodyCodeConvergence<'a> {
    previous: &'a DeclarationSyntax,
    fallback: Option<BodyCodeCandidates>,
}
impl<'a> OriginalBodyCodeConvergence<'a> {
    pub(super) fn new(previous: &'a DeclarationSyntax) -> Self {
        Self { previous, fallback: None }
    }

    pub(super) fn converge(
        &mut self,
        current: &mut RelativeSyntax,
        chunk: usize,
        a: &dm_syntax::SettingAdmission<'_>,
    ) -> std::io::Result<()> {
        code_checkpoint(a)?;
        let previous = self.previous;
        let peer = previous.chunks().get(chunk).map(CurrentSyntaxChunk::shared_relative);
        let peer = match peer {
            Some(peer) if peer.ordinary_code_demand()==current.ordinary_code_demand()&&peer.initializer_admission_matches(a)? && peer.shared_source().is_some() => Some(peer),
            _ => None,
        };
        current.converge_body_codes_using(a, |current, ordinal| {
            if let Some(peer) = peer.filter(|peer| ordinal < peer.bodies.len()) {
                // Only a genuine already-issued predecessor warrants token
                // equality work. Header-only predecessors do not force any
                // Code or scan every BODY merely to prove absence.
                if let Some(code)=peer.issued_body_code(ordinal){if current.code_recipe_equal(ordinal,peer,ordinal,a)?{return Ok(Some(code))}}
            }
            if self.fallback.is_none() {
                let mut index = BodyCodeCandidates::new(a)?;
                for chunk in previous.chunks().iter() {
                    if chunk.shared_relative().ordinary_code_demand()==current.ordinary_code_demand(){index.capture(chunk.shared_relative(),a)?;}
                }
                index.finish(a)?;
                self.fallback = Some(index);
            }
            self.fallback.as_ref().expect("built on first miss").lookup(current, ordinal, a)
        })?;
        Ok(())
    }
}

#[cfg(test)]
thread_local! {
    static CODE_RECIPE_HASHES: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}
#[cfg(test)]
pub(super) fn code_recipe_hashes() -> usize {
    CODE_RECIPE_HASHES.with(std::cell::Cell::get)
}
fn code_io(message:&'static str)->std::io::Error{std::io::Error::new(std::io::ErrorKind::InvalidData,message)}
fn code_checkpoint(a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{let result=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(actual)}result}
fn code_hash(parts:&[&[u8]],a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<u64>{
 use std::hash::Hasher;let mut hash=std::collections::hash_map::DefaultHasher::new();
 for part in parts{code_checkpoint(a)?;hash.write_usize(part.len());for chunk in part.chunks(4096){code_checkpoint(a)?;hash.write(chunk);}}
 Ok(hash.finish())
}
fn code_equal(left:&[u8],right:&[u8],a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<bool>{
 if left.len()!=right.len(){return Ok(false)}for(x,y)in left.chunks(4096).zip(right.chunks(4096)){code_checkpoint(a)?;if x!=y{return Ok(false)}}Ok(true)
}
/// Compare only the actual already-produced sparse facts in this body. None
/// is unissued, distinct from a completed zero-literal stream. No parse/cache.
type CodeLiteralFacts<'a>=(dm_syntax::OriginalLiteralRows<'a>,usize);
fn code_literal_rows<'a>(rows:Option<CodeLiteralFacts<'a>>,body:dm_syntax::Span,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Option<CodeLiteralFacts<'a>>>{
 let Some((rows,origin))=rows else{return Ok(None)};
 let start=origin.checked_add(body.start).ok_or_else(||code_io("actual literal body origin overflow"))?;
 let end=origin.checked_add(body.end).ok_or_else(||code_io("actual literal body end overflow"))?;
 if start>end{return Err(code_io("actual literal body window is reversed"))}
 let begin=rows.partition_point(|(span,_)|span.end<=start);
 let limit=rows.partition_point(|(span,_)|span.start<end);
 if begin>limit{return Err(code_io("actual literal fact ordering differs"))}
 let selected=rows.range(begin..limit).ok_or_else(||code_io("actual literal fact ordering differs"))?;
 for(span,_)in selected.iter(){code_checkpoint(a)?;if span.start<start||span.end>end||span.end<span.start{return Err(code_io("actual literal fact crosses its body recipe"))}}
 Ok(Some((selected,start)))
}
fn code_literal_hash(rows:Option<CodeLiteralFacts<'_>>,body:dm_syntax::Span,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<u64>{
 use std::hash::Hasher;let mut hash=std::collections::hash_map::DefaultHasher::new();
 code_checkpoint(a)?;let rows=code_literal_rows(rows,body,a)?;
 let Some((rows,base))=rows else{hash.write_u8(0);return Ok(hash.finish())};hash.write_u8(1);hash.write_usize(rows.len());
 for(span,value)in rows.iter(){code_checkpoint(a)?;hash.write_usize(span.start-base);hash.write_usize(span.end-base);
  fn text(hash:&mut impl Hasher,value:&str,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{hash.write_usize(value.len());for bytes in value.as_bytes().chunks(4096){code_checkpoint(a)?;hash.write(bytes);}Ok(())}
  text(&mut hash,value.raw()?,a)?;hash.write_u8(value.string_mode() as u8);
  match value.value()?{
   dm_syntax::OriginalTokenValue::Int(value)=>{hash.write_u8(0);hash.write_i32(value)},
   dm_syntax::OriginalTokenValue::Float(value)=>{hash.write_u8(1);hash.write_u32(value.to_bits())},
   dm_syntax::OriginalTokenValue::String(value)=>{hash.write_u8(2);text(&mut hash,value,a)?},
   dm_syntax::OriginalTokenValue::Resource(value)=>{hash.write_u8(3);text(&mut hash,value,a)?},
   _=>return Err(code_io("unissued literal variant in original code recipe")),
  }
 }Ok(hash.finish())
}
fn code_literal_equal(left:Option<CodeLiteralFacts<'_>>,left_body:dm_syntax::Span,right:Option<CodeLiteralFacts<'_>>,right_body:dm_syntax::Span,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<bool>{
 code_checkpoint(a)?;let left=code_literal_rows(left,left_body,a)?;let right=code_literal_rows(right,right_body,a)?;
 let((left,left_base),(right,right_base))=match(left,right){(None,None)=>return Ok(true),(Some(left),Some(right))=>(left,right),_=>return Ok(false)};
 if left.len()!=right.len(){return Ok(false)}
 for((ls,lv),(rs,rv))in left.iter().zip(right.iter()){
  code_checkpoint(a)?;if(ls.start-left_base,ls.end-left_base)!=(rs.start-right_base,rs.end-right_base)||!code_equal(lv.raw()?.as_bytes(),rv.raw()?.as_bytes(),a)?||lv.string_mode()!=rv.string_mode(){return Ok(false)}
  let equal=match(lv.value()?,rv.value()?){
   (dm_syntax::OriginalTokenValue::Int(l),dm_syntax::OriginalTokenValue::Int(r))=>l==r,
   (dm_syntax::OriginalTokenValue::Float(l),dm_syntax::OriginalTokenValue::Float(r))=>l.to_bits()==r.to_bits(),
   (dm_syntax::OriginalTokenValue::String(l),dm_syntax::OriginalTokenValue::String(r))|(dm_syntax::OriginalTokenValue::Resource(l),dm_syntax::OriginalTokenValue::Resource(r))=>code_equal(l.as_bytes(),r.as_bytes(),a)?,
   _=>false,
  };if !equal{return Ok(false)}
 }Ok(true)
}
// Close-Colon roles are an actual sparse primary side column. Rendered bytes
// and literal values cannot authorize reuse across differing native roles.
type CodeColonFacts<'a>=(dm_syntax::OriginalColonRows<'a>,usize);
type CodeColonWindow<'a>=(dm_syntax::OriginalColonRows<'a>,usize,usize,usize);
fn code_colon_rows<'a>(rows:Option<CodeColonFacts<'a>>,body:dm_syntax::Span,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Option<CodeColonWindow<'a>>>{
 let Some((rows,origin))=rows else{return Ok(None)};
 let start=origin.checked_add(body.start).ok_or_else(||code_io("actual colon body origin overflow"))?;
 let end=origin.checked_add(body.end).ok_or_else(||code_io("actual colon body end overflow"))?;
 if start>end{return Err(code_io("actual colon body window is reversed"))}
 let begin=rows.partition_point(|(span,_)|span.end<=start);
 let limit=rows.partition_point(|(span,_)|span.start<end);
 if begin>limit{return Err(code_io("actual colon fact ordering differs"))}
 for index in begin..limit{let(span,_)=rows.get(index).ok_or_else(||code_io("actual colon fact ordinal differs"))?;code_checkpoint(a)?;if span.start<start||span.end>end||span.end<span.start{return Err(code_io("actual colon fact crosses its body recipe"))}}
 Ok(Some((rows,start,begin,limit)))
}
fn code_colon_hash(rows:Option<CodeColonFacts<'_>>,body:dm_syntax::Span,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<u64>{
 use std::hash::Hasher;let mut hash=std::collections::hash_map::DefaultHasher::new();
 code_checkpoint(a)?;let Some((rows,base,begin,end))=code_colon_rows(rows,body,a)? else{hash.write_u8(0);return Ok(hash.finish())};
 hash.write_u8(1);hash.write_usize(end-begin);
 for index in begin..end{let(span,role)=rows.get(index).ok_or_else(||code_io("actual colon fact ordinal differs"))?;code_checkpoint(a)?;hash.write_usize(span.start-base);hash.write_usize(span.end-base);hash.write_u8(u8::from(role));}
 Ok(hash.finish())
}
fn code_colon_equal(left:Option<CodeColonFacts<'_>>,left_body:dm_syntax::Span,right:Option<CodeColonFacts<'_>>,right_body:dm_syntax::Span,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<bool>{
 code_checkpoint(a)?;let left=code_colon_rows(left,left_body,a)?;let right=code_colon_rows(right,right_body,a)?;
 let((left,lb,ls,le),(right,rb,rs,re))=match(left,right){(None,None)=>return Ok(true),(Some(left),Some(right))=>(left,right),_=>return Ok(false)};
 if le-ls!=re-rs{return Ok(false)}
 for(li,ri)in (ls..le).zip(rs..re){
  let(ls,lv)=left.get(li).ok_or_else(||code_io("actual left colon ordinal differs"))?;let(rs,rv)=right.get(ri).ok_or_else(||code_io("actual right colon ordinal differs"))?;
  code_checkpoint(a)?;if(ls.start-lb,ls.end-lb,lv)!=(rs.start-rb,rs.end-rb,rv){return Ok(false)}
 }Ok(true)
}
impl RelativeSyntax{
 /// The actual fresh primary produced these facts already. Identical rendered
 /// source text alone cannot authorize reuse of a different typed token stream.
 pub(crate) fn original_literals_match_headers(&self,headers:&crate::procedure::OriginalProcedureHeaders,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<bool>{
  let Some(previous)=self.original_headers.as_ref()else{return Ok(false)};
  Ok(code_literal_equal(previous.original_literal_facts()?.map(|view|view.raw_parts()),dm_syntax::Span::new(0,self.source_len),headers.original_literal_facts()?.map(|view|view.raw_parts()),dm_syntax::Span::new(0,self.source_len),a)?
   &&code_colon_equal(previous.original_literal_facts()?.map(|view|view.raw_colons()),dm_syntax::Span::new(0,self.source_len),headers.original_literal_facts()?.map(|view|view.raw_colons()),dm_syntax::Span::new(0,self.source_len),a)?)
 }
 fn code_recipe_hash(&self,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<u64>{
  #[cfg(test)]
  CODE_RECIPE_HASHES.with(|count|count.set(count.get()+1));
  let(bytes,header,profile)=self.code_parts(ordinal)?;let body=self.bodies.get(ordinal).ok_or_else(||code_io("actual relative body absent"))?;
  let headers=self.original_headers.as_ref().ok_or_else(||code_io("actual original header producer absent"))?;
  let literals=code_literal_hash(headers.original_literal_facts()?.map(|view|view.raw_parts()),body.span,a)?.to_le_bytes();
  let colons=code_colon_hash(headers.original_literal_facts()?.map(|view|view.raw_colons()),body.span,a)?.to_le_bytes();
  code_hash(&[bytes,header,&profile,&literals,&colons],a)
 }
 fn code_recipe_literals_equal(&self,ordinal:usize,other:&Self,other_ordinal:usize,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<bool>{
  let body=self.bodies.get(ordinal).ok_or_else(||code_io("actual relative body absent"))?;let old=other.bodies.get(other_ordinal).ok_or_else(||code_io("actual previous relative body absent"))?;
  let headers=self.original_headers.as_ref().ok_or_else(||code_io("actual original header producer absent"))?;let previous=other.original_headers.as_ref().ok_or_else(||code_io("actual previous original header producer absent"))?;
  Ok(code_literal_equal(headers.original_literal_facts()?.map(|view|view.raw_parts()),body.span,previous.original_literal_facts()?.map(|view|view.raw_parts()),old.span,a)?
   &&code_colon_equal(headers.original_literal_facts()?.map(|view|view.raw_colons()),body.span,previous.original_literal_facts()?.map(|view|view.raw_colons()),old.span,a)?)
 }
 fn code_item(&self,path:&[usize])->Option<arena::Ref<'_>>{
  let(first,rest)=path.split_first()?;let mut item=self.items.roots().nth(*first)?;
  for index in rest{item=item.children().nth(*index)?;}Some(item)
 }
 fn code_parts(&self,ordinal:usize)->std::io::Result<(&[u8],&[u8],[u8;2])>{
  let body=self.bodies.get(ordinal).ok_or_else(||code_io("actual relative body absent"))?;
  let item=self.code_item(&body.path).ok_or_else(||code_io("actual primary body path differs"))?;
  let bytes=self.shared_source().and_then(|source|source.as_bytes().get(body.span.range())).ok_or_else(||code_io("actual original body source window absent"))?;
  let profile=self.original_headers.as_ref().ok_or_else(||code_io("actual original header producer absent"))?.checker_body_profile();
  let kind=match item.kind(){ItemKind::Proc=>0,ItemKind::Verb=>1,_=>return Err(code_io("actual body recipe is not callable"))};
  Ok((bytes,item.header().as_bytes(),[kind,u8::from(profile)]))
 }
 fn code_recipe_equal(
  &self,ordinal:usize,other:&Self,other_ordinal:usize,a:&dm_syntax::SettingAdmission<'_>,
 )->std::io::Result<bool>{
  let(bytes,header,profile)=self.code_parts(ordinal)?;
  let(old_bytes,old_header,old_profile)=other.code_parts(other_ordinal)?;
  Ok(profile==old_profile&&code_equal(header,old_header,a)?&&code_equal(bytes,old_bytes,a)?
      &&self.code_recipe_literals_equal(ordinal,other,other_ordinal,a)?)
 }
 pub(super) fn converge_body_codes(&mut self,previous:&BodyCodeCandidates,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<usize>{
  self.converge_body_codes_using(a,|current,ordinal|previous.lookup(current,ordinal,a))
 }
 fn converge_body_codes_using(
  &mut self,a:&dm_syntax::SettingAdmission<'_>,
  mut lookup:impl FnMut(&Self,usize)->std::io::Result<Option<Arc<BodyCodeIdentity>>>,
 )->std::io::Result<usize>{
  code_checkpoint(a)?;if !self.initializer_admission_matches(a)?||self.shared_source().is_none(){return Ok(0)}
  let mut changed=0;
  for ordinal in 0..self.bodies.len(){
   code_checkpoint(a)?;
   if self.ordinary_code_demand()&&self.code_storage.as_ref().and_then(|s|s.slots.as_ref()).and_then(|s|s.issued(ordinal)).is_some(){continue}
   if let Some(code)=lookup(self,ordinal)?{
    // An unadmitted compatibility identity remains DATA. Do not move an
    // unfunded/foreign tail into this actual native allocation domain.
    if !code.committed_allocation_credit().is_some_and(|credit|a.matches_lease_domain(credit)){continue}
    self.bodies[ordinal].code=Some(code);changed+=1;
   }
  }
  code_checkpoint(a)?;Ok(changed)
 }
}
impl BodyCodeCandidates{
 fn lookup(&self,current:&RelativeSyntax,ordinal:usize,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Option<Arc<BodyCodeIdentity>>>{
  if self.rows.is_empty(){return Ok(None)}
  let hash=current.code_recipe_hash(ordinal,a)?;
  let mut begin=0;let mut end=self.rows.len();
  while begin<end{code_checkpoint(a)?;let mid=begin+(end-begin)/2;if self.rows[mid].hash<hash{begin=mid+1}else{end=mid}}
  for candidate in &self.rows[begin..]{
   code_checkpoint(a)?;if candidate.hash!=hash{break}
   if candidate.syntax.ordinary_code_demand()!=current.ordinary_code_demand(){continue}
   if current.code_recipe_equal(ordinal,&candidate.syntax,candidate.ordinal,a)?{
    if let Some(code)=candidate.syntax.issued_body_code(candidate.ordinal){return Ok(Some(code))}
   }
  }
  Ok(None)
 }
 pub(super) fn new(a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<Self>{let pending=a.reserve(std::mem::size_of::<Self>());if let Some(actual)=a.take_operational_error(){return Err(actual)}Ok(Self{rows:Vec::new(),lease:pending?})}
 pub(super) fn capture(&mut self,syntax:&Arc<RelativeSyntax>,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{
  code_checkpoint(a)?;if !syntax.initializer_admission_matches(a)?||syntax.shared_source().is_none(){return Ok(())}
  for ordinal in 0..syntax.bodies.len(){
   code_checkpoint(a)?;if syntax.issued_body_code(ordinal).is_none(){continue}let hash=syntax.code_recipe_hash(ordinal,a)?;
   if self.rows.len()==self.rows.capacity(){
    let count=self.rows.capacity().max(4).checked_mul(2).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;
    let bytes=count.checked_mul(4).and_then(|n|n.checked_mul(std::mem::size_of::<BodyCandidate>())).and_then(|n|n.checked_add(std::mem::size_of::<Self>()+128)).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;
    if bytes>self.lease.bytes(){let growth=bytes-self.lease.bytes();a.grow(&mut self.lease,growth)?;}
    let mut next=Vec::new();next.try_reserve_exact(count).map_err(|error|std::io::Error::new(std::io::ErrorKind::OutOfMemory,error))?;
    if next.capacity()>count.checked_mul(4).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?{return Err(code_io("candidate allocator exceeds admitted peak"))}
    next.append(&mut self.rows);self.rows=next;
   }
   self.rows.push(BodyCandidate{hash,syntax:Arc::clone(syntax),ordinal});
  }Ok(())
 }
 pub(super) fn finish(&mut self,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{
  // In-place heapsort: no hidden allocation and a real typed checkpoint on
  // every comparison/sift, including cancellation during ordering.
  fn sift(rows:&mut[BodyCandidate],mut root:usize,end:usize,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{
   loop{code_checkpoint(a)?;let Some(left)=root.checked_mul(2).and_then(|n|n.checked_add(1)).filter(|n|*n<end)else{return Ok(())};let mut child=left;
    if left+1<end&&rows[left].hash<rows[left+1].hash{child+=1}if rows[root].hash>=rows[child].hash{return Ok(())}rows.swap(root,child);root=child;
   }
  }
  let len=self.rows.len();for root in(0..len/2).rev(){sift(&mut self.rows,root,len,a)?;}for end in(1..len).rev(){code_checkpoint(a)?;self.rows.swap(0,end);sift(&mut self.rows,0,end,a)?;}code_checkpoint(a)
 }
}

#[cfg(test)]mod real_body_convergence_tests{
 use super::*;
 use crate::frontend::declaration_state::RetainedDeclarations;
 fn actual_current(store:&RetainedDeclarations,text:&str,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<crate::frontend::declaration_state::CurrentContribution>{
  let parsed=dm_syntax::parse_declaration_skeleton(text);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);
  let source=dm_preprocess::SourceText::from(text.to_owned());
  let headers=crate::procedure::OriginalProcedureHeaders::from_primary_admitted(source.clone(),&parsed.items,0,parsed.tokens,a).map_err(|failure|match failure{crate::procedure::header_input::OriginalHeaderFailure::Operational(error)=>error,crate::procedure::header_input::OriginalHeaderFailure::Source(message)=>std::io::Error::new(std::io::ErrorKind::InvalidData,message)})?;
  let ast=dm_syntax::AstFile{items:parsed.items,..Default::default()};
  let(mut facts,receipt)=crate::adapter::from_ast_with_source_headers_checked(&ast,dm_ir::SymbolTable::default(),dm_ir::FileId(0),0,0,text,&headers,0,a)?.unwrap();drop(receipt);
  let ledger=crate::allocation_ledger::capture(&ast.items,"/",&mut facts.symbols).unwrap();
  let key=RetainedDeclarations::original_header_key(text);store.retain(&[key.clone()]);
  store.capture_source_headers_checked(&key,source,0,ast.items,facts,ledger,headers,a)?.ok_or_else(||code_io("actual native contribution was not captured"))
 }
 fn code(syntax:&RelativeSyntax,name:&str)->Arc<BodyCodeIdentity>{
  let row=syntax.bodies.iter().find(|body|syntax.code_item(&body.path).unwrap().header().starts_with(&format!("/proc/{name}("))).unwrap();Arc::clone(row.code.as_ref().expect("eager test Code"))
 }
 #[test]fn actual_published_primary_capture_converges_both_unchanged_siblings_after_length_changing_same_chunk_edit(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&counter,1<<26,&||Ok(()));let store=RetainedDeclarations::default();
  let old="/proc/p(value=1)\n    return value\n/proc/q()\n    return 2\n/proc/r()\n    return 3\n";
  let request=store.begin_request(true);let first=actual_current(&store,old,&a).unwrap();let p=code(&first.syntax.shared_relative(),"p");let q=code(&first.syntax.shared_relative(),"q");let r=code(&first.syntax.shared_relative(),"r");assert!(request.publish_successful());
  let new="/proc/p(value=1)\n    return value\n/proc/q()\n    return list(222,333,444)\n/proc/r()\n    return 3\n";
  let request=store.begin_request(true);let second=actual_current(&store,new,&a).unwrap();assert!(Arc::ptr_eq(&p,&code(&second.syntax.shared_relative(),"p")));assert!(!Arc::ptr_eq(&q,&code(&second.syntax.shared_relative(),"q")));assert!(Arc::ptr_eq(&r,&code(&second.syntax.shared_relative(),"r")));assert_ne!(first.syntax.shared_relative().source_len,second.syntax.shared_relative().source_len);assert!(!Arc::ptr_eq(first.syntax.shared_relative().original_headers.as_ref().unwrap(),second.syntax.shared_relative().original_headers.as_ref().unwrap()),"only code data converges; actual current primary/header owner remains distinct");assert!(request.publish_successful());
  let request=store.begin_request(true);let shifted=actual_current(&store,&format!("// earlier header offset shifts every same-chunk body\n{new}"),&a).unwrap();assert!(Arc::ptr_eq(&p,&code(&shifted.syntax.shared_relative(),"p")));assert!(Arc::ptr_eq(&r,&code(&shifted.syntax.shared_relative(),"r")));assert!(request.publish_successful());
 }
 #[test]fn failed_current_capture_does_not_publish_or_erase_the_previous_body_code_candidates(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let store=RetainedDeclarations::default();let a=dm_syntax::SettingAdmission::new(&counter,1<<26,&||Ok(()));
  let old="/proc/p()\n    return 1\n/proc/q()\n    return 2\n";let first_request=store.begin_request(true);let original=actual_current(&store,old,&a).unwrap();let p=code(&original.syntax.shared_relative(),"p");assert!(first_request.publish_successful());
  let failure=||Err(std::io::Error::from_raw_os_error(1450));let denied=dm_syntax::SettingAdmission::new(&counter,1<<26,&failure);let failed_request=store.begin_request(true);let error=actual_current(&store,old,&denied).err().expect("real operational capture failure");assert_eq!(error.raw_os_error(),Some(1450));drop(failed_request);
  let request=store.begin_request(true);let next=actual_current(&store,"/proc/p()\n    return 1\n/proc/q()\n    return 222222\n",&a).unwrap();assert!(Arc::ptr_eq(&p,&code(&next.syntax.shared_relative(),"p")));assert!(request.publish_successful());
  let request=store.begin_request(true);let deleted=actual_current(&store,"/proc/q()\n    return 222222\n",&a).unwrap();assert_eq!(deleted.syntax.shared_relative().bodies.len(),1);assert!(request.publish_successful());
  drop(original);drop(next);
  let request=store.begin_request(true);let readded=actual_current(&store,old,&a).unwrap();assert!(!Arc::ptr_eq(&p,&code(&readded.syntax.shared_relative(),"p")),"deleted code is not revived from unclaimed global core variants");assert!(request.publish_successful());
 }
 #[test]fn native_body_candidate_index_quota_and_checkpoint_failures_keep_exact_operational_identity(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let failure=||Err(std::io::Error::from_raw_os_error(1450));let a=dm_syntax::SettingAdmission::new(&counter,1<<24,&failure);assert_eq!(BodyCodeCandidates::new(&a).err().unwrap().raw_os_error(),Some(1450));
  let a=dm_syntax::SettingAdmission::new(&counter,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));assert_eq!(BodyCodeCandidates::new(&a).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}

#[cfg(test)]mod sparse_original_literal_recipe_data_tests{
 use super::*;use dm_syntax::{OriginalLiteralData,OriginalTokenValue,Span};use std::sync::atomic::AtomicUsize;
 #[test]fn same_rendered_numeric_spelling_never_converges_distinct_actual_literal_variants_or_float_bits(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&poll);
  let make=|value|vec![(Span::new(2,3),OriginalLiteralData::from_value_using("0".into(),value,&a).unwrap())];
  let int=make(OriginalTokenValue::Int(0));let float=make(OriginalTokenValue::Float(0.0));let negative=make(OriginalTokenValue::Float(-0.0));let body=Span::new(0,4);
  for other in [&float,&negative]{assert!(!code_literal_equal(Some((dm_syntax::OriginalLiteralRows::from_slice(&int),0)),body,Some((dm_syntax::OriginalLiteralRows::from_slice(other),0)),body,&a).unwrap());assert_ne!(code_literal_hash(Some((dm_syntax::OriginalLiteralRows::from_slice(&int),0)),body,&a).unwrap(),code_literal_hash(Some((dm_syntax::OriginalLiteralRows::from_slice(other),0)),body,&a).unwrap());}
  assert!(!code_literal_equal(Some((dm_syntax::OriginalLiteralRows::from_slice(&float),0)),body,Some((dm_syntax::OriginalLiteralRows::from_slice(&negative),0)),body,&a).unwrap());
 }
 #[test]fn body_move_keeps_relative_facts_but_unissued_stream_and_changed_static_value_cannot_alias(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&poll);
  let data=OriginalLiteralData::from_value_using("same displayed token".into(),OriginalTokenValue::String("[static]"),&a).unwrap();
  let left=vec![(Span::new(2,3),data.clone())];let moved=vec![(Span::new(102,103),data.clone())];let before=Span::new(0,10);let after=Span::new(100,110);
  assert!(code_literal_equal(Some((dm_syntax::OriginalLiteralRows::from_slice(&left),0)),before,Some((dm_syntax::OriginalLiteralRows::from_slice(&moved),0)),after,&a).unwrap());
  assert!(code_literal_equal(Some((dm_syntax::OriginalLiteralRows::from_slice(&left),0)),before,Some((dm_syntax::OriginalLiteralRows::from_slice(&moved),100)),before,&a).unwrap(),"real TU-origin view projects the same chunk-local occurrence without copies");assert_eq!(code_literal_hash(Some((dm_syntax::OriginalLiteralRows::from_slice(&left),0)),before,&a).unwrap(),code_literal_hash(Some((dm_syntax::OriginalLiteralRows::from_slice(&moved),0)),after,&a).unwrap());
  let changed=vec![(Span::new(2,3),OriginalLiteralData::from_value_using("same displayed token".into(),OriginalTokenValue::String("[different]"),&a).unwrap())];assert!(!code_literal_equal(Some((dm_syntax::OriginalLiteralRows::from_slice(&left),0)),before,Some((dm_syntax::OriginalLiteralRows::from_slice(&changed),0)),before,&a).unwrap());
  assert!(!code_literal_equal(None,before,Some((dm_syntax::OriginalLiteralRows::from_slice(&[]),0)),before,&a).unwrap());assert_ne!(code_literal_hash(None,before,&a).unwrap(),code_literal_hash(Some((dm_syntax::OriginalLiteralRows::from_slice(&[]),0)),before,&a).unwrap());
 }
 #[test]fn sparse_literal_comparison_preserves_exact_operational_error(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Err(std::io::Error::from_raw_os_error(1450));let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&poll);
  assert_eq!(code_literal_hash(None,Span::new(0,1),&a).unwrap_err().raw_os_error(),Some(1450));
  // A stopped operation does not poll again or manufacture a second owned OS
  // error. Each independent demand starts with its genuine fresh admission.
  let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&poll);
  assert_eq!(code_literal_equal(None,Span::new(0,1),None,Span::new(0,1),&a).unwrap_err().raw_os_error(),Some(1450));
 }
}

#[cfg(test)]mod sparse_original_literal_poll_controls{
 use super::*;
 #[test]fn cancellation_during_selected_row_validation_stops_before_value_hashing_and_fresh_operation_recovers(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let success=||Ok(());let seed=dm_syntax::SettingAdmission::new(&counter,1<<20,&success);
  let data=dm_syntax::OriginalLiteralData::from_value_using("0".into(),dm_syntax::OriginalTokenValue::Int(0),&seed).unwrap();let rows=vec![(dm_syntax::Span::new(1,2),data.clone()),(dm_syntax::Span::new(3,4),data)];let calls=std::cell::Cell::new(0);let poll=||{calls.set(calls.get()+1);if calls.get()==3{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};let stopped=dm_syntax::SettingAdmission::new(&counter,1<<20,&poll);
  assert_eq!(code_literal_hash(Some((dm_syntax::OriginalLiteralRows::from_slice(&rows),0)),dm_syntax::Span::new(0,5),&stopped).unwrap_err().raw_os_error(),Some(1450));assert_eq!(calls.get(),3);
  let fresh=dm_syntax::SettingAdmission::new(&counter,1<<20,&success);assert!(code_literal_hash(Some((dm_syntax::OriginalLiteralRows::from_slice(&rows),0)),dm_syntax::Span::new(0,5),&fresh).is_ok());
 }
}

impl BodyCodeIdentity{pub fn committed_allocation_credit(&self)->Option<&dm_syntax::SettingRootLease>{self.allocation_credit.get()}}
impl std::fmt::Debug for BodyCodeIdentity{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("BodyCodeIdentity").field("_private",&0u8).finish()}}

impl BodyCodeIdentity{pub fn visit_allocation_storage(&self,visit:&mut dyn FnMut(usize,usize,usize)){let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<Self>()).expect("actual Code Arc layout");visit(self as *const Self as usize,std::mem::size_of::<Self>(),layout.pad_to_align().size());let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<BodyCodeWeakAllocation>()).expect("actual Code credit Arc layout");visit(Arc::as_ptr(&self.allocation_credit)as usize,std::mem::size_of::<BodyCodeWeakAllocation>(),layout.pad_to_align().size());if let Some(credit)=self.allocation_credit.get(){credit.visit_counter_storage(|p,n|visit(p,n,n));}}}

#[cfg(test)]#[test]fn actual_intrinsic_code_allocation_layout_is_measured_without_root_or_header_changes(){
 #[allow(dead_code)]struct Prior{_private:u8}
 fn padded<T>()->usize{let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<T>()).unwrap();layout.pad_to_align().size()}
 assert_eq!(std::mem::size_of::<BodyCodeWeak>(),std::mem::size_of::<std::sync::Weak<BodyCodeIdentity>>(),"same one-pointer weak consumer representation");eprintln!("CODE_RESOURCE_OWNER payload={} padded_arc={} weak_locator={}",std::mem::size_of::<BodyCodeWeakAllocation>(),padded::<BodyCodeWeakAllocation>(),std::mem::size_of::<BodyCodeWeak>());let old=padded::<Prior>();let new=padded::<BodyCodeIdentity>();eprintln!("COMMITTED_CODE_ALLOCATION prior_payload={} current_payload={} prior_arc={} current_arc={} inline_lease={}",std::mem::size_of::<Prior>(),std::mem::size_of::<BodyCodeIdentity>(),old,new,std::mem::size_of::<dm_syntax::SettingRootLease>());assert!(new>=old);assert_eq!(std::mem::size_of::<BodyCodeIdentity>(),std::mem::size_of::<Arc<BodyCodeWeakAllocation>>());
}

#[cfg(test)]#[test]fn actual_funded_code_allocation_denies_peak_preserves_first_io_and_refunds_last_strong_owner(){
 use std::sync::atomic::Ordering;let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();
 fn arc<T>()->usize{let(l,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<T>()).unwrap();l.pad_to_align().size()}
 let required=arc::<BodyCodeIdentity>()+arc::<BodyCodeWeakAllocation>();let poll=||Ok(());let denied=dm_syntax::SettingAdmission::new(&counter,root+required-1,&poll);assert_eq!(funded_body_code(&denied).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);drop(denied);assert_eq!(counter.load(Ordering::Acquire),root);
 let stop=||Err(std::io::Error::from_raw_os_error(1450));let failed=dm_syntax::SettingAdmission::new(&counter,root+required,&stop);assert_eq!(funded_body_code(&failed).unwrap_err().raw_os_error(),Some(1450));drop(failed);assert_eq!(counter.load(Ordering::Acquire),root);
 let actual=dm_syntax::SettingAdmission::new(&counter,root+required,&poll);let code=funded_body_code(&actual).unwrap();let other=Arc::clone(&code);assert_eq!(counter.load(Ordering::Acquire),root+required);drop(code);assert_eq!(counter.load(Ordering::Acquire),root+required);drop(other);assert_eq!(counter.load(Ordering::Acquire),root);
}

#[cfg(test)]#[test]fn actual_weak_code_credit_preserves_expiry_and_funds_dead_shell_until_last_locator(){
 use std::sync::atomic::Ordering;let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();let poll=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&poll);
 let code=funded_body_code(&a).unwrap();let paid=code.committed_allocation_credit().unwrap().bytes();let first=BodyCodeIdentity::downgrade(&code);let second=first.clone();assert!(first.ptr_eq(&second));assert!(first.matches(&code));assert_eq!(first.strong_count(),1);assert!(first.upgrade().is_some());
 drop(code);assert_eq!(first.strong_count(),0);assert!(first.upgrade().is_none());assert_eq!(counter.load(Ordering::Acquire),root+paid);drop(first);assert_eq!(counter.load(Ordering::Acquire),root+paid);drop(second);assert_eq!(counter.load(Ordering::Acquire),root);
}

impl BodyCodeIdentity{
 /// Resource-only adoption of an existing DATA allocation; no source/current grant.
 pub fn admit_native_allocation(&self,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>{
  if let Some(actual)=a.take_operational_error(){return Err(actual)}
  fn padded<T>()->std::io::Result<usize>{let(layout,_)=std::alloc::Layout::new::<[std::sync::atomic::AtomicUsize;2]>().extend(std::alloc::Layout::new::<T>()).map_err(|_|std::io::ErrorKind::OutOfMemory)?;Ok(layout.pad_to_align().size())}
  let required=padded::<Self>()?.checked_add(padded::<BodyCodeWeakAllocation>()?).ok_or(std::io::ErrorKind::OutOfMemory)?;
  let validate=|credit:&dm_syntax::SettingRootLease|{if !a.matches_lease_domain(credit)||credit.bytes()<required{Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual Code allocation uses another or incomplete grant"))}else{Ok(())}};
  if let Some(credit)=self.allocation_credit.get(){return validate(credit)}
  let pending=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(actual)}pending?;let reserved=a.reserve(required);if let Some(actual)=a.take_operational_error(){return Err(actual)}let credit=reserved?;if let Err(unused)=self.allocation_credit.set(credit){drop(unused)}validate(self.allocation_credit.get().expect("actual Code allocation initialized"))
 }
}

#[cfg(test)]#[test]fn actual_data_code_admission_updates_prior_weak_locators_and_keeps_reserve_first_io(){
 use std::sync::atomic::Ordering;let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();let code=ordinary_body_code(None).unwrap();let prior=BodyCodeIdentity::downgrade(&code);assert!(code.committed_allocation_credit().is_none());
 let calls=std::cell::Cell::new(0);let fail=||{let next=calls.get()+1;calls.set(next);if next==2{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}};let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&fail);assert_eq!(code.admit_native_allocation(&a).unwrap_err().raw_os_error(),Some(1450));assert_eq!(calls.get(),2);assert!(code.committed_allocation_credit().is_none());drop(a);assert_eq!(counter.load(Ordering::Acquire),root);
 let good=dm_syntax::SettingAdmission::new(&counter,1<<20,&||Ok(()));code.admit_native_allocation(&good).unwrap();let paid=code.committed_allocation_credit().unwrap().bytes();let owner_pointer=Arc::as_ptr(&code.allocation_credit);assert_eq!(Arc::as_ptr(&prior.credit),owner_pointer);drop(code);assert!(prior.upgrade().is_none());assert_eq!(prior.strong_count(),0);assert_eq!(counter.load(Ordering::Acquire),root+paid);drop(prior);assert_eq!(counter.load(Ordering::Acquire),root);
}

#[cfg(test)]#[test]
fn actual_ordinary_code_binding_preserves_original_1450_and_exact_quota_payload(){
 let root=dm_syntax::SettingChargeCounter::root_allocation_bytes();
 let counter=dm_syntax::SettingChargeCounter::try_new(root).unwrap();
 let stop=||Err(std::io::Error::from_raw_os_error(1450));
 let failed=dm_syntax::SettingAdmission::new(&counter,1<<20,&stop);
 assert_eq!(ordinary_body_code(Some(&failed)).unwrap_err(),BindingError::InvalidRelativeSpan);
 assert_eq!(failed.take_operational_error().unwrap().raw_os_error(),Some(1450));
 assert_eq!(counter.load(Ordering::Acquire),root);
 let ok=||Ok(());let tight=dm_syntax::SettingAdmission::new(&counter,root,&ok);
 assert_eq!(ordinary_body_code(Some(&tight)).unwrap_err(),BindingError::InvalidRelativeSpan);
 let actual=tight.take_operational_error().unwrap();assert_eq!(actual.kind(),std::io::ErrorKind::OutOfMemory);
 assert!(actual.to_string().contains("requested"),"actual admission allocation context must survive the BindingError boundary");
 assert_eq!(counter.load(Ordering::Acquire),root);
 let recovered=dm_syntax::SettingAdmission::new(&counter,1<<20,&ok);let code=ordinary_body_code(Some(&recovered)).unwrap();assert!(code.committed_allocation_credit().is_some());drop(code);assert_eq!(counter.load(Ordering::Acquire),root);
}

impl DeclarationSyntax{
    pub(crate) fn setting_token_input_header_only<'a>(
        &'a self,
        span: Span,
        ordinal: usize,
    ) -> Result<OriginalSettingTokenInput<'a>, dm_syntax::Diagnostic> {
        let recipe = self.original_header_recipe(span)?;
        let fail = |message: &str| dm_syntax::Diagnostic {
            span,
            kind: dm_syntax::DiagnosticKind::Unsupported,
            message: message.into(),
        };
        let input = recipe
            .headers
            .ok_or_else(|| fail("original setting token owner unavailable"))?;
        let owner = recipe
            .relative
            .settings_owner
            .as_ref()
            .ok_or_else(|| fail("original setting metadata owner unavailable"))?;
        let footprint = recipe
            .relative
            .setting_footprints
            .as_ref()
            .and_then(|rows| rows.get(ordinal))
            .ok_or_else(|| fail("original setting footprint ordinal unavailable"))?;
        let (source, tokens) = input
            .setting_value_tokens(recipe.relative.span, owner, footprint)
            .map_err(|message| fail(&message))?;
        let slots = input
            .setting_root_slots(recipe.relative.span, owner, footprint)
            .map_err(|message| fail(&message))?;
        let header = Span::new(
            footprint.header.start + recipe.offset,
            footprint.header.end + recipe.offset,
        );
        let value = Span::new(
            footprint.value.start + recipe.offset,
            footprint.value.end + recipe.offset,
        );
        Ok(OriginalSettingTokenInput {
            literal_owner:input,
            source,
            tokens,
            original_owner: owner,
            ordinal,
            header,
            value,
            offset: recipe.offset,
            slots,
            original_value: footprint.value,
        })
    }
    pub(crate) fn return_annotation_token_input_header_only<'a>(
        &'a self,
        span: Span,
        fragment: &dm_ir::SymbolicExpression,
        selected: &dm_ir::ProcedureMetadata,
        symbols: &dm_ir::SymbolTable,
    ) -> Result<OriginalReturnTokenInput<'a>, dm_syntax::Diagnostic> {
        let recipe = self.original_header_recipe(span)?;
        let fail = |message: String| dm_syntax::Diagnostic {
            span,
            kind: dm_syntax::DiagnosticKind::Unsupported,
            message,
        };
        let headers = recipe
            .headers
            .ok_or_else(|| fail("original return token owner unavailable".into()))?;
        let owner = recipe
            .relative
            .settings_owner
            .as_ref()
            .ok_or_else(|| fail("original return metadata owner unavailable".into()))?;
        if owner.signature.return_annotation != selected.signature.return_annotation {
            return Err(fail(
                "selected return annotation differs from original metadata".into(),
            ));
        }
        let (source, tokens, value, ordinal, count, slots) = headers
            .return_fragment(recipe.relative.span, owner, fragment, symbols)
            .map_err(fail)?;
        Ok(OriginalReturnTokenInput {
            literal_owner:headers,
            source,
            tokens,
            original_value: value,
            ordinal,
            count,
            slots,
            offset: recipe.offset,
        })
    }
    pub(super) fn abi_root_owner_header_only<'a>(&'a self,span:Span)->Result<(&'a Arc<crate::procedure::OriginalProcedureHeaders>,Span),dm_syntax::Diagnostic>{let recipe=self.original_header_recipe(span)?;recipe.headers.map(|owner|(owner,recipe.relative.span)).ok_or_else(||dm_syntax::Diagnostic{span,kind:dm_syntax::DiagnosticKind::Unsupported,message:"ABI original header owner unavailable".into()})}
    pub(super) fn cached_abi_root_header_only(&self,span:Span,ordinal:usize,count:usize,returns:bool,a:&dm_syntax::SettingAdmission<'_>)->Result<dm_syntax::SettingExpression,dm_syntax::SettingSyntaxFailure>{
      let recipe=self.original_header_recipe(span).map_err(dm_syntax::SettingSyntaxFailure::Syntax)?;
      let fail=|message:&str|dm_syntax::SettingSyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,message));
      let headers=recipe.headers.ok_or_else(||fail("ABI original header owner unavailable"))?;let owner=recipe.relative.settings_owner.as_ref().ok_or_else(||fail("ABI original metadata owner unavailable"))?;
      let root=headers.cached_abi_root(recipe.relative.span,owner,ordinal,count,returns,a)?;
      root.project_current(recipe.offset,headers.abi_source_len()).map_err(dm_syntax::SettingSyntaxFailure::Operational)
    }
}

#[cfg(test)]mod portable_eager_recipe_binding_controls{
 use super::*;
 #[test]fn actual_portable_eager_code_recipe_remains_valid_without_original_header_authority(){
  let source="/proc/p()\n    return 1\n";let parsed=dm_syntax::parse(source);assert!(parsed.diagnostics.is_empty());let relative=Arc::new(RelativeSyntax::capture(parsed.items,source).unwrap());assert!(relative.original_headers.is_none());assert!(relative.code_storage.is_none(),"old no-admission portable constructor stays explicitly unqualified");let span=relative.bodies[0].span;let code=Arc::clone(relative.bodies[0].code.as_ref().unwrap());let syntax=DeclarationSyntax::new(vec![relative.bind(source.len(),0).unwrap()]).unwrap();
  let bound=syntax.original_body_recipe_checked(span,&code).unwrap();assert!(bound.setting_headers().is_none());assert!(Arc::ptr_eq(&bound.issued_code_for_binding().unwrap().unwrap(),&code));assert!(syntax.original_body_recipe(span,&code).is_ok(),"old Diagnostic wrapper must preserve the portable recipe contract");assert!(syntax.original_header_recipe(span).is_err(),"portable Code identity does NOT mint Original Header/ABI authority");
  let foreign=Arc::new(RelativeSyntax::capture(dm_syntax::parse(source).items,source).unwrap());let foreign_code=foreign.bodies[0].code.as_ref().unwrap();assert!(matches!(syntax.original_body_recipe_checked(span,foreign_code),Err(BodySyntaxFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::InvalidData));assert!(syntax.original_body_recipe_checked(Span::new(span.start,span.end+1),&code).is_err());
 }
}

impl DeclarationSyntax{pub(super) fn has_parser_report_prefix(&self)->bool{self.chunks.iter().any(|chunk|chunk.relative.original_headers.as_ref().is_some_and(|headers|headers.committed_prefix_products().is_some()))}}

impl DeclarationSyntax{
 /// DATA-only owner test on the same ordered chunk geometry. This grants no
 /// current body/Code identity; the existing recipe checks still follow it.
 pub(super) fn body_has_parser_report_prefix(&self,span:Span)->bool{
  if !self.ordered_chunks{return self.has_parser_report_prefix()}
  let Some(index)=self.chunks.partition_point(|chunk|chunk.offset<=span.start).checked_sub(1)else{return false};let chunk=&self.chunks[index];
  chunk.relative.original_headers.as_ref().is_some_and(|headers|headers.committed_prefix_products().is_some())
 }
}
