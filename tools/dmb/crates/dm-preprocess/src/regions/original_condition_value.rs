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

/// Explicit utility model DATA callbacks. Implementations must bind their actual
/// retained declaration/source owner; this evaluator issues no source grant.
pub trait ModelContext{
 fn identifier(&self,name:&str,must_be_const:bool,a:&SettingAdmission<'_>)->io::Result<ModelOutcome>;
 fn type_value(&self,parent:bool,a:&SettingAdmission<'_>)->io::Result<ModelOutcome>;
 fn static_member(&self,path:&str,name:&str,a:&SettingAdmission<'_>)->io::Result<ModelOutcome>;
 fn resolve_prefab(&self,path:&str,a:&SettingAdmission<'_>)->io::Result<ModelOutcome>;
 fn type_hint(&self)->Option<&str>;
}
/// Operation-owned paid VALUE only; never an expression/model/cache receipt.
pub struct ModelValue{value:Value<'static>}
pub struct ModelMessage{value:TextBuffer,site:Option<usize>}
impl ModelMessage{pub fn as_str(&self)->&str{self.value.as_str()}pub fn site(&self)->Option<usize>{self.site}}
impl From<TextBuffer> for ModelMessage{fn from(value:TextBuffer)->Self{Self{value,site:None}}}
pub enum ModelOutcome{Value(ModelValue),SourceFailure(ModelMessage),SourceWarning(ModelMessage),Unissued(&'static str)}
impl ModelOutcome{
 pub fn at_site(mut self,key:usize)->Self{match &mut self{Self::SourceFailure(message)|Self::SourceWarning(message)=>message.site=Some(key),_=>()}self}
 pub fn failure_format_using(message:std::fmt::Arguments<'_>,a:&SettingAdmission<'_>)->io::Result<Self>{
  let pending=(||{let mut text=TextBuffer::new(a)?;original_format_using(&mut text,a,|out|{use std::fmt::Write;out.write_fmt(message)})?;Ok(Self::SourceFailure(text.into()))})();
  match a.take_operational_error(){Some(first)=>Err(first),None=>pending}
 }
 pub fn at_site_if_absent(mut self,key:usize)->Self{match &mut self{Self::SourceFailure(message)|Self::SourceWarning(message)=>{if message.site.is_none(){message.site=Some(key)}},_=>()}self}
 pub fn failure_using(message:&str,a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self::SourceFailure(ModelMessage{value:copy_text(message,a)?,site:None}))}
 pub fn warning_using(message:&str,a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self::SourceWarning(ModelMessage{value:copy_text(message,a)?,site:None}))}
}
struct Inputs<'a>{macros:&'a dyn MacroLookup,model:Option<&'a dyn ModelContext>,hint:Option<&'a str>}
impl Inputs<'_>{fn contains_key(&self,name:&str)->bool{self.macros.contains_key(name)}fn no_hint(&self)->Inputs<'_>{Inputs{macros:self.macros,model:self.model,hint:None}}}
macro_rules! model_value{($call:expr)=>{match $call?{ModelOutcome::Value(value)=>value.value,ModelOutcome::SourceFailure(message)=>return Ok(Evaluated::SourceFailure(message.into())),ModelOutcome::SourceWarning(message)=>return Ok(Evaluated::SourceWarning(message.into())),ModelOutcome::Unissued(reason)=>return Ok(Evaluated::Unissued(reason))}}}

enum Value<'s>{Number(ConditionNumber),Null(Option<TextBuffer>),String(Text<'s>),Resource(Text<'s>),Prefab(Text<'s>),Compound{display:TextBuffer,equality:TextBuffer,debug:Option<TextBuffer>,prefab:Option<TextBuffer>}}
enum Evaluated<'s>{Value(Value<'s>),SourceFailure(ModelMessage),SourceWarning(ModelMessage),Unissued(&'static str)}
macro_rules! value{($expr:expr)=>{match $expr?{Evaluated::Value(value)=>value,Evaluated::SourceFailure(message)=>return Ok(Evaluated::SourceFailure(message.into())),Evaluated::SourceWarning(message)=>return Ok(Evaluated::SourceWarning(message.into())),Evaluated::Unissued(reason)=>return Ok(Evaluated::Unissued(reason))}}}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|error|a.take_operational_error().unwrap_or(error))}
fn failure<'s>(message:&str,a:&SettingAdmission<'_>)->io::Result<Evaluated<'s>>{let mut text=TextBuffer::new(a)?;text.push_str(message,a)?;Ok(Evaluated::SourceFailure(text.into()))}
impl Value<'_>{
 fn truth(&self)->bool{match self{Self::Number(n)=>n.truth(),Self::Null(_)=>false,Self::String(s)=>!s.get().is_empty(),Self::Resource(_)|Self::Prefab(_)|Self::Compound{..}=>true}}
 fn equal(&self,rhs:&Self)->bool{match(self,rhs){(Self::Null(a),Self::Null(b))=>a.as_ref().map(TextBuffer::as_str)==b.as_ref().map(TextBuffer::as_str),(Self::Number(ConditionNumber::Original(a)),Self::Number(ConditionNumber::Original(b)))=>a==b||(a.is_nan()&&b.is_nan()),(Self::String(a),Self::String(b))=>a.get()==b.get(),(Self::Resource(a),Self::Resource(b))=>a.get()==b.get(),(Self::Prefab(a),Self::Prefab(b))=>a.get()==b.get(),(Self::Compound{equality:a,..},Self::Compound{equality:b,..})=>a.as_str()==b.as_str(),_=>false}}
 fn display(&self,out:&mut TextBuffer,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;match self{
  Self::Number(ConditionNumber::Original(n))=>original_format_using(out,a,|out|dm_syntax::numeric_form::write_original_float(*n,out)),
  Self::Number(ConditionNumber::Null)|Self::Null(_)=>out.push_str("null",a),
  Self::Number(ConditionNumber::Native(_))=>Err(io::Error::new(io::ErrorKind::InvalidData,"native integer reached Original conditional judge")),
  Self::String(value)=>{let(open,close)=crate::macro_expansion::original_quote_delimiters(value.get());out.push_str(open,a)?;out.push_str(value.get(),a)?;out.push_str(close,a)},
  Self::Resource(value)=>{out.push('\'',a)?;out.push_str(value.get(),a)?;out.push('\'',a)},
  Self::Prefab(path)=>out.push_str(path.get(),a),
  Self::Compound{display,..}=>out.push_str(display.as_str(),a),
 }}
}
// Injective typed folded VALUE key, not source spelling or parser authority.
// Children remain funded through the parent's funded copy, then retire. The
// retained two flat buffers need no recursive owner destruction or cloned AST.
fn equality_key(value:&Value<'_>,out:&mut TextBuffer,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;match value{
 Value::Number(ConditionNumber::Original(number))=>{let bits=if number.is_nan(){f32::NAN.to_bits()}else if *number==0.0{0}else{number.to_bits()};original_format_using(out,a,|out|{use std::fmt::Write;write!(out,"N{bits:08x};")})},
 Value::Number(ConditionNumber::Null)|Value::Null(None)=>out.push_str("Z;",a),Value::Null(Some(path))=>typed_key("ZP",path.as_str(),out,a),Value::Number(ConditionNumber::Native(_))=>Err(io::ErrorKind::InvalidData.into()),
 Value::String(value)=>typed_key("S",value.get(),out,a),Value::Resource(value)=>typed_key("R",value.get(),out,a),Value::Prefab(value)=>typed_key("P",value.get(),out,a),Value::Compound{equality,..}=>typed_key("V",equality.as_str(),out,a),
}}
fn typed_key(tag:&str,text:&str,out:&mut TextBuffer,a:&SettingAdmission<'_>)->io::Result<()>{original_format_using(out,a,|out|{use std::fmt::Write;write!(out,"{tag}{}:",text.len())})?;out.push_str(text,a)}

struct CompoundParts{display:TextBuffer,equality:TextBuffer,debug:Option<TextBuffer>,list:bool,previous_assoc:bool,index:usize}
impl CompoundParts{
 fn new(name:&str,count:usize,model:bool,a:&SettingAdmission<'_>)->io::Result<Self>{let list=name=="list";let mut display=TextBuffer::new(a)?;let mut equality=TextBuffer::new(a)?;display.push_str(name,a)?;display.push('(',a)?;typed_key(if list{"L"}else{"C"},name,&mut equality,a)?;original_format_using(&mut equality,a,|out|{use std::fmt::Write;write!(out,"{count};")})?;let mut debug=if model{Some(TextBuffer::new(a)?)}else{None};if let Some(out)=debug.as_mut(){match name{"new"=>out.push('[',a)?,"list"=>out.push_str("List([",a)?,_=>{let kind=match name{"icon"=>"Icon","matrix"=>"Matrix","newlist"=>"Newlist","sound"=>"Sound","filter"=>"Filter","file"=>"File","generator"=>"Generator",_=>return Err(io::ErrorKind::InvalidData.into())};out.push_str("Call(",a)?;out.push_str(kind,a)?;out.push_str(", [",a)?;}}}Ok(Self{display,equality,debug,list,previous_assoc:false,index:0})}
 fn begin(&mut self,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;if self.index!=0{self.display.push(',',a)?;if !self.list||self.previous_assoc{self.display.push(' ',a)?}}Ok(())}
 fn key(&mut self,key:&Value<'_>,a:&SettingAdmission<'_>)->io::Result<()>{key.display(&mut self.display,a)?;equality_key(key,&mut self.equality,a)?;if let Some(out)=self.debug.as_mut(){if self.index!=0{out.push_str(", ",a)?}out.push('(',a)?;key.write_debug_using(out,a)?;}Ok(())}
 fn mark_association(&mut self,associated:bool,a:&SettingAdmission<'_>)->io::Result<()>{self.previous_assoc=associated;self.equality.push_str(if associated{"A"}else{"O"},a)}
 fn association(&mut self,value:Option<&Value<'_>>,a:&SettingAdmission<'_>)->io::Result<()>{if let Some(value)=value{self.display.push_str(" = ",a)?;value.display(&mut self.display,a)?;equality_key(value,&mut self.equality,a)?;if let Some(out)=self.debug.as_mut(){out.push_str(", Some(",a)?;value.write_debug_using(out,a)?;out.push_str("))",a)?;}}else{if let Some(out)=self.debug.as_mut(){out.push_str(", None)",a)?}}self.index+=1;Ok(())}
 fn finish<'s>(mut self,new:bool,a:&SettingAdmission<'_>)->io::Result<Value<'s>>{self.display.push(')',a)?;if let Some(out)=self.debug.as_mut(){out.push_str(if new{"]"}else{"])"},a)?;}Ok(Value::Compound{display:self.display,equality:self.equality,debug:self.debug,prefab:None})}
}
fn compound_argument<'s>(out:&mut CompoundParts,arg:&'s Expr,macros:&Inputs<'_>,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>,debug:&mut Option<&mut dyn FnMut(&Expr,&mut TextBuffer)->io::Result<super::original_condition_tokens::DebugSupport>>)->io::Result<Option<Evaluated<'s>>>{
 out.begin(a)?;let(key,associated)=if let ExprKind::Binary{op,lhs,rhs}=&arg.kind{if op=="="{(lhs.as_ref(),Some(rhs.as_ref()))}else{(arg,None)}}else{(arg,None)};
 let key=if associated.is_some(){if let ExprKind::Ident(name)=&key.kind{Value::String(Text::Borrowed(name))}else{match evaluate_inner(key,&macros.no_hint(),a,file_exists,constructors,debug)?{Evaluated::Value(value)=>value,other=>return Ok(Some(other))}}}else{match evaluate_inner(key,&macros.no_hint(),a,file_exists,constructors,debug)?{Evaluated::Value(value)=>value,other=>return Ok(Some(other))}};
 out.key(&key,a)?;drop(key);out.mark_association(associated.is_some(),a)?;if let Some(associated)=associated{let value=match evaluate_inner(associated,&macros.no_hint(),a,file_exists,constructors,debug)?{Evaluated::Value(value)=>value,other=>return Ok(Some(other))};out.association(Some(&value),a)?;}else{out.association(None,a)?}Ok(None)
}
fn compound<'s>(name:&str,args:&'s [Expr],macros:&Inputs<'_>,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>,debug:&mut Option<&mut dyn FnMut(&Expr,&mut TextBuffer)->io::Result<super::original_condition_tokens::DebugSupport>>)->io::Result<Evaluated<'s>>{
 let mut out=CompoundParts::new(name,args.len(),macros.model.is_some(),a)?;for arg in args{if let Some(outcome)=compound_argument(&mut out,arg,macros,a,file_exists,constructors,debug)?{return Ok(outcome)}}Ok(Evaluated::Value(out.finish(name=="new",a)?))
}

fn copy_text(text:&str,a:&SettingAdmission<'_>)->io::Result<TextBuffer>{let pending=(||{poll(a)?;let mut out=TextBuffer::new(a)?;out.push_str(text,a)?;Ok(out)})();match a.take_operational_error(){Some(first)=>Err(first),None=>pending}}
fn owned_text(text:Text<'_>,a:&SettingAdmission<'_>)->io::Result<Text<'static>>{match text{Text::Owned(value)=>Ok(Text::Owned(value)),other=>Ok(Text::Owned(copy_text(other.get(),a)?))}}
impl Value<'_>{
 fn into_owned_using(self,a:&SettingAdmission<'_>)->io::Result<Value<'static>>{poll(a)?;Ok(match self{Self::Number(v)=>Value::Number(v),Self::Null(v)=>Value::Null(v),Self::String(v)=>Value::String(owned_text(v,a)?),Self::Resource(v)=>Value::Resource(owned_text(v,a)?),Self::Prefab(v)=>Value::Prefab(owned_text(v,a)?),Self::Compound{display,equality,debug,prefab}=>Value::Compound{display,equality,debug,prefab}})}
 fn duplicate_using(&self,a:&SettingAdmission<'_>)->io::Result<Value<'static>>{poll(a)?;Ok(match self{Self::Number(v)=>Value::Number(*v),Self::Null(v)=>Value::Null(v.as_ref().map(|v|copy_text(v.as_str(),a)).transpose()?),Self::String(v)=>Value::String(Text::Owned(copy_text(v.get(),a)?)),Self::Resource(v)=>Value::Resource(Text::Owned(copy_text(v.get(),a)?)),Self::Prefab(v)=>Value::Prefab(Text::Owned(copy_text(v.get(),a)?)),Self::Compound{display,equality,debug,prefab}=>Value::Compound{display:copy_text(display.as_str(),a)?,equality:copy_text(equality.as_str(),a)?,debug:debug.as_ref().map(|v|copy_text(v.as_str(),a)).transpose()?,prefab:prefab.as_ref().map(|v|copy_text(v.as_str(),a)).transpose()?}})}
}
impl ModelValue{
 pub fn prefab_format_using(path:std::fmt::Arguments<'_>,a:&SettingAdmission<'_>)->io::Result<Self>{let pending=(||{let mut text=TextBuffer::new(a)?;original_format_using(&mut text,a,|out|{use std::fmt::Write;out.write_fmt(path)})?;Ok(Self{value:Value::Prefab(Text::Owned(text))})})();match a.take_operational_error(){Some(first)=>Err(first),None=>pending}}
 pub fn number_using(number:f32,a:&SettingAdmission<'_>)->io::Result<Self>{poll(a)?;Ok(Self{value:Value::Number(ConditionNumber::Original(number))})}
 pub fn string_using(text:&str,a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{value:Value::String(Text::Owned(copy_text(text,a)?))})}

 pub fn duplicate_using(&self,a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{value:self.value.duplicate_using(a)?})}
 pub fn null_using(hint:Option<&str>,a:&SettingAdmission<'_>)->io::Result<Self>{poll(a)?;Ok(Self{value:Value::Null(hint.map(|path|copy_text(path,a)).transpose()?)})}
 pub fn prefab_using(path:&str,a:&SettingAdmission<'_>)->io::Result<Self>{Ok(Self{value:Value::Prefab(Text::Owned(copy_text(path,a)?))})}
}


fn debug_path(path:&str,out:&mut TextBuffer,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;out.push('[',a)?;let mut first=true;for part in path.split('/').filter(|part|!part.is_empty()){poll(a)?;if !first{out.push_str(", ",a)?}first=false;original_format_using(out,a,|out|{use std::fmt::Write;write!(out,"{part:?}")})?;}out.push(']',a)}
impl Value<'_>{
 fn write_debug_using(&self,out:&mut TextBuffer,a:&SettingAdmission<'_>)->io::Result<()>{poll(a)?;match self{
  Self::Null(None)|Self::Number(ConditionNumber::Null)=>out.push_str("Null(None)",a),
  Self::Null(Some(path))=>{out.push_str("Null(Some(",a)?;debug_path(path.as_str(),out,a)?;out.push_str("))",a)},
  Self::Number(ConditionNumber::Original(number))=>original_format_using(out,a,|out|{use std::fmt::Write;write!(out,"Float({number:?})")}),
  Self::Number(ConditionNumber::Native(_))=>Err(io::ErrorKind::InvalidData.into()),
  Self::String(text)=>original_format_using(out,a,|out|{use std::fmt::Write;write!(out,"String({:?})",text.get())}),
  Self::Resource(text)=>original_format_using(out,a,|out|{use std::fmt::Write;write!(out,"Resource({:?})",text.get())}),
  Self::Prefab(path)=>{out.push_str("Prefab(",a)?;self.write_pop_debug_using(out,a)?;out.push(')',a)},
  Self::Compound{debug:Some(text),..}=>out.push_str(text.as_str(),a),
  Self::Compound{debug:None,..}=>Err(io::Error::new(io::ErrorKind::Unsupported,"actual folded utility Debug value is unissued")),
 }}
 fn write_pop_debug_using(&self,out:&mut TextBuffer,a:&SettingAdmission<'_>)->io::Result<()>{match self{
  Self::Prefab(path)=>{out.push_str("Pop { path: ",a)?;debug_path(path.get(),out,a)?;out.push_str(", vars: {} }",a)},
  Self::Compound{debug:Some(text),prefab:Some(_),..}=>out.push_str(text.as_str().strip_prefix("Prefab(").and_then(|s|s.strip_suffix(')')).ok_or(io::ErrorKind::InvalidData)?,a),
  _=>Err(io::Error::new(io::ErrorKind::Unsupported,"actual new target has no typed prefab value")),
 }}
}
impl ModelValue{
 pub fn debug_using(&self,a:&SettingAdmission<'_>)->io::Result<ModelMessage>{let pending=(||{let mut value=TextBuffer::new(a)?;self.value.write_debug_using(&mut value,a)?;Ok(ModelMessage{value,site:None})})();match a.take_operational_error(){Some(first)=>Err(first),None=>pending}}
}

fn int(value:&Value<'_>)->Option<i32>{match value{Value::Number(ConditionNumber::Original(number))=>Some(*number as i32),_=>None}}
fn string<'a>(value:&'a Value<'_>)->Option<&'a str>{match value{Value::String(value)=>Some(value.get()),_=>None}}
// SAME pinned rgb algorithm and color_space0.5.4, bounded to five actual args.
// Stack tuple slots retain their actual independently funded folded children.
fn rgb<'s>(args:&'s [Expr],macros:&Inputs<'_>,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>,debug:&mut Option<&mut dyn FnMut(&Expr,&mut TextBuffer)->io::Result<super::original_condition_tokens::DebugSupport>>)->io::Result<Evaluated<'s>>{
 use color_space::{Rgb,Hsv,Hsl,Lch};
 if !matches!(args.len(),3..=5){let mut m=TextBuffer::new(a)?;original_format_using(&mut m,a,|out|{use std::fmt::Write;write!(out,"malformed rgb() call, must have 3, 4, or 5 arguments and instead has {}",args.len())})?;return Ok(Evaluated::SourceFailure(m.into()))}
 let mut arguments:[Option<(Value<'s>,Option<Value<'s>>)>;5]=std::array::from_fn(|_|None);
 for(index,arg)in args.iter().enumerate(){poll(a)?;let(key,association)=if let ExprKind::Binary{op,lhs,rhs}=&arg.kind{if op=="="{(lhs.as_ref(),Some(rhs.as_ref()))}else{(arg,None)}}else{(arg,None)};let key=if association.is_some(){if let ExprKind::Ident(name)=&key.kind{Value::String(Text::Borrowed(name))}else{value!(evaluate_inner(key,&macros.no_hint(),a,file_exists,constructors,debug))}}else{value!(evaluate_inner(key,&macros.no_hint(),a,file_exists,constructors,debug))};let association=match association{Some(v)=>Some(value!(evaluate_inner(v,macros,a,file_exists,constructors,debug))),None=>None};arguments[index]=Some((key,association));}
 let(mut has_rgb,mut h,mut sat,mut v,mut l,mut c,mut y)=(false,false,false,false,false,false,false);let mut alpha=None;let mut space=None;
 for(key,association)in arguments[..args.len()].iter().map(|v|v.as_ref().unwrap()){poll(a)?;let Some(associated)=association else{continue};let Some(key_string)=string(key)else{let mut m=TextBuffer::new(a)?;m.push_str("malformed rgb() call, kwarg is not string: ",a)?;key.display(&mut m,a)?;return Ok(Evaluated::SourceFailure(m.into()))};match key_string{
 "r"|"red"|"g"|"green"|"b"|"blue"=>has_rgb=true,"h"|"hue"=>h=true,"s"|"saturation"=>sat=true,"v"|"value"=>v=true,"l"|"luminance"=>l=true,"c"|"chroma"=>c=true,"y"=>y=true,"a"|"alpha"=>alpha=int(associated),
 "space"=>match int(associated){Some(n @ 0..=3)=>space=Some(n),_=>{let mut m=TextBuffer::new(a)?;m.push_str("malformed rgb() call, bad color space: ",a)?;associated.display(&mut m,a)?;return Ok(Evaluated::SourceFailure(m.into()))}},
 _=>{let mut m=TextBuffer::new(a)?;m.push_str("malformed rgb() call, bad kwarg passed: ",a)?;m.push_str(key_string,a)?;return Ok(Evaluated::SourceFailure(m.into()))}
 }}
 let space=if let Some(space)=space{space}else if has_rgb{0}else if h{if c&&y{3}else if sat{if v{1}else if l{2}else{return failure("malformed rgb() call, could not determine space: only h & s specified",a)}}else{return failure("malformed rgb() call, could not determine space: only h specified",a)}}else{0};
 let mut values=[0f64;5];let mut count=0;
 for(index,(key,association))in arguments[..args.len()].iter().map(|v|v.as_ref().unwrap()).enumerate(){poll(a)?;let mut range=if index==0{if space==0{0..=255}else{0..=360}}else if index<3{if space==0{0..=255}else{0..=100}}else{0..=255};let check=if let Some(associated)=association{let key=string(key).ok_or(io::ErrorKind::InvalidData)?;range=match key{"r"|"red"|"g"|"green"|"b"|"blue"=>0..=255,"h"|"hue"=>0..=360,"s"|"saturation"|"v"|"value"|"c"|"chroma"|"l"|"y"|"luminance"=>0..=100,"a"|"alpha"=>0..=255,"space"=>continue,_=>return Err(io::ErrorKind::InvalidData.into())};associated}else{key};
 let Some(number)=int(check)else{return failure("malformed rgb() call, value wasn't an int",a)};if !range.contains(&number){let mut m=TextBuffer::new(a)?;original_format_using(&mut m,a,|out|{use std::fmt::Write;write!(out,"malformed rgb() call, {} is not within the valid range ({}..{})",number,range.start(),range.end())})?;return Ok(Evaluated::SourceWarning(m.into()))}values[count]=number.clamp(*range.start(),*range.end())as f64;count+=1;
 }
 // Pinned asserts/panics here for duplicate space arguments leaving <3 values;
 // no successful VALUE or false source result is invented for that old panic.
 if count<3{return Ok(Evaluated::Unissued("pinned rgb() panics after fewer than three non-space arguments"))}
 let color:Rgb=match space{0=>Rgb::new(values[0],values[1],values[2]),1=>Hsv::new(values[0],values[1]*0.01,values[2]*0.01).into(),2=>Hsl::new(values[0],values[1]*0.01,values[2]*0.01).into(),3=>Lch::new(values[2],values[1],values[0]).into(),_=>return Err(io::ErrorKind::InvalidData.into())};let alpha=alpha.or_else(||(count>3).then_some(values[3]as i32));let mut text=TextBuffer::new(a)?;original_format_using(&mut text,a,|out|{use std::fmt::Write;if let Some(alpha)=alpha{write!(out,"#{:02x}{:02x}{:02x}{:02x}",color.r.round()as u8,color.g.round()as u8,color.b.round()as u8,alpha)}else{write!(out,"#{:02x}{:02x}{:02x}",color.r.round()as u8,color.g.round()as u8,color.b.round()as u8)}})?;Ok(Evaluated::Value(Value::String(Text::Owned(text))))
}
fn absolute_prefab(path:&str)->bool{path.starts_with('/')&&!path.contains(['.',':'])}
fn prefab_fields<'s>(object:&'s Expr,fields:&'s [(String,Expr)],macros:&Inputs<'_>,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>,debug:&mut Option<&mut dyn FnMut(&Expr,&mut TextBuffer)->io::Result<super::original_condition_tokens::DebugSupport>>)->io::Result<Evaluated<'s>>{
 let ExprKind::TypePath(path)=&object.kind else{return Ok(Evaluated::Unissued("Original prefab fields lack actual native TypePath target"))};let mut values:Rows<(&str,Value<'s>)>=Rows::new(a)?;
 // Pinned prefab folds every initializer in encounter order before resolving
 // its path. Duplicate fields replace their value without moving first position.
 for(name,expression)in fields{poll(a)?;let value=value!(evaluate_inner(expression,&macros.no_hint(),a,file_exists,constructors,debug));let mut existing=None;for(index,(prior,_))in values.as_slice().iter().enumerate(){poll(a)?;if *prior==name.as_str(){existing=Some(index);break}}if let Some(index)=existing{values.as_mut_slice()[index].1=value}else{values.push((name.as_str(),value),a)?;}}
 let mut resolved:Option<Text<'s>>=None;
 if !absolute_prefab(path){if let Some(model)=macros.model{let actual=model_value!(model.resolve_prefab(path,a));let Value::Prefab(text)=actual else{return Ok(Evaluated::Unissued("model prefab resolver returned another VALUE kind"))};resolved=Some(text);}else{let mut message=TextBuffer::new(a)?;message.push_str("cannot resolve relative type path without an object tree: ",a)?;message.push_str(path,a)?;return Ok(Evaluated::SourceFailure(message.into()))}}
 if values.len()==0{return Ok(Evaluated::Value(Value::Prefab(resolved.unwrap_or(Text::Borrowed(path)))))}
 let path=resolved.as_ref().map(Text::get).unwrap_or(path);
 let mut display=TextBuffer::new(a)?;let mut equality=TextBuffer::new(a)?;display.push_str(path,a)?;for(index,(name,value))in values.as_slice().iter().enumerate(){poll(a)?;display.push_str(if index==0{" {"}else{"; "},a)?;display.push_str(name,a)?;display.push_str(" = ",a)?;value.display(&mut display,a)?;}display.push('}',a)?;
 // IndexMap equality ignores insertion order. Canonicalize names using a
 // bounded scanned selection over the existing funded map, never a shadow map.
 typed_key("P",path,&mut equality,a)?;original_format_using(&mut equality,a,|out|{use std::fmt::Write;write!(out,"{};",values.len())})?;let mut previous:Option<&str>=None;for _ in 0..values.len(){let mut chosen:Option<(&str,&Value<'s>)>=None;for(name,value)in values.as_slice(){poll(a)?;if previous.is_none_or(|previous|*name>previous)&&chosen.is_none_or(|(chosen,_)|*name<chosen){chosen=Some((*name,value))}}let(name,value)=chosen.ok_or(io::ErrorKind::InvalidData)?;typed_key("F",name,&mut equality,a)?;equality_key(value,&mut equality,a)?;previous=Some(name);}
 let mut value_debug=if macros.model.is_some(){Some(TextBuffer::new(a)?)}else{None};
 if let Some(out)=value_debug.as_mut(){out.push_str("Prefab(Pop { path: ",a)?;debug_path(path,out,a)?;out.push_str(", vars: {",a)?;for(index,(name,value))in values.as_slice().iter().enumerate(){poll(a)?;if index!=0{out.push_str(", ",a)?;}original_format_using(out,a,|out|{use std::fmt::Write;write!(out,"{name:?}: ")})?;value.write_debug_using(out,a)?;}out.push_str("} })",a)?;}
 let prefab=if macros.model.is_some(){Some(copy_text(path,a)?)}else{None};
 Ok(Evaluated::Value(Value::Compound{display,equality,debug:value_debug,prefab}))
}

struct ConstructorParts{display:TextBuffer,equality:TextBuffer,debug:Option<TextBuffer>}
impl ConstructorParts{
 fn new(model:bool,a:&SettingAdmission<'_>)->io::Result<Self>{let mut display=TextBuffer::new(a)?;let mut equality=TextBuffer::new(a)?;display.push_str("new",a)?;equality.push_str("J",a)?;let debug=if model{let mut text=TextBuffer::new(a)?;text.push_str("New { type_: ",a)?;Some(text)}else{None};Ok(Self{display,equality,debug})}
 fn target(&mut self,target:Option<&Value<'_>>,a:&SettingAdmission<'_>)->io::Result<()>{if let Some(target)=target{self.display.push(' ',a)?;target.display(&mut self.display,a)?;if let Some(out)=self.debug.as_mut(){out.push_str("Some(",a)?;target.write_pop_debug_using(out,a)?;out.push(')',a)?;}self.equality.push_str("T",a)?;equality_key(target,&mut self.equality,a)?;}else{self.equality.push_str("O",a)?;if let Some(out)=self.debug.as_mut(){out.push_str("None",a)?;}}Ok(())}
 fn args(&mut self,args:Option<Value<'_>>,a:&SettingAdmission<'_>)->io::Result<()>{if let Some(args)=args{let Value::Compound{display,equality,debug,..}=args else{return Err(io::ErrorKind::InvalidData.into())};self.display.push_str(display.as_str().strip_prefix("new").ok_or(io::ErrorKind::InvalidData)?,a)?;typed_key("A",equality.as_str(),&mut self.equality,a)?;if let Some(out)=self.debug.as_mut(){out.push_str(", args: Some(",a)?;out.push_str(debug.as_ref().ok_or(io::ErrorKind::InvalidData)?.as_str(),a)?;out.push(')',a)?;}}else{self.equality.push_str("O",a)?;if let Some(out)=self.debug.as_mut(){out.push_str(", args: None",a)?;}}Ok(())}
 fn finish<'s>(mut self,a:&SettingAdmission<'_>)->io::Result<Value<'s>>{if let Some(out)=self.debug.as_mut(){out.push_str(" }",a)?;}Ok(Value::Compound{display:self.display,equality:self.equality,debug:self.debug,prefab:None})}
}
fn new_value<'s>(target:Option<&'s Expr>,args:Option<&'s [Expr]>,macros:&Inputs<'_>,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>,debug:&mut Option<&mut dyn FnMut(&Expr,&mut TextBuffer)->io::Result<super::original_condition_tokens::DebugSupport>>)->io::Result<Evaluated<'s>>{
 let mut out=ConstructorParts::new(macros.model.is_some(),a)?;if let Some(target)=target{let target=value!(evaluate_inner(target,&macros.no_hint(),a,file_exists,constructors,debug));out.target(Some(&target),a)?;}else{out.target(None,a)?;}
 if let Some(args)=args{let args=value!(compound("new",args,macros,a,file_exists,constructors,debug));out.args(Some(args),a)?;}else{out.args(None,a)?;}Ok(Evaluated::Value(out.finish(a)?))
}
/// Actual VarSuffix::into_initializer VALUE derivation. Its caller supplies only
/// the original present dimension roots; no synthesized expression/AST exists.
pub struct ModelArrayBuilder{constructor:ConstructorParts,args:CompoundParts,count:usize}
impl ModelArrayBuilder{
 pub fn new(count:usize,a:&SettingAdmission<'_>)->io::Result<Self>{let pending=(||{let mut constructor=ConstructorParts::new(true,a)?;constructor.target(Some(&Value::Prefab(Text::Borrowed("/list"))),a)?;let args=CompoundParts::new("new",count,true,a)?;Ok(Self{constructor,args,count})})();match a.take_operational_error(){Some(first)=>Err(first),None=>pending}}
 pub fn push_using(&mut self,expr:&Expr,model:&dyn ModelContext,a:&SettingAdmission<'_>,constructors:&dm_syntax::OriginalConstructorFacts,debug:&mut dyn FnMut(&Expr)->io::Result<crate::original_expression_debug::Formatted>)->io::Result<Option<ModelOutcome>>{
  struct NoMacros;impl MacroLookup for NoMacros{fn initial_environment(&self)->crate::InitialEnvironment{crate::InitialEnvironment::OriginalChecker0290}fn get_key_value(&self,_:&str)->Option<(&str,&crate::Macro)>{None}}
  let pending=(||{if self.args.index>=self.count||!constructors.is_admitted_by(a){return Err(io::ErrorKind::InvalidInput.into())}let inputs=Inputs{macros:&NoMacros,model:Some(model),hint:None};let mut files=None;let mut writer=|expr:&Expr,out:&mut TextBuffer|{let actual=debug(expr)?;out.push_str(actual.as_str(),a)?;Ok(actual.support())};let mut writer=Some(&mut writer as &mut dyn FnMut(&Expr,&mut TextBuffer)->io::Result<crate::original_expression_debug::DebugSupport>);Ok(match compound_argument(&mut self.args,expr,&inputs,a,&mut files,Some(constructors),&mut writer)?{None=>None,Some(Evaluated::Value(_))=>return Err(io::ErrorKind::InvalidData.into()),Some(Evaluated::SourceFailure(message))=>Some(ModelOutcome::SourceFailure(message)),Some(Evaluated::SourceWarning(message))=>Some(ModelOutcome::SourceWarning(message)),Some(Evaluated::Unissued(reason))=>Some(ModelOutcome::Unissued(reason))})})();match a.take_operational_error(){Some(first)=>Err(first),None=>pending}
 }
 pub fn finish(mut self,a:&SettingAdmission<'_>)->io::Result<ModelValue>{let pending=(||{if self.args.index!=self.count{return Err(io::ErrorKind::InvalidInput.into())}let args=self.args.finish(true,a)?;self.constructor.args(Some(args),a)?;Ok(ModelValue{value:self.constructor.finish(a)?})})();match a.take_operational_error(){Some(first)=>Err(first),None=>pending}}
}

fn flag(value:bool)->Value<'static>{Value::Number(ConditionNumber::flag(value,true))}
/// The caller attaches SourceFailure to the SAVED actual condition start,
/// exactly as preprocessor_evaluate(start,...); not its later read point.
pub(crate) fn evaluate(expr:&Expr,macros:&dyn MacroLookup,a:&SettingAdmission<'_>)->io::Result<Outcome>{evaluate_with_file_exists_using(expr,macros,a,None)}
pub(crate) fn evaluate_with_file_exists_using(expr:&Expr,macros:&dyn MacroLookup,a:&SettingAdmission<'_>,file_exists:Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>)->io::Result<Outcome>{evaluate_with_native_facts_using(expr,macros,a,file_exists,None)}
pub(crate) fn evaluate_with_native_facts_using(expr:&Expr,macros:&dyn MacroLookup,a:&SettingAdmission<'_>,file_exists:Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>)->io::Result<Outcome>{evaluate_with_debug_inputs_using(expr,macros,a,file_exists,constructors,None)}
pub(crate) fn evaluate_with_debug_inputs_using(expr:&Expr,macros:&dyn MacroLookup,a:&SettingAdmission<'_>,mut file_exists:Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>,mut debug:Option<&mut dyn FnMut(&Expr,&mut TextBuffer)->io::Result<super::original_condition_tokens::DebugSupport>>)->io::Result<Outcome>{
 if constructors.is_some_and(|facts|!facts.is_admitted_by(a)){return Err(io::ErrorKind::InvalidInput.into())}

 poll(a)?;if macros.initial_environment()!=crate::InitialEnvironment::OriginalChecker0290{return Err(io::Error::new(io::ErrorKind::InvalidInput,"Original condition requires actual Original macro environment"))}
 let inputs=Inputs{macros,model:None,hint:None};
 Ok(match evaluate_inner(expr,&inputs,a,&mut file_exists,constructors,&mut debug)?{Evaluated::Value(value)=>Outcome::Value(value.truth()),Evaluated::SourceFailure(message)=>Outcome::SourceFailure(message.value),Evaluated::SourceWarning(message)=>Outcome::SourceWarning(message.value),Evaluated::Unissued(reason)=>Outcome::Unissued(reason)})
}

/// Canonical already-parsed initializer VALUE through the SAME Original kernel.
/// Constructor facts and literal VALUE must be supplied by the actual bound root.
pub fn evaluate_model_using(expr:&Expr,model:&dyn ModelContext,a:&SettingAdmission<'_>,constructors:Option<&dm_syntax::OriginalConstructorFacts>,mut debug:Option<&mut dyn FnMut(&Expr)->io::Result<crate::original_expression_debug::Formatted>>)->io::Result<ModelOutcome>{
 struct NoMacros;impl MacroLookup for NoMacros{fn initial_environment(&self)->crate::InitialEnvironment{crate::InitialEnvironment::OriginalChecker0290}fn get_key_value(&self,_:&str)->Option<(&str,&crate::Macro)>{None}}
 let pending=(||{
 if constructors.is_some_and(|facts|!facts.is_admitted_by(a)){return Err(io::ErrorKind::InvalidInput.into())}
 let inputs=Inputs{macros:&NoMacros,model:Some(model),hint:model.type_hint()};let mut no_files=None;
 let has_debug=debug.is_some();let pending={let mut write_debug=|expression:&Expr,out:&mut TextBuffer|->io::Result<crate::original_expression_debug::DebugSupport>{let actual=debug.as_deref_mut().ok_or(io::ErrorKind::Unsupported)?(expression)?;out.push_str(actual.as_str(),a)?;Ok(actual.support())};let mut actual_debug=if has_debug{Some(&mut write_debug as &mut dyn FnMut(&Expr,&mut TextBuffer)->io::Result<crate::original_expression_debug::DebugSupport>)}else{None};evaluate_inner(expr,&inputs,a,&mut no_files,constructors,&mut actual_debug)};
 match pending?{Evaluated::Value(value)=>Ok(ModelOutcome::Value(ModelValue{value:value.into_owned_using(a)?})),Evaluated::SourceFailure(message)=>Ok(ModelOutcome::SourceFailure(message)),Evaluated::SourceWarning(message)=>Ok(ModelOutcome::SourceWarning(message)),Evaluated::Unissued(reason)=>Ok(ModelOutcome::Unissued(reason))}
 })();match a.take_operational_error(){Some(first)=>Err(first),None=>pending}
}

fn evaluate_inner<'s>(expr:&'s Expr,macros:&Inputs<'_>,a:&SettingAdmission<'_>,file_exists:&mut Option<&mut dyn FnMut(&str)->io::Result<FileExistsResult>>,constructors:Option<&dm_syntax::OriginalConstructorFacts>,debug:&mut Option<&mut dyn FnMut(&Expr,&mut TextBuffer)->io::Result<super::original_condition_tokens::DebugSupport>>)->io::Result<Evaluated<'s>>{
 let _frame=a.evaluation_frame().map_err(|error|a.take_operational_error().unwrap_or(error))?;
 let value=match &expr.kind{
  ExprKind::Literal(literal)if literal.original_template_lexical_shape().is_some_and(|shape|shape.interpolated)=>return failure("non-constant expression",a),
  ExprKind::Literal(literal)=>match literal.original_value(){
   Some(OriginalTokenValue::Int(n))=>Value::Number(ConditionNumber::Original(n as f32)),Some(OriginalTokenValue::Float(n))=>Value::Number(ConditionNumber::Original(n)),
   Some(OriginalTokenValue::String(s))=>Value::String(Text::Borrowed(s)),Some(OriginalTokenValue::Resource(s))=>Value::Resource(Text::Borrowed(s)),
   Some(_)=>return Ok(Evaluated::Unissued("Original condition literal has no scalar constant product")),
   None if literal.as_str()=="null"=>Value::Null(match macros.hint{Some(path)=>Some(copy_text(path,a)?),None=>None}),
   None=>return Ok(Evaluated::Unissued("Original condition literal lacks authentic typed value")),
  },
  ExprKind::ObjectInitializer{object,fields}=>return prefab_fields(object,fields,macros,a,file_exists,constructors,debug),
  ExprKind::Ident(name)=>match name.as_str(){
   "null"=>Value::Null(match macros.hint{Some(path)=>Some(copy_text(path,a)?),None=>None}),"type"|"parent_type"=>{if let Some(model)=macros.model{model_value!(model.type_value(name=="parent_type",a))}else{return failure("no type context",a)}},"__TYPE__"=>{if let Some(model)=macros.model{model_value!(model.type_value(false,a))}else{return failure("No type context",a)}},"__IMPLIED_TYPE__"=>{if let Some(path)=macros.hint{Value::Prefab(Text::Owned(copy_text(path,a)?))}else{return failure("No type hint",a)}},
   _=>{if let Some(model)=macros.model{model_value!(model.identifier(name,false,a))}else{let mut message=TextBuffer::new(a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out,"cannot reference variable {name:?} in this context")})?;return Ok(Evaluated::SourceFailure(message.into()))}}
  },
  ExprKind::TypePath(path)=>{if !absolute_prefab(path) {if let Some(model)=macros.model{model_value!(model.resolve_prefab(path,a))}else{let mut message=TextBuffer::new(a)?;message.push_str("cannot resolve relative type path without an object tree: ",a)?;message.push_str(path,a)?;return Ok(Evaluated::SourceFailure(message.into()))}}else{Value::Prefab(Text::Borrowed(path))}},
  ExprKind::Group(inner)=>value!(evaluate_inner(inner,macros,a,file_exists,constructors,debug)),
  // Native Original TypeFilter belongs to input() clause syntax.
  ExprKind::TypeFilter{value:inner,..}=>value!(evaluate_inner(inner,macros,a,file_exists,constructors,debug)),
  ExprKind::Conditional{condition,then_value,else_value}=>{let condition=value!(evaluate_inner(condition,&macros.no_hint(),a,file_exists,constructors,debug));value!(evaluate_inner(if condition.truth(){then_value}else{else_value},macros,a,file_exists,constructors,debug))},
  ExprKind::Unary{op,value:operand}=>{
   if op=="::"{return failure("non-constant expression",a)}
   if op=="new"{let(target,args)=match &operand.kind{ExprKind::Call{callee,args}if matches!(callee.kind,ExprKind::TypePath(_)|ExprKind::ObjectInitializer{..})=>(callee.as_ref(),Some(args.as_slice())),ExprKind::TypePath(_)|ExprKind::ObjectInitializer{..}=>(operand.as_ref(),None),_=>return failure("non-constant new expression",a)};return new_value(Some(target),args,macros,a,file_exists,constructors,debug)}

   if !matches!(op.as_str(),"!"|"-"|"~"|"&"|"*"|"pre++"|"pre--"|"post++"|"post--"){return Ok(Evaluated::Unissued("Original conditional unary grammar branch is not issued"))}
   let operand=value!(evaluate_inner(operand,&macros.no_hint(),a,file_exists,constructors,debug));
   if matches!(op.as_str(),"&"|"*"|"pre++"|"pre--"|"post++"|"post--"){let mut message=TextBuffer::new(a)?;message.push_str("non-constant unary operation: ",a)?;let(prefix,suffix)=match op.as_str(){"pre++"=>("++",""),"pre--"=>("--",""),"post++"=>("","++"),"post--"=>("","--"),"&"=>("&",""),"*"=>("*",""),_=>unreachable!()};message.push_str(prefix,a)?;operand.display(&mut message,a)?;message.push_str(suffix,a)?;return Ok(Evaluated::SourceFailure(message.into()))}

   if op=="!"{flag(!operand.truth())}else if let Value::Number(ConditionNumber::Original(number))=operand{Value::Number(ConditionNumber::Original(number).unary(op).map_err(|_|io::Error::new(io::ErrorKind::InvalidData,"accepted Original numeric unary operation refused"))?)}else{
    let mut message=TextBuffer::new(a)?;message.push_str("non-constant unary operation: ",a)?;message.push_str(op,a)?;operand.display(&mut message,a)?;return Ok(Evaluated::SourceFailure(message.into()))
   }
  },
  ExprKind::Binary{op,lhs,rhs}=>{
   if matches!(op.as_str(),"="|"+="|"-="|"*="|"/="|"%="|"%%="|"**="|"|="|"&="|"^="|"<<="|">>="|"&&="|"||="|":="){return failure("non-constant assignment",a)}
   if !matches!(op.as_str(),"+"|"-"|"*"|"/"|"%"|"%%"|"**"|"<"|"<="|">"|">="|"|"|"&"|"^"|"<<"|">>"|"=="|"!="|"&&"|"||"|"in"){return Ok(Evaluated::Unissued("Original conditional binary grammar branch is not issued"))}
   // The actual old folder evaluates BOTH operands before And/Or selection.
   let lhs=value!(evaluate_inner(lhs,&macros.no_hint(),a,file_exists,constructors,debug));let rhs=value!(evaluate_inner(rhs,&macros.no_hint(),a,file_exists,constructors,debug));
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
  ExprKind::Member{object,selector,via_colon}=>{let object=value!(evaluate_inner(object,&macros.no_hint(),a,file_exists,constructors,debug));let mut message=TextBuffer::new(a)?;message.push_str("non-constant expression follower: ",a)?;object.display(&mut message,a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out," Field({}, {selector:?})",if *via_colon{"Colon"}else{"Dot"})})?;return Ok(Evaluated::SourceFailure(message.into()))},
  ExprKind::Index{object,index}|ExprKind::SafeIndex{object,index}=>{let object=value!(evaluate_inner(object,&macros.no_hint(),a,file_exists,constructors,debug));let Some(write_debug)=debug.as_deref_mut()else{return Ok(Evaluated::Unissued("Original index follower requires actual source-owned Debug facts"))};let mut message=TextBuffer::new(a)?;message.push_str("non-constant expression follower: ",a)?;object.display(&mut message,a)?;message.push_str(if matches!(expr.kind,ExprKind::SafeIndex{..}){" Index(Safe, "}else{" Index(Normal, "},a)?;match write_debug(index,&mut message)?{super::original_condition_tokens::DebugSupport::Complete=>(),super::original_condition_tokens::DebugSupport::Unissued(reason)=>return Ok(Evaluated::Unissued(reason))}message.push(')',a)?;return Ok(Evaluated::SourceFailure(message.into()))},
  ExprKind::SafeMember{object,selector,via_colon}=>{let object=value!(evaluate_inner(object,&macros.no_hint(),a,file_exists,constructors,debug));let mut message=TextBuffer::new(a)?;message.push_str("non-constant expression follower: ",a)?;object.display(&mut message,a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out," Field({}, {selector:?})",if *via_colon{"SafeColon"}else{"SafeDot"})})?;return Ok(Evaluated::SourceFailure(message.into()))},
  ExprKind::StaticMember{object,selector}=>{let object=value!(evaluate_inner(object,&macros.no_hint(),a,file_exists,constructors,debug));let path=match &object{Value::Prefab(path)=>Some(path.get()),Value::Compound{prefab:Some(path),..}=>Some(path.as_str()),_=>None};if let Some(path)=path{if let Some(model)=macros.model{return Ok(Evaluated::Value(model_value!(model.static_member(path,selector,a))))}return failure("no type tree available",a)}let mut message=TextBuffer::new(a)?;message.push_str("non typepath ",a)?;object.display(&mut message,a)?;message.push_str(" used with ::",a)?;return Ok(Evaluated::SourceFailure(message.into()))},
  ExprKind::Call{callee,args}=>{
   if matches!(&callee.kind,ExprKind::Unary{op,..}if op=="::"){return failure("non-constant expression",a)}
   let ExprKind::Ident(name)=&callee.kind else{return Ok(Evaluated::Unissued("Original conditional expression follower requires its actual constant product"))};
   match name.as_str(){
    "new"=>{let Some(has_args)=(match constructors{Some(facts)=>facts.implicit_at_using(callee.span,a)?,None=>None})else{return Ok(Evaluated::Unissued("Original implicit new lacks actual native argument-presence fact"))};if !has_args&&!args.is_empty(){return Err(io::ErrorKind::InvalidData.into())}return new_value(None,has_args.then_some(args.as_slice()),macros,a,file_exists,constructors,debug)},

    "input"|"locate"|"pick"=>return failure("non-constant expression",a),
    "defined"=>{if macros.model.is_some(){return failure("non-constant function call: defined",a)}
     if args.len()!=1{return arity_failure("defined",args.len(),a)}
     let ExprKind::Ident(name)=&args[0].kind else{return failure("malformed defined() call, argument given isn't an Ident.",a)};
     let present=macros.contains_key(name);poll(a)?;flag(present)
    },
    "nameof"=>{
     if args.len()!=1{return arity_failure("nameof",args.len(),a)}
     let Some(name)=nameof(&args[0],a)? else{return failure("malformed nameof() call, expression appears to have no name",a)};
     Value::String(Text::Borrowed(name))
    },
    "fexists"=>{if macros.model.is_some(){return failure("non-constant function call: fexists",a)}if args.len()!=1{return arity_failure("fexists",args.len(),a)}let ExprKind::Literal(literal)=&args[0].kind else{return failure("malformed fexists() call, argument given isn't a string.",a)};let Some(OriginalTokenValue::String(path))=literal.original_value()else{return failure("malformed fexists() call, argument given isn't a string.",a)};let Some(context)=file_exists.as_deref_mut()else{return Ok(Evaluated::Unissued("Original fexists requires the authentic saved file/context and filesystem question"))};match context(path)?{FileExistsResult::Value(value)=>flag(value),FileExistsResult::SourceFailure(message)=>return Ok(Evaluated::SourceFailure(message.into()))}},
    "sin"|"cos"|"arcsin"|"arccos"=>{if args.len()!=1{let mut message=TextBuffer::new(a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out,"trig function requires exactly 1 argument, instead found {}",args.len())})?;return Ok(Evaluated::SourceFailure(message.into()))}let argument=value!(evaluate_inner(&args[0],&macros.no_hint(),a,file_exists,constructors,debug));let Value::Number(ConditionNumber::Original(number))=argument else{return failure("trig function requires numeric argument",a)};let operation:fn(f32)->f32=match name.as_str(){"sin"=>f32::sin,"cos"=>f32::cos,"arcsin"=>f32::asin,"arccos"=>f32::acos,_=>unreachable!()};Value::Number(ConditionNumber::Original(operation(number)))},
    "matrix"|"newlist"|"icon"|"sound"|"filter"|"file"|"generator"|"list"=>return compound(name,args,macros,a,file_exists,constructors,debug),
    "rgb"=>return rgb(args,macros,a,file_exists,constructors,debug),
    _=>{let mut message=TextBuffer::new(a)?;message.push_str("non-constant function call: ",a)?;message.push_str(name,a)?;return Ok(Evaluated::SourceFailure(message.into()))}
   }
  },
  _=>return Ok(Evaluated::Unissued("Original conditional term/follower constant product is not issued")),
 };
 Ok(Evaluated::Value(value))
}
fn arity_failure<'s>(name:&str,count:usize,a:&SettingAdmission<'_>)->io::Result<Evaluated<'s>>{let mut message=TextBuffer::new(a)?;original_format_using(&mut message,a,|out|{use std::fmt::Write;write!(out,"malformed {name}() call, must have 1 argument and instead has {count}")})?;Ok(Evaluated::SourceFailure(message.into()))}
fn binary_failure<'s>(op:&str,lhs:&Value<'_>,rhs:&Value<'_>,a:&SettingAdmission<'_>)->io::Result<Evaluated<'s>>{
 let debug=if op=="/"{"Div"}else{dm_syntax::original_scalar_transport::original_punctuation_debug_name(op,false).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"accepted Original binary operator lacks canonical Debug name"))?};
 let mut message=TextBuffer::new(a)?;message.push_str("non-constant ",a)?;message.push_str(debug,a)?;message.push_str(": ",a)?;lhs.display(&mut message,a)?;message.push(' ',a)?;message.push_str(op,a)?;message.push(' ',a)?;rhs.display(&mut message,a)?;Ok(Evaluated::SourceFailure(message.into()))
}
fn nameof<'s>(expr:&'s Expr,a:&SettingAdmission<'_>)->io::Result<Option<&'s str>>{
 let _frame=a.evaluation_frame().map_err(|error|a.take_operational_error().unwrap_or(error))?;
 Ok(match &expr.kind{ExprKind::Ident(name)=>Some(name),ExprKind::Group(inner)=>return nameof(inner,a),ExprKind::Member{selector,..}|ExprKind::StaticMember{selector,..}|ExprKind::SafeMember{selector,..}=>Some(selector),ExprKind::TypePath(path)=>path.rsplit('/').next().map(|part|part.trim_start_matches(['.',':'])).filter(|part|!part.is_empty()),ExprKind::Unary{op,value}if op=="::"=>return nameof(value,a),ExprKind::ObjectInitializer{object,fields}if fields.is_empty()=>return nameof(object,a),_=>None})
}

