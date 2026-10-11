//! Exact source-neutral current recipe; no retained classification handles/spans.
use super::receipts::{Binding, FragmentInputs, Inputs, Shape};
use crate::initializer_policy::DefaultValue;
use dm_ir::{InitializerWrite, ResolveQuery};
pub(super) struct Recipe {
    pub bytes: Vec<u8>,
    pub mandatory: Vec<ResolveQuery>,
    pub assembly: bool,
    pub modified_only: bool,
    pub roots: usize,
}
fn part(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    out.extend_from_slice(bytes);
}
fn write(out: &mut Vec<u8>, value: &FragmentInputs, required: &mut Vec<ResolveQuery>) {
    part(out, &value.write.canonical_bytes());
    out.push(u8::from(value.debug_enabled));
    match &value.shape {
        Shape::Expression => out.push(0),
        Shape::SizedArray(dims) | Shape::SizedArrayExplicit(dims, _) => {
            out.push(if matches!(value.shape, Shape::SizedArray(_)) {
                1
            } else {
                2
            });
            out.extend_from_slice(&(dims.len() as u64).to_le_bytes());
            for dim in dims.iter() {
                out.extend_from_slice(&dim.to_le_bytes());
            }
            if let Shape::SizedArrayExplicit(_, explicit) = value.shape {
                out.push(u8::from(explicit));
            }
        }
    }
    match value.resource_context {
        None => out.push(0),
        Some(value) => {
            out.push(1);
            out.extend_from_slice(&value.to_le_bytes());
        }
    }
    mandatory(&value.write, required);
}
fn mandatory(write: &InitializerWrite, queries: &mut Vec<ResolveQuery>) {
    queries.push(ResolveQuery::Ancestry(write.lexical_owner));
    if let Some(proc) = write.lexical_procedure {
        queries.push(ResolveQuery::Ancestry(proc.owner));
        queries.push(ResolveQuery::OverrideChain {
            owner: proc.owner,
            name: proc.name,
            verb: proc.verb,
        });
    }
}
pub(super) fn capture(
    binding: &Binding,
    policy: &[u8],
    engine: Option<(u128, bool, u128)>,
    roots: &[&dm_syntax::Expr],
) -> Option<Recipe> {
    capture_with_modified_policy(binding, policy, engine, roots, None)
}
pub(super) fn capture_with_modified_policy(
    binding: &Binding,
    policy: &[u8],
    engine: Option<(u128, bool, u128)>,
    roots: &[&dm_syntax::Expr],
    modified_policy: Option<&[u8]>,
) -> Option<Recipe> {
    let mut bytes = b"initializer-current-portable-recipe-v1\0".to_vec();
    bytes.extend_from_slice(&crate::lowering_memo::PROCEDURE_VERSION.to_le_bytes());
    part(&mut bytes, policy);
    match engine {
        None => bytes.push(0),
        Some((schema, bootstrap, compiler)) => {
            bytes.push(1);
            bytes.extend_from_slice(&schema.to_le_bytes());
            bytes.push(u8::from(bootstrap));
            bytes.extend_from_slice(&compiler.to_le_bytes());
        }
    }
    part(&mut bytes, &binding.key);
    let mut required = Vec::new();
    let assembly = match binding.inputs.as_ref() {
        Inputs::Fragment(input) if roots.len() == 1 => {
            bytes.push(0);
            write(&mut bytes, input, &mut required);
            false
        }
        Inputs::Assembly { receiver, writes } if writes.len() == roots.len() => {
            bytes.push(1);
            match receiver {
                None => bytes.push(0),
                Some(owner) => {
                    bytes.push(1);
                    bytes.extend_from_slice(&owner.bits().to_le_bytes());
                }
            }
            bytes.extend_from_slice(&(writes.len() as u64).to_le_bytes());
            for row in writes {
                let Inputs::Fragment(input) = row.fragment.as_ref() else {
                    return None;
                };
                write(&mut bytes, input, &mut required);
                match &row.default {
                    DefaultValue::Scalar(value) => {
                        bytes.push(0);
                        part(&mut bytes, &value.canonical_bytes());
                    }
                    DefaultValue::InitializerExpression { token, canonical } => {
                        bytes.push(1);
                        bytes.extend_from_slice(&token.to_le_bytes());
                        part(&mut bytes, canonical);
                    }
                    DefaultValue::Transform(_) => return None,
                }
            }
            true
        }
        Inputs::Modified {
            canonical,
            lexical_owner,
            runtime_type,
            field_count,
            resource_context,
            ..
        } if resource_context.is_none() && !roots.is_empty() && roots.len() == *field_count => {
            // The standalone modified producer may use a different PureCalls
            // provider from the ordinary initializer factory. Exact bytes are
            // mandatory; resident identity alone cannot license disk reuse.
            let pure = modified_policy?;
            bytes.push(2);
            part(&mut bytes, canonical);
            part(&mut bytes, pure);
            bytes.extend_from_slice(&lexical_owner.bits().to_le_bytes());
            bytes.extend_from_slice(&runtime_type.bits().to_le_bytes());
            bytes.extend_from_slice(&(roots.len() as u64).to_le_bytes());
            required.push(ResolveQuery::Ancestry(*lexical_owner));
            required.push(ResolveQuery::RuntimeType(*runtime_type));
            true
        }
        _ => return None,
    };
    for root in roots {
        expression(&mut bytes, root, 0)?;
    }
    required.sort();
    required.dedup();
    (bytes.len() <= super::disk::LIMIT).then_some(Recipe {
        bytes,
        mandatory: required,
        assembly,
        modified_only: matches!(binding.inputs.as_ref(), Inputs::Modified { .. }),
        roots: roots.len(),
    })
}
/// Complete AST kind encoding. Current source spans are intentionally not values.
fn expression(out: &mut Vec<u8>, value: &dm_syntax::Expr, depth: usize) -> Option<()> {
    use dm_syntax::ExprKind::*;
    if depth > 256 || out.len() > super::disk::LIMIT {
        return None;
    }
    let child = |out: &mut Vec<u8>, value: &dm_syntax::Expr| expression(out, value, depth + 1);
    match &value.kind {
        // Until an exact portable resource closure is shared with this stage,
        // resource-bearing recipes execute the ordinary producer.
        Literal(text) if text.starts_with('\'') => return None,
        Ident(text) | Literal(text) | TypePath(text) => {
            out.push(match value.kind {
                Ident(_) => 0,
                Literal(_) => 1,
                _ => 2,
            });
            part(out, text.as_bytes());
        }
        Unary { op, value } => {
            out.push(3);
            part(out, op.as_bytes());
            child(out, value)?;
        }
        Binary { op, lhs, rhs } => {
            out.push(4);
            part(out, op.as_bytes());
            child(out, lhs)?;
            child(out, rhs)?;
        }
        Conditional {
            condition,
            then_value,
            else_value,
        } => {
            out.push(5);
            child(out, condition)?;
            child(out, then_value)?;
            child(out, else_value)?;
        }
        Call { callee, args } => {
            out.push(6);
            child(out, callee)?;
            out.extend_from_slice(&(args.len() as u64).to_le_bytes());
            for arg in args {
                child(out, arg)?;
            }
        }
        Member {
            object,
            selector,
            via_colon,
        } => {
            out.push(7);
            out.push(u8::from(*via_colon));
            child(out, object)?;
            part(out, selector.as_bytes());
        }
        StaticMember { object, selector } | SafeMember { object, selector } => {
            out.push(if matches!(value.kind, StaticMember { .. }) {
                8
            } else {
                9
            });
            child(out, object)?;
            part(out, selector.as_bytes());
        }
        TypeFilter { value, types } => {
            out.push(10);
            child(out, value)?;
            out.extend_from_slice(&(types.len() as u64).to_le_bytes());
            for item in types {
                part(out, item.as_bytes());
            }
        }
        ObjectInitializer { object, fields } => {
            out.push(11);
            child(out, object)?;
            out.extend_from_slice(&(fields.len() as u64).to_le_bytes());
            for (name, value) in fields {
                part(out, name.as_bytes());
                child(out, value)?;
            }
        }
        Index { object, index } | SafeIndex { object, index } => {
            out.push(if matches!(value.kind, Index { .. }) {
                12
            } else {
                13
            });
            child(out, object)?;
            child(out, index)?;
        }
        Group(value) => {
            out.push(14);
            child(out, value)?;
        }
    }
    Some(())
}
