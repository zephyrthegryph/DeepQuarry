//! Stored declarations certified by the exact issued parse, shared by consumers.
use super::{BodyOccurrence, ColdFrontend, ParsedBody};
use crate::{procedure_statics::StaticPlan, MemberKind};
use dm_ir::ProcedureIdentity;
use std::sync::{Arc, OnceLock, Weak};

pub struct IssuedStaticPlan {
    plan: StaticPlan,
    snapshot: StaticSourceReceipt,
    body_span: dm_syntax::Span,
    source: Arc<str>,
    reusable: OnceLock<Arc<RelativeStaticPlan>>,
    // SAME admitted AST parent, never a cloned initializer expression.
    syntax: Option<Arc<super::StatementBody>>,
    syntax_body: dm_syntax::Span,
}

/// Identity of actual current source owners at issuance, without retaining a
/// second tree/model. Weak owners are upgraded before exact owner comparison;
/// source addresses, hashes and equal body text cannot mint this receipt.
#[derive(Debug)]
struct StaticSourceReceipt {
    declaration:crate::OccurrenceId,
    tree:Weak<crate::SemanticTree>,
    occurrences:Weak<crate::OccurrenceTable>,
    code:super::BodyCodeWeak,
    termination:dm_syntax::BodyTermination,
}
impl StaticSourceReceipt {
    fn new(frontend:&ColdFrontend,body:&BodyOccurrence)->Result<Self,String>{
        let code=frontend.body_code(body).map_err(|error|error.message)?;
        Ok(Self{declaration:body.declaration,tree:Arc::downgrade(&frontend.snapshot.tree),occurrences:Arc::downgrade(&frontend.snapshot.occurrences),code:super::BodyCodeIdentity::downgrade(code.identity()),termination:code.termination()})
    }
    fn matches(&self,frontend:&ColdFrontend,body:&BodyOccurrence)->Result<bool,String>{
        let (Some(tree),Some(occurrences),Some(code))=(self.tree.upgrade(),self.occurrences.upgrade(),self.code.upgrade())else{return Ok(false)};
        let current=frontend.body_code(body).map_err(|error|error.message)?;
        Ok(Arc::ptr_eq(&tree,&frontend.snapshot.tree)&&Arc::ptr_eq(&occurrences,&frontend.snapshot.occurrences)
            &&Arc::ptr_eq(&code,current.identity())&&self.termination==current.termination())
    }
}

/// Original current body/code arrays, retained weakly without a copied roster.
/// A body-only edit can reuse semantic snapshots; this actual owner receipt
/// still refuses the old finalized plan under the changed body frame.
#[derive(Debug)]
pub struct InitializerFrameReceipt {
    bodies:Weak<[BodyOccurrence]>,
    codes:Weak<[super::body_code::BodyCodeOwner]>,
    bodies_bytes:usize,
    codes_bytes:usize,
}
impl InitializerFrameReceipt {
    pub(crate) fn issue(frontend:&ColdFrontend)->Result<Self,String>{
        frontend.require_current_body_code_owners().map_err(|error|error.message)?;
        Ok(Self{bodies:Arc::downgrade(&frontend.issued_bodies),codes:Arc::downgrade(&frontend.issued_body_codes),bodies_bytes:std::mem::size_of_val(frontend.issued_bodies.as_ref()),codes_bytes:std::mem::size_of_val(frontend.issued_body_codes.as_ref())})
    }
    /// Weak owners retain the existing slice allocations even after element
    /// destruction. Report their saved actual payload layout without reading T.
    /// Arc control/header and backend allocator overhead remain census unknowns.
    pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
        visit(self.bodies.as_ptr() as *const BodyOccurrence as usize,if self.bodies.strong_count()>0{self.bodies_bytes}else{0},self.bodies_bytes);
        visit(self.codes.as_ptr() as *const super::body_code::BodyCodeOwner as usize,if self.codes.strong_count()>0{self.codes_bytes}else{0},self.codes_bytes);
    }
    pub fn matches_frontend(&self,frontend:&ColdFrontend)->bool{
        if frontend.require_current_body_code_owners().is_err(){return false;}
        let (Some(bodies),Some(codes))=(self.bodies.upgrade(),self.codes.upgrade())else{return false};
        Arc::ptr_eq(&bodies,&frontend.issued_bodies)&&Arc::ptr_eq(&codes,&frontend.issued_body_codes)
    }
}

