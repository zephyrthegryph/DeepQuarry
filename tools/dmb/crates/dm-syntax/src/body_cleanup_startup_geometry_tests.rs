//! Resource bounds against the SAME ordinary parser product. No source or
//! Original completion authority is issued by these scalar geometry controls.
use super::*;
use crate::{Span,TokenKind};

fn geometry(source:&str,a:&SettingAdmission<'_>)->crate::BodyCleanupStartupGeometry{
 let ast=crate::parse(source);assert!(ast.diagnostics.is_empty(),"structural fixture: {:?}",ast.diagnostics);
 let lexical=crate::lex_spans(source);
 crate::body_cleanup_startup_geometry(&ast.items[0].children,lexical.tokens.iter().map(|t|(t.kind,t.span,t.text(source))),a).unwrap()
}
fn check_bound(source:&str,allow_recovery:bool){
 let fixed=SettingChargeCounter::root_allocation_bytes();let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::with_stack_allowance(&counter,32<<20,1<<20,&||Ok(()));
 let bound=geometry(source,&a);let parsed=body(source);
 if !allow_recovery{assert!(parsed.diagnostics.is_empty(),"body fixture: {:?}\n{source}",parsed.diagnostics);}
 let (statements,expressions)={let collected=collect(&parsed,&a).unwrap();let mut expressions=0usize;
  for root in collected.roots.as_slice(){let measured=crate::setting_prepare::prepare_body_measure(root,&a).unwrap();expressions=expressions.checked_add(measured.cleanup_nodes).unwrap();}
  (collected.statements,expressions)
 };
 let measured=statements.checked_mul(4*size_of::<Vec<Statement>>()).unwrap().checked_add(expressions.checked_mul(4*(size_of::<Expr>()+size_of::<SharedSettingRetention>())).unwrap()).unwrap();
 assert!(measured<=bound.bytes(),"ordinary parser cleanup {measured} exceeds prepaid token/item geometry {}: {source}",bound.bytes());
 assert_eq!(counter.load(Ordering::Acquire),fixed,"all preflight/measurement scratch actually retired");
 drop_body_literal_syntax(parsed,None);assert_eq!(counter.load(Ordering::Acquire),fixed);
}

#[test]fn startup_geometry_covers_actual_constructor_control_and_local_node_products(){
 for source in [
  "/proc/p()\n    return new\n",
  "/proc/p()\n    return f(,,,1,,2)\n",
  "/proc/p()\n    return new(,,,1,,2)\n",
  "/proc/p()\n    return ()\n",
  "/proc/p()\n    return list(1,2,3)[1] + (a ? b : c)\n",
  "/proc/p()\n    var/list/a[1+2], b[3+4]\n    var/x=1, y=2, z=3\n    return x\n",
  "/proc/p()\n    if(a) return 1\n    else if(b) return 2\n    else return 3\n",
  "/proc/p()\n    spawn(1) return 2\n    while(a) break\n    label: return 3\n",
  "/proc/p()\n    for(var/i=1 to 3 step 1)\n        f(i)\n    for(var/j=0; j<3; j++)\n        f(j)\n",
  "/proc/p()\n    switch(x)\n        if(1,2 to 4) return 5\n        else return 6\n",
  "/proc/p()\n    try\n        f()\n    catch(var/e)\n        throw e\n",
 ]{check_bound(source,true);}
 // Real successful ordinary products keep this test falsifiable even when
 // some compatibility-only edge fixtures legitimately produce diagnostics.
 check_bound("/proc/p()\n    if(a)\n        return f(1,2,3)\n    return 0\n",false);
}

