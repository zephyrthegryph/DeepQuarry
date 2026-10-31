use super::*;
use std::cell::{Cell,RefCell};
#[path="constants_original/constants_original_evaluator.rs"]
mod original;

#[test]
fn fallible_scalar_callbacks_match_frozen_original_values_reads_and_skipped_nameof_order(){
    for source in ["seed*2+3","/datum::seed","/datum","null","1/0","0x12 + 1","1.#INF","\"encoded\"","nameof(seed)","'asset.txt'","'asset.txt'=='asset.txt'","1||missing","0&&missing","0?missing:seed","list(seed)","0 && (missing + nameof(world.cpu))","1 ? 9 : (missing + nameof(/obj::icon))","seed > 2 ? -seed : ~seed","seed<<3","seed%2"]{
        let parsed=parse_expression(source);assert!(parsed.diagnostics.is_empty(),"{source}");let expression=parsed.expr.as_ref().unwrap();
        let before=RefCell::new(Vec::new());
        let observer=|expression:&Expr|before.borrow_mut().push(format!("observe:{:?}",expression.span));
        let old=original::evaluate_expr_with_resources_and_calls_and_nameof_observer(expression,
            |name|{before.borrow_mut().push(format!("resolve:{name}"));matches!(name,"seed"|"/datum::seed").then_some(original::Constant::Number(5.0))},
            |raw|{before.borrow_mut().push(format!("decode:{raw}"));Some(vec![0xff,0x80])},
            |_|{before.borrow_mut().push("nameof".into());Some("seed".into())},
            |raw|{before.borrow_mut().push(format!("resource:{raw}"));(raw=="'asset.txt'").then_some(crate::SymbolId::of("asset.txt"))},None,Some(&observer)).unwrap();
        let after=RefCell::new(Vec::new());
        let observer=|expression:&Expr|after.borrow_mut().push(format!("observe:{:?}",expression.span));
        let new=try_evaluate_expr_with_resources_and_calls_and_nameof_observer::<std::convert::Infallible>(expression,
            |name|{after.borrow_mut().push(format!("resolve:{name}"));Ok(matches!(name,"seed"|"/datum::seed").then_some(Constant::Number(5.0)))},
            |raw|{after.borrow_mut().push(format!("decode:{raw}"));Ok(Some(vec![0xff,0x80]))},
            |_|{after.borrow_mut().push("nameof".into());Ok(Some("seed".into()))},
            |raw|{after.borrow_mut().push(format!("resource:{raw}"));Ok((raw=="'asset.txt'").then_some(crate::SymbolId::of("asset.txt")))},None,Some(&observer)).unwrap();
        assert_eq!(old.map(|value|value.canonical_bytes()),new.map(|value|value.canonical_bytes()),"{source}");
        assert_eq!(before.into_inner(),after.into_inner(),"{source}");
    }
}

#[test]
fn fallible_scalar_actual_io_leaves_recursive_stack_without_none_or_later_callback(){
    for source in ["fail+later","/datum::fail","\"text\"","nameof(fail)","'asset.txt'"]{
        let parsed=parse_expression(source);assert!(parsed.diagnostics.is_empty());
        let calls=Cell::new(0);
        let fail=||{calls.set(calls.get()+1);std::io::Error::from_raw_os_error(1450)};
        let result=try_evaluate_expr_with_resources_and_calls_and_nameof_observer(parsed.expr.as_ref().unwrap(),
            |_|Err(fail()),|_|Err(fail()),|_|Err(fail()),|_|Err(fail()),None,None);
        let error=result.err().expect("actual callback failure cannot be an unfurled runtime expression");
        assert!(matches!(error,ConstantEvaluationFailure::Callback(ref actual)if actual.raw_os_error()==Some(1450)));
        assert_eq!(calls.get(),1,"later siblings are not evaluated after an operational exit");
        let fresh=try_evaluate_expr_with_resources_and_calls_and_nameof_observer::<std::io::Error>(parsed.expr.as_ref().unwrap(),|_|Ok(Some(Constant::Number(7.0))),|_|Ok(Some(b"text".to_vec())),|_|Ok(Some("fail".into())),|_|Ok(Some(crate::SymbolId::of("asset.txt"))),None,None).unwrap();
        assert!(fresh.is_some(),"same original AST is retryable");
    }
}

struct Calls;
impl PureCalls for Calls {
    fn identity(&self)->u128{7}
    fn accepts(&self,name:&str)->bool{name=="pure"||name=="reject"}
    fn evaluate(&self,name:&str,args:&[Option<Constant>])->Result<Constant,PureCallError>{
        if name=="reject"{return Err(PureCallError{name:name.into(),reason:"actual pinned policy refusal".into()})}
        Ok(Constant::Number(args.iter().flatten().count() as f32))
    }
}
#[test]
fn fallible_scalar_pure_calls_keep_none_arguments_and_distinct_policy_error(){
    let parsed=parse_expression("pure(missing, present)");let trace=RefCell::new(Vec::new());
    let value=try_evaluate_expr_with_resources_and_calls_and_nameof_observer::<std::io::Error>(parsed.expr.as_ref().unwrap(),|name|{trace.borrow_mut().push(name.to_owned());Ok((name=="present").then_some(Constant::Number(1.0)))},|_|Ok(None),|_|Ok(None),|_|Ok(None),Some(&Calls),None).unwrap();
    assert_eq!(trace.into_inner(),vec!["missing".to_owned(),"present".to_owned()]);assert_eq!(value,Some(Constant::Number(1.0)));
    let parsed=parse_expression("reject(1)");
    let result=try_evaluate_expr_with_resources_and_calls_and_nameof_observer::<std::io::Error>(parsed.expr.as_ref().unwrap(),|_|Ok(None),|_|Ok(None),|_|Ok(None),|_|Ok(None),Some(&Calls),None);
    assert!(matches!(result,Err(ConstantEvaluationFailure::PureCall(PureCallError{ref name,ref reason}))if name=="reject"&&reason=="actual pinned policy refusal"));
}

