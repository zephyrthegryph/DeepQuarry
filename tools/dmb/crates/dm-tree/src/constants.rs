//! Authoritative scalar declaration evaluator extracted from the preserved compiler.
//! String escape interpretation and nameof are supplied by the syntax adapter so
//! this crate does not depend on BYOND encoding or lowering. Unknown/runtime/list
//! expressions return None; they must not be cached as a negative declaration.
//! Pure evaluation of declaration expressions. Runtime operations remain unfurled.
use dm_syntax::{parse_expression, Expr, ExprKind};

#[derive(Clone, Debug, PartialEq)]
pub enum Constant {
    Null,
    Number(f32),
    Text(String),
    EncodedText(Vec<u8>),
    TypePath(String),
    Resource(dm_ir::SymbolId),
}
impl Constant {
    fn truth(&self) -> bool {
        match self {
            Self::Null => false,
            Self::Number(n) => *n != 0.0,
            Self::Text(s) => !s.is_empty(),
            Self::EncodedText(s) => !s.is_empty(),
            Self::TypePath(_) | Self::Resource(_) => true,
        }
    }
    fn number(&self) -> Option<f32> {
        match self {
            Self::Number(n) => Some(*n),
            _ => None,
        }
    }
}

pub fn evaluate_with(
    source: &str,
    resolve: impl Fn(&str) -> Option<Constant>,
    decode: impl Fn(&str) -> Option<Vec<u8>>,
    nameof: impl Fn(&Expr) -> Option<String>,
) -> Option<Constant> {
    evaluate_with_resources(source, resolve, decode, nameof, |_| None)
}
/// Resource literals are admitted only by an explicit captured search callback.
/// The compatibility evaluator above continues to decline resource literals.
pub fn evaluate_with_resources(
    source: &str,
    resolve: impl Fn(&str) -> Option<Constant>,
    decode: impl Fn(&str) -> Option<Vec<u8>>,
    nameof: impl Fn(&Expr) -> Option<String>,
    resource: impl Fn(&str) -> Option<dm_ir::SymbolId>,
) -> Option<Constant> {
    let parsed = parse_expression(source);
    if !parsed.diagnostics.is_empty() {
        return None;
    }
    evaluate_expr_with_resources(parsed.expr.as_ref()?, resolve, decode, nameof, resource)
}
/// Evaluate an already parsed expression through the same scalar interpreter.
/// The caller owns syntax diagnostics and supplies the same captured callbacks
/// as the string entry; this API neither reparses nor infers resource authority.
pub fn evaluate_expr_with_resources(
    expression: &Expr,
    resolve: impl Fn(&str) -> Option<Constant>,
    decode: impl Fn(&str) -> Option<Vec<u8>>,
    nameof: impl Fn(&Expr) -> Option<String>,
    resource: impl Fn(&str) -> Option<dm_ir::SymbolId>,
) -> Option<Constant> {
    eval(expression, &resolve, &decode, &nameof, &resource)
}
fn eval(
    expr: &Expr,
    resolve: &impl Fn(&str) -> Option<Constant>,
    decode: &impl Fn(&str) -> Option<Vec<u8>>,
    nameof: &impl Fn(&Expr) -> Option<String>,
    resource: &impl Fn(&str) -> Option<dm_ir::SymbolId>,
) -> Option<Constant> {
    use Constant::*;
    let boolean = |value| Number(if value { 1.0 } else { 0.0 });
    let result = match &expr.kind {
        ExprKind::Ident(name) if name == "null" => Null,
        ExprKind::Ident(name) => resolve(name)?,
        ExprKind::TypePath(path) => TypePath(path.clone()),
        ExprKind::StaticMember { object, selector } => {
            let TypePath(path) = eval(object, resolve, decode, nameof, resource)? else {
                return None;
            };
            resolve(&format!("{path}::{selector}"))?
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "nameof") =>
        {
            let [argument] = args.as_slice() else {
                return None;
            };
            Text(nameof(argument)?)
        }
        ExprKind::Literal(raw) if raw.starts_with('\'') && raw.ends_with('\'') => {
            Resource(resource(raw)?)
        }
        ExprKind::Literal(raw) if raw == "null" => Null,
        ExprKind::Literal(raw) if raw == "1.#INF" => Number(f32::INFINITY),
        ExprKind::Literal(raw) => {
            if (raw.starts_with('"') && raw.ends_with('"'))
                || (raw.starts_with("{\"") && raw.ends_with("\"}"))
                || raw.starts_with('@')
            {
                let bytes = decode(raw)?;
                match String::from_utf8(bytes) {
                    Ok(text) => Text(text),
                    Err(error) => EncodedText(error.into_bytes()),
                }
            } else {
                let n = if let Some(hex) = raw.strip_prefix("0x").or_else(|| raw.strip_prefix("0X"))
                {
                    u32::from_str_radix(hex, 16).ok()? as f32
                } else {
                    raw.parse::<f32>().ok()?
                };
                Number(n)
            }
        }
        ExprKind::Group(inner) => eval(inner, resolve, decode, nameof, resource)?,
        ExprKind::Unary { op, value } => {
            let value = eval(value, resolve, decode, nameof, resource)?;
            match op.as_str() {
                "!" => boolean(!value.truth()),
                "+" => Number(value.number()?),
                "-" => Number(-value.number()?),
                "~" => Number((!(value.number()? as i32) & 0xffffff) as f32),
                _ => return None,
            }
        }
        ExprKind::Binary { op, lhs, rhs } => {
            let left = eval(lhs, resolve, decode, nameof, resource)?;
            if op == "&&" {
                return if left.truth() {
                    eval(rhs, resolve, decode, nameof, resource)
                } else {
                    Some(left)
                };
            }
            if op == "||" {
                return if left.truth() {
                    Some(left)
                } else {
                    eval(rhs, resolve, decode, nameof, resource)
                };
            }
            let right = eval(rhs, resolve, decode, nameof, resource)?;
            // Authored lookup paths are not runtime content identities. Do not
            // fold resource comparisons/arithmetic from path equality.
            if matches!(left, Resource(_)) || matches!(right, Resource(_)) {
                return None;
            }
            if op == "+" {
                if let (Text(a), Text(b)) = (&left, &right) {
                    return Some(Text(format!("{a}{b}")));
                }
                let bytes = |value: &Constant| match value {
                    Text(text) => Some(text.as_bytes().to_vec()),
                    EncodedText(text) => Some(text.clone()),
                    _ => None,
                };
                if let (Some(mut a), Some(b)) = (bytes(&left), bytes(&right)) {
                    a.extend(b);
                    return Some(EncodedText(a));
                }
            }
            if op == "==" || op == "!=" {
                if std::mem::discriminant(&left) != std::mem::discriminant(&right) {
                    return None;
                }
                return Some(boolean(if op == "==" {
                    left == right
                } else {
                    left != right
                }));
            }
            let a = left.number()?;
            let b = right.number()?;
            match op.as_str() {
                "+" => Number(a + b),
                "-" => Number(a - b),
                "*" => Number(a * b),
                "/" if b != 0.0 => Number(a / b),
                "%" if b != 0.0 => Number((a as i32).checked_rem(b as i32)? as f32),
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
                        return None;
                    }
                    Number(
                        ((a.max(0.0) as u32).wrapping_shl((b.max(0.0) as u32) & 31) & 0xffffff)
                            as f32,
                    )
                }
                ">>" => Number(((a as i32 & 0xffffff) >> ((b.max(0.0) as u32) & 31)) as f32),
                _ => return None,
            }
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => eval(
            if eval(condition, resolve, decode, nameof, resource)?.truth() {
                then_value
            } else {
                else_value
            },
            resolve,
            decode,
            nameof,
            resource,
        )?,
        _ => return None,
    };
    if matches!(result, Number(n) if n.is_nan()) {
        None
    } else {
        Some(result)
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
        symbols: &mut dm_ir::SymbolTable,
    ) -> Result<dm_ir::SemanticValue, dm_ir::SymbolCollision> {
        Ok(match self {
            Self::Null => dm_ir::SemanticValue::Null,
            Self::Number(number) => dm_ir::SemanticValue::NumberBits(number.to_bits()),
            Self::Text(text) => dm_ir::SemanticValue::Text(std::sync::Arc::from(text.as_bytes())),
            Self::EncodedText(text) => {
                dm_ir::SemanticValue::Text(std::sync::Arc::from(text.as_slice()))
            }
            Self::TypePath(path) => dm_ir::SemanticValue::Type(symbols.intern(path)?),
            Self::Resource(content) => dm_ir::SemanticValue::Resource(*content),
        })
    }
}

#[cfg(test)]
mod resource_tests {
    use super::*;
    #[test]
    fn resource_is_typed_and_requires_explicit_capture() {
        let path = dm_ir::SymbolId::of("asset.txt");
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
                .to_semantic(&mut dm_ir::SymbolTable::default())
                .unwrap(),
            dm_ir::SemanticValue::Resource(path)
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
        let path = dm_ir::SymbolId::of("asset.txt");
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
                let decode = |raw: &str| {
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
        let path = dm_ir::SymbolId::of("asset.txt");
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
    fn unsupported_runtime_and_list_expressions_remain_unresolved() {
        assert_eq!(evaluate("list(1,2)"), None);
        assert_eq!(evaluate("rand(1,2)"), None);
        assert_eq!(evaluate("unknown"), None);
    }
}
