//! Native borrowed projection for the unique ACT_TRY pairing CFG.
//! Actual current BODY/query/source authority stays with the enclosing report.
use crate::{sem_handlers_pair_policy as pair,key_policy_control::{self as kc,Control},reactive_reads_native::Failure};
use dm_syntax::{Expr,ExprKind,Statement,StatementKind,ForControl,SwitchAlternative,LocalSourceKind,VisitDecision};
fn ungroup(mut e:&Expr)->&Expr{while let ExprKind::Group(inner)=&e.kind{e=inner}e}
fn bare(e:&Expr)->Option<&str>{if let ExprKind::Ident(name)=&ungroup(e).kind{Some(name)}else{None}}
fn ordinary(e:&Expr)->Option<(&str,&[Expr])>{if let ExprKind::Call{callee,args}=&ungroup(e).kind{if let ExprKind::Ident(name)=&callee.kind{if dm_analysis::original_base_terms::ordinary_call_name(name){return Some((name,args))}}}None}
fn call(e:&Expr)->Option<(&str,&[Expr])>{if let ExprKind::Call{callee,args}=&e.kind{match &callee.kind{ExprKind::Ident(name)if dm_analysis::original_base_terms::ordinary_call_name(name)=>Some((name,args)),ExprKind::Member{selector,..}|ExprKind::SafeMember{selector,..}=>Some((selector,args)),_=>None}}else{None}}
struct Scan<'a,C,F>{c:&'a mut C,visit:&'a mut F,error:Option<Failure>}
impl<C:Control<Error=Failure>,F:FnMut(&Expr,&mut C)->Result<(),Failure>> Scan<'_,C,F>{fn fail(&mut self,error:Failure)->VisitDecision{if self.error.is_none(){self.error=Some(error)}VisitDecision::Stop}}
impl<C:Control<Error=Failure>,F:FnMut(&Expr,&mut C)->Result<(),Failure>> dm_analysis::policy_body_observation::BaseChainVisitor for Scan<'_,C,F>{
 fn statement(&mut self,_:&Statement)->VisitDecision{if self.error.is_some(){VisitDecision::Stop}else{VisitDecision::Descend}}
 fn expression(&mut self,e:&Expr,_:bool)->VisitDecision{if self.error.is_some(){return VisitDecision::Stop}match self.c.checkpoint().and_then(|()|(self.visit)(e,self.c)){Ok(())=>VisitDecision::Descend,Err(error)=>self.fail(error)}}
 fn projected_expression(&mut self,e:dm_syntax::ProjectedExprView<'_>,child:bool)->VisitDecision{self.expression(e.original(),child)}
 fn frame_capacity(&mut self,n:usize)->Result<(),&'static str>{match self.c.reserve(n){Ok(())=>Ok(()),Err(error)=>{self.fail(error);Err("pair scan admission refused")}}}
 fn frame_overflow(&mut self)->&'static str{let e=self.c.overflow();self.fail(e);"pair scan overflow"}fn frame_allocation_failed(&mut self)->&'static str{let e=self.c.allocation_failed();self.fail(e);"pair scan allocation refused"}
}
fn scan_result<C,F>(visitor:Scan<'_,C,F>,coverage:Result<(),&'static str>)->Result<(),Failure>{if let Some(actual)=visitor.error{return Err(actual)}coverage.map_err(Failure::from)}
/// Callbacks borrow actual current source/Debug loans; no default boolean answer.
pub(crate) struct Syntax<'a,L,D>{pub view:dm_syntax::StatementView<'a>,pub locals:dm_tree::frontend::SourceLocalView<'a>,pub try_calls:&'a[&'a str],pub line:L,pub refusal_debug:D}
impl<C,L,D> pair::Syntax<C> for Syntax<'_,L,D>where C:Control<Error=Failure>,L:Fn(dm_syntax::Span)->Result<u32,Failure>,D:Fn(&Expr)->Result<bool,Failure>{
 type Statement=Statement;type Expression=Expr;
 fn seen_try(&self,block:&[Statement],c:&mut C)->Result<bool,Failure>{let mut seen=false;let mut visit=|e:&Expr,c:&mut C|{c.checkpoint()?;seen|=ordinary(e).is_some_and(|(name,_)|self.try_calls.contains(&name));Ok(())};let mut scan=Scan{c,visit:&mut visit,error:None};let coverage=dm_analysis::policy_body_observation::observe_base_chains(self.view.child(block),&mut scan);scan_result(scan,coverage)?;Ok(seen)}
 fn line(&self,s:&Statement,c:&mut C)->Result<u32,Failure>{c.checkpoint()?;(self.line)(s.header_span)}
 fn step<'b>(&'b self,s:&'b Statement,c:&mut C)->Result<pair::Step<'b,Statement,Expr>,Failure>{
  c.checkpoint()?;use pair::Step as S;let mut expressions=Vec::new();let mut blocks=Vec::new();let mut exhaustive=false;match &s.kind{
   StatementKind::Return(e)=>return Ok(S::Return(e.as_ref())),StatementKind::Throw(_)=>return Ok(S::Terminate),
   StatementKind::If{condition,then_branch,else_branch}=>{let mut arms=Vec::new();kc::row(c,&mut arms)?;arms.push((condition,then_branch.as_slice()));return Ok(S::Conditional{arms,otherwise:if else_branch.is_empty(){None}else{Some(else_branch)}})},
   StatementKind::Assign{target,op,value}=>return Ok(S::Assign{lhs:target,rhs:value,plain:op=="="}),
   StatementKind::Call(e)if matches!(&e.kind,ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Ident(name)if name=="CRASH"))=>{let ExprKind::Call{args,..}=&e.kind else{unreachable!()};if args.len()>1{return Err("pair CRASH with multiple arguments needs actual original grammar disposition".into())}return Ok(S::Terminate)},
   StatementKind::Call(e)|StatementKind::Expression(e)|StatementKind::Delete(e)=>return Ok(S::Simple(e)),
   StatementKind::Var{value,..}=>{let entries=self.locals.in_span(s.header_span)?;if entries.len()!=1{return Err("pair Var has no exact one-name native ledger association".into())}let entry=&entries[0];let all=self.locals.entries()?;let index=all.iter().position(|old|std::ptr::eq(old,entry)).ok_or("pair Var name belongs to another local ledger")?;let grouped=entry.source_kind==LocalSourceKind::CommaContinuation||all.get(index+1).is_some_and(|next|next.source_kind==LocalSourceKind::CommaContinuation);
    if !grouped&&value.is_none(){if let Some(array)=entry.implicit_list_initializer(){for expression in array.dimensions.iter(){kc::row(c,&mut expressions)?;expressions.push(expression);}return Ok(S::Other{expressions,blocks,exhaustive:false})}}
    let mut values=Vec::new();kc::row(c,&mut values)?;values.push(pair::Var{name:self.locals.name(entry)?,value:value.as_ref()});return Ok(S::Variables{values,grouped})},
   StatementKind::While{condition,body}|StatementKind::DoWhile{condition,body}=>{kc::row(c,&mut expressions)?;expressions.push(condition);kc::row(c,&mut blocks)?;blocks.push(body.as_slice());},
   StatementKind::For{control,body}=>{match control{ForControl::All{..}=>(),ForControl::Each{iterable,..}|ForControl::Pair{iterable,..}=>{kc::row(c,&mut expressions)?;expressions.push(iterable)},ForControl::Range{start,end,step,..}=>{for e in [Some(start),Some(end),step.as_ref()].into_iter().flatten(){kc::row(c,&mut expressions)?;expressions.push(e)}},ForControl::RangeImplicitArray{end,step,..}=>{let rows=self.locals.in_span(s.header_span)?;let root=rows.iter().find_map(|row|row.implicit_list_initializer()).ok_or("pair range implicit start has no native root")?;for e in root.dimensions.iter().chain(std::iter::once(end)).chain(step.iter()){kc::row(c,&mut expressions)?;expressions.push(e)}},ForControl::CStyle{condition,..}=>if let Some(e)=condition{kc::row(c,&mut expressions)?;expressions.push(e)}}kc::row(c,&mut blocks)?;blocks.push(body.as_slice());},
   StatementKind::Spawn{delay,body}=>{if let Some(e)=delay{kc::row(c,&mut expressions)?;expressions.push(e)}kc::row(c,&mut blocks)?;blocks.push(body.as_slice());},StatementKind::Label{body,..}=>{kc::row(c,&mut blocks)?;blocks.push(body.as_slice());},
   StatementKind::Switch{selector,cases,else_branch,default_present}=>{exhaustive=*default_present;kc::row(c,&mut expressions)?;expressions.push(selector);for case in cases{for alternative in &case.alternatives{match alternative{SwitchAlternative::Exact(e)=>{kc::row(c,&mut expressions)?;expressions.push(e)},SwitchAlternative::Range(a,b)=>{kc::row(c,&mut expressions)?;expressions.push(a);kc::row(c,&mut expressions)?;expressions.push(b)}}}kc::row(c,&mut blocks)?;blocks.push(case.body.as_slice());}if *default_present{kc::row(c,&mut blocks)?;blocks.push(else_branch.as_slice());}},
   StatementKind::Try{body,catch_body,..}=>{for b in [body,catch_body]{kc::row(c,&mut blocks)?;blocks.push(b.as_slice());}},
   StatementKind::Set{value,..}=>{kc::row(c,&mut expressions)?;expressions.push(value)},StatementKind::ProjectedSet{value,..}=>{kc::row(c,&mut expressions)?;expressions.push(value.original_expression())},
   StatementKind::Unsupported=>return Err("pair native grammar is unissued; cannot stand in for old skipped BODY".into()),_=>(),
  }Ok(S::Other{expressions,blocks,exhaustive})
 }
 fn is_try(&self,e:&Expr,c:&mut C)->Result<bool,Failure>{c.checkpoint()?;Ok(ordinary(e).is_some_and(|(name,_)|self.try_calls.contains(&name)))}
 fn bare_name<'b>(&self,e:&'b Expr)->Option<&'b str>{bare(e)}
 fn closes(&self,e:&Expr,pending:&mut pair::Pending,c:&mut C)->Result<(),Failure>{let mut visit=|e:&Expr,c:&mut C|{c.checkpoint()?;if let Some(("act_done"|"act_cancel",args))=call(e){if let Some(name)=args.first().and_then(bare){pending.close(name)}}Ok(())};let mut scan=Scan{c,visit:&mut visit,error:None};let coverage=dm_analysis::policy_body_observation::observe_expression_base_chains(e,e.span,&mut scan);scan_result(scan,coverage)}
 fn null_tested(&self,e:&Expr,c:&mut C)->Result<Vec<String>,Failure>{nulls(e,false,c,&self.refusal_debug)}
 fn non_null_tested(&self,e:&Expr,c:&mut C)->Result<Vec<String>,Failure>{nulls(e,true,c,&self.refusal_debug)}
}
fn push<C:Control<Error=Failure>>(out:&mut Vec<String>,name:&str,c:&mut C)->Result<(),Failure>{kc::row(c,out)?;out.push(kc::own(c,name)?);Ok(())}
fn integer<C:Control<Error=Failure>>(e:&Expr,c:&mut C)->Result<Option<i32>,Failure>{c.checkpoint()?;let ExprKind::Literal(text)=&ungroup(e).kind else{return Ok(None)};if let Some(value)=text.original_value(){return Ok(if let dm_syntax::OriginalTokenValue::Int(value)=value{Some(value)}else{None})}if dm_analysis::original_base_terms::is_null_term(ungroup(e)){return Ok(None)}let raw=text.as_str();if !raw.as_bytes().first().is_some_and(|byte|byte.is_ascii_digit()||*byte==b'.'){return Ok(None)}kc::reserve(c,||raw.len().checked_mul(8)?.checked_add(512))?;Ok(match dm_syntax::numeric_form::numeric_form(raw).map_err(Failure::from)?{dm_syntax::numeric_form::NumericForm::Integer(value)=>Some(value),_=>None})}
fn sentinel<C:Control<Error=Failure>>(e:&Expr,c:&mut C)->Result<bool,Failure>{let e=ungroup(e);if dm_analysis::original_base_terms::is_null_term(e){return Ok(true)}if integer(e,c)?.is_some_and(|value|value<0){return Ok(true)}if let ExprKind::Unary{op,value}=&e.kind{if op=="-"{return Ok(integer(value,c)?==Some(1))}}Ok(false)}
fn refusal<'a,C:Control<Error=Failure>>(e:&'a Expr,c:&mut C,debug:&impl Fn(&Expr)->Result<bool,Failure>)->Result<Option<&'a str>,Failure>{c.checkpoint()?;let Some(("istype",args))=ordinary(e)else{return Ok(None)};if args.len()!=2{return Ok(None)}if debug(&args[1])?{Ok(bare(&args[0]))}else{Ok(None)}}
fn nulls<C:Control<Error=Failure>>(e:&Expr,non_null:bool,c:&mut C,debug:&impl Fn(&Expr)->Result<bool,Failure>)->Result<Vec<String>,Failure>{
 c.checkpoint()?;let e=ungroup(e);let mut out=Vec::new();if non_null{if let Some(name)=bare(e){push(&mut out,name,c)?;}if let ExprKind::Unary{op,value}=&e.kind{if op=="!"{if let Some(name)=refusal(ungroup(value),c,debug)?{push(&mut out,name,c)?;}}}}else{if let ExprKind::Unary{op,value}=&e.kind{if op=="!"{if let Some(name)=bare(value){push(&mut out,name,c)?;}}}if let Some(("isnull",args))=ordinary(e){if let Some(name)=args.first().and_then(bare){push(&mut out,name,c)?;}}if let Some(name)=refusal(e,c,debug)?{push(&mut out,name,c)?;}}
 if let ExprKind::Binary{op,lhs,rhs}=&e.kind{if op==if non_null{"!="}else{"=="}{for(a,b)in[(lhs,rhs),(rhs,lhs)]{if let Some(name)=bare(a){if sentinel(b,c)?{push(&mut out,name,c)?;}}}}else if !non_null&&op=="||"{for part in [lhs,rhs]{for name in nulls(part,false,c,debug)?{kc::row(c,&mut out)?;out.push(name);}}}}
 c.checkpoint()?;Ok(out)
}
