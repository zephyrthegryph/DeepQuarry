//! Compact request-local source certificates; wide indices remain exact.
#[derive(Debug)]
pub(crate) enum OriginRoster {
    Compact(Box<[(u32, u32)]>),
    Wide(Box<[(usize, u32)]>),
}

impl OriginRoster {
    pub(crate) fn from_entries(entries: impl IntoIterator<Item = (usize, u32)>) -> Self {
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
                    return Self::Wide(wide.into_boxed_slice());
                }
            }
        }
        Self::Compact(compact.into_boxed_slice())
    }

    pub(crate) fn len(&self) -> usize {
        match self {
            Self::Compact(entries) => entries.len(),
            Self::Wide(entries) => entries.len(),
        }
    }

    pub(crate) fn get(&self, index: usize) -> Option<(usize, u32)> {
        match self {
            Self::Compact(entries) => entries
                .get(index)
                .map(|&(path, line)| (path as usize, line)),
            Self::Wide(entries) => entries.get(index).copied(),
        }
    }

    pub(crate) fn iter(&self) -> impl Iterator<Item = (usize, u32)> + '_ {
        (0..self.len()).map(|index| match self {
            Self::Compact(entries) => {
                let (path, line) = entries[index];
                (path as usize, line)
            }
            Self::Wide(entries) => entries[index],
        })
    }

    pub(crate) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        match self {
            Self::Compact(entries) => {
                census.slice("current_image.origins.compact", entries, true);
            }
            Self::Wide(entries) => {
                census.slice("current_image.origins.wide", entries, true);
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
            image.origins.census(census, "current_image.origins");
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
        if let OriginRoster::Compact(entries) = &roster {
            assert_eq!(std::mem::size_of_val(entries.as_ref()), input.len() * 8);
        }
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