#[test]fn startup_geometry_stress_disjoint_commas_nested_nodes_and_recovering_input(){
 for width in [1usize,2,7,31,127]{
  let args=(0..width).map(|i|format!("({i}+1)")).collect::<Vec<_>>().join(",");
  check_bound(&format!("/proc/p()\n    return f({args})\n"),false);
  let locals=(0..width).map(|i|format!("x{i}={i}")).collect::<Vec<_>>().join(",");
  check_bound(&format!("/proc/p()\n    var/{locals}\n    return 0\n"),true);
 }
 for depth in [1usize,2,8,24,48]{
  let expr=format!("{}1{}","(".repeat(depth),")".repeat(depth));check_bound(&format!("/proc/p()\n    return {expr}\n"),false);
  let mut source="/proc/p()\n".to_owned();for n in 0..depth{source.push_str(&"    ".repeat(n+1));source.push_str("if(a)\n");}source.push_str(&"    ".repeat(depth+1));source.push_str("return 1\n");check_bound(&source,false);
 }
 for source in ["/proc/p()\n    return (1 + )\n", "/proc/p()\n    if(a)\n        return 1 +\n", "/proc/p()\n    var/x=1,y=\n"]{check_bound(source,true);}
}

#[test]fn startup_geometry_long_comments_and_literals_do_not_multiply_ordinary_nodes(){
 let fixed=SettingChargeCounter::root_allocation_bytes();let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::with_stack_allowance(&counter,16<<20,1<<20,&||Ok(()));
 let short="/proc/p()\n    return 1\n";
 let comment=format!("/proc/p()\n    // {}\n    return 1\n","comment text ".repeat(32768));
 assert_eq!(geometry(short,&a).bytes(),geometry(&comment,&a).bytes(),"comment bytes add neither ordinary Expr nor Statement worklist nodes");
 let small="/proc/p()\n    return \"literal\"\n";
 let large=format!("/proc/p()\n    return \"{}\"\n","literal text ".repeat(16384));
 assert_eq!(geometry(small,&a).bytes(),geometry(&large,&a).bytes(),"literal raw length does not introduce ordinary cleanup nodes");
 check_bound(&large,false);assert_eq!(counter.load(Ordering::Acquire),fixed);
}

#[test]fn startup_geometry_allows_real_small_body_with_long_comment_under_tight_unchanged_cap(){
 let source=format!("/proc/p()\n    // {}\n    return 1\n","ordinary comment ".repeat(32768));let cap=1<<20;
 assert!(source.len().checked_mul(512).unwrap()+8192>cap,"old source-width startup envelope genuinely exceeds this cap");
 let fixed=SettingChargeCounter::root_allocation_bytes();let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::with_stack_allowance(&counter,cap,cap,&||Ok(()));let bound=geometry(&source,&a);assert!(bound.bytes()<cap/4);
 let cleanup=a.reserve(bound.bytes()).unwrap();let prepared=prepare_body_literal_syntax(body(&source),cleanup,&a).unwrap();let(parsed,literals)=prepared.into_parts();assert!(matches!(parsed.statements.as_slice(),[Statement{kind:StatementKind::Return(Some(_)),..}]));
 drop_body_literal_syntax(parsed,Some(literals));assert_eq!(counter.load(Ordering::Acquire),fixed);
}

#[test]fn startup_geometry_first_io_cancel_and_foreign_counter_cleanup_preserve_actual_channels(){
 let source="/proc/p()\n    return 1 + 2\n";let ast=crate::parse(source);let lexical=crate::lex_spans(source);let fixed=SettingChargeCounter::root_allocation_bytes();
 for (raw,wanted) in [(Some(1450),io::ErrorKind::Other),(None,io::ErrorKind::Interrupted)]{
  let counter=SettingChargeCounter::try_new(fixed).unwrap();let stop=||match raw{Some(code)=>Err(io::Error::from_raw_os_error(code)),None=>Err(io::Error::new(wanted,"actual expired operation"))};let a=SettingAdmission::new(&counter,1<<20,&stop);
  let error=crate::body_cleanup_startup_geometry(&ast.items[0].children,lexical.tokens.iter().map(|t|(t.kind,t.span,t.text(source))),&a).unwrap_err();
  if let Some(code)=raw{assert_eq!(error.raw_os_error(),Some(code));}else{assert_eq!(error.kind(),wanted);}assert_eq!(counter.load(Ordering::Acquire),fixed,"no preflight scratch acquired after first stop");
 }
 let first=SettingChargeCounter::try_new(fixed).unwrap();let second=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&first,4<<20,&||Ok(()));let b=SettingAdmission::new(&second,4<<20,&||Ok(()));let bound=geometry(source,&a);
 let foreign=b.reserve(bound.bytes()).unwrap();assert!(!a.matches_lease_domain(&foreign));let prepared=prepare_body_literal_syntax(body(source),foreign,&a).unwrap();assert_eq!(second.load(Ordering::Acquire),fixed,"foreign cleanup retired rather than reused as this counter's payment");assert!(first.load(Ordering::Acquire)>fixed,"actual prepared payload and cleanup funded by own counter");drop(prepared);assert_eq!(first.load(Ordering::Acquire),fixed);
}