#[cfg(test)]mod tests{
 use super::*;use std::{collections::BTreeMap, sync::{atomic::{Ordering}}, cell::Cell};
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
 #[test]fn typed_scalar_values_precede_misleading_raw_spelling_and_preserve_nan_and_resource_variants(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let env=macros();{
  let zero=literal(OriginalTokenValue::Int(0),&a);assert!(!yes(evaluate(&zero,&env,&a).unwrap()));
  let nan=binary("==",literal(OriginalTokenValue::Float(f32::NAN),&a),literal(OriginalTokenValue::Float(f32::NAN),&a));assert!(yes(evaluate(&nan,&env,&a).unwrap()));
  let negative_zero=binary("==",literal(OriginalTokenValue::Float(-0.0),&a),literal(OriginalTokenValue::Int(0),&a));assert!(yes(evaluate(&negative_zero,&env,&a).unwrap()));
  assert!(yes(evaluate(&literal(OriginalTokenValue::Resource(""),&a),&env,&a).unwrap()));assert!(!yes(evaluate(&literal(OriginalTokenValue::String(""),&a),&env,&a).unwrap()));
  let variants=binary("==",literal(OriginalTokenValue::String("same"),&a),literal(OriginalTokenValue::Resource("same"),&a));assert!(!yes(evaluate(&variants,&env,&a).unwrap()));
 }assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes())}
 #[test]fn actual_eager_boolean_operands_and_lazy_ternary_do_not_use_host_short_circuit_semantics(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let env=macros();for(op,left)in[("&&",0),("||",1)]{let expr=binary(op,literal(OriginalTokenValue::Int(left),&a),ident("UNEXPANDED"));assert_eq!(source(evaluate(&expr,&env,&a).unwrap()),"cannot reference variable \"UNEXPANDED\" in this context");}let expr=expression(ExprKind::Conditional{condition:Box::new(literal(OriginalTokenValue::Int(1),&a)),then_value:Box::new(literal(OriginalTokenValue::Int(7),&a)),else_value:Box::new(ident("NEVER_EVALUATED"))});assert!(yes(evaluate(&expr,&env,&a).unwrap()));}
 #[test]fn defined_records_actual_positive_and_negative_name_questions_without_evaluating_or_unwrapping_operand(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut env=macros();env.values.insert("PRESENT".into(),crate::Macro{parameters:None,variadic:false,replacement:"anything".into()});assert!(yes(evaluate(&call("defined",vec![ident("PRESENT")]),&env,&a).unwrap()));assert!(!yes(evaluate(&call("defined",vec![ident("MISSING")]),&env,&a).unwrap()));assert_eq!(env.reads.get(),2);let bad=call("defined",vec![expression(ExprKind::Group(Box::new(ident("PRESENT"))))]);assert_eq!(source(evaluate(&bad,&env,&a).unwrap()),"malformed defined() call, argument given isn't an Ident.");assert_eq!(env.reads.get(),2);assert_eq!(source(evaluate(&call("defined",vec![]),&env,&a).unwrap()),"malformed defined() call, must have 1 argument and instead has 0");}
 #[test]fn exact_old_numeric_judge_and_source_error_formatting_share_existing_arithmetic_and_display(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let env=macros();for(op,left,right,result)in[("%%",-5.0,3.0,1.0),("**",2.0,3.0,8.0),("|",16777216.0,1.0,1.0)]{let expr=binary("==",binary(op,literal(OriginalTokenValue::Float(left),&a),literal(OriginalTokenValue::Float(right),&a)),literal(OriginalTokenValue::Float(result),&a));assert!(yes(evaluate(&expr,&env,&a).unwrap()));}let expr=binary("/",literal(OriginalTokenValue::String("bad"),&a),literal(OriginalTokenValue::Int(2),&a));assert_eq!(source(evaluate(&expr,&env,&a).unwrap()),"non-constant Div: \"bad\" / 2");let expr=binary("=",ident("LHS_NOT_EVALUATED"),ident("RHS_NOT_EVALUATED"));assert_eq!(source(evaluate(&expr,&env,&a).unwrap()),"non-constant assignment");}
 #[test]fn allocation_and_first_actual_io_refusal_do_not_become_false_or_source_failure_and_same_domain_recovers(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let env=macros();let expr=ident("UNEXPANDED");let failed=SettingAdmission::new(&used,1<<20,&||Err(io::Error::from_raw_os_error(1450)));assert_eq!(evaluate(&expr,&env,&failed).err().unwrap().raw_os_error(),Some(1450));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());let too_small=SettingAdmission::new(&used,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));assert_eq!(evaluate(&expr,&env,&too_small).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());let good=SettingAdmission::new(&used,1<<20,&||Ok(()));let result=evaluate(&expr,&env,&good).unwrap();assert!(matches!(result,Outcome::SourceFailure(_)));drop(result);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn unavailable_context_and_wide_shift_are_not_silently_false(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let env=macros();for expr in[call("fexists",vec![literal(OriginalTokenValue::String("x"),&a)]),binary("<<",literal(OriginalTokenValue::Int(1),&a),literal(OriginalTokenValue::Int(32),&a))]{assert!(matches!(evaluate(&expr,&env,&a).unwrap(),Outcome::Unissued(_)));}}
 #[test]fn actual_compound_key_preserves_folded_numeric_nan_zero_and_nested_constructor_structure(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let env=macros();{let expr=binary("==",call("matrix",vec![literal(OriginalTokenValue::Float(-0.0),&a),literal(OriginalTokenValue::Float(f32::from_bits(0x7fc00001)),&a)]),call("matrix",vec![literal(OriginalTokenValue::Int(0),&a),literal(OriginalTokenValue::Float(f32::from_bits(0x7fc00002)),&a)]));assert!(yes(evaluate(&expr,&env,&a).unwrap()));let expr=binary("==",call("icon",vec![call("list",vec![binary("+",literal(OriginalTokenValue::Int(1),&a),literal(OriginalTokenValue::Int(1),&a))])]),call("icon",vec![call("list",vec![literal(OriginalTokenValue::Int(2),&a)])]));assert!(yes(evaluate(&expr,&env,&a).unwrap()));}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn compound_product_quota_and_late_first_io_retire_flat_buffers_without_false_outcome(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let env=macros();let expr=call("icon",vec![call("matrix",vec![])]);let tiny=SettingAdmission::new(&used,dm_syntax::SettingChargeCounter::root_allocation_bytes(),&||Ok(()));assert_eq!(evaluate(&expr,&env,&tiny).err().unwrap().kind(),io::ErrorKind::OutOfMemory);assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());for fail_at in[1,8,32]{let calls=Cell::new(0);let checkpoint=||{let n=calls.get()+1;calls.set(n);if n>=fail_at{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};let a=SettingAdmission::new(&used,8<<20,&checkpoint);let result=evaluate(&expr,&env,&a);if let Err(error)=result{assert_eq!(error.raw_os_error(),Some(1450))}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}}

}

