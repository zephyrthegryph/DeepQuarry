//! Exact-byte string payloads in deterministic first-encounter order.
//!
//! This is a payload roster, not another symbol namespace. UTF-8 spellings and
//! BYOND formatting bytes use the same `SymbolId::of_bytes` identity.
use crate::SymbolId;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::{collections::HashMap, fmt, sync::Arc};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct StringPayload {
    pub id: SymbolId,
    pub bytes: Arc<[u8]>,
}

impl StringPayload {
    pub fn new(bytes: impl Into<Arc<[u8]>>) -> Self {
        let bytes = bytes.into();
        Self {
            id: SymbolId::of_bytes(&bytes),
            bytes,
        }
    }
}

impl Serialize for StringPayload {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        #[derive(Serialize)]
        struct Wire<'a> {
            id: SymbolId,
            bytes: &'a [u8],
        }
        Wire {
            id: self.id,
            bytes: &self.bytes,
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for StringPayload {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        struct Wire {
            id: SymbolId,
            bytes: Vec<u8>,
        }
        let wire = Wire::deserialize(deserializer)?;
        let actual = SymbolId::of_bytes(&wire.bytes);
        if wire.id != actual {
            return Err(serde::de::Error::custom(
                StringRosterError::InvalidIdentity {
                    claimed: wire.id,
                    actual,
                },
            ));
        }
        Ok(Self {
            id: wire.id,
            bytes: wire.bytes.into(),
        })
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum StringRosterError {
    InvalidIdentity {
        claimed: SymbolId,
        actual: SymbolId,
    },
    Collision {
        id: SymbolId,
        existing: Arc<[u8]>,
        incoming: Arc<[u8]>,
    },
}

impl fmt::Display for StringRosterError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidIdentity { claimed, actual } => write!(
                formatter,
                "string payload identity {:016x} differs from exact-byte hash {:016x}",
                claimed.bits(),
                actual.bits()
            ),
            Self::Collision {
                id,
                existing,
                incoming,
            } => write!(
                formatter,
                "string payload hash collision {:016x}: {:?} and {:?}",
                id.bits(),
                existing,
                incoming
            ),
        }
    }
}
impl std::error::Error for StringRosterError {}

#[derive(Clone, Debug, Default)]
pub struct StringRoster {
    payloads: Vec<StringPayload>,
    positions: HashMap<SymbolId, usize>,
}

impl StringRoster {
    pub fn intern_bytes(&mut self, bytes: &[u8]) -> Result<SymbolId, StringRosterError> {
        let id = SymbolId::of_bytes(bytes);
        if let Some(existing) = self.lookup(id) {
            if existing != bytes {
                return Err(StringRosterError::Collision {
                    id,
                    existing: Arc::from(existing),
                    incoming: Arc::from(bytes),
                });
            }
        } else {
            self.positions.insert(id, self.payloads.len());
            self.payloads.push(StringPayload {
                id,
                bytes: Arc::from(bytes),
            });
        }
        Ok(id)
    }

    pub fn lookup(&self, id: SymbolId) -> Option<&[u8]> {
        self.positions
            .get(&id)
            .map(|&position| self.payloads[position].bytes.as_ref())
    }

    pub fn payloads(&self) -> &[StringPayload] {
        &self.payloads
    }
    pub fn into_payloads(self) -> Vec<StringPayload> {
        self.payloads
    }
    pub fn len(&self) -> usize {
        self.payloads.len()
    }
    pub fn is_empty(&self) -> bool {
        self.payloads.is_empty()
    }

    /// Replay a procedure's ordered roster without modifying this roster if
    /// any payload is invalid or conflicts with existing/replayed exact bytes.
    /// No lossless identity check may be replaced with lossy UTF-8 conversion.
    pub fn merge(
        &mut self,
        payloads: impl IntoIterator<Item = StringPayload>,
    ) -> Result<(), StringRosterError> {
        let mut pending = Vec::<StringPayload>::new();
        let mut positions = HashMap::<SymbolId, usize>::new();
        for payload in payloads {
            let existing = self.lookup(payload.id).or_else(|| {
                positions
                    .get(&payload.id)
                    .map(|&index| pending[index].bytes.as_ref())
            });
            if let Some(existing) = existing {
                if existing != payload.bytes.as_ref() {
                    return Err(StringRosterError::Collision {
                        id: payload.id,
                        existing: Arc::from(existing),
                        incoming: payload.bytes,
                    });
                }
            }
            let actual = SymbolId::of_bytes(&payload.bytes);
            if payload.id != actual {
                return Err(StringRosterError::InvalidIdentity {
                    claimed: payload.id,
                    actual,
                });
            }
            if existing.is_none() {
                positions.insert(payload.id, pending.len());
                pending.push(payload);
            }
        }
        for payload in pending {
            self.positions.insert(payload.id, self.payloads.len());
            self.payloads.push(payload);
        }
        Ok(())
    }

