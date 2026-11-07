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
    WithCheckGrep,
    WithDeadlinePolling,
    WithEngineInternal,
    // V1 must neither serialize nor accept this v2-only plan as an alias.
    #[serde(skip)]
    WithCooldownAndEngineInternal,
    WithSilicon,
    WithLibraryLayering,
    WithEngineLayering,
    WithHandlers,
    WithSemanticReads,
    WithSetterPublishes,
    WithReactivePolicies,
    WithUntyped,
    WithDerivedReads,
    WithSysReactive,
    WithLifeforms,
    WithPlayerLink,
    WithLifeformsAndPlayerLink,
    WithReferencePolicies,
    WithRequirementBool,
    WithKeys,
    WithMapEdits,
    WithOrderAndOwnership,
    WithDeclarationPolicies,
    WithRawDeclarationPolicies,
    AllRawFilePolicies,
    WithDocSnippets,
    WithUiActions,
    WithWorkspaceFoldPolicies,
    WithSysSourcePolicies,
    WithStoredAndTracked,
    WithRawRuntimePolicies,
}

impl Roster {
    pub const MAX_POLICIES: usize = 7;
    // A V1 alias is a single wire token. This bound is for internal staged
    // sections only, independent of the V2 array decoder's seven-name cap.
    pub const MAX_STAGED_POLICIES: usize = 45;
    pub const ALL: [Self; 32] = [Self::Base, Self::WithCooldown, Self::WithCheckGrep, Self::WithDeadlinePolling, Self::WithEngineInternal, Self::WithSilicon, Self::WithLibraryLayering, Self::WithEngineLayering, Self::WithHandlers, Self::WithSemanticReads, Self::WithSetterPublishes, Self::WithReactivePolicies, Self::WithUntyped, Self::WithDerivedReads, Self::WithSysReactive, Self::WithLifeforms, Self::WithPlayerLink, Self::WithLifeformsAndPlayerLink, Self::WithReferencePolicies, Self::WithRequirementBool, Self::WithKeys, Self::WithMapEdits, Self::WithOrderAndOwnership, Self::WithDeclarationPolicies, Self::WithRawDeclarationPolicies, Self::AllRawFilePolicies, Self::WithDocSnippets, Self::WithUiActions, Self::WithRawRuntimePolicies, Self::WithWorkspaceFoldPolicies, Self::WithSysSourcePolicies, Self::WithStoredAndTracked];

    /// Independently qualified Analyze-only capture plans.
    pub const GENERIC_V2: [Self; 4] = [
        Self::Base, Self::WithCooldown, Self::WithEngineInternal, Self::WithCooldownAndEngineInternal,
    ];

    fn names_v2() -> impl Iterator<Item = Self> {
        Self::GENERIC_V2.into_iter().chain([Self::WithLibraryLayering])
    }

