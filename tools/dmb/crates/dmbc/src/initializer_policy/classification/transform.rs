//! Target-specific folding of immutable initial appearance values.
//! Ordinary matrix variables retain their mutable constructor semantics.
use super::super::*;

pub(super) fn fold(write:&InitializerWrite,expression:&dm_syntax::Expr,source:&str,symbols:&SymbolTable,evaluator:&dyn CapturedInitializerEvaluator)->Result<Option<[u32;6]>,String>{fold_with::<value_demand::Compatibility>(write,expression,value_demand::Source::Flat(source),symbols,evaluator)}
pub(in crate::initializer_policy) fn fold_checked(write:&InitializerWrite,expression:&dm_syntax::Expr,source:&str,symbols:&SymbolTable,evaluator:&dyn CapturedInitializerEvaluator)->Result<Option<[u32;6]>,InitializerFailure>{
    crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational)?;
    let result=fold_with::<value_demand::Checked>(write,expression,value_demand::Source::Flat(source),symbols,evaluator);
    if matches!(&result,Err(InitializerFailure::Operational(_))){return result;}
    crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational)?;result
}
fn fold_with<D: value_demand::Demand>(
    write: &InitializerWrite,
    expression: &dm_syntax::Expr,
    source: value_demand::Source<'_,'_>,
    symbols: &SymbolTable,
    evaluator: &dyn CapturedInitializerEvaluator,
) -> Result<Option<[u32; 6]>, D::Error> {
    if write.declaration_flags.is_some()
        || write.lexical_procedure.is_some()
        || !matches!(write.target, InitializerTarget::Instance {declaring_owner,name,..}
            if declaring_owner == SymbolId::of("/atom") && name == SymbolId::of("transform"))
    {
        return Ok(None);
    }
    let dm_syntax::ExprKind::Call { callee, args } = &expression.kind else {
        return Ok(None);
    };
    if !matches!(&callee.kind, dm_syntax::ExprKind::Ident(name) if name == "matrix") {
        return Ok(None);
    }
    if args.is_empty() {
        return Ok(Some([1.0f32.to_bits(), 0, 0, 0, 1.0f32.to_bits(), 0]));
    }
    if args.len() != 6 {
        return Ok(None);
    }
    let mut result = [0; 6];
    for (slot, argument) in result.iter_mut().zip(args) {
        let Evaluation::Scalar(SemanticValue::NumberBits(bits)) =
            D::ast(evaluator,write,argument,source,symbols)?
        else {
            return Ok(None);
        };
        if !f32::from_bits(bits).is_finite() {
            return Ok(None);
        }
        *slot = bits;
    }
    Ok(Some(result))
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Numeric;
    impl CapturedInitializerEvaluator for Numeric {
        fn evaluate(&self, _: SymbolId, value: &SymbolicExpression) -> Result<Evaluation, String> {
            let _ = value;
            Ok(Evaluation::Runtime)
        }
        fn evaluate_ast_write(
            &self,
            _: &InitializerWrite,
            ast: &dm_syntax::Expr,
            _: &str,
            _: &SymbolTable,
        ) -> Result<Evaluation, String> {
            if let dm_syntax::ExprKind::Literal(text) = &ast.kind {
                if let Ok(value) = text.parse::<f32>() {
                    return Ok(Evaluation::Scalar(SemanticValue::NumberBits(
                        value.to_bits(),
                    )));
                }
            }
            Ok(Evaluation::Runtime)
        }
    }
    fn target() -> InitializerWrite {
        InitializerWrite {
            source_site: dm_ir::InitializerSite::Declaration,
            target: InitializerTarget::Instance {
                declaring_owner: SymbolId::of("/atom"),
                receiver_owner: SymbolId::of("/obj/probe"),
                name: SymbolId::of("transform"),
            },
            lexical_owner: SymbolId::of("/obj/probe"),
            lexical_procedure: None,
            value: InitializerValue::NoAuthoredValue,
            declared_array: None,
            declaration_flags: None,
        }
    }
    #[test]
    fn six_numeric_transform_and_identity_fold_but_ordinary_matrix_declines() {
        let symbols = SymbolTable::default();
        let source = "matrix(2,0,3,0,4,5)";
        let ast = dm_syntax::parse_expression(source).expr.unwrap();
        let matrix = fold(&target(), &ast, source, &symbols, &Numeric)
            .unwrap()
            .unwrap();
        let oracle = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../../../fixtures/native_compiler/matrix_transform/probe.native.bin"
        ))
        .unwrap();
        let record = oracle
            .classes
            .iter()
            .find(|class| oracle.string(class.path_string_id()) == Some(b"/obj/matrix_probe"))
            .unwrap();
        assert_eq!(Some(matrix), record.transform);
        let mut ordinary = target();
        ordinary.declaration_flags = Some(0);
        assert!(
            fold(&ordinary, &ast, source, &symbols, &Numeric)
                .unwrap()
                .is_none()
        );
        let source = "matrix()";
        let ast = dm_syntax::parse_expression(source).expr.unwrap();
        assert_eq!(
            fold(&target(), &ast, source, &symbols, &Numeric).unwrap(),
            Some([1.0f32.to_bits(), 0, 0, 0, 1.0f32.to_bits(), 0])
        );
        let source = "matrix(2,0,runtime_value,0,4,5)";
        let ast = dm_syntax::parse_expression(source).expr.unwrap();
        assert!(
            fold(&target(), &ast, source, &symbols, &Numeric)
                .unwrap()
                .is_none()
        );
    }
}

