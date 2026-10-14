//! Lossless source-neutral answer transport; never an admission certificate.
#[path = "portable_answer_value.rs"]
mod value;
use crate::{ResolveQuery, ResolvedMeaning, SymbolId};
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
}
impl PortableResolvedAnswer {
    pub fn capture(answer: &ResolvedMeaning) -> Option<Self> {
        Some(match answer {
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
                content: *content,
            },
            _ => return None,
        })
    }
    pub fn restore(&self) -> ResolvedMeaning {
        if let Self::Value(value) = self {
            return ResolvedMeaning::Value(value.restore());
        }
        match *self {
            Self::Value(_) => unreachable!("handled portable value"),
            Self::Missing => ResolvedMeaning::Missing,
            Self::Unsupported(q) => ResolvedMeaning::Unsupported(q),
            Self::Presence(v) => ResolvedMeaning::Presence(v),
            Self::DeclaredType(v) => ResolvedMeaning::DeclaredType(v),
            Self::InstanceField {
                declaring_owner,
                name,
            } => ResolvedMeaning::InstanceField {
                declaring_owner,
                name,
            },
            Self::Slot {
                symbol,
                owner,
                name,
            } => ResolvedMeaning::Slot {
                symbol,
                owner,
                name,
            },
            Self::Symbol(v) => ResolvedMeaning::Symbol(v),
            Self::IntrinsicProc {
                declaring_owner,
                name,
            } => ResolvedMeaning::IntrinsicProc {
                declaring_owner,
                name,
            },
            Self::Resource { path, content } => ResolvedMeaning::Resource { path, content },
        }
    }
    pub fn matches_canonical(&self, bytes: &[u8]) -> bool {
        self.restore().canonical_bytes() == bytes
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
            assert_eq!(wire.restore(), answer);
            assert!(wire.matches_canonical(&answer.canonical_bytes()));
            assert!(!wire.matches_canonical(b"malformed"));
        }
        assert!(
            PortableResolvedAnswer::capture(&ResolvedMeaning::Symbols(std::sync::Arc::from([])))
                .is_none()
        );
        assert!(
            PortableResolvedAnswer::capture(&ResolvedMeaning::RetainedProc {
                declaring_owner: SymbolId::of("/datum"),
                name: SymbolId::of("New"),
                verb: false,
                engine_identity: 1,
                wire_proc: 7
            })
            .is_none()
        );
    }
}
