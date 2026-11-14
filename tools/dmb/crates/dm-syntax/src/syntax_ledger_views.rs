//! Borrowed coordinate DATA over ONE original primary product. These views do
//! not grant a current source, parser issuance, semantic model, slot or compiler
//! acceptance. Only the current native recipe can establish those capabilities.
//! No expression parse, lazy literal preparation, AST clone or storage owner.
use crate::{Expr,ExprKind,Span,SyntaxProjection,ParameterSignature,ParameterSyntax,HeaderTypeDeclarationSyntax,ParameterInputSyntax,LocalVariableLedger,LocalVariableSyntax,ImplicitListInitializer,ControlOrigin,PendingBody};
#[derive(Debug)]pub enum SyntaxViewError{OutsideWindow,Unavailable(&'static str),Literal(crate::literal::PinnedStaticTextError)}
fn point(projection:SyntaxProjection,span:Span)->Result<Span,SyntaxViewError>{projection.span(span).ok_or(SyntaxViewError::OutsideWindow)}
#[derive(Clone,Copy)]pub struct ProjectedSyntaxExpr<'a>{original:&'a Expr,projection:SyntaxProjection}
impl<'a> ProjectedSyntaxExpr<'a>{
 pub fn new(original:&'a Expr,projection:SyntaxProjection)->Result<Self,SyntaxViewError>{point(projection,original.span)?;Ok(Self{original,projection})}
 pub fn original(self)->&'a Expr{self.original}
 pub fn span(self)->Span{self.projection.span(self.original.span).expect("constructor checked root window")}
 pub fn projection(self)->SyntaxProjection{self.projection}
 pub fn try_visit_children<E>(self,mut visit:impl FnMut(usize,Result<Self,SyntaxViewError>)->Result<(),E>)->Result<Result<(),SyntaxViewError>,E>{
  if let ExprKind::Literal(text)=&self.original.kind{if !text.owns_template_syntax(){return Ok(Ok(()))}let parts=match text.prepared_syntax_parts(){Some(Ok(Some(parts)))=>parts,Some(Ok(None))=>return Ok(Ok(())),Some(Err(_))=>return Ok(Err(SyntaxViewError::Literal(crate::literal::PinnedStaticTextError::DeferredSyntax))),None=>return Ok(Err(SyntaxViewError::Literal(crate::literal::PinnedStaticTextError::Unprepared)))};for(ordinal,child)in parts.expressions.iter().enumerate(){visit(ordinal,Self::new(child,self.projection))?;}Ok(Ok(()))}else{crate::try_for_each_expression_child(self.original,|ordinal,child|visit(ordinal,Self::new(child,self.projection)))?;Ok(Ok(()))}
 }
 pub fn literal_fragments(self)->Result<Option<impl Iterator<Item=Result<ProjectedLiteralFragment<'a>,SyntaxViewError>>+'a>,SyntaxViewError>{let ExprKind::Literal(text)=&self.original.kind else{return Err(SyntaxViewError::Unavailable("projected expression is not a literal"))};if !text.owns_template_syntax(){return Ok(None)}Ok(text.pinned_fragments().map_err(SyntaxViewError::Literal)?.map(move|fragments|fragments.map(move|fragment|fragment.map(|original|ProjectedLiteralFragment{original,projection:self.projection}).map_err(SyntaxViewError::Literal))))}
}
pub struct ProjectedLiteralFragment<'a>{original:crate::literal::PinnedLiteralFragment<'a>,projection:SyntaxProjection}
impl<'a> ProjectedLiteralFragment<'a>{
 pub fn expression(&self)->Result<Option<ProjectedSyntaxExpr<'a>>,SyntaxViewError>{self.original.expression().map(|root|ProjectedSyntaxExpr::new(root,self.projection)).transpose()}
 pub fn tokens(&self)->impl Iterator<Item=Result<(crate::TokenKind,Span),SyntaxViewError>>+'_ {self.original.tokens().map(move|token|{let(kind,span)=token.map_err(SyntaxViewError::Literal)?;Ok((kind,point(self.projection,span)?))})}
 pub fn token_text(&self,current:Span)->Result<&'a str,SyntaxViewError>{let original=self.projection.inverse().span(current).ok_or(SyntaxViewError::OutsideWindow)?;self.original.token_text(original).map_err(SyntaxViewError::Literal)}
 pub fn write_text(&self,out:&mut impl std::fmt::Write)->Result<(),SyntaxViewError>{self.original.write_text(out).map_err(SyntaxViewError::Literal)}
}
#[derive(Clone,Copy)]pub struct ProjectedParameterSignature<'a>{original:&'a ParameterSignature,projection:SyntaxProjection}
impl<'a> ProjectedParameterSignature<'a>{
 pub fn new(original:&'a ParameterSignature,projection:SyntaxProjection)->Result<Self,SyntaxViewError>{point(projection,original.header())?;Ok(Self{original,projection})}
 pub fn original(self)->&'a ParameterSignature{self.original}
 pub fn header(self)->Span{self.projection.span(self.original.header()).expect("constructor checked header window")}
 pub fn entries(self)->Result<impl Iterator<Item=ProjectedParameter<'a>>+'a,SyntaxViewError>{Ok(self.original.entries().map_err(SyntaxViewError::Unavailable)?.iter().map(move|original|ProjectedParameter{original,projection:self.projection}))}
 pub fn absolute_declarations(self)->Result<impl Iterator<Item=ProjectedHeaderTypeDeclaration<'a>>+'a,SyntaxViewError>{Ok(self.original.absolute_declarations().map_err(SyntaxViewError::Unavailable)?.iter().map(move|original|ProjectedHeaderTypeDeclaration{original,projection:self.projection}))}
}
#[derive(Clone,Copy)]pub struct ProjectedHeaderTypeDeclaration<'a>{original:&'a HeaderTypeDeclarationSyntax,projection:SyntaxProjection}
impl ProjectedHeaderTypeDeclaration<'_>{pub fn ordinal(self)->usize{self.original.ordinal()}pub fn span(self)->Result<Span,SyntaxViewError>{point(self.projection,self.original.span())}}
#[derive(Clone,Copy)]pub struct ProjectedParameter<'a>{original:&'a ParameterSyntax,projection:SyntaxProjection}
impl<'a> ProjectedParameter<'a>{
 pub fn original(self)->&'a ParameterSyntax{self.original}pub fn ordinal(self)->usize{self.original.ordinal()}pub fn variadic(self)->bool{self.original.variadic()}pub fn source_modifiers(self)->u8{self.original.source_modifiers()}
 pub fn name(self)->Result<Span,SyntaxViewError>{point(self.projection,self.original.name())}pub fn declaration_cursor(self)->Result<Span,SyntaxViewError>{point(self.projection,self.original.declaration_cursor())}
 pub fn type_components(self)->impl Iterator<Item=Result<Span,SyntaxViewError>>+'a{self.original.type_components().iter().copied().map(move|span|point(self.projection,span))}
 pub fn array_brackets(self)->impl Iterator<Item=Result<Span,SyntaxViewError>>+'a{self.original.array_brackets().iter().copied().map(move|span|point(self.projection,span))}
 fn expressions(self)->Result<Option<&'a crate::ParameterExpressions>,SyntaxViewError>{self.original.expressions().map_err(SyntaxViewError::Unavailable)}
 pub fn default(self)->Result<Option<ProjectedSyntaxExpr<'a>>,SyntaxViewError>{self.expressions()?.and_then(|roots|roots.default()).map(|root|ProjectedSyntaxExpr::new(root,self.projection)).transpose()}
 pub fn source(self)->Result<Option<ProjectedSyntaxExpr<'a>>,SyntaxViewError>{self.expressions()?.and_then(|roots|roots.source()).map(|root|ProjectedSyntaxExpr::new(root,self.projection)).transpose()}
 pub fn dimensions(self)->Result<impl Iterator<Item=Result<Option<ProjectedSyntaxExpr<'a>>,SyntaxViewError>>+'a,SyntaxViewError>{Ok(self.expressions()?.into_iter().flat_map(|roots|roots.dimensions().iter()).map(move|root|root.as_deref().map(|root|ProjectedSyntaxExpr::new(root,self.projection)).transpose()))}
 pub fn input(self)->Result<Option<ProjectedParameterInput<'a>>,SyntaxViewError>{Ok(self.expressions()?.and_then(|roots|roots.annotation()).map(|original|ProjectedParameterInput{original,projection:self.projection}))}
}
#[derive(Clone,Copy)]pub struct ProjectedParameterInput<'a>{original:&'a ParameterInputSyntax,projection:SyntaxProjection}
impl<'a> ProjectedParameterInput<'a>{pub fn original(self)->&'a ParameterInputSyntax{self.original}pub fn after_in(self)->bool{match self.original{ParameterInputSyntax::EmptyParens{after_in,..}|ParameterInputSyntax::Union{after_in,..}=>*after_in}}pub fn span(self)->Result<Span,SyntaxViewError>{point(self.projection,match self.original{ParameterInputSyntax::EmptyParens{span,..}|ParameterInputSyntax::Union{span,..}=>*span})}pub fn identifiers(self)->impl Iterator<Item=Result<Span,SyntaxViewError>>+'a{let ids:&'a[Span]=match self.original{ParameterInputSyntax::Union{identifiers,..}=>identifiers,_=>&[]};ids.iter().copied().map(move|span|point(self.projection,span))}}
#[derive(Clone,Copy)]pub struct ProjectedLocalLedger<'a>{original:&'a LocalVariableLedger,projection:SyntaxProjection}
impl<'a> ProjectedLocalLedger<'a>{pub fn new(original:&'a LocalVariableLedger,projection:SyntaxProjection)->Self{Self{original,projection}}pub fn entries(self)->Result<impl Iterator<Item=ProjectedLocal<'a>>+'a,SyntaxViewError>{Ok(self.original.entries().map_err(SyntaxViewError::Unavailable)?.iter().map(move|original|ProjectedLocal{original,projection:self.projection}))}}
#[derive(Clone,Copy)]pub struct ProjectedLocal<'a>{original:&'a LocalVariableSyntax,projection:SyntaxProjection}
impl<'a> ProjectedLocal<'a>{pub fn original(self)->&'a LocalVariableSyntax{self.original}pub fn source_kind(self)->crate::LocalSourceKind{self.original.source_kind}pub fn source_modifiers(self)->u8{self.original.source_modifiers}pub fn array_suffix(self)->bool{self.original.array_suffix}pub fn anchor(self)->Result<Span,SyntaxViewError>{point(self.projection,self.original.anchor)}pub fn name(self)->Result<Span,SyntaxViewError>{point(self.projection,self.original.name)}pub fn type_components(self)->impl Iterator<Item=Result<Span,SyntaxViewError>>+'a{self.original.type_components.iter().copied().map(move|span|point(self.projection,span))}pub fn array(self)->Option<ProjectedArrayInitializer<'a>>{self.original.array_syntax.as_ref().map(|array|ProjectedArrayInitializer{original:&array.root,explicit_initializer:array.explicit_initializer,projection:self.projection})}}
#[derive(Clone,Copy)]pub struct ProjectedArrayInitializer<'a>{original:&'a ImplicitListInitializer,explicit_initializer:bool,projection:SyntaxProjection}
impl<'a> ProjectedArrayInitializer<'a>{pub fn origin(self)->crate::ImplicitListOrigin{self.original.origin}pub fn explicit_initializer(self)->bool{self.explicit_initializer}pub fn dimension_slots(self)->&'a[Option<usize>]{&self.original.dimension_slots}pub fn brackets(self)->impl Iterator<Item=Result<Span,SyntaxViewError>>+'a{self.original.brackets.iter().copied().map(move|span|point(self.projection,span))}pub fn dimensions(self)->impl Iterator<Item=Result<ProjectedSyntaxExpr<'a>,SyntaxViewError>>+'a{self.original.dimensions.iter().map(move|root|ProjectedSyntaxExpr::new(root,self.projection))}}
#[derive(Clone,Copy)]pub struct ProjectedControlOrigins<'a>{original:&'a[ControlOrigin],projection:SyntaxProjection}
impl<'a> ProjectedControlOrigins<'a>{pub fn new(original:&'a[ControlOrigin],projection:SyntaxProjection)->Self{Self{original,projection}}pub fn entries(self)->impl Iterator<Item=Result<ControlOrigin,SyntaxViewError>>+'a{self.original.iter().map(move|original|Ok(ControlOrigin{condition:point(self.projection,original.condition)?,opening:point(self.projection,original.opening)?}))}pub fn opening_for(self,current_condition:Span)->Result<Option<Span>,SyntaxViewError>{let original=self.projection.inverse().span(current_condition).ok_or(SyntaxViewError::OutsideWindow)?;self.original.iter().find(|row|row.condition==original).map(|row|point(self.projection,row.opening)).transpose()}}
/// Old termination is deliberately not projected as current truth: a following
/// declaration/EOF edit can change it without changing this body's source.
#[derive(Clone,Copy)]pub struct ProjectedPendingBodies<'a>{original:&'a[PendingBody],projection:SyntaxProjection}
impl<'a> ProjectedPendingBodies<'a>{pub fn new(original:&'a[PendingBody],projection:SyntaxProjection)->Self{Self{original,projection}}pub fn headers(self)->impl Iterator<Item=Result<Span,SyntaxViewError>>+'a{self.original.iter().map(move|row|point(self.projection,row.header))}}

#[cfg(test)]mod tests{
 use super::*;
 fn raw(source:&str)->crate::ProcedureWithOrigins{let ast=crate::parse_declaration_skeleton(source);assert!(ast.diagnostics.is_empty());crate::parse_proc_with_origins_from_spans(source,ast.items[0].span,&ast.tokens,0).unwrap()}
 #[test]fn parameter_views_keep_every_original_private_root_and_project_actual_utf8_byte_points(){
  let source="/proc/p(obj/item/x[first()][2][] = list(\"e,()\", list(1,2)) as mob|obj|null in view(7), y=3, /datum/Absolute)\n    return x\n";let issued=raw(source);let prefix="// \u{e9}\u{6f22}\n";let current=format!("{prefix}{source}");let map=SyntaxProjection::new(Span::new(0,source.len()),Span::new(prefix.len(),current.len())).unwrap();let view=ProjectedParameterSignature::new(&issued.parameters,map).unwrap();assert!(std::ptr::eq(view.original(),&*issued.parameters));assert_eq!(&current[view.header().range()],&source[issued.parameters.header().range()]);
  let entries=view.entries().unwrap().collect::<Vec<_>>();assert_eq!(entries.len(),2);let x=entries[0];assert_eq!(&current[x.name().unwrap().range()],"x");assert_eq!(x.ordinal(),0);assert_eq!(x.array_brackets().count(),3);assert_eq!(x.type_components().map(|point|current[point.unwrap().range()].to_owned()).collect::<Vec<_>>(),["obj","item"]);let dimensions=x.dimensions().unwrap().collect::<Vec<_>>();assert_eq!(dimensions.len(),3);assert!(dimensions[2].as_ref().unwrap().is_none());let default=x.default().unwrap().unwrap();assert!(std::ptr::eq(default.original(),issued.parameters.entries().unwrap()[0].expressions().unwrap().unwrap().default().unwrap()));assert_eq!(&current[default.span().range()],&source[default.original().span.range()]);assert_eq!(&current[x.source().unwrap().unwrap().span().range()],"view(7)");assert_eq!(x.input().unwrap().unwrap().identifiers().map(|point|current[point.unwrap().range()].to_owned()).collect::<Vec<_>>(),["mob","obj","null"]);let declarations=view.absolute_declarations().unwrap().collect::<Vec<_>>();assert_eq!(declarations.len(),1);assert_eq!(&current[declarations[0].span().unwrap().range()],"/datum/Absolute");
  assert_eq!(map.inverse().span(x.name().unwrap()),Some(x.original().name()));assert!(ProjectedParameterSignature::new(&issued.parameters,SyntaxProjection::new(Span::new(0,1),Span::new(9,10)).unwrap()).is_err());
 }
 #[test]fn local_array_control_and_pending_views_preserve_native_ledgers_without_promoting_old_boundary_truth(){
  let source="/proc/p()\n    var/datum/value[first()][][second(1)]\n    if(1)\n        return\n    for(var/z in list())\n";let ast=crate::parse(source);assert!(ast.diagnostics.is_empty());let parsed=crate::parse_body_items_with_source(&ast.items[0].children,source);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);let prefix="// current prefix\n";let current=format!("{prefix}{source}");let map=SyntaxProjection::new(Span::new(0,source.len()),Span::new(prefix.len(),current.len())).unwrap();let rows=ProjectedLocalLedger::new(&parsed.local_variables,map).entries().unwrap().collect::<Vec<_>>();let value=rows.iter().copied().find(|row|&current[row.name().unwrap().range()]=="value").unwrap();assert_eq!(&current[value.anchor().unwrap().range()],"var");let array=value.array().unwrap();assert_eq!(array.origin(),crate::ImplicitListOrigin::ParserSynthetic);assert_eq!(array.brackets().count(),3);assert_eq!(array.dimension_slots(),[Some(0),None,Some(1)]);let roots=array.dimensions().map(Result::unwrap).collect::<Vec<_>>();assert_eq!(roots.len(),2);assert_eq!(&current[roots[0].span().range()],"first()");assert_eq!(&current[roots[1].span().range()],"second(1)");assert!(std::ptr::eq(roots[0].original(),&value.original().array_syntax.as_ref().unwrap().root.dimensions[0]));
  let origins=ProjectedControlOrigins::new(&parsed.control_origins,map);assert!(!parsed.control_origins.is_empty());for(original,projected)in parsed.control_origins.iter().zip(origins.entries()){let projected=projected.unwrap();assert_eq!(origins.opening_for(projected.condition).unwrap(),Some(projected.opening));assert_eq!(&source[original.opening.range()],&current[projected.opening.range()]);}assert!(!parsed.pending_bodies.is_empty());let headers=ProjectedPendingBodies::new(&parsed.pending_bodies,map).headers().map(Result::unwrap).collect::<Vec<_>>();assert_eq!(headers.len(),parsed.pending_bodies.len());for(old,new)in parsed.pending_bodies.iter().zip(headers){assert_eq!(&source[old.header.range()],&current[new.range()]);}
 }
 #[test]fn literal_views_never_prepare_or_clone_original_interpolation_and_keep_native_consumer_errors(){
  let number=crate::parse_expression("123").expr.unwrap();let plain=ProjectedSyntaxExpr::new(&number,SyntaxProjection::new(number.span,number.span).unwrap()).unwrap();assert!(plain.literal_fragments().unwrap().is_none());assert!(plain.try_visit_children::<std::convert::Infallible>(|_,_|panic!("plain numeric grammar has no interpolation child")).unwrap().is_ok());
  let mut expression=crate::parse_expression("\"a[x]b[f(1)]c\"").expr.unwrap();crate::shift_expression(&mut expression,100);let original_origin=expression.span.start;let extent=expression.span.end-expression.span.start;let map=SyntaxProjection::new(expression.span,Span::new(7,7+extent)).unwrap();let view=ProjectedSyntaxExpr::new(&expression,map).unwrap();let before=crate::literal::literal_child_parses_for_test();let mut calls=0;let unprepared=view.try_visit_children::<std::convert::Infallible>(|_,_|{calls+=1;Ok(())}).unwrap();assert!(matches!(unprepared,Err(SyntaxViewError::Literal(crate::literal::PinnedStaticTextError::Unprepared))));assert_eq!(calls,0);assert_eq!(crate::literal::literal_child_parses_for_test(),before);
  let ExprKind::Literal(text)=&expression.kind else{panic!("literal")};text.parts().unwrap();let before=crate::literal::literal_child_parses_for_test();let original=text.prepared_syntax_parts().unwrap().unwrap().unwrap();let fragments=view.literal_fragments().unwrap().unwrap().map(Result::unwrap).collect::<Vec<_>>();let projected=fragments.iter().filter_map(|fragment|fragment.expression().unwrap()).collect::<Vec<_>>();assert_eq!(projected.len(),2);for(old,new)in original.expressions.iter().zip(projected){assert!(std::ptr::eq(old,new.original()));assert_eq!(new.span(),map.span(old.span).unwrap());}for fragment in &fragments{for token in fragment.tokens(){let(_,span)=token.unwrap();let original=map.inverse().span(span).unwrap();assert_eq!(fragment.token_text(span).unwrap(),&text.as_str()[original.start-original_origin..original.end-original_origin]);}}
  let mut calls=0;let failed=view.try_visit_children(|_,child|{child.unwrap();calls+=1;Err(std::io::Error::from_raw_os_error(1450))});assert_eq!(failed.unwrap_err().raw_os_error(),Some(1450));assert_eq!(calls,1);assert_eq!(crate::literal::literal_child_parses_for_test(),before);
 }
}

/// Borrowed authored statement structure with all current points explicit.
#[derive(Clone,Copy)]pub struct ProjectedStatements<'a>{original:&'a[crate::Statement],projection:SyntaxProjection}
impl<'a> ProjectedStatements<'a>{pub fn new(original:&'a[crate::Statement],projection:SyntaxProjection)->Self{Self{original,projection}}pub fn iter(self)->impl Iterator<Item=Result<ProjectedStatement<'a>,SyntaxViewError>>+'a{self.original.iter().map(move|original|ProjectedStatement::new(original,self.projection))}pub fn len(self)->usize{self.original.len()}pub fn is_empty(self)->bool{self.original.is_empty()}}
#[derive(Clone,Copy)]pub struct ProjectedStatement<'a>{original:&'a crate::Statement,projection:SyntaxProjection}
impl<'a> ProjectedStatement<'a>{
 pub fn new(original:&'a crate::Statement,projection:SyntaxProjection)->Result<Self,SyntaxViewError>{point(projection,original.span)?;point(projection,original.header_span)?;Ok(Self{original,projection})}
 pub fn original(self)->&'a crate::Statement{self.original}pub fn span(self)->Span{self.projection.span(self.original.span).expect("constructor checked statement window")}pub fn header_span(self)->Span{self.projection.span(self.original.header_span).expect("constructor checked header window")}pub fn raw_header(self)->&'a str{&self.original.raw_header}
 pub fn kind(self)->Result<ProjectedStatementKind<'a>,SyntaxViewError>{
  let expr=|root:&'a Expr|ProjectedSyntaxExpr::new(root,self.projection);let branch=|rows:&'a[crate::Statement]|ProjectedStatements::new(rows,self.projection);
  use crate::StatementKind as S;Ok(match &self.original.kind{
   S::If{condition,then_branch,else_branch}=>ProjectedStatementKind::If{condition:expr(condition)?,then_branch:branch(then_branch),else_branch:branch(else_branch)},
   S::While{condition,body}=>ProjectedStatementKind::While{condition:expr(condition)?,body:branch(body)},
   S::DoWhile{body,condition}=>ProjectedStatementKind::DoWhile{body:branch(body),condition:expr(condition)?},
   S::Spawn{delay,body}=>ProjectedStatementKind::Spawn{delay:delay.as_ref().map(expr).transpose()?,body:branch(body)},
   S::Set{attribute,relation,value}=>ProjectedStatementKind::Set{attribute,relation,value:expr(value)?},
   S::ProjectedSet{attribute,relation,value}=>ProjectedStatementKind::ProjectedSet{attribute,relation,value:ProjectedSettingExpression::new(value,self.projection)?},
   S::For{control,body}=>ProjectedStatementKind::For{control:ProjectedForControl::new(control,self.projection)?,body:branch(body)},
   S::Switch{selector,cases,else_branch,default_present}=>ProjectedStatementKind::Switch{selector:expr(selector)?,cases:ProjectedSwitchCases{original:cases,projection:self.projection},else_branch:branch(else_branch),default_present:*default_present},
   S::Try{body,catch_binding,catch_parameter_count,catch_header_span,catch_body}=>ProjectedStatementKind::Try{body:branch(body),catch_binding:catch_binding.as_deref(),catch_parameter_count:*catch_parameter_count,catch_header_span:point(self.projection,*catch_header_span)?,catch_body:branch(catch_body)},
   S::Throw(value)=>ProjectedStatementKind::Throw(expr(value)?),S::Delete(value)=>ProjectedStatementKind::Delete(expr(value)?),S::Label{name,body}=>ProjectedStatementKind::Label{name,body:branch(body)},S::Goto(name)=>ProjectedStatementKind::Goto(name),
   S::Return(value)=>ProjectedStatementKind::Return(value.as_ref().map(expr).transpose()?),S::Var{declaration,value}=>ProjectedStatementKind::Var{declaration,value:value.as_ref().map(expr).transpose()?},
   S::Assign{target,op,value}=>ProjectedStatementKind::Assign{target:expr(target)?,op,value:expr(value)?},S::Call(value)=>ProjectedStatementKind::Call(expr(value)?),S::Expression(value)=>ProjectedStatementKind::Expression(expr(value)?),
   S::Break=>ProjectedStatementKind::Break,S::BreakLabel(name)=>ProjectedStatementKind::BreakLabel(name),S::Continue=>ProjectedStatementKind::Continue,S::ContinueLabel(name)=>ProjectedStatementKind::ContinueLabel(name),S::Unsupported=>ProjectedStatementKind::Unsupported,
  })
 }
}
pub enum ProjectedStatementKind<'a>{
 If{condition:ProjectedSyntaxExpr<'a>,then_branch:ProjectedStatements<'a>,else_branch:ProjectedStatements<'a>},While{condition:ProjectedSyntaxExpr<'a>,body:ProjectedStatements<'a>},DoWhile{body:ProjectedStatements<'a>,condition:ProjectedSyntaxExpr<'a>},Spawn{delay:Option<ProjectedSyntaxExpr<'a>>,body:ProjectedStatements<'a>},
 Set{attribute:&'a str,relation:&'a str,value:ProjectedSyntaxExpr<'a>},ProjectedSet{attribute:&'a str,relation:&'a str,value:ProjectedSettingExpression<'a>},
 For{control:ProjectedForControl<'a>,body:ProjectedStatements<'a>},Switch{selector:ProjectedSyntaxExpr<'a>,cases:ProjectedSwitchCases<'a>,else_branch:ProjectedStatements<'a>,default_present:bool},
 Try{body:ProjectedStatements<'a>,catch_binding:Option<&'a str>,catch_parameter_count:usize,catch_header_span:Span,catch_body:ProjectedStatements<'a>},Throw(ProjectedSyntaxExpr<'a>),Delete(ProjectedSyntaxExpr<'a>),Label{name:&'a str,body:ProjectedStatements<'a>},Goto(&'a str),Return(Option<ProjectedSyntaxExpr<'a>>),Var{declaration:&'a str,value:Option<ProjectedSyntaxExpr<'a>>},Assign{target:ProjectedSyntaxExpr<'a>,op:&'a str,value:ProjectedSyntaxExpr<'a>},Call(ProjectedSyntaxExpr<'a>),Expression(ProjectedSyntaxExpr<'a>),Break,BreakLabel(&'a str),Continue,ContinueLabel(&'a str),Unsupported
}
pub enum ProjectedForInitializer<'a>{Declare{declaration:&'a str,value:Option<ProjectedSyntaxExpr<'a>>},Expr(ProjectedSyntaxExpr<'a>)}
pub enum ProjectedForControl<'a>{All{declaration:&'a str,source_binding:Option<Span>},Each{binding:&'a str,source_binding:Option<Span>,iterable:ProjectedSyntaxExpr<'a>},Pair{key_binding:&'a str,value_binding:&'a str,iterable:ProjectedSyntaxExpr<'a>},Range{binding:&'a str,start:ProjectedSyntaxExpr<'a>,end:ProjectedSyntaxExpr<'a>,step:Option<ProjectedSyntaxExpr<'a>>},RangeImplicitArray{binding:&'a str,end:ProjectedSyntaxExpr<'a>,step:Option<ProjectedSyntaxExpr<'a>>},CStyle{initializer:Option<ProjectedForInitializer<'a>>,condition:Option<ProjectedSyntaxExpr<'a>>,step:Option<ProjectedSyntaxExpr<'a>>}}
impl<'a> ProjectedForControl<'a>{fn new(original:&'a crate::ForControl,projection:SyntaxProjection)->Result<Self,SyntaxViewError>{let expr=|root:&'a Expr|ProjectedSyntaxExpr::new(root,projection);use crate::ForControl as F;Ok(match original{F::All{declaration,source_binding}=>Self::All{declaration,source_binding:source_binding.as_ref().map(|binding|point(projection,binding.name())).transpose()?},F::Each{binding,source_binding,iterable}=>Self::Each{binding,source_binding:source_binding.as_ref().map(|binding|point(projection,binding.name())).transpose()?,iterable:expr(iterable)?},F::Pair{key_binding,value_binding,iterable}=>Self::Pair{key_binding,value_binding,iterable:expr(iterable)?},F::Range{binding,start,end,step}=>Self::Range{binding,start:expr(start)?,end:expr(end)?,step:step.as_ref().map(expr).transpose()?},F::RangeImplicitArray{binding,end,step}=>Self::RangeImplicitArray{binding,end:expr(end)?,step:step.as_ref().map(expr).transpose()?},F::CStyle{initializer,condition,step}=>Self::CStyle{initializer:initializer.as_ref().map(|initializer|Ok::<_,SyntaxViewError>(match initializer{crate::ForInitializer::Declare{declaration,value}=>ProjectedForInitializer::Declare{declaration,value:value.as_ref().map(expr).transpose()?},crate::ForInitializer::Expr(value)=>ProjectedForInitializer::Expr(expr(value)?)})).transpose()?,condition:condition.as_ref().map(expr).transpose()?,step:step.as_ref().map(expr).transpose()?}})}}
#[derive(Clone,Copy)]pub struct ProjectedSwitchCases<'a>{original:&'a[crate::SwitchCase],projection:SyntaxProjection}
impl<'a> ProjectedSwitchCases<'a>{pub fn iter(self)->impl Iterator<Item=ProjectedSwitchCase<'a>>+'a{self.original.iter().map(move|original|ProjectedSwitchCase{original,projection:self.projection})}}
#[derive(Clone,Copy)]pub struct ProjectedSwitchCase<'a>{original:&'a crate::SwitchCase,projection:SyntaxProjection}
pub enum ProjectedSwitchAlternative<'a>{Exact(ProjectedSyntaxExpr<'a>),Range(ProjectedSyntaxExpr<'a>,ProjectedSyntaxExpr<'a>)}
impl<'a> ProjectedSwitchCase<'a>{
 /// Authored case geometry only. A reader cursor must be reissued from
 /// current source because its continuation can escape the retained body.
 pub fn projected_case_site(self)->Result<(Span,Span),SyntaxViewError>{let site=self.original.original_site;Ok((point(self.projection,site.header)?,point(self.projection,site.body)?))}
 pub fn projected_cursor(self)->Result<crate::OriginalCaseCursor,SyntaxViewError>{let cursor=self.original.original_site.cursor.map_err(SyntaxViewError::Unavailable)?;Ok(match cursor{crate::OriginalCaseCursor::Token(at)=>crate::OriginalCaseCursor::Token(point(self.projection,at)?),crate::OriginalCaseCursor::SourceEnd{offset,fallback}=>crate::OriginalCaseCursor::SourceEnd{offset:point(self.projection,Span::new(offset,offset))?.start,fallback:point(self.projection,fallback)?}})}
 pub fn alternatives(self)->impl Iterator<Item=Result<ProjectedSwitchAlternative<'a>,SyntaxViewError>>+'a{self.original.alternatives.iter().map(move|alternative|Ok(match alternative{crate::SwitchAlternative::Exact(root)=>ProjectedSwitchAlternative::Exact(ProjectedSyntaxExpr::new(root,self.projection)?),crate::SwitchAlternative::Range(start,end)=>ProjectedSwitchAlternative::Range(ProjectedSyntaxExpr::new(start,self.projection)?,ProjectedSyntaxExpr::new(end,self.projection)?)}))}
 pub fn body(self)->ProjectedStatements<'a>{ProjectedStatements::new(&self.original.body,self.projection)}
}

#[cfg(test)]mod statement_tests{
 use super::*;
 #[test]fn borrowed_statement_views_keep_real_branches_and_ranges_without_copying_authored_nodes(){
  let source="/proc/p(x)\n    if(x)\n        return 1\n    else\n        return 2\n    for(var/i=0; i<2; i++)\n        continue\n    switch(x)\n        if(1 to 2)\n            break\n        else\n            return\n    try\n        throw x\n    catch(var/e)\n        return e\n";let ast=crate::parse(source);assert!(ast.diagnostics.is_empty());let parsed=crate::parse_body_items_with_source(&ast.items[0].children,source);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);let map=SyntaxProjection::new(Span::new(0,source.len()),Span::new(200,200+source.len())).unwrap();let rows=ProjectedStatements::new(&parsed.statements,map).iter().map(Result::unwrap).collect::<Vec<_>>();assert_eq!(rows.len(),4);for(old,new)in parsed.statements.iter().zip(rows.iter()){assert!(std::ptr::eq(old,new.original()));assert_eq!(new.header_span(),map.span(old.header_span).unwrap());}
  let ProjectedStatementKind::If{condition,then_branch,else_branch}=rows[0].kind().unwrap()else{panic!("if")};assert_eq!(condition.span(),map.span(condition.original().span).unwrap());assert_eq!(then_branch.len(),1);assert_eq!(else_branch.len(),1);assert!(matches!(then_branch.iter().next().unwrap().unwrap().kind().unwrap(),ProjectedStatementKind::Return(Some(_))));
  let ProjectedStatementKind::For{control:ProjectedForControl::CStyle{initializer:Some(ProjectedForInitializer::Declare{..}),condition:Some(_),step:Some(_)},body}=rows[1].kind().unwrap()else{panic!("native C-style control")};assert_eq!(body.len(),1);
  let ProjectedStatementKind::Switch{cases,default_present,else_branch,..}=rows[2].kind().unwrap()else{panic!("switch")};assert!(default_present);assert_eq!(else_branch.len(),1);let case=cases.iter().next().unwrap();assert!(matches!(case.alternatives().next().unwrap().unwrap(),ProjectedSwitchAlternative::Range(_,_)));assert!(case.projected_cursor().is_err(),"no original cursor provider in this real ordinary parse, never fabricate a point");
  let ProjectedStatementKind::Try{catch_parameter_count,catch_binding,catch_body,..}=rows[3].kind().unwrap()else{panic!("try/catch")};assert_eq!(catch_parameter_count,1);assert!(catch_binding.is_some());assert_eq!(catch_body.len(),1);
 }
 #[test]fn setting_statement_rebinding_keeps_real_original_root_and_rejects_wrong_source_window(){
  let source="/proc/p()\n    set mystery=1+2\n    return\n";let ast=crate::parse(source);let tokens=crate::lex_spans(source);let begin=source.find("1+2").unwrap();let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<22,&||Ok(()));let first=tokens.tokens.partition_point(|token|token.span.end<=begin);let last=tokens.tokens.partition_point(|token|token.span.start<begin+3);let root=crate::prepare_setting_expression(source,&tokens.tokens[first..last],Span::new(begin,begin+3),&a).unwrap().project_current(0,source.len()).unwrap();
  struct Provider<'a>(&'a crate::SettingExpression);impl crate::SettingSyntaxProvider for Provider<'_>{fn setting(&self,_:&crate::Item)->Result<crate::SettingStatement,crate::Diagnostic>{Ok(crate::SettingStatement{attribute:"mystery".into(),relation:"=".into(),value:self.0.clone()})}}
  let parsed=crate::parse_body_items_with_context_and_settings(&ast.items[0].children,source,&|_|None,&Provider(&root),&a);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);let map=SyntaxProjection::new(Span::new(0,source.len()),Span::new(500,500+source.len())).unwrap();let row=ProjectedStatements::new(&parsed.statements,map).iter().next().unwrap().unwrap();let ProjectedStatementKind::ProjectedSet{value,..}=row.kind().unwrap()else{panic!("same original projected setting")};assert!(value.same_root(&root));assert!(std::ptr::eq(value.original_expression(),root.original_expression()));assert_eq!(value.current_span(),Span::new(begin+500,begin+503));assert!(value.is_retained_in(&a));let wrong=SyntaxProjection::new(Span::new(1,begin+1),Span::new(800,800+begin)).unwrap();assert!(ProjectedStatement::new(&parsed.statements[0],wrong).is_err(),"a body-only/foreign coordinate window cannot impersonate the actual setting source owner");
 }
}

