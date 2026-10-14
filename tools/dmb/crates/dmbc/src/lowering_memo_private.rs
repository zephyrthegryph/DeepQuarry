//! Private executable wire values pass through the validated descriptor issuer, never a
//! deserialization route into private cached canonical/semantic fields.
use dm_codegen_byond::lower_resolver::CapturedModifiedInstance;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId};
use dm_syntax::{Expr, ExprKind, Span};
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
enum ExprWire {
    Ident(String),
    Literal(String),
    TypePath(String),
    Unary(String, Box<Self>),
    Binary(String, Box<Self>, Box<Self>),
    Conditional(Box<Self>, Box<Self>, Box<Self>),
    Call(Box<Self>, Vec<Self>),
    Member(Box<Self>, String, bool),
    StaticMember(Box<Self>, String),
    TypeFilter(Box<Self>, Vec<String>),
    Object(Box<Self>, Vec<(String, Self)>),
    SafeMember(Box<Self>, String, bool),
    Index(Box<Self>, Box<Self>),
    SafeIndex(Box<Self>, Box<Self>),
    Group(Box<Self>),
}
// Private AST data must be bounded before recursive serde decoding, as well as
// before reconstruction. The budget belongs to this thread's current decode.
#[derive(Deserialize)]
#[serde(remote = "ExprWire")]
enum ExprWireSerde {
    Ident(String),
    Literal(String),
    TypePath(String),
    Unary(String, Box<ExprWire>),
    Binary(String, Box<ExprWire>, Box<ExprWire>),
    Conditional(Box<ExprWire>, Box<ExprWire>, Box<ExprWire>),
    Call(Box<ExprWire>, Vec<ExprWire>),
    Member(Box<ExprWire>, String, bool),
    StaticMember(Box<ExprWire>, String),
    TypeFilter(Box<ExprWire>, Vec<String>),
    Object(Box<ExprWire>, Vec<(String, ExprWire)>),
    SafeMember(Box<ExprWire>, String, bool),
    Index(Box<ExprWire>, Box<ExprWire>),
    SafeIndex(Box<ExprWire>, Box<ExprWire>),
    Group(Box<ExprWire>),
}
thread_local! {
 static EXPR_DECODE: std::cell::Cell<(usize,usize)> = const { std::cell::Cell::new((0,4096)) };
}
struct DecodeGuard;
impl Drop for DecodeGuard {
    fn drop(&mut self) {
        EXPR_DECODE.with(|state| {
            let (depth, left) = state.get();
            state.set((depth - 1, left));
        });
    }
}
impl<'de> Deserialize<'de> for ExprWire {
    fn deserialize<D: serde::Deserializer<'de>>(decoder: D) -> Result<Self, D::Error> {
        let permitted = EXPR_DECODE.with(|state| {
            let (depth, mut left) = state.get();
            if depth == 0 {
                left = 4096;
            }
            if depth >= 65 || left == 0 {
                return false;
            }
            state.set((depth + 1, left - 1));
            true
        });
        if !permitted {
            return Err(serde::de::Error::custom(
                "modified expression depth/node limit",
            ));
        }
        let _guard = DecodeGuard;
        ExprWireSerde::deserialize(decoder)
    }
}