/// Producer-owned syntax with checked body-relative coordinates. It carries
/// neither a frontend issuance nor absolute source coordinates.
pub struct RelativeStaticPlan {
    plan: StaticPlan,
    source: Arc<str>,
    declarations: Arc<[Arc<dm_ir::ProcedureStaticDeclaration>]>,
    syntax_code:Option<super::BodyCodeWeak>,
    syntax_termination:dm_syntax::BodyTermination,
    syntax: Option<Arc<super::StatementBody>>,
    syntax_body: dm_syntax::Span,
}
impl RelativeStaticPlan {
    pub fn visit_weak_syntax_storage(&self,mut visit:impl FnMut(usize,usize,usize)){if let Some(code)=&self.syntax_code{code.visit_allocation_storage(&mut visit);}}
    pub fn retained_statement_body(&self)->Option<&Arc<super::StatementBody>>{self.syntax.as_ref()}
    pub fn canonical_declarations(&self) -> &Arc<[Arc<dm_ir::ProcedureStaticDeclaration>]> {
        &self.declarations
    }
    pub fn plan(&self) -> &StaticPlan {
        &self.plan
    }
    pub fn source(&self) -> &Arc<str> {
        &self.source
    }
    pub fn bind(
        self: &Arc<Self>,
        frontend: &ColdFrontend,
        body: &BodyOccurrence,
    ) -> Result<Arc<IssuedStaticPlan>, String> {
        frontend
            .compact_body(body)
            .map_err(|e| format!("static body issuance: {e:?}"))?;
        let source = frontend
            .expanded
            .text
            .get(body.expanded_span.range())
            .ok_or("static body source outside capture")?;
        if source != self.source.as_ref() || identity(frontend, body)? != self.plan.procedure {
            return Err("relative static syntax differs from current issued body".into());
        }
        let mut plan = clone_semantics(&self.plan)?;
        for origin in &mut plan.origins {
            origin.span = shift(origin.span, body.expanded_span.start, self.source.len())?;
            origin.header_span = shift(
                origin.header_span,
                body.expanded_span.start,
                self.source.len(),
            )?;
        }
        let reusable = OnceLock::new();
        let _ = reusable.set(Arc::clone(self));
        Ok(Arc::new(IssuedStaticPlan {
            plan,
            snapshot:StaticSourceReceipt::new(frontend,body)?,
            body_span: body.expanded_span,
            source: Arc::clone(&self.source),
            reusable,
            syntax: {let current=frontend.body_code(body).map_err(|e|e.message)?;if self.syntax_code.as_ref().is_some_and(|code|same_syntax_profile(code,self.syntax_termination,&current)){self.syntax.clone()}else{None}},
            syntax_body:self.syntax_body,
        }))
    }
}
impl IssuedStaticPlan {
    pub fn retained_statement_body(&self)->Option<&Arc<super::StatementBody>>{self.syntax.as_ref()}
    /// Current original weak source owners, safe to inventory after strong
    /// payload destruction; no dead owner is dereferenced by this visitor.
    pub fn visit_weak_source_storage(&self,mut visit:impl FnMut(usize,usize,usize)){
        let snapshot=&self.snapshot;
        for (pointer,live,capacity) in [
            (snapshot.tree.as_ptr() as usize,snapshot.tree.strong_count()>0,std::mem::size_of::<crate::SemanticTree>()),
            (snapshot.occurrences.as_ptr() as usize,snapshot.occurrences.strong_count()>0,std::mem::size_of::<crate::OccurrenceTable>()),
        ]{visit(pointer,if live{capacity}else{0},capacity);}
        snapshot.code.visit_allocation_storage(&mut visit);
    }
    /// Resource-domain predicate only. Current source/code/termination authority
    /// is checked separately by require_current_source before native use.
    pub fn admitted_by(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<bool,super::BodySyntaxFailure>{
        let pending=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(super::BodySyntaxFailure::Operational(actual))}pending.map_err(super::BodySyntaxFailure::Operational)?;
        Ok(self.syntax.as_ref().and_then(|body|body.literal_admission.as_ref()).is_some_and(|lease|lease.is_admitted_by(a)))
    }
    pub(crate) fn source_occurrence(&self)->crate::OccurrenceId{self.snapshot.declaration}
    pub(crate) fn require_current_source(&self,frontend:&ColdFrontend,occurrence:crate::OccurrenceId)->Result<(),String>{
        let index=*frontend.body_by_declaration.get(&occurrence).ok_or("static source occurrence has no current body")?;
        let body=frontend.issued_bodies.get(index).ok_or("static source current body missing")?;
        if self.snapshot.declaration!=occurrence||self.body_span!=body.expanded_span||!self.snapshot.matches(frontend,body)?{
            return Err("static producer differs from current original body/code issuance".into());
        }
        Ok(())
    }
    /// The current issued source is already validated before this owner is used.
    pub fn canonical_declarations(
        &self,
    ) -> Result<Arc<[Arc<dm_ir::ProcedureStaticDeclaration>]>, String> {
        Ok(Arc::clone(
            self.relative_payload()?.canonical_declarations(),
        ))
    }
    pub fn plan(&self) -> &StaticPlan {
        &self.plan
    }
    pub fn source(&self) -> &Arc<str> {
        &self.source
    }
    pub fn retained_relative_payload(&self) -> Option<&Arc<RelativeStaticPlan>> {
        self.reusable.get()
    }
    pub fn relative_payload(&self) -> Result<Arc<RelativeStaticPlan>, String> {
        if let Some(payload) = self.reusable.get() {
            return Ok(Arc::clone(payload));
        }
        let mut plan = clone_semantics(&self.plan)?;
        for origin in &mut plan.origins {
            origin.span = relative(origin.span, self.body_span)?;
            origin.header_span = relative(origin.header_span, self.body_span)?;
        }
        let mut declarations: Vec<_> = plan.declarations.iter().cloned().map(Arc::new).collect();
        declarations.sort_by_key(|declaration| declaration.identity);
        let payload = Arc::new(RelativeStaticPlan {
            plan,
            source: Arc::clone(&self.source),
            declarations: declarations.into(),
            syntax_code:self.syntax.as_ref().map(|_|self.snapshot.code.clone()),
            syntax_termination:self.snapshot.termination,
            syntax:self.syntax.clone(),
            syntax_body:self.syntax_body,
        });
        let _ = self.reusable.set(payload);
        Ok(Arc::clone(
            self.reusable
                .get()
                .expect("relative static payload initialized"),
        ))
    }
}
fn clone_semantics(plan: &StaticPlan) -> Result<StaticPlan, String> {
    if !plan.executable_body.is_empty() {
        return Err("reusable static syntax cannot retain executable ASTs".into());
    }
    Ok(StaticPlan {
        procedure: plan.procedure,
        declarations: plan.declarations.clone(),
        origins: plan.origins.clone(),
        symbols: plan.symbols.clone(),
        executable_body: Vec::new(),
    })
}
fn relative(span: dm_syntax::Span, body: dm_syntax::Span) -> Result<dm_syntax::Span, String> {
    if span.start < body.start || span.start > span.end || span.end > body.end {
        return Err("static origin outside issued body".into());
    }
    Ok(dm_syntax::Span::new(
        span.start - body.start,
        span.end - body.start,
    ))
}
fn shift(span: dm_syntax::Span, start: usize, len: usize) -> Result<dm_syntax::Span, String> {
    if span.start > span.end || span.end > len {
        return Err("relative static origin outside current body".into());
    }
    Ok(dm_syntax::Span::new(
        start
            .checked_add(span.start)
            .ok_or("static origin offset overflow")?,
        start
            .checked_add(span.end)
            .ok_or("static origin offset overflow")?,
    ))
}
fn identity(frontend: &ColdFrontend, body: &BodyOccurrence) -> Result<ProcedureIdentity, String> {
    let tree = &frontend.snapshot.tree;
    let member = tree
        .member(body.member)
        .ok_or("static procedure member absent")?;
    let owner = tree
        .type_node(member.owner)
        .ok_or("static procedure owner absent")?
        .path;
    let verb = match member.kind {
        MemberKind::Proc => false,
        MemberKind::Verb => true,
        MemberKind::Var => return Err("static body is not a procedure".into()),
    };
    Ok(ProcedureIdentity {
        owner,
        name: member.name,
        verb,
        occurrence: tree
            .member_occurrence(body.member)
            .ok_or("static procedure chain empty")?,
    })
}
impl ParsedBody<'_> {
    pub fn capture_stored_declarations(
        &self,
        identity: ProcedureIdentity,
    ) -> Result<Arc<IssuedStaticPlan>, String> {
        self.issuer
            .validate_parsed_body(self, self.occurrence)
            .map_err(|e| format!("static body issuance: {e:?}"))?;
        if identity != self::identity(self.issuer, self.occurrence)? {
            return Err("static procedure identity differs from issued body".into());
        }
        self.static_receipt
            .get_or_init(|| {
                let plan = match self.statement_body() {
                    Some(body) => {
                        crate::procedure_statics::capture_issued_statements(identity, body)
                    }
                    None => crate::procedure_statics::capture_declarations(
                        identity,
                        &self.item().children,
                    ),
                }?;
                self.issuer
                    .compact_body(self.occurrence)
                    .map_err(|e| format!("static body issuance: {e:?}"))?;
                let source = self
                    .issuer
                    .expanded
                    .text
                    .get(self.occurrence.expanded_span.range())
                    .ok_or("static body source outside capture")?;
                Ok(Arc::new(IssuedStaticPlan {
                    plan,
                    snapshot:StaticSourceReceipt::new(self.issuer,self.occurrence)?,
                    body_span: self.occurrence.expanded_span,
                    source: Arc::from(source),
                    reusable: OnceLock::new(),
                    syntax:self.shared_statement_body(),
                    syntax_body:self.occurrence.expanded_span,
                }))
            })
            .clone()
    }
    pub fn stored_declaration_receipt(&self) -> Option<Arc<IssuedStaticPlan>> {
        self.static_receipt
            .get()
            .and_then(|result| result.as_ref().ok())
            .map(Arc::clone)
    }
}

