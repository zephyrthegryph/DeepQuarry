//! Original type-expression compile diagnostics over the actual primary AST.
//! Policy: SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc,
//! dreamchecker/type_expr.rs SHA256 d6553fa12004a2f3bc79265cb480ab87463aedc39e8b542fe1bbe1ce5c93f90f (GPL-3.0).
//!
//! This private compile phase does not infer executable return values. Successful
//! compilation still needs the existing return-binding consumer; no default
//! checker route is enabled by this module.
use dm_syntax::{Expr, ExprKind, Span};
use crate::policy_body_demand::PolicyFailure;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Shape { Static, ParameterPath, ParameterStatic, Conditional }
#[derive(Clone, Copy, Debug)]
pub(crate) enum Message<'a> {
    BadExpression,
    NoParameter(&'a str),
    BadTerm,
    CannotIndexNonParameter,
    CannotIndexExceptUnderscore,
    CannotTakeTypeOfNonParameter,
    BadFollow(&'a Expr),
    UndefinedType(&'a str),
}
impl Message<'_> {
    pub(crate) fn fixed(self) -> Option<&'static str> {
        Some(match self {
            Self::BadExpression => "type expr: bad expression node",
            Self::BadTerm => "type expr: bad term node",
            Self::CannotIndexNonParameter => "type expr: cannot index non-parameters",
            Self::CannotIndexExceptUnderscore => "type expr: cannot index by anything but `_`",
            Self::CannotTakeTypeOfNonParameter => "type expr: cannot take .type of non-parameters",
            _ => return None,
        })
    }
}
#[derive(Clone, Copy, Debug)]
pub(crate) struct Issue<'a> { pub at: Span, pub message: Message<'a> }