#[test]fn startup_geometry_each_preflight_checkpoint_keeps_first_raw_io_and_late_cancel(){
 let source="/proc/p()\n    if(a)\n        return f(1,2,3)\n    return 4\n";let ast=crate::parse(source);let lexical=crate::lex_spans(source);let fixed=SettingChargeCounter::root_allocation_bytes();let mut reached=0;
 for at in 1..=32{
  let count=std::cell::Cell::new(0usize);let stop=||{let n=count.get()+1;count.set(n);if n==at{Err(io::Error::from_raw_os_error(1450))}else{Ok(())}};let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&counter,1<<20,&stop);
  let result=crate::body_cleanup_startup_geometry(&ast.items[0].children,lexical.tokens.iter().map(|t|(t.kind,t.span,t.text(source))),&a);
  if count.get()>=at{reached+=1;assert_eq!(result.unwrap_err().raw_os_error(),Some(1450),"first actual failure at checkpoint {at}, including Worklist allocation windows");}else{result.unwrap();}
  assert_eq!(counter.load(Ordering::Acquire),fixed,"scratch retires at failed checkpoint {at}");
 }
 assert!(reached>=16,"actual body must reach enough distinct worklist/token checkpoints");
 let count=std::cell::Cell::new(0usize);let cancel=||{let n=count.get()+1;count.set(n);if n==9{Err(io::Error::new(io::ErrorKind::Interrupted,"late actual cancellation"))}else{Ok(())}};let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&counter,1<<20,&cancel);
 let error=crate::body_cleanup_startup_geometry(&ast.items[0].children,lexical.tokens.iter().map(|t|(t.kind,t.span,t.text(source))),&a).unwrap_err();assert_eq!(error.kind(),io::ErrorKind::Interrupted);assert_eq!(error.to_string(),"late actual cancellation");assert_eq!(counter.load(Ordering::Acquire),fixed);
}


#[test]fn startup_geometry_only_duplicates_actual_square_windows_and_fails_closed(){
 let fixed=SettingChargeCounter::root_allocation_bytes();let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&counter,1<<20,&||Ok(()));
 let geometry=|tokens:&[(crate::TokenKind,&str)]|crate::body_cleanup_startup_geometry(&[],tokens.iter().enumerate().map(|(i,(kind,text))|(*kind,crate::Span::new(i,i+1),*text)),&a).unwrap().bytes();
 use crate::TokenKind::{Number as N,Operator as O,Punctuation as P,String as S,Resource as R,Ident as I};
 let slot=4*(size_of::<Expr>()+size_of::<SharedSettingRetention>());
 assert_eq!(geometry(&[(N,"1"),(O,"+"),(N,"2")]),8192+slot,"numeric leaves have no future cleanup entry; only the operator stays funded");
 assert_eq!(geometry(&[(I,"a"),(P,"["),(N,"1"),(P,"]")]),8192+4*slot,"opening/closing keep the conservative duplicate payment; numeric child drops directly");
 assert_eq!(geometry(&[(I,"a"),(P,"?["),(N,"1"),(P,"]")]),8192+4*slot,"native safe-index brackets stay doubled while numeric child drops directly");
 assert_eq!(geometry(&[(S,"["),(R,"]")]),8192+2*slot,"literal spelling cannot open or close syntax windows");
 for tokens in [vec![(P,"[")],vec![(P,"]")],vec![(P,"["),(P,"("),(N,"1")],vec![(P,"("),(P,"]")]]{
  assert_eq!(geometry(&tokens),8192+2*tokens.len()*slot,"malformed square windows retain the whole old double-token bound");
 }
 assert_eq!(geometry(&[(P,"("),(N,"1")]),8192+slot,"unclosed parentheses do not duplicate dimensions or queue numeric leaves");
 assert_eq!(geometry(&[(P,"}"),(N,"1")]),8192+slot,"unmatched braces do not duplicate dimensions or queue numeric leaves");
 assert_eq!(geometry(&[(P,"["),(P,"("),(P,"]"),(P,")")]),8192+7*slot,"mismatched other groups remain fully covered inside the only duplicable square window");
 assert_eq!(counter.load(Ordering::Acquire),fixed,"preflight scratch and credit physically retire");
}

