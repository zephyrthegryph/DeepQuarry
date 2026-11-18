use super::*;
use crate::{SettingAdmission,SettingChargeCounter,Span};
use std::sync::atomic::Ordering;

fn expr(kind:ExprKind)->Expr{Expr{kind,span:Span::new(0,1)}}
fn ident()->Expr{expr(ExprKind::Ident("owned_identifier".repeat(3)))}
fn path()->Expr{expr(ExprKind::TypePath("/obj/item/owned_type_path".repeat(2)))}
fn literal()->Expr{expr(ExprKind::Literal("0".into()))}
fn actual(text:&str,a:&SettingAdmission<'_>)->Result<crate::SettingExpression,crate::SettingSyntaxFailure>{
    let lexed=crate::lex_spans(text);assert!(lexed.diagnostics.is_empty());
    crate::setting_prepare::prepare_setting_expression(text,&lexed.tokens,Span::new(0,text.len()),a)
}

#[test]
fn scalar_leaf_cleanup_never_allocates_an_expression_worklist(){
    let mut pending=Vec::new();
    schedule(&mut pending,ident());schedule(&mut pending,path());
    assert!(pending.is_empty());assert_eq!(pending.capacity(),0,"both real owned Strings dropped without a Vec allocation");
    let before=LEAF_WORKLIST_ENTRIES.with(|n|n.get());
    drop_expression(ident(),None);drop_expression(path(),None);
    assert_eq!(LEAF_WORKLIST_ENTRIES.with(|n|n.get()),before);
}

#[test]
fn every_compound_child_edge_drops_scalar_leaves_before_worklist_entry(){
    let roots=vec![
        expr(ExprKind::Unary{op:"-".into(),value:Box::new(ident())}),
        expr(ExprKind::Group(Box::new(path()))),
        expr(ExprKind::TypeFilter{value:Box::new(ident()),types:vec!["/obj/item".into()]}),
        expr(ExprKind::Binary{op:"+".into(),lhs:Box::new(ident()),rhs:Box::new(path())}),
        expr(ExprKind::Conditional{condition:Box::new(ident()),then_value:Box::new(path()),else_value:Box::new(ident())}),
        expr(ExprKind::Call{callee:Box::new(ident()),args:vec![ident(),path(),literal()]}),
        expr(ExprKind::Member{object:Box::new(ident()),selector:"field".into(),via_colon:false}),
        expr(ExprKind::StaticMember{object:Box::new(path()),selector:"field".into()}),
        expr(ExprKind::SafeMember{object:Box::new(ident()),selector:"field".into(),via_colon:false}),
        expr(ExprKind::ObjectInitializer{object:Box::new(path()),fields:vec![("a".into(),ident()),("b".into(),path())]}),
        expr(ExprKind::Index{object:Box::new(ident()),index:Box::new(path())}),
        expr(ExprKind::SafeIndex{object:Box::new(path()),index:Box::new(ident())}),
    ];
    let before=LEAF_WORKLIST_ENTRIES.with(|n|n.get());
    for root in roots{drop_expression(root,None);}
    assert_eq!(LEAF_WORKLIST_ENTRIES.with(|n|n.get()),before,"a bypassed child push/append would expose a leaf at the actual release loop");
    // The literal donor owns this Vec uniquely. No shared LiteralText/AST is
    // changed; initial scalar rows are removed before worklist traversal.
    let text=crate::LiteralText::at("\"[owned_identifier][/obj/item]\"".into(),0);
    text.syntax_parts().unwrap();
    let (parts,anchor)=text.into_drop_parts();
    drop_literal_parts(parts.expect("actual last-owner literal parts"),anchor);
    assert_eq!(LEAF_WORKLIST_ENTRIES.with(|n|n.get()),before);
}

