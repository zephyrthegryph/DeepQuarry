//! SAME pinned Preprocessor::real_next Function substitution judge.
//! Input tokens MUST come from the actual current native lexical transport.
//! This module owns no lexer, environment prepass, source/model/cache or fallback.
//! Function arguments are RAW tokens: only the final expansion frame rescans them.
use super::funded_storage::{MacroRows, MacroTokenRows};
use dm_syntax::SettingAdmission;
use std::io;
#[derive(Clone,Copy)]pub(super) enum TokenView<'a>{Ident(&'a str,bool),Int(i32),Hash,Paste,Other}
pub(super) enum JoinTail<'a>{Ident(&'a str),Int(i32)}
/// Allocation/formatting adapter, not a semantic lookup. Native implementation
/// must keep real lexical Int/Float/string-part facts and exact original Display;
/// a raw whole String token cannot masquerade as interpolation-part evidence.
pub(super) trait Tokens{
 type Token;
 fn view<'a>(&self,token:&'a Self::Token)->TokenView<'a>;
 fn duplicate(&mut self,token:&Self::Token,a:&SettingAdmission<'_>)->io::Result<Self::Token>;
 fn join_ident(&mut self,first:&str,last:JoinTail<'_>,whitespace:bool,a:&SettingAdmission<'_>)->io::Result<Self::Token>;
 fn stringify(&mut self, raw: &MacroTokenRows<Self::Token>, a: &SettingAdmission<'_>) -> io::Result<Self::Token>;
 fn comma(&mut self,a:&SettingAdmission<'_>)->io::Result<Self::Token>;
}
/// Exact old source diagnostics are emitted by the actual preprocessor owner;
/// these borrowed DATA cases allocate no diagnostic text or authority here.
pub(super) enum SubstitutionFailure<'a,T>{NonArgument(&'a str),NonIdent(&'a T),Eof}
fn poll(a:&SettingAdmission<'_>)->io::Result<()>{a.checkpoint().map_err(|e|a.take_operational_error().unwrap_or(e))}
fn copied<'t, F: Tokens>(
    out: &mut MacroTokenRows<F::Token>,
    tokens: impl Iterator<Item = &'t F::Token>,
    f: &mut F,
    a: &SettingAdmission<'_>,
) -> io::Result<()> where F::Token: 't {
    for token in tokens {
        poll(a)?;
        out.push(f.duplicate(token, a)?, a)?;
    }
    Ok(())
}
/// Preserve actual variadic adjustment and wrong-arity ordering BEFORE the
/// substitution judge. The parser supplied raw empty argument is NOT invented or
/// removed here; this has exactly the pinned algorithm's input contract.
pub(super) fn arguments_using<F: Tokens>(
    params: &[impl AsRef<str>],
    mut raw: MacroRows<MacroTokenRows<F::Token>>,
    variadic: bool,
    f: &mut F,
    a: &SettingAdmission<'_>,
) -> io::Result<Result<MacroRows<MacroTokenRows<F::Token>>, ()>> {
    poll(a)?;
    let pack = variadic && raw.len() > params.len();
    let append_empty = variadic && !pack && raw.len().checked_add(1) == Some(params.len());
    let count = if pack {
        params.len()
    } else {
        raw.len().checked_add(usize::from(append_empty)).ok_or(io::ErrorKind::OutOfMemory)?
    };
    if count != params.len() {
        return Ok(Err(()));
    }
    if !pack {
        // These are still raw arguments, with no expansion or origin changes.
        // Only emitted substitution copies take the invocation origin.
        if append_empty {
            raw.push(MacroTokenRows::new(a)?, a)?;
        }
        return Ok(Ok(raw));
    }
    let ordinary = params.len().checked_sub(1).ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "original variadic signature lacks actual final parameter")
    })?;
    let mut raw = raw.into_cursor();
    let mut out = MacroRows::new(a)?;
    for _ in 0..ordinary {
        let arg = raw.next().ok_or(io::ErrorKind::InvalidData)?;
        out.push(arg, a)?;
    }
    let mut packed = raw.next().ok_or(io::ErrorKind::InvalidData)?;
    while let Some(arg) = raw.next() {
        packed.push(f.comma(a)?, a)?;
        let mut arg = arg.into_cursor();
        while let Some(token) = arg.next() {
            packed.push(token, a)?;
        }
    }
    out.push(packed, a)?;
    Ok(Ok(out))
}
/// Exact replacement order from pinned real_next: substitution, paste, stringify.
/// No environment lookup occurs here, including forwarding and unused arguments.
/// Therefore a fatal final-output consumer can stop before a future real lookup.
pub(super) fn substitute_using<'a,F:Tokens>(params:&[impl AsRef<str>],args:&[MacroTokenRows<F::Token>],replacement:&'a[F::Token],f:&mut F,a:&SettingAdmission<'_>)->io::Result<Result<MacroTokenRows<F::Token>,SubstitutionFailure<'a,F::Token>>>{
 poll(a)?;if args.len()!=params.len(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"original replacement arguments have not passed actual arity adjustment"))}
 let mut out=MacroTokenRows::new(a)?;let mut at=0;while let Some(token)=replacement.get(at){poll(a)?;at+=1;match f.view(token){
 TokenView::Ident(name,_)=>{if let Some(i)=params.iter().position(|p|p.as_ref()==name){copied(&mut out,args[i].iter(),f,a)?;}else{out.push(f.duplicate(token,a)?,a)?;}},
 TokenView::Paste=>{let first=out.pop();let second=replacement.get(at);if second.is_some(){at+=1;}
  match(first,second){
   (Some(first),Some(second))=>{if let TokenView::Ident(first_name,_ws1)=f.view(&first){if let TokenView::Ident(param_name,ws)=f.view(second){if let Some(i)=params.iter().position(|p|p.as_ref()==param_name){let mut arg=args[i].iter();if let Some(head)=arg.next(){match f.view(head){TokenView::Ident(name,ws)=>out.push(f.join_ident(first_name,JoinTail::Ident(name),ws,a)?,a)?,TokenView::Int(n)=>out.push(f.join_ident(first_name,JoinTail::Int(n),ws,a)?,a)?,_=>{out.push(first,a)?;out.push(f.duplicate(head,a)?,a)?;}}copied(&mut out,arg,f,a)?;}}else{out.push(f.join_ident(first_name,JoinTail::Ident(param_name),ws,a)?,a)?;}continue}}
    out.push(first,a)?;if let TokenView::Ident(name,_)=f.view(second){if let Some(i)=params.iter().position(|p|p.as_ref()==name){copied(&mut out,args[i].iter(),f,a)?;}else{out.push(f.duplicate(second,a)?,a)?;}}else{out.push(f.duplicate(second,a)?,a)?;}
   },
   (first,Some(second))=>{if let Some(first)=first{out.push(first,a)?;}if let TokenView::Ident(name,_)=f.view(second){if let Some(i)=params.iter().position(|p|p.as_ref()==name){copied(&mut out,args[i].iter(),f,a)?;}else{out.push(f.duplicate(second,a)?,a)?;}}else{out.push(f.duplicate(second,a)?,a)?;}},
   (first,None)=>{if let Some(first)=first{out.push(first,a)?;}},
  }
 },
 TokenView::Hash=>{let Some(next)=replacement.get(at)else{return Ok(Err(SubstitutionFailure::Eof))};at+=1;let TokenView::Ident(name,_)=f.view(next)else{return Ok(Err(SubstitutionFailure::NonIdent(next)))};let Some(i)=params.iter().position(|p|p.as_ref()==name)else{return Ok(Err(SubstitutionFailure::NonArgument(name)))};out.push(f.stringify(&args[i],a)?,a)?;},
 _=>out.push(f.duplicate(token,a)?,a)?,
 }}Ok(Ok(out))
}