/// A sealed alias of the SAME native body parent and exact Var RHS locator.
/// It contains no source text and performs no expression parse or AST copy.
#[derive(Clone)]
pub(crate) struct OriginalStaticInitializerRoot {
    body:Arc<super::StatementBody>,
    header:dm_syntax::Span,
    value:dm_syntax::Span,
    dimension:Option<usize>,
    original_body:dm_syntax::Span,
}
#[derive(Clone)]
pub(crate) struct OriginalStaticRootProvenance{body:Weak<super::StatementBody>,header:dm_syntax::Span,value:dm_syntax::Span,dimension:Option<usize>,original_body:dm_syntax::Span,root:usize}
impl OriginalStaticRootProvenance{
 pub(crate) fn matches(&self,current:&OriginalStaticInitializerRoot)->bool{
  Weak::ptr_eq(&self.body,&Arc::downgrade(&current.body))&&self.header==current.header&&self.value==current.value&&self.dimension==current.dimension&&self.original_body==current.original_body
 }
 pub(crate) fn matches_prepared(&self,current:&OriginalStaticInitializerRoot)->bool{self.matches(current)&&self.root==current.ast() as *const dm_syntax::Expr as usize}
 pub(crate) fn weak_backing_charge(&self)->usize{std::mem::size_of::<super::StatementBody>()}
 pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){visit(self.body.as_ptr() as usize,self.weak_backing_charge());}
}
impl OriginalStaticInitializerRoot {
    pub(crate) fn provenance(&self)->OriginalStaticRootProvenance{OriginalStaticRootProvenance{body:Arc::downgrade(&self.body),header:self.header,value:self.value,dimension:self.dimension,original_body:self.original_body,root:self.ast() as *const dm_syntax::Expr as usize}}

