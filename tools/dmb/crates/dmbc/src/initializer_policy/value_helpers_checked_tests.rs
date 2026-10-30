use super::*;
use std::cell::Cell;
fn write()->InitializerWrite {let owner=SymbolId::of("/datum/test");InitializerWrite{source_site:dm_ir::InitializerSite::Declaration,target:InitializerTarget::Instance{declaring_owner:owner,receiver_owner:owner,name:SymbolId::of("value")},lexical_owner:owner,lexical_procedure:None,value:InitializerValue::NoAuthoredValue,declared_array:None,declaration_flags:Some(0)}}
struct Values;
impl CapturedInitializerEvaluator for Values {
    fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("exact AST hook must remain selected")}
    fn evaluate_ast_write(&self,_:&InitializerWrite,ast:&dm_syntax::Expr,_:&str,_:&SymbolTable)->Result<Evaluation,String>{
        Ok(match &ast.kind {
            dm_syntax::ExprKind::TypePath(path)=>Evaluation::Scalar(SemanticValue::Type(SymbolId::of(path))),
            dm_syntax::ExprKind::Literal(text)=>Evaluation::Scalar(SemanticValue::NumberBits(text.parse::<f32>().unwrap().to_bits())),
            _=>Evaluation::Runtime,
        })
    }
    fn initializer_constructor_type(&self,_:&InitializerWrite)->Result<Option<SymbolId>,String>{Ok(Some(SymbolId::of("/list")))}
    fn initializer_intrinsic_constructor(&self,_:&InitializerWrite,name:&str)->bool{matches!(name,"file"|"icon")}
}
#[test]
fn checked_value_helpers_preserve_exact_original_keys_scalar_shortcircuits_and_custom_hooks(){
    let mut symbols=SymbolTable::default();for text in ["1","2","3","runtime"]{symbols.intern(text).unwrap();}
    for source in ["list(1,2)","alist(a=1)","new /list(3)","newlist(/datum/a)","file(1)","icon(2)","generator(1)","sound(1)","matrix(1)","list(runtime)","new"]{
        let ast=dm_syntax::parse_expression(source).expr.unwrap();
        assert_eq!(crate::initializer_tokens::construction_key_checked(&ast,source,&write(),&symbols,&Values).unwrap(),crate::initializer_tokens::construction_key(&ast,source,&write(),&symbols,&Values).unwrap(),"{source}");
    }
    for source in ["1","list(1,2)","list(runtime)","newlist()"]{
        let ast=dm_syntax::parse_expression(source).expr.unwrap();
        assert_eq!(scalar_literal_checked(&ast,&write(),&symbols,source,&Values).unwrap(),scalar_literal(&ast,&write(),&symbols,source,&Values).unwrap(),"{source}");
    }
}
#[derive(Clone,Copy)]enum FailAt{Ast,Scalar,Constructor,Intrinsic}
struct Failure(FailAt);
impl CapturedInitializerEvaluator for Failure {
    fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("checked helpers cannot select String hooks")}
    fn evaluate_ast_write_checked(&self,w:&InitializerWrite,a:&dm_syntax::Expr,s:&str,t:&SymbolTable)->Result<Evaluation,InitializerFailure>{if matches!(self.0,FailAt::Ast){Err(InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Values.evaluate_ast_write(w,a,s,t).map_err(InitializerFailure::Unsupported)}}
    fn initializer_token_scalar_checked(&self,v:&SemanticValue)->Result<Vec<u8>,InitializerFailure>{if matches!(self.0,FailAt::Scalar){Err(InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Values.initializer_token_scalar(v).map_err(InitializerFailure::Unsupported)}}
    fn initializer_constructor_type_checked(&self,_:&InitializerWrite)->Result<Option<SymbolId>,InitializerFailure>{Err(InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)))}
    fn initializer_intrinsic_constructor_checked(&self,_:&InitializerWrite,_:&str)->Result<bool,InitializerFailure>{Err(InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)))}
}
#[test]
fn checked_construction_key_never_turns_actual_io_into_runtime_argument_or_none(){
    let symbols=SymbolTable::default();
    for (source,at) in [("list(1)",FailAt::Ast),("list(1)",FailAt::Scalar),("new",FailAt::Constructor),("file(1)",FailAt::Intrinsic)]{
        let ast=dm_syntax::parse_expression(source).expr.unwrap();
        let actual=crate::initializer_tokens::construction_key_checked(&ast,source,&write(),&symbols,&Failure(at)).err().expect("actual IO cannot be None").into_operational().unwrap();
        assert_eq!(actual.raw_os_error(),Some(1450),"{source}");
    }
}
#[test]
fn actual_mid_key_cancellation_drops_partial_key_and_same_original_expression_recovers(){
    struct Cancel{calls:Cell<usize>,token:crate::daemon::control::Cancellation}
    impl CapturedInitializerEvaluator for Cancel {
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("checked AST hook")}
        fn evaluate_ast_write_checked(&self,w:&InitializerWrite,a:&dm_syntax::Expr,s:&str,t:&SymbolTable)->Result<Evaluation,InitializerFailure>{self.calls.set(self.calls.get()+1);if self.calls.get()==2{self.token.cancel();}crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational)?;Values.evaluate_ast_write(w,a,s,t).map_err(InitializerFailure::Unsupported)}
    }
    let source="list(1,2)";let ast=dm_syntax::parse_expression(source).expr.unwrap();let symbols=SymbolTable::default();
    let token=crate::daemon::control::Cancellation::default();let worker=Cancel{calls:Cell::new(0),token:token.clone()};let binding=crate::daemon::control::bind_with_deadline(token,std::time::Instant::now()+std::time::Duration::from_secs(30));
    let error=crate::initializer_tokens::construction_key_checked(&ast,source,&write(),&symbols,&worker).err().expect("second real operand operation after partial key prefix").into_operational().unwrap();assert_eq!(error.kind(),std::io::ErrorKind::Interrupted);assert_eq!(worker.calls.get(),2);drop(binding);
    assert_eq!(crate::initializer_tokens::construction_key_checked(&ast,source,&write(),&symbols,&worker).unwrap(),crate::initializer_tokens::construction_key(&ast,source,&write(),&symbols,&Values).unwrap());
}
#[test]
fn scalar_helper_final_checkpoint_catches_successful_hook_cancellation_and_empty_entry(){
    struct Late(crate::daemon::control::Cancellation);
    impl CapturedInitializerEvaluator for Late {
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("checked AST hook")}
        fn evaluate_ast_write_checked(&self,_:&InitializerWrite,_:&dm_syntax::Expr,_:&str,_:&SymbolTable)->Result<Evaluation,InitializerFailure>{self.0.cancel();Ok(Evaluation::Scalar(SemanticValue::Null))}
    }
    let mut symbols=SymbolTable::default();symbols.intern("1").unwrap();let ast=dm_syntax::parse_expression("1").expr.unwrap();
    let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));
    let actual=scalar_literal_checked(&ast,&write(),&symbols,"1",&Late(token)).err().unwrap().into_operational().unwrap();assert_eq!(actual.kind(),std::io::ErrorKind::Interrupted);
    let empty=dm_syntax::parse_expression("newlist()").expr.unwrap();assert!(scalar_literal_checked(&empty,&write(),&symbols,"newlist()",&Values).is_err());drop(binding);
    assert!(scalar_literal_checked(&ast,&write(),&symbols,"1",&Values).unwrap());
}
