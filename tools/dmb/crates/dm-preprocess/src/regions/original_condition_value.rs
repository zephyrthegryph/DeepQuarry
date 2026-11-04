//! Judge for an ALREADY parsed authentic Original condition. No parsing,
//! expansion, source reads, or unavailable-model recovery lives here.
//! ConstantFolder::expr/unary/binary/term at pinned0290 is the authority.
use crate::condition_parser::ConditionNumber;
use crate::macro_expansion::{OriginalMacroText as TextBuffer,OriginalMacroTextValue as Text,original_format_using};
use crate::MacroLookup;
use crate::macro_expansion::OriginalMacroRows as Rows;
use dm_syntax::{Expr,ExprKind,OriginalTokenValue,SettingAdmission};
use std::io;

pub(super) enum FileExistsResult{Value(bool),SourceFailure(TextBuffer)}
pub(crate) enum Outcome{Value(bool),SourceFailure(TextBuffer),SourceWarning(TextBuffer),Unissued(&'static str)}
enum Value<'s>{Number(ConditionNumber),String(Text<'s>),Resource(&'s str),Prefab(&'s str),Compound{display:TextBuffer,equality:TextBuffer}}
enum Evaluated<'s>{Value(Value<'s>),SourceFailure(TextBuffer),SourceWarning(TextBuffer),Unissued(&'static str)}
macro_rules! value{($expr:expr)=>{match $expr?{Evaluated::Value(value)=>value,Evaluated::SourceFailure(message)=>return Ok(Evaluated::SourceFailure(message)),Evaluated::SourceWarning(message)=>return Ok(Evaluated::SourceWarning(message)),Evaluated::Unissued(reason)=>return Ok(Evaluated::Unissued(reason))}}}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|error|a.take_operational_error().unwrap_or(error))}
fn failure<'s>(message:&str,a:&SettingAdmission<'_>)->io::Result<Evaluated<'s>>{let mut text=TextBuffer::new(a)?;text.push_str(message,a)?;Ok(Evaluated::SourceFailure(text))}
impl Value<'_>{
 fn truth(&self)->bool{match self{Self::Number(n)=>n.truth(),Self::String(s)=>!s.get().is_empty(),Self::Resource(_)|Self::Prefab(_)|Self::Compound{..}=>true}}
 fn equal(&self,rhs:&Self)->bool{match(self,rhs){(Self::Number(ConditionNumber::Null),Self::Number(ConditionNumber::Null))=>true,(Self::Number(ConditionNumber::Original(a)),Self::Number(ConditionNumber::Original(b)))=>a==b||(a.is_nan()&&b.is_nan()),(Self::String(a),Self::String(b))=>a.get()==b.get(),(Self::Resource(a),Self::Resource(b))=>a==b,(Self::Prefab(a),Self::Prefab(b))=>a==b,(Self::Compound{equality:a,..},Self::Compound{equality:b,..})=>a.as_str()==b.as_str(),_=>false}}
 fn display(&self,out:&mut TextBuffer,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;match self{
  Self::Number(ConditionNumber::Original(n))=>original_format_using(out,a,|out|dm_syntax::numeric_form::write_original_float(*n,out)),
  Self::Number(ConditionNumber::Null)=>out.push_str("null",a),
  Self::Number(ConditionNumber::Native(_))=>Err(io::Error::new(io::ErrorKind::InvalidData,"native integer reached Original conditional judge")),
  Self::String(value)=>{let(open,close)=crate::macro_expansion::original_quote_delimiters(value.get());out.push_str(open,a)?;out.push_str(value.get(),a)?;out.push_str(close,a)},
  Self::Resource(value)=>{out.push('\'',a)?;out.push_str(value,a)?;out.push('\'',a)},
  Self::Prefab(path)=>out.push_str(path,a),
  Self::Compound{display,..}=>out.push_str(display.as_str(),a),
 }}
}
// Injective typed folded VALUE key, not source spelling or parser authority.
// Children remain funded through the parent's funded copy, then retire. The
// retained two flat buffers need no recursive owner destruction or cloned AST.
fn equality_key(value:&Value<'_>,out:&mut TextBuffer,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;match value{
 Value::Number(ConditionNumber::Original(number))=>{let bits=if number.is_nan(){f32::NAN.to_bits()}else if *number==0.0{0}else{number.to_bits()};original_format_using(out,a,|out|{use std::fmt::Write;write!(out,"N{bits:08x};")})},
 Value::Number(ConditionNumber::Null)=>out.push_str("Z;",a),Value::Number(ConditionNumber::Native(_))=>Err(io::ErrorKind::InvalidData.into()),
 Value::String(value)=>typed_key("S",value.get(),out,a),Value::Resource(value)=>typed_key("R",value,out,a),Value::Prefab(value)=>typed_key("P",value,out,a),Value::Compound{equality,..}=>typed_key("V",equality.as_str(),out,a),
}}
fn typed_key(tag:&str,text:&str,out:&mut TextBuffer,a:&SettingAdmission<'_>)->io::Result<()>{original_format_using(out,a,|out|{use std::fmt::Write;write!(out,"{tag}{}:",text.len())})?;out.push_str(text,a)}
fn compound<'s>(name:&str,args:&'s [Expr],macros:&dyn MacroLookup,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>)->io::Result<Evaluated<'s>>{
 let list=name=="list";let mut display=TextBuffer::new(a)?;let mut equality=TextBuffer::new(a)?;
 display.push_str(name,a)?;display.push('(',a)?;typed_key(if list{"L"}else{"C"},name,&mut equality,a)?;original_format_using(&mut equality,a,|out|{use std::fmt::Write;write!(out,"{};",args.len())})?;
 let mut previous_assoc=false;
 for(index,arg)in args.iter().enumerate(){poll(a)?;if index!=0{display.push(',',a)?;if !list||previous_assoc{display.push(' ',a)?}}let(key,associated)=if let ExprKind::Binary{op,lhs,rhs}=&arg.kind{if op=="="{(lhs.as_ref(),Some(rhs.as_ref()))}else{(arg,None)}}else{(arg,None)};
 let key=if associated.is_some(){if let ExprKind::Ident(name)=&key.kind{Value::String(Text::Borrowed(name))}else{value!(evaluate_inner(key,macros,a,file_exists,constructors))}}else{value!(evaluate_inner(key,macros,a,file_exists,constructors))};
 key.display(&mut display,a)?;equality_key(&key,&mut equality,a)?;drop(key);previous_assoc=associated.is_some();
 if let Some(associated)=associated{equality.push_str("A",a)?;let associated=value!(evaluate_inner(associated,macros,a,file_exists,constructors));display.push_str(" = ",a)?;associated.display(&mut display,a)?;equality_key(&associated,&mut equality,a)?;}else{equality.push_str("O",a)?;}
 }
 display.push(')',a)?;Ok(Evaluated::Value(Value::Compound{display,equality}))
}
fn int(value:&Value<'_>)->Option<i32>{match value{Value::Number(ConditionNumber::Original(number))=>Some(*number as i32),_=>None}}
fn string<'a>(value:&'a Value<'_>)->Option<&'a str>{match value{Value::String(value)=>Some(value.get()),_=>None}}
// SAME pinned rgb algorithm and color_space0.5.4, bounded to five actual args.
// Stack tuple slots retain their actual independently funded folded children.
fn rgb<'s>(args:&'s [Expr],macros:&dyn MacroLookup,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>)->io::Result<Evaluated<'s>>{
 use color_space::{Rgb,Hsv,Hsl,Lch};
 if !matches!(args.len(),3..=5){let mut m=TextBuffer::new(a)?;original_format_using(&mut m,a,|out|{use std::fmt::Write;write!(out,"malformed rgb() call, must have 3, 4, or 5 arguments and instead has {}",args.len())})?;return Ok(Evaluated::SourceFailure(m))}
 let mut arguments:[Option<(Value<'s>,Option<Value<'s>>)>;5]=std::array::from_fn(|_|None);
 for(index,arg)in args.iter().enumerate(){poll(a)?;let(key,association)=if let ExprKind::Binary{op,lhs,rhs}=&arg.kind{if op=="="{(lhs.as_ref(),Some(rhs.as_ref()))}else{(arg,None)}}else{(arg,None)};let key=if association.is_some(){if let ExprKind::Ident(name)=&key.kind{Value::String(Text::Borrowed(name))}else{value!(evaluate_inner(key,macros,a,file_exists,constructors))}}else{value!(evaluate_inner(key,macros,a,file_exists,constructors))};let association=match association{Some(v)=>Some(value!(evaluate_inner(v,macros,a,file_exists,constructors))),None=>None};arguments[index]=Some((key,association));}
 let(mut has_rgb,mut h,mut sat,mut v,mut l,mut c,mut y)=(false,false,false,false,false,false,false);let mut alpha=None;let mut space=None;
 for(key,association)in arguments[..args.len()].iter().map(|v|v.as_ref().unwrap()){poll(a)?;let Some(associated)=association else{continue};let Some(key_string)=string(key)else{let mut m=TextBuffer::new(a)?;m.push_str("malformed rgb() call, kwarg is not string: ",a)?;key.display(&mut m,a)?;return Ok(Evaluated::SourceFailure(m))};match key_string{
 "r"|"red"|"g"|"green"|"b"|"blue"=>has_rgb=true,"h"|"hue"=>h=true,"s"|"saturation"=>sat=true,"v"|"value"=>v=true,"l"|"luminance"=>l=true,"c"|"chroma"=>c=true,"y"=>y=true,"a"|"alpha"=>alpha=int(associated),
 "space"=>match int(associated){Some(n @ 0..=3)=>space=Some(n),_=>{let mut m=TextBuffer::new(a)?;m.push_str("malformed rgb() call, bad color space: ",a)?;associated.display(&mut m,a)?;return Ok(Evaluated::SourceFailure(m))}},
 _=>{let mut m=TextBuffer::new(a)?;m.push_str("malformed rgb() call, bad kwarg passed: ",a)?;m.push_str(key_string,a)?;return Ok(Evaluated::SourceFailure(m))}
 }}
 let space=if let Some(space)=space{space}else if has_rgb{0}else if h{if c&&y{3}else if sat{if v{1}else if l{2}else{return failure("malformed rgb() call, could not determine space: only h & s specified",a)}}else{return failure("malformed rgb() call, could not determine space: only h specified",a)}}else{0};
 let mut values=[0f64;5];let mut count=0;
 for(index,(key,association))in arguments[..args.len()].iter().map(|v|v.as_ref().unwrap()).enumerate(){poll(a)?;let mut range=if index==0{if space==0{0..=255}else{0..=360}}else if index<3{if space==0{0..=255}else{0..=100}}else{0..=255};let check=if let Some(associated)=association{let key=string(key).ok_or(io::ErrorKind::InvalidData)?;range=match key{"r"|"red"|"g"|"green"|"b"|"blue"=>0..=255,"h"|"hue"=>0..=360,"s"|"saturation"|"v"|"value"|"c"|"chroma"|"l"|"y"|"luminance"=>0..=100,"a"|"alpha"=>0..=255,"space"=>continue,_=>return Err(io::ErrorKind::InvalidData.into())};associated}else{key};
 let Some(number)=int(check)else{return failure("malformed rgb() call, value wasn't an int",a)};if !range.contains(&number){let mut m=TextBuffer::new(a)?;original_format_using(&mut m,a,|out|{use std::fmt::Write;write!(out,"malformed rgb() call, {} is not within the valid range ({}..{})",number,range.start(),range.end())})?;return Ok(Evaluated::SourceWarning(m))}values[count]=number.clamp(*range.start(),*range.end())as f64;count+=1;
 }
 // Pinned asserts/panics here for duplicate space arguments leaving <3 values;
 // no successful VALUE or false source result is invented for that old panic.
 if count<3{return Ok(Evaluated::Unissued("pinned rgb() panics after fewer than three non-space arguments"))}
 let color:Rgb=match space{0=>Rgb::new(values[0],values[1],values[2]),1=>Hsv::new(values[0],values[1]*0.01,values[2]*0.01).into(),2=>Hsl::new(values[0],values[1]*0.01,values[2]*0.01).into(),3=>Lch::new(values[2],values[1],values[0]).into(),_=>return Err(io::ErrorKind::InvalidData.into())};let alpha=alpha.or_else(||(count>3).then_some(values[3]as i32));let mut text=TextBuffer::new(a)?;original_format_using(&mut text,a,|out|{use std::fmt::Write;if let Some(alpha)=alpha{write!(out,"#{:02x}{:02x}{:02x}{:02x}",color.r.round()as u8,color.g.round()as u8,color.b.round()as u8,alpha)}else{write!(out,"#{:02x}{:02x}{:02x}",color.r.round()as u8,color.g.round()as u8,color.b.round()as u8)}})?;Ok(Evaluated::Value(Value::String(Text::Owned(text))))
}
fn absolute_prefab(path:&str)->bool{path.starts_with('/')&&!path.contains(['.',':'])}
fn prefab_fields<'s>(object:&'s Expr,fields:&'s [(String,Expr)],macros:&dyn MacroLookup,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>)->io::Result<Evaluated<'s>>{
 let ExprKind::TypePath(path)=&object.kind else{return Ok(Evaluated::Unissued("Original prefab fields lack actual native TypePath target"))};let mut values:Rows<(&str,Value<'s>)>=Rows::new(a)?;
 // Pinned prefab folds every initializer in encounter order before resolving
 // its path. Duplicate fields replace their value without moving first position.
 for(name,expression)in fields{poll(a)?;let value=value!(evaluate_inner(expression,macros,a,file_exists,constructors));let mut existing=None;for(index,(prior,_))in values.as_slice().iter().enumerate(){poll(a)?;if *prior==name.as_str(){existing=Some(index);break}}if let Some(index)=existing{values.as_mut_slice()[index].1=value}else{values.push((name.as_str(),value),a)?;}}
 if !absolute_prefab(path){let mut message=TextBuffer::new(a)?;message.push_str("cannot resolve relative type path without an object tree: ",a)?;message.push_str(path,a)?;return Ok(Evaluated::SourceFailure(message))}if values.len()==0{return Ok(Evaluated::Value(Value::Prefab(path)))}
 let mut display=TextBuffer::new(a)?;let mut equality=TextBuffer::new(a)?;display.push_str(path,a)?;for(index,(name,value))in values.as_slice().iter().enumerate(){poll(a)?;display.push_str(if index==0{" {"}else{"; "},a)?;display.push_str(name,a)?;display.push_str(" = ",a)?;value.display(&mut display,a)?;}display.push('}',a)?;
 // IndexMap equality ignores insertion order. Canonicalize names using a
 // bounded scanned selection over the existing funded map, never a shadow map.
 typed_key("P",path,&mut equality,a)?;original_format_using(&mut equality,a,|out|{use std::fmt::Write;write!(out,"{};",values.len())})?;let mut previous:Option<&str>=None;for _ in 0..values.len(){let mut chosen:Option<(&str,&Value<'s>)>=None;for(name,value)in values.as_slice(){poll(a)?;if previous.is_none_or(|previous|*name>previous)&&chosen.is_none_or(|(chosen,_)|*name<chosen){chosen=Some((*name,value))}}let(name,value)=chosen.ok_or(io::ErrorKind::InvalidData)?;typed_key("F",name,&mut equality,a)?;equality_key(value,&mut equality,a)?;previous=Some(name);}
 Ok(Evaluated::Value(Value::Compound{display,equality}))
}
fn new_value<'s>(target:Option<&'s Expr>,args:Option<&'s [Expr]>,macros:&dyn MacroLookup,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>)->io::Result<Evaluated<'s>>{
 let mut display=TextBuffer::new(a)?;let mut equality=TextBuffer::new(a)?;display.push_str("new",a)?;equality.push_str("J",a)?;
 if let Some(target)=target{let target=value!(evaluate_inner(target,macros,a,file_exists,constructors));display.push(' ',a)?;target.display(&mut display,a)?;equality.push_str("T",a)?;equality_key(&target,&mut equality,a)?;}else{equality.push_str("O",a)?;}
 if let Some(args)=args{let args=value!(compound("new",args,macros,a,file_exists,constructors));let Value::Compound{display:arg_display,equality:arg_equality}=args else{return Err(io::ErrorKind::InvalidData.into())};display.push_str(arg_display.as_str().strip_prefix("new").ok_or(io::ErrorKind::InvalidData)?,a)?;typed_key("A",arg_equality.as_str(),&mut equality,a)?;}else{equality.push_str("O",a)?;}
 Ok(Evaluated::Value(Value::Compound{display,equality}))
}
fn flag(value:bool)->Value<'static>{Value::Number(ConditionNumber::flag(value,true))}
/// The caller attaches SourceFailure to the SAVED actual condition start,
/// exactly as preprocessor_evaluate(start,...); not its later read point.
pub(crate) fn evaluate(expr:&Expr,macros:&dyn MacroLookup,a:&SettingAdmission<'_>)->io::Result<Outcome>{evaluate_with_file_exists_using(expr,macros,a,None)}
pub(crate) fn evaluate_with_file_exists_using(expr:&Expr,macros:&dyn MacroLookup,a:&SettingAdmission<'_>,file_exists:Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>)->io::Result<Outcome>{evaluate_with_native_facts_using(expr,macros,a,file_exists,None)}
pub(crate) fn evaluate_with_native_facts_using(expr:&Expr,macros:&dyn MacroLookup,a:&SettingAdmission<'_>,mut file_exists:Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>)->io::Result<Outcome>{
 if constructors.is_some_and(|facts|!facts.is_admitted_by(a)){return Err(io::ErrorKind::InvalidInput.into())}

 poll(a)?;if macros.initial_environment()!=crate::InitialEnvironment::OriginalChecker0290{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original condition requires actual Original macro environment"))}
 Ok(match evaluate_inner(expr,macros,a,&mut file_exists,constructors)?{Evaluated::Value(value)=>Outcome::Value(value.truth()),Evaluated::SourceFailure(message)=>Outcome::SourceFailure(message),Evaluated::SourceWarning(message)=>Outcome::SourceWarning(message),Evaluated::Unissued(reason)=>Outcome::Unissued(reason)})
}
fn evaluate_inner<'s>(expr:&'s Expr,macros:&dyn MacroLookup,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>)->io::Result<Evaluated<'s>>{
 let _frame=a.evaluation_frame().map_err(|error|a.take_operational_error().unwrap_or(error))?;
 let value=match &expr.kind{
  ExprKind::Literal(literal)if literal.original_template_lexical_shape().is_some_and(|shape|shape.interpolated)=>return failure("non-constant expression",a),
  ExprKind::Literal(literal)=>match literal.original_value(){
   Some(OriginalTokenValue::Int(n))=>Value::Number(ConditionNumber::Original(n as f32)),Some(OriginalTokenValue::Float(n))=>Value::Number(ConditionNumber::Original(n)),
   Some(OriginalTokenValue::String(s))=>Value::String(Text::Borrowed(s)),Some(OriginalTokenValue::Resource(s))=>Value::Resource(s),
   Some(_)=>return Ok(Evaluated::Unissued("Original condition literal has no scalar constant product")),
   None if literal.as_str()=="null"=>Value::Number(ConditionNumber::Null),
   None=>return Ok(Evaluated::Unissued("Original condition literal lacks authentic typed value")),
  },
  ExprKind::ObjectInitializer{object,fields}=>return prefab_fields(object,fields,macros,a,file_exists,constructors),
  ExprKind::Ident(name)=>match name.as_str(){
   "null"=>Value::Number(ConditionNumber::Null),"type"|"parent_type"=>return failure("no type context",a),"__TYPE__"=>return failure("No type context",a),"__IMPLIED_TYPE__"=>return failure("No type hint",a),
   _=>{let mut message=TextBuffer::new(a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out,"cannot reference variable {name:?} in this context")})?;return Ok(Evaluated::SourceFailure(message))}
  },
  ExprKind::TypePath(path)=>{if !absolute_prefab(path) {let mut message=TextBuffer::new(a)?;message.push_str("cannot resolve relative type path without an object tree: ",a)?;message.push_str(path,a)?;return Ok(Evaluated::SourceFailure(message))}Value::Prefab(path)},
  ExprKind::Group(inner)=>value!(evaluate_inner(inner,macros,a,file_exists,constructors)),
  // Native Original TypeFilter belongs to input() clause syntax.
  ExprKind::TypeFilter{value:inner,..}=>value!(evaluate_inner(inner,macros,a,file_exists,constructors)),
  ExprKind::Conditional{condition,then_value,else_value}=>{let condition=value!(evaluate_inner(condition,macros,a,file_exists,constructors));value!(evaluate_inner(if condition.truth(){then_value}else{else_value},macros,a,file_exists,constructors))},
  ExprKind::Unary{op,value:operand}=>{
   if op=="::"{return failure("non-constant expression",a)}
   if op=="new"{let(target,args)=match &operand.kind{ExprKind::Call{callee,args}if matches!(callee.kind,ExprKind::TypePath(_)|ExprKind::ObjectInitializer{..})=>(callee.as_ref(),Some(args.as_slice())),ExprKind::TypePath(_)|ExprKind::ObjectInitializer{..}=>(operand.as_ref(),None),_=>return failure("non-constant new expression",a)};return new_value(Some(target),args,macros,a,file_exists,constructors)}

   if !matches!(op.as_str(),"!"|"-"|"~"|"&"|"*"|"pre++"|"pre--"|"post++"|"post--"){return Ok(Evaluated::Unissued("Original conditional unary grammar branch is not issued"))}
   let operand=value!(evaluate_inner(operand,macros,a,file_exists,constructors));
   if matches!(op.as_str(),"&"|"*"|"pre++"|"pre--"|"post++"|"post--"){let mut message=TextBuffer::new(a)?;message.push_str("non-constant unary operation: ",a)?;let(prefix,suffix)=match op.as_str(){"pre++"=>("++",""),"pre--"=>("--",""),"post++"=>("","++"),"post--"=>("","--"),"&"=>("&",""),"*"=>("*",""),_=>unreachable!()};message.push_str(prefix,a)?;operand.display(&mut message,a)?;message.push_str(suffix,a)?;return Ok(Evaluated::SourceFailure(message))}

   if op=="!"{flag(!operand.truth())}else if let Value::Number(ConditionNumber::Original(number))=operand{Value::Number(ConditionNumber::Original(number).unary(op).map_err(|_|io::Error::new(io::ErrorKind::InvalidData,"accepted Original numeric unary operation refused"))?)}else{
    let mut message=TextBuffer::new(a)?;message.push_str("non-constant unary operation: ",a)?;message.push_str(op,a)?;operand.display(&mut message,a)?;return Ok(Evaluated::SourceFailure(message))
   }
  },
  ExprKind::Binary{op,lhs,rhs}=>{
   if matches!(op.as_str(),"="|"+="|"-="|"*="|"/="|"%="|"%%="|"**="|"|="|"&="|"^="|"<<="|">>="|"&&="|"||="|":="){return failure("non-constant assignment",a)}
   if !matches!(op.as_str(),"+"|"-"|"*"|"/"|"%"|"%%"|"**"|"<"|"<="|">"|">="|"|"|"&"|"^"|"<<"|">>"|"=="|"!="|"&&"|"||"|"in"){return Ok(Evaluated::Unissued("Original conditional binary grammar branch is not issued"))}
   // The actual old folder evaluates BOTH operands before And/Or selection.
   let lhs=value!(evaluate_inner(lhs,macros,a,file_exists,constructors));let rhs=value!(evaluate_inner(rhs,macros,a,file_exists,constructors));
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
  ExprKind::Member{object,selector,via_colon}=>{let object=value!(evaluate_inner(object,macros,a,file_exists,constructors));let mut message=TextBuffer::new(a)?;message.push_str("non-constant expression follower: ",a)?;object.display(&mut message,a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out," Field({}, {selector:?})",if *via_colon{"Colon"}else{"Dot"})})?;return Ok(Evaluated::SourceFailure(message))},
  ExprKind::SafeMember{object,selector,via_colon}=>{let object=value!(evaluate_inner(object,macros,a,file_exists,constructors));let mut message=TextBuffer::new(a)?;message.push_str("non-constant expression follower: ",a)?;object.display(&mut message,a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out," Field({}, {selector:?})",if *via_colon{"SafeColon"}else{"SafeDot"})})?;return Ok(Evaluated::SourceFailure(message))},
  ExprKind::StaticMember{object,..}=>{let object=value!(evaluate_inner(object,macros,a,file_exists,constructors));if matches!(object,Value::Prefab(_)){return failure("no type tree available",a)}let mut message=TextBuffer::new(a)?;message.push_str("non typepath ",a)?;object.display(&mut message,a)?;message.push_str(" used with ::",a)?;return Ok(Evaluated::SourceFailure(message))},
  ExprKind::Call{callee,args}=>{
   if matches!(&callee.kind,ExprKind::Unary{op,..}if op=="::"){return failure("non-constant expression",a)}
   let ExprKind::Ident(name)=&callee.kind else{return Ok(Evaluated::Unissued("Original conditional expression follower requires its actual constant product"))};
   match name.as_str(){
    "new"=>{let Some(has_args)=(match constructors{Some(facts)=>facts.implicit_at_using(callee.span,a)?,None=>None})else{return Ok(Evaluated::Unissued("Original implicit new lacks actual native argument-presence fact"))};if !has_args&&!args.is_empty(){return Err(io::ErrorKind::InvalidData.into())}return new_value(None,has_args.then_some(args.as_slice()),macros,a,file_exists,constructors)},

    "input"|"locate"|"pick"=>return failure("non-constant expression",a),
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
    "fexists"=>{if args.len()!=1{return arity_failure("fexists",args.len(),a)}let ExprKind::Literal(literal)=&args[0].kind else{return failure("malformed fexists() call, argument given isn't a string.",a)};let Some(OriginalTokenValue::String(path))=literal.original_value()else{return failure("malformed fexists() call, argument given isn't a string.",a)};let Some(context)=file_exists.as_deref_mut()else{return Ok(Evaluated::Unissued("Original fexists requires the authentic saved file/context and filesystem question"))};match context(path)?{FileExistsResult::Value(value)=>flag(value),FileExistsResult::SourceFailure(message)=>return Ok(Evaluated::SourceFailure(message))}},
    "sin"|"cos"|"arcsin"|"arccos"=>{if args.len()!=1{let mut message=TextBuffer::new(a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out,"trig function requires exactly 1 argument, instead found {}",args.len())})?;return Ok(Evaluated::SourceFailure(message))}let argument=value!(evaluate_inner(&args[0],macros,a,file_exists,constructors));let Value::Number(ConditionNumber::Original(number))=argument else{return failure("trig function requires numeric argument",a)};let operation:fn(f32)->f32=match name.as_str(){"sin"=>f32::sin,"cos"=>f32::cos,"arcsin"=>f32::asin,"arccos"=>f32::acos,_=>unreachable!()};Value::Number(ConditionNumber::Original(operation(number)))},
    "matrix"|"newlist"|"icon"|"sound"|"filter"|"file"|"generator"|"list"=>return compound(name,args,macros,a,file_exists,constructors),
    "rgb"=>return rgb(args,macros,a,file_exists,constructors),
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
 fn yes(out:Outcome)->bool{match out{Outcome::Value(value)=>value,Outcome::SourceFailure(message)=>panic!("unexpected source failure: {}",message.as_str()),Outcome::SourceWarning(message)=>panic!("unexpected source warning: {}",message.as_str()),Outcome::Unissued(reason)=>panic!("unexpected unissued: {reason}")}}
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
 #[test]fn unavailable_context_and_wide_shift_are_not_silently_false(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let env=macros();for expr in[call("fexists",vec![literal(OriginalTokenValue::String("x"),&a)]),binary("<<",literal(OriginalTokenValue::Int(1),&a),literal(OriginalTokenValue::Int(32),&a))]{assert!(matches!(evaluate(&expr,&env,&a).unwrap(),Outcome::Unissued(_)));}}
 #[test]fn actual_compound_key_preserves_folded_numeric_nan_zero_and_nested_constructor_structure(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let env=macros();{let expr=binary("==",call("matrix",vec![literal(OriginalTokenValue::Float(-0.0),&a),literal(OriginalTokenValue::Float(f32::from_bits(0x7fc00001)),&a)]),call("matrix",vec![literal(OriginalTokenValue::Int(0),&a),literal(OriginalTokenValue::Float(f32::from_bits(0x7fc00002)),&a)]));assert!(yes(evaluate(&expr,&env,&a).unwrap()));let expr=binary("==",call("icon",vec![call("list",vec![binary("+",literal(OriginalTokenValue::Int(1),&a),literal(OriginalTokenValue::Int(1),&a))])]),call("icon",vec![call("list",vec![literal(OriginalTokenValue::Int(2),&a)])]));assert!(yes(evaluate(&expr,&env,&a).unwrap()));}assert_eq!(used.load(Ordering::Acquire),0);}
 #[test]fn compound_product_quota_and_late_first_io_retire_flat_buffers_without_false_outcome(){let used=Arc::new(AtomicUsize::new(0));let env=macros();let expr=call("icon",vec![call("matrix",vec![])]);let tiny=SettingAdmission::new(&used,0,&||Ok(()));assert_eq!(evaluate(&expr,&env,&tiny).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),0);for fail_at in[1,8,32]{let calls=Cell::new(0);let checkpoint=||{let n=calls.get()+1;calls.set(n);if n>=fail_at{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};let a=SettingAdmission::new(&used,8<<20,&checkpoint);let result=evaluate(&expr,&env,&a);if let Err(error)=result{assert_eq!(error.raw_os_error(),Some(1450))}assert_eq!(used.load(Ordering::Acquire),0);}}

}

