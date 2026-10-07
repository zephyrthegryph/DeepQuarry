//! Finite positive native 516.1687 callable receipts.
//! Every pair has an authored bare override with Proc namespace, flags 4,
//! source (0,255), exact display spelling and absent desc/category/ext flags.
//! These establish no inherited signature, operand IDs or name absence.
use dm_codegen_byond::procedure_abi::{Category, ProcLayout};
use dm_ir::SymbolId;
use dm_tree::MemberKind;

const OBSERVED_FLAGS: u32 = 4;
const OBSERVED_SOURCE_KIND: u8 = 0;
const OBSERVED_SOURCE_PARAMETER: u8 = 255;

#[derive(Clone, Copy)]
pub(crate) struct Fact {
    pub owner: &'static str,
    pub name: &'static str,
    pub kind: MemberKind,
}
impl Fact {
    /// Explicit observed header, independent of generic fresh-procedure policy.
    pub(crate) fn layout(self) -> ProcLayout {
        ProcLayout {
            display_name: Some(self.name.as_bytes().to_vec()),
            description: None,
            category: Category::Default,
            source_kind: OBSERVED_SOURCE_KIND,
            source_parameter: OBSERVED_SOURCE_PARAMETER,
            flags: OBSERVED_FLAGS,
            invisibility: None,
        }
    }
}
const FAMILIES: &[(&str, &[&str])] = &[
    (
        "/client",
        &[
            "New",
            "Del",
            "Topic",
            "Stat",
            "AllowUpload",
            "Move",
            "Click",
            "DblClick",
            "MouseDown",
            "MouseDrag",
            "MouseDrop",
            "MouseEntered",
            "MouseExited",
            "MouseUp",
            "Export",
            "MouseMove",
            "MouseWheel",
            "Northeast",
            "Northwest",
            "Southeast",
            "Southwest",
            "Center",
        ],
    ),
    ("/datum", &["New", "Del", "Topic"]),
    (
        "/world",
        &[
            "New", "Del", "Error", "Reboot", "Topic", "Export", "IsBanned", "Profile", "Tick",
        ],
    ),
    (
        "/atom",
        &[
            "New",
            "Del",
            "Entered",
            "Exited",
            "Enter",
            "Exit",
            "Click",
            "DblClick",
            "MouseDrop",
            "MouseEntered",
            "MouseExited",
            "MouseDown",
            "MouseDrag",
            "MouseUp",
            "Stat",
            "Cross",
            "Crossed",
            "Uncross",
            "Uncrossed",
            "MouseMove",
            "MouseWheel",
        ],
    ),
    ("/mob", &["New", "Del", "Login", "Logout"]),
    ("/atom/movable", &["Bump", "Move"]),
    ("/area", &["Enter", "Entered", "Exit", "Exited"]),
    ("/turf", &["Enter", "Entered", "Exit", "Exited"]),
    ("/icon", &["Insert", "New"]),
    ("/image", &["New"]),
    ("/matrix", &["Add", "Multiply", "New", "Subtract"]),
    ("/sound", &["New"]),
];
pub(crate) fn facts() -> impl Iterator<Item = Fact> {
    FAMILIES.iter().flat_map(|&(owner, names)| {
        names.iter().copied().map(move |name| Fact {
            owner,
            name,
            kind: MemberKind::Proc,
        })
    })
}
pub(crate) fn lookup(owner: SymbolId, name: SymbolId) -> Option<Fact> {
    facts().find(|fact| SymbolId::of(fact.owner) == owner && SymbolId::of(fact.name) == name)
}
/// Both engine presence and ABI policy bind the same exact observed inventory.
pub(crate) fn append_fingerprint(bytes: &mut Vec<u8>) {
    bytes.extend_from_slice(b"native-callable-receipts-5161687-v1\0");
    for fact in facts() {
        for text in [fact.owner, fact.name] {
            bytes.extend_from_slice(&(text.len() as u64).to_le_bytes());
            bytes.extend_from_slice(text.as_bytes());
        }
        bytes.push(fact.kind as u8);
        bytes.extend_from_slice(&OBSERVED_FLAGS.to_le_bytes());
        bytes.extend_from_slice(&[OBSERVED_SOURCE_KIND, OBSERVED_SOURCE_PARAMETER, 0, 0, 0]);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn finite_receipts_certify_proc_namespace_without_name_absence() {
        let fact = lookup(SymbolId::of("/client"), SymbolId::of("Northeast")).unwrap();
        assert_eq!(fact.kind, MemberKind::Proc);
        let layout = fact.layout();
        assert_eq!(
            layout.display_name.as_deref(),
            Some(b"Northeast".as_slice())
        );
        assert_eq!(layout.encoded_flags(), (4, None));
        assert_eq!((layout.source_kind, layout.source_parameter), (0, 255));
        assert_eq!(layout.category, Category::Default);
        assert!(layout.description.is_none());
        assert!(layout.invisibility.is_none());
        assert!(lookup(SymbolId::of("/client"), SymbolId::of("UnobservedCallback")).is_none());
        assert!(lookup(SymbolId::of("/datum"), SymbolId::of("Crossed")).is_none());
        assert!(lookup(SymbolId::of("/list"), SymbolId::of("Copy")).is_none());
    }
}