    pub(crate) fn parent(&self)->&Arc<super::StatementBody>{&self.body}
    pub(crate) fn ast(&self)->&dm_syntax::Expr{
        match self.dimension{None=>static_value(&self.body.parsed().statements,self.header),Some(index)=>static_dimension(&self.body,self.header,index)}
            .expect("private static root locator remains on immutable original body")
    }
    pub(crate) fn original_body(&self)->dm_syntax::Span{self.original_body}
    pub(crate) fn same_root(&self,other:&Self)->bool{
        Arc::ptr_eq(&self.body,&other.body)&&self.header==other.header&&self.value==other.value&&self.dimension==other.dimension
    }
    pub(crate) fn require_admission(&self,a:&dm_syntax::SettingAdmission<'_>)->Result<(),super::BodySyntaxFailure>{
        let status=a.checkpoint();if let Some(actual)=a.take_operational_error(){return Err(super::BodySyntaxFailure::Operational(actual))}status.map_err(super::BodySyntaxFailure::Operational)?;
        if !self.body.literal_admission.as_ref().is_some_and(|lease|lease.is_admitted_by(a)){
            return Err(super::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidInput,"static initializer requires SAME admitted original body counter")));
        }
        Ok(())
    }
    pub(crate) fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){
        visit(Arc::as_ptr(&self.body) as usize,std::mem::size_of::<super::StatementBody>());
        self.body.visit_literal_admission_storage(visit);
    }
}
/// Sorted source spans permit scalar, iterative descent to the original Var.
/// No per-reference whole-plan scan, auxiliary index, path Vec or recursion.
fn static_value(mut statements:&[dm_syntax::Statement],header:dm_syntax::Span)->Option<&dm_syntax::Expr>{
    use dm_syntax::StatementKind as K;
    fn contains(nodes:&[dm_syntax::Statement],span:dm_syntax::Span)->bool{
        nodes.first().zip(nodes.last()).is_some_and(|(first,last)|first.span.start<=span.start&&span.end<=last.span.end)
    }
    loop {
        let index=statements.partition_point(|statement|statement.span.end<=header.start);
        let statement=statements.get(index)?;
        if statement.span.start>header.start||statement.span.end<header.end{return None}
        statements=match &statement.kind{
            K::Var{value:Some(value),..} if statement.header_span==header=>return Some(value),
            K::If{then_branch,else_branch,..}=>if contains(then_branch,header){then_branch}else{else_branch},
            K::While{body,..}|K::DoWhile{body,..}|K::Spawn{body,..}|K::Label{body,..}|K::For{body,..}=>body,
            K::Try{body,catch_body,..}=>if contains(body,header){body}else{catch_body},
            K::Switch{cases,else_branch,..}=>cases.iter().find(|case|contains(&case.body,header)).map(|case|case.body.as_slice()).unwrap_or(else_branch),
            _=>return None,
        };
    }
}
impl IssuedStaticPlan {
    fn original_syntax_header(&self,identity:dm_ir::ProcedureStaticIdentity,header:dm_syntax::Span)->Result<(&Arc<super::StatementBody>,dm_syntax::Span),String>{
        let index=self.plan.origins.binary_search_by_key(&header.start,|origin|origin.header_span.start).map_err(|_|"static root header is not original producer origin")?;
        let origin=self.plan.origins.get(index).ok_or("static root origin unavailable")?;
        let declaration=self.plan.declarations.get(index).ok_or("static root declaration unavailable")?;
        if origin.header_span!=header||declaration.identity!=identity{return Err("static root does not match original declaration identity/header".into())}
        let body=self.syntax.as_ref().ok_or("static producer has no original typed body")?;
        let original_header=dm_syntax::Span::new(
            header.start.checked_sub(self.body_span.start).and_then(|v|v.checked_add(self.syntax_body.start)).ok_or("static header projection overflow")?,
            header.end.checked_sub(self.body_span.start).and_then(|v|v.checked_add(self.syntax_body.start)).ok_or("static header projection overflow")?);
        if original_header.start<self.syntax_body.start||original_header.end>self.syntax_body.end{return Err("static root header outside original body".into())}
        Ok((body,original_header))
    }
    pub(crate) fn original_initializer_root(&self,identity:dm_ir::ProcedureStaticIdentity,header:dm_syntax::Span)->Result<OriginalStaticInitializerRoot,String>{
        let (body,original_header)=self.original_syntax_header(identity,header)?;
        let value=static_value(&body.parsed().statements,original_header).ok_or("static producer original Var RHS unavailable")?;
        if value.span.start<original_header.start||value.span.end>original_header.end{return Err("static root RHS outside original header".into())}
        Ok(OriginalStaticInitializerRoot{body:Arc::clone(body),header:original_header,value:value.span,dimension:None,original_body:self.syntax_body})
    }
    pub(crate) fn original_dimension_root(&self,identity:dm_ir::ProcedureStaticIdentity,header:dm_syntax::Span,index:usize,count:usize)->Result<OriginalStaticInitializerRoot,String>{
        let (body,original_header)=self.original_syntax_header(identity,header)?;
        let [fact]=body.parsed().local_variables.in_span(original_header)? else{return Err("static dimension requires one original local declaration row".into())};
        let array=fact.array_syntax.as_ref().ok_or("original static dimension array ledger unavailable")?;
        if array.root.dimension_slots.len()!=count{return Err("static dimension count differs from original primary grammar".into())}
        let value=static_dimension(body,original_header,index).ok_or("original static dimension expression unavailable")?;
        if value.span.start<original_header.start||value.span.end>original_header.end{return Err("static dimension outside original declaration".into())}
        Ok(OriginalStaticInitializerRoot{body:Arc::clone(body),header:original_header,value:value.span,dimension:Some(index),original_body:self.syntax_body})
    }
    pub(crate) fn original_declaration(&self,header:dm_syntax::Span)->Option<&dm_ir::ProcedureStaticDeclaration>{
        let index=self.plan.origins.binary_search_by_key(&header.start,|origin|origin.header_span.start).ok()?;
        (self.plan.origins.get(index)?.header_span==header).then(||self.plan.declarations.get(index)).flatten()
    }
}

