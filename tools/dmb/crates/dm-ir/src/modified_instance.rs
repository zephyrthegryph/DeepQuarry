//! Anonymous type-value descriptors. Their VM type remains the original type;
//! ordered authored assignments execute in a separate instance initializer.
use crate::SymbolId;
use dm_syntax::{Expr, ExprKind};
use std::{collections::BTreeMap, sync::Arc};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CapturedModifiedResource {
    pub path: SymbolId,
    pub content: u128,
}

#[derive(Clone, Debug)]
pub struct ModifiedInstance {
    runtime_type: SymbolId,
    lexical_owner: SymbolId,
    resource_context: Option<u128>,
    fields: Arc<[(String, Expr)]>,
    canonical: Arc<[u8]>,
    resources: Arc<BTreeMap<String, CapturedModifiedResource>>,
}
impl PartialEq for ModifiedInstance {
    fn eq(&self, other: &Self) -> bool {
        self.canonical == other.canonical
    }
}
impl Eq for ModifiedInstance {}
impl ModifiedInstance {
    pub fn capture_with_resources(
        runtime_type: SymbolId,
        lexical_owner: SymbolId,
        resource_context: Option<u128>,
        fields: &[(String, Expr)],
        decode: impl Fn(&str) -> Option<Vec<u8>>,
        calls: Option<&dyn crate::constants::PureCalls>,
        resource: impl Fn(&str) -> Result<CapturedModifiedResource, String>,
    ) -> Result<Self, String> {
        let proofs = std::cell::RefCell::new(BTreeMap::new());
        let capture = |raw: &str| {
            let path = raw
                .strip_prefix('\'')
                .and_then(|value| value.strip_suffix('\''))
                .ok_or("malformed modified resource literal")?;
            if path.contains(['\\', '[', ']']) {
                return Err("escaped or interpolated modified resource path is unsupported".into());
            }
            let proof = resource(path)?;
            let previous = proofs.borrow_mut().insert(raw.to_owned(), proof);
            if previous.is_some_and(|previous| previous != proof) {
                return Err("modified resource lookup changed during capture".into());
            }
            Ok(())
        };
        let fields = fields
            .iter()
            .map(|(name, value)| {
                Ok((
                    name.clone(),
                    normalize_with_resources(value, &decode, calls, &capture)?,
                ))
            })
            .collect::<Result<Vec<_>, String>>()?;
        let mut result = Self::capture(runtime_type, lexical_owner, resource_context, &fields);
        result.resources = Arc::new(proofs.into_inner());
        let mut bytes = b"dm-modified-instance-v2\0".to_vec();
        bytes.extend_from_slice(&runtime_type.bits().to_le_bytes());
        fields_bytes(result.fields(), &mut bytes, &result.resources);
        result.canonical = bytes.into();
        Ok(result)
    }
    pub fn resources(&self) -> &BTreeMap<String, CapturedModifiedResource> {
        &self.resources
    }
    pub fn capture_with_policy(
        runtime_type: SymbolId,
        lexical_owner: SymbolId,
        resource_context: Option<u128>,
        fields: &[(String, Expr)],
        decode: impl Fn(&str) -> Option<Vec<u8>>,
        calls: Option<&dyn crate::constants::PureCalls>,
    ) -> Result<Self, String> {
        Self::capture_with_resources(
            runtime_type,
            lexical_owner,
            resource_context,
            fields,
            decode,
            calls,
            |_| Err("modified resource requires captured payload identity".into()),
        )
    }
    pub fn capture(
        runtime_type: SymbolId,
        lexical_owner: SymbolId,
        resource_context: Option<u128>,
        fields: &[(String, Expr)],
    ) -> Self {
        let resource_context = fields
            .iter()
            .any(|(_, value)| contains_resources(value))
            .then_some(resource_context)
            .flatten();
        let mut bytes = b"dm-modified-instance-v1\0".to_vec();
        bytes.extend_from_slice(&runtime_type.bits().to_le_bytes());
        match resource_context {
            Some(value) => {
                bytes.push(1);
                bytes.extend_from_slice(&value.to_le_bytes());
            }
            None => bytes.push(0),
        }
        // Distinct field order does not distinguish native descriptors. Stable
        // sorting preserves repeated writes to the same field (last wins).
        fields_bytes(fields, &mut bytes, &BTreeMap::new());
        let mut ordered_fields = fields.to_vec();
        ordered_fields.sort_by(|left, right| left.0.cmp(&right.0));
        Self {
            runtime_type,
            lexical_owner,
            resource_context,
            fields: ordered_fields.into(),
            canonical: bytes.into(),
            resources: Arc::new(BTreeMap::new()),
        }
    }
    pub fn canonical_bytes(&self) -> &[u8] {
        &self.canonical
    }
    pub fn runtime_type(&self) -> SymbolId {
        self.runtime_type
    }
    pub fn lexical_owner(&self) -> SymbolId {
        self.lexical_owner
    }
    pub fn resource_context(&self) -> Option<u128> {
        self.resource_context
    }
    pub fn fields(&self) -> &[(String, Expr)] {
        &self.fields
    }
    pub fn requires_captured_resources(&self) -> bool {
        self.fields
            .iter()
            .any(|(_, value)| contains_resources(value))
    }
    pub fn alias(&self) -> String {
        format!(
            "modified-instance:{:032x}",
            xxhash_rust::xxh3::xxh3_128(&self.canonical)
        )
    }
}
fn contains_resources(value: &Expr) -> bool {
    match &value.kind {
        ExprKind::Literal(value) => value.starts_with('\''),
        ExprKind::Unary { value, .. }
        | ExprKind::Group(value)
        | ExprKind::TypeFilter { value, .. } => contains_resources(value),
        ExprKind::Member { object, .. }
        | ExprKind::StaticMember { object, .. }
        | ExprKind::SafeMember { object, .. } => contains_resources(object),
        ExprKind::Binary { lhs, rhs, .. } => contains_resources(lhs) || contains_resources(rhs),
        ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
            contains_resources(object) || contains_resources(index)
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            contains_resources(condition)
                || contains_resources(then_value)
                || contains_resources(else_value)
        }
        ExprKind::Call { callee, args } => {
            contains_resources(callee) || args.iter().any(contains_resources)
        }
        ExprKind::ObjectInitializer { object, fields } => {
            contains_resources(object) || fields.iter().any(|(_, value)| contains_resources(value))
        }
        ExprKind::Ident(_) | ExprKind::TypePath(_) => false,
    }
}
fn text(value: &str, bytes: &mut Vec<u8>) {
    bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
    bytes.extend_from_slice(value.as_bytes());
}
fn fields_bytes(
    fields: &[(String, Expr)],
    bytes: &mut Vec<u8>,
    resources: &BTreeMap<String, CapturedModifiedResource>,
) {
    bytes.extend_from_slice(&(fields.len() as u64).to_le_bytes());
    let mut fields = fields.iter().collect::<Vec<_>>();
    fields.sort_by(|left, right| left.0.cmp(&right.0));
    for (name, value) in fields {
        text(name, bytes);
        expression(value, bytes, resources);
    }
}
fn expression(
    value: &Expr,
    bytes: &mut Vec<u8>,
    resources: &BTreeMap<String, CapturedModifiedResource>,
) {
    match &value.kind {
        ExprKind::Ident(value) => {
            bytes.push(0);
            text(value, bytes);
        }
        ExprKind::Literal(value) => {
            if let Some(proof) = resources.get(value) {
                bytes.push(17);
                bytes.extend_from_slice(&proof.content.to_le_bytes());
                return;
            }
            if let Ok(number) = value.parse::<f32>() {
                bytes.push(15);
                bytes.extend_from_slice(&number.to_bits().to_le_bytes());
                return;
            }
            if let Ok(text) = serde_json::from_str::<String>(value) {
                bytes.push(16);
                bytes.extend_from_slice(&(text.len() as u64).to_le_bytes());
                bytes.extend_from_slice(text.as_bytes());
                return;
            }
            bytes.push(1);
            text(value, bytes);
        }
        ExprKind::TypePath(value) => {
            bytes.push(2);
            text(value, bytes);
        }
        ExprKind::Unary { op, value } => {
            bytes.push(3);
            text(op, bytes);
            expression(value, bytes, resources);
        }
        ExprKind::Binary { op, lhs, rhs } => {
            bytes.push(4);
            text(op, bytes);
            expression(lhs, bytes, resources);
            expression(rhs, bytes, resources);
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            bytes.push(5);
            expression(condition, bytes, resources);
            expression(then_value, bytes, resources);
            expression(else_value, bytes, resources);
        }
        ExprKind::Call { callee, args } => {
            bytes.push(6);
            expression(callee, bytes, resources);
            bytes.extend_from_slice(&(args.len() as u64).to_le_bytes());
            for arg in args {
                expression(arg, bytes, resources);
            }
        }
        ExprKind::Member {
            object,
            selector,
            via_colon,
        } => {
            bytes.push(7);
            expression(object, bytes, resources);
            text(selector, bytes);
            bytes.push(u8::from(*via_colon));
        }
        ExprKind::StaticMember { object, selector } => {
            bytes.push(8);
            expression(object, bytes, resources);
            text(selector, bytes);
        }
        ExprKind::TypeFilter { value, types } => {
            bytes.push(9);
            expression(value, bytes, resources);
            bytes.extend_from_slice(&(types.len() as u64).to_le_bytes());
            for value in types {
                text(value, bytes);
            }
        }
        ExprKind::ObjectInitializer { object, fields } => {
            bytes.push(10);
            expression(object, bytes, resources);
            fields_bytes(fields, bytes, resources);
        }
        ExprKind::SafeMember {
            object,
            selector,
            via_colon,
        } => {
            bytes.push(11);
            expression(object, bytes, resources);
            text(selector, bytes);
            bytes.push(u8::from(*via_colon));
        }
        ExprKind::Index { object, index } => {
            bytes.push(12);
            expression(object, bytes, resources);
            expression(index, bytes, resources);
        }
        ExprKind::SafeIndex { object, index } => {
            bytes.push(13);
            expression(object, bytes, resources);
            expression(index, bytes, resources);
        }
        ExprKind::Group(value) => {
            bytes.push(14);
            expression(value, bytes, resources);
        }
    }
}
fn normalize_with_resources(
    value: &Expr,
    decode: &impl Fn(&str) -> Option<Vec<u8>>,
    calls: Option<&dyn crate::constants::PureCalls>,
    capture: &impl Fn(&str) -> Result<(), String>,
) -> Result<Expr, String> {
    use crate::constants::{self, Constant};
    if let ExprKind::Literal(raw) = &value.kind {
        if raw.starts_with('\'') {
            capture(raw)?;
            return Ok(value.clone());
        }
    }
    if contains_resources(value)
        && (matches!(
            &value.kind,
            ExprKind::Unary { .. } | ExprKind::Conditional { .. }
        ) || matches!(&value.kind, ExprKind::Binary { op, .. } if op != "="))
    {
        return Err("modified resource operator has no certified constant meaning".into());
    }
    if let Some(scalar) = constants::evaluate_expr_with_resources_and_calls(
        value,
        |_| None,
        decode,
        |_| None,
        |_| None,
        calls,
    )
    .map_err(|error| error.reason)?
    {
        let kind = match scalar {
            Constant::Number(number) if number.is_finite() => ExprKind::Literal(number.to_string()),
            Constant::Text(text) => {
                ExprKind::Literal(serde_json::to_string(&text).map_err(|error| error.to_string())?)
            }
            Constant::EncodedText(bytes) => ExprKind::Literal(
                serde_json::to_string(&String::from_utf8(bytes).map_err(|_| {
                    "modified scalar text needs an exact byte-valued representation"
                })?)
                .map_err(|error| error.to_string())?,
            ),
            Constant::Null => ExprKind::Ident("null".into()),
            Constant::TypePath(path) => ExprKind::TypePath(path),
            _ => return Err("modified scalar representation is unsupported".into()),
        };
        return Ok(Expr {
            kind,
            span: value.span,
        });
    }
    let mut result = value.clone();
    match &mut result.kind {
        ExprKind::Group(inner) => return normalize_with_resources(inner, decode, calls, capture),
        ExprKind::Unary { value, .. } => {
            **value = normalize_with_resources(value, decode, calls, capture)?
        }
        ExprKind::Binary { lhs, rhs, .. } => {
            **lhs = normalize_with_resources(lhs, decode, calls, capture)?;
            **rhs = normalize_with_resources(rhs, decode, calls, capture)?;
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            **condition = normalize_with_resources(condition, decode, calls, capture)?;
            **then_value = normalize_with_resources(then_value, decode, calls, capture)?;
            **else_value = normalize_with_resources(else_value, decode, calls, capture)?;
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind,ExprKind::Ident(name) if name=="list" || name=="newlist") => {
            for value in args {
                if let ExprKind::Binary { op, lhs, rhs } = &mut value.kind {
                    if op == "=" {
                        if !matches!(&lhs.kind, ExprKind::Ident(_)) {
                            **lhs = normalize_with_resources(lhs, decode, calls, capture)?;
                        }
                        **rhs = normalize_with_resources(rhs, decode, calls, capture)?;
                        continue;
                    }
                }
                *value = normalize_with_resources(value, decode, calls, capture)?;
            }
        }
        ExprKind::ObjectInitializer { fields, .. } => {
            for (_, value) in fields {
                *value = normalize_with_resources(value, decode, calls, capture)?;
            }
        }
        ExprKind::Ident(name) if name == "null" || name == "TRUE" || name == "FALSE" => (),
        ExprKind::TypePath(_) => (),
        _ => return Err("modified value has no certified constant or allocation meaning".into()),
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn capture(source: &str) -> ModifiedInstance {
        let value = dm_syntax::parse_expression(source).expr.unwrap();
        let ExprKind::ObjectInitializer { fields, .. } = value.kind else {
            panic!("descriptor")
        };
        ModifiedInstance::capture(SymbolId::of("/obj"), SymbolId::of("/datum"), None, &fields)
    }
    #[test]
    fn modified_recipe_distinguishes_safe_dot_from_safe_colon() {
        let dot = capture("/obj{a=W?.cpu}");
        let colon = capture("/obj{a=W?:cpu}");
        assert_ne!(dot.canonical_bytes(), colon.canonical_bytes());
        assert_eq!(
            colon.canonical_bytes(),
            capture(" /obj { a = W?:cpu }").canonical_bytes()
        );
    }

    #[test]
    fn identity_excludes_positions_but_preserves_order_values_and_empty_blocks() {
        let one = capture("/obj{a=1;b=2}");
        let shifted = capture("  /obj { a = 1; b = 2 }");
        assert_eq!(one.canonical_bytes(), shifted.canonical_bytes());
        assert_eq!(
            one.canonical_bytes(),
            capture("/obj{b=2;a=1}").canonical_bytes()
        );
        assert_ne!(
            one.canonical_bytes(),
            capture("/obj{a=2;b=2}").canonical_bytes()
        );
        assert_ne!(one.canonical_bytes(), capture("/obj{}").canonical_bytes());
    }
    #[test]
    fn captured_resource_payload_identity_deduplicates_aliases_and_contexts() {
        let capture = |source: &str, context: u128, content: u128| {
            let value = dm_syntax::parse_expression(source).expr.unwrap();
            let ExprKind::ObjectInitializer { fields, .. } = value.kind else {
                panic!("descriptor")
            };
            ModifiedInstance::capture_with_resources(
                SymbolId::of("/obj"),
                SymbolId::of("/datum"),
                Some(context),
                &fields,
                |_| None,
                None,
                |path| {
                    Ok(CapturedModifiedResource {
                        path: SymbolId::of(path),
                        content,
                    })
                },
            )
            .unwrap()
        };
        let first = capture("/obj{asset=list('one/asset.txt');amount=1+0}", 1, 7);
        let alias = capture("/obj{amount=(1);asset=list('two/asset.txt')}", 2, 7);
        assert_eq!(first, alias);
        assert_eq!(first.alias(), alias.alias());
        assert_ne!(
            first,
            capture("/obj{amount=1;asset=list('two/asset.txt')}", 2, 8)
        );
        assert_eq!(first.resources().len(), 1);
        assert_ne!(
            first.resources(),
            alias.resources(),
            "lookup provenance remains inspectable"
        );
        assert_eq!(
            crate::constants::Constant::ModifiedInstance(Arc::new(first)),
            crate::constants::Constant::ModifiedInstance(Arc::new(alias))
        );
    }
    #[test]
    fn resource_capture_requires_positive_stable_proof() {
        let value = dm_syntax::parse_expression("/obj{asset='asset.txt'}")
            .expr
            .unwrap();
        let ExprKind::ObjectInitializer { fields, .. } = value.kind else {
            panic!("descriptor")
        };
        assert!(ModifiedInstance::capture_with_policy(
            SymbolId::of("/obj"),
            SymbolId::of("/"),
            None,
            &fields,
            |_| None,
            None
        )
        .is_err());
    }
}