#[cfg(test)]
mod checked_transport_tests {
    use super::*;
    struct Numbers;
    impl CapturedInitializerEvaluator for Numbers {
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{Ok(Evaluation::Runtime)}
        fn evaluate_ast_write(&self,_:&InitializerWrite,ast:&dm_syntax::Expr,_:&str,_:&SymbolTable)->Result<Evaluation,String>{
            Ok(if let dm_syntax::ExprKind::Literal(text)=&ast.kind {Evaluation::Scalar(SemanticValue::NumberBits(text.parse::<f32>().unwrap().to_bits()))} else {Evaluation::Runtime})
        }
    }
    struct Failed;
    impl CapturedInitializerEvaluator for Failed {
        fn evaluate(&self,_:SymbolId,_:&SymbolicExpression)->Result<Evaluation,String>{panic!("AST only")}
        fn evaluate_ast_write_checked(&self,_:&InitializerWrite,_:&dm_syntax::Expr,_:&str,_:&SymbolTable)->Result<Evaluation,InitializerFailure>{Err(InitializerFailure::Operational(std::io::Error::from_raw_os_error(1450)))}
    }
    #[test]
    fn checked_matrix_fold_preserves_exact_policy_and_actual_operand_failure(){
        let write=InitializerWrite{source_site:dm_ir::InitializerSite::Declaration,target:InitializerTarget::Instance{declaring_owner:SymbolId::of("/atom"),receiver_owner:SymbolId::of("/obj/probe"),name:SymbolId::of("transform")},lexical_owner:SymbolId::of("/obj/probe"),lexical_procedure:None,value:InitializerValue::NoAuthoredValue,declared_array:None,declaration_flags:None};
        let source="matrix(1,0,0,0,1,0)";let ast=dm_syntax::parse_expression(source).expr.unwrap();let symbols=SymbolTable::default();
        assert_eq!(fold_checked(&write,&ast,source,&symbols,&Numbers).unwrap(),fold(&write,&ast,source,&symbols,&Numbers).unwrap());
        let error=fold_checked(&write,&ast,source,&symbols,&Failed).err().unwrap().into_operational().unwrap();assert_eq!(error.raw_os_error(),Some(1450));
    }
}

pub(crate) fn fold_source_checked(write:&InitializerWrite,expression:&dm_syntax::Expr,source:value_demand::Source<'_,'_>,symbols:&SymbolTable,evaluator:&dyn CapturedInitializerEvaluator)->Result<Option<[u32;6]>,InitializerFailure>{
 crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational)?;let result=fold_with::<value_demand::Checked>(write,expression,source,symbols,evaluator);if matches!(&result,Err(InitializerFailure::Operational(_))){return result}crate::daemon::control::checkpoint().map_err(InitializerFailure::Operational)?;result
}
