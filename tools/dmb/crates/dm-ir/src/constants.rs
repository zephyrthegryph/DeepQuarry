//! Authoritative scalar declaration evaluator extracted from the preserved compiler.
//! String escape interpretation and nameof are supplied by the syntax adapter so
//! this crate does not depend on BYOND encoding or lowering. Unknown/runtime/list
//! expressions return None; they must not be cached as a negative declaration.
//! Pure evaluation of declaration expressions. Runtime operations remain unfurled.
use dm_syntax::{parse_expression, Expr, ExprKind, LiteralText};

#[derive(Clone, Debug, PartialEq)]
pub enum Constant {
    Null,
    Number(f32),
    Text(String),
    EncodedText(Vec<u8>),
    TypePath(String),
    Procedure(crate::ProcedureIdentity),
    ModifiedInstance(std::sync::Arc<crate::ModifiedInstance>),
    Resource(crate::SymbolId),
}
impl Constant {
    fn truth(&self) -> bool {
        match self {
            Self::Null => false,
            Self::Number(n) => *n != 0.0,
            Self::Text(s) => !s.is_empty(),
            Self::EncodedText(s) => !s.is_empty(),
            Self::TypePath(_)
            | Self::Procedure(_)
            | Self::Resource(_)
            | Self::ModifiedInstance(_) => true,
        }
    }
    fn number(&self) -> Option<f32> {
        match self {
            Self::Number(n) => Some(*n),
            _ => None,
        }
    }
}

/// Optional, immutable pure-call policy. Unknown calls must not evaluate arguments.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PureCallError {
    pub name: String,
    pub reason: String,
}
pub trait PureCalls: Sync {
    /// Some only when every result depends exclusively on the arguments and
    /// this immutable policy. Providers with external reads must decline.
    fn immutable_policy_identity(&self) -> Option<u128> {
        None
    }
    /// Exact, source-independent immutable policy evidence for disk transport.
    /// Equal bytes must guarantee equal semantics for every input. A process-local
    /// identity or policy with external reads must return None.
    fn immutable_policy_bytes(&self) -> Option<&[u8]> {
        None
    }
    fn identity(&self) -> u128;
    fn accepts(&self, name: &str) -> bool;
    fn evaluate(
        &self,
        name: &str,
        arguments: &[Option<Constant>],
    ) -> Result<Constant, PureCallError>;
}

pub fn evaluate_with(
    source: &str,
    resolve: impl Fn(&str) -> Option<Constant>,
    decode: impl Fn(&LiteralText) -> Option<Vec<u8>>,
    nameof: impl Fn(&Expr) -> Option<String>,
) -> Option<Constant> {
    evaluate_with_resources(source, resolve, decode, nameof, |_| None)
}
/// Classify only grammar-shaped explicit callable literals. Resolution still
/// supplies positive declaration authority and the exact source occurrence.
pub fn procedure_literal_query(path: &str) -> Option<crate::ResolveQuery> {
    crate::procedure_value_query(path)
}