    pub fn v2_for(judgment: JudgmentV2) -> &'static [Self] {
        match judgment {
            JudgmentV2::Raw | JudgmentV2::CiCeilings => &Self::GENERIC_V2,
            JudgmentV2::CiLibrarySites => &[Self::WithLibraryLayering],
        }
    }

    pub fn is_source_only(self) -> bool {
        matches!(self, Self::AllRawFilePolicies | Self::WithDocSnippets | Self::WithUiActions)
    }

    pub fn workspace_roots(self) -> &'static [&'static str] {
        match self {
            Self::AllRawFilePolicies => &["code", "interface", "maps", "modular_chomp"],
            Self::WithDocSnippets => &["code", "doc/rewrite", "maps"],
            Self::WithUiActions => &["code", "maps", "tgui/packages/tgui/interfaces"],
            Self::WithCheckGrep => &["code", "maps", "tgui"],
            _ => &["code", "maps"],
        }
    }

    pub fn is_combined(self) -> bool {
        matches!(self, Self::WithSemanticReads | Self::WithReactivePolicies | Self::WithUntyped | Self::WithStoredAndTracked)
    }

    pub fn names(self) -> &'static [&'static str] {
        match self {
            Self::Base => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithDeadlinePolling => &["allow_annotations", "deadline_polling", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithCheckGrep => &["allow_annotations", "check_grep", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithCooldown => &["allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithEngineInternal => &["allow_annotations", "engine_internal", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithCooldownAndEngineInternal => &["allow_annotations", "cooldown", "engine_internal", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithSilicon => &["allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler", "silicon_entry"],
            Self::WithSetterPublishes => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler", "setter_publishes"],
            Self::WithSemanticReads => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler", "sem/reads", "untracked_inputs"],
            Self::WithReactivePolicies => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler", "sem/reads", "setter_publishes", "untracked_inputs"],
            Self::WithDerivedReads => &["allow_annotations", "derived_reads", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithPlayerLink => &["allow_annotations", "notice_publisher", "player_link", "report_in_catch", "scheduler"],
            Self::WithLifeforms => &["allow_annotations", "lifeforms", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithLifeformsAndPlayerLink => &["allow_annotations", "lifeforms", "notice_publisher", "player_link", "report_in_catch", "scheduler"],
            Self::WithReferencePolicies => &["allow_annotations", "notice_publisher", "rel_write_undeclared", "report_in_catch", "scheduler", "untyped_member", "weak_raw_read"],
            Self::WithRawRuntimePolicies => &[
                "allow_annotations", "interactions", "latent", "notice_publisher", "pollers",
                "pool", "read_back", "report_in_catch", "scheduler",
            ],
            Self::WithStoredAndTracked => &[
                "allow_annotations", "notice_publisher", "report_in_catch", "scheduler",
                "stored_refs", "tracked", "tracked_tests",
            ],
            Self::WithSysSourcePolicies => &[
                "allow_annotations", "notice_publisher", "report_in_catch", "scheduler",
                "sys/dx_constructor_shadow", "sys/dx_look_side_effects", "sys/dx_manual_fingerprint_log", "sys/dx_string_names",
                "sys/expiry", "sys/hygiene", "sys/requirements", "sys/resolvers",
                "sys/sfx", "sys/tables", "sys/ui", "system_boundary",
            ],
            Self::WithWorkspaceFoldPolicies => &[
                "allow_annotations", "api", "cache", "instance_list",
                "lifecycle", "notice_publisher", "report_in_catch", "scheduler",
                "state_schema", "sys/appearance", "sys/dx_ownership_forms", "sys/fields",
                "sys/loot",
            ],
            Self::WithUiActions => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler", "ui_actions"],
            Self::WithDocSnippets => &["allow_annotations", "doc_snippets", "notice_publisher", "report_in_catch", "scheduler"],
            Self::AllRawFilePolicies => &[
                // deadline_polling has its own configuration/allowlist subject.
                "actor_forwarding", "allow_annotations", "breakpoint", "containment",
                "dcs", "door_gates", "engine_internal", "entity_ids",
                "entry_slots", "i7_handler", "in_precedence", "leftovers",
                "legacy_forms", "lifecycle_counts", "lifeform_allows", "escape_hatches",
                "mouse_override", "native_ref_write", "notice_publisher", "organ_slots",
                "qdel_src", "reactions_table_proc", "ref_text", "registry",
                "report_in_catch", "saved_handle", "scheduler", "silent_catch",
                "spatial", "stance_examine", "subsystem_fire", "sys/contents",
                "sys/damage_reactions", "sys/dx_manual_transfer", "sys/dx_raw_delay", "sys/dx_raw_overlays",
                "sys/dx_review", "sys/emag", "sys/grants", "sys/messages",
                "sys/presentation", "sys/sync_sql", "sys/topic", "sys/usr_use",
                "verb_category",
            ],
            Self::WithRawDeclarationPolicies => &["allow_annotations", "cap_bits", "declaration_block", "duplicate_input_key", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithDeclarationPolicies => &["allow_annotations", "base_vars", "decl", "init", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithMapEdits => &["allow_annotations", "map_edits", "notice_publisher", "report_in_catch", "scheduler"],
            Self::WithOrderAndOwnership => &["allow_annotations", "notice_publisher", "op_order", "ownership", "report_in_catch", "scheduler"],
            Self::WithKeys => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler", "sem/keys"],
            Self::WithRequirementBool => &["allow_annotations", "notice_publisher", "report_in_catch", "requirement_bool", "scheduler"],
            Self::WithSysReactive => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler", "sys/dx_reactive"],
            Self::WithUntyped => &["allow_annotations", "notice_publisher", "report_in_catch", "scheduler", "untyped"],
            Self::WithHandlers => &["allow_annotations", "cooldown", "notice_publisher", "report_in_catch", "scheduler", "sem/handlers"],
            Self::WithEngineLayering => &["allow_annotations", "engine_layering", "notice_publisher", "report_in_catch", "scheduler"],
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
/// V2 serializes the ordered registered policy names instead of a v1 alias.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct SelectedPoliciesV2(Roster);
impl SelectedPoliciesV2 {
    pub fn for_roster(roster: Roster) -> io::Result<Self> {
        if !Roster::names_v2().any(|candidate| candidate == roster) {
            return Err(invalid("selected policy set is outside Analyze-only v2 qualification"));
        }
        Ok(Self(roster))
    }
    pub fn names(self) -> &'static [&'static str] { self.0.names() }
}
impl Serialize for SelectedPoliciesV2 {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.names().serialize(serializer)
    }
}
impl<'de> Deserialize<'de> for SelectedPoliciesV2 {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct Policies;
        impl<'de> serde::de::Visitor<'de> for Policies {
            type Value = SelectedPoliciesV2;
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("a qualified ordered Analyze-only policy set")
            }
            fn visit_seq<A: serde::de::SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
                let mut candidates = [None; Roster::GENERIC_V2.len() + 1];
                for (slot, roster) in candidates.iter_mut().zip(Roster::names_v2()) { *slot = Some(roster); }
                for i in 0..=Roster::MAX_POLICIES {
                    let name = seq.next_element::<String>()?;
                    for roster in &mut candidates {
                        if roster.is_some_and(|r| r.names().get(i).copied() != name.as_deref()) {
                            *roster = None;
                        }
                    }
                    if name.is_none() {
                        return candidates.into_iter().flatten().next().map(SelectedPoliciesV2)
                            .ok_or_else(|| serde::de::Error::custom("unqualified or unordered v2 selected policies"));
                    }
                    if candidates.iter().all(Option::is_none) { break; }
                }
                Err(serde::de::Error::custom("unqualified or oversized v2 selected policies"))
            }
        }
        deserializer.deserialize_seq(Policies)
    }
}

/// Presentation over the same actual selected producers. No baseline updates,
/// model choices or filesystem targets are expressible through this field.
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum JudgmentV2 {
    #[default]
    Raw,
    CiCeilings,
    CiLibrarySites,
}
impl JudgmentV2 {
    pub fn is_raw(&self) -> bool { *self == Self::Raw }
}

/// Source-only coordinates from the actual retained raw-query preparation.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RawSelectedFrame {
    pub query_revision: Hex128,
    pub source_revision: Hex128,
    pub policy_revision: Hex128,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum RawSelectedSchema {
    #[serde(rename = "native-analyze-raw-selected-batch-v1")]
    V1,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RawSelectedTerminal {
    pub schema: RawSelectedSchema,
    pub roster: Roster,
    pub frame: RawSelectedFrame,
    pub clean: bool,
    pub report: Seal,
}
impl RawSelectedTerminal {
    pub fn require(self, expected: Roster) -> io::Result<()> {
        if !expected.is_source_only() || self.roster != expected {
            return Err(invalid("raw selected terminal differs from its closed roster"));
        }
        self.report.require_bound()
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum SchemaV2 {
    #[serde(rename = "native-analyze-exclusions-batch-v2")]
    V2,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct TerminalV2 {
    pub schema: SchemaV2,
    pub policies: SelectedPoliciesV2,
    #[serde(default, skip_serializing_if = "JudgmentV2::is_raw")]
    pub judgment: JudgmentV2,
    pub frame: Frame,
    pub clean: bool,
    #[serde(deserialize_with = "explicit_option")]
    pub diagnostics: Option<Seal>,
    pub report: Seal,
}
impl TerminalV2 {
    pub fn require(self, expected: Roster) -> io::Result<()> {
        self.require_using(expected, JudgmentV2::Raw)
    }
    pub fn require_using(self, expected: Roster, judgment: JudgmentV2) -> io::Result<()> {
        if self.judgment != judgment || !Roster::v2_for(judgment).contains(&expected) {
            return Err(invalid("selected v2 terminal differs from the requested judgment or scope"));
        }
        if self.policies != SelectedPoliciesV2::for_roster(expected)? {
            return Err(invalid("selected v2 terminal names foreign policies"));
        }
        self.report.require_bound()?;
        if let Some(diagnostics) = self.diagnostics {
            diagnostics.require_bound()?;
            if self.report.length.checked_add(diagnostics.length).is_none_or(|n| n > MAX_STREAM) {
                return Err(invalid("selected v2 report and notices exceed the aggregate stream bound"));
            }
        }
        Ok(())
    }
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

/// Standalone named ImageDir terminal. It has no exclusions roster, ALLOW
/// join, checker output or diagnostics channel.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum NamedImageDirSchema {
    #[serde(rename = "native-analyze-image-dir-v1")]
    V1,
}
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct NamedImageDirTerminal {
    pub schema: NamedImageDirSchema,
    pub frame: Frame,
    pub clean: bool,
    pub report: Seal,
}
impl NamedImageDirTerminal {
    pub fn require(self)->io::Result<()>{self.report.require_bound()}
}

/// Named ImageDir plus its completed Original warning/hint stream. The v1
/// notice-free named terminal and the selected/combined rosters are separate.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum NamedImageDirNoticeSchema {
    #[serde(rename = "native-analyze-image-dir-notices-v1")]
    V1,
}
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct NamedImageDirNoticeTerminal {
    pub schema: NamedImageDirNoticeSchema,
    pub frame: Frame,
    pub clean: bool,
    #[serde(deserialize_with = "explicit_option")]
    pub diagnostics: Option<Seal>,
    pub report: Seal,
}
impl NamedImageDirNoticeTerminal {
    pub fn require(self) -> io::Result<()> {
        self.report.require_bound()?;
        if let Some(diagnostics) = self.diagnostics {
            diagnostics.require_bound()?;
            if self.report.length.checked_add(diagnostics.length).is_none_or(|n| n > MAX_STREAM) {
                return Err(invalid("named ImageDir report and notices exceed the aggregate stream bound"));
            }
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
        if expected.is_source_only() || self.roster != expected {
            return Err(invalid("selected report terminal names a foreign roster"));
        }
        self.report.require_bound()?;
        if let Some(diagnostics) = self.diagnostics {
            diagnostics.require_bound()?;
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub enum CombinedSchema {
    #[serde(rename = "native-checker-analyze-selected-batch-v1")]
    V1,
}

/// The two reports share one semantic/source preparation. Checker and
/// Analyze each retain the policy revision of their own actual configuration.
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct CombinedTerminal {
    pub schema: CombinedSchema,
    pub roster: Roster,
    pub frame: Frame,
    pub checker_policy_revision: Hex128,
    pub clean: bool,
    #[serde(deserialize_with = "explicit_option")]
    pub diagnostics: Option<Seal>,
    pub checker: Seal,
    pub report: Seal,
}
impl CombinedTerminal {
    pub fn require(self) -> io::Result<()> {
        if !self.roster.is_combined() {
            return Err(invalid("combined selected report requires its qualified semantic roster"));
        }
        self.report.require_bound()?;
        self.checker.require_bound()?;
        if let Some(diagnostics) = self.diagnostics {
            diagnostics.require_bound()?;
        }
        let total = self.report.length.checked_add(self.checker.length)
            .and_then(|sum| sum.checked_add(self.diagnostics.map_or(0, |seal| seal.length)));
        if total.is_none_or(|total| total > MAX_STREAM) {
            return Err(invalid("combined selected report exceeds the aggregate stream bound"));
        }
        Ok(())
    }
}