/// Source-free compiler kernel. Context is private to the actual archived
/// producer below; tests use it only for independent primary-AST probes.
trait Context {
    type Frame<'a> where Self:'a;
    fn frame(&self) -> Result<Self::Frame<'_>, PolicyFailure>;
    fn parameter(&self, name:&str) -> Result<bool, PolicyFailure>;
    fn path_exists(&self, absolute_path:&str) -> Result<bool, PolicyFailure>;
    /// Follow locations come from the existing issued token interval. Never
    /// guess the punctuation point from UTF-8 string length or caller offsets.
    fn follow_point(&self, object:&Expr, follow:&Expr) -> Result<Span, PolicyFailure>;
}
fn problem<'a>(at:Span,message:Message<'a>)->Result<Shape,Issue<'a>>{Err(Issue{at,message})}
fn compile<'a>(c:&impl Context,e:&'a Expr,location:Span)->Result<Result<Shape,Issue<'a>>,PolicyFailure>{
    let _frame=c.frame()?;
    Ok(match &e.kind {
        ExprKind::Binary{op,lhs,rhs} if op=="||" || op=="&&" => {
            match compile(c,lhs,location)? { Err(issue)=>Err(issue), Ok(_)=>match compile(c,rhs,location)? {Err(issue)=>Err(issue),Ok(_)=>Ok(Shape::Conditional)} }
        }
        ExprKind::Binary{..} => problem(location,Message::BadExpression),
        ExprKind::Conditional{condition,then_value,else_value} => {
            let mut result=Ok(Shape::Conditional);
            for child in [condition.as_ref(),then_value.as_ref(),else_value.as_ref()] {
                match compile(c,child,location)? {Err(issue)=>{result=Err(issue);break},Ok(_)=>()}
            } result
        }
        // Group is the original Term::Expr: recursive expression diagnostics
        // inherit that term's actual location.
        ExprKind::Group(inner)=>compile(c,inner,e.span)?,
        ExprKind::Ident(name) if name=="null" => Ok(Shape::Static),
        ExprKind::Literal(raw) if raw.original_value().is_none()&&raw.as_str()=="null" => Ok(Shape::Static),
        ExprKind::Ident(name) => if c.parameter(name)? {Ok(Shape::ParameterPath)}else{problem(e.span,Message::NoParameter(name))},
        ExprKind::TypePath(path)=>static_path(c,path,e.span)?,
        ExprKind::ObjectInitializer{object,..} => match &object.kind {
            ExprKind::TypePath(path)=>static_path(c,path,e.span)?,
            _=>return Err("original type-expression prefab path is not represented by the primary AST".into()),
        },
        ExprKind::Index{object,index}|ExprKind::SafeIndex{object,index} => {
            match compile(c,object,location)? {
                Err(issue)=>Err(issue),
                Ok(shape)=> {
                    let at=c.follow_point(object,e)?;
                    // as_term() deliberately does NOT peel a Group around `_`.
                    if !matches!(&index.kind,ExprKind::Ident(name)if name=="_") {problem(at,Message::CannotIndexExceptUnderscore)}
                    else if shape==Shape::ParameterPath {Ok(Shape::ParameterPath)}
                    else {problem(at,Message::CannotIndexNonParameter)}
                }
            }
        }
        ExprKind::Member{object,selector,..}|ExprKind::SafeMember{object,selector,..} => {
            match compile(c,object,location)? {
                Err(issue)=>Err(issue),Ok(shape)=> {
                    let at=c.follow_point(object,e)?;
                    if selector!="type" {problem(at,Message::BadFollow(e))}
                    else if shape==Shape::ParameterPath {Ok(Shape::ParameterStatic)}
                    else {problem(at,Message::CannotTakeTypeOfNonParameter)}
                }
            }
        }
        ExprKind::StaticMember{object,..} => {
            match compile(c,object,location)? {Err(issue)=>Err(issue),Ok(_)=>problem(c.follow_point(object,e)?,Message::BadFollow(e))}
        }
        // Member calls are Follow::Call, not a call on a field. Compile the
        // base first; do not produce a premature bad Field diagnostic.
        ExprKind::Call{callee,..} if matches!(callee.kind,ExprKind::Member{..}|ExprKind::SafeMember{..}|ExprKind::StaticMember{..}) => {
            let object=match &callee.kind{ExprKind::Member{object,..}|ExprKind::SafeMember{object,..}|ExprKind::StaticMember{object,..}=>object.as_ref(),_=>unreachable!()};
            match compile(c,object,location)? {Err(issue)=>Err(issue),Ok(_)=>problem(c.follow_point(object,e)?,Message::BadFollow(e))}
        }
        ExprKind::Unary{op,value} if matches!(op.as_str(),"-"|"!"|"~"|"pre++"|"post++"|"pre--"|"post--"|"&"|"*") => {
            match compile(c,value,location)? {Err(issue)=>Err(issue),Ok(_)=>problem(c.follow_point(value,e)?,Message::BadFollow(e))}
        }
        _=>problem(e.span,Message::BadTerm),
    })
}
fn static_path<'a>(c:&impl Context,path:&'a str,at:Span)->Result<Result<Shape,Issue<'a>>,PolicyFailure>{
    if !path.starts_with('/') {return Err("original type-expression relative prefab path needs primary original path projection".into())}
    let mut rest=path;
    loop {
        let Some(component)=rest.strip_prefix('/').and_then(|s|s.split('/').next())else{break};
        if ["static","global","const","tmp","final","SpacemanDMM_final","SpacemanDMM_private","SpacemanDMM_protected","list"].contains(&component) {
            // Original static_type strips qualifiers at each recursive list
            // boundary; an isolated empty /list tail is still valid.
            rest=&rest[component.len()+1..];
        } else {break}
    }
    if rest.is_empty() || c.path_exists(rest)? {Ok(Ok(Shape::Static))}else{Ok(problem(at,Message::UndefinedType(rest)))}
}