/// Resource literals are admitted only by an explicit captured search callback.
/// The compatibility evaluator above continues to decline resource literals.
pub fn evaluate_with_resources(
    source: &str,
    resolve: impl Fn(&str) -> Option<Constant>,
    decode: impl Fn(&LiteralText) -> Option<Vec<u8>>,
    nameof: impl Fn(&Expr) -> Option<String>,
    resource: impl Fn(&str) -> Option<crate::SymbolId>,
) -> Option<Constant> {
    let parsed = parse_expression(source);
    if !parsed.diagnostics.is_empty() {
        return None;
    }
    evaluate_expr_with_resources(parsed.expr.as_ref()?, resolve, decode, nameof, resource)
}
/// Evaluate an already parsed expression through the same scalar interpreter.
/// The decoder borrows the literal issued in `expression`, including its shared
/// interpolation syntax. It must not reconstruct a literal from raw spelling.
/// The caller owns syntax diagnostics and supplies the same captured callbacks
/// as the string entry; this API neither reparses nor infers resource authority.
pub fn evaluate_expr_with_resources(
    expression: &Expr,
    resolve: impl Fn(&str) -> Option<Constant>,
    decode: impl Fn(&LiteralText) -> Option<Vec<u8>>,
    nameof: impl Fn(&Expr) -> Option<String>,
    resource: impl Fn(&str) -> Option<crate::SymbolId>,
) -> Option<Constant> {
    evaluate_expr_with_resources_and_calls(expression, resolve, decode, nameof, resource, None)
        .ok()
        .flatten()
}
pub fn evaluate_with_resources_and_calls(
    source: &str,
    resolve: impl Fn(&str) -> Option<Constant>,
    decode: impl Fn(&LiteralText) -> Option<Vec<u8>>,
    nameof: impl Fn(&Expr) -> Option<String>,
    resource: impl Fn(&str) -> Option<crate::SymbolId>,
    calls: Option<&dyn PureCalls>,
) -> Result<Option<Constant>, PureCallError> {
    let parsed = parse_expression(source);
    if !parsed.diagnostics.is_empty() {
        return Ok(None);
    }
    let Some(expression) = parsed.expr.as_ref() else {
        return Ok(None);
    };
    evaluate_expr_with_resources_and_calls(expression, resolve, decode, nameof, resource, calls)
}
pub fn evaluate_expr_with_resources_and_calls(
    expression: &Expr,
    resolve: impl Fn(&str) -> Option<Constant>,
    decode: impl Fn(&LiteralText) -> Option<Vec<u8>>,
    nameof: impl Fn(&Expr) -> Option<String>,
    resource: impl Fn(&str) -> Option<crate::SymbolId>,
    calls: Option<&dyn PureCalls>,
) -> Result<Option<Constant>, PureCallError> {
    evaluate_expr_with_resources_and_calls_and_nameof_observer(
        expression, resolve, decode, nameof, resource, calls, None,
    )
}
/// Observe typed nameof references during the same evaluation traversal,
/// including unevaluated branches. The observer must not evaluate their values.
/// Existing adapters retain their original traversal by passing no observer.
pub fn evaluate_expr_with_resources_and_calls_and_nameof_observer(
    expression: &Expr,
    resolve: impl Fn(&str) -> Option<Constant>,
    decode: impl Fn(&LiteralText) -> Option<Vec<u8>>,
    nameof: impl Fn(&Expr) -> Option<String>,
    resource: impl Fn(&str) -> Option<crate::SymbolId>,
    calls: Option<&dyn PureCalls>,
    observer: Option<&dyn Fn(&Expr)>,
) -> Result<Option<Constant>, PureCallError> {
    let error = std::cell::RefCell::new(None);
    let value = eval(
        expression, &resolve, &decode, &nameof, &resource, calls, &error, observer,
    );
    match error.into_inner() {
        Some(error) => Err(error),
        None => Ok(value),
    }
}
#[path = "constants_reference_observer.rs"]
mod reference_observer;
/// A callback failure travels directly through the original scalar interpreter.
/// Pure-call refusal retains its existing, distinct semantic policy class.
#[derive(Debug)]
pub enum ConstantEvaluationFailure<E>{Callback(E),PureCall(PureCallError)}
pub fn try_evaluate_expr_with_resources_and_calls_and_nameof_observer<E>(expression:&Expr,resolve:impl Fn(&str)->Result<Option<Constant>,E>,decode:impl Fn(&LiteralText)->Result<Option<Vec<u8>>,E>,nameof:impl Fn(&Expr)->Result<Option<String>,E>,resource:impl Fn(&str)->Result<Option<crate::SymbolId>,E>,calls:Option<&dyn PureCalls>,observer:Option<&dyn Fn(&Expr)>)->Result<Option<Constant>,ConstantEvaluationFailure<E>>{
    try_evaluate_expr_with_resources_and_calls_and_nameof_observer_controlled(expression,resolve,decode,nameof,resource,calls,observer,||Ok::<(),E>(()))
}
pub fn try_evaluate_expr_with_resources_and_calls_and_nameof_observer_controlled<E,G>(expression:&Expr,resolve:impl Fn(&str)->Result<Option<Constant>,E>,decode:impl Fn(&LiteralText)->Result<Option<Vec<u8>>,E>,nameof:impl Fn(&Expr)->Result<Option<String>,E>,resource:impl Fn(&str)->Result<Option<crate::SymbolId>,E>,calls:Option<&dyn PureCalls>,observer:Option<&dyn Fn(&Expr)>,enter:impl Fn()->Result<G,E>)->Result<Option<Constant>,ConstantEvaluationFailure<E>>{
    let error=std::cell::RefCell::new(None);
    let value=eval_fallible(expression,&resolve,&decode,&nameof,&resource,calls,&error,observer,&enter).map_err(ConstantEvaluationFailure::Callback)?;
    match error.into_inner(){Some(error)=>Err(ConstantEvaluationFailure::PureCall(error)),None=>Ok(value)}
}
fn eval(
    expr: &Expr,
    resolve: &impl Fn(&str) -> Option<Constant>,
    decode: &impl Fn(&LiteralText) -> Option<Vec<u8>>,
    nameof: &impl Fn(&Expr) -> Option<String>,
    resource: &impl Fn(&str) -> Option<crate::SymbolId>,
    calls: Option<&dyn PureCalls>,
    error: &std::cell::RefCell<Option<PureCallError>>,
    observer: Option<&dyn Fn(&Expr)>,
) -> Option<Constant> {
    match eval_fallible(expr,&|name|Ok::<_,std::convert::Infallible>(resolve(name)),&|raw|Ok(decode(raw)),&|expr|Ok(nameof(expr)),&|raw|Ok(resource(raw)),calls,error,observer,&||Ok::<(),std::convert::Infallible>(())){Ok(value)=>value,Err(never)=>match never{}}
}
fn eval_fallible<E,G>(
    expr: &Expr,
    resolve: &impl Fn(&str) -> Result<Option<Constant>,E>,
    decode: &impl Fn(&LiteralText) -> Result<Option<Vec<u8>>,E>,
    nameof: &impl Fn(&Expr) -> Result<Option<String>,E>,
    resource: &impl Fn(&str) -> Result<Option<crate::SymbolId>,E>,
    calls: Option<&dyn PureCalls>,
    error: &std::cell::RefCell<Option<PureCallError>>,
    observer: Option<&dyn Fn(&Expr)>,
    enter:&impl Fn()->Result<G,E>,
) -> Result<Option<Constant>,E> {
    let frame=enter()?;
    eval_admitted(expr,resolve,decode,nameof,resource,calls,error,observer,enter,frame)
}
fn eval_admitted<E,G>(
    expr: &Expr,
    resolve: &impl Fn(&str) -> Result<Option<Constant>,E>,
    decode: &impl Fn(&LiteralText) -> Result<Option<Vec<u8>>,E>,
    nameof: &impl Fn(&Expr) -> Result<Option<String>,E>,
    resource: &impl Fn(&str) -> Result<Option<crate::SymbolId>,E>,
    calls: Option<&dyn PureCalls>,
    error: &std::cell::RefCell<Option<PureCallError>>,
    observer: Option<&dyn Fn(&Expr)>,
    enter:&impl Fn()->Result<G,E>,
    _frame:G,
) -> Result<Option<Constant>,E> {
    // Semantic absence and operational callback failure are separate exits.
    macro_rules! some {($value:expr)=>{match $value{Some(value)=>value,None=>return Ok(None)}}}
    use Constant::*;
    let boolean = |value| Number(if value { 1.0 } else { 0.0 });
    let result = match &expr.kind {
        ExprKind::Ident(name) if name == "null" => Null,
        ExprKind::Ident(name) => some!(resolve(name)?),
        ExprKind::TypePath(path) => TypePath(path.clone()),
        ExprKind::StaticMember { object, selector } => {
            let TypePath(path) = some!(eval_fallible(
                object, resolve, decode, nameof, resource, calls, error, observer, enter,
            )?)
            else {
                return Ok(None);
            };
            some!(resolve(&format!("{path}::{selector}"))?)
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "nameof") =>
        {
            let [argument] = args.as_slice() else {
                return Ok(None);
            };
            reference_observer::try_observe_unevaluated(expr, observer,enter)?;
            Text(some!(nameof(argument)?))
        }
        ExprKind::Call { callee, args } => {
            let ExprKind::Ident(name) = &callee.kind else {
                reference_observer::try_observe_unevaluated(expr, observer,enter)?;
                return Ok(None);
            };
            let Some(policy) = calls.filter(|policy| policy.accepts(name)) else {
                reference_observer::try_observe_unevaluated(expr, observer,enter)?;
                return Ok(None);
            };
            let arguments = args
                .iter()
                .map(|argument| {
                    eval_fallible(
                        argument, resolve, decode, nameof, resource, calls, error, observer, enter,
                    )
                })
                .collect::<Result<Vec<_>,E>>()?;
            if error.borrow().is_some() {
                return Ok(None);
            }
            match policy.evaluate(name, &arguments) {
                Ok(value) => value,
                Err(rejection) => {
                    *error.borrow_mut() = Some(rejection);
                    return Ok(None);
                }
            }
        }
        ExprKind::Literal(raw) if raw.starts_with('\'') && raw.ends_with('\'') => {
            Resource(some!(resource(raw)?))
        }
        ExprKind::Literal(raw) if raw == "null" => Null,
        ExprKind::Literal(raw) if raw == "1.#INF" => Number(f32::INFINITY),
        ExprKind::Literal(raw) => {
            if (raw.starts_with('"') && raw.ends_with('"'))
                || (raw.starts_with("{\"") && raw.ends_with("\"}"))
                || raw.starts_with('@')
            {
                let bytes = some!(decode(raw)?);
                match String::from_utf8(bytes) {
                    Ok(text) => Text(text),
                    Err(error) => EncodedText(error.into_bytes()),
                }
            } else {
                let n = if let Some(hex) = raw.strip_prefix("0x").or_else(|| raw.strip_prefix("0X"))
                {
                    some!(u32::from_str_radix(hex, 16).ok()) as f32
                } else {
                    some!(raw.parse::<f32>().ok())
                };
                Number(n)
            }
        }
        ExprKind::Group(inner) => some!(eval_fallible(
            inner, resolve, decode, nameof, resource, calls, error, observer, enter,
        )?),
        ExprKind::Unary { op, value } => {
            let value = some!(eval_fallible(
                value, resolve, decode, nameof, resource, calls, error, observer, enter,
            )?);
            match op.as_str() {
                "!" => boolean(!value.truth()),
                "+" => Number(some!(value.number())),
                "-" => Number(-some!(value.number())),
                "~" => Number((!(some!(value.number()) as i32) & 0xffffff) as f32),
                _ => return Ok(None),
            }
        }
        ExprKind::Binary { op, lhs, rhs } => {
            let Some(left) = eval_fallible(
                lhs, resolve, decode, nameof, resource, calls, error, observer, enter,
            )? else {
                reference_observer::try_observe_unevaluated(rhs, observer,enter)?;
                return Ok(None);
            };
            if op == "&&" {
                return if left.truth() {
                    eval_fallible(
                        rhs, resolve, decode, nameof, resource, calls, error, observer, enter,
                    )
                } else {
                    reference_observer::try_observe_unevaluated(rhs, observer,enter)?;
                    Ok(Some(left))
                };
            }
            if op == "||" {
                return if left.truth() {
                    reference_observer::try_observe_unevaluated(rhs, observer,enter)?;
                    Ok(Some(left))
                } else {
                    eval_fallible(
                        rhs, resolve, decode, nameof, resource, calls, error, observer, enter,
                    )
                };
            }
            let right = some!(eval_fallible(
                rhs, resolve, decode, nameof, resource, calls, error, observer, enter,
            )?);
            // Authored lookup paths are not runtime content identities. Do not
            // fold resource comparisons/arithmetic from path equality.
            if matches!(left, Resource(_)) || matches!(right, Resource(_)) {
                return Ok(None);
            }
            if op == "+" {
                if let (Text(a), Text(b)) = (&left, &right) {
                    return Ok(Some(Text(format!("{a}{b}"))));
                }
                let bytes = |value: &Constant| match value {
                    Text(text) => Some(text.as_bytes().to_vec()),
                    EncodedText(text) => Some(text.clone()),
                    _ => None,
                };
                if let (Some(mut a), Some(b)) = (bytes(&left), bytes(&right)) {
                    a.extend(b);
                    return Ok(Some(EncodedText(a)));
                }
            }
            if op == "==" || op == "!=" {
                if std::mem::discriminant(&left) != std::mem::discriminant(&right) {
                    return Ok(None);
                }
                return Ok(Some(boolean(if op == "==" {
                    left == right
                } else {
                    left != right
                })));
            }
            let a = some!(left.number());
            let b = some!(right.number());
            match op.as_str() {
                "+" => Number(a + b),
                "-" => Number(a - b),
                "*" => Number(a * b),
                "/" if b != 0.0 => Number(a / b),
                "%" if b != 0.0 => Number(some!((a as i32).checked_rem(b as i32)) as f32),
                "**" => Number(a.powf(b)),
                "<" => boolean(a < b),
                "<=" => boolean(a <= b),
                ">" => boolean(a > b),
                ">=" => boolean(a >= b),
                "&" => Number(((a as i32 & b as i32) & 0xffffff) as f32),
                "|" => Number(((a as i32 | b as i32) & 0xffffff) as f32),
                "^" => Number(((a as i32 ^ b as i32) & 0xffffff) as f32),
                "<<" => {
                    if !a.is_finite() || !b.is_finite() || a >= 2147483648.0 || b >= 4294967296.0 {
                        return Ok(None);
                    }
                    Number(
                        ((a.max(0.0) as u32).wrapping_shl((b.max(0.0) as u32) & 31) & 0xffffff)
                            as f32,
                    )
                }
                ">>" => Number(((a as i32 & 0xffffff) >> ((b.max(0.0) as u32) & 31)) as f32),
                _ => return Ok(None),
            }
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            let Some(condition) = eval_fallible(
                condition, resolve, decode, nameof, resource, calls, error, observer, enter,
            )? else {
                reference_observer::try_observe_unevaluated(then_value, observer,enter)?;
                reference_observer::try_observe_unevaluated(else_value, observer,enter)?;
                return Ok(None);
            };
            let (selected, skipped) = if condition.truth() {
                (then_value, else_value)
            } else {
                (else_value, then_value)
            };
            reference_observer::try_observe_unevaluated(skipped, observer,enter)?;
            some!(eval_fallible(
                selected, resolve, decode, nameof, resource, calls, error, observer, enter,
            )?)
        }
        _ => {
            reference_observer::try_observe_unevaluated(expr, observer,enter)?;
            return Ok(None);
        }
    };
    if matches!(result, Number(n) if n.is_nan()) {
        Ok(None)
    } else {
        Ok(Some(result))
    }
}

