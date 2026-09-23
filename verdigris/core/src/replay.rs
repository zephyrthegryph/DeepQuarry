//! Serializing the flight-recorder log and checking replays (`rust_core.md`
//! §3.9, §11).
//!
//! A [`FrameLog`] holds each domain's command batch type-erased. To write it
//! out, each domain supplies a [`DomainCodec`] (made with [`codec`] from its
//! [`DomainKey`], given [`Codec`] impls for its value and command types).
//! The codecs are listed in domain-registration order, like the domains.
//!
//! File layout (little endian), `.vglog`:
//! ```text
//! magic "VGLOG" 0x01 | scenario: str | seed: u64 | domains: u32, name: str each
//! frames: u64, then per frame: frame: u64, per domain: present: u8 [ops: u32, op each]
//! hashes: u32, u64 each   (state hash per domain after the last frame; 0 = none)
//! ```
//! `str` is `u32` length + UTF-8; an op is `seq: u64, target: u32, tag: u8`
//! and then the value (`0` put), nothing (`1` take) or the command (`2` apply).
//!
//! The replay tool (`verdigris/tools/replay`) reads a log, rebuilds the
//! named scenario, runs [`Sim::replay`] and compares [`state_hashes`].

use std::any::Any;
use std::fmt;

use crate::command::{Op, Seq, Sequenced};
use crate::owner::{Domain, DomainKey, DomainOp};
use crate::sim::{FrameLog, FrameRecord, Sim};

const MAGIC: &[u8; 6] = b"VGLOG\x01";

/// A malformed or mismatched log.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DecodeError(pub String);

impl fmt::Display for DecodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "replay log: {}", self.0)
    }
}

impl std::error::Error for DecodeError {}

/// A cursor over encoded bytes.
pub struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    #[must_use]
    pub const fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, pos: 0 }
    }

    /// The next `n` bytes.
    ///
    /// # Errors
    /// If fewer than `n` remain.
    pub fn take(&mut self, n: usize) -> Result<&'a [u8], DecodeError> {
        let end = self
            .pos
            .checked_add(n)
            .filter(|end| *end <= self.bytes.len())
            .ok_or_else(|| DecodeError(format!("truncated at byte {}", self.pos)))?;
        let out = &self.bytes[self.pos..end];
        self.pos = end;
        Ok(out)
    }

    #[must_use]
    pub const fn is_empty(&self) -> bool {
        self.pos >= self.bytes.len()
    }
}

/// A value that can go into a replay log. Encodings must be exact
/// (floats by bit pattern) so that state hashes are bit-for-bit.
pub trait Codec: Sized {
    fn encode(&self, out: &mut Vec<u8>);

    /// # Errors
    /// On malformed input.
    fn decode(r: &mut Reader<'_>) -> Result<Self, DecodeError>;
}

macro_rules! codec_le {
    ($($t:ty),*) => {$(
        impl Codec for $t {
            fn encode(&self, out: &mut Vec<u8>) {
                out.extend_from_slice(&self.to_le_bytes());
            }
            fn decode(r: &mut Reader<'_>) -> Result<Self, DecodeError> {
                let bytes = r.take(size_of::<$t>())?;
                Ok(<$t>::from_le_bytes(bytes.try_into().expect("sized take")))
            }
        }
    )*};
}
codec_le!(u8, u16, u32, u64, i8, i16, i32, i64, f32, f64);

impl Codec for bool {
    fn encode(&self, out: &mut Vec<u8>) {
        out.push(u8::from(*self));
    }
    fn decode(r: &mut Reader<'_>) -> Result<Self, DecodeError> {
        Ok(u8::decode(r)? != 0)
    }
}

impl Codec for String {
    fn encode(&self, out: &mut Vec<u8>) {
        len(self.len()).encode(out);
        out.extend_from_slice(self.as_bytes());
    }
    fn decode(r: &mut Reader<'_>) -> Result<Self, DecodeError> {
        let n = u32::decode(r)? as usize;
        String::from_utf8(r.take(n)?.to_vec()).map_err(|e| DecodeError(e.to_string()))
    }
}

impl<T: Codec> Codec for Vec<T> {
    fn encode(&self, out: &mut Vec<u8>) {
        len(self.len()).encode(out);
        for v in self {
            v.encode(out);
        }
    }
    fn decode(r: &mut Reader<'_>) -> Result<Self, DecodeError> {
        let n = u32::decode(r)?;
        (0..n).map(|_| T::decode(r)).collect()
    }
}

impl<T: Codec> Codec for Option<T> {
    fn encode(&self, out: &mut Vec<u8>) {
        self.is_some().encode(out);
        if let Some(v) = self {
            v.encode(out);
        }
    }
    fn decode(r: &mut Reader<'_>) -> Result<Self, DecodeError> {
        Ok(if bool::decode(r)? {
            Some(T::decode(r)?)
        } else {
            None
        })
    }
}

fn len(n: usize) -> u32 {
    u32::try_from(n).expect("replay log section over u32::MAX entries")
}

/// FNV-1a over bytes: stable across platforms and releases.
#[derive(Clone, Copy, Debug)]
pub struct StableHasher(u64);

impl Default for StableHasher {
    fn default() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }
}

