//! Judge for an ALREADY parsed authentic Original condition. No parsing,
//! expansion, source reads, or unavailable-model recovery lives here.
//! ConstantFolder::expr/unary/binary/term at pinned0290 is the authority.
use crate::condition_parser::ConditionNumber;
use crate::macro_expansion::{OriginalMacroText as TextBuffer,OriginalMacroTextValue as Text,original_format_using};
use crate::MacroLookup;
use dm_syntax::{Expr,ExprKind,OriginalTokenValue,SettingAdmission};
use std::io;

pub(crate) enum Outcome{Value(bool),SourceFailure(TextBuffer),Unissued(&'static str)}
enum Value<'s>{Number(ConditionNumber),String(Text<'s>),Resource(&'s str)}
enum Evaluated<'s>{Value(Value<'s>),SourceFailure(TextBuffer),Unissued(&'static str)}
macro_rules! value{($expr:expr)=>{match $expr?{Evaluated::Value(value)=>value,Evaluated::SourceFailure(message)=>return Ok(Evaluated::SourceFailure(message)),Evaluated::Unissued(reason)=>return Ok(Evaluated::Unissued(reason))}}}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|error|a.take_operational_error().unwrap_or(error))}
fn failure<'s>(message:&str,a:&SettingAdmission<'_>)->io::Result<Evaluated<'s>>{let mut text=TextBuffer::new(a)?;text.push_str(message,a)?;Ok(Evaluated::SourceFailure(text))}
impl Value<'_>{
 fn truth(&self)->bool{match self{Self::Number(n)=>n.truth(),Self::String(s)=>!s.get().is_empty(),Self::Resource(_)=>true}}
 fn equal(&self,rhs:&Self)->bool{match(self,rhs){(Self::Number(ConditionNumber::Null),Self::Number(ConditionNumber::Null))=>true,(Self::Number(ConditionNumber::Original(a)),Self::Number(ConditionNumber::Original(b)))=>a==b||(a.is_nan()&&b.is_nan()),(Self::String(a),Self::String(b))=>a.get()==b.get(),(Self::Resource(a),Self::Resource(b))=>a==b,_=>false}}
 fn display(&self,out:&mut TextBuffer,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;match self{
  Self::Number(ConditionNumber::Original(n))=>original_format_using(out,a,|out|dm_syntax::numeric_form::write_original_float(*n,out)),
  Self::Number(ConditionNumber::Null)=>out.push_str("null",a),
  Self::Number(ConditionNumber::Native(_))=>Err(io::Error::new(io::ErrorKind::InvalidData,"native integer reached Original conditional judge")),
  Self::String(value)=>{let(open,close)=crate::macro_expansion::original_quote_delimiters(value.get());out.push_str(open,a)?;out.push_str(value.get(),a)?;out.push_str(close,a)},
  Self::Resource(value)=>{out.push('\'',a)?;out.push_str(value,a)?;out.push('\'',a)},
 }}
}
fn flag(value:bool)->Value<'static>{Value::Number(ConditionNumber::flag(value,true))}
/// The caller attaches SourceFailure to the SAVED actual condition start,
/// exactly as preprocessor_evaluate(start,...); not its later read point.
pub(crate) fn evaluate(expr:&Expr,macros:&dyn MacroLookup,a:&SettingAdmission<'_>)->io::Result<Outcome>{
 poll(a)?;if macros.initial_environment()!=crate::InitialEnvironment::OriginalChecker0290{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original condition requires actual Original macro environment"))}
 Ok(match evaluate_inner(expr,macros,a)?{Evaluated::Value(value)=>Outcome::Value(value.truth()),Evaluated::SourceFailure(message)=>Outcome::SourceFailure(message),Evaluated::Unissued(reason)=>Outcome::Unissued(reason)})
}
fn evaluate_inner<'s>(expr:&'s Expr,macros:&dyn MacroLookup,a:&SettingAdmission<'_>)->io::Result<Evaluated<'s>>{
 let _frame=a.evaluation_frame().map_err(|error|a.take_operational_error().unwrap_or(error))?;
 let value=match &expr.kind{
  ExprKind::Literal(literal)=>match literal.original_value(){
   Some(OriginalTokenValue::Int(n))=>Value::Number(ConditionNumber::Original(n as f32)),Some(OriginalTokenValue::Float(n))=>Value::Number(ConditionNumber::Original(n)),
   Some(OriginalTokenValue::String(s))=>Value::String(Text::Borrowed(s)),Some(OriginalTokenValue::Resource(s))=>Value::Resource(s),
   Some(_)=>return Ok(Evaluated::Unissued("Original condition literal has no scalar constant product")),
   None if literal.as_str()=="null"=>Value::Number(ConditionNumber::Null),
   None=>return Ok(Evaluated::Unissued("Original condition literal lacks authentic typed value")),
  },
  ExprKind::Ident(name)=>match name.as_str(){
   "null"=>Value::Number(ConditionNumber::Null),"type"|"parent_type"=>return failure("no type context",a),"__TYPE__"=>return failure("No type context",a),"__IMPLIED_TYPE__"=>return failure("No type hint",a),
   _=>{let mut message=TextBuffer::new(a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out,"cannot reference variable {name:?} in this context")})?;return Ok(Evaluated::SourceFailure(message))}
  },
  ExprKind::Group(inner)=>value!(evaluate_inner(inner,macros,a)),
  ExprKind::Conditional{condition,then_value,else_value}=>{let condition=value!(evaluate_inner(condition,macros,a));value!(evaluate_inner(if condition.truth(){then_value}else{else_value},macros,a))},
  ExprKind::Unary{op,value:operand}=>{
   if !matches!(op.as_str(),"!"|"-"|"~"){return Ok(Evaluated::Unissued("Original conditional unary grammar branch is not issued"))}
   let operand=value!(evaluate_inner(operand,macros,a));
   if op=="!"{flag(!operand.truth())}else if let Value::Number(ConditionNumber::Original(number))=operand{Value::Number(ConditionNumber::Original(number).unary(op).map_err(|_|io::Error::new(io::ErrorKind::InvalidData,"accepted Original numeric unary operation refused"))?)}else{
    let mut message=TextBuffer::new(a)?;message.push_str("non-constant unary operation: ",a)?;message.push_str(op,a)?;operand.display(&mut message,a)?;return Ok(Evaluated::SourceFailure(message))
   }
  },
  ExprKind::Binary{op,lhs,rhs}=>{
   if matches!(op.as_str(),"="|"+="|"-="|"*="|"/="|"%="|"%%="|"**="|"|="|"&="|"^="|"<<="|">>="|"&&="|"||="|":="){return failure("non-constant assignment",a)}
   if !matches!(op.as_str(),"+"|"-"|"*"|"/"|"%"|"%%"|"**"|"<"|"<="|">"|">="|"|"|"&"|"^"|"<<"|">>"|"=="|"!="|"&&"|"||"|"in"){return Ok(Evaluated::Unissued("Original conditional binary grammar branch is not issued"))}
   // The actual old folder evaluates BOTH operands before And/Or selection.
   let lhs=value!(evaluate_inner(lhs,macros,a));let rhs=value!(evaluate_inner(rhs,macros,a));
   if matches!(op.as_str(),"=="|"!="){let equal=lhs.equal(&rhs);flag(if op=="=="{equal}else{!equal})}
   else if op=="&&"{if lhs.truth(){rhs}else{lhs}}
   else if op=="||"{if lhs.truth(){lhs}else{rhs}}
   else if let(Value::Number(ConditionNumber::Original(left)),Value::Number(ConditionNumber::Original(right)))=(&lhs,&rhs){
    if op=="in"{return binary_failure(op,&lhs,&rhs,a)}
    if matches!(op.as_str(),"<<"|">>")&&(*right as u32)>=32{return Ok(Evaluated::Unissued("Original numeric shift is outside issued u32 width"))}
    match ConditionNumber::Original(*left).binary(ConditionNumber::Original(*right),op){Ok(number)=>Value::Number(number),Err(_)=>return Ok(Evaluated::Unissued("Original numeric shift is outside issued u32 width"))}
   }else if op=="+"&&matches!((&lhs,&rhs),(Value::String(_),Value::String(_))){
    let(Value::String(left),Value::String(right))=(lhs,rhs)else{unreachable!()};let mut joined=TextBuffer::new(a)?;joined.push_str(left.get(),a)?;joined.push_str(right.get(),a)?;Value::String(Text::Owned(joined))
   }else{return binary_failure(op,&lhs,&rhs,a)}
  },
  ExprKind::Call{callee,args}=>{
   let ExprKind::Ident(name)=&callee.kind else{return Ok(Evaluated::Unissued("Original conditional expression follower requires its actual constant product"))};
   match name.as_str(){
    "defined"=>{
     if args.len()!=1{return arity_failure("defined",args.len(),a)}
     let ExprKind::Ident(name)=&args[0].kind else{return failure("malformed defined() call, argument given isn't an Ident.",a)};
     let present=macros.contains_key(name);poll(a)?;flag(present)
    },
    "nameof"=>{
     if args.len()!=1{return arity_failure("nameof",args.len(),a)}
     let Some(name)=nameof(&args[0],a)? else{return failure("malformed nameof() call, expression appears to have no name",a)};
     Value::String(Text::Borrowed(name))
    },
    "fexists"=>return Ok(Evaluated::Unissued("Original fexists requires the authentic saved file/context and filesystem question")),
    "matrix"|"newlist"|"icon"|"sound"|"filter"|"file"|"generator"|"sin"|"cos"|"arcsin"|"arccos"|"rgb"|"list"=>return Ok(Evaluated::Unissued("Original conditional constant constructor/function is not issued")),
    _=>{let mut message=TextBuffer::new(a)?;message.push_str("non-constant function call: ",a)?;message.push_str(name,a)?;return Ok(Evaluated::SourceFailure(message))}
   }
  },
  _=>return Ok(Evaluated::Unissued("Original conditional term/follower constant product is not issued")),
 };
 Ok(Evaluated::Value(value))
}
fn arity_failure<'s>(name:&str,count:usize,a:&SettingAdmission<'_>)->io::Result<Evaluated<'s>>{let mut message=TextBuffer::new(a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out,"malformed {name}() call, must have 1 argument and instead has {count}")})?;Ok(Evaluated::SourceFailure(message))}
fn binary_failure<'s>(op:&str,lhs:&Value<'_>,rhs:&Value<'_>,a:&SettingAdmission<'_>)->io::Result<Evaluated<'s>>{
 let debug=if op=="/"{"Div"}else{dm_syntax::original_scalar_transport::original_punctuation_debug_name(op,false).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"accepted Original binary operator lacks canonical Debug name"))?};
 let mut message=TextBuffer::new(a)?;message.push_str("non-constant ",a)?;message.push_str(debug,a)?;message.push_str(": ",a)?;lhs.display(&mut message,a)?;message.push(' ',a)?;message.push_str(op,a)?;message.push(' ',a)?;rhs.display(&mut message,a)?;Ok(Evaluated::SourceFailure(message))
}
fn nameof<'s>(expr:&'s Expr,a:&SettingAdmission<'_>)->io::Result<Option<&'s str>>{
 let _frame=a.evaluation_frame().map_err(|error|a.take_operational_error().unwrap_or(error))?;
 Ok(match &expr.kind{ExprKind::Ident(name)=>Some(name),ExprKind::Group(inner)=>return nameof(inner,a),ExprKind::Member{selector,..}|ExprKind::StaticMember{selector,..}|ExprKind::SafeMember{selector,..}=>Some(selector),ExprKind::TypePath(path)=>path.rsplit('/').next().filter(|part|!part.is_empty()),_=>None})
}