struct Archived<'a,'op>{body:&'a dyn dm_tree::frontend::InitialSettingSource,admission:&'a dm_syntax::SettingAdmission<'op>,offset:usize,path_lookup:Option<&'a dyn Fn(&str)->Result<bool,PolicyFailure>>}
impl<'op> Context for Archived<'_,'op>{
 type Frame<'a>=dm_syntax::SettingEvaluationFrame<'a,'op> where Self:'a;
 fn frame(&self)->Result<Self::Frame<'_>,PolicyFailure>{
  let pending=self.admission.evaluation_frame();if let Some(actual)=self.admission.take_operational_error(){return Err(PolicyFailure::Operational(actual))}pending.map_err(PolicyFailure::Operational)
 }
 fn parameter(&self,name:&str)->Result<bool,PolicyFailure>{
  let member=self.body.tree().member(self.body.occurrence().member).ok_or("return-expression source callable absent")?;
  let metadata=member.metadata.procedure.as_ref().ok_or("return-expression source signature absent")?;
  for parameter in metadata.signature.parameters.iter(){self.admission.checkpoint().map_err(PolicyFailure::Operational)?;if self.body.tree().symbols().text(parameter.name)==Some(name){return Ok(true)}}Ok(false)
 }
 fn path_exists(&self,path:&str)->Result<bool,PolicyFailure>{self.admission.checkpoint().map_err(PolicyFailure::Operational)?;match self.path_lookup{Some(lookup)=>lookup(path),None=>Ok(self.body.tree().lookup_type(dm_ir::SymbolId::of(path)).is_some())}}
 fn follow_point(&self,object:&Expr,follow:&Expr)->Result<Span,PolicyFailure>{
  if let ExprKind::Unary{op,..}=&follow.kind{if !op.starts_with("post"){return Ok(Span::new(follow.span.start,follow.span.start.checked_add(1).ok_or("return unary point overflow")?))}}
  let start=object.span.end.checked_add(self.offset).ok_or("return follow start overflow")?;let end=follow.span.end.checked_add(self.offset).ok_or("return follow end overflow")?;
  for token in self.body.original_body_tokens().map_err(|actual|match actual{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>PolicyFailure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(actual)=>actual.message.into()})?.tokens(self.body.source_point(Span::new(start,end))?)?{
   self.admission.checkpoint().map_err(PolicyFailure::Operational)?;let(kind,at,_)=token;if matches!(kind,dm_syntax::TokenKind::Whitespace|dm_syntax::TokenKind::Newline|dm_syntax::TokenKind::Comment){continue}
   let at=self.body.canonical_point(at)?;return Ok(Span::new(at.start.checked_sub(self.offset).ok_or("return follow point precedes original root")?,at.end.checked_sub(self.offset).ok_or("return follow point precedes original root")?))
  }Err("original return follow punctuation absent".into())
 }
}
/// One actual initial-setting ordinal selects the privately issued root. This
/// function never accepts a substitute tree, parameters, AST or source counter.
/// It emits only the compile diagnostic; it does not replace the return binding
/// on an invalid expression (the pinned compiler keeps its previous binding).
pub(crate) fn archived_setting<W:crate::checker_effects::EffectReportWork>(body:&dm_tree::frontend::ArchivedBody<'_>,ordinal:usize,work:&mut W,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<Option<crate::checks::Diagnostic>,PolicyFailure>{
 checkpoint().map_err(PolicyFailure::Operational)?;
 let pending=body.with_original_syntax_admission(|admission|{
  let pending=(||{
   if !body.statement_body().is_native_literal_syntax_admitted_by(admission){return Err("original return expression has another syntax admission".into())}
   for earlier in body.statement_body().parsed().statements.iter().take(ordinal){if earlier.setting().is_none(){return Err("return expression is outside the initial setting prefix".into())}}
   let statement=body.statement_body().parsed().statements.get(ordinal).ok_or("return setting ordinal absent")?;let setting=statement.setting().ok_or("return ordinal is not a setting")?;if setting.attribute!="SpacemanDMM_return_type"{return Err("return ordinal has another setting name".into())}
   let offset=match setting.value{dm_syntax::SettingValueView::Owned(_)=>0,dm_syntax::SettingValueView::Projected(root)=>{if !root.is_retained_in(admission){return Err("return setting root belongs to another admission".into())}root.current_offset()}};
   let context=Archived{body,admission,offset,path_lookup:None};
   let canonical_header=Span::new(statement.header_span.start.checked_sub(offset).ok_or("return header precedes root offset")?,statement.header_span.end.checked_sub(offset).ok_or("return header precedes root offset")?);
   let mut issue=match compile(&context,setting.value.original(),canonical_header)?{Ok(_)=>return Ok(None),Err(issue)=>issue};
   if matches!(setting.value.original().kind,ExprKind::TypePath(_)|ExprKind::ObjectInitializer{..})&&matches!(issue.message,Message::UndefinedType(_)){issue.at=canonical_header;}
   let span=Span::new(issue.at.start.checked_add(offset).ok_or("return issue coordinate overflow")?,issue.at.end.checked_add(offset).ok_or("return issue coordinate overflow")?);
   let message=match issue.message{
    Message::BadFollow(expr)=>crate::checker_original_expression_debug::with_type_follow_debug(body,expr,offset,checkpoint,|text|{
     let bytes=text.len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or("return follow output overflow")?;work.reserve(bytes).map_err(PolicyFailure::Operational)?;Ok(format!("type expr: bad follow node {text}"))
    })?,
    message=>{
     let length=match message{Message::NoParameter(name)|Message::UndefinedType(name)=>name.len(),_=>0};let bytes=length.checked_mul(12).and_then(|n|n.checked_add(256)).ok_or("return expression output overflow")?;work.reserve(bytes).map_err(PolicyFailure::Operational)?;
     match message{Message::NoParameter(name)=>format!("type expr: no such parameter {name:?}"),Message::UndefinedType(path)=>format!("undefined type: {path}"),message=>message.fixed().ok_or("return message family absent")?.to_owned()}
    }
   };
   Ok(Some(crate::checks::Diagnostic{family:"return_type_expression",severity:crate::checks::Severity::Error,span,expression_span:setting.value.current_span(),message,notes:Vec::new()}))
  })();if let Some(actual)=admission.take_operational_error(){return Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual))}match pending{Err(PolicyFailure::Operational(actual))=>Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual)),other=>Ok(other)}
 });
 let pending=match pending{Ok(value)=>value,Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual))=>Err(PolicyFailure::Operational(actual)),Err(dm_tree::frontend::BodySyntaxFailure::Syntax(error))=>Err(error.message.into())};if matches!(&pending,Err(PolicyFailure::Operational(_))){return pending}checkpoint().map_err(PolicyFailure::Operational)?;pending
}

