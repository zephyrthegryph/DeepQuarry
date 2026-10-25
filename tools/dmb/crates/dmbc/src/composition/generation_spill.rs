//! A generation's patch base on disk (see `crate::variant_spill`): written before the base would be dropped, restored lazily at
//! patch admission.
use super::*;
use std::path::PathBuf;

/// Where this variant's stored base lives, and what is known of the file.
#[derive(Default)]
pub(super) struct SpillState {
    /// Directory and key of the variant's file, set by each request of the variant (`attach_spill`).
    target: Option<(PathBuf, u128)>,
    /// What the file held when this generation last looked or wrote.
    stored: Option<crate::variant_spill::Header>,
}

impl RetainedGeneration {
    /// Tell this generation which file holds its variant's stored patch base (the directory is the cache root's spill
    /// directory, the key says which variant). Idempotent per request; looks at the file's header once per target.
    pub fn attach_spill(&self, directory: PathBuf, key: u128) {
        if !crate::variant_spill::enabled() {
            return;
        }
        let mut state = self.spill.lock().unwrap_or_else(|e| e.into_inner());
        if state.target.as_ref().is_some_and(|(known, known_key)| *known == directory && *known_key == key) {
            return;
        }
        state.stored = crate::variant_spill::peek(&directory, key);
        if let Some(header) = &state.stored {
            crate::daemon_eprintln!(
                "native variant spill: stored patch base found image={:032x} bodies={} bytes={}",
                header.dmb_hash,
                header.text_key.1,
                header.image_bytes
            );
        }
        state.target = Some((directory, key));
    }

    /// The stored base's image digest, while the base is on disk and not in memory.
    pub(super) fn stored_image_hash(&self) -> Option<u128> {
        self.spill.lock().unwrap_or_else(|e| e.into_inner()).stored.as_ref().map(|header| header.dmb_hash)
    }

    /// Write the published patch base to this variant's file, unless that file already holds this image. Returns what was
    /// written (for the log). Run before idle tiers and variant stashes drop the base.
    pub(crate) fn spill_patch_base(&self, workers: usize) -> Option<String> {
        let (directory, key) = self.spill.lock().unwrap_or_else(|e| e.into_inner()).target.clone()?;
        let slot = self
            .publication
            .with_published(|old| old.patch.lock().unwrap_or_else(|e| e.into_inner()).clone())
            .unwrap_or_else(|| self.patch.lock().unwrap_or_else(|e| e.into_inner()).clone());
        let (Some(base), Some(link), Some(image)) = (slot.base.as_ref(), slot.link.as_ref(), slot.image.as_ref()) else {
            return None;
        };
        let hash = image.rows.image().content_hash();
        if self
            .spill
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .stored
            .as_ref()
            .is_some_and(|header| header.dmb_hash == hash)
        {
            return Some(format!("image {hash:032x} already stored"));
        }
        let message = match crate::variant_spill::write(&directory, key, base, link, slot.fields.as_ref(), image, workers) {
            Ok(written) => {
                self.spill.lock().unwrap_or_else(|e| e.into_inner()).stored = crate::variant_spill::peek(&directory, key);
                let evicted = crate::variant_spill::evict(&directory, None);
                format!(
                    "stored image {hash:032x} bodies={} {:.1} MB in {:.2}s{}{}",
                    base.text_key().1,
                    written.bytes as f64 / 1e6,
                    written.seconds,
                    if evicted.is_empty() { "" } else { "; " },
                    evicted
                )
            }
            Err(error) => format!("not stored: {error}"),
        };
        crate::daemon_eprintln!("native variant spill: {message}");
        Some(message)
    }

    /// Put the stored base in this request's patch slot when the slot has none and the file describes a build with the
    /// program text the request has (`wanted`, from `OutputBase::text_key`). Returns whether a base was installed.
    pub(crate) fn restore_patch_base(&self, wanted: (u128, usize)) -> bool {
        let Some((directory, key)) = self.spill.lock().unwrap_or_else(|e| e.into_inner()).target.clone() else {
            return false;
        };
        if self.patch.lock().unwrap_or_else(|e| e.into_inner()).base.is_some() {
            return false;
        }
        let Some(header) = crate::variant_spill::peek(&directory, key) else {
            return false;
        };
        if header.text_key != (wanted.0, wanted.1 as u64) {
            crate::daemon_eprintln!(
                "native variant spill: stored base has other program text (bodies {} against {}); not restored",
                header.text_key.1,
                wanted.1
            );
            return false;
        }
        let started = std::time::Instant::now();
        let restored = match crate::variant_spill::read(&directory, key) {
            Ok(restored) => restored,
            Err(error) => {
                crate::daemon_eprintln!("native variant spill: stored base unreadable: {error}");
                return false;
            }
        };
        let mut slot = self.patch.lock().unwrap_or_else(|e| e.into_inner());
        if slot.base.is_some() {
            return false;
        }
        slot.link = Some(Arc::new(restored.link));
        slot.fields = restored.fields;
        slot.base = Some(Arc::new(restored.base));
        slot.image = Some(Arc::new(restored.image));
        slot.model_rows.clear();
        slot.model_anchor = None;
        drop(slot);
        self.spill.lock().unwrap_or_else(|e| e.into_inner()).stored = Some(header.clone());
        crate::daemon_eprintln!(
            "native variant spill: restored patch base image={:032x} bodies={} {:.1} MB in {:.2}s",
            header.dmb_hash,
            header.text_key.1,
            header.image_bytes as f64 / 1e6,
            started.elapsed().as_secs_f64()
        );
        true
    }
}
