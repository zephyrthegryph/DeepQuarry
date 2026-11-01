//! Original Debug projection over already-issued native nodes.
//! No parser, copied AST, source receipt, or public checker family is introduced.
//! Independent original-AST observations live in Analyze tests, outside native dependencies.
use dm_syntax::{Expr,ExprKind,Span};
use std::fmt::Write;

/// Source-free counting/fixed sink. Overflow is sticky; fixed writes never
/// reserve, grow, or expose bytes beyond their pre-admitted physical capacity.
pub(super) struct DebugSink<'a>{target:Option<&'a mut String>,limit:usize,pub(super) used:usize,denied:bool}
impl<'a> DebugSink<'a>{
 pub(super) fn count()->Self{Self{target:None,limit:usize::MAX,used:0,denied:false}}
 pub(super) fn fixed(target:&'a mut String,limit:usize)->Self{Self{target:Some(target),limit,used:0,denied:false}}
 pub(super) fn push_str(&mut self,text:&str){if self.denied{return}let Some(next)=self.used.checked_add(text.len())else{self.denied=true;return};if next>self.limit||self.target.as_ref().is_some_and(|target|next>target.capacity()){self.denied=true;return}if let Some(target)=&mut self.target{target.push_str(text)}self.used=next;}
 pub(super) fn push(&mut self,ch:char){let mut bytes=[0;4];self.push_str(ch.encode_utf8(&mut bytes))}
 pub(super) fn denied(&self)->bool{self.denied}
 pub(super) fn len(&self)->usize{self.used}
}
impl Write for DebugSink<'_>{fn write_str(&mut self,text:&str)->std::fmt::Result{self.push_str(text);if self.denied{Err(std::fmt::Error)}else{Ok(())}}}


/// Scalar spelling policy from pinned ast::{BinaryOp,AssignOp,UnaryOp}.
fn binary(op:&str)->Option<(&'static str,&'static str)>{Some(match op{
 "+"=>("BinaryOp","Add"),"-"=>("BinaryOp","Sub"),"*"=>("BinaryOp","Mul"),"/"=>("BinaryOp","Div"),"**"=>("BinaryOp","Pow"),"%"=>("BinaryOp","Mod"),"%%"=>("BinaryOp","FloatMod"),
 "=="=>("BinaryOp","Eq"),"!="=>("BinaryOp","NotEq"),"<"=>("BinaryOp","Less"),">"=>("BinaryOp","Greater"),"<="=>("BinaryOp","LessEq"),">="=>("BinaryOp","GreaterEq"),"<=>"=>("BinaryOp","LessOrGreater"),"~="=>("BinaryOp","Equiv"),"~!"=>("BinaryOp","NotEquiv"),
 "&"=>("BinaryOp","BitAnd"),"^"=>("BinaryOp","BitXor"),"|"=>("BinaryOp","BitOr"),"<<"=>("BinaryOp","LShift"),">>"=>("BinaryOp","RShift"),"&&"=>("BinaryOp","And"),"||"=>("BinaryOp","Or"),"in"=>("BinaryOp","In"),"to"=>("BinaryOp","To"),
 "="=>("AssignOp","Assign"),"+="=>("AssignOp","AddAssign"),"-="=>("AssignOp","SubAssign"),"*="=>("AssignOp","MulAssign"),"/="=>("AssignOp","DivAssign"),"%="=>("AssignOp","ModAssign"),"%%="=>("AssignOp","FloatModAssign"),":="=>("AssignOp","AssignInto"),"&="=>("AssignOp","BitAndAssign"),"&&="=>("AssignOp","AndAssign"),"|="=>("AssignOp","BitOrAssign"),"||="=>("AssignOp","OrAssign"),"^="=>("AssignOp","BitXorAssign"),"<<="=>("AssignOp","LShiftAssign"),">>="=>("AssignOp","RShiftAssign"),_=>return None})}
fn unary(op:&str)->Option<&'static str>{Some(match op{"-"=>"Neg","!"=>"Not","~"=>"BitNot","pre++"=>"PreIncr","post++"=>"PostIncr","pre--"=>"PreDecr","post--"=>"PostDecr","&"=>"Reference","*"=>"Dereference",_=>return None})}

/// DATA-only adapters must answer from authenticated original token geometry.
/// The production adapter borrows the actual archive/mapping and SAME SettingAdmission.
/// A token is selected from its issued interval, never found by rescanning text.
pub(super) trait Source{
 type Error:From<&'static str>;
 type Frame<'a> where Self:'a;
 type Scratch<'a> where Self:'a;
 fn scratch(&self,bytes:usize)->Result<Self::Scratch<'_>,Self::Error>;
 fn frame(&self)->Result<Self::Frame<'_>,Self::Error>;
 // fmt::Write cannot transport typed source IO. Real adapters keep the first
 // checkpoint error in their SAME existing admission until the outer boundary.
 fn literal_checkpoint(&self)->std::fmt::Result{Ok(())}
 fn location(&self,canonical_offset:usize,out:&mut DebugSink<'_>)->Result<(),Self::Error>;
 fn punctuation(&self,canonical_interval:Span,spelling:&str)->Result<usize,Self::Error>;
 fn path(&self,path:&Expr,out:&mut DebugSink<'_>)->Result<(),Self::Error>;
 fn fragment_expression(&self,fragment:&dm_syntax::literal::PinnedLiteralFragment<'_>,out:&mut DebugSink<'_>)->Result<(),Self::Error>;
 fn literal(&self,value:&dm_syntax::LiteralText,out:&mut DebugSink<'_>)->Result<(),Self::Error> where Self:Sized {literal_debug(self,value,out)}
}
fn base_child(expr:&Expr)->Option<&Expr>{match &expr.kind{
 ExprKind::Unary{op,value}if unary(op).is_some()=>Some(value),
 ExprKind::Member{object,..}|ExprKind::SafeMember{object,..}|ExprKind::StaticMember{object,..}|ExprKind::Index{object,..}|ExprKind::SafeIndex{object,..}=>Some(object),
 ExprKind::Call{callee,..}if matches!(callee.kind,ExprKind::Member{..}|ExprKind::SafeMember{..}|ExprKind::StaticMember{..})=>Some(callee),_=>None}}
fn leaf<'a,S:Source>(source:&S,mut node:&'a Expr)->Result<&'a Expr,S::Error>{while let Some(next)=base_child(node){let _frame=source.frame()?;node=next}Ok(node)}
fn spanned<S:Source>(source:&S,offset:usize,out:&mut DebugSink<'_>,emit:impl FnOnce(&mut DebugSink<'_>)->Result<(),S::Error>)->Result<(),S::Error>{out.push_str("Spanned { location: ");source.location(offset,out)?;out.push_str(", elem: ");emit(out)?;out.push_str(" }");Ok(())}
pub(super) fn expression<S:Source>(source:&S,expr:&Expr,out:&mut DebugSink<'_>)->Result<(),S::Error>{
 let _frame=source.frame()?;
 if primitive(source,expr,out,true)?{return Ok(())}
 match &expr.kind{
  ExprKind::Binary{op,lhs,rhs}=>{let(kind,op)=binary(op).ok_or("unmapped native binary Debug operation")?;write!(out,"{kind} {{ op: {op}, lhs: ").map_err(|_|S::Error::from("Debug output failed"))?;expression(source,lhs,out)?;out.push_str(", rhs: ");expression(source,rhs,out)?;out.push_str(" }");}
  ExprKind::Conditional{condition,then_value,else_value}=>{out.push_str("TernaryOp { cond: ");expression(source,condition,out)?;out.push_str(", if_: ");expression(source,then_value,out)?;out.push_str(", else_: ");expression(source,else_value,out)?;out.push_str(" }");}
  _=>{out.push_str("Base { term: ");let term=leaf(source,expr)?;spanned(source,term.span.start,out,|out|term_debug(source,term,out))?;out.push_str(", follow: [");let mut first=true;follows(source,expr,out,&mut first)?;out.push_str("] }");}
 }
 Ok(())
}
pub(super) fn term_debug<S:Source>(source:&S,expr:&Expr,out:&mut DebugSink<'_>)->Result<(),S::Error>{
 let _frame=source.frame()?;
 if primitive(source,expr,out,false)?{return Ok(())}
 match &expr.kind{
 ExprKind::Ident(name)=>match name.as_str(){"null"=>out.push_str("Null"),"__PROC__"|"__TYPE__"|"__IMPLIED_TYPE__"=>out.push_str(name),_=>{out.push_str("Ident(");write!(out,"{name:?}").map_err(|_|S::Error::from("Debug output failed"))?;out.push(')');}},
 ExprKind::Literal(value)=>source.literal(value,out)?,
 ExprKind::TypePath(_)|ExprKind::ObjectInitializer{..}=>{out.push_str("Prefab(");prefab(source,expr,out)?;out.push(')');},
 ExprKind::Unary{op,value}if op=="new"=>new_term(source,value,out)?,
 ExprKind::Unary{op,value}if op=="::"=>{let ExprKind::Ident(name)=&value.kind else{return Err("original global identifier unavailable".into())};write!(out,"GlobalIdent({name:?})").map_err(|_|S::Error::from("Debug output failed"))?;},
 ExprKind::Group(inner)=>{out.push_str("Expr(");expression(source,inner,out)?;out.push(')');},
 ExprKind::Call{callee,args}=>{match &callee.kind{ExprKind::Call{callee:primitive,args:inner}if matches!(&primitive.kind,ExprKind::Ident(name)if name=="call"||name=="call_ext")=>{let ExprKind::Ident(name)=&primitive.kind else{unreachable!()};if name=="call"{out.push_str("DynamicCall(");arguments(source,inner,out)?;out.push_str(", ");arguments(source,args,out)?;out.push(')');}else{external_call(source,inner,args,out)?;}},ExprKind::Ident(name)if name=="pick"=>{out.push_str("Pick([");for(index,arg)in args.iter().enumerate(){if index!=0{out.push_str(", ")}out.push('(');if let ExprKind::Binary{op,lhs,rhs}=&arg.kind{if op!=";"{out.push_str("None, ");expression(source,arg,out)?;}else{out.push_str("Some(");expression(source,lhs,out)?;out.push_str("), ");expression(source,rhs,out)?;}}else{out.push_str("None, ");expression(source,arg,out)?;}out.push(')');}out.push_str("])");},ExprKind::Ident(name)if name=="as"=>{out.push_str("As(");let bits=if args.is_empty(){0}else if args.len()==1{type_expression(source,&args[0])?.ok_or("as primary type expression unavailable")?}else{return Err("as primary argument count differs".into())};type_debug(bits,out);out.push(')');},ExprKind::Ident(name)if name=="list"||name=="alist"=>{out.push_str("List(");arguments(source,args,out)?;out.push(')');},ExprKind::Ident(name)if name=="new"=>{out.push_str("NewImplicit { args: ");if expr.span.end==callee.span.end{out.push_str("None")}else{out.push_str("Some(");arguments(source,args,out)?;out.push(')')}out.push_str(" }");},ExprKind::Ident(name)if name=="."||name==".."=>{out.push_str(if name=="."{"SelfCall("}else{"ParentCall("});arguments(source,args,out)?;out.push(')');},ExprKind::Unary{op,value}if op=="::"=>{let ExprKind::Ident(name)=&value.kind else{return Err("global call primary name unavailable".into())};write!(out,"GlobalCall({name:?}, ").map_err(|_|S::Error::from("Debug output failed"))?;arguments(source,args,out)?;out.push(')');},ExprKind::Ident(name)if name!="new"&&name!="input"&&name!="locate"&&name!="pick"&&name!="call"&&name!="call_ext"&&name!="as"=>{out.push_str("Call(");write!(out,"{name:?}, ").map_err(|_|S::Error::from("Debug output failed"))?;arguments(source,args,out)?;out.push(')');},_=>return Err("special native call Debug projection incomplete".into())}},
 _=>return Err("native term Debug projection incomplete".into())}
 Ok(())
}
fn arguments<S:Source>(source:&S,args:&[Expr],out:&mut DebugSink<'_>)->Result<(),S::Error>{out.push('[');let mut first=true;for arg in args{
 // Pinned arguments() deliberately omits empty argument expressions; its
 // TODO is not the runtime compiler's explicit-null argument semantics. Only
 // the primary parser's zero-width null placeholder is omitted here.
 if arg.span.start==arg.span.end&&matches!(&arg.kind,ExprKind::Literal(raw)if raw.as_str()=="null"){continue}
 if !first{out.push_str(", ")}first=false;expression(source,arg,out)?;}out.push(']');Ok(())}
fn follows<S:Source>(source:&S,expr:&Expr,out:&mut DebugSink<'_>,first:&mut bool)->Result<(),S::Error>{
 let _frame=source.frame()?;
 let Some(child)=base_child(expr)else{return Ok(())};
 // A member immediately beneath a call is emitted ONCE as Follow::Call.
 if let ExprKind::Call{callee,args}=&expr.kind{
  if let ExprKind::StaticMember{object,selector}=&callee.kind{follows(source,object,out,first)?;if !*first{out.push_str(", ")}*first=false;let offset=source.punctuation(Span::new(object.span.end,callee.span.end),"::")?;return spanned(source,offset,out,|out|{write!(out,"ProcReference({selector:?})").map_err(|_|S::Error::from("Debug output failed"))?;Ok(())})}
  let(object,selector,kind)=match &callee.kind{ExprKind::Member{object,selector,via_colon}=>(object.as_ref(),selector,if *via_colon{"Colon"}else{"Dot"}),ExprKind::SafeMember{object,selector,via_colon}=>(object.as_ref(),selector,if *via_colon{"SafeColon"}else{"SafeDot"}),_=>return Err("static proc-reference call Debug projection incomplete".into())};
  follows(source,object,out,first)?;if !*first{out.push_str(", ")}*first=false;let offset=source.punctuation(Span::new(object.span.end,callee.span.end),match kind{"Dot"=>".","Colon"=>":","SafeDot"=>"?.",_=>"?:"})?;
  return spanned(source,offset,out,|out|{write!(out,"Call({kind}, {selector:?}, ").map_err(|_|S::Error::from("Debug output failed"))?;arguments(source,args,out)?;out.push(')');Ok(())})
 }
 follows(source,child,out,first)?;if !*first{out.push_str(", ")}*first=false;
 let(offset,spelling)=match &expr.kind{ExprKind::Unary{op,..}=>{let offset=if op.starts_with("post"){source.punctuation(Span::new(child.span.end,expr.span.end),&op[4..])?}else{expr.span.start};(offset,None)},ExprKind::Member{via_colon,..}|ExprKind::SafeMember{via_colon,..}=>{let safe=matches!(expr.kind,ExprKind::SafeMember{..});let spelling=match(safe,*via_colon){(false,false)=>".",(false,true)=>":",(true,false)=>"?.",(true,true)=>"?:"};(source.punctuation(Span::new(child.span.end,expr.span.end),spelling)?,Some(spelling))},ExprKind::StaticMember{..}=>(source.punctuation(Span::new(child.span.end,expr.span.end),"::")?,None),ExprKind::Index{..}|ExprKind::SafeIndex{..}=>(source.punctuation(Span::new(child.span.end,expr.span.end),if matches!(expr.kind,ExprKind::SafeIndex{..}){"?["}else{"["})?,None),_=>return Err("native follow Debug projection incomplete".into())};
 spanned(source,offset,out,|out|{match &expr.kind{
 ExprKind::Unary{op,..}=>{write!(out,"Unary({})",unary(op).ok_or("unmapped native unary Debug operation")?).map_err(|_|S::Error::from("Debug output failed"))?;},
 ExprKind::Member{selector,..}|ExprKind::SafeMember{selector,..}=>{let kind=match spelling.unwrap(){"."=>"Dot",":"=>"Colon","?."=>"SafeDot",_=>"SafeColon"};write!(out,"Field({kind}, {selector:?})").map_err(|_|S::Error::from("Debug output failed"))?;},
 ExprKind::StaticMember{selector,..}=>{write!(out,"StaticField({selector:?})").map_err(|_|S::Error::from("Debug output failed"))?;},
 ExprKind::Index{index,..}|ExprKind::SafeIndex{index,..}=>{out.push_str(if matches!(expr.kind,ExprKind::SafeIndex{..}){"Index(Safe, "}else{"Index(Normal, "});expression(source,index,out)?;out.push(')');},_=>unreachable!()};Ok(())})
}

/// Stream exactly Rust str Debug escaping while a primary lexical writer emits
/// pieces. Apostrophes differ from char::Debug and must remain literal here.
struct Quoted<'a,'buffer,S:Source>{output:&'a mut DebugSink<'buffer>,source:&'a S,until_poll:usize}
impl<'a,'buffer,S:Source> Quoted<'a,'buffer,S>{fn new(output:&'a mut DebugSink<'buffer>,source:&'a S)->Self{Self{output,source,until_poll:1024}}}
impl<S:Source> Write for Quoted<'_,'_,S>{fn write_str(&mut self,text:&str)->std::fmt::Result{for ch in text.chars(){self.until_poll=self.until_poll.saturating_sub(ch.len_utf8());if self.until_poll==0{self.source.literal_checkpoint()?;self.until_poll=1024;}if ch=='\''{self.output.push(ch)}else{for escaped in ch.escape_debug(){self.output.push(escaped)}}}Ok(())}}
fn literal_debug<S:Source>(source:&S,value:&dm_syntax::LiteralText,out:&mut DebugSink<'_>)->Result<(),S::Error>{
 use dm_syntax::numeric_form::{numeric_form,NumericForm};
 let raw=value.as_str();
 if raw=="null"{out.push_str("Null");return Ok(())}
 if raw.as_bytes().first().is_some_and(|b|b.is_ascii_digit()||*b==b'.'){
  let numeric_bytes=raw.len().checked_mul(4).and_then(|n|n.checked_add(64)).ok_or("original numeric scratch capacity overflow")?;let _scratch=source.scratch(numeric_bytes)?;
  match numeric_form(raw).map_err(|_|S::Error::from("invalid primary numeric literal"))?{
   NumericForm::Integer(value)=>write!(out,"Int({value})").map_err(|_|S::Error::from("Debug output failed"))?,
   NumericForm::Float=>{let normalized:String=raw.chars().filter(|ch|*ch!='_').collect();let value=if normalized.ends_with("#INF"){f32::INFINITY}else if normalized.ends_with("#IND"){f32::NAN}else{normalized.parse::<f32>().map_err(|_|S::Error::from("invalid primary float literal"))?};write!(out,"Float({value:?})").map_err(|_|S::Error::from("Debug output failed"))?;}
  };return Ok(())
 }
 // Resource spelling is the SAME read_resource backslash projection: one
 // backslash quotes exactly its next source character; there is no DM string
 // escape interpretation. The prepared primary lexical writer owns this projection.
 if raw.starts_with('\''){out.push_str("Resource(\"");if !value.write_pinned_resource_text(&mut Quoted::new(out,source)).map_err(|_|S::Error::from("original resource lexical text unavailable"))?{return Err("original resource token unavailable".into())}out.push_str("\")");return Ok(())}
 let mut fragments=value.pinned_fragments().map_err(|_|S::Error::from("original literal fragments unavailable"))?;
 if let Some(fragments)=fragments.as_mut(){
  let first=fragments.next().ok_or("interpolated literal lacks initial original fragment")?.map_err(|_|S::Error::from("original literal fragment unavailable"))?;
  if first.expression().is_some(){return Err("initial original fragment has unexpected child".into())}
  out.push_str("InterpString(\"");first.write_text(&mut Quoted::new(out,source)).map_err(|_|S::Error::from("original lexical fragment unavailable"))?;out.push_str("\", [");
  for(index,fragment)in fragments.enumerate(){let fragment=fragment.map_err(|_|S::Error::from("original literal fragment unavailable"))?;if index!=0{out.push_str(", ")}out.push('(');if fragment.expression().is_some(){out.push_str("Some(");source.fragment_expression(&fragment,out)?;out.push(')')}else{out.push_str("None")}out.push_str(", \"");fragment.write_text(&mut Quoted::new(out,source)).map_err(|_|S::Error::from("original lexical fragment unavailable"))?;out.push_str("\")");}
  out.push_str("])");
 }else{
  out.push_str("String(\"");if !value.write_pinned_static_text(&mut Quoted::new(out,source)).map_err(|_|S::Error::from("original static lexical text unavailable"))?{return Err("original static string projection unavailable".into())}out.push_str("\")");
 }
 Ok(())
}

fn prefab<S:Source>(source:&S,expr:&Expr,out:&mut DebugSink<'_>)->Result<(),S::Error>{
 let _frame=source.frame()?;
 let(path,fields)=match &expr.kind{ExprKind::TypePath(_)=>(expr,&[][..]),ExprKind::ObjectInitializer{object,fields}if matches!(object.kind,ExprKind::TypePath(_))=>(object.as_ref(),fields.as_slice()),_=>return Err("prefab primary target is not an issued path".into())};
 out.push_str("Prefab { path: ");source.path(path,out)?;out.push_str(", vars: [");
 for(index,(name,value))in fields.iter().enumerate(){if index!=0{out.push_str(", ")}write!(out,"({name:?}, ").map_err(|_|S::Error::from("Debug output failed"))?;expression(source,value,out)?;out.push(')');}
 out.push_str("] }");Ok(())
}
fn new_term<S:Source>(source:&S,value:&Expr,out:&mut DebugSink<'_>)->Result<(),S::Error>{
 let _frame=source.frame()?;
 let(target,args)=match &value.kind{ExprKind::Call{callee,args}=>(callee.as_ref(),Some(args.as_slice())),_=>(value,None)};
 match &target.kind{
 ExprKind::TypePath(_)|ExprKind::ObjectInitializer{..}=>{out.push_str("NewPrefab { prefab: ");prefab(source,target,out)?;},
 ExprKind::Ident(_)|ExprKind::Member{..}|ExprKind::SafeMember{..}=>{out.push_str("NewMiniExpr { expr: MiniExpr { ident: ");let name=mini_name(source,target)?.ok_or("constructor primary miniature expression unavailable")?;write!(out,"{name:?}, fields: [").map_err(|_|S::Error::from("Debug output failed"))?;let mut first=true;mini_fields(source,target,out,&mut first)?;out.push_str("] }");},
 _=>return Err("constructor primary target Debug projection incomplete".into())}
 out.push_str(", args: ");if let Some(args)=args{out.push_str("Some(");arguments(source,args,out)?;out.push(')')}else{out.push_str("None")}out.push_str(" }");Ok(())
}
fn mini_name<'a,S:Source>(source:&S,mut expr:&'a Expr)->Result<Option<&'a str>,S::Error>{loop{let _frame=source.frame()?;match &expr.kind{ExprKind::Ident(name)=>return Ok(Some(name)),ExprKind::Member{object,..}|ExprKind::SafeMember{object,..}=>expr=object,_=>return Ok(None)}}}
fn mini_fields<S:Source>(source:&S,expr:&Expr,out:&mut DebugSink<'_>,first:&mut bool)->Result<(),S::Error>{let _frame=source.frame()?;let(object,selector,kind)=match &expr.kind{ExprKind::Ident(_)=>return Ok(()),ExprKind::Member{object,selector,via_colon}=>(object,selector,if *via_colon{"Colon"}else{"Dot"}),ExprKind::SafeMember{object,selector,via_colon}=>(object,selector,if *via_colon{"SafeColon"}else{"SafeDot"}),_=>return Err("constructor primary miniature field unavailable".into())};mini_fields(source,object,out,first)?;if !*first{out.push_str(", ")}*first=false;write!(out,"Field {{ kind: {kind}, ident: {selector:?} }}").map_err(|_|S::Error::from("Debug output failed"))?;Ok(())}

/// Exact scalar InputType bit values and bitflags-1.3 Debug declaration order.
/// This contains no inferred type facts or expression outcome cache.
const INPUT_FLAGS:[(&str,&str,u32);19]=[("mob","MOB",1),("obj","OBJ",2),("text","TEXT",4),("num","NUM",8),("file","FILE",16),("turf","TURF",32),("key","KEY",64),("null","NULL",128),("area","AREA",256),("icon","ICON",512),("sound","SOUND",1024),("message","MESSAGE",2048),("anything","ANYTHING",4096),("password","PASSWORD",1<<15),("command_text","COMMAND_TEXT",1<<16),("color","COLOR",1<<17),("movable","MOVABLE",3),("atom","ATOM",291),("list","LIST",1<<31)];
fn type_bit(name:&str)->Option<u32>{INPUT_FLAGS.iter().find(|row|row.0==name).map(|row|row.2)}
fn type_expression<S:Source>(source:&S,expr:&Expr)->Result<Option<u32>,S::Error>{let _frame=source.frame()?;Ok(match &expr.kind{ExprKind::Ident(name)=>type_bit(name),ExprKind::Binary{op,lhs,rhs}if op=="|"=>match(type_expression(source,lhs)?,type_expression(source,rhs)?){(Some(lhs),Some(rhs))=>Some(lhs|rhs),_=>None},_=>None})}
fn type_debug(bits:u32,out:&mut DebugSink<'_>){let mut first=true;for(_,name,value)in INPUT_FLAGS{if bits&value==value{if !first{out.push_str(" | ")}first=false;out.push_str(name)}}if first{out.push_str("(empty)")}}
fn optional_expression<S:Source>(source:&S,value:Option<&Expr>,out:&mut DebugSink<'_>)->Result<(),S::Error>{if let Some(value)=value{out.push_str("Some(");expression(source,value,out)?;out.push(')')}else{out.push_str("None")}Ok(())}
fn primitive<S:Source>(source:&S,expr:&Expr,out:&mut DebugSink<'_>,base:bool)->Result<bool,S::Error>{
 let(value,in_list)=match &expr.kind{ExprKind::Binary{op,lhs,rhs}if op=="in"=>(lhs.as_ref(),Some(rhs.as_ref())),_=>(expr,None)};
 let(call,types)=match &value.kind{ExprKind::TypeFilter{value,types}=>(value.as_ref(),Some(types.as_slice())),_=>(value,None)};
 let ExprKind::Call{callee,args}=&call.kind else{return Ok(false)};let ExprKind::Ident(name)=&callee.kind else{return Ok(false)};
 if name!="input"&&!(name=="locate"&&types.is_none()){return Ok(false)}
 let emit=|out:&mut DebugSink<'_>|->Result<(),S::Error>{
 if name=="input"{out.push_str("Input { args: ");arguments(source,args,out)?;out.push_str(", input_type: ");if let Some(types)=types{let mut bits=0;for name in types{bits|=type_bit(name).ok_or("input primary type spelling unavailable")?;}out.push_str("Some(");type_debug(bits,out);out.push(')')}else{out.push_str("None")}}
 else{out.push_str("Locate { args: ");arguments(source,args,out)?;}
 out.push_str(", in_list: ");optional_expression(source,in_list,out)?;out.push_str(" }");Ok(())};if base{out.push_str("Base { term: ");spanned(source,callee.span.start,out,emit)?;out.push_str(", follow: [] }")}else{emit(out)?}Ok(true)
}
fn external_call<S:Source>(source:&S,inner:&[Expr],args:&[Expr],out:&mut DebugSink<'_>)->Result<(),S::Error>{let(library,function)=match inner{[function]=>(None,function),[library,function]=>(Some(library),function),_=>return Err("external call primary argument count differs".into())};out.push_str("ExternalCall { library: ");optional_expression(source,library,out)?;out.push_str(", function: ");expression(source,function,out)?;out.push_str(", args: ");arguments(source,args,out)?;out.push_str(" }");Ok(())}

pub(super) fn path_debug<S:Source>(source:&S,path:&Expr,out:&mut DebugSink<'_>)->Result<(),S::Error>{let ExprKind::TypePath(path)=&path.kind else{return Err("original prefab path node unavailable".into())};out.push('[');let mut at=0;let mut first=true;while at<path.len(){let _frame=source.frame()?;let op=match path.as_bytes()[at]{b'/'=>"Slash",b'.'=>"Dot",b':'=>"Colon",_=>return Err("primary path separator unavailable".into())};at+=1;let end=path[at..].find(['/', '.', ':']).map_or(path.len(),|next|at+next);let name=&path[at..end];if name.is_empty(){return Err("primary path component unavailable".into())}if !first{out.push_str(", ")}first=false;write!(out,"({op}, {name:?})").map_err(|_|S::Error::from("Debug output failed"))?;at=end;}out.push(']');Ok(())}

/// Original evaluated Constant Debug, distinct from primary Term Debug.
pub(super) enum ConstantView<'a>{Null,Literal(&'a dm_syntax::LiteralText),Prefab(&'a str),Procedure{owner:&'a str,kind:Option<&'a str>,name:&'a str}}
pub(super) fn constant_debug<S:Source>(source:&S,value:Option<ConstantView<'_>>,out:&mut DebugSink<'_>)->Result<(),S::Error>{
 let _frame=source.frame()?;let Some(value)=value else{out.push_str("None");return Ok(())};out.push_str("Some(");match value{
 ConstantView::Null=>out.push_str("Null(None)"),
 ConstantView::Procedure{owner,kind,name}=>{out.push_str("Prefab(Pop { path: [");let mut first=true;for part in owner.split('/').filter(|part|!part.is_empty()).chain(kind).chain(std::iter::once(name)){let _frame=source.frame()?;if !first{out.push_str(", ")}first=false;write!(out,"{part:?}").map_err(|_|S::Error::from("Debug output failed"))?;}out.push_str("], vars: {} })");},
 ConstantView::Prefab(path)=>{out.push_str("Prefab(Pop { path: [");let mut first=true;for part in path.split('/').filter(|part|!part.is_empty()){let _frame=source.frame()?;if !first{out.push_str(", ")}first=false;write!(out,"{part:?}").map_err(|_|S::Error::from("Debug output failed"))?;}out.push_str("], vars: {} })");},
 ConstantView::Literal(value)=>{let raw=value.as_str();if raw=="null"{out.push_str("Null(None)")}else if raw.starts_with('\''){literal_debug(source,value,out)?;}else if raw.as_bytes().first().is_some_and(|b|b.is_ascii_digit()||*b==b'.'){
 let _scratch=source.scratch(raw.len().checked_mul(4).and_then(|n|n.checked_add(64)).ok_or("constant numeric scratch overflow")?)?;
 let value=match dm_syntax::numeric_form::numeric_form(raw).map_err(|_|S::Error::from("invalid original numeric constant"))?{dm_syntax::numeric_form::NumericForm::Integer(value)=>value as f32,dm_syntax::numeric_form::NumericForm::Float=>{let normalized:String=raw.chars().filter(|ch|*ch!='_').collect();if normalized.ends_with("#INF"){f32::INFINITY}else if normalized.ends_with("#IND"){f32::NAN}else{normalized.parse::<f32>().map_err(|_|S::Error::from("invalid original float constant"))?}}};write!(out,"Float({value:?})").map_err(|_|S::Error::from("Debug output failed"))?;
 }else{out.push_str("String(\"");if !value.write_pinned_static_text(&mut Quoted::new(out,source)).map_err(|_|S::Error::from("original constant static text unavailable"))?{return Err("original constant has non-static lexical text".into())}out.push_str("\")");}}
 }out.push(')');Ok(())
}

/// Pinned lexer::FormatFloat, shared scalar formatting without a Constant model.
fn display_float(n:f32,out:&mut DebugSink<'_>)->std::fmt::Result{if n.is_nan(){out.write_str(if n.is_sign_negative(){"-1.#IND"}else{"1.#IND"})}else if n.is_infinite(){out.write_str(if n.is_sign_negative(){"-1.#INF"}else{"1.#INF"})}else if n==0.0{out.write_str("0")}else{let exp=n.abs().log10().floor();let factor=10.0f32.powf(5.0-exp);if exp>=6.0||exp<=-5.0{let n2=(n*factor).round()*1.0e-5;let mut precision=0;while precision<5&&(n2*10.0f32.powi(precision))!=(n2*10.0f32.powi(precision)).round(){precision+=1;}write!(out,"{:.*}e{:+04}",precision as usize,n2,exp)}else{let n2=(n*factor).round()/factor;write!(out,"{n2}")}}}
struct TextFlags<'a,S:Source>{source:&'a S,remaining:usize,quote:bool,newline:bool,terminator:bool,last_quote:bool}
impl<S:Source> Write for TextFlags<'_,S>{fn write_str(&mut self,text:&str)->std::fmt::Result{for ch in text.chars(){self.remaining=self.remaining.saturating_sub(ch.len_utf8());if self.remaining==0{self.source.literal_checkpoint()?;self.remaining=1024;}self.terminator|=self.last_quote&&ch=='}';self.last_quote=ch=='"';self.quote|=ch=='"';self.newline|=ch=='\n';}Ok(())}}
struct Plain<'a,'b,S:Source>{out:&'a mut DebugSink<'b>,source:&'a S}
impl<S:Source> Write for Plain<'_,'_,S>{fn write_str(&mut self,text:&str)->std::fmt::Result{for part in text.as_bytes().chunks(1024){self.source.literal_checkpoint()?;let _=part;}self.out.write_str(text)}}
pub(super) fn constant_display<S:Source>(source:&S,value:ConstantView<'_>,out:&mut DebugSink<'_>)->Result<(),S::Error>{let _frame=source.frame()?;match value{
 ConstantView::Null=>out.push_str("null"),ConstantView::Prefab(path)=>{for part in path.split('/').filter(|part|!part.is_empty()){let _frame=source.frame()?;out.push('/');out.push_str(part)}},ConstantView::Procedure{owner,kind,name}=>{for part in owner.split('/').filter(|part|!part.is_empty()).chain(kind).chain(std::iter::once(name)){let _frame=source.frame()?;out.push('/');out.push_str(part)}},
 ConstantView::Literal(value)=>{let raw=value.as_str();if raw=="null"{out.push_str("null")}else if raw.starts_with('\''){out.push('\'');if !value.write_pinned_resource_text(&mut Plain{out,source}).map_err(|_|S::Error::from("original resource display unavailable"))?{return Err("resource primary value unavailable".into())}out.push('\'');}else if raw.as_bytes().first().is_some_and(|b|b.is_ascii_digit()||*b==b'.'){let _scratch=source.scratch(raw.len().checked_mul(4).and_then(|n|n.checked_add(64)).ok_or("original numeric display scratch overflow")?)?;let number=match dm_syntax::numeric_form::numeric_form(raw).map_err(|_|S::Error::from("invalid original numeric display"))?{dm_syntax::numeric_form::NumericForm::Integer(n)=>n as f32,dm_syntax::numeric_form::NumericForm::Float=>{let normalized:String=raw.chars().filter(|ch|*ch!='_').collect();if normalized.ends_with("#INF"){f32::INFINITY}else if normalized.ends_with("#IND"){f32::NAN}else{normalized.parse::<f32>().map_err(|_|S::Error::from("invalid original float display"))?}}};display_float(number,out).map_err(|_|S::Error::from("original numeric display output failed"))?;}else{let mut flags=TextFlags{source,remaining:1024,quote:false,newline:false,terminator:false,last_quote:false};if !value.write_pinned_static_text(&mut flags).map_err(|_|S::Error::from("original static display unavailable"))?{return Err("original static display has runtime interpolation".into())}let(open,close)=if flags.terminator{("@@","@")}else if flags.quote||flags.newline{("{\"","\"}")}else{("\"","\"")};out.push_str(open);if !value.write_pinned_static_text(&mut Plain{out,source}).map_err(|_|S::Error::from("original static display unavailable"))?{return Err("original static display changed".into())}out.push_str(close);}}
 }Ok(())}
