//! Original immutable source-frame provenance. This does not certify a scalar
//! result; only the native ABI producer can pair it with successful evaluation.
use super::*;
pub struct OriginalAbiSourceInput<'source> {
    frontend: &'source ColdFrontend,
    body: &'source BodyOccurrence,
    code: &'source Arc<BodyCodeIdentity>,
    termination: dm_syntax::BodyTermination,
}
impl<'source> OriginalAbiSourceInput<'source> {
    pub(super) fn issue(
        frontend: &'source ColdFrontend,
        body: &BodyOccurrence,
        metadata: &dm_ir::ProcedureMetadata,
    ) -> Result<Self, BodySyntaxFailure> {
        let code = frontend
            .body_code(body)
            .map_err(BodySyntaxFailure::Syntax)?;
        let actual = code.occurrence();
        if !std::ptr::eq(body, actual) {
            return Err(BodySyntaxFailure::Syntax(internal(
                "ABI source body is not original current occurrence",
            )));
        }
        let current = frontend
            .snapshot
            .tree
            .member(actual.member)
            .and_then(|node| node.metadata.procedure.as_ref())
            .ok_or_else(|| {
                BodySyntaxFailure::Syntax(internal("ABI source metadata unavailable"))
            })?;
        if !std::ptr::eq(current.as_ref(), metadata) {
            return Err(BodySyntaxFailure::Syntax(internal(
                "ABI source metadata is not original current object",
            )));
        }
        Ok(Self {
            frontend,
            body: actual,
            code: &frontend.issued_body_codes[*frontend.body_by_declaration.get(&actual.declaration).ok_or_else(||BodySyntaxFailure::Syntax(internal("ABI source body ordinal unavailable")))?].identity,
            termination: code.termination(),
        })
    }
}
#[derive(Clone,Copy)]
pub enum OriginalAbiExpressionKind{Setting,ReturnAnnotation}
/// Storage provenance for ONE actually prepared root. Owner checks precede
/// warm-only slot borrowing; no source text, metadata clone or AST is retained.
pub struct OriginalAbiExpressionProvenance{owner:std::sync::Weak<crate::procedure::OriginalProcedureHeaders>,body:dm_syntax::Span,kind:OriginalAbiExpressionKind,ordinal:usize,count:usize,value:dm_syntax::Span,ast:usize}
impl OriginalAbiSourceInput<'_>{
 pub fn expression_provenance(&self,kind:OriginalAbiExpressionKind,expression:&dm_ir::SymbolicExpression,root:&dm_syntax::SettingExpression)->Result<OriginalAbiExpressionProvenance,BodySyntaxFailure>{
  let metadata=self.frontend.snapshot.tree.member(self.body.member).and_then(|node|node.metadata.procedure.as_deref()).ok_or_else(||BodySyntaxFailure::Syntax(internal("ABI source current metadata unavailable")))?;
  let (owner,body)=self.frontend.issued_syntax.abi_root_owner(self.body.expanded_span,self.code).map_err(|e|BodySyntaxFailure::Syntax(internal(&e.message)))?;
  let (ordinal,count,_value,offset,contains)=match kind{
   OriginalAbiExpressionKind::Setting=>{let source=self.frontend.original_setting_source(self.body,metadata,expression).map_err(BodySyntaxFailure::Syntax)?;source.require_expression(root).map_err(BodySyntaxFailure::Operational)?;let input=source.token_input();(input.ordinal,input.original_owner.settings.len(),input.original_value,input.offset,input.slots.contains_original(input.ordinal,root))},
   OriginalAbiExpressionKind::ReturnAnnotation=>{let input=self.frontend.issued_syntax.return_annotation_token_input(self.body.expanded_span,self.code,expression,metadata,self.frontend.snapshot.tree.symbols()).map_err(|e|BodySyntaxFailure::Syntax(internal(&e.message)))?;(input.ordinal,input.count,input.original_value,input.offset,input.slots.contains_original(input.ordinal,root))}
  };
  if !contains||root.current_offset()!=offset{return Err(BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::InvalidData,"ABI root is not original source slot")))}
  Ok(OriginalAbiExpressionProvenance{owner:Arc::downgrade(owner),body,kind,ordinal,count,value:root.original_expression().span,ast:root.original_expression() as *const dm_syntax::Expr as usize})
 }
}
impl OriginalAbiExpressionProvenance{
 pub fn matches(&self,current:&OriginalAbiSourceInput<'_>,a:&dm_syntax::SettingAdmission<'_>)->Result<bool,BodySyntaxFailure>{
  let pending=(||{
   a.checkpoint().map_err(BodySyntaxFailure::Operational)?;
   let (owner,body)=current.frontend.issued_syntax.abi_root_owner(current.body.expanded_span,current.code).map_err(|e|BodySyntaxFailure::Syntax(internal(&e.message)))?;
   if !self.owner.ptr_eq(&Arc::downgrade(owner))||self.body!=body{return Ok(false)}
   let root=current.frontend.issued_syntax.cached_abi_root(current.body.expanded_span,current.code,self.ordinal,self.count,matches!(self.kind,OriginalAbiExpressionKind::ReturnAnnotation),a).map_err(|error|match error{dm_syntax::SettingSyntaxFailure::Operational(actual)=>BodySyntaxFailure::Operational(actual),dm_syntax::SettingSyntaxFailure::Syntax(source)=>BodySyntaxFailure::Syntax(internal(&source.message))})?;
   Ok(root.is_retained_in(a)&&root.original_expression().span==self.value&&root.original_expression() as *const dm_syntax::Expr as usize==self.ast)
  })();if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}pending
 }
 pub fn weak_backing_charge()->usize{std::mem::size_of::<crate::procedure::OriginalProcedureHeaders>()}
 pub fn visit_storage(&self,mut visit:impl FnMut(usize,usize)){visit(self.owner.as_ptr() as usize,Self::weak_backing_charge())}
}