/// Borrowed current-coordinate DATA over ONE canonical retained setting root.
/// This is not a completed current header slot or a current model issuer.
/// The original root keeps its ENTIRE original source extent/resource owner;
/// the separate expression view maps only actually issued expression points.
#[derive(Clone,Copy)]
pub struct ProjectedSettingExpression<'a>{original:&'a crate::SettingExpression,expression:ProjectedSyntaxExpr<'a>}
impl<'a> ProjectedSettingExpression<'a>{
 pub fn new(original:&'a crate::SettingExpression,body:SyntaxProjection)->Result<Self,SyntaxViewError>{
  let original_expression=original.original_expression();
  let old=original.current_span();let current=point(body,old)?;
  let projection=SyntaxProjection::new(original_expression.span,current).map_err(|_|SyntaxViewError::OutsideWindow)?;
  Ok(Self{original,expression:ProjectedSyntaxExpr::new(original_expression,projection)?})
 }
 pub fn original(self)->&'a crate::SettingExpression{self.original}
 pub fn original_source_window(self)->Span{self.original.current_projection().original()}
 pub fn expression(self)->ProjectedSyntaxExpr<'a>{self.expression}
 pub fn original_expression(self)->&'a Expr{self.original.original_expression()}
 pub fn current_span(self)->Span{self.expression.span()}
 pub fn current_span_of(self,expression:&Expr)->Option<Span>{self.expression.projection().span(expression.span)}
 pub fn same_root(self,other:&crate::SettingExpression)->bool{self.original.same_root(other)}
 pub fn is_retained_in(self,a:&crate::SettingAdmission<'_>)->bool{self.original.is_retained_in(a)}
}
#[cfg(test)]mod current_setting_view_tests{
 use super::*;use std::sync::{atomic::{Ordering}};
 #[test]fn same_chunk_earlier_shift_setting_view_keeps_original_extent_and_root_without_fake_unsigned_origin(){
  let source=format!("{}list(1,list(2,3))"," ".repeat(1000));let tokens=crate::lex_spans(&source);let counter=crate::SettingChargeCounter::try_new(crate::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=crate::SettingAdmission::new(&counter,1<<24,&||Ok(()));let at=source.find("list").unwrap();
  let first=tokens.tokens.partition_point(|token|token.span.end<=at);let last=tokens.tokens.partition_point(|token|token.span.start<source.len());let root=crate::prepare_setting_expression(&source,&tokens.tokens[first..last],Span::new(at,source.len()),&a).unwrap().project_current(0,source.len()).unwrap();let used=counter.load(Ordering::Acquire);
  let body=SyntaxProjection::new(Span::new(900,source.len()),Span::new(10,10+source.len()-900)).unwrap();let view=ProjectedSettingExpression::new(&root,body).unwrap();
  assert_eq!(view.current_span(),Span::new(110,110+source.len()-1000));assert_eq!(view.original_source_window(),Span::new(0,source.len()));assert!(view.same_root(&root));assert!(std::ptr::eq(view.original_expression(),root.original_expression()));assert!(view.is_retained_in(&a));assert_eq!(counter.load(Ordering::Acquire),used);
  let mut children=Vec::new();view.expression().try_visit_children(|_,child|{children.push(child.unwrap().span());Ok::<(),()>(())}).unwrap().unwrap();assert!(!children.is_empty());assert!(children.iter().all(|span|span.start>=110&&span.end<=view.current_span().end));
  let wrong=SyntaxProjection::new(Span::new(0,at),Span::new(500,500+at)).unwrap();assert!(ProjectedSettingExpression::new(&root,wrong).is_err());assert_eq!(root.current_offset(),0,"old root binding remains truthful and unchanged");
 }
}

