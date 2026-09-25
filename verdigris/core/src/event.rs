//! Typed events (`rust_architecture.md` §4.8): the **one** path by which
//! simulation code tells DM that something happened.
//!
//! A domain declares `#[vg::events(Pump)] pub enum PumpEvent { Starved,
//! TargetReached { pressure: f32 } }` (or `#[vg::events(domain = power)]`
//! for events about a region rather than a component). The macro implements
//! [`Event`]: a stable numeric id per variant, a payload encoder and the
//! [`EventSchema`] the DM generator turns into a decoder and handler
//! dispatch (`on_pump_target_reached(pressure)`).
//!
//! Laws call [`LawCtx::emit`](crate::law::LawCtx::emit), which encodes into
//! an [`EventSink`]; the driver concatenates every sink of a frame and
//! `vg-ffi` hands the whole list to DM in one call. There is no other
//! `Vec<f32>` encoding anywhere: a domain that hand-encodes a list for DM is
//! re-implementing this module (`rust_architecture.md` §2).
//!
//! # Wire format
//!
//! One record per event, every number exact as an `f32`:
//!
//! ```text
//! header, entity, len, payload[0], ..., payload[len - 1]
//! header = domain << 16 | kind << 8 | variant       (below 2^24)
//! entity = the vg_entity value the event is about   (0: none, e.g. a region)
//! ```
//!
//! `len` is redundant with the schema; it lets a decoder skip records it
//! does not know (an event added to Rust before DM was regenerated).

use std::fmt;

/// One payload field of an event variant, for the generator.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EventField {
    pub name: &'static str,
    /// The declared unit (`#[vg(unit = "K")]` on the variant field), if any.
    pub unit: Option<&'static str>,
}

/// One variant of an event enum, for the generator.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct EventSchema {
    /// `snake_case` variant name: the DM handler is `on_<source>_<name>`.
    pub name: &'static str,
    pub fields: &'static [EventField],
}

/// A typed event enum (`#[vg::events]`).
pub trait Event: Send + 'static {
    /// Numeric domain id ([`crate::component::domains`]).
    const DOMAIN_ID: u8;
    /// The component kind the events are about, or `0` for domain-level
    /// events (`#[vg::events(domain = ...)]`). Below 256.
    const KIND: u16;
    /// Every variant, indexed by [`id`](Self::id).
    const VARIANTS: &'static [EventSchema];

    /// The variant's stable numeric id (declaration order).
    fn id(&self) -> u8;
    /// Appends the variant's payload fields, in declaration order.
    fn encode(&self, out: &mut Vec<f32>);
    /// Rebuilds a variant from its id and payload (tests, replay).
    fn decode(id: u8, payload: &[f32]) -> Option<Self>
    where
        Self: Sized;

    /// This event's record header.
    #[must_use]
    fn header(&self) -> u32 {
        header(Self::DOMAIN_ID, Self::KIND, self.id())
    }
}

/// Packs a record header. `kind` must be below 256 (checked by the macro).
#[must_use]
pub const fn header(domain: u8, kind: u16, variant: u8) -> u32 {
    ((domain as u32) << 16) | (((kind & 0xff) as u32) << 8) | variant as u32
}

/// Unpacks a record header into `(domain, kind, variant)`.
#[must_use]
#[allow(clippy::cast_possible_truncation)]
pub const fn split_header(header: u32) -> (u8, u16, u8) {
    ((header >> 16) as u8, ((header >> 8) & 0xff) as u16, header as u8)
}

/// One decoded record, borrowed from an [`EventSink`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Record<'a> {
    pub header: u32,
    /// The `vg_entity` value the event is about (`0.0`: none).
    pub entity: f32,
    pub payload: &'a [f32],
}

impl Record<'_> {
    #[must_use]
    pub const fn domain(&self) -> u8 {
        split_header(self.header).0
    }
    #[must_use]
    pub const fn kind(&self) -> u16 {
        split_header(self.header).1
    }
    #[must_use]
    pub const fn variant(&self) -> u8 {
        split_header(self.header).2
    }

    /// Decodes this record as `E`, if it is one.
    #[must_use]
    pub fn decode<E: Event>(&self) -> Option<E> {
        let (domain, kind, variant) = split_header(self.header);
        if domain != E::DOMAIN_ID || kind != (E::KIND & 0xff) {
            return None;
        }
        E::decode(variant, self.payload)
    }
}