impl StableHasher {
    pub fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.0 ^= u64::from(*b);
            self.0 = self.0.wrapping_mul(0x0100_0000_01b3);
        }
    }

    #[must_use]
    pub const fn finish(self) -> u64 {
        self.0
    }
}

/// The type-erased codec for one domain's batches and views.
pub trait DomainCodec {
    fn name(&self) -> &'static str;

    /// Encodes one recorded batch (as stored in a [`FrameRecord`]).
    fn encode_batch(&self, batch: &(dyn Any + Send + Sync), out: &mut Vec<u8>);

    /// # Errors
    /// On malformed input.
    fn decode_batch(&self, r: &mut Reader<'_>) -> Result<Box<dyn Any + Send + Sync>, DecodeError>;

    /// One line per command, for human-readable dumps.
    fn describe_batch(&self, batch: &(dyn Any + Send + Sync)) -> Vec<String>;

    /// A stable hash of the domain's pinned view (every cell's encoding).
    fn hash_view(&self, sim: &Sim) -> u64;
}

struct TypedCodec<D: Domain> {
    key: DomainKey<D>,
}

type Batch<D> = Vec<Sequenced<DomainOp<D>>>;

impl<D: Domain> DomainCodec for TypedCodec<D>
where
    D::Value: Codec,
    D::Command: Codec,
{
    fn name(&self) -> &'static str {
        D::NAME
    }

    fn encode_batch(&self, batch: &(dyn Any + Send + Sync), out: &mut Vec<u8>) {
        let batch = batch
            .downcast_ref::<Batch<D>>()
            .expect("recorded batch type mismatch");
        len(batch.len()).encode(out);
        for s in batch {
            s.seq.0.encode(out);
            s.target.encode(out);
            match &s.op {
                Op::Put(v) => {
                    out.push(0);
                    v.encode(out);
                }
                Op::Take => out.push(1),
                Op::Apply(c) => {
                    out.push(2);
                    c.encode(out);
                }
            }
        }
    }

    fn decode_batch(&self, r: &mut Reader<'_>) -> Result<Box<dyn Any + Send + Sync>, DecodeError> {
        let n = u32::decode(r)?;
        let mut batch: Batch<D> = Vec::with_capacity(n.min(1 << 16) as usize);
        for _ in 0..n {
            let seq = Seq(u64::decode(r)?);
            let target = u32::decode(r)?;
            let op = match u8::decode(r)? {
                0 => Op::Put(D::Value::decode(r)?),
                1 => Op::Take,
                2 => Op::Apply(D::Command::decode(r)?),
                t => return Err(DecodeError(format!("bad op tag {t}"))),
            };
            batch.push(Sequenced { seq, target, op });
        }
        Ok(Box::new(batch))
    }

    fn describe_batch(&self, batch: &(dyn Any + Send + Sync)) -> Vec<String> {
        batch
            .downcast_ref::<Batch<D>>()
            .map(|b| {
                b.iter()
                    .map(|s| format!("#{} cell {}: {:?}", s.seq.0, s.target, s.op))
                    .collect()
            })
            .unwrap_or_default()
    }

    fn hash_view(&self, sim: &Sim) -> u64 {
        let view = sim.port_ref(self.key).pinned();
        let mut h = StableHasher::default();
        let mut buf = Vec::new();
        for cell in 0..view.store().layout().len() {
            buf.clear();
            if let Some(v) = view.get(cell) {
                v.encode(&mut buf);
            }
            h.write(&buf);
        }
        h.finish()
    }
}

/// The codec for domain `D`, registered as `key`.
#[must_use]
pub fn codec<D: Domain>(key: DomainKey<D>) -> Box<dyn DomainCodec>
where
    D::Value: Codec,
    D::Command: Codec,
{
    Box::new(TypedCodec { key })
}

/// Every domain's pinned-view hash, in codec order.
#[must_use]
pub fn state_hashes(sim: &Sim, codecs: &[Box<dyn DomainCodec>]) -> Vec<u64> {
    codecs.iter().map(|c| c.hash_view(sim)).collect()
}