#[cfg(test)]mod for_binding_projection_tests{
 use super::*;
 #[test]fn projected_for_bindings_borrow_actual_name_spans_and_reject_foreign_windows(){
  let source="/proc/p()\n    for(var/obj/item/tool)\n        continue\n    for(var/obj/item/tool in things)\n        continue\n";let ast=crate::parse(source);assert!(ast.diagnostics.is_empty());let parsed=crate::parse_body_items_with_source(&ast.items[0].children,source);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);assert_eq!(parsed.statements.len(),2);let projection=SyntaxProjection::new(Span::new(0,source.len()),Span::new(200,200+source.len())).unwrap();
  for statement in &parsed.statements{let crate::StatementKind::For{control,..}=&statement.kind else{panic!("actual for-list")};let original=match control{crate::ForControl::All{source_binding,..}|crate::ForControl::Each{source_binding,..}=>source_binding.expect("actual header tokens issue the name component").name(),_=>panic!("actual all/each")};assert_eq!(&source[original.start..original.end],"tool");let view=ProjectedForControl::new(control,projection).unwrap();let projected=match view{ProjectedForControl::All{source_binding,..}|ProjectedForControl::Each{source_binding,..}=>source_binding.expect("same real name"),_=>panic!("same all/each")};assert_eq!(projected,projection.span(original).unwrap());let wrong=SyntaxProjection::new(Span::new(0,original.start),Span::new(500,500+original.start)).unwrap();assert!(matches!(ProjectedForControl::new(control,wrong),Err(SyntaxViewError::OutsideWindow)));}
 }
}
