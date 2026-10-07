//! Input capture for ordered map/skin includes. This is an explicit I/O boundary,
//! separate from pure map planning, semantic queries and backend composition.
use crate::frontend::ColdFrontend;
use crate::maps::CapturedMap;
use dm_preprocess::regions::{NonTextKind, OrderedItem};
use dm_preprocess::SourceProvider;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;

#[derive(Clone, Debug)]
pub struct CapturedSkin {
    pub path: Arc<PathBuf>,
    pub include_occurrence: u32,
    pub source: Arc<str>,
    pub source_identity: u128,
}
#[derive(Clone, Debug)]
pub enum NonTextInput {
    Map(CapturedMap),
    Skin(CapturedSkin),
}
#[derive(Clone, Debug)]
pub struct CaptureError {
    pub path: Arc<PathBuf>,
    pub include_occurrence: usize,
    pub message: String,
}
/// Read each distinct captured path once, retaining the manifest's joint include
/// order and separate occurrence identities for repeated map/skin includes.
/// Skin bytes remain explicitly opaque; this does not claim DMF compilation.
pub fn capture<P: SourceProvider>(
    frontend: &ColdFrontend,
    provider: &P,
) -> Result<Arc<[NonTextInput]>, Vec<CaptureError>> {
    let mut sources = BTreeMap::<Arc<PathBuf>, Arc<str>>::new();
    let mut inputs = Vec::new();
    let mut errors = Vec::new();
    for item in &frontend.plan.items {
        let OrderedItem::NonText { occurrence, kind } = *item else {
            continue;
        };
        let path = frontend.plan.occurrences[occurrence].path.clone();
        let include_occurrence = match u32::try_from(occurrence) {
            Ok(value) => value,
            Err(_) => {
                errors.push(CaptureError {
                    path,
                    include_occurrence: occurrence,
                    message: "too many non-text include occurrences".into(),
                });
                continue;
            }
        };
        let source = if let Some(source) = sources.get(&path) {
            Arc::clone(source)
        } else {
            match provider.read(&path) {
                Ok(source) => {
                    let source: Arc<str> = Arc::from(source);
                    sources.insert(path.clone(), source.clone());
                    source
                }
                Err(message) => {
                    errors.push(CaptureError {
                        path,
                        include_occurrence: occurrence,
                        message,
                    });
                    continue;
                }
            }
        };
        inputs.push(match kind {
            NonTextKind::Map => NonTextInput::Map(CapturedMap {
                path,
                include_occurrence,
                source,
            }),
            NonTextKind::Skin => {
                let source_identity = xxhash_rust::xxh3::xxh3_128(source.as_bytes());
                NonTextInput::Skin(CapturedSkin {
                    path,
                    include_occurrence,
                    source,
                    source_identity,
                })
            }
        });
    }
    if errors.is_empty() {
        Ok(inputs.into())
    } else {
        Err(errors)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::path::Path;
    struct Memory {
        inputs: BTreeMap<PathBuf, String>,
        reads: RefCell<BTreeMap<PathBuf, usize>>,
    }
    impl SourceProvider for Memory {
        fn read(&self, path: &Path) -> Result<String, String> {
            *self.reads.borrow_mut().entry(path.into()).or_default() += 1;
            self.inputs
                .get(path)
                .cloned()
                .ok_or_else(|| "missing captured input".into())
        }
    }
    #[test]
    fn map_skin_capture_preserves_joint_occurrences_and_shares_repeated_bytes() {
        let memory = Memory {
            inputs: [
                (
                    PathBuf::from("project.dme"),
                    "#include \"world.dmm\"\n#include \"interface.dmf\"\n#include \"world.dmm\"\n"
                        .into(),
                ),
                (
                    PathBuf::from("world.dmm"),
                    "\"a\"=(/turf,/area)\n(1,1,1)={\"a\"}".into(),
                ),
                (PathBuf::from("interface.dmf"), "window \"main\"\n".into()),
            ]
            .into(),
            reads: RefCell::default(),
        };
        let frontend =
            crate::frontend::build(Path::new("project.dme"), &memory, &BTreeMap::new(), 1).unwrap();
        assert_eq!(memory.reads.borrow().get(Path::new("world.dmm")), None);
        let inputs = capture(&frontend, &memory).unwrap();
        assert_eq!(inputs.len(), 3);
        let NonTextInput::Map(first) = &inputs[0] else {
            panic!("first include is not map")
        };
        let NonTextInput::Skin(skin) = &inputs[1] else {
            panic!("second include is not skin")
        };
        let NonTextInput::Map(last) = &inputs[2] else {
            panic!("third include is not map")
        };
        assert_ne!(first.include_occurrence, last.include_occurrence);
        assert!(Arc::ptr_eq(&first.source, &last.source));
        assert_eq!(memory.reads.borrow().get(Path::new("world.dmm")), Some(&1));
        assert_eq!(
            skin.source_identity,
            xxhash_rust::xxh3::xxh3_128(skin.source.as_bytes())
        );
        assert_eq!(
            crate::maps::plan(first.clone())
                .unwrap()
                .model
                .templates
                .len(),
            1
        );
    }
}