#[test]fn startup_geometry_square_dimension_products_and_nonarray_constructors_fit_actual_parser(){
 for source in [
  "/proc/p()\n    var/list/a[f(1+2)][g(3*4)]\n    return a\n",
  "/proc/p()\n    var/list/a[f(1+2)] = list(3,4)\n    return a[1]\n",
  "/proc/p()\n    var/a[f(1 + 2)]\n    return 0\n",
  "/proc/p()\n    return list(new, new(), new /datum(), (), f(,,,1), pick(1;2,3;4))\n",
  "/proc/p()\n    return input(\"question\") as num in list(1,2)\n",
 ]{check_bound(source,true);}
 for n in [1usize,4,16,64]{
  let dimension=(0..n).map(|i|format!("({i}+1)")).collect::<Vec<_>>().join("+");
  check_bound(&format!("/proc/p()\n    var/list/a[{dimension}]\n    return a[1]\n"),true);
 }
}


#[test]fn startup_geometry_actual_identifier_heavy_and_dimension_nodes_keep_payload_and_bounds(){
 for count in[1usize,4,16,64]{
  let arguments=(0..count).map(|i|format!("value{i}")).collect::<Vec<_>>().join(",");
  check_bound(&format!("/proc/p()\n    return dispatch({arguments})\n"),false);
  check_bound(&format!("/proc/p()\n    var/list/local[dispatch({arguments})]\n    return local[index]\n"),true);
 }
 for source in[
  "/proc/p()\n    return new\n",
  "/proc/p()\n    return null\n",
  "/proc/p()\n    return receiver in values\n",
  "/proc/p()\n    return input(\"question\") as num in list(1,2)\n",
  "/proc/p()\n    return 1 to 3\n",
 ]{check_bound(source,true);}
}

#[test]fn serialized_header_peak_covers_actual_multiroot_calls_inline_and_comma_local_products(){
 for source in[
  "/proc/p()\n    call(a+b,c+d)\n    call(e+f,g+h)\n    return call(i+j,k+l)\n",
  "/proc/p()\n    var/a=list(1,2,3), b=list(4,5,6)\n    if(a) return list(a,b)\n    else return null\n",
  "/proc/p()\n    for(var/i=0; i<3; i++)\n        call(i,1,2)\n    try\n        call(1,2,3)\n    catch(var/e)\n        throw e\n",
 ]{
  let fixed=SettingChargeCounter::root_allocation_bytes();let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::with_stack_allowance(&counter,32<<20,1<<20,&||Ok(()));let ast=crate::parse(source);assert!(ast.diagnostics.is_empty());let lexical=crate::lex_spans(source);
  let actual=crate::original_body_cleanup_peak_geometry(&ast.items[0].children,lexical.tokens.iter().map(|t|(t.kind,t.span,t.text(source))),&a).unwrap();let parsed=body(source);let collected=collect(&parsed,&a).unwrap();let mut peak=0usize;
  for root in collected.roots.as_slice(){peak=peak.max(crate::setting_prepare::prepare_body_measure(root,&a).unwrap().cleanup_nodes);}
  let needed=4*(collected.statements*size_of::<Vec<Statement>>()+peak*(size_of::<Expr>()+size_of::<SharedSettingRetention>()));assert!(needed<=actual.bytes(),"actual destructive peak exceeds genuine header geometry: {source}");drop(collected);drop_body_literal_syntax(parsed,None);assert_eq!(counter.load(Ordering::Acquire),fixed);
 }
}
#[test]fn serialized_header_peak_scales_with_largest_header_and_falls_back_for_interpolation(){
 let fixed=SettingChargeCounter::root_allocation_bytes();let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&counter,32<<20,&||Ok(()));let arguments=std::iter::repeat_n("value",60).collect::<Vec<_>>().join(",");let source=format!("/proc/p()\n{}",std::iter::repeat_n(format!("    call({arguments})\n"),40).collect::<String>());let ast=crate::parse(&source);assert!(ast.diagnostics.is_empty());let lexical=crate::lex_spans(&source);let tokens=||lexical.tokens.iter().map(|t|(t.kind,t.span,t.text(&source)));
 let old=crate::original_body_cleanup_startup_geometry(&ast.items[0].children,tokens(),&a).unwrap();let actual=crate::original_body_cleanup_peak_geometry(&ast.items[0].children,tokens(),&a).unwrap();assert!(actual.bytes()<old.bytes(),"grouped call commas do not create2400 Statements; roots share one cleanup peak");
 // A genuine interpolation marker cannot be certified from lexical spelling.
 // Keep the complete previous bound, including hidden literal expansion.
 let span=Span::new(0,1);let interpolated=[(TokenKind::Interpolation,span,"hidden"),(TokenKind::Punctuation,span,"[")];let old=crate::original_body_cleanup_startup_geometry(&[],interpolated.into_iter(),&a).unwrap();let actual=crate::original_body_cleanup_peak_geometry(&[],interpolated.into_iter(),&a).unwrap();assert_eq!(actual.bytes(),old.bytes());assert_eq!(counter.load(Ordering::Acquire),fixed);
}