impl std::fmt::Debug for IssuedStaticPlan{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("IssuedStaticPlan").field("plan",&self.plan).field("body_span",&self.body_span).finish_non_exhaustive()}}
impl std::fmt::Debug for RelativeStaticPlan{fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.debug_struct("RelativeStaticPlan").field("plan",&self.plan).finish_non_exhaustive()}}

fn same_syntax_profile(code:&super::BodyCodeWeak,termination:dm_syntax::BodyTermination,current:&super::IssuedBodyCode<'_>)->bool{
 code.matches(current.identity())&&termination==current.termination()
}
#[cfg(test)]
mod static_syntax_profile_tests{
 use super::*;
 struct Source;
 impl dm_preprocess::SourceProvider for Source{fn read(&self,_:&std::path::Path)->Result<String,String>{Ok("/proc/p()\n    var/static/value=1+2\n    return value\n".into())}}
 #[test]
 fn same_original_body_code_cannot_retain_static_ast_under_changed_termination_profile(){
  let front=super::super::build(std::path::Path::new("static-profile.dme"),&Source,&Default::default(),1).unwrap();
  let current=front.body_code(&front.bodies[0]).unwrap();let code=crate::frontend::BodyCodeIdentity::downgrade(current.identity());
  assert!(same_syntax_profile(&code,current.termination(),&current));
  let changed=if current.termination()==dm_syntax::BodyTermination::Unknown{dm_syntax::BodyTermination::ExhaustedInput}else{dm_syntax::BodyTermination::Unknown};
  assert!(!same_syntax_profile(&code,changed,&current),"same actual code owner does not erase lexical termination proof");
 }
}