impl ExprWire {
    fn capture(value: &Expr) -> Self {
        use ExprKind as E;
        match &value.kind {
            E::Ident(v) => Self::Ident(v.clone()),
            E::Literal(v) => Self::Literal(v.clone()),
            E::TypePath(v) => Self::TypePath(v.clone()),
            E::Unary { op, value } => Self::Unary(op.clone(), Box::new(Self::capture(value))),
            E::Binary { op, lhs, rhs } => Self::Binary(
                op.clone(),
                Box::new(Self::capture(lhs)),
                Box::new(Self::capture(rhs)),
            ),
            E::Conditional {
                condition,
                then_value,
                else_value,
            } => Self::Conditional(
                Box::new(Self::capture(condition)),
                Box::new(Self::capture(then_value)),
                Box::new(Self::capture(else_value)),
            ),
            E::Call { callee, args } => Self::Call(
                Box::new(Self::capture(callee)),
                args.iter().map(Self::capture).collect(),
            ),
            E::Member {
                object,
                selector,
                via_colon,
            } => Self::Member(
                Box::new(Self::capture(object)),
                selector.clone(),
                *via_colon,
            ),
            E::StaticMember { object, selector } => {
                Self::StaticMember(Box::new(Self::capture(object)), selector.clone())
            }
            E::TypeFilter { value, types } => {
                Self::TypeFilter(Box::new(Self::capture(value)), types.clone())
            }
            E::ObjectInitializer { object, fields } => Self::Object(
                Box::new(Self::capture(object)),
                fields
                    .iter()
                    .map(|(name, value)| (name.clone(), Self::capture(value)))
                    .collect(),
            ),
            E::SafeMember {
                object,
                selector,
                via_colon,
            } => Self::SafeMember(
                Box::new(Self::capture(object)),
                selector.clone(),
                *via_colon,
            ),
            E::Index { object, index } => Self::Index(
                Box::new(Self::capture(object)),
                Box::new(Self::capture(index)),
            ),
            E::SafeIndex { object, index } => Self::SafeIndex(
                Box::new(Self::capture(object)),
                Box::new(Self::capture(index)),
            ),
            E::Group(value) => Self::Group(Box::new(Self::capture(value))),
        }
    }
    fn rebuild(self, depth: usize, budget: &mut usize) -> Option<Expr> {
        if depth > 64 || *budget == 0 {
            return None;
        }
        *budget -= 1;
        use ExprKind as E;
        let child =
            |value: Self, budget: &mut usize| value.rebuild(depth + 1, budget).map(Box::new);
        let kind = match self {
            Self::Ident(v) => E::Ident(v),
            Self::Literal(v) => E::Literal(v),
            Self::TypePath(v) => E::TypePath(v),
            Self::Unary(op, v) => E::Unary {
                op,
                value: child(*v, budget)?,
            },
            Self::Binary(op, l, r) => E::Binary {
                op,
                lhs: child(*l, budget)?,
                rhs: child(*r, budget)?,
            },
            Self::Conditional(c, t, e) => E::Conditional {
                condition: child(*c, budget)?,
                then_value: child(*t, budget)?,
                else_value: child(*e, budget)?,
            },
            Self::Call(c, args) => E::Call {
                callee: child(*c, budget)?,
                args: args
                    .into_iter()
                    .map(|v| v.rebuild(depth + 1, budget))
                    .collect::<Option<_>>()?,
            },
            Self::Member(o, selector, via_colon) => E::Member {
                object: child(*o, budget)?,
                selector,
                via_colon,
            },
            Self::StaticMember(o, selector) => E::StaticMember {
                object: child(*o, budget)?,
                selector,
            },
            Self::TypeFilter(v, types) => E::TypeFilter {
                value: child(*v, budget)?,
                types,
            },
            Self::Object(o, fields) => E::ObjectInitializer {
                object: child(*o, budget)?,
                fields: fields
                    .into_iter()
                    .map(|(name, value)| Some((name, value.rebuild(depth + 1, budget)?)))
                    .collect::<Option<_>>()?,
            },
            Self::SafeMember(o, selector, via_colon) => E::SafeMember {
                object: child(*o, budget)?,
                selector,
                via_colon,
            },
            Self::Index(o, i) => E::Index {
                object: child(*o, budget)?,
                index: child(*i, budget)?,
            },
            Self::SafeIndex(o, i) => E::SafeIndex {
                object: child(*o, budget)?,
                index: child(*i, budget)?,
            },
            Self::Group(v) => E::Group(child(*v, budget)?),
        };
        Some(Expr {
            kind,
            span: Span::new(0, 0),
        })
    }
}