    pub fn from_payloads(
        payloads: impl IntoIterator<Item = StringPayload>,
    ) -> Result<Self, StringRosterError> {
        let mut roster = Self::default();
        roster.merge(payloads)?;
        Ok(roster)
    }
}

impl Serialize for StringRoster {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.payloads.serialize(serializer)
    }
}
impl<'de> Deserialize<'de> for StringRoster {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Self::from_payloads(Vec::<StringPayload>::deserialize(deserializer)?)
            .map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn binary_format_bytes_never_pass_through_unicode() {
        let bytes = [0xff, 0x80, 0, b'[', 0x1f, b']'];
        let mut roster = StringRoster::default();
        let id = roster.intern_bytes(&bytes).unwrap();
        assert_eq!(id, SymbolId::of_bytes(&bytes));
        assert_eq!(roster.lookup(id), Some(bytes.as_slice()));
        assert!(std::str::from_utf8(roster.lookup(id).unwrap()).is_err());
        let text = roster.intern_bytes(b"ordinary").unwrap();
        assert_eq!(text, SymbolId::of("ordinary"));
    }

    #[test]
    fn encounter_order_survives_deduplication_and_replay() {
        let mut roster = StringRoster::default();
        roster.intern_bytes(b"z").unwrap();
        roster.intern_bytes(b"a").unwrap();
        roster.intern_bytes(b"z").unwrap();
        roster
            .merge([StringPayload::new(&b"b"[..]), StringPayload::new(&b"a"[..])])
            .unwrap();
        let bytes: Vec<_> = roster
            .payloads()
            .iter()
            .map(|payload| payload.bytes.as_ref())
            .collect();
        assert_eq!(bytes, vec![&b"z"[..], &b"a"[..], &b"b"[..]]);
    }

    #[test]
    fn collision_rejects_entire_merge_without_mutation() {
        let mut roster = StringRoster::default();
        let id = roster.intern_bytes(b"old").unwrap();
        let error = roster
            .merge([
                StringPayload::new(&b"new"[..]),
                StringPayload {
                    id,
                    bytes: Arc::from(&b"different"[..]),
                },
            ])
            .unwrap_err();
        assert!(matches!(error, StringRosterError::Collision { .. }));
        assert_eq!(roster.len(), 1);
        assert_eq!(roster.lookup(id), Some(&b"old"[..]));
        assert_eq!(roster.lookup(SymbolId::of("new")), None);
    }

    #[test]
    fn conflicting_pending_payloads_also_leave_original_unchanged() {
        let mut roster = StringRoster::default();
        let id = SymbolId::of("first");
        let error = roster
            .merge([
                StringPayload::new(&b"first"[..]),
                StringPayload {
                    id,
                    bytes: Arc::from(&b"second"[..]),
                },
            ])
            .unwrap_err();
        assert!(matches!(error, StringRosterError::Collision { .. }));
        assert!(roster.is_empty());
    }

    #[test]
    fn serde_roundtrip_preserves_exact_payloads_and_order() {
        let mut roster = StringRoster::default();
        roster.intern_bytes(&[0xff, 0, 0x81]).unwrap();
        roster.intern_bytes(b"plain").unwrap();
        let wire = serde_json::to_vec(&roster).unwrap();
        let decoded: StringRoster = serde_json::from_slice(&wire).unwrap();
        assert_eq!(decoded.payloads(), roster.payloads());
        for payload in roster.payloads() {
            assert_eq!(decoded.lookup(payload.id), Some(payload.bytes.as_ref()));
        }
    }

    #[test]
    fn serde_and_merge_reject_forged_hash_identity() {
        let payload = StringPayload {
            id: SymbolId::of("wrong"),
            bytes: Arc::from(&b"actual"[..]),
        };
        let wire = serde_json::to_vec(&payload).unwrap();
        assert!(serde_json::from_slice::<StringPayload>(&wire).is_err());
        let mut roster = StringRoster::default();
        assert!(matches!(
            roster.merge([payload]),
            Err(StringRosterError::InvalidIdentity { .. })
        ));
        assert!(roster.is_empty());
    }
}