#[cfg(test)]mod tests{
 use super::*;use super::super::funded_storage::MacroText;use std::sync::{atomic::{Ordering}};
 enum Text{Borrowed(&'static str),Owned(MacroText)}impl Text{fn get(&self)->&str{match self{Self::Borrowed(s)=>s,Self::Owned(s)=>s.as_str()}}}
 enum Kind{Ident(bool),Int(i32),Float(f32),Hash,Paste,Other,String}
 struct Token{kind:Kind,text:Text}
 struct Factory{joined:usize,stringified:usize}
 impl Tokens for Factory{type Token=Token;
  fn view<'a>(&self,t:&'a Token)->TokenView<'a>{match t.kind{Kind::Ident(ws)=>TokenView::Ident(t.text.get(),ws),Kind::Int(n)=>TokenView::Int(n),Kind::Hash=>TokenView::Hash,Kind::Paste=>TokenView::Paste,_=>TokenView::Other}}
  fn duplicate(&mut self,t:&Token,a:&SettingAdmission<'_>)->io::Result<Token>{poll(a)?;let text=match &t.text{Text::Borrowed(s)=>Text::Borrowed(s),Text::Owned(s)=>{let mut n=MacroText::new(a)?;n.push_str(s.as_str(),a)?;Text::Owned(n)}};let kind=match t.kind{Kind::Ident(ws)=>Kind::Ident(ws),Kind::Int(n)=>Kind::Int(n),Kind::Float(n)=>Kind::Float(n),Kind::Hash=>Kind::Hash,Kind::Paste=>Kind::Paste,Kind::Other=>Kind::Other,Kind::String=>Kind::String};Ok(Token{kind,text})}
  fn join_ident(&mut self,first:&str,last:JoinTail<'_>,ws:bool,a:&SettingAdmission<'_>)->io::Result<Token>{let mut n=MacroText::new(a)?;n.push_str(first,a)?;match last{JoinTail::Ident(s)=>n.push_str(s,a)?,JoinTail::Int(i)=>{let s=i.to_string();n.push_str(&s,a)?;}}self.joined+=1;Ok(Token{kind:Kind::Ident(ws),text:Text::Owned(n)})}
  fn stringify(&mut self,raw:&MacroTokenRows<Token>,a:&SettingAdmission<'_>)->io::Result<Token>{let mut text=MacroText::new(a)?;for(index,t)in raw.iter().enumerate(){if index>0{text.push(' ',a)?;}text.push_str(t.text.get(),a)?;}self.stringified+=1;Ok(Token{kind:Kind::String,text:Text::Owned(text)})}
  fn comma(&mut self,a:&SettingAdmission<'_>)->io::Result<Token>{poll(a)?;Ok(other(","))}
 }
 fn ident(text:&'static str)->Token{Token{kind:Kind::Ident(false),text:Text::Borrowed(text)}}fn other(text:&'static str)->Token{Token{kind:Kind::Other,text:Text::Borrowed(text)}}fn paste()->Token{Token{kind:Kind::Paste,text:Text::Borrowed("##")}}fn row(tokens:impl IntoIterator<Item=Token>,a:&SettingAdmission<'_>)->MacroTokenRows<Token>{let mut row=MacroTokenRows::new(a).unwrap();for t in tokens{row.push(t,a).unwrap();}row}
 fn spell(row:&MacroTokenRows<Token>)->Vec<&str>{row.iter().map(|t|t.text.get()).collect()}
 #[test]fn raw_forwarded_unused_argument_is_not_preexpanded_or_inspected_as_a_macro(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut f=Factory{joined:0,stringified:0};let args=[row([ident("TOO_FEW"),other("("),Token{kind:Kind::Int(1),text:Text::Borrowed("1")},other(")")],&a)];let replacement=[other(","),ident("x")];let params=["x".to_owned()];let out=substitute_using(&params,&args,&replacement,&mut f,&a).unwrap().ok().unwrap();assert_eq!(spell(&out),[",","TOO_FEW","(","1",")"]);assert_eq!((f.joined,f.stringified),(0,0));drop((out,args));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn paste_preserves_actual_ident_int_empty_and_nonident_tail_rules(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut f=Factory{joined:0,stringified:0};let params=["x".to_owned()];for(raw,wanted,joins)in[(vec![ident("tail"),other("(")],vec!["pretail","("],1),(vec![Token{kind:Kind::Int(2147483647),text:Text::Borrowed("2147483647")}],vec!["pre2147483647"],1),(vec![Token{kind:Kind::Float(1.0),text:Text::Borrowed("1")}],vec!["pre","1"],0),(vec![],vec![],0)]{let args=[row(raw,&a)];let replacement=[ident("pre"),paste(),ident("x")];let before=f.joined;let out=substitute_using(&params,&args,&replacement,&mut f,&a).unwrap().ok().unwrap();assert_eq!(spell(&out),wanted);assert_eq!(f.joined-before,joins);}assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]fn stringify_consumes_raw_token_display_and_diagnostics_stay_borrowed_without_environment_lookups(){let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=SettingAdmission::new(&used,1<<20,&||Ok(()));let mut f=Factory{joined:0,stringified:0};let params=["x".to_owned()];let args=[row([ident("F"),other("("),other(")")],&a)];let hash=||Token{kind:Kind::Hash,text:Text::Borrowed("#")};let replacement=[hash(),ident("x")];let out=substitute_using(&params,&args,&replacement,&mut f,&a).unwrap().ok().unwrap();assert_eq!(spell(&out),["F ( )"]);assert!(matches!(out.iter().next().unwrap().kind,Kind::String));let bad=[hash(),ident("absent")];assert!(matches!(substitute_using(&params,&args,&bad,&mut f,&a).unwrap(),Err(SubstitutionFailure::NonArgument("absent"))));let bad=[hash(),other("+")];assert!(matches!(substitute_using(&params,&args,&bad,&mut f,&a).unwrap(),Err(SubstitutionFailure::NonIdent(_))));let bad=[hash()];assert!(matches!(substitute_using(&params,&args,&bad,&mut f,&a).unwrap(),Err(SubstitutionFailure::Eof)));drop((out,args));assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());}
 #[test]
 fn variadic_and_paste_and_stringify_cross_page_edges_without_losing_order() {
    let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
    let mut f=Factory{joined:0,stringified:0};
    let params=["tail"];
    let mut raw=MacroRows::new(&a).unwrap();
    raw.push(row(std::iter::once(ident("head")).chain((0..127).map(|_| other("a"))),&a),&a).unwrap();
    raw.push(row([ident("second"),other("b")],&a),&a).unwrap();
    let packed=arguments_using(&params,raw,true,&mut f,&a).unwrap().ok().unwrap();
    let packed_tokens=spell(&packed.as_slice()[0]);
    assert_eq!(&packed_tokens[126..],["a","a",",","second","b"]);

    // Exactly one token on the next output page must be popped by ##.
    let mut replacement:Vec<_>=(0..128).map(|_| other("pad")).collect();
    replacement.extend([ident("pre"),paste(),ident("tail"),
        Token{kind:Kind::Hash,text:Text::Borrowed("#")},ident("tail")]);
    let out=substitute_using(&params,packed.as_slice(),&replacement,&mut f,&a).unwrap().ok().unwrap();
    let out_tokens=spell(&out);
    assert_eq!(out_tokens[127],"pad");
    assert_eq!(out_tokens[128],"prehead");
    assert_eq!(&out_tokens[256..259],[",","second","b"]);
    assert_eq!(out_tokens[259],packed_tokens.join(" "));
    assert_eq!((f.joined,f.stringified),(1,1));
    drop((out,packed));
    assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn original_variadic_join_and_missing_empty_tail_keep_parameter_order(){
    let used=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();
    let a=SettingAdmission::new(&used,1<<20,&||Ok(()));
    let mut f=Factory{joined:0,stringified:0};
    let params=["first","tail"];
    let args=|names:&[&'static str]|{
        let mut args=MacroRows::new(&a).unwrap();
        for name in names { args.push(row([ident(name)],&a),&a).unwrap(); }
        args
    };
    let normalized=arguments_using(&params,args(&["a","b","c"]),true,&mut f,&a).unwrap().ok().unwrap();
    assert_eq!(spell(&normalized.as_slice()[0]),["a"]);
    assert_eq!(spell(&normalized.as_slice()[1]),["b",",","c"]);
    let empty=arguments_using(&params,args(&["a"]),true,&mut f,&a).unwrap().ok().unwrap();
    assert!(empty.as_slice()[1].iter().next().is_none());
    assert!(arguments_using(&params,args(&["a"]),false,&mut f,&a).unwrap().is_err());
    drop((normalized,empty));
    assert_eq!(used.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
}
