mod cli_dmb;
mod cli_od;
mod cli_rsc;

use byond_dmb::dmb::Dmb;
use std::io;

#[derive(Clone, Copy)]
enum Tail {
    None,
    Any,
    Optional {
        exact: &'static [&'static str],
        prefixes: &'static [&'static str],
    },
    Many {
        exact: &'static [&'static str],
        prefixes: &'static [&'static str],
    },
}

#[derive(Clone, Copy)]
struct CommandSpec {
    name: &'static str,
    usage: &'static str,
    positional: usize,
    tail: Tail,
}

impl CommandSpec {
    const fn fixed(name: &'static str, usage: &'static str, positional: usize) -> Self {
        Self {
            name,
            usage,
            positional,
            tail: Tail::None,
        }
    }
    const fn optional(
        name: &'static str,
        usage: &'static str,
        positional: usize,
        exact: &'static [&'static str],
        prefixes: &'static [&'static str],
    ) -> Self {
        Self {
            name,
            usage,
            positional,
            tail: Tail::Optional { exact, prefixes },
        }
    }
}

const COMMANDS: &[CommandSpec] = &[
    CommandSpec::optional("od-proc-audit", "INPUT.json BASELINE.json TEMPLATE.dmb RESOURCE_ROOT NATIVE.dmb [--grouped|--grouped-values|--paths|--samples=N|--pairs=FIELD|--field=FIELD]", 5, &["--grouped", "--grouped-values", "--paths"], &["--samples=", "--pairs=", "--field="]),
    CommandSpec::optional("od-class-audit", "INPUT.json BASELINE.json TEMPLATE.dmb RESOURCE_ROOT NATIVE.dmb [--grouped|--grouped-values|--paths]", 5, &["--grouped", "--grouped-values", "--paths"], &[]),
    CommandSpec::optional("od-map-audit", "INPUT.json BASELINE.json TEMPLATE.dmb RESOURCE_ROOT NATIVE.dmb [--semantic-values]", 5, &["--semantic-values"], &[]),
    CommandSpec { name: "od-lowering-audit", usage: "INPUT.json BASELINE.json TEMPLATE.dmb RESOURCE_ROOT [--debug-lines] [--examples=N]", positional: 4, tail: Tail::Many { exact: &["--debug-lines"], prefixes: &["--examples="] } },
    CommandSpec::fixed("od-diagnostic", "INPUT.json BASELINE.json TEMPLATE.dmb RESOURCE_ROOT", 4),
    CommandSpec { name: "dmb-compare", usage: "EXPECTED.dmb ACTUAL.dmb [PATH_PREFIX...]", positional: 2, tail: Tail::Any },
    CommandSpec::optional("dmb-map-compare", "EXPECTED.dmb ACTUAL.dmb [--semantic-values]", 2, &["--semantic-values"], &[]),
    CommandSpec::optional("od-to-dmb", "INPUT.json BASELINE.json TEMPLATE.dmb RESOURCE_ROOT OUTPUT.dmb OUTPUT.rsc [--debug-lines]", 6, &["--debug-lines"], &[]),
    CommandSpec::fixed("dmb-info", "FILE.dmb", 1),
    CommandSpec::fixed("reference-audit", "FILE.dmb", 1),
    CommandSpec::fixed("dmb-detail", "FILE.dmb", 1),
    CommandSpec::fixed("instance", "FILE.dmb INSTANCE_ID", 2),
    CommandSpec::fixed("proc-args-audit", "FILE.dmb", 1),
    CommandSpec::fixed("argument-source-audit", "FILE.dmb", 1),
    CommandSpec::fixed("table-audit", "FILE.dmb", 1),
    CommandSpec::fixed("class-vars-audit", "FILE.dmb", 1),
    CommandSpec::fixed("class-initials-audit", "FILE.dmb", 1),
    CommandSpec::fixed("class-overrides-audit", "FILE.dmb", 1),
    CommandSpec::fixed("class-initial-tag", "FILE.dmb TAG", 2),
    CommandSpec::fixed("class-initials", "FILE.dmb CLASS_ID", 2),
    CommandSpec::fixed("dmb-copy", "INPUT.dmb OUTPUT.dmb", 2),
    CommandSpec::fixed("pair-info", "FILE.dmb FILE.rsc", 2),
    CommandSpec::fixed("opcode-audit", "FILE.dmb", 1),
    CommandSpec::fixed("value-tags", "FILE.dmb", 1),
    CommandSpec::fixed("value-tag-context", "FILE.dmb TAG", 2),
    CommandSpec::fixed("proc-code", "FILE.dmb PROC_ID", 2),
    CommandSpec::fixed("list-code", "FILE.dmb LIST_ID", 2),
    CommandSpec::fixed("opcode-context", "FILE.dmb OPCODE", 2),
    CommandSpec::fixed("string", "FILE.dmb STRING_ID", 2),
    CommandSpec::fixed("list", "FILE.dmb LIST_ID", 2),
    CommandSpec::fixed("variable", "FILE.dmb VARIABLE_ID", 2),
    CommandSpec::fixed("proc", "FILE.dmb PROC_ID", 2),
    CommandSpec::fixed("mob-type", "FILE.dmb MOB_ID", 2),
    CommandSpec::fixed("class", "FILE.dmb CLASS_ID", 2),
    CommandSpec::fixed("class-path", "FILE.dmb CLASS_ID", 2),
    CommandSpec::fixed("class-low-flags", "FILE.dmb", 1),
    CommandSpec::fixed("class-interface-audit", "FILE.dmb", 1),
    CommandSpec::fixed("record-kinds-audit", "FILE.dmb", 1),
    CommandSpec::fixed("record-kind-context", "FILE.dmb KIND", 2),
    CommandSpec::fixed("proc-flags-audit", "FILE.dmb", 1),
    CommandSpec::fixed("proc-source-audit", "FILE.dmb", 1),
    CommandSpec::fixed("proc-flag-context", "FILE.dmb FLAG", 2),
    CommandSpec::fixed("proc-flags-context", "FILE.dmb", 1),
    CommandSpec::fixed("mob-sight-audit", "FILE.dmb", 1),
    CommandSpec::fixed("rsc-info", "FILE.rsc", 1),
    CommandSpec::fixed("rsc-kind-audit", "FILE.rsc", 1),
    CommandSpec::fixed("rsc-id-audit", "FILE.rsc", 1),
    CommandSpec::fixed("rsc-copy", "INPUT.rsc OUTPUT.rsc", 2),
];