#[cfg(test)]mod tests{
 use super::*;use std::{collections::BTreeMap,sync::{Arc,atomic::{AtomicUsize,Ordering}},cell::Cell};
 struct Macros{values:BTreeMap<String,crate::Macro>,reads:Cell<usize>}
 impl MacroLookup for Macros{fn initial_environment(&self)->crate::InitialEnvironment{crate::InitialEnvironment::OriginalChecker0290}fn get_key_value(&self,name:&str)->Option<(&str,&crate::Macro)>{self.reads.set(self.reads.get()+1);self.values.get_key_value(name).map(|(name,value)|(name.as_str(),value))}}
 fn macros()->Macros{Macros{values:BTreeMap::new(),reads:Cell::new(0)}}
 fn expression(kind:ExprKind)->Expr{Expr{kind,span:dm_syntax::Span::new(0,1)}}
 fn ident(name:&str)->Expr{expression(ExprKind::Ident(name.into()))}
 fn literal(value:OriginalTokenValue<&str>,a:&SettingAdmission<'_>)->Expr{expression(ExprKind::Literal(dm_syntax::LiteralText::from_original_value_data("intentionally misleading grammar".into(),0,value,a).unwrap()))}
 fn binary(op:&str,lhs:Expr,rhs:Expr)->Expr{expression(ExprKind::Binary{op:op.into(),lhs:Box::new(lhs),rhs:Box::new(rhs)})}
 fn call(name:&str,args:Vec<Expr>)->Expr{expression(ExprKind::Call{callee:Box::new(ident(name)),args})}
 fn yes(out:Outcome)->bool{match out{Outcome::Value(value)=>value,Outcome::SourceFailure(message)=>panic!("unexpected source failure: {}",message.as_str()),Outcome::Unissued(reason)=>panic!("unexpected unissued: {reason}")}}
 fn source(out:Outcome)->String{match out{Outcome::SourceFailure(message)=>message.as_str().into(),_=>panic!("expected exact original source failure")}}
 #[test]fn typed_scalar_values_precede_misleading_raw_spelling_and_preserve_nan_and_resource_variants(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let env=macros();{
  let zero=literal(OriginalTokenValue::Int(0),&a);assert!(!yes(evaluate(&zero,&env,&a).unwrap()));
  let nan=binary("==",literal(OriginalTokenValue::Float(f32::NAN),&a),literal(OriginalTokenValue::Float(f32::NAN),&a));assert!(yes(evaluate(&nan,&env,&a).unwrap()));
  let negative_zero=binary("==",literal(OriginalTokenValue::Float(-0.0),&a),literal(OriginalTokenValue::Int(0),&a));assert!(yes(evaluate(&negative_zero,&env,&a).unwrap()));
  assert!(yes(evaluate(&literal(OriginalTokenValue::Resource(""),&a),&env,&a).unwrap()));assert!(!yes(evaluate(&literal(OriginalTokenValue::String(""),&a),&env,&a).unwrap()));
  let variants=binary("==",literal(OriginalTokenValue::String("same"),&a),literal(OriginalTokenValue::Resource("same"),&a));assert!(!yes(evaluate(&variants,&env,&a).unwrap()));
 }assert_eq!(used.load(Ordering::Acquire),0)}
 #[test]fn actual_eager_boolean_operands_and_lazy_ternary_do_not_use_host_short_circuit_semantics(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let env=macros();for(op,left)in[("&&",0),("||",1)]{let expr=binary(op,literal(OriginalTokenValue::Int(left),&a),ident("UNEXPANDED"));assert_eq!(source(evaluate(&expr,&env,&a).unwrap()),"cannot reference variable \"UNEXPANDED\" in this context");}let expr=expression(ExprKind::Conditional{condition:Box::new(literal(OriginalTokenValue::Int(1),&a)),then_value:Box::new(literal(OriginalTokenValue::Int(7),&a)),else_value:Box::new(ident("NEVER_EVALUATED"))});assert!(yes(evaluate(&expr,&env,&a).unwrap()));}
 #[test]fn defined_records_actual_positive_and_negative_name_questions_without_evaluating_or_unwrapping_operand(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut env=macros();env.values.insert("PRESENT".into(),crate::Macro{parameters:None,variadic:false,replacement:"anything".into()});assert!(yes(evaluate(&call("defined",vec![ident("PRESENT")]),&env,&a).unwrap()));assert!(!yes(evaluate(&call("defined",vec![ident("MISSING")]),&env,&a).unwrap()));assert_eq!(env.reads.get(),2);let bad=call("defined",vec![expression(ExprKind::Group(Box::new(ident("PRESENT"))))]);assert_eq!(source(evaluate(&bad,&env,&a).unwrap()),"malformed defined() call, argument given isn't an Ident.");assert_eq!(env.reads.get(),2);assert_eq!(source(evaluate(&call("defined",vec![]),&env,&a).unwrap()),"malformed defined() call, must have 1 argument and instead has 0");}
 #[test]fn exact_old_numeric_judge_and_source_error_formatting_share_existing_arithmetic_and_display(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let env=macros();for(op,left,right,result)in[("%%",-5.0,3.0,1.0),("**",2.0,3.0,8.0),("|",16777216.0,1.0,1.0)]{let expr=binary("==",binary(op,literal(OriginalTokenValue::Float(left),&a),literal(OriginalTokenValue::Float(right),&a)),literal(OriginalTokenValue::Float(result),&a));assert!(yes(evaluate(&expr,&env,&a).unwrap()));}let expr=binary("/",literal(OriginalTokenValue::String("bad"),&a),literal(OriginalTokenValue::Int(2),&a));assert_eq!(source(evaluate(&expr,&env,&a).unwrap()),"non-constant Div: \"bad\" / 2");let expr=binary("=",ident("LHS_NOT_EVALUATED"),ident("RHS_NOT_EVALUATED"));assert_eq!(source(evaluate(&expr,&env,&a).unwrap()),"non-constant assignment");}
 #[test]fn allocation_and_first_actual_io_refusal_do_not_become_false_or_source_failure_and_same_domain_recovers(){let used=Arc::new(AtomicUsize::new(0));let env=macros();let expr=ident("UNEXPANDED");let failed=SettingAdmission::new(&used,1<<20,&||Err(io::Error::from_raw_os_error(1450)));assert_eq!(evaluate(&expr,&env,&failed).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),0);let too_small=SettingAdmission::new(&used,0,&||Ok(()));assert_eq!(evaluate(&expr,&env,&too_small).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),0);let good=SettingAdmission::new(&used,1<<20,&||Ok(()));let result=evaluate(&expr,&env,&good).unwrap();assert!(matches!(result,Outcome::SourceFailure(_)));drop(result);assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn unavailable_contextual_constructor_and_unissued_shift_are_not_silently_false(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let env=macros();for expr in[call("fexists",vec![literal(OriginalTokenValue::String("x"),&a)]),call("sin",vec![literal(OriginalTokenValue::Int(0),&a)]),binary("<<",literal(OriginalTokenValue::Int(1),&a),literal(OriginalTokenValue::Int(32),&a))]{assert!(matches!(evaluate(&expr,&env,&a).unwrap(),Outcome::Unissued(_)));}}
}
