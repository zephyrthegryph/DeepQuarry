//! Final VM-domain image on the existing symbolic payload owner. Current sites
//! are always validated before a final-image hit; no source authority is held.
use super::*;
#[derive(Default)]
pub(super) struct WireImage {
    current: std::sync::Mutex<Option<Wired>>,
}
struct Wired {
    base: ProcedureImage,
    answers: dm_link::TypePathAnswers,
    final_image: ProcedureImage,
}
impl WireImage {
    pub(super) fn image(
        &self,
        base: ProcedureImage,
        code: &dm_ir::SymbolicCode,
        tables: &LinkTables,
        mobs: &dm_link::MobBindings,
    ) -> Result<ProcedureImage, IntegrationError> {
        let bound = dm_link::bind_type_path_words(&base.words, code, tables, mobs)
            .map_err(IntegrationError::WireDomain)?;
        let mut current = self.current.lock().unwrap_or_else(|e| e.into_inner());
        if bound.is_empty() {
            drop(bound);
            *current = None;
            return Ok(base);
        }
        if let Some(hit) = current
            .as_ref()
            .filter(|hit| Arc::ptr_eq(&hit.base.words, &base.words) && bound.matches(&hit.answers))
        {
            return Ok(hit.final_image.clone());
        }
        let (final_image, answers) = bound.encode_with_answers();
        let image = final_image.clone();
        *current = Some(Wired {
            base,
            answers,
            final_image,
        });
        Ok(image)
    }
    pub(super) fn visit_retained(
        &self,
        mut visitor: impl FnMut(&ProcedureImage, &dm_link::TypePathAnswers, &ProcedureImage),
    ) {
        let current = self.current.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(wired) = current.as_ref() {
            visitor(&wired.base, &wired.answers, &wired.final_image);
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> (dm_ir::SymbolicCode, ProcedureImage, LinkTables, SymbolId) {
        let path = SymbolId::of("/mob/example");
        let tables = LinkTables::build(LinkInventory {
            fixed: vec![(Key::Type(path), 100)],
            entries: vec![Entry {
                key: Key::Type(path),
                content: b"type".to_vec().into(),
            }],
            spellings: vec![(path, Arc::from(&b"/mob/example"[..]))],
            ..Default::default()
        })
        .unwrap();
        let code = dm_ir::SymbolicCode::new(
            vec![0, 0],
            vec![dm_ir::Relocation {
                offset: 0,
                reference: SymRef::Type(path),
                encoding: dm_ir::RelocationEncoding::PackedValue24 { tag: 8 },
            }],
        )
        .unwrap();
        let base = tables.link(&code, &Default::default()).unwrap();
        (code, base, tables, path)
    }
    #[test]
    fn retained_wire_image_requires_current_mob_proof_and_authentic_base() {
        let (code, base, tables, path) = fixture();
        let owner = Arc::new(latest_image::LatestImage::default());
        let retained = Arc::clone(&owner);
        let mobs = dm_link::MobBindings::from([(path, 7)]);
        assert_eq!(
            latest_image::LatestImage::wire_words(&owner, base.clone(), &code, &tables, &mobs)
                .unwrap(),
            vec![8, 7]
        );
        let mut first = None;
        owner.visit_retained_wire(|_, _, image| first = Some(Arc::clone(&image.words)));
        let first = first.unwrap();
        assert_eq!(
            latest_image::LatestImage::wire_words(&owner, base.clone(), &code, &tables, &mobs)
                .unwrap(),
            vec![8, 7]
        );
        owner.visit_retained_wire(|_, _, image| assert!(Arc::ptr_eq(&first, &image.words)));
        let mut one = crate::heap_census::HeapCensus::new("one");
        one.latest_image(&owner);
        let one = one.finish();
        let mut duplicate = crate::heap_census::HeapCensus::new("duplicate");
        duplicate.latest_image(&owner);
        duplicate.latest_image(&retained);
        if duplicate.arc_object("external_base", &base.words) {
            duplicate.vec_payload("external_base", &base.words);
        }
        if duplicate.arc_object("external_final", &first) {
            duplicate.vec_payload("external_final", &first);
        }
        let duplicate = duplicate.finish();
        assert_eq!(
            one.unique_known_capacity_bytes,
            duplicate.unique_known_capacity_bytes
        );
        assert!(one
            .owners
            .iter()
            .any(|entry| entry.owner == "latest_images.wire_answers"
                && entry.unique_known_capacity_bytes > 0));
        let changed = dm_link::MobBindings::from([(path, 8)]);
        assert_eq!(
            latest_image::LatestImage::wire_words(&owner, base.clone(), &code, &tables, &changed)
                .unwrap(),
            vec![8, 8]
        );
        owner.visit_retained_wire(|_, _, image| assert!(!Arc::ptr_eq(&first, &image.words)));
        let invalid = ProcedureImage {
            words: Arc::new(vec![8, 999]),
        };
        assert!(
            latest_image::LatestImage::wire_words(&owner, invalid, &code, &tables, &changed)
                .is_err()
        );
        let plain = ProcedureImage {
            words: Arc::new(vec![42]),
        };
        assert_eq!(
            latest_image::LatestImage::wire_words(
                &owner,
                plain,
                &Default::default(),
                &tables,
                &changed
            )
            .unwrap(),
            vec![42]
        );
        let mut present = false;
        owner.visit_retained_wire(|_, _, _| present = true);
        assert!(!present);
    }
    #[test]
    fn unique_completion_preserves_in_place_word_allocation_and_retains_nothing() {
        let (code, base, tables, path) = fixture();
        let pointer = base.words.as_ptr();
        let owner = Arc::new(latest_image::LatestImage::default());
        let words = latest_image::LatestImage::wire_words(
            &owner,
            base,
            &code,
            &tables,
            &dm_link::MobBindings::from([(path, 7)]),
        )
        .unwrap();
        assert_eq!(words, vec![8, 7]);
        assert_eq!(pointer, words.as_ptr());
        let mut present = false;
        owner.visit_retained_wire(|_, _, _| present = true);
        assert!(!present);
    }
}