#[test]
fn scalar_leaf_retention_counts_payload_without_removed_coordination_and_refunds_last_alias(){
    let fixed=SettingChargeCounter::root_allocation_bytes();
    let used=SettingChargeCounter::try_new(fixed).unwrap();
    let a=SettingAdmission::new(&used,16<<20,&||Ok(()));
    for text in ["owned_identifier","/obj/item"]{
        let root=actual(text,&a).unwrap();
        let measured=crate::setting_prepare::prepare_body_measure(root.original_expression(),&a).unwrap();
        assert_eq!(measured.nodes,1);assert_eq!(measured.cleanup_nodes,0);
        let expected=measured.bytes+crate::setting_expression::root_storage_envelope();
        assert_eq!(root.retained_charge(),Some(expected));
        assert_eq!(used.load(Ordering::Acquire),fixed+expected);
        let alias=root.clone();drop(root);
        assert_eq!(used.load(Ordering::Acquire),fixed+expected,"live root/string alias keeps the exact SAME grant");
        drop(alias);assert_eq!(used.load(Ordering::Acquire),fixed);
    }
    let root=actual("call(alpha,beta)",&a).unwrap();
    let measured=crate::setting_prepare::prepare_body_measure(root.original_expression(),&a).unwrap();
    assert_eq!(measured.nodes,4);assert_eq!(measured.cleanup_nodes,1,"callee and two scalar args are never queued");
    let expected=measured.bytes+4*(std::mem::size_of::<Expr>()+std::mem::size_of::<SharedSettingRetention>())+crate::setting_expression::root_storage_envelope();
    assert_eq!(root.retained_charge(),Some(expected));drop(root);assert_eq!(used.load(Ordering::Acquire),fixed);
}

#[test]
fn scalar_child_cleanup_preserves_shared_literal_owner_and_anchor_lifetime(){
    let fixed=SettingChargeCounter::root_allocation_bytes();let used=SettingChargeCounter::try_new(fixed).unwrap();
    let a=SettingAdmission::new(&used,32<<20,&||Ok(()));
    let root=actual("\"value [owned_identifier] and [/obj/item]\"",&a).unwrap();
    let ExprKind::Literal(value)=&root.kind else{panic!("real prepared literal root")};
    let before=crate::literal::literal_child_parses_for_test();
    let parts=value.parts().unwrap().unwrap();let pointer=parts.expressions.as_ptr();
    let alias=value.clone();let charge=used.load(Ordering::Acquire);
    drop(root);assert_eq!(used.load(Ordering::Acquire),charge,"shared literal still owns its original children and grant");
    assert_eq!(alias.parts().unwrap().unwrap().expressions.as_ptr(),pointer);
    assert_eq!(crate::literal::literal_child_parses_for_test(),before,"drop does not demand/clone/replace shared syntax");
    let before_entries=LEAF_WORKLIST_ENTRIES.with(|n|n.get());drop(alias);
    assert_eq!(LEAF_WORKLIST_ENTRIES.with(|n|n.get()),before_entries);assert_eq!(used.load(Ordering::Acquire),fixed);
}

#[test]
fn scalar_dimension_payloads_and_compound_dimension_cleanup_still_share_the_body_grant(){
    let source="/proc/p()\n    var/x[bound][][size()]\n    return x\n";
    let ast=crate::parse(source);assert!(ast.diagnostics.is_empty());
    let parsed=crate::parse_proc_body(&ast.items[0]);assert!(parsed.diagnostics.is_empty());
    let array=parsed.local_variables.storage()[0].array_syntax.as_ref().expect("actual dimension syntax");
    assert_eq!(array.root.dimensions.len(),2);
    let fixed=SettingChargeCounter::root_allocation_bytes();let used=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&used,32<<20,&||Ok(()));
    let mut total=0;let mut cleanup=0;
    for dimension in &array.root.dimensions{let measured=crate::setting_prepare::prepare_body_measure(dimension,&a).unwrap();total+=measured.nodes;cleanup+=measured.cleanup_nodes;}
    assert_eq!((total,cleanup),(3,1),"scalar bound remains payload; size() schedules only its Call");
    let prepared=crate::body_literal_syntax::prepare_body_literal_syntax(parsed,a.reserve(source.len()*512+8192).unwrap(),&a).unwrap();
    let(parsed,admission)=prepared.into_parts();assert!(admission.is_admitted_by(&a));
    crate::body_literal_syntax::drop_body_literal_syntax(parsed,Some(admission));assert_eq!(used.load(Ordering::Acquire),fixed);
}

