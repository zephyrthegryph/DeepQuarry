//! Borrowed final output enumeration shared by wire encoding and staging.
use super::{Artifact, GeneratorName};
pub(crate) enum GeneratedFiles<'a> {
    Single(Option<(&'static str, &'a str)>),
    Multiple(std::slice::Iter<'a, (String, String)>),
}
impl<'a> Iterator for GeneratedFiles<'a> {
    type Item = (&'a str, &'a str);
    fn next(&mut self) -> Option<Self::Item> {
        match self {
            Self::Single(value) => value.take(),
            Self::Multiple(values) => values
                .next()
                .map(|(path, text)| (path.as_str(), text.as_str())),
        }
    }
    fn size_hint(&self) -> (usize, Option<usize>) {
        let length = self.len();
        (length, Some(length))
    }
}
impl ExactSizeIterator for GeneratedFiles<'_> {
    fn len(&self) -> usize {
        match self {
            Self::Single(value) => usize::from(value.is_some()),
            Self::Multiple(values) => values.len(),
        }
    }
}
impl Artifact {
    pub(crate) fn generated_files(&self) -> GeneratedFiles<'_> {
        if matches!(
            self.name,
            GeneratorName::UiTypes | GeneratorName::DerivedReads
        ) {
            GeneratedFiles::Multiple(self.files.iter())
        } else {
            GeneratedFiles::Single(Some((self.name.path(), self.text.as_str())))
        }
    }
}
