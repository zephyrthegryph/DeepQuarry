//! Compatibility launcher; the compiler executable itself certifies version identity.
fn main() {
    let result = (|| -> std::io::Result<std::process::ExitStatus> {
        let compiler = std::env::current_exe()?.with_file_name(if cfg!(windows) {
            "dmbc.exe"
        } else {
            "dmbc"
        });
        let mut command = std::process::Command::new(compiler);
        command.arg("--serve-daemon");
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            command.creation_flags(0x08000000);
        }
        command.status()
    })();
    match result {
        Ok(status) => std::process::exit(status.code().unwrap_or(1)),
        Err(error) => {
            eprintln!("dmbd: {error}");
            std::process::exit(1);
        }
    }
}