enum CliAction {
    Help(Option<&'static CommandSpec>),
    Execute(&'static CommandSpec),
}

fn parse_cli(args: &[String]) -> Result<CliAction, String> {
    let Some(name) = args.get(1).map(String::as_str) else {
        return Err("missing command".into());
    };
    if name == "--help" || name == "-h" {
        return if args.len() == 2 {
            Ok(CliAction::Help(None))
        } else {
            Err("unexpected arguments after --help".into())
        };
    }
    if name == "help" {
        return match args.len() {
            2 => Ok(CliAction::Help(None)),
            3 => COMMANDS
                .iter()
                .find(|spec| spec.name == args[2])
                .map(|spec| CliAction::Help(Some(spec)))
                .ok_or_else(|| format!("unknown command: {}", args[2])),
            _ => Err("usage: dmb-inspect help [COMMAND]".into()),
        };
    }
    let spec = COMMANDS
        .iter()
        .find(|spec| spec.name == name)
        .ok_or_else(|| format!("unknown command: {name}"))?;
    if args.len() == 3 && args[2] == "--help" {
        return Ok(CliAction::Help(Some(spec)));
    }
    let provided = args.len() - 2;
    if provided < spec.positional {
        return Err(format!(
            "{} needs {} positional arguments",
            spec.name, spec.positional
        ));
    }
    let extra = &args[2 + spec.positional..];
    let valid = match spec.tail {
        Tail::None => extra.is_empty(),
        Tail::Any => true,
        Tail::Optional { exact, prefixes } => {
            extra.len() <= 1
                && extra
                    .iter()
                    .all(|value| option_valid(value, exact, prefixes))
        }
        Tail::Many { exact, prefixes } => extra
            .iter()
            .all(|value| option_valid(value, exact, prefixes)),
    };
    if !valid {
        return Err(format!("invalid arguments for {}", spec.name));
    }
    Ok(CliAction::Execute(spec))
}

fn option_valid(value: &str, exact: &[&str], prefixes: &[&str]) -> bool {
    exact.contains(&value) || prefixes.iter().any(|prefix| value.starts_with(prefix))
}

fn print_help(spec: Option<&CommandSpec>) {
    match spec {
        Some(spec) => println!("usage: dmb-inspect {} {}", spec.name, spec.usage),
        None => {
            println!("usage: dmb-inspect COMMAND [ARGS]\n\nCommands:");
            for spec in COMMANDS {
                println!("  {:<24} {}", spec.name, spec.usage);
            }
            println!("\nUse `dmb-inspect help COMMAND` for one command.");
        }
    }
}

fn load_dmb(path: &str) -> io::Result<Dmb> {
    Dmb::from_bytes(&std::fs::read(path)?)
}

fn execute_command(name: &str, args: &[String]) -> io::Result<()> {
    match name {
        name if name.starts_with("od-") => cli_od::execute(name, args),
        name if name.starts_with("rsc-") || name == "pair-info" => cli_rsc::execute(name, args),
        name => cli_dmb::execute(name, args),
    }
}

fn run() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let command = match parse_cli(&args) {
        Ok(CliAction::Help(spec)) => {
            print_help(spec);
            return Ok(());
        }
        Ok(CliAction::Execute(spec)) => spec,
        Err(message) => {
            eprintln!("error: {message}\nRun `dmb-inspect --help` for usage.");
            std::process::exit(2);
        }
    };
    debug_assert_eq!(args[1], command.name);
    execute_command(command.name, &args)?;
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("error: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod cli_tests {
    use super::*;

    fn arguments(words: &[&str]) -> Vec<String> {
        std::iter::once("dmb-inspect")
            .chain(words.iter().copied())
            .map(str::to_owned)
            .collect()
    }

    #[test]
    fn every_registered_command_accepts_its_required_arguments() {
        for spec in COMMANDS {
            let mut args = vec!["dmb-inspect".to_owned(), spec.name.to_owned()];
            args.extend((0..spec.positional).map(|_| "path".to_owned()));
            assert!(
                matches!(parse_cli(&args), Ok(CliAction::Execute(found)) if found.name == spec.name),
                "{}",
                spec.name
            );
            args.pop();
            assert!(
                parse_cli(&args).is_err(),
                "{} accepted too few arguments",
                spec.name
            );
        }
    }

    #[test]
    fn help_and_option_validation() {
        assert!(matches!(
            parse_cli(&arguments(&["--help"])),
            Ok(CliAction::Help(None))
        ));
        assert!(matches!(
            parse_cli(&arguments(&["help", "od-to-dmb"])),
            Ok(CliAction::Help(Some(_)))
        ));
        assert!(matches!(
            parse_cli(&arguments(&["od-to-dmb", "--help"])),
            Ok(CliAction::Help(Some(_)))
        ));
        assert!(matches!(
            parse_cli(&arguments(&[
                "od-to-dmb",
                "a",
                "b",
                "c",
                "d",
                "e",
                "f",
                "--debug-lines"
            ])),
            Ok(CliAction::Execute(_))
        ));
        assert!(parse_cli(&arguments(&[
            "od-to-dmb",
            "a",
            "b",
            "c",
            "d",
            "e",
            "f",
            "--bogus"
        ]))
        .is_err());
        assert!(parse_cli(&arguments(&["dmb-info", "a", "extra"])).is_err());
        assert!(parse_cli(&arguments(&["unknown", "a"])).is_err());
        assert!(matches!(
            parse_cli(&arguments(&["dmb-compare", "a", "b", "/obj", "/mob"])),
            Ok(CliAction::Execute(_))
        ));
    }

    #[test]
    fn every_registered_command_has_a_dispatch_handler() {
        let missing = "__dmb_inspect_cli_fixture_that_does_not_exist__";
        for spec in COMMANDS {
            let mut args = vec!["dmb-inspect".to_owned(), spec.name.to_owned()];
            args.extend((0..spec.positional).map(|_| missing.to_owned()));
            let error = execute_command(spec.name, &args).expect_err(spec.name);
            assert!(
                !error.to_string().contains("unknown command"),
                "{} has no command handler",
                spec.name
            );
        }
    }
}