#[cfg(test)] mod tests {
 use super::*;
 struct Probe { stop:Option<usize>, polls:std::cell::Cell<usize> }
 impl Context for Probe {
  type Frame<'a>=() where Self:'a;
  fn frame(&self)->Result<(),PolicyFailure>{let next=self.polls.get()+1;self.polls.set(next);if self.stop==Some(next){Err(PolicyFailure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Ok(())}}
  fn parameter(&self,name:&str)->Result<bool,PolicyFailure>{Ok(name=="x")}
  fn path_exists(&self,path:&str)->Result<bool,PolicyFailure>{Ok(path=="/datum")}
  fn follow_point(&self,object:&Expr,_:&Expr)->Result<Span,PolicyFailure>{Ok(Span::new(object.span.end,object.span.end+1))}
 }
 fn expression(text:&str)->Expr {let parsed=dm_syntax::parse_expression(text);assert!(parsed.diagnostics.is_empty(),"{:?}",parsed.diagnostics);parsed.expr.unwrap()}
 #[test] fn return_expression_compile_does_not_treat_grouped_underscore_as_an_index_marker(){
  let c=Probe{stop:None,polls:std::cell::Cell::new(0)};let e=expression("x[(_)]");let issue=compile(&c,&e,e.span).unwrap().unwrap_err();assert!(matches!(issue.message,Message::CannotIndexExceptUnderscore));
 }
 #[test] fn return_expression_compile_preserves_first_failing_child_before_later_follow(){
  let c=Probe{stop:None,polls:std::cell::Cell::new(0)};for source in ["missing || absent","missing.hello","missing[1]","missing ? absent : later"]{let e=expression(source);let issue=compile(&c,&e,e.span).unwrap().unwrap_err();assert!(matches!(issue.message,Message::NoParameter("missing")),"{source}: {issue:?}")}
 }
 #[test] fn return_expression_compile_uses_same_callback_io_without_making_a_diagnostic(){
  let c=Probe{stop:Some(2),polls:std::cell::Cell::new(0)};let e=expression("x || null");let result=compile(&c,&e,e.span);assert!(matches!(result,Err(PolicyFailure::Operational(ref error))if error.raw_os_error()==Some(1450)));assert_eq!(c.polls.get(),2);
 }
 #[test] fn return_expression_compile_does_not_diagnose_grouped_parameter_type_as_nonparameter(){
  let c=Probe{stop:None,polls:std::cell::Cell::new(0)};let e=expression("(x).type");assert!(matches!(compile(&c,&e,e.span).unwrap(),Ok(Shape::ParameterStatic)));
 }
}