#[derive(Serialize, Deserialize)]
pub struct DescriptorWire {
    runtime_type: SymbolId,
    lexical_owner: SymbolId,
    resource_context: Option<u128>,
    fields: Vec<(String, ExprWire)>,
    canonical: Vec<u8>,
    resources: Vec<(String, SymbolId, u128)>,
    origin: Option<u32>,
    field_origins: Vec<Option<u32>>,
}
impl DescriptorWire {
    pub fn capture(value: &CapturedModifiedInstance) -> Self {
        let descriptor = &value.descriptor;
        Self {
            runtime_type: descriptor.runtime_type(),
            lexical_owner: descriptor.lexical_owner(),
            resource_context: descriptor.resource_context(),
            fields: descriptor
                .fields()
                .iter()
                .map(|(name, value)| (name.clone(), ExprWire::capture(value)))
                .collect(),
            canonical: descriptor.canonical_bytes().to_vec(),
            resources: descriptor
                .resources()
                .iter()
                .map(|(raw, proof)| (raw.clone(), proof.path, proof.content))
                .collect(),
            origin: value.origin,
            field_origins: value.field_origins.clone(),
        }
    }
    pub fn rehydrate<R: Resolver>(
        self,
        host: &R,
        debug_count: usize,
    ) -> Option<CapturedModifiedInstance> {
        let ordinal_valid =
            |ordinal: Option<u32>| ordinal.is_some_and(|ordinal| (ordinal as usize) < debug_count);
        if !ordinal_valid(self.origin)
            || self.field_origins.len() != self.fields.len()
            || !self
                .field_origins
                .iter()
                .all(|ordinal| ordinal_valid(*ordinal))
        {
            return None;
        }
        if !matches!(host.resolve(Q::RuntimeType(self.runtime_type)),M::Symbol(actual) if actual==self.runtime_type)
        {
            return None;
        }
        let mut proofs = std::collections::BTreeMap::new();
        for (raw, path, content) in self.resources {
            let literal = raw.strip_prefix('\'')?.strip_suffix('\'')?;
            let query = match self.resource_context {
                Some(search_context) => Q::ResourceIn {
                    path: SymbolId::of(literal),
                    search_context,
                },
                None => Q::Resource(SymbolId::of(literal)),
            };
            if !matches!(host.resolve(query),M::Resource{path:actual,content:bytes} if actual==path && bytes==content)
            {
                return None;
            }
            if proofs
                .insert(raw, dm_ir::CapturedModifiedResource { path, content })
                .is_some()
            {
                return None;
            }
        }
        let mut budget = 4096;
        let fields = self
            .fields
            .into_iter()
            .map(|(name, value)| Some((name, value.rebuild(0, &mut budget)?)))
            .collect::<Option<Vec<_>>>()?;
        let descriptor = dm_ir::ModifiedInstance::capture_with_resources(
            self.runtime_type,
            self.lexical_owner,
            self.resource_context,
            &fields,
            |raw| {
                dm_codegen_byond::decode_constant_string_literal(raw)
                    .ok()
                    .flatten()
            },
            None,
            |literal| {
                proofs
                    .get(&format!("'{literal}'"))
                    .copied()
                    .ok_or_else(|| "cached resource proof missing".to_owned())
            },
        )
        .ok()?;
        if descriptor.canonical_bytes() != self.canonical || descriptor.resources() != &proofs {
            return None;
        }
        Some(CapturedModifiedInstance {
            descriptor,
            source_span: None,
            origin: self.origin,
            field_origins: self.field_origins,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn safe_selector_wire_preserves_dot_colon_property_and_call_callees() {
        for (source, expected_colon) in [
            ("receiver?.field", false),
            ("receiver?:field", true),
            ("receiver?.method()", false),
            ("receiver?:method()", true),
        ] {
            let parsed = dm_syntax::parse_expression(source);
            assert!(parsed.diagnostics.is_empty());
            let wire = ExprWire::capture(parsed.expr.as_ref().unwrap());
            let bytes = dm_wire::encode(0x0e26_0001, &wire).unwrap();
            let wire: ExprWire = dm_wire::decode(0x0e26_0001, &bytes, bytes.len()).unwrap();
            let restored = wire.rebuild(0, &mut 4096).unwrap();
            let selected = match &restored.kind {
                ExprKind::Call { callee, .. } => callee.as_ref(),
                _ => &restored,
            };
            let ExprKind::SafeMember { via_colon, .. } = &selected.kind else {
                panic!("safe selector survives wire");
            };
            assert_eq!(*via_colon, expected_colon);
        }
    }
    struct Host;
    impl Resolver for Host {
        fn resolve(&self, q: Q) -> M {
            match q {
                Q::RuntimeType(path) => M::Symbol(path),
                _ => M::Unsupported(q),
            }
        }
    }
    #[test]
    fn modified_private_wire_reissues_identity_and_rejects_stale_proofs() {
        let value = dm_syntax::parse_expression("1+0").expr.unwrap();
        let descriptor = dm_ir::ModifiedInstance::capture_with_resources(
            SymbolId::of("/obj/base"),
            SymbolId::of("/datum/caller"),
            None,
            &[("amount".into(), value)],
            |_| None,
            None,
            |_| Err("unexpected resource".into()),
        )
        .unwrap();
        let capture = CapturedModifiedInstance {
            descriptor,
            source_span: None,
            origin: Some(0),
            field_origins: vec![Some(1)],
        };
        let bytes = dm_wire::encode(0x0204_0005, &DescriptorWire::capture(&capture)).unwrap();
        let restored: DescriptorWire =
            dm_wire::decode(0x0204_0005, &bytes, dm_wire::MAX_BYTES).unwrap();
        let restored = restored.rehydrate(&Host, 2).unwrap();
        assert_eq!(restored.descriptor, capture.descriptor);
        assert_eq!(restored.field_origins, vec![Some(1)]);
        assert_eq!(restored.descriptor.fields()[0].1.span, Span::new(0, 0));
        let stale: DescriptorWire =
            dm_wire::decode(0x0204_0005, &bytes, dm_wire::MAX_BYTES).unwrap();
        assert!(stale.rehydrate(&Host, 1).is_none());
        let mut forged: DescriptorWire =
            dm_wire::decode(0x0204_0005, &bytes, dm_wire::MAX_BYTES).unwrap();
        forged.canonical.push(1);
        assert!(forged.rehydrate(&Host, 2).is_none());
    }
    #[test]
    fn private_expression_decode_rejects_excessive_depth_before_rebuild() {
        let mut expression = ExprWire::Literal("1".into());
        for _ in 0..66 {
            expression = ExprWire::Group(Box::new(expression));
        }
        let bytes = dm_wire::encode(0x0204_0006, &expression).unwrap();
        assert!(dm_wire::decode::<ExprWire>(0x0204_0006, &bytes, dm_wire::MAX_BYTES).is_err());
        let good = dm_wire::encode(0x0204_0006, &ExprWire::Literal("1".into())).unwrap();
        assert!(dm_wire::decode::<ExprWire>(0x0204_0006, &good, dm_wire::MAX_BYTES).is_ok());
    }
}
