//! Compact request-local source certificates; wide indices remain exact.
pub(super) enum OriginRoster {
    Compact(Vec<(u32, u32)>),
    Wide(Vec<(usize, u32)>),
}

impl OriginRoster {
    pub(super) fn from_entries(entries: impl IntoIterator<Item = (usize, u32)>) -> Self {
        let mut compact = Vec::new();
        let mut entries = entries.into_iter();
        while let Some((path, line)) = entries.next() {
            match u32::try_from(path) {
                Ok(path) => compact.push((path, line)),
                Err(_) => {
                    let mut wide: Vec<_> = compact
                        .into_iter()
                        .map(|(path, line)| (path as usize, line))
                        .collect();
                    wide.push((path, line));
                    wide.extend(entries);
                    return Self::Wide(wide);
                }
            }
        }
        Self::Compact(compact)
    }

    pub(super) fn len(&self) -> usize {
        match self {
            Self::Compact(entries) => entries.len(),
            Self::Wide(entries) => entries.len(),
        }
    }

    pub(super) fn iter(&self) -> impl Iterator<Item = (usize, u32)> + '_ {
        (0..self.len()).map(|index| match self {
            Self::Compact(entries) => {
                let (path, line) = entries[index];
                (path as usize, line)
            }
            Self::Wide(entries) => entries[index],
        })
    }

    fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        match self {
            Self::Compact(entries) => {
                census.vec_payload("current_image.origins.compact", entries);
            }
            Self::Wide(entries) => {
                census.vec_payload("current_image.origins.wide", entries);
            }
        }
    }
}

impl super::FrozenBatch {
    pub(crate) fn census_current_images(&self, census: &mut crate::heap_census::HeapCensus) {
        let images = self
            .units
            .iter()
            .filter_map(|unit| unit.current_image.as_ref())
            .chain(
                self.helpers
                    .iter()
                    .filter_map(|helper| helper.current_image.as_ref()),
            )
            .chain(
                self.initializers
                    .iter()
                    .filter_map(|initializer| initializer.current_image.as_ref()),
            );
        for image in images {
            image.origins.census(census);
            census.vec_payload("current_image.paths", &image.paths);
            for path in &image.paths {
                census.arc_text("current_image.paths", path);
            }
            if census.arc_object("current_image.words", &image.image.words) {
                census.vec_payload("current_image.words", &image.image.words);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::OriginRoster;

    #[test]
    fn common_roster_is_compact_and_preserves_every_line() {
        let input = [(0, 0), (7, u32::MAX), (u32::MAX as usize, 42)];
        let roster = OriginRoster::from_entries(input);
        assert!(matches!(&roster, OriginRoster::Compact(_)));
        assert_eq!(roster.iter().collect::<Vec<_>>(), input);
        assert_eq!(std::mem::size_of::<(u32, u32)>(), 8);
    }

    #[cfg(target_pointer_width = "64")]
    #[test]
    fn overflow_widens_prior_and_future_entries_without_truncation() {
        let input = [(7, 1), (usize::MAX, 2), (0, 3)];
        let roster = OriginRoster::from_entries(input);
        assert!(matches!(&roster, OriginRoster::Wide(_)));
        assert_eq!(roster.iter().collect::<Vec<_>>(), input);
    }
}