/// The callback cannot retain the syntax root beyond its existing source loan.
/// Rejected compound expressions leave an earlier binding in place. A direct
/// prefab whose static type is absent instead installs None, as gather_settings
/// calls static_type directly in that special branch.
pub(crate) enum CompiledSetting<'a>{Rejected,Empty,Value(&'a Expr)}
pub(crate) fn with_compiled_setting<T>(body:&dyn dm_tree::frontend::InitialSettingSource,resolver:&(impl dm_ir::Resolver+?Sized),ordinal:usize,checkpoint:&dyn Fn()->std::io::Result<()>,consume:impl for<'e,'op> FnOnce(CompiledSetting<'e>,&dm_syntax::SettingAdmission<'op>)->Result<T,PolicyFailure>)->Result<T,PolicyFailure>{
 checkpoint().map_err(PolicyFailure::Operational)?;
 if resolver.source_owner()!=dm_ir::Resolver::source_owner(body.tree()){return Err("compiled return setting resolver belongs to another current tree".into())}
 // A rejected/empty compiled expression still depends on the actual type
 // lookup it consulted. Do not wait for Eval: that would miss negative edges.
 let path_lookup=|path:&str|->Result<bool,PolicyFailure>{checkpoint().map_err(PolicyFailure::Operational)?;let id=dm_ir::SymbolId::of(path);let query=dm_ir::ResolveQuery::Type(id);let actual=resolver.resolve(query);let expected=dm_ir::Resolver::resolve(body.tree(),query);if actual!=expected{return Err("compiled return setting type dependency differs from actual native source".into())}Ok(body.tree().lookup_type(id).is_some())};
 let pending=body.with_source_admission(|admission|{
  let pending=(||{
   if !body.statement_body().is_native_literal_syntax_admitted_by(admission){return Err("compiled return binding has another syntax admission".into())}
   for previous in body.statement_body().parsed().statements.iter().take(ordinal){if previous.setting().is_none(){return Err("compiled return binding is outside initial settings".into())}}
   let statement=body.statement_body().parsed().statements.get(ordinal).ok_or("compiled return binding ordinal absent")?;let setting=statement.setting().ok_or("compiled return binding is not setting")?;if setting.attribute!="SpacemanDMM_return_type"{return Err("compiled return binding setting differs".into())}
   let offset=match setting.value{dm_syntax::SettingValueView::Owned(_)=>0,dm_syntax::SettingValueView::Projected(root)=>{if !root.is_retained_in(admission){return Err("compiled return root belongs to another admission".into())}root.current_offset()}};
   let root=setting.value.original();let context=Archived{body,admission,offset,path_lookup:Some(&path_lookup)};
   let location=Span::new(statement.header_span.start.checked_sub(offset).ok_or("compiled return header coordinate underflow")?,statement.header_span.end.checked_sub(offset).ok_or("compiled return header coordinate underflow")?);
   let compiled=match compile(&context,root,location)?{Ok(_)=>CompiledSetting::Value(root),Err(issue)=>if matches!(root.kind,ExprKind::TypePath(_)|ExprKind::ObjectInitializer{..})&&matches!(issue.message,Message::UndefinedType(_)){CompiledSetting::Empty}else{CompiledSetting::Rejected}};
   consume(compiled,admission)
  })();if let Some(actual)=admission.take_operational_error(){return Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual))}match pending{Err(PolicyFailure::Operational(actual))=>Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual)),other=>Ok(other)}
 });let pending=match pending{Ok(value)=>value,Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual))=>Err(PolicyFailure::Operational(actual)),Err(dm_tree::frontend::BodySyntaxFailure::Syntax(error))=>Err(error.message.into())};// T is opaque and may contain the consumer's actual typed error. The
 // caller checks it before its own final source/cancellation guard.
 pending
}


