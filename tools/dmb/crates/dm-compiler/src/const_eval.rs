//! Pure evaluation of declaration expressions. Runtime operations remain unfurled.
use dm_syntax::{parse_expression, Expr, ExprKind};

#[derive(Clone, Debug, PartialEq)]
pub(super) enum Constant {
    Null,
    Number(f32),
    Text(String),
    EncodedText(Vec<u8>),
    TypePath(String),
}
impl Constant {
    fn truth(&self) -> bool {
        match self {
            Self::Null => false,
            Self::Number(n) => *n != 0.0,
            Self::Text(s) => !s.is_empty(),
            Self::EncodedText(s) => !s.is_empty(),
            Self::TypePath(_) => true,
        }
    }
    fn number(&self) -> Option<f32> {
        match self {
            Self::Number(n) => Some(*n),
            _ => None,
        }
    }
}

pub(super) fn evaluate(
    source: &str,
    resolve: impl Fn(&str) -> Option<Constant>,
) -> Option<Constant> {
    let parsed = parse_expression(source);
    if !parsed.diagnostics.is_empty() {
        return None;
    }
    eval(parsed.expr.as_ref()?, &resolve)
}
fn eval(expr: &Expr, resolve: &impl Fn(&str) -> Option<Constant>) -> Option<Constant> {
    use Constant::*;
    let boolean = |value| Number(if value { 1.0 } else { 0.0 });
    let result = match &expr.kind {
        ExprKind::Ident(name) if name == "null" => Null,
        ExprKind::Ident(name) => resolve(name)?,
        ExprKind::TypePath(path) => TypePath(path.clone()),
        ExprKind::StaticMember { object, selector } => {
            let TypePath(path) = eval(object, resolve)? else {
                return None;
            };
            resolve(&format!("{path}::{selector}"))?
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind, ExprKind::Ident(name) if name == "nameof") =>
        {
            let [argument] = args.as_slice() else {
                return None;
            };
            Text(dm_codegen_byond::nameof_reference(argument)?.to_owned())
        }
        ExprKind::Literal(raw) if raw == "null" => Null,
        ExprKind::Literal(raw) if raw == "1.#INF" => Number(f32::INFINITY),
        ExprKind::Literal(raw) => {
            if (raw.starts_with('"') && raw.ends_with('"'))
                || (raw.starts_with("{\"") && raw.ends_with("\"}"))
                || raw.starts_with('@')
            {
                let bytes = dm_codegen_byond::decode_constant_string_literal(raw).ok()??;
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
        ExprKind::Group(inner) => eval(inner, resolve)?,
        ExprKind::Unary { op, value } => {
            let value = eval(value, resolve)?;
            match op.as_str() {
                "!" => boolean(!value.truth()),
                "+" => Number(value.number()?),
                "-" => Number(-value.number()?),
                "~" => Number((!(value.number()? as i32) & 0xffffff) as f32),
                _ => return None,
            }
        }
        ExprKind::Binary { op, lhs, rhs } => {
            let left = eval(lhs, resolve)?;
            if op == "&&" {
                return if left.truth() {
                    eval(rhs, resolve)
                } else {
                    Some(left)
                };
            }
            if op == "||" {
                return if left.truth() {
                    Some(left)
                } else {
                    eval(rhs, resolve)
                };
            }
            let right = eval(rhs, resolve)?;
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
            if eval(condition, resolve)?.truth() {
                then_value
            } else {
                else_value
            },
            resolve,
        )?,
        _ => return None,
    };
    if matches!(result, Number(n) if n.is_nan()) {
        None
    } else {
        Some(result)
    }
}
