//! Machine output authority is the successful typed publication outcome.
//! Runtime acquisition delegates to the existing authenticated writable-copy core.
use crate::publish::{OutputPair, PairStore};
use crate::request::{BuildOutcome, CommandOutcome};
use serde::Serialize;
use std::fs::OpenOptions;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

#[derive(Serialize)]
struct CompileReceipt<'a> {
    schema_version: u32,
    kind: &'static str,
    store: &'a Path,
    pair_id: String,
    dmb_bytes: u64,
    rsc_bytes: u64,
    dmb_hash: String,
    rsc_hash: String,
    output_project: &'a Path,
}
#[derive(Serialize)]
struct AcquiredReceipt<'a> {
    schema_version: u32,
    kind: &'static str,
    store: &'a Path,
    pair_id: String,
    dmb_bytes: u64,
    rsc_bytes: u64,
    dmb_hash: String,
    rsc_hash: String,
    slot: &'a Path,
    dmb: PathBuf,
    rsc: PathBuf,
}
fn absolute(path: &Path) -> io::Result<PathBuf> {
    if path.is_absolute() {
        Ok(path.to_owned())
    } else {
        Ok(std::env::current_dir()?.join(path))
    }
}
fn write_unique(path: &Path, value: &impl Serialize) -> io::Result<()> {
    let path = absolute(path)?;
    // Serialize before creating the file; existing receipts are never overwritten.
    let bytes = serde_json::to_vec(value).map_err(io::Error::other)?;
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)?;
    let written = output
        .write_all(&bytes)
        .and_then(|()| output.write_all(b"\n"))
        .and_then(|()| output.sync_all());
    drop(output);
    if written.is_err() {
        let _ = std::fs::remove_file(path);
    }
    written
}
fn check_lengths(pair: &OutputPair) -> io::Result<()> {
    // The build launcher reads lengths as JavaScript numbers. Refuse values
    // which that contract cannot represent exactly rather than rounding them.
    const MAX_EXACT_JSON_NUMBER: u64 = (1 << 53) - 1;
    if pair.dmb_bytes > MAX_EXACT_JSON_NUMBER || pair.rsc_bytes > MAX_EXACT_JSON_NUMBER {
        return Err(io::Error::other(
            "output length exceeds the machine receipt's exact numeric range",
        ));
    }
    Ok(())
}
pub fn write_compile(path: &Path, outcome: &BuildOutcome) -> io::Result<()> {
    let BuildOutcome::Published {
        pair,
        output_project,
        store,
        ..
    } = outcome
    else {
        return Err(io::Error::other(
            "a compile receipt requires successful publication",
        ));
    };
    check_lengths(pair)?;
    write_unique(
        path,
        &CompileReceipt {
            schema_version: 1,
            kind: "native_pair",
            store,
            pair_id: pair.name(),
            dmb_bytes: pair.dmb_bytes,
            rsc_bytes: pair.rsc_bytes,
            dmb_hash: format!("{:032x}", pair.dmb_hash),
            rsc_hash: format!("{:032x}", pair.rsc_hash),
            output_project,
        },
    )
}
pub fn finish_command(
    path: Option<&Path>,
    outcome: CommandOutcome,
) -> Result<CommandOutcome, Box<dyn std::error::Error>> {
    if let Some(path) = path {
        let CommandOutcome::Build(build) = &outcome else {
            return Err("a compile receipt requires a compile command".into());
        };
        write_compile(path, build)?;
    }
    Ok(outcome)
}
/// Keep this client-owned path out of daemon requests and session identities.
pub fn extract_compile_result(
    arguments: &mut Vec<String>,
) -> Result<Option<PathBuf>, Box<dyn std::error::Error>> {
    let mut result = None;
    let mut index = 0;
    while index < arguments.len() {
        if arguments[index] != "--compile-result-file" {
            index += 1;
            continue;
        }
        if result.is_some() {
            return Err("--compile-result-file accepts one file".into());
        }
        if index + 1 >= arguments.len() {
            return Err("--compile-result-file requires a file".into());
        }
        arguments.remove(index);
        result = Some(absolute(Path::new(&arguments.remove(index)))?);
    }
    if result.is_some() && arguments.first().map(String::as_str) != Some("compile") {
        return Err("--compile-result-file is only valid for compile".into());
    }
    Ok(result)
}
pub fn acquire(arguments: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    let mut args = arguments.iter().skip(1);
    let (mut store, mut pair, mut slots, mut result) = (None, None, None, None);
    let mut exact = false;
    while let Some(option) = args.next() {
        if option == "--exact-inputs" {
            if exact {
                return Err("duplicate --exact-inputs".into());
            }
            exact = true;
            continue;
        }
        let destination = match option.as_str() {
            "--output-store" => &mut store,
            "--pair-id" => &mut pair,
            "--slots" => &mut slots,
            "--result-file" => &mut result,
            _ => return Err(format!("unknown acquisition option {option}").into()),
        };
        if destination
            .replace(
                args.next()
                    .ok_or("acquisition option requires a value")?
                    .clone(),
            )
            .is_some()
        {
            return Err(format!("duplicate acquisition option {option}").into());
        }
    }
    let pair = pair.ok_or("--pair-id is required")?;
    if pair.len() != 32
        || !pair
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err("--pair-id requires exactly 32 lowercase hexadecimal digits".into());
    }
    let id = u128::from_str_radix(&pair, 16)?;
    let root = std::fs::canonicalize(store.ok_or("--output-store is required")?)?;
    let slots = absolute(Path::new(&slots.ok_or("--slots is required")?))?;
    let result = absolute(Path::new(&result.ok_or("--result-file is required")?))?;
    let store = PairStore::open(&root)?;
    let identity: OutputPair = store.verify(id, exact)?;
    check_lengths(&identity)?;
    let slot = store.acquire(id, &slots)?;
    let receipt = AcquiredReceipt {
        schema_version: 1,
        kind: "acquired_pair",
        store: &root,
        pair_id: identity.name(),
        dmb_bytes: identity.dmb_bytes,
        rsc_bytes: identity.rsc_bytes,
        dmb_hash: format!("{:032x}", identity.dmb_hash),
        rsc_hash: format!("{:032x}", identity.rsc_hash),
        slot: &slot,
        dmb: slot.join("deepquarry.dmb"),
        rsc: slot.join("deepquarry.rsc"),
    };
    if let Err(error) = write_unique(&result, &receipt) {
        // Only this freshly created slot is removed; no store generation is touched.
        let _ = std::fs::remove_dir_all(&slot);
        return Err(error.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn result_path_is_client_only_and_duplicates_or_analysis_are_rejected() {
        let mut args = vec![
            "compile",
            "project.dme",
            "--compile-result-file",
            "result.json",
        ]
        .into_iter()
        .map(String::from)
        .collect();
        assert!(extract_compile_result(&mut args)
            .unwrap()
            .unwrap()
            .is_absolute());
        assert_eq!(args, ["compile", "project.dme"]);
        for input in [
            vec!["analyze", "--compile-result-file", "x"],
            vec!["compile", "--compile-result-file"],
            vec![
                "compile",
                "--compile-result-file",
                "x",
                "--compile-result-file",
                "y",
            ],
        ] {
            let mut args = input.into_iter().map(String::from).collect();
            assert!(extract_compile_result(&mut args).is_err());
        }
    }
    #[test]
    fn compile_receipt_uses_exact_hex_strings_and_refuses_overwriting() {
        let base = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmb-native-v2/contract-tests")
        } else {
            std::env::temp_dir()
        };
        std::fs::create_dir_all(&base).unwrap();
        let root = base.join(format!(
            "dmbc-receipt-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&root).unwrap();
        let path = root.join("result.json");
        let pair = OutputPair::from_bytes(b"dmb", b"rsc");
        let outcome = BuildOutcome::Published {
            pair: pair.clone(),
            store: root.clone(),
            output_project: root.join("project.dme"),
            session_hit: false,
            seconds: 1.0,
        };
        write_compile(&path, &outcome).unwrap();
        let first = std::fs::read(&path).unwrap();
        let json: serde_json::Value = serde_json::from_slice(&first).unwrap();
        assert_eq!(json["pair_id"], pair.name());
        assert_eq!(json["dmb_hash"], format!("{:032x}", pair.dmb_hash));
        assert!(write_compile(&path, &outcome).is_err());
        assert_eq!(std::fs::read(&path).unwrap(), first);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn acquire_returns_independent_writable_copies_and_preserves_generation_on_failure() {
        let base = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmb-native-v2/contract-tests")
        } else {
            std::env::temp_dir()
        };
        std::fs::create_dir_all(&base).unwrap();
        let root = base.join(format!(
            "acquire-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir(&root).unwrap();
        let store = PairStore::open(root.join("store")).unwrap();
        let pair = store.publish(1, b"original dmb", b"original rsc").unwrap();
        let slots = root.join("slots");
        let result = root.join("result.json");
        let arguments = vec![
            "acquire".into(),
            "--output-store".into(),
            store.root_path().to_string_lossy().into_owned(),
            "--pair-id".into(),
            pair.name(),
            "--slots".into(),
            slots.to_string_lossy().into_owned(),
            "--result-file".into(),
            result.to_string_lossy().into_owned(),
        ];
        acquire(&arguments).unwrap();
        let receipt: serde_json::Value =
            serde_json::from_slice(&std::fs::read(&result).unwrap()).unwrap();
        assert_eq!(receipt["pair_id"], pair.name());
        let dmb = PathBuf::from(receipt["dmb"].as_str().unwrap());
        std::fs::write(&dmb, b"runtime mutation").unwrap();
        assert_eq!(store.verify(pair.id, false).unwrap(), pair);
        assert_eq!(std::fs::read_dir(&slots).unwrap().count(), 1);
        // A pre-existing receipt rejects the next acquisition and removes only
        // its newly made copy, keeping the first runtime slot and generation.
        assert!(acquire(&arguments).is_err());
        assert_eq!(std::fs::read_dir(&slots).unwrap().count(), 1);
        assert_eq!(std::fs::read(&dmb).unwrap(), b"runtime mutation");
        assert_eq!(store.verify(pair.id, false).unwrap(), pair);
        drop(store);
        std::fs::remove_dir_all(root).unwrap();
    }
}