/// Producer-owned source-neutral compile finding. A renderer cannot manufacture
/// an accepted/rejected setting and never compiles/evaluates a root again.
#[derive(Debug)]pub(crate) struct CurrentReturnRecipe{span:Span,expression_span:Span,ordinal:usize,message:CurrentReturnMessage}
#[derive(Debug)]enum CurrentReturnMessage{Fixed(String),Follow{span:Span,kind:u8}}
fn follow_class(expr:&Expr)->Result<u8,PolicyFailure>{Ok(match &expr.kind{ExprKind::Member{..}=>0,ExprKind::SafeMember{..}=>1,ExprKind::StaticMember{..}=>2,ExprKind::Call{..}=>3,ExprKind::Unary{..}=>4,_=>return Err("return issue is not an original Follow node".into())})}
impl CurrentReturnRecipe{
 pub(crate) fn retained_bytes(&self)->Option<usize>{std::mem::size_of::<Self>().checked_add(match &self.message{CurrentReturnMessage::Fixed(text)=>text.capacity(),_=>0})}
 pub(crate) fn visit_storage(&self,visit:&mut impl FnMut(crate::checker_effects::Storage)){if let CurrentReturnMessage::Fixed(text)=&self.message{visit(crate::checker_effects::Storage::Buffer{owner:"current_prefix.return_message",address:text.as_ptr()as usize,logical:text.len(),capacity:text.capacity()});}}
 pub(crate) fn fingerprint_parts(&self,part:&mut impl FnMut(&[u8])){for n in [self.span.start,self.span.end,self.expression_span.start,self.expression_span.end,self.ordinal]{part(&(n as u64).to_le_bytes());}match &self.message{CurrentReturnMessage::Fixed(text)=>{part(&[0]);part(&(text.len()as u64).to_le_bytes());part(text.as_bytes());},CurrentReturnMessage::Follow{span,kind}=>{part(&[1,*kind]);part(&(span.start as u64).to_le_bytes());part(&(span.end as u64).to_le_bytes());}}}
 pub(crate) fn render<W:crate::checker_effects::EffectReportWork>(&self,body:&dyn dm_tree::frontend::InitialSettingSource,work:&mut W,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<crate::checks::Diagnostic,PolicyFailure>{
  let statement=body.statement_body().parsed().statements.get(self.ordinal).ok_or("current return recipe statement absent")?;let setting=statement.setting().ok_or("current return recipe setting absent")?;if setting.attribute!="SpacemanDMM_return_type"{return Err("current return recipe setting changed".into())}
  let offset=match setting.value{dm_syntax::SettingValueView::Owned(_)=>0,dm_syntax::SettingValueView::Projected(root)=>root.current_offset()};
  let message=match &self.message{CurrentReturnMessage::Fixed(text)=>{work.reserve(text.len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or("return message presentation overflow")?).map_err(PolicyFailure::Operational)?;text.clone()},CurrentReturnMessage::Follow{span,kind}=>{
   // Locate the exact SAME canonical node by its producer-issued geometry and
   // kind. No expression evaluation or foreign absolute AST is accepted.
   fn select<'a>(node:&'a Expr,span:Span,kind:u8,out:&mut Option<&'a Expr>,a:&dm_syntax::SettingAdmission<'_>,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<(),PolicyFailure>{checkpoint().map_err(PolicyFailure::Operational)?;let _frame=a.evaluation_frame().map_err(PolicyFailure::Operational)?;if node.span==span&&follow_class(node).ok()==Some(kind){if out.replace(node).is_some(){return Err("return Follow recipe has ambiguous canonical node".into())}}if matches!(&node.kind,ExprKind::Literal(_)){return Ok(())}dm_syntax::try_for_each_expression_child(node,|_,child|select(child,span,kind,out,a,checkpoint))}
   let mut found=None;let pending=body.with_source_admission(|a|{select(setting.value.original(),*span,*kind,&mut found,a,checkpoint).map_err(|actual|match actual{PolicyFailure::Operational(actual)=>dm_tree::frontend::BodySyntaxFailure::Operational(actual),PolicyFailure::Unsupported(actual)=>dm_tree::frontend::BodySyntaxFailure::Operational(std::io::Error::new(std::io::ErrorKind::Unsupported,actual.0))})});if let Err(actual)=pending{return Err(match actual{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>PolicyFailure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(actual)=>actual.message.into()})}
   let node=found.ok_or("return Follow recipe node absent")?;crate::checker_original_expression_debug::with_type_follow_debug(body,node,offset,checkpoint,|text|{work.reserve(text.len().checked_mul(4).and_then(|n|n.checked_add(128)).ok_or("return Follow presentation overflow")?).map_err(PolicyFailure::Operational)?;Ok(format!("type expr: bad follow node {text}"))})?
  }};
  Ok(crate::checks::Diagnostic{family:"return_type_expression",severity:crate::checks::Severity::Error,span:body.source_point(self.span)?,expression_span:body.source_point(self.expression_span)?,message,notes:Vec::new()})
 }
}
pub(crate) fn current_setting_recipe<W:crate::checker_effects::EffectReportWork>(body:&dyn dm_tree::frontend::InitialSettingSource,resolver:&(impl dm_ir::Resolver+?Sized),ordinal:usize,work:&mut W,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<Option<CurrentReturnRecipe>,PolicyFailure>{
 checkpoint().map_err(PolicyFailure::Operational)?;
 if resolver.source_owner()!=dm_ir::Resolver::source_owner(body.tree()){return Err("current return compiler resolver belongs to another source".into())}
 let lookup=|path:&str|{checkpoint().map_err(PolicyFailure::Operational)?;let query=dm_ir::ResolveQuery::Type(dm_ir::SymbolId::of(path));if resolver.resolve(query)!=dm_ir::Resolver::resolve(body.tree(),query){return Err(PolicyFailure::from("current return compile dependency differs from actual native lookup"))}Ok(body.tree().lookup_type(dm_ir::SymbolId::of(path)).is_some())};
 let pending=body.with_source_admission(|a|{let pending=(||{
  if !body.statement_body().is_native_literal_syntax_admitted_by(a){return Err("current return compiler syntax belongs to another operation".into())}
  let statement=body.statement_body().parsed().statements.get(ordinal).ok_or("current return setting ordinal absent")?;let setting=statement.setting().ok_or("current return ordinal is not setting")?;if setting.attribute!="SpacemanDMM_return_type"{return Err("current return setting attribute differs".into())}
  let offset=match setting.value{dm_syntax::SettingValueView::Owned(_)=>0,dm_syntax::SettingValueView::Projected(root)=>{if !root.is_retained_in(a){return Err("current return expression root belongs to another operation".into())}root.current_offset()}};
  let header=Span::new(statement.header_span.start.checked_sub(offset).ok_or("current return header underflow")?,statement.header_span.end.checked_sub(offset).ok_or("current return header underflow")?);let context=Archived{body,admission:a,offset,path_lookup:Some(&lookup)};
  let mut issue=match compile(&context,setting.value.original(),header)?{Ok(_)=>return Ok(None),Err(issue)=>issue};if matches!(setting.value.original().kind,ExprKind::TypePath(_)|ExprKind::ObjectInitializer{..})&&matches!(issue.message,Message::UndefinedType(_)){issue.at=header;}
  let span=Span::new(issue.at.start.checked_add(offset).ok_or("current return issue overflow")?,issue.at.end.checked_add(offset).ok_or("current return issue overflow")?);
  let message=match issue.message{Message::BadFollow(expr)=>CurrentReturnMessage::Follow{span:expr.span,kind:follow_class(expr)?},other=>{let length=match other{Message::NoParameter(name)|Message::UndefinedType(name)=>name.len(),_=>0};work.reserve(length.checked_mul(12).and_then(|n|n.checked_add(256)).ok_or("current return recipe message overflow")?).map_err(PolicyFailure::Operational)?;CurrentReturnMessage::Fixed(match other{Message::NoParameter(name)=>format!("type expr: no such parameter {name:?}"),Message::UndefinedType(path)=>format!("undefined type: {path}"),message=>message.fixed().ok_or("current return fixed message absent")?.to_owned()})}};
  Ok(Some(CurrentReturnRecipe{span,expression_span:setting.value.current_span(),ordinal,message}))
 })();if let Some(actual)=a.take_operational_error(){return Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual))}match pending{Err(PolicyFailure::Operational(actual))=>Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual)),other=>Ok(other)}});
 match pending{Ok(value)=>value,Err(dm_tree::frontend::BodySyntaxFailure::Operational(actual))=>Err(PolicyFailure::Operational(actual)),Err(dm_tree::frontend::BodySyntaxFailure::Syntax(actual))=>Err(actual.message.into())}
}
