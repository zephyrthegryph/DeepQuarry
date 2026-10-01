//! Local prototype daemon. The transport is intentionally small; compiler
//! sessions and the CAS live in the library so IPC can change independently.

use dm_compiled::{default_cache_root, Request};
use std::env;
use std::io::{BufRead, BufReader, Read};
use std::net::{Ipv4Addr, SocketAddrV4, TcpListener};
use std::path::PathBuf;
use std::time::Duration;

mod parallel;

const MAX_REQUEST_BYTES: u64 = 32 * 1024 * 1024;

fn read_request(reader: impl Read) -> Result<Request, String> {
    let mut line = String::new();
    BufReader::new(reader)
        .take(MAX_REQUEST_BYTES + 1)
        .read_line(&mut line)
        .map_err(|error| error.to_string())?;
    if line.len() as u64 > MAX_REQUEST_BYTES {
        return Err("daemon request exceeds 32 MiB limit".into());
    }
    serde_json::from_str(&line).map_err(|error| error.to_string())
}

fn main() {
    if let Err(error) = dm_host::run_on_compiler_thread(|| run().map_err(|error| error.to_string()))
    {
        eprintln!("dm-compiled: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let _process_budget = dm_host::install_process_budget()?;
    let mut args = env::args().skip(1);
    let port: u16 = args.next().unwrap_or_else(|| "47616".into()).parse()?;
    let cache = args.next().map(PathBuf::from).unwrap_or_else(|| {
        default_cache_root(&env::current_dir().unwrap_or_else(|_| PathBuf::from(".")))
    });
    if args.next().is_some() {
        return Err("usage: dm-compiled [PORT [CACHE_DIRECTORY]]".into());
    }
    let listener = TcpListener::bind(SocketAddrV4::new(Ipv4Addr::LOCALHOST, port))?;
    let workers = parallel::worker_count(env::var("DM_DAEMON_WORKERS").ok().as_deref())?;
    let mut pool = parallel::WorkerPool::new(cache, workers)?;
    eprintln!("dm-compiled listening on {port} with {workers} compiler workers");
    for incoming in listener.incoming() {
        let mut stream = match incoming {
            Ok(stream) => stream,
            Err(error) => {
                eprintln!("dm-compiled connection error: {error}");
                continue;
            }
        };
        stream.set_read_timeout(Some(Duration::from_secs(15)))?;
        stream.set_write_timeout(Some(Duration::from_secs(15)))?;
        match read_request(stream.try_clone()?) {
            Ok(Request::Ping) => parallel::write_response(&mut stream, &parallel::response(None)),
            Ok(request) => {
                if let Err((mut job, error)) = pool.submit(parallel::Job { stream, request }) {
                    parallel::write_response(&mut job.stream, &parallel::response(Some(error)));
                }
            }
            Err(error) => parallel::write_response(&mut stream, &parallel::response(Some(error))),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn malformed_request_does_not_poison_next_request() {
        assert!(read_request(&b"{bad}\n"[..]).is_err());
        let bytes = serde_json::to_vec(&Request::Ping).unwrap();
        assert!(matches!(read_request(bytes.as_slice()), Ok(Request::Ping)));
    }
}
