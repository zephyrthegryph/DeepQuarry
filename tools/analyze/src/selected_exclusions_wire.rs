//! Data-only selected exclusions protocol. None of these values issue source authority.
use serde::{Deserialize, Serialize};
use std::io;

pub const MAX_HEADER: usize = 1024;
pub const MAX_STREAM: u64 = 64 * 1024 * 1024;

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Roster {
    Base,
    WithCooldown,
    WithSilicon,
    WithLibraryLayering,
    WithHandlers,
    WithSemanticReads,
}

impl Roster {
    pub const MAX_POLICIES: usize = 6;
    pub const ALL: [Self; 6] = [Self::Base, Self::WithCooldown, Self::WithSilicon, Self::WithLibraryLayering, Self::WithHandlers, Self::WithSemanticReads];

    pub fn names(self) -> &'static [&'static str] {
        match self {
            Self::Base => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithCooldown => &["allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithSilicon => &["allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler", "silicon_entry"],
            Self::WithSemanticReads => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler", "sem/reads", "untracked_inputs"],
            Self::WithHandlers => &["allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler", "sem/handlers"],
            Self::WithLibraryLayering => &["allow_annotations", "cooldown", "library_layering", "notice_publisher", "report_in_catch", "scheduler"],
        }
    }
}

fn invalid(message: &'static str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Hex128(pub u128);

impl Hex128 {
    pub fn parse(value: &str) -> Option<Self> {
        if value.len() != 32 || !value.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) {
            return None;
        }
        u128::from_str_radix(value, 16).ok().map(Self)
    }
}
impl Serialize for Hex128 {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_str(&format_args!("{:032x}", self.0))
    }
}
impl<'de> Deserialize<'de> for Hex128 {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct HexVisitor;
        impl serde::de::Visitor<'_> for HexVisitor {
            type Value = Hex128;
            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("32 lowercase hexadecimal digits")
            }
            fn visit_str<E: serde::de::Error>(self, value: &str) -> Result<Self::Value, E> {
                Hex128::parse(value).ok_or_else(|| E::custom("invalid selected report digest or revision"))
            }
        }
        deserializer.deserialize_str(HexVisitor)
    }
}

/// Transport coordinates from the actual admitted preparation. Decoding these
/// values on the client does not create a source frame or a reusable query pin.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Frame {
    pub semantic_revision: Hex128,
    pub source_revision: Hex128,
    pub policy_revision: Hex128,
}
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum Schema {
    #[serde(rename = "native-analyze-exclusions-batch-v1")]
    V1,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Seal {
    pub length: u64,
    pub hash: Hex128,
}
impl Seal {
    fn require_bound(self) -> io::Result<()> {
        if self.length == 0 || self.length > MAX_STREAM {
            return Err(invalid("selected report terminal declares an empty or oversized stream"));
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Terminal {
    pub schema: Schema,
    pub roster: Roster,
    pub frame: Frame,
    pub clean: bool,
    #[serde(deserialize_with = "explicit_option")]
    pub diagnostics: Option<Seal>,
    pub report: Seal,
}
fn explicit_option<'de, D: serde::Deserializer<'de>, T: Deserialize<'de>>(deserializer: D) -> Result<Option<T>, D::Error> {
    Option::deserialize(deserializer)
}

impl Terminal {
    pub fn require(self, expected: Roster) -> io::Result<()> {
        if self.roster != expected {
            return Err(invalid("selected report terminal names a foreign roster"));
        }
        self.report.require_bound()?;
        if let Some(diagnostics) = self.diagnostics {
            diagnostics.require_bound()?;
        }
        Ok(())
    }
}
