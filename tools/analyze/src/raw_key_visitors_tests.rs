use super::*;
#[test]fn checked_key_visitors_reserve_before_owned_rows_and_match_compatibility(){
 let source="perform_op(user, src, \"alpha.open\")\nhold(src, STAT_DENSITY, 1, source = \"text\")\n";
 let mut starts=vec![0];for(i,b)in source.bytes().enumerate(){if b==b'\n'{starts.push((i+1)as u32);}}
 let mut old=Vec::new();let mut oldbad=Vec::new();visit_calls("code/a.dm",source,&starts,|v|old.push(v),|v|oldbad.push(v));
 let mut actual=Vec::new();let mut bad=Vec::new();assert!(visit_calls_checked("code/a.dm",source,&starts,|v|actual.push(v),|v|bad.push(v),|bytes|{assert!(bytes>=1024);true}));
 assert_eq!(format!("{actual:?}"),format!("{old:?}"));assert_eq!(bad,oldbad);assert_eq!(actual.len(),1);assert_eq!(bad.len(),1);
 let calls=std::cell::Cell::new(0);assert!(!visit_calls_checked("code/a.dm",source,&starts,|_|calls.set(calls.get()+1),|_|calls.set(calls.get()+1),|_|false));assert_eq!(calls.get(),0);
}
#[test]fn checked_header_visitors_preserve_reset_and_report_incomplete_after_late_denial(){
 let source="/datum/capability/a/entries()\n    op(\"one\"), op(\"two\")\n#define RAW_KEY 1\n/obj/elsewhere\n    op(\"ignored\")\n";
 let mut old=Vec::new();let mut defs=Vec::new();visit_headers(source,|a,b|old.push((a.to_string(),b.to_string())),|s|defs.push(s.to_string()));assert_eq!(old.len(),2);assert_eq!(defs,vec!["RAW_KEY"]);
 let mut actual=Vec::new();let mut found=Vec::new();assert!(visit_headers_checked(source,|a,b|actual.push((a.to_string(),b.to_string())),|s|found.push(s.to_string()),|_|true));assert_eq!(actual,old);assert_eq!(found,defs);
 let calls=std::cell::Cell::new(0);assert!(!visit_headers_checked(source,|_,_|calls.set(calls.get()+1),|_|calls.set(calls.get()+1),|_|false));assert_eq!(calls.get(),0);
 let admitted=std::cell::Cell::new(0);let rows=std::cell::Cell::new(0);assert!(!visit_headers_checked(source,|_,_|rows.set(rows.get()+1),|_|{},|_|{let n=admitted.get()+1;admitted.set(n);n<=3}));assert_eq!(rows.get(),1,"caller must discard this partial prefix on false");
}

#[test]fn checked_call_rows_charge_repeated_long_paths_and_compatibility_skips_bound_arithmetic(){
 assert!(work::<()>(&mut None,||panic!("legacy mode must not evaluate native bound arithmetic"),&||()).is_ok());
 let mut yes=|_:usize|Ok::<(),u8>(());assert_eq!(work(&mut Some(&mut yes),||usize::MAX.checked_mul(128),&||7),Err(7));
 let rel="r".repeat(4096);let source=format!("perform_op({})",vec!["\"a\"";256].join(","));
 let bytes=std::cell::Cell::new(0usize);let rows=std::cell::Cell::new(0usize);
 assert!(visit_calls_checked(&rel,&source,&[0],|_|rows.set(rows.get()+1),|_|panic!("not source call"),|n|{bytes.set(bytes.get().checked_add(n).unwrap());true}));
 assert_eq!(rows.get(),256);assert!(bytes.get()>=rows.get()*rel.len()*2,"every owned row's report path is independently admitted");
 let admitted=std::cell::Cell::new(0usize);let prefix=std::cell::Cell::new(0usize);
 assert!(!visit_calls_checked(&rel,&source,&[0],|_|prefix.set(prefix.get()+1),|_|{},|n|{let next=admitted.get().checked_add(n).unwrap();if next>512*1024{false}else{admitted.set(next);true}}));
 assert!(prefix.get()<256,"denial leaves no apparently complete native result");
}