#[cfg(test)]mod actual_original_trig_controls{use super::*;use std::{sync::{atomic::{Ordering}}, collections::BTreeMap};struct Env(BTreeMap<String,crate::Macro>);impl MacroLookup for Env{fn initial_environment(&self)->crate::InitialEnvironment{crate::InitialEnvironment::OriginalChecker0290}fn get_key_value(&self,n:&str)->Option<(&str,&crate::Macro)>{self.0.get_key_value(n).map(|(k,v)|(k.as_str(),v))}}fn call(n:&str,args:Vec<Expr>)->Expr{let span=dm_syntax::Span::new(0,1);Expr{span,kind:ExprKind::Call{callee:Box::new(Expr{span,kind:ExprKind::Ident(n.into())}),args}}}fn lit(v:OriginalTokenValue<&str>,a:&SettingAdmission<'_>)->Expr{Expr{span:dm_syntax::Span::new(0,1),kind:ExprKind::Literal(dm_syntax::LiteralText::from_original_value_data("same-issued-value".into(),0,v,a).unwrap())}}#[test]fn original_trig_uses_exact_pinned_f32_operations_and_argument_failure_text(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,8<<20,&||Ok(()));let env=Env(BTreeMap::new());for(name,arg,wanted)in[("sin",0,false),("cos",0,true),("arcsin",0,false),("arccos",1,false)]{let expr=call(name,vec![lit(OriginalTokenValue::Int(arg),&a)]);assert!(matches!(evaluate(&expr,&env,&a).unwrap(),Outcome::Value(v)if v==wanted));}for(expr,message)in[(call("sin",vec![]),"trig function requires exactly 1 argument, instead found 0"),(call("cos",vec![lit(OriginalTokenValue::String("x"),&a)]),"trig function requires numeric argument")]{let Outcome::SourceFailure(actual)=evaluate(&expr,&env,&a).unwrap()else{panic!("actual source failure")};assert_eq!(actual.as_str(),message);}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}}


impl ModelMessage{
 pub fn copy_using(message:&str,a:&SettingAdmission<'_>)->io::Result<Self>{Ok(copy_text(message,a)?.into())}
 pub fn format_using(a:&SettingAdmission<'_>,write:impl FnOnce(&mut dyn std::fmt::Write)->std::fmt::Result)->io::Result<Self>{let pending=(||{let mut text=TextBuffer::new(a)?;original_format_using(&mut text,a,|out|write(out))?;Ok(text.into())})();match a.take_operational_error(){Some(first)=>Err(first),None=>pending}}
 pub fn append_using(&mut self,text:&str,a:&SettingAdmission<'_>)->io::Result<()>{let pending=self.value.push_str(text,a);match a.take_operational_error(){Some(first)=>Err(first),None=>pending}}
 pub fn append_format_using(&mut self,text:std::fmt::Arguments<'_>,a:&SettingAdmission<'_>)->io::Result<()>{let pending=original_format_using(&mut self.value,a,|out|{use std::fmt::Write;out.write_fmt(text)});match a.take_operational_error(){Some(first)=>Err(first),None=>pending}}
}
