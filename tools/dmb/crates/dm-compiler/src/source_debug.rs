//! Maps current expanded spans to authored locations after symbolic cache reuse.
//! This index never enters semantic lowering identity or a portable memo.
use dm_preprocess::{Origin, PreprocessedProject};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub(crate) struct SourceDebugIndex<'a> {
    line_starts: Vec<usize>,
    origins: std::borrow::Cow<'a, [Origin]>,
    origin_map: Option<&'a dm_preprocess::OriginMap>,
    files: HashMap<&'a Path, String>,
    source_len: usize,
    segmented: Option<dm_syntax::SegmentedSource>,
    project_root: PathBuf,
    directory: PathBuf,
}
impl<'a> SourceDebugIndex<'a> {
    pub fn new(project: &'a PreprocessedProject, project_root: &Path) -> Self {
        let mut line_starts = vec![0];
        line_starts.extend(
            project
                .text
                .bytes()
                .enumerate()
                .filter_map(|(at, byte)| (byte == b'\n').then_some(at + 1)),
        );
        let mut origins: Vec<_> = project.origin_iter().collect();
        origins.sort_by_key(|origin| origin.output_line);
        let directory = std::env::current_dir().unwrap_or_default();
        let project_root = absolute_lexical(project_root, &directory);
        let mut files = HashMap::new();
        // Normalize each unique file once, using the same lexical policy on both
        // sides. Files need not exist and Windows canonicalization cannot add a
        // verbatim prefix to just one side of the comparison.
        for origin in &project.origins {
            files.entry(origin.path.as_path()).or_insert_with(|| {
                let path = absolute_lexical(&origin.path, &directory);
                path.strip_prefix(&project_root)
                    .unwrap_or(&path)
                    .to_string_lossy()
                    .replace('\\', "/")
            });
        }
        Self {
            line_starts,
            origins: std::borrow::Cow::Owned(origins),
            origin_map: None,
            files,
            source_len: project.text.len(),
            segmented: None,
            project_root,
            directory,
        }
    }
    pub fn new_segmented(project: &'a PreprocessedProject, project_root: &Path, source: &dm_syntax::SegmentedSource) -> Self {
        // Build only origin/file metadata; avoid scanning or allocating a global
        // expanded line-start vector. Shared piece indexes resolve current spans.
        let directory = std::env::current_dir().unwrap_or_default();
        let project_root = absolute_lexical(project_root, &directory);
        let origins = std::borrow::Cow::Borrowed(project.origins.as_slice());
        let mut files = HashMap::new();
        for authored in project.dependencies.iter().chain(project.units.iter().map(|unit| &unit.path)) {
            files.entry(authored.as_path()).or_insert_with(|| {
                let path = absolute_lexical(authored, &directory);
                path.strip_prefix(&project_root).unwrap_or(&path).to_string_lossy().replace('\\', "/")
            });
        }
        Self { line_starts: Vec::new(), origins, origin_map: project.origin_map.as_deref(), files, source_len: source.len(), segmented: Some(source.clone()), project_root, directory }
    }
    pub fn resolve(&self, offset: usize) -> Option<(String, u32)> {
        if offset >= self.source_len {
            return None;
        }
        let line = self.segmented.as_ref().and_then(|source| source.line_number(offset))
            .unwrap_or_else(|| self.line_starts.partition_point(|start| *start <= offset));
        let origin = if let Some(map) = self.origin_map {
            map.at_line(line)?
        } else {
            let index=self.origins.partition_point(|origin|origin.output_line<=line).checked_sub(1)?;
            let origin=self.origins.get(index)?;
            if origin.output_line!=line {return None;}
            origin.clone()
        };
        // A macro expansion may produce several output lines from one authored
        // line. The producer's exact origin wins; adding an output delta is false.
        let file = self.files.get(origin.path.as_path()).cloned().unwrap_or_else(|| {
            let path = absolute_lexical(&origin.path, &self.directory);
            path.strip_prefix(&self.project_root).unwrap_or(&path).to_string_lossy().replace('\\', "/")
        });
        Some((file, u32::try_from(origin.source_line).ok()?))
    }
}