#[cfg(test)]mod tests{
 use super::*;use std::{path::Path,sync::atomic::{AtomicUsize,Ordering}};
 struct Source;impl dm_preprocess::SourceProvider for Source{fn read(&self,_:&Path)->Result<String,String>{Ok("/proc/p()\n    set waitfor=0\n    return\n/proc/q()\n    set waitfor=1\n    return\n".into())}}
 #[derive(Debug)]struct Host(Arc<AtomicUsize>);impl SettingExpressionQueries for Host{fn expression(&self,input:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{let check=||Ok(());let a=dm_syntax::SettingAdmission::new(&self.0,8*1024*1024,&check);input.prepare(&a)}}
 #[test]fn same_header_foreign_body_row_declines_before_unprepared_abi_slot(){
  let counter=Arc::new(AtomicUsize::new(0));let host=Arc::new(Host(counter.clone())) as Arc<dyn SettingExpressionQueries>;let front=build(Path::new("abi-source-row.dme"),&Source,&Default::default(),1).unwrap().with_setting_expression_queries(&host).unwrap();let context=front.original_declaration_expression_context().unwrap();let p=&front.bodies[0];let q=&front.bodies[1];let metadata=|body:&BodyOccurrence|front.snapshot.tree.member(body.member).unwrap().metadata.procedure.as_deref().unwrap();let pm=metadata(p);let qm=metadata(q);let dm_ir::ProcedureSettingNode::Setting(setting)=&pm.settings[0]else{panic!("actual source setting")};let root=front.setting_expression(p,pm,&setting.value).unwrap();let input=context.abi_source_input(p,pm).unwrap();let provenance=input.expression_provenance(OriginalAbiExpressionKind::Setting,&setting.value,&root).unwrap();let target=context.abi_source_input(q,qm).unwrap();
  let (left,_)=front.issued_syntax.abi_root_owner(p.expanded_span,input.code).unwrap();let (right,_)=front.issued_syntax.abi_root_owner(q.expanded_span,target.code).unwrap();assert!(Arc::ptr_eq(left,right),"real single source chunk owns both procedure rows");
  let before=counter.load(Ordering::Acquire);let check=||Ok(());let a=dm_syntax::SettingAdmission::new(&counter,8*1024*1024,&check);assert!(!provenance.matches(&target,&a).unwrap());assert_eq!(counter.load(Ordering::Acquire),before,"a different row cannot initialize even empty slot metadata");assert!(provenance.matches(&input,&a).unwrap());
 }
}
