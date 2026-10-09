//! Optional lossless compression; raw traces retain their existing writer path.
use flate2::{write::GzEncoder, Compression};
use serde::Serialize;
use std::{
    fs::File,
    io::{self, Write},
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};
use xxhash_rust::xxh3::Xxh3;

#[derive(Clone, Debug, Serialize)]
pub struct Artifact {
    pub path: PathBuf,
    pub logical_format: &'static str,
    pub stored_bytes: u64,
    pub uncompressed_bytes: u64,
    pub stored_xxh3_128: String,
    pub uncompressed_xxh3_128: String,
}
#[derive(Clone, Debug, Serialize)]
pub struct Metadata {
    pub mode: &'static str,
    pub artifacts: Vec<Artifact>,
}
struct HashedFile {
    file: File,
    hash: Xxh3,
    bytes: u64,
}
impl Write for HashedFile {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        let count = self.file.write(bytes)?;
        self.hash.update(&bytes[..count]);
        self.bytes += count as u64;
        Ok(count)
    }
    fn flush(&mut self) -> io::Result<()> {
        self.file.flush()
    }
}
struct Compressed {
    encoder: Option<GzEncoder<HashedFile>>,
    hash: Xxh3,
    bytes: u64,
    failure: Option<String>,
}
#[derive(Clone)]
pub(crate) struct Stream(Arc<Mutex<Compressed>>);
impl Write for Stream {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        let mut inner = self
            .0
            .lock()
            .map_err(|_| io::Error::other("compressed trace lock poisoned"))?;
        let result = inner
            .encoder
            .as_mut()
            .ok_or_else(|| io::Error::other("compressed trace already finalized"))?
            .write(bytes);
        match result {
            Ok(count) => {
                inner.hash.update(&bytes[..count]);
                inner.bytes += count as u64;
                Ok(count)
            }
            Err(error) => {
                inner.failure = Some(error.to_string());
                Err(error)
            }
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        let mut inner = self
            .0
            .lock()
            .map_err(|_| io::Error::other("compressed trace lock poisoned"))?;
        let Some(encoder) = inner.encoder.as_mut() else {
            return Ok(());
        };
        let result = encoder.flush();
        if let Err(error) = &result {
            inner.failure = Some(error.to_string());
        }
        result
    }
}
pub(crate) enum TraceWriter {
    Raw(File),
    Gzip(Stream),
}
impl Write for TraceWriter {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        match self {
            Self::Raw(file) => file.write(bytes),
            Self::Gzip(stream) => stream.write(bytes),
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        match self {
            Self::Raw(file) => file.flush(),
            Self::Gzip(stream) => stream.flush(),
        }
    }
}
struct Finalizer {
    stream: Stream,
    path: PathBuf,
    format: &'static str,
}
pub(crate) struct Outputs {
    gzip: bool,
    finalizers: Vec<Finalizer>,
}
impl Outputs {
    pub(crate) fn from_environment() -> io::Result<Self> {
        let mode = std::env::var("DMB_TRACE_COMPRESSION").unwrap_or_else(|_| "raw".into());
        Self::new(&mode)
    }
    fn new(mode: &str) -> io::Result<Self> {
        match mode {
            "raw" => Ok(Self {
                gzip: false,
                finalizers: Vec::new(),
            }),
            "gzip" => Ok(Self {
                gzip: true,
                finalizers: Vec::new(),
            }),
            _ => Err(io::Error::other(
                "DMB_TRACE_COMPRESSION must be raw or gzip",
            )),
        }
    }
    pub(crate) fn writer(&mut self, path: &Path, format: &'static str) -> io::Result<TraceWriter> {
        if !self.gzip {
            return Ok(TraceWriter::Raw(File::create(path)?));
        }
        let mut name = path.as_os_str().to_os_string();
        name.push(".gz");
        let path = PathBuf::from(name);
        let encoder = GzEncoder::new(
            HashedFile {
                file: File::create(&path)?,
                hash: Xxh3::new(),
                bytes: 0,
            },
            Compression::new(1),
        );
        let stream = Stream(Arc::new(Mutex::new(Compressed {
            encoder: Some(encoder),
            hash: Xxh3::new(),
            bytes: 0,
            failure: None,
        })));
        self.finalizers.push(Finalizer {
            stream: stream.clone(),
            path,
            format,
        });
        Ok(TraceWriter::Gzip(stream))
    }
    pub(crate) fn finish(&mut self) -> io::Result<Metadata> {
        let mut artifacts = Vec::new();
        let mut failure = None;
        for finalizer in self.finalizers.drain(..) {
            let result = (|| {
                let mut inner = finalizer
                    .stream
                    .0
                    .lock()
                    .map_err(|_| io::Error::other("compressed trace lock poisoned"))?;
                let mut output = inner
                    .encoder
                    .take()
                    .ok_or_else(|| io::Error::other("compressed trace finalized twice"))?
                    .finish()?;
                output.flush()?;
                if let Some(error) = &inner.failure {
                    return Err(io::Error::other(error.clone()));
                }
                Ok(Artifact {
                    path: finalizer.path,
                    logical_format: finalizer.format,
                    stored_bytes: output.bytes,
                    uncompressed_bytes: inner.bytes,
                    stored_xxh3_128: format!("{:032x}", output.hash.digest128()),
                    uncompressed_xxh3_128: format!("{:032x}", inner.hash.digest128()),
                })
            })();
            match result {
                Ok(artifact) => artifacts.push(artifact),
                Err(error) => {
                    if failure.is_none() {
                        failure = Some(error);
                    }
                }
            }
        }
        if let Some(error) = failure {
            return Err(error);
        }
        Ok(Metadata {
            mode: if self.gzip { "gzip-level1-v1" } else { "raw" },
            artifacts,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    #[test]
    fn gzip_finalization_preserves_every_byte_and_certifies_both_encodings() {
        let path =
            std::env::temp_dir().join(format!("dm-profile-gzip-{}.json", std::process::id()));
        let mut outputs = Outputs::new("gzip").unwrap();
        let mut writer = outputs.writer(&path, "chrome-json").unwrap();
        let bytes = b"{\"events\":[1,2,3]}\n";
        writer.write_all(bytes).unwrap();
        writer.flush().unwrap();
        let metadata = outputs.finish().unwrap();
        let artifact = &metadata.artifacts[0];
        let stored = std::fs::read(&artifact.path).unwrap();
        let mut decoded = Vec::new();
        flate2::read::GzDecoder::new(stored.as_slice())
            .read_to_end(&mut decoded)
            .unwrap();
        assert_eq!(decoded, bytes);
        assert_eq!(artifact.stored_bytes, stored.len() as u64);
        assert_eq!(artifact.uncompressed_bytes, bytes.len() as u64);
        assert_eq!(
            artifact.uncompressed_xxh3_128,
            format!("{:032x}", xxhash_rust::xxh3::xxh3_128(bytes))
        );
        assert_eq!(
            artifact.stored_xxh3_128,
            format!("{:032x}", xxhash_rust::xxh3::xxh3_128(&stored))
        );
        assert!(writer.write_all(b"late event").is_err());
        drop(writer);
        std::fs::remove_file(&artifact.path).unwrap();
    }
    #[test]
    fn asynchronous_writer_failure_is_reported_at_finalization() {
        let path = std::env::temp_dir().join(format!(
            "dm-profile-gzip-failure-{}.json",
            std::process::id()
        ));
        let mut outputs = Outputs::new("gzip").unwrap();
        let mut writer = outputs.writer(&path, "chrome-json").unwrap();
        writer.write_all(b"partial trace").unwrap();
        if let TraceWriter::Gzip(stream) = &writer {
            stream.0.lock().unwrap().failure = Some("injected async writer failure".into());
        }
        assert!(outputs
            .finish()
            .unwrap_err()
            .to_string()
            .contains("injected async writer failure"));
        drop(writer);
        let mut compressed = path.as_os_str().to_os_string();
        compressed.push(".gz");
        std::fs::remove_file(PathBuf::from(compressed)).unwrap();
    }
    #[test]
    fn unknown_compression_mode_is_not_silently_accepted() {
        assert!(Outputs::new("lossy").is_err());
    }
    #[test]
    fn raw_writer_retains_original_path_and_bytes() {
        let path = std::env::temp_dir().join(format!("dm-profile-raw-{}.json", std::process::id()));
        let mut outputs = Outputs::new("raw").unwrap();
        let mut writer = outputs.writer(&path, "chrome-json").unwrap();
        writer.write_all(b"original").unwrap();
        writer.flush().unwrap();
        drop(writer);
        assert_eq!(std::fs::read(&path).unwrap(), b"original");
        assert!(outputs.finish().unwrap().artifacts.is_empty());
        std::fs::remove_file(path).unwrap();
    }
}