#[test]fn serialized_header_peak_empty_foreign_and_noncovering_headers_keep_old_aggregate(){
 let fixed=SettingChargeCounter::root_allocation_bytes();let counter=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&counter,32<<20,&||Ok(()));
 let source="/proc/p()\n    call(a+b,c+d)\n    call(e+f,g+h)\n    return call(i+j,k+l)\n";let ast=crate::parse(source);assert!(ast.diagnostics.is_empty());let lexical=crate::lex_spans(source);let tokens=||lexical.tokens.iter().map(|t|(t.kind,t.span,t.text(source)));
 let old=crate::original_body_cleanup_startup_geometry(&ast.items[0].children,tokens(),&a).unwrap();let good=crate::original_body_cleanup_peak_geometry(&ast.items[0].children,tokens(),&a).unwrap();assert!(good.bytes()<old.bytes(),"control must distinguish real peak from aggregate fallback");
 let empty:Vec<crate::Item>=Vec::new();let mut foreign=ast.items[0].children.clone();for header in &mut foreign{header.header_span.start+=source.len()+100;header.header_span.end+=source.len()+100;}
 let mut empty_header=ast.items[0].children.clone();empty_header[0].header_span.end=empty_header[0].header_span.start;
 let mut outside_end=ast.items[0].children.clone();outside_end.last_mut().unwrap().header_span.end=source.len()+100;
 let mut unseen_tail=ast.items[0].children.clone();unseen_tail.last_mut().unwrap().header_span=Span::new(source.len()+10,source.len()+20);
 let mut trivia_only=ast.items[0].children.clone();trivia_only[0].header_span=Span::new(source.find("    ").unwrap(),source.find("    ").unwrap()+4);
 for(headers,label)in[(&empty,"empty"),(&foreign,"foreign"),(&empty_header,"zero-width"),(&outside_end,"beyond-token-range"),(&unseen_tail,"unseen-tail"),(&trivia_only,"trivia-only")]{
  let old=crate::original_body_cleanup_startup_geometry(headers,tokens(),&a).unwrap();let actual=crate::original_body_cleanup_peak_geometry(headers,tokens(),&a).unwrap();assert_eq!(actual.bytes(),old.bytes(),"{label} metadata must retain the entire old aggregate");
 }
 let wrapper=||lexical.tokens.iter().filter(|token|token.span.end<=source.find('\n').unwrap()).map(|t|(t.kind,t.span,t.text(source)));
 let old=crate::original_body_cleanup_startup_geometry(&ast.items[0].children,wrapper(),&a).unwrap();let actual=crate::original_body_cleanup_peak_geometry(&ast.items[0].children,wrapper(),&a).unwrap();assert_eq!(actual.bytes(),old.bytes(),"headers with no body-token coverage cannot mint a zero peak");assert_eq!(counter.load(Ordering::Acquire),fixed);
}