/// The existing output witness records authored debug observations, separately
/// from dense string IDs. Expanded offsets only select current observations;
/// shifting an unchanged procedure in the expansion does not change identity.
pub(crate) fn authored_debug_identity(
    index: Option<&SourceDebugIndex<'_>>, header: usize, body_base: usize,
    resolved: impl IntoIterator<Item=usize>, unresolved: impl IntoIterator<Item=usize>,
) -> String {
    use sha2::{Digest,Sha256};
    let mut hash=Sha256::new();
    hash.update(b"dm-authored-debug-observations-v1\0");
    let Some(index)=index else {
        hash.update([0]);
        return format!("{:x}",hash.finalize());
    };
    hash.update([1]);
    fn origin(hash:&mut Sha256,index:&SourceDebugIndex<'_>,offset:Option<usize>) {
        match offset.and_then(|offset|index.resolve(offset)) {
            Some((file,line))=>{
                hash.update([1]);hash.update((file.len() as u64).to_le_bytes());
                hash.update(file.as_bytes());hash.update(line.to_le_bytes());
            }
            None=>hash.update([0]),
        }
    }
    hash.update([0]);origin(&mut hash,index,Some(header));
    let mut count=0u64;
    for relative in resolved {
        hash.update([1]);hash.update((relative as u64).to_le_bytes());
        origin(&mut hash,index,body_base.checked_add(relative));count+=1;
    }
    hash.update([2]);hash.update(count.to_le_bytes());count=0;
    for relative in unresolved {
        hash.update([3]);hash.update((relative as u64).to_le_bytes());
        origin(&mut hash,index,body_base.checked_add(relative));count+=1;
    }
    hash.update([4]);hash.update(count.to_le_bytes());
    format!("{:x}",hash.finalize())
}

fn absolute_lexical(path: &Path, directory: &Path) -> PathBuf {
    let absolute = if path.is_absolute() {
        path.to_owned()
    } else {
        directory.join(path)
    };
    let mut output = PathBuf::new();
    for component in absolute.components() {
        match component {
            std::path::Component::CurDir => {}
            std::path::Component::ParentDir => {
                if output.file_name().is_some() {
                    output.pop();
                }
            }
            _ => output.push(component.as_os_str()),
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn relative_origin_and_relative_project_use_the_same_lexical_namespace() {
        let project = PreprocessedProject {
            text: "statement\n".into(),
            origins: vec![Origin {
                output_line: 1,
                path: PathBuf::from("project/code/../code/test.dm").into(),
                source_line: 7,
            }],
            ..Default::default()
        };
        let index = SourceDebugIndex::new(&project, Path::new("project/./nested/.."));
        assert_eq!(index.resolve(0), Some(("code/test.dm".into(), 7)));
    }
    #[test]
    fn inserted_source_and_macro_lines_use_current_authored_origins() {
        let owned_root = std::env::current_dir().unwrap().join("project");
        let root = owned_root.as_path();
        let project = PreprocessedProject {
            text: "first\nmacro-a\nmacro-b\nlast\n".into(),
            origins: vec![
                Origin {
                    output_line: 1,
                    path: root.join("code/a.dm").into(),
                    source_line: 4,
                },
                Origin {
                    output_line: 2,
                    path: root.join("code/a.dm").into(),
                    source_line: 8,
                },
                Origin {
                    output_line: 3,
                    path: root.join("code/a.dm").into(),
                    source_line: 8,
                },
                Origin {
                    output_line: 4,
                    path: root.join("code/b.dm").into(),
                    source_line: 17,
                },
            ],
            ..Default::default()
        };
        let index = SourceDebugIndex::new(&project, root);
        assert_eq!(index.resolve(0), Some(("code/a.dm".into(), 4)));
        assert_eq!(index.resolve(14), Some(("code/a.dm".into(), 8)));
        assert_eq!(index.resolve(22), Some(("code/b.dm".into(), 17)));
        assert_eq!(index.resolve(project.text.len()), None);
        let sparse = PreprocessedProject {
            text: "first\nsecond\n".into(),
            origins: vec![Origin {
                output_line: 1,
                path: root.join("code/a.dm").into(),
                source_line: 4,
            }],
            ..Default::default()
        };
        assert_eq!(SourceDebugIndex::new(&sparse, root).resolve(6), None);
    }
}
