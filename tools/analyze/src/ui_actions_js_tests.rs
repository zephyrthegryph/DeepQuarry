 use super::*;use crate::key_policy_control::Control;
 #[path="../fixtures/original_policies/ui_actions_source_scanner.rs"]mod original;
 struct Probe{left:usize,polls:usize,fail:usize}
 impl Control for Probe{type Error=std::io::Error;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.polls==self.fail{Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}fn reserve(&mut self,n:usize)->Result<(),Self::Error>{self.left=self.left.checked_sub(n).ok_or_else(||std::io::Error::from(std::io::ErrorKind::OutOfMemory))?;Ok(())}fn overflow(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}fn allocation_failed(&mut self)->Self::Error{std::io::ErrorKind::OutOfMemory.into()}}
 fn work()->Probe{Probe{left:64*1024*1024,polls:0,fail:usize::MAX}}
 #[test]fn complete_tsx_scanner_matches_frozen_original_for_unicode_nested_and_malformed_inputs(){
  for text in ["", "act(variable, {a:1})", "act('go', { speed: 1, 'ref': value, shorthand, nested: {a:[1,2]}, f(x){} });", "act(`go`, { ...params }); act('two', {[dynamic]: 1});", "act(`raw${value}`, {a:1}); act('last', variable);", "// act('comment', {kept:1})\nobj.act('member', {x:1}); fooact('excluded'); $act('excluded');", "act('a', {x: /* , ] */ 2, y:'a,b', z:`a${{x:[1,2]}}b`});", "act('unterminated", "act('a', {x:1]); act('next')", "λ\n\nact('𐀀', {名:1}); act('go', {key:1, key:2, nested:{a:1}})", "act(\"a\", {a:1, malformed!}); act('missing', ); act('empty')"]{
   let expected=original::original_tsx_observation(text);let compatibility=serde_json::to_value(tsx_calls(text)).unwrap();let actual=serde_json::to_value(tsx_calls_using(text,&mut work()).unwrap()).unwrap();assert_eq!(compatibility,expected,"legacy extraction: {text:?}");assert_eq!(actual,expected,"controlled extraction: {text:?}");
  }
 }
 #[test]fn real_scanner_operational_failure_discards_every_preceding_row(){let text="act('first', {key:1}); act('second', {nested:{more:[1,2,3]}});";let mut succeeded=work();let expected=tsx_calls_using(text,&mut succeeded).unwrap();assert_eq!(expected.len(),2);for fail in 1..=succeeded.polls{let mut c=Probe{left:64*1024*1024,polls:0,fail};let error=tsx_calls_using(text,&mut c).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450),"checkpoint {fail}");}}
 #[test]fn real_scanner_quota_refuses_without_partial_result_and_next_operation_recovers(){let text="act('first', {key:1}); act('second', {nested:{more:[1,2,3]}});";let mut c=Probe{left:1,polls:0,fail:usize::MAX};assert_eq!(tsx_calls_using(text,&mut c).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(tsx_calls_using(text,&mut work()).unwrap(),tsx_calls(text));}

 #[test]fn tsx_scanner_exact_original_matrix_preserves_nonsemantic_lexical_quirks(){
  let prefixes=["", "λ\n", "// ", "obj.", "my", "$", "/* before */ "];
  let actions=["'go'", "\"go\"", "`go`", "`go${x}`", "dynamic", "'unterminated"];
  let arguments=["", ", {}", ", {a:1,a:2}", ", variable", ", {...x}", ", {[x]:1}", ", {q:`x${{a:[1,2]}}`, z:3}", ", {x:'\\\" , ]',bad!}"];
  for prefix in prefixes {for action in actions {for args in arguments {let text=format!("{prefix}act({action}{args});\nact('later',{{kept:1}});");let expected=original::original_tsx_observation(&text);assert_eq!(serde_json::to_value(tsx_calls_using(&text,&mut work()).unwrap()).unwrap(),expected,"{text:?}");}}}
 }

 #[test]fn borrowed_raw_proc_headers_keep_original_grammar_order_without_a_tree(){
  let file=crate::tree::SourceFile::from_text("code/fixture.dm","/proc/first(value)\n    return value\n/datum/fixture/proc/second(\n    value as num,\n    obj/item/thing = null\n)\n    return thing\nrelative(value)\n    return value\n");let mut actual=Vec::new();crate::dm::dx::visit_proc_headers_using(&file,&mut work(),|p,_|{actual.push((p.rel.to_owned(),p.path.to_owned(),p.name.to_owned(),p.params.to_owned(),p.line,p.body_start,p.body_len));Ok(())}).unwrap();
  assert_eq!(actual,vec![("code/fixture.dm".into(),"/".into(),"first".into(),"value".into(),1,2,1),("code/fixture.dm".into(),"/datum/fixture".into(),"second".into()," value as num, obj/item/thing = null ".into(),3,7,1)]);
  let old=crate::dm::dx::procs_in(&file);assert_eq!(old.len(),2);assert_eq!(old[1].params,vec!["value","thing"]);
  let mut failure=Probe{left:64*1024*1024,polls:0,fail:5};assert_eq!(crate::dm::dx::visit_proc_headers_using(&file,&mut failure,|_,_|Ok(())).unwrap_err().raw_os_error(),Some(1450));
 }
