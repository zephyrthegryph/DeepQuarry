//! Preserve the existing string codec while sharing current lexical arenas.
use crate::{SourceText, SourceTextStorage};
use serde::{Deserialize, Deserializer, Serializer};
use std::{mem::align_of, sync::Arc};

pub(super) fn serialize<S: Serializer>(
    text: &SourceText,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serializer.serialize_str(text.as_str())
}
pub(super) fn deserialize<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<SourceText, D::Error> {
    Arc::<str>::deserialize(deserializer).map(SourceText::from)
}
/// Budgeted legacy callers charge whole retained arenas, including shared ones
/// per encounter. Counting only the view length would undercharge an owner.
pub(super) fn retained_size(text: &SourceText) -> usize {
    let mut bytes = 0usize;
    text.visit_storage(|_, descriptor, storage| {
        bytes = super::retained_size::arc_bytes(descriptor, align_of::<usize>());
        bytes = bytes.saturating_add(match storage {
            SourceTextStorage::Original(value) => super::retained_size::slice::<u8>(value.len()),
            SourceTextStorage::Transformed(value) => value.capacity(),
        });
    });
    text.visit_fingerprint_storage(|_, _, capacity| bytes = bytes.saturating_add(capacity));
    bytes
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::{Deserialize, Serialize};

    #[derive(Serialize, Deserialize)]
    struct Shared(#[serde(with = "super")] SourceText);
    #[derive(Serialize, Deserialize)]
    struct Legacy(Arc<str>);

    #[test]
    fn exact_string_wire_is_unchanged_for_a_shared_subview() {
        let arena: SourceText = "prefix α text suffix".to_owned().into();
        let view = arena.view(7..14);
        let previous = dm_wire::encode(3, &Legacy(Arc::from(view.as_str()))).unwrap();
        let current = dm_wire::encode(3, &Shared(view.clone())).unwrap();
        assert_eq!(current, previous);
        let decoded: Shared = dm_wire::decode(3, &current, current.len()).unwrap();
        assert_eq!(decoded.0, view);
        assert!(!decoded.0.same_view(&view));
    }
}