#[test]
fn scalar_leaf_cleanup_preserves_unwind_first_io_and_late_cancel(){
    let fixed=SettingChargeCounter::root_allocation_bytes();let used=SettingChargeCounter::try_new(fixed).unwrap();
    for text in ["owned_identifier","call(alpha,beta)","\"value [owned_identifier]\""]{
        let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{
            let a=SettingAdmission::new(&used,32<<20,&||Ok(()));let _root=actual(text,&a).unwrap();panic!("intentional owner unwind");
        }));assert!(result.is_err());assert_eq!(used.load(Ordering::Acquire),fixed,"actual root and all retained children free before their grant");
    }
    let calls=std::cell::Cell::new(0);let fault=||{calls.set(calls.get()+1);if calls.get()==1{Err(std::io::Error::from_raw_os_error(1450))}else{Err(std::io::ErrorKind::Interrupted.into())}};
    let failed=SettingAdmission::new(&used,32<<20,&fault);assert!(matches!(actual("owned_identifier",&failed),Err(crate::SettingSyntaxFailure::Operational(_))));
    assert_eq!(failed.take_operational_error().unwrap().raw_os_error(),Some(1450));assert_eq!(calls.get(),1);assert_eq!(used.load(Ordering::Acquire),fixed);
    let cancel=std::cell::Cell::new(false);let polls=std::cell::Cell::new(0);let poll=||{polls.set(polls.get()+1);if cancel.get(){Err(std::io::ErrorKind::Interrupted.into())}else{Ok(())}};
    let current=SettingAdmission::new(&used,32<<20,&poll);let root=actual("call(alpha,beta)",&current).unwrap();cancel.set(true);let before=polls.get();drop(root);
    assert_eq!(polls.get(),before,"cleanup never polls or substitutes a later cancel");assert_eq!(used.load(Ordering::Acquire),fixed);
}

#[test]
fn general_deep_cleanup_stays_iterative_with_scalar_terminal(){
    std::thread::Builder::new().stack_size(96*1024).spawn(||{
        let before=LEAF_WORKLIST_ENTRIES.with(|n|n.get());let mut root=ident();
        for _ in 0..20_000{root=expr(ExprKind::Group(Box::new(root)));}
        drop_expression(root,None);assert_eq!(LEAF_WORKLIST_ENTRIES.with(|n|n.get()),before);
    }).unwrap().join().unwrap();
}

#[test]fn numeric_null_and_plain_resource_literals_never_enter_cleanup_worklists(){
 let mut pending=Vec::new();for raw in ["0","1.25","null","'icons/leaf.dmi'"]{
  let value=expr(ExprKind::Literal(raw.into()));assert!(!needs_drop_coordination(&value));schedule(&mut pending,value);
 }assert_eq!(pending.capacity(),0,"actual leaf scheduling removed the physical worklist allocation");
 let fixed=SettingChargeCounter::root_allocation_bytes();let used=SettingChargeCounter::try_new(fixed).unwrap();let a=SettingAdmission::new(&used,32<<20,&||Ok(()));
 for text in["0","null","call(1,null,2)","array[1] + (null ? 2 : 3)"]{
  let root=actual(text,&a).unwrap();let measured=crate::setting_prepare::prepare_body_measure(root.original_expression(),&a).unwrap();assert!(measured.cleanup_nodes<measured.nodes);
  let alias=root.clone();drop(root);assert!(used.load(Ordering::Acquire)>fixed);drop(alias);assert_eq!(used.load(Ordering::Acquire),fixed);
 }
 let ordinary=crate::LiteralText::at("\"ordinary [call(1)]\"".into(),0);assert!(ordinary.owns_template_syntax());assert!(needs_drop_coordination(&expr(ExprKind::Literal(ordinary))),"ordinary/deferred interpolation remains coordinated");
}
