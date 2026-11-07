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

/// Typed failures from the same descriptor normalization traversal.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ModifiedCaptureError {
    InvalidNameofReference,
    Unsupported(String),
}
impl std::fmt::Display for ModifiedCaptureError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::InvalidNameofReference => {
                f.write_str("nameof: requires a var, proc reference, or type path")
            }
            Self::Unsupported(reason) => f.write_str(reason),
        }
    }
}
impl From<String> for ModifiedCaptureError {
    fn from(reason: String) -> Self {
        Self::Unsupported(reason)
    }
}
impl From<&str> for ModifiedCaptureError {
    fn from(reason: &str) -> Self {
        Self::Unsupported(reason.into())
    }
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
        decode: impl Fn(&dm_syntax::LiteralText) -> Option<Vec<u8>>,
        calls: Option<&dyn crate::constants::PureCalls>,
        resource: impl Fn(&str) -> Result<CapturedModifiedResource, String>,
    ) -> Result<Self, String> {
        Self::capture_with_resources_and_nameof_observer(
            runtime_type,
            lexical_owner,
            resource_context,
            fields,
            decode,
            calls,
            resource,
            None,
        )
    }

    pub fn capture_with_resources_and_nameof_observer(
        runtime_type: SymbolId,
        lexical_owner: SymbolId,
        resource_context: Option<u128>,
        fields: &[(String, Expr)],
        decode: impl Fn(&dm_syntax::LiteralText) -> Option<Vec<u8>>,
        calls: Option<&dyn crate::constants::PureCalls>,
        resource: impl Fn(&str) -> Result<CapturedModifiedResource, String>,
        observer: Option<&dyn Fn(&Expr)>,
    ) -> Result<Self, String> {
        Self::capture_with_resources_and_nameof_observer_checked(
            runtime_type,
            lexical_owner,
            resource_context,
            fields,
            decode,
            calls,
            resource,
            observer,
        )
        .map_err(|error| error.to_string())
    }
    pub fn capture_with_resources_and_nameof_observer_checked(
        runtime_type: SymbolId,
        lexical_owner: SymbolId,
        resource_context: Option<u128>,
        fields: &[(String, Expr)],
        decode: impl Fn(&dm_syntax::LiteralText) -> Option<Vec<u8>>,
        calls: Option<&dyn crate::constants::PureCalls>,
        resource: impl Fn(&str) -> Result<CapturedModifiedResource, String>,
        observer: Option<&dyn Fn(&Expr)>,
    ) -> Result<Self, ModifiedCaptureError> {
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
                    normalize_with_resources(value, &decode, calls, &capture, observer)?,
                ))
            })
            .collect::<Result<Vec<_>, ModifiedCaptureError>>()?;
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
        decode: impl Fn(&dm_syntax::LiteralText) -> Option<Vec<u8>>,
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
        ExprKind::Literal(value) => match value.original_value(){
            // Typed scalar/static facts are authoritative before grammar
            // spelling. Static String contains no lexical child/resource even
            // when its spelling resembles a resource or runtime decode refuses.
            Some(dm_syntax::OriginalTokenValue::Resource(_))=>true,
            Some(dm_syntax::OriginalTokenValue::Int(_)|dm_syntax::OriginalTokenValue::Float(_)|dm_syntax::OriginalTokenValue::String(_))=>false,
            // Current immutable OriginalLiteralData cannot issue other kinds.
            Some(_)=>true,
            None=>value.starts_with('\'') || value.parts().map_or(true, |parts| parts.is_some_and(|parts| parts.expressions.iter().any(contains_resources))),
        },
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
            if let Some(original)=value.original_value(){
                // SAME canonical descriptor stream, distinct typed-literal tag.
                // Full canonical bytes (PartialEq), never this descriptor's
                // short alias hash alone, decide identity. Raw spelling and TU
                // geometry are not substitutes for actual token VALUE facts.
                bytes.push(18);
                match original{
                    dm_syntax::OriginalTokenValue::Int(number)=>{bytes.push(0);bytes.extend_from_slice(&number.to_le_bytes());},
                    dm_syntax::OriginalTokenValue::Float(number)=>{bytes.push(1);bytes.extend_from_slice(&number.to_bits().to_le_bytes());},
                    dm_syntax::OriginalTokenValue::String(text_value)=>{bytes.push(2);bytes.push(value.original_string_mode().expect("actual Original owner") as u8);text(text_value,bytes);},
                    dm_syntax::OriginalTokenValue::Resource(path)=>{
                        bytes.push(3);text(path,bytes);
                        // Preserve existing raw-keyed captured resource proof
                        // contract while ALSO retaining exact typed path. This
                        // does not pretend raw->typed resource binding is issued.
                        if let Some(proof)=resources.get(value.as_str()){
                            bytes.push(1);bytes.extend_from_slice(&proof.content.to_le_bytes());
                        }else{bytes.push(0);}
                    },
                    _=>unreachable!("immutable Original literal owner issued a non-scalar/template variant"),
                }
                return;
            }
            if let Some(proof) = resources.get(value.as_str()) {
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
    decode: &impl Fn(&dm_syntax::LiteralText) -> Option<Vec<u8>>,
    calls: Option<&dyn crate::constants::PureCalls>,
    capture: &impl Fn(&str) -> Result<(), String>,
    observer: Option<&dyn Fn(&Expr)>,
) -> Result<Expr, ModifiedCaptureError> {
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
    if let Some(scalar) = constants::evaluate_expr_with_resources_and_calls_and_nameof_observer(
        value,
        |_| None,
        decode,
        |_| None,
        |_| None,
        calls,
        observer,
    )
    .map_err(|error| error.reason)?
    {
        let kind = match scalar {
            Constant::Number(number) if number.is_finite() => ExprKind::Literal(number.to_string().into()),
            Constant::Text(text) => {
                ExprKind::Literal(serde_json::to_string(&text).map_err(|error| error.to_string())?.into())
            }
            Constant::EncodedText(bytes) => ExprKind::Literal(
                serde_json::to_string(&String::from_utf8(bytes).map_err(|_| {
                    "modified scalar text needs an exact byte-valued representation"
                })?)
                .map_err(|error| error.to_string())?.into(),
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
        ExprKind::Group(inner) => {
            return normalize_with_resources(inner, decode, calls, capture, observer)
        }
        ExprKind::Unary { value, .. } => {
            **value = normalize_with_resources(value, decode, calls, capture, observer)?
        }
        ExprKind::Binary { lhs, rhs, .. } => {
            **lhs = normalize_with_resources(lhs, decode, calls, capture, observer)?;
            **rhs = normalize_with_resources(rhs, decode, calls, capture, observer)?;
        }
        ExprKind::Conditional {
            condition,
            then_value,
            else_value,
        } => {
            **condition = normalize_with_resources(condition, decode, calls, capture, observer)?;
            **then_value = normalize_with_resources(then_value, decode, calls, capture, observer)?;
            **else_value = normalize_with_resources(else_value, decode, calls, capture, observer)?;
        }
        // Evaluated nameof could not resolve a reference in this descriptor
        // context. Short-circuited calls were already folded by the common
        // constant evaluator above and never reach this rejection.
        ExprKind::Call { callee, args }
            if matches!(&callee.kind, ExprKind::Ident(name) if name == "nameof")
                && matches!(
                    args.as_slice(),
                    [Expr {
                        kind: ExprKind::Member { .. } | ExprKind::StaticMember { .. },
                        ..
                    }]
                ) =>
        {
            return Err(ModifiedCaptureError::InvalidNameofReference);
        }
        ExprKind::Call { callee, args } if matches!(&callee.kind,ExprKind::Ident(name) if name=="list" || name=="newlist") => {
            for value in args {
                if let ExprKind::Binary { op, lhs, rhs } = &mut value.kind {
                    if op == "=" {
                        if !matches!(&lhs.kind, ExprKind::Ident(_)) {
                            **lhs =
                                normalize_with_resources(lhs, decode, calls, capture, observer)?;
                        }
                        **rhs = normalize_with_resources(rhs, decode, calls, capture, observer)?;
                        continue;
                    }
                }
                *value = normalize_with_resources(value, decode, calls, capture, observer)?;
            }
        }
        ExprKind::ObjectInitializer { fields, .. } => {
            for (_, value) in fields {
                *value = normalize_with_resources(value, decode, calls, capture, observer)?;
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
    fn skipped_nameof_observation_preserves_modified_value_and_canonical_recipe() {
        let value = dm_syntax::parse_expression("/obj{a=0 && nameof(world.cpu)}")
            .expr
            .unwrap();
        let ExprKind::ObjectInitializer { fields, .. } = value.kind else {
            panic!("descriptor")
        };
        let count = std::cell::Cell::new(0);
        let observe = |reference: &Expr| {
            assert!(
                matches!(&reference.kind, ExprKind::Member { selector, .. } if selector == "cpu")
            );
            count.set(count.get() + 1);
        };
        let observed = ModifiedInstance::capture_with_resources_and_nameof_observer(
            SymbolId::of("/obj"),
            SymbolId::of("/datum"),
            None,
            &fields,
            |_| None,
            None,
            |_| panic!("no resource access"),
            Some(&observe),
        )
        .unwrap();
        let plain = ModifiedInstance::capture_with_resources(
            SymbolId::of("/obj"),
            SymbolId::of("/datum"),
            None,
            &fields,
            |_| None,
            None,
            |_| panic!("no resource access"),
        )
        .unwrap();
        assert_eq!(count.get(), 1);
        assert_eq!(observed, plain);
        assert_eq!(observed.canonical_bytes(), plain.canonical_bytes());
        let direct = dm_syntax::parse_expression("nameof(world.cpu)")
            .expr
            .unwrap();
        assert!(
            ModifiedInstance::capture_with_resources_and_nameof_observer(
                SymbolId::of("/obj"),
                SymbolId::of("/datum"),
                None,
                &[("a".into(), direct)],
                |_| None,
                None,
                |_| panic!("no resource access"),
                Some(&observe),
            )
            .is_err()
        );
    }

    #[test]
    fn modified_nameof_typed_failure_preserves_opaque_and_skipped_cases() {
        for (source, invalid_nameof, accepted) in [
            ("nameof(world.cpu)", true, false),
            ("nameof(/obj::icon)", true, false),
            ("0 && nameof(world.cpu)", false, true),
            ("unknown_call()", false, false),
        ] {
            let value = dm_syntax::parse_expression(source).expr.unwrap();
            let result = ModifiedInstance::capture_with_resources_and_nameof_observer_checked(
                SymbolId::of("/obj"),
                SymbolId::of("/datum"),
                None,
                &[("a".into(), value)],
                |_| None,
                None,
                |_| panic!("no resource access"),
                None,
            );
            if accepted {
                assert!(result.is_ok());
            } else if invalid_nameof {
                assert_eq!(
                    result.unwrap_err(),
                    ModifiedCaptureError::InvalidNameofReference
                );
            } else {
                assert!(matches!(result, Err(ModifiedCaptureError::Unsupported(_))));
            }
        }
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

#[cfg(test)]mod original_literal_canonical_tests{
 use super::*;use dm_syntax::{OriginalTokenValue as V,LiteralText,SettingAdmission};use std::sync::atomic::{Ordering};
 fn literal(raw:&str,value:V<&str>,origin:usize,a:&SettingAdmission<'_>)->Expr{Expr{span:dm_syntax::Span::new(origin,origin+raw.len()),kind:ExprKind::Literal(LiteralText::from_original_value_data(raw.to_owned(),origin,value,a).unwrap())}}
 fn descriptor(value:Expr,context:Option<u128>)->ModifiedInstance{ModifiedInstance::capture(SymbolId::of("/obj"),SymbolId::of("/datum"),context,&[("value".into(),value)])}
 #[test]fn same_raw_spelling_never_aliases_distinct_actual_variant_float_bits_or_static_value(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);let values=[V::Int(0),V::Float(0.0),V::Float(-0.0),V::Float(f32::from_bits(0x7fc00111)),V::Float(f32::from_bits(0x7fc00222)),V::String("[static]"),V::String("\"static\""),V::Resource("actual/path")];
  let all:Vec<_>=values.into_iter().map(|value|descriptor(literal("same raw",value,0,&a),None)).collect();for(i,left)in all.iter().enumerate(){for right in &all[i+1..]{assert_ne!(left.canonical_bytes(),right.canonical_bytes());assert_ne!(left,right,"canonical equality must include actual variant/value, not an alias hash");}}drop(all);assert_eq!(counter.load(Ordering::Acquire),dm_syntax::SettingChargeCounter::root_allocation_bytes());
 }
 #[test]fn exact_typed_value_ignores_cosmetic_raw_and_geometry_while_native_canonical_rules_stay_unchanged(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);let left=descriptor(literal("2147483648",V::Int(0),0,&a),None);let right=descriptor(literal("0",V::Int(0),200,&a),None);assert_eq!(left,right);let native=|raw:&str|descriptor(dm_syntax::parse_expression(raw).expr.unwrap(),None);assert_eq!(native("1"),native("1.0"));assert_ne!(left,native("0"),"Original typed recipe is separate from Native spelling inference");
 }
 #[test]fn only_actual_typed_resource_requires_context_and_raw_key_proof_cannot_override_scalar(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);for value in [V::Int(0),V::Float(1.0),V::String("[resource-looking]")]{let result=descriptor(literal("'looks_like_resource'",value,0,&a),Some(91));assert!(!result.requires_captured_resources());assert_eq!(result.resource_context(),None);}let result=descriptor(literal("not_resource_spelling",V::Resource("actual/path"),0,&a),Some(91));assert!(result.requires_captured_resources());assert_eq!(result.resource_context(),Some(91));
  let value=literal("'looks_like_resource'",V::Int(0),0,&a);let proof=CapturedModifiedResource{path:SymbolId::of("actual/path"),content:123};let mut with=Vec::new();let mut plain=Vec::new();expression(&value,&mut with,&BTreeMap::from([("'looks_like_resource'".into(),proof)]));expression(&value,&mut plain,&BTreeMap::new());assert_eq!(with,plain,"resource proof lookup is not allowed to replace genuine numeric VALUE");
 }
 #[test]fn actual_typed_resource_value_and_captured_content_both_enter_canonical_recipe(){
  let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let poll=||Ok(());let a=SettingAdmission::new(&counter,1<<20,&poll);let left=literal("'raw'",V::Resource("first/path"),0,&a);let right=literal("'raw'",V::Resource("second/path"),0,&a);let encode=|value:&Expr,content|{let mut out=Vec::new();expression(value,&mut out,&BTreeMap::from([("'raw'".into(),CapturedModifiedResource{path:SymbolId::of("bound"),content})]));out};assert_ne!(encode(&left,1),encode(&right,1));assert_ne!(encode(&left,1),encode(&left,2));
 }
}

#[cfg(test)]mod original_string_mode_fingerprint_tests{
 use super::*;use std::sync::{Arc};
 #[test]fn canonical_original_string_facts_include_actual_lexical_mode(){let counter=dm_syntax::SettingChargeCounter::try_new(dm_syntax::SettingChargeCounter::root_allocation_bytes()).unwrap();let a=dm_syntax::SettingAdmission::new(&counter,1<<20,&||Ok(()));let mut recipes=Vec::new();for mode in [dm_syntax::OriginalStringMode::Unknown,dm_syntax::OriginalStringMode::Normal,dm_syntax::OriginalStringMode::Raw,dm_syntax::OriginalStringMode::Generated]{let literal=dm_syntax::LiteralText::from_original_value_with_mode_data("same".into(),0,dm_syntax::OriginalTokenValue::String("same"),mode,&a).unwrap();let expr=Expr{span:dm_syntax::Span::new(0,4),kind:ExprKind::Literal(literal)};let mut bytes=Vec::new();expression(&expr,&mut bytes,&BTreeMap::new());assert!(!recipes.contains(&bytes));recipes.push(bytes);}}
}