/// An append-only buffer of encoded event records.
#[derive(Clone, Default, PartialEq)]
pub struct EventSink {
    data: Vec<f32>,
    records: usize,
}

impl fmt::Debug for EventSink {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_list().entries(self.iter()).finish()
    }
}

impl EventSink {
    #[must_use]
    pub const fn new() -> Self {
        Self {
            data: Vec::new(),
            records: 0,
        }
    }

    /// Encodes `event` about `entity` (a `vg_entity` value; `0.0` for none).
    #[allow(clippy::cast_precision_loss)]
    pub fn push<E: Event>(&mut self, entity: f32, event: &E) {
        self.data.push(event.header() as f32);
        self.data.push(entity);
        let len_at = self.data.len();
        self.data.push(0.0);
        event.encode(&mut self.data);
        let len = self.data.len() - len_at - 1;
        self.data[len_at] = len as f32;
        self.records += 1;
    }

    /// Records in this sink.
    #[must_use]
    pub const fn len(&self) -> usize {
        self.records
    }

    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.records == 0
    }

    /// Moves every record of `other` to the end of this sink.
    pub fn append(&mut self, other: &mut Self) {
        self.data.append(&mut other.data);
        self.records += other.records;
        other.records = 0;
    }

    /// The raw wire form (what DM receives).
    #[must_use]
    pub fn as_slice(&self) -> &[f32] {
        &self.data
    }

    /// Takes the wire form, leaving the sink empty.
    pub fn take(&mut self) -> Vec<f32> {
        self.records = 0;
        std::mem::take(&mut self.data)
    }

    pub fn clear(&mut self) {
        self.data.clear();
        self.records = 0;
    }

    /// Every record, in emission order.
    pub fn iter(&self) -> impl Iterator<Item = Record<'_>> {
        let mut at = 0;
        let data = &self.data;
        std::iter::from_fn(move || {
            if at + 3 > data.len() {
                return None;
            }
            #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
            let (header, entity, len) = (data[at] as u32, data[at + 1], data[at + 2] as usize);
            let payload = &data[at + 3..(at + 3 + len).min(data.len())];
            at += 3 + len;
            Some(Record {
                header,
                entity,
                payload,
            })
        })
    }

    /// Every record that decodes as `E`, with its entity.
    pub fn decoded<E: Event>(&self) -> impl Iterator<Item = (f32, E)> + '_ {
        self.iter().filter_map(|r| r.decode::<E>().map(|e| (r.entity, e)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, PartialEq)]
    enum Probe {
        Tripped,
        Reading { kelvin: f32, kpa: f32 },
    }

    impl Event for Probe {
        const DOMAIN_ID: u8 = 2;
        const KIND: u16 = 7;
        const VARIANTS: &'static [EventSchema] = &[
            EventSchema { name: "tripped", fields: &[] },
            EventSchema {
                name: "reading",
                fields: &[
                    EventField { name: "kelvin", unit: Some("K") },
                    EventField { name: "kpa", unit: Some("kPa") },
                ],
            },
        ];
        fn id(&self) -> u8 {
            match self {
                Self::Tripped => 0,
                Self::Reading { .. } => 1,
            }
        }
        fn encode(&self, out: &mut Vec<f32>) {
            if let Self::Reading { kelvin, kpa } = self {
                out.extend([*kelvin, *kpa]);
            }
        }
        fn decode(id: u8, p: &[f32]) -> Option<Self> {
            match (id, p) {
                (0, []) => Some(Self::Tripped),
                (1, [k, p]) => Some(Self::Reading { kelvin: *k, kpa: *p }),
                _ => None,
            }
        }
    }

    #[test]
    fn records_round_trip_through_the_wire_form() {
        let mut sink = EventSink::new();
        sink.push(5.0, &Probe::Tripped);
        sink.push(9.0, &Probe::Reading { kelvin: 300.0, kpa: 101.0 });
        assert_eq!(sink.len(), 2);
        let decoded: Vec<_> = sink.decoded::<Probe>().collect();
        assert_eq!(
            decoded,
            vec![(5.0, Probe::Tripped), (9.0, Probe::Reading { kelvin: 300.0, kpa: 101.0 })]
        );
        let r = sink.iter().nth(1).unwrap();
        assert_eq!((r.domain(), r.kind(), r.variant()), (2, 7, 1));
        assert!(header(255, 255, 255) < 1 << 24, "headers stay exact as f32");
    }
}
