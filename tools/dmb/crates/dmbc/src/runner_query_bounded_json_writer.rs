//! Operation-local body-model wire helpers. No syntax/model/cache ownership.
use std::io::{self, Write};
#[derive(Default)]
struct Failure(Option<io::Error>);
impl Failure {
    fn require(&self) -> io::Result<()> {
        if self.0.is_some() {
            Err(io::Error::other("bounded JSON writer stopped"))
        } else {
            Ok(())
        }
    }
    fn fail<T>(&mut self, error: io::Error) -> io::Result<T> {
        if self.0.is_none() {
            self.0 = Some(error);
        }
        Err(io::Error::other("bounded JSON writer stopped"))
    }
    fn restore<T>(&mut self, result: io::Result<T>) -> io::Result<T> {
        self.0.take().map_or(result, Err)
    }
}
pub(super) struct Bounded {
    pub(super) bytes: Vec<u8>,
    limit: usize,
    label: &'static str,
    failure: Failure,
}
impl Bounded {
    pub(super) fn new(limit: usize, label: &'static str) -> Self {
        Self {
            bytes: Vec::new(),
            limit,
            label,
            failure: Failure::default(),
        }
    }
    pub(super) fn restore<T>(&mut self, result: io::Result<T>) -> io::Result<T> {
        self.failure.restore(result)
    }
}
impl Write for Bounded {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        self.failure.require()?;
        if let Err(error) = crate::daemon::control::checkpoint() {
            return self.failure.fail(error);
        }
        if b.len() > self.limit.saturating_sub(self.bytes.len()) {
            return self.failure.fail(io::Error::other(self.label));
        }
        self.bytes.extend_from_slice(b);
        Ok(b.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        self.failure.require()
    }
}
struct Forward<'a, W: Write> {
    output: &'a mut W,
    failure: Failure,
}
impl<W: Write> Write for Forward<'_, W> {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        self.failure.require()?;
        if let Err(error) = crate::daemon::control::checkpoint() {
            return self.failure.fail(error);
        }
        match self.output.write(b) {
            Ok(n) => Ok(n),
            Err(error) => self.failure.fail(error),
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        self.failure.require()?;
        match self.output.flush() {
            Ok(()) => Ok(()),
            Err(error) => self.failure.fail(error),
        }
    }
}
fn json_error(e: serde_json::Error) -> io::Error {
    io::Error::new(e.io_error_kind().unwrap_or(io::ErrorKind::InvalidData), e)
}
pub(super) fn write_json_line(
    value: &impl serde::Serialize,
    output: &mut impl Write,
) -> io::Result<()> {
    let mut forward = Forward {
        output,
        failure: Failure::default(),
    };
    let encoded = serde_json::to_writer(&mut forward, value).map_err(json_error);
    forward.failure.restore(encoded)?;
    let newline = forward.write_all(b"\n");
    forward.failure.restore(newline)?;
    crate::daemon::control::checkpoint()
}
#[cfg(test)]
mod tests {
    use super::*;
    use serde::{ser::SerializeMap, Serialize, Serializer};
    struct CancelAfterPrefix {
        token: crate::daemon::control::Cancellation,
    }
    impl Serialize for CancelAfterPrefix {
        fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
            let mut map = s.serialize_map(Some(2))?;
            map.serialize_entry("prefix", "written")?;
            self.token.cancel();
            map.serialize_entry("after", &1)?;
            map.end()
        }
    }
    #[test]
    fn body_model_mid_json_cancellation_unwinds_before_exposing_local_bytes() {
        let token = crate::daemon::control::Cancellation::default();
        let bound = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(60),
        );
        let mut wire = Bounded::new(192 * 1024, "body model query exceeds output budget");
        let encoded =
            serde_json::to_writer(&mut wire, &CancelAfterPrefix { token }).map_err(json_error);
        assert!(!wire.bytes.is_empty());
        let error = wire.restore(encoded).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert!(!wire.bytes.ends_with(b"\n"));
        drop(bound);
    }
    #[test]
    fn body_model_final_writer_interrupted_is_not_retried_and_json_bytes_stay_identical() {
        struct Refuse {
            calls: usize,
        }
        impl Write for Refuse {
            fn write(&mut self, _: &[u8]) -> io::Result<usize> {
                self.calls += 1;
                Err(io::Error::new(
                    io::ErrorKind::Interrupted,
                    "actual body-model output refusal",
                ))
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let mut out = Refuse { calls: 0 };
        let row = serde_json::json!({"row":"source_body_model","typed_jsonl":"x\n","lexical_jsonl":"y\n"});
        let error = write_json_line(&row, &mut out).unwrap_err();
        assert_eq!(out.calls, 1);
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert_eq!(error.to_string(), "actual body-model output refusal");
        let mut okay = Vec::new();
        write_json_line(&row, &mut okay).unwrap();
        assert_eq!(
            okay,
            [serde_json::to_vec(&row).unwrap(), b"\n".to_vec()].concat()
        );
        let mut tiny = Bounded::new(1, "body model query exceeds output budget");
        let denied = serde_json::to_writer(&mut tiny, &row).map_err(json_error);
        assert!(tiny.restore(denied).is_err());
    }
}

#[cfg(test)]
mod partial_tests {
    use super::*;
    #[test]
    fn query_wire_partial_emission_cancel_returns_interrupted_without_completed_success() {
        struct Partial {
            token: crate::daemon::control::Cancellation,
            bytes: Vec<u8>,
            calls: usize,
        }
        impl Write for Partial {
            fn write(&mut self, b: &[u8]) -> io::Result<usize> {
                self.calls += 1;
                self.bytes.push(b[0]);
                self.token.cancel();
                Ok(1)
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        let token = crate::daemon::control::Cancellation::default();
        let bound = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(60),
        );
        let mut out = Partial {
            token,
            bytes: Vec::new(),
            calls: 0,
        };
        let error =
            write_json_line(&serde_json::json!({"row":"source_body_model"}), &mut out).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert_eq!(out.calls, 1);
        assert_eq!(out.bytes.len(), 1);
        assert!(!out.bytes.ends_with(b"\n"));
        drop(bound);
    }
}