#[test]
fn controlled_scalar_stack_guard_denial_releases_every_frame_and_same_ast_retries(){
    use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
    let parsed=parse_expression("((1+2)+3)");let expression=parsed.expr.as_ref().unwrap();
    let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());
    let limited=dm_syntax::SettingAdmission::with_stack_allowance(&counter,1024*1024,32*1024,&healthy);
    let result=try_evaluate_expr_with_resources_and_calls_and_nameof_observer_controlled(expression,|_|Ok(None),|_|Ok(None),|_|Ok(None),|_|Ok(None),None,None,||limited.evaluation_frame());
    assert!(matches!(result,Err(ConstantEvaluationFailure::Callback(ref actual))if actual.kind()==std::io::ErrorKind::OutOfMemory));
    assert_eq!(counter.load(Ordering::Acquire),0,"all actual held recursion guards unwind on refusal");
    let retry=dm_syntax::SettingAdmission::with_stack_allowance(&counter,1024*1024,1024*1024,&healthy);
    let value=try_evaluate_expr_with_resources_and_calls_and_nameof_observer_controlled(expression,|_|Ok(None),|_|Ok(None),|_|Ok(None),|_|Ok(None),None,None,||retry.evaluation_frame()).unwrap();
    assert_eq!(value,Some(Constant::Number(6.0)));assert_eq!(counter.load(Ordering::Acquire),0);
}
#[test]
fn controlled_scalar_guard_is_held_through_callback_and_released_on_unwind(){
    use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
    let parsed=parse_expression("seed");let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());
    let admission=dm_syntax::SettingAdmission::with_stack_allowance(&counter,1024*1024,1024*1024,&healthy);
    let result=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||{
        let _=try_evaluate_expr_with_resources_and_calls_and_nameof_observer_controlled(parsed.expr.as_ref().unwrap(),|_|{assert_eq!(counter.load(Ordering::Acquire),16*1024);panic!("actual callback unwind")},|_|Ok(None),|_|Ok(None),|_|Ok(None),None,None,||admission.evaluation_frame());
    }));
    assert!(result.is_err());assert_eq!(counter.load(Ordering::Acquire),0);
}

#[test]
fn controlled_skipped_unknown_and_nameof_observer_descents_are_guarded_and_retry_original_order(){
    use std::sync::{Arc,atomic::{AtomicUsize,Ordering}};
    let deep=format!("{}nameof(seed){}","(".repeat(48),")".repeat(48));
    let deep_argument=format!("{}seed{}","(".repeat(48),")".repeat(48));
    for source in [format!("1 || {deep}"),format!("unrecognized({deep})"),format!("nameof({deep_argument})")]{
        let parsed=parse_expression(&source);assert!(parsed.diagnostics.is_empty());let expr=parsed.expr.as_ref().unwrap();
        let counter=Arc::new(AtomicUsize::new(0));let healthy=||Ok(());
        let denied=dm_syntax::SettingAdmission::with_stack_allowance(&counter,1024*1024,32*1024,&healthy);
        let observer=|_:&Expr|{};
        let result=try_evaluate_expr_with_resources_and_calls_and_nameof_observer_controlled(expr,|_|panic!("reference traversal must not evaluate identifiers"),|_|panic!("reference traversal must not decode"),|_|panic!("denial precedes nameof value callback"),|_|panic!("reference traversal must not resolve resources"),None,Some(&observer),||denied.evaluation_frame());
        assert!(matches!(result,Err(ConstantEvaluationFailure::Callback(ref actual))if actual.kind()==std::io::ErrorKind::OutOfMemory),"{source}");
        assert_eq!(counter.load(Ordering::Acquire),0,"every skipped traversal guard releases on refusal");
        let old_reads=RefCell::new(Vec::new());let old_observer=|expr:&Expr|old_reads.borrow_mut().push(format!("observe:{:?}",expr.span));
        let old=original::evaluate_expr_with_resources_and_calls_and_nameof_observer(expr,|_|panic!("old identifier"),|_|None,|_|{old_reads.borrow_mut().push("nameof-value".into());Some("seed".into())},|_|None,None,Some(&old_observer)).unwrap();
        let new_reads=RefCell::new(Vec::new());let new_observer=|expr:&Expr|new_reads.borrow_mut().push(format!("observe:{:?}",expr.span));
        let fresh=dm_syntax::SettingAdmission::with_stack_allowance(&counter,4*1024*1024,2*1024*1024,&healthy);
        let new=try_evaluate_expr_with_resources_and_calls_and_nameof_observer_controlled(expr,|_|panic!("new identifier"),|_|Ok(None),|_|{new_reads.borrow_mut().push("nameof-value".into());Ok(Some("seed".into()))},|_|Ok(None),None,Some(&new_observer),||fresh.evaluation_frame()).unwrap();
        assert_eq!(new.map(|c|c.canonical_bytes()),old.map(|c|c.canonical_bytes()));assert_eq!(new_reads.into_inner(),old_reads.into_inner());assert_eq!(counter.load(Ordering::Acquire),0);
    }
}