#[cfg(test)]mod actual_original_trig_controls{use super::*;use std::{sync::{Arc,atomic::{AtomicUsize,Ordering}},collections::BTreeMap};struct Env(BTreeMap<String,crate::Macro>);impl MacroLookup for Env{fn initial_environment(&self)->crate::InitialEnvironment{crate::InitialEnvironment::OriginalChecker0290}fn get_key_value(&self,n:&str)->Option<(&str,&crate::Macro)>{self.0.get_key_value(n).map(|(k,v)|(k.as_str(),v))}}fn call(n:&str,args:Vec<Expr>)->Expr{let span=dm_syntax::Span::new(0,1);Expr{span,kind:ExprKind::Call{callee:Box::new(Expr{span,kind:ExprKind::Ident(n.into())}),args}}}fn lit(v:OriginalTokenValue<&str>,a:&SettingAdmission<'_>)->Expr{Expr{span:dm_syntax::Span::new(0,1),kind:ExprKind::Literal(dm_syntax::LiteralText::from_original_value_data("same-issued-value".into(),0,v,a).unwrap())}}#[test]fn original_trig_uses_exact_pinned_f32_operations_and_argument_failure_text(){let used=Arc::new(AtomicUsize::new(0));let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let env=Env(BTreeMap::new());for(name,arg,wanted)in[("sin",0,false),("cos",0,true),("arcsin",0,false),("arccos",1,false)]{let expr=call(name,vec![lit(OriginalTokenValue::Int(arg),&a)]);assert!(matches!(evaluate(&expr,&env,&a).unwrap(),Outcome::Value(v)if v==wanted));}for(expr,message)in[(call("sin",vec![]),"trig function requires exactly 1 argument, instead found 0"),(call("cos",vec![lit(OriginalTokenValue::String("x"),&a)]),"trig function requires numeric argument")]{let Outcome::SourceFailure(actual)=evaluate(&expr,&env,&a).unwrap()else{panic!("actual source failure")};assert_eq!(actual.as_str(),message);}assert_eq!(used.load(Ordering::Acquire),0);}}