fn static_dimension(body:&super::StatementBody,header:dm_syntax::Span,index:usize)->Option<&dm_syntax::Expr>{
 let [fact]=body.parsed().local_variables.in_span(header).ok()? else{return None};
 let array=fact.array_syntax.as_ref()?;let slot=(*array.root.dimension_slots.get(index)?)?;array.root.dimensions.get(slot)
}

#[cfg(test)]#[test]fn actual_weak_code_locator_owner_widths_are_measured(){
 {#[allow(dead_code)]struct Prior{
    declaration:crate::OccurrenceId,
    tree:Weak<crate::SemanticTree>,
    occurrences:Weak<crate::OccurrenceTable>,
    code:std::sync::Weak<super::BodyCodeIdentity>,
    termination:dm_syntax::BodyTermination,
}
let old=std::mem::size_of::<Prior>();let new=std::mem::size_of::<StaticSourceReceipt>();eprintln!("WEAK_CODE_OWNER StaticSourceReceipt prior={old} current={new} delta={}",new as isize-old as isize);assert!(new<=old+std::mem::size_of::<usize>());}
 {#[allow(dead_code)]struct Prior{
    plan: StaticPlan,
    source: Arc<str>,
    declarations: Arc<[Arc<dm_ir::ProcedureStaticDeclaration>]>,
    syntax_code:Option<std::sync::Weak<super::BodyCodeIdentity>>,
    syntax_termination:dm_syntax::BodyTermination,
    syntax: Option<Arc<super::StatementBody>>,
    syntax_body: dm_syntax::Span,
}
let old=std::mem::size_of::<Prior>();let new=std::mem::size_of::<RelativeStaticPlan>();eprintln!("WEAK_CODE_OWNER RelativeStaticPlan prior={old} current={new} delta={}",new as isize-old as isize);assert!(new<=old+std::mem::size_of::<usize>());}
}
