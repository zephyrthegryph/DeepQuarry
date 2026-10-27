//! Lossless source-neutral answer transport; never an admission certificate.
#[path = "portable_answer_value.rs"]
mod value;
use crate::{
    portable_meaning::{Names, PortableMeaning},
    DeclarationMeaning, DeclaredTypeKnowledge, OpaqueFieldBase, ProcedureDefinition,
    ProcedureIdentity, ResolveQuery, ResolvedMeaning, SymbolId,
};
use std::sync::Arc;
/// Nesting bound for `Members`; resolvers never nest them, so a deeper wire is malformed.
const MAX_DEPTH: usize = 4;
/// The inherited engine base of a declaration whose flags and defaults are unknown.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct PortableOpaque {
    owner: SymbolId,
    name: SymbolId,
    knowledge: u8,
    known: Option<SymbolId>,
}
fn capture_data(
    data: &DeclarationMeaning,
) -> Option<(Box<PortableMeaning>, Option<PortableOpaque>)> {
    let Some(base) = &data.inherited_opaque else {
        return Some((Box::new(PortableMeaning::capture(data, false)?), None));
    };
    let mut plain = data.clone();
    plain.inherited_opaque = None;
    let (knowledge, known) = match base.declared_type {
        DeclaredTypeKnowledge::Known(symbol) => (0, Some(symbol)),
        DeclaredTypeKnowledge::KnownUntyped => (1, None),
        DeclaredTypeKnowledge::Unsupported => (2, None),
    };
    Some((
        Box::new(PortableMeaning::capture(&plain, false)?),
        Some(PortableOpaque {
            owner: base.owner,
            name: base.name,
            knowledge,
            known,
        }),
    ))
}
fn restore_data(
    data: &PortableMeaning,
    opaque: &Option<PortableOpaque>,
) -> Option<Arc<DeclarationMeaning>> {
    let mut meaning = data.clone().restore(Names::unchecked())?;
    if let Some(base) = opaque {
        meaning.inherited_opaque = Some(OpaqueFieldBase {
            owner: base.owner,
            name: base.name,
            declared_type: match (base.knowledge, base.known) {
                (0, Some(symbol)) => DeclaredTypeKnowledge::Known(symbol),
                (1, None) => DeclaredTypeKnowledge::KnownUntyped,
                (2, None) => DeclaredTypeKnowledge::Unsupported,
                _ => return None,
            },
        });
    }
    Some(Arc::new(meaning))
}
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub enum PortableResolvedAnswer {
    Value(value::PortableValue),
    Missing,
    Unsupported(ResolveQuery),
    Presence(bool),
    DeclaredType(Option<SymbolId>),
    InstanceField {
        declaring_owner: SymbolId,
        name: SymbolId,
    },
    Slot {
        symbol: SymbolId,
        owner: SymbolId,
        name: SymbolId,
    },
    Symbol(SymbolId),
    IntrinsicProc {
        declaring_owner: SymbolId,
        name: SymbolId,
    },
    Resource {
        path: SymbolId,
        content: u128,
    },
    Symbols(Vec<SymbolId>),
    Members(Vec<PortableResolvedAnswer>),
    Member {
        owner: SymbolId,
        name: SymbolId,
        fingerprint: u128,
        data: Box<PortableMeaning>,
        opaque: Option<PortableOpaque>,
    },
    Declaration {
        identity: ProcedureIdentity,
        definition: u8,
        previous: Option<ProcedureIdentity>,
        data: Box<PortableMeaning>,
        opaque: Option<PortableOpaque>,
    },
}
impl PortableResolvedAnswer {
    /// The scalar answers only: values, symbols, presence and resources.
    pub fn capture(answer: &ResolvedMeaning) -> Option<Self> {
        Self::capture_in(answer, false)
    }
    /// Every answer with a source-neutral form: `capture` plus symbol lists and declaration
    /// meanings (`None` for an opaque inherited base, a procedure static or a retained proc).
    pub fn capture_declared(answer: &ResolvedMeaning) -> Option<Self> {
        Self::capture_in(answer, true)
    }
    fn capture_in(answer: &ResolvedMeaning, declared: bool) -> Option<Self> {
        Some(match answer {
            ResolvedMeaning::Symbols(values) if declared => Self::Symbols(values.to_vec()),
            ResolvedMeaning::Members(values) if declared => Self::Members(
                values
                    .iter()
                    .map(|value| Self::capture_in(value, true))
                    .collect::<Option<_>>()?,
            ),
            ResolvedMeaning::Member {
                owner,
                name,
                fingerprint,
                data,
            } if declared => {
                let (data, opaque) = capture_data(data)?;
                Self::Member {
                    owner: *owner,
                    name: *name,
                    fingerprint: (*fingerprint).into(),
                    data,
                    opaque,
                }
            }
            ResolvedMeaning::Declaration {
                identity,
                definition,
                previous,
                data,
            } if declared => {
                let (data, opaque) = capture_data(data)?;
                Self::Declaration {
                    identity: *identity,
                    definition: match definition {
                        ProcedureDefinition::Declare => 0,
                        ProcedureDefinition::Override => 1,
                        ProcedureDefinition::Reopen => 2,
                        ProcedureDefinition::Implicit => 3,
                    },
                    previous: *previous,
                    data,
                    opaque,
                }
            }
            ResolvedMeaning::Value(v) => Self::Value(value::PortableValue::capture(v)?),
            ResolvedMeaning::Missing => Self::Missing,
            ResolvedMeaning::Unsupported(q) => Self::Unsupported(*q),
            ResolvedMeaning::Presence(v) => Self::Presence(*v),
            ResolvedMeaning::DeclaredType(v) => Self::DeclaredType(*v),
            ResolvedMeaning::InstanceField {
                declaring_owner,
                name,
            } => Self::InstanceField {
                declaring_owner: *declaring_owner,
                name: *name,
            },
            ResolvedMeaning::Slot {
                symbol,
                owner,
                name,
            } => Self::Slot {
                symbol: *symbol,
                owner: *owner,
                name: *name,
            },
            ResolvedMeaning::Symbol(v) => Self::Symbol(*v),
            ResolvedMeaning::IntrinsicProc {
                declaring_owner,
                name,
            } => Self::IntrinsicProc {
                declaring_owner: *declaring_owner,
                name: *name,
            },
            ResolvedMeaning::Resource { path, content } => Self::Resource {
                path: *path,
                content: (*content).into(),
            },
            _ => return None,
        })
    }
    /// The answer this form stands for. `None` when a declaration inside it does not decode;
    /// a caller compares the result's canonical bytes with its stored evidence before use.
    pub fn restore(&self) -> Option<ResolvedMeaning> {
        self.restore_in(0)
    }
    fn restore_in(&self, depth: usize) -> Option<ResolvedMeaning> {
        Some(match self {
            Self::Value(value) => ResolvedMeaning::Value(value.restore()),
            Self::Missing => ResolvedMeaning::Missing,
            Self::Unsupported(q) => ResolvedMeaning::Unsupported(*q),
            Self::Presence(v) => ResolvedMeaning::Presence(*v),
            Self::DeclaredType(v) => ResolvedMeaning::DeclaredType(*v),
            Self::InstanceField {
                declaring_owner,
                name,
            } => ResolvedMeaning::InstanceField {
                declaring_owner: *declaring_owner,
                name: *name,
            },
            Self::Slot {
                symbol,
                owner,
                name,
            } => ResolvedMeaning::Slot {
                symbol: *symbol,
                owner: *owner,
                name: *name,
            },
            Self::Symbol(v) => ResolvedMeaning::Symbol(*v),
            Self::IntrinsicProc {
                declaring_owner,
                name,
            } => ResolvedMeaning::IntrinsicProc {
                declaring_owner: *declaring_owner,
                name: *name,
            },
            Self::Resource { path, content } => ResolvedMeaning::Resource {
                path: *path,
                content: (*content).into(),
            },
            Self::Symbols(values) => ResolvedMeaning::Symbols(Arc::from(values.as_slice())),
            Self::Members(values) => {
                if depth >= MAX_DEPTH {
                    return None;
                }
                ResolvedMeaning::Members(
                    values
                        .iter()
                        .map(|value| value.restore_in(depth + 1))
                        .collect::<Option<Vec<_>>>()?
                        .into(),
                )
            }
            Self::Member {
                owner,
                name,
                fingerprint,
                data,
                opaque,
            } => ResolvedMeaning::Member {
                owner: *owner,
                name: *name,
                fingerprint: (*fingerprint).into(),
                data: restore_data(data, opaque)?,
            },
            Self::Declaration {
                identity,
                definition,
                previous,
                data,
                opaque,
            } => ResolvedMeaning::Declaration {
                identity: *identity,
                definition: match definition {
                    0 => ProcedureDefinition::Declare,
                    1 => ProcedureDefinition::Override,
                    2 => ProcedureDefinition::Reopen,
                    3 => ProcedureDefinition::Implicit,
                    _ => return None,
                },
                previous: *previous,
                data: restore_data(data, opaque)?,
            },
        })
    }
    pub fn matches_canonical(&self, bytes: &[u8]) -> bool {
        self.restore().is_some_and(|answer| answer.canonical_bytes() == bytes)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn portable_simple_answers_preserve_negative_and_unsupported_evidence() {
        let query = ResolveQuery::GlobalProc(SymbolId::of("absent"));
        for answer in [
            ResolvedMeaning::Missing,
            ResolvedMeaning::Presence(false),
            ResolvedMeaning::Unsupported(query),
        ] {
            let wire = PortableResolvedAnswer::capture(&answer).unwrap();
            assert_eq!(wire.restore(), Some(answer.clone()));
            assert!(wire.matches_canonical(&answer.canonical_bytes()));
            assert!(!wire.matches_canonical(b"malformed"));
        }
        let symbols = ResolvedMeaning::Symbols(std::sync::Arc::from([SymbolId::of("/obj")]));
        assert!(PortableResolvedAnswer::capture(&symbols).is_none());
        let wire = PortableResolvedAnswer::capture_declared(&symbols).unwrap();
        assert_eq!(wire.restore(), Some(symbols));
        assert!(
            PortableResolvedAnswer::capture(&ResolvedMeaning::RetainedProc {
                declaring_owner: SymbolId::of("/datum"),
                name: SymbolId::of("New"),
                verb: false,
                engine_identity: 1.into(),
                wire_proc: 7
            })
            .is_none()
        );
    }

    fn expression(text: &str) -> crate::SymbolicExpression {
        crate::SymbolicExpression {
            tokens: Arc::from([crate::ExpressionToken {
                kind: dm_syntax::TokenKind::Ident,
                text: SymbolId::of(text),
                relative_span: dm_syntax::Span::new(0, text.len()),
            }]),
        }
    }
    fn meaning() -> crate::DeclarationMeaning {
        crate::DeclarationMeaning {
            declared_type: Some(SymbolId::of("/obj")),
            flags: 3,
            procedure: Some(Arc::new(crate::ProcedureMetadata {
                signature: crate::ProcedureSignature {
                    parameters: Arc::from([crate::Parameter {
                        name: SymbolId::of("amount"),
                        declared_type: None,
                        list_element_type: None,
                        flags: 0,
                        array: None,
                        default: Some(expression("null")),
                        input_annotation: None,
                        source_expression: None,
                        relative_span: dm_syntax::Span::new(0, 6),
                    }]),
                    variadic: false,
                    return_annotation: Some(expression("num")),
                },
                settings: Arc::from([crate::ProcedureSettingNode::Setting(
                    crate::ProcedureSetting {
                        name: SymbolId::of("name"),
                        operation: crate::SettingOperation::Assign,
                        value: expression("probe"),
                    },
                )]),
            })),
            initializer: Some(expression("1")),
            canonical: Arc::from(&b"recipe"[..]),
            ..Default::default()
        }
    }
    #[test]
    fn declaration_chains_round_trip_through_the_wire_with_identical_canonical_bytes() {
        let identity = ProcedureIdentity {
            owner: SymbolId::of("/obj"),
            name: SymbolId::of("attack"),
            verb: false,
            occurrence: 1,
        };
        let chain = ResolvedMeaning::Members(Arc::from([
            ResolvedMeaning::Declaration {
                identity,
                definition: ProcedureDefinition::Override,
                previous: Some(identity),
                data: Arc::new(meaning()),
            },
            ResolvedMeaning::Member {
                owner: SymbolId::of("/obj"),
                name: SymbolId::of("amount"),
                fingerprint: 9.into(),
                data: Arc::new(crate::DeclarationMeaning::default()),
            },
        ]));
        let wire = PortableResolvedAnswer::capture_declared(&chain).unwrap();
        let bytes = serde_json::to_vec(&wire).unwrap();
        let back: PortableResolvedAnswer = serde_json::from_slice(&bytes).unwrap();
        let restored = back.restore().unwrap();
        assert_eq!(restored, chain);
        assert!(back.matches_canonical(&chain.canonical_bytes()));
        assert!(PortableResolvedAnswer::capture(&chain).is_none());
        // An opaque inherited base keeps its engine owner and type knowledge.
        let opaque = ResolvedMeaning::Member {
            owner: SymbolId::of("/obj"),
            name: SymbolId::of("x"),
            fingerprint: 1.into(),
            data: Arc::new(crate::DeclarationMeaning {
                inherited_opaque: Some(crate::OpaqueFieldBase {
                    owner: SymbolId::of("/atom"),
                    name: SymbolId::of("x"),
                    declared_type: crate::DeclaredTypeKnowledge::Known(SymbolId::of("/obj")),
                }),
                ..Default::default()
            }),
        };
        let wire = PortableResolvedAnswer::capture_declared(&opaque).unwrap();
        assert_eq!(wire.restore(), Some(opaque.clone()));
        assert!(wire.matches_canonical(&opaque.canonical_bytes()));
    }
}