impl Constant {
    /// Explicit value serialization for resolver fingerprints and cache records.
    /// EncodedText and Text normalize to the same byte meaning.
    pub fn canonical_bytes(&self) -> Vec<u8> {
        let mut result = Vec::new();
        result.extend_from_slice(b"dm-scalar-v1\0");
        match self {
            Self::Null => result.push(0),
            Self::Number(number) => {
                result.push(1);
                result.extend_from_slice(&number.to_bits().to_le_bytes());
            }
            Self::Text(text) => {
                result.push(2);
                result.extend_from_slice(text.as_bytes());
            }
            Self::EncodedText(text) => {
                result.push(2);
                result.extend_from_slice(text);
            }
            Self::Resource(content) => {
                result.push(4);
                result.extend_from_slice(&content.bits().to_le_bytes());
            }
            Self::Procedure(procedure) => {
                result.push(5);
                result.extend_from_slice(&procedure.owner.bits().to_le_bytes());
                result.extend_from_slice(&procedure.name.bits().to_le_bytes());
                result.push(u8::from(procedure.verb));
                result.extend_from_slice(&procedure.occurrence.to_le_bytes());
            }
            Self::ModifiedInstance(instance) => {
                result.push(6);
                let data = instance.canonical_bytes();
                result.extend_from_slice(&(data.len() as u64).to_le_bytes());
                result.extend_from_slice(data);
            }
            Self::TypePath(path) => {
                result.push(3);
                result.extend_from_slice(path.as_bytes());
            }
        }
        result
    }
}