/// A decoded log's header.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LogHeader {
    /// What built the sim (the replay tool looks this up).
    pub scenario: String,
    pub seed: u64,
    pub domains: Vec<String>,
}

/// Encodes `frames` as a log for `scenario`, with optional final state
/// hashes (empty: none recorded).
#[must_use]
pub fn encode_log<'a>(
    scenario: &str,
    seed: u64,
    frames: impl ExactSizeIterator<Item = &'a FrameRecord>,
    codecs: &[Box<dyn DomainCodec>],
    hashes: &[u64],
) -> Vec<u8> {
    let mut out = MAGIC.to_vec();
    scenario.to_owned().encode(&mut out);
    seed.encode(&mut out);
    len(codecs.len()).encode(&mut out);
    for c in codecs {
        c.name().to_owned().encode(&mut out);
    }
    (frames.len() as u64).encode(&mut out);
    for record in frames {
        record.frame.encode(&mut out);
        assert_eq!(record.batches().len(), codecs.len(), "codec count differs");
        for (codec, batch) in codecs.iter().zip(record.batches()) {
            match batch {
                Some(b) => {
                    out.push(1);
                    codec.encode_batch(b.as_ref(), &mut out);
                }
                None => out.push(0),
            }
        }
    }
    hashes.to_vec().encode(&mut out);
    out
}

/// Reads just the header, to pick the scenario before decoding frames.
///
/// # Errors
/// On a malformed header.
pub fn decode_header(bytes: &[u8]) -> Result<LogHeader, DecodeError> {
    header(&mut Reader::new(bytes))
}

fn header(r: &mut Reader<'_>) -> Result<LogHeader, DecodeError> {
    if r.take(MAGIC.len())? != MAGIC {
        return Err(DecodeError("not a verdigris replay log".into()));
    }
    Ok(LogHeader {
        scenario: String::decode(r)?,
        seed: u64::decode(r)?,
        domains: Vec::<String>::decode(r)?,
    })
}

/// Decodes a whole log: the header, the frames (as a [`FrameLog`] for
/// [`Sim::replay`]) and the recorded final hashes.
///
/// # Errors
/// On malformed input, or if the codecs' domains differ from the log's.
pub fn decode_log(
    bytes: &[u8],
    codecs: &[Box<dyn DomainCodec>],
) -> Result<(LogHeader, FrameLog, Vec<u64>), DecodeError> {
    let mut r = Reader::new(bytes);
    let head = header(&mut r)?;
    let names: Vec<_> = codecs.iter().map(|c| c.name()).collect();
    if head.domains != names {
        return Err(DecodeError(format!(
            "log domains {:?} differ from the scenario's {names:?}",
            head.domains
        )));
    }
    let count = u64::decode(&mut r)?;
    let mut frames = Vec::new();
    for _ in 0..count {
        let frame = u64::decode(&mut r)?;
        let mut batches = Vec::with_capacity(codecs.len());
        for codec in codecs {
            batches.push(if bool::decode(&mut r)? {
                Some(codec.decode_batch(&mut r)?)
            } else {
                None
            });
        }
        frames.push(FrameRecord::new(frame, batches));
    }
    let hashes = Vec::<u64>::decode(&mut r)?;
    if !r.is_empty() {
        return Err(DecodeError("trailing bytes".into()));
    }
    Ok((
        head.clone(),
        FrameLog {
            seed: head.seed,
            frames,
        },
        hashes,
    ))
}

/// The outcome of [`verify`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Verdict {
    pub frames: usize,
    pub expected: Vec<u64>,
    pub actual: Vec<u64>,
}

impl Verdict {
    /// Whether every recorded hash matched (vacuously true if none were).
    #[must_use]
    pub fn ok(&self) -> bool {
        self.expected.is_empty() || self.expected == self.actual
    }
}

/// Replays `bytes` into the sim `build` makes (same domains and tasks as
/// the recording) and compares final state hashes.
///
/// # Errors
/// On a malformed log, a domain mismatch, or a pool build failure.
pub fn verify<B>(bytes: &[u8], build: B) -> Result<Verdict, Box<dyn std::error::Error>>
where
    B: FnOnce(&LogHeader) -> Result<(crate::sim::SimBuilder, Vec<Box<dyn DomainCodec>>), String>,
{
    let head = decode_header(bytes)?;
    let (builder, codecs) = build(&head)?;
    let (_, log, expected) = decode_log(bytes, &codecs)?;
    let sim = Sim::replay(builder, &log)?;
    Ok(Verdict {
        frames: log.frames.len(),
        actual: state_hashes(&sim, &codecs),
        expected,
    })
}