impl Constant {
    /// Convert evaluated scalar values to the shared lowering boundary model.
    pub fn to_semantic(
        &self,
        symbols: &mut crate::SymbolTable,
    ) -> Result<crate::SemanticValue, crate::SymbolCollision> {
        Ok(match self {
            Self::Null => crate::SemanticValue::Null,
            Self::Number(number) => crate::SemanticValue::NumberBits(number.to_bits()),
            Self::Text(text) => crate::SemanticValue::Text(std::sync::Arc::from(text.as_bytes())),
            Self::EncodedText(text) => {
                crate::SemanticValue::Text(std::sync::Arc::from(text.as_slice()))
            }
            Self::TypePath(path) => crate::SemanticValue::Type(symbols.intern(path)?),
            Self::Procedure(procedure) => crate::SemanticValue::Procedure(*procedure),
            Self::ModifiedInstance(instance) => {
                crate::SemanticValue::ModifiedInstance(instance.clone())
            }
            Self::Resource(content) => crate::SemanticValue::Resource(*content),
        })
    }
}

#[cfg(test)]
mod resource_tests {
    use super::*;
    #[test]
    fn resource_is_typed_and_requires_explicit_capture() {
        let path = crate::SymbolId::of("asset.txt");
        assert_eq!(
            evaluate_with("'asset.txt'", |_| None, |_| None, |_| None),
            None
        );
        assert_eq!(
            evaluate_with_resources(
                "'asset.txt'",
                |_| None,
                |_| None,
                |_| None,
                |raw| (raw == "'asset.txt'").then_some(path)
            ),
            Some(Constant::Resource(path))
        );
        assert_eq!(
            Constant::Resource(path)
                .to_semantic(&mut crate::SymbolTable::default())
                .unwrap(),
            crate::SemanticValue::Resource(path)
        );
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn evaluate(source: &str) -> Option<Constant> {
        evaluate_with(
            source,
            |name| match name {
                "seed" => Some(Constant::Number(5.0)),
                _ => None,
            },
            |_| None,
            |_| None,
        )
    }
    #[test]
    fn parsed_scalar_api_matches_string_values_and_callback_reads() {
        use std::cell::RefCell;
        let path = crate::SymbolId::of("asset.txt");
        for source in [
            "seed * 2 + 3",
            "/datum::seed",
            "/datum",
            "null",
            "1 / 0",
            "\"encoded\"",
            "nameof(seed)",
            "'asset.txt'",
            "'asset.txt' == 'asset.txt'",
            "1 || missing",
            "0 && missing",
            "0 ? missing : seed",
            "list(seed)",
        ] {
            let parsed = parse_expression(source);
            assert!(
                parsed.diagnostics.is_empty(),
                "{source}: {:?}",
                parsed.diagnostics
            );
            let expression = parsed.expr.as_ref().unwrap();
            let run = |from_ast| {
                let reads = RefCell::new(Vec::new());
                let resolve = |name: &str| {
                    reads.borrow_mut().push(format!("resolve:{name}"));
                    matches!(name, "seed" | "/datum::seed").then_some(Constant::Number(5.0))
                };
                let decode = |raw: &LiteralText| {
                    reads.borrow_mut().push(format!("decode:{raw}"));
                    Some(vec![0xff, 0x80])
                };
                let nameof = |_: &Expr| {
                    reads.borrow_mut().push("nameof".into());
                    Some("seed".into())
                };
                let resource = |raw: &str| {
                    reads.borrow_mut().push(format!("resource:{raw}"));
                    (raw == "'asset.txt'").then_some(path)
                };
                let value = if from_ast {
                    evaluate_expr_with_resources(expression, resolve, decode, nameof, resource)
                } else {
                    evaluate_with_resources(source, resolve, decode, nameof, resource)
                };
                (
                    value.map(|value| value.canonical_bytes()),
                    reads.into_inner(),
                )
            };
            assert_eq!(run(true), run(false), "{source}");
        }
        assert_eq!(
            evaluate_with_resources("1 +", |_| None, |_| None, |_| None, |_| None),
            None
        );
    }

    #[test]
    fn parsed_scalar_api_preserves_short_circuit_and_resource_admission() {
        for source in ["1 || missing", "0 && missing", "1 ? 7 : 'uncaptured'"] {
            let parsed = parse_expression(source);
            let result = evaluate_expr_with_resources(
                parsed.expr.as_ref().unwrap(),
                |_| panic!("unreachable name"),
                |_| panic!("unreachable string"),
                |_| panic!("unreachable nameof"),
                |_| panic!("unreachable resource"),
            );
            assert!(result.is_some(), "{source}");
        }
        let parsed = parse_expression("'asset.txt'");
        let expression = parsed.expr.as_ref().unwrap();
        assert_eq!(
            evaluate_expr_with_resources(expression, |_| None, |_| None, |_| None, |_| None),
            None
        );
        let path = crate::SymbolId::of("asset.txt");
        assert_eq!(
            evaluate_expr_with_resources(
                expression,
                |_| None,
                |_| None,
                |_| None,
                |raw| (raw == "'asset.txt'").then_some(path)
            ),
            Some(Constant::Resource(path))
        );
    }

    #[test]
    fn arithmetic_and_scoped_dependency_preserve_scalar_semantics() {
        assert_eq!(evaluate("seed * 2 + 3"), Some(Constant::Number(13.0)));
        assert_eq!(
            evaluate("0xffffff ^ 3"),
            Some(Constant::Number(16_777_212.0))
        );
        assert_eq!(evaluate("~0"), Some(Constant::Number(16_777_215.0)));
        assert_eq!(evaluate("1 << 25"), Some(Constant::Number(0.0)));
        assert_eq!(evaluate("1 / 0"), None);
    }
    #[test]
    fn short_circuit_does_not_resolve_unreachable_name() {
        let result = evaluate_with(
            "1 || missing",
            |_| panic!("unreachable resolver"),
            |_| None,
            |_| None,
        );
        assert_eq!(result, Some(Constant::Number(1.0)));
        assert_eq!(evaluate("0 ? missing : seed"), Some(Constant::Number(5.0)));
    }
    #[test]
    fn backend_supplied_decoding_preserves_non_utf8_bytes() {
        let result = evaluate_with(
            "\"encoded\"",
            |_| None,
            |_| Some(vec![0xff, 0x80]),
            |_| None,
        );
        assert_eq!(result, Some(Constant::EncodedText(vec![0xff, 0x80])));
        assert_eq!(
            Constant::Text("a".into()).canonical_bytes(),
            Constant::EncodedText(vec![b'a']).canonical_bytes()
        );
    }
    #[test]
    fn parsed_decoder_borrows_the_exact_issued_literal_and_preserves_policy() {
        let parsed = parse_expression(r#""[unobserved()]""#);
        assert!(parsed.diagnostics.is_empty());
        let expression = parsed.expr.as_ref().unwrap();
        let ExprKind::Literal(issued) = &expression.kind else {
            panic!()
        };
        let parts = issued.parts().unwrap().unwrap();
        let seen = std::cell::Cell::new(0);
        let result = evaluate_expr_with_resources(
            expression,
            |_| None,
            |received| {
                assert!(std::ptr::eq(received, issued));
                assert!(std::ptr::eq(received.parts().unwrap().unwrap(), parts));
                seen.set(seen.get() + 1);
                // The evaluator must preserve its caller's decoding contract rather
                // than silently replace it with an additional builtin policy.
                Some(vec![0xff, 0x80])
            },
            |_| None,
            |_| None,
        );
        assert_eq!(seen.get(), 1);
        assert_eq!(result, Some(Constant::EncodedText(vec![0xff, 0x80])));
    }

    #[test]
    fn unsupported_runtime_and_list_expressions_remain_unresolved() {
        assert_eq!(evaluate("list(1,2)"), None);
        assert_eq!(evaluate("rand(1,2)"), None);
        assert_eq!(evaluate("unknown"), None);
    }
}

#[cfg(test)]
#[path="constants_try_tests.rs"]
mod try_tests;
