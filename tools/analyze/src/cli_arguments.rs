//! Shared original command argument and root selection, with no model or policy authority.
use std::path::PathBuf;

#[derive(Debug,PartialEq,Eq)]
pub struct Args {
    pub cmd: String,
    pub lints: Vec<String>,
    pub flags: Vec<String>,
    pub root: Option<PathBuf>,
}

pub fn parse(argv: Vec<String>) -> Args {
    let mut it = argv.into_iter().skip(1);
    let cmd = it.next().unwrap_or_else(|| "help".to_string());
    let mut lints = Vec::new();
    let mut flags = Vec::new();
    let mut root = None;
    let mut taking_lints = false;
    let mut rest: Vec<String> = it.collect();
    let mut i = 0;
    while i < rest.len() {
        let a = std::mem::take(&mut rest[i]);
        i += 1;
        match a.as_str() {
            "--lint" => taking_lints = true,
            "--root" => {
                root = rest.get(i).map(PathBuf::from);
                i += 1;
                taking_lints = false;
            }
            s if s.starts_with("--") => {
                flags.push(s.to_string());
                taking_lints = false;
            }
            _ => {
                if taking_lints || cmd == "parity" {
                    for n in a.split(',') {
                        if !n.is_empty() {
                            lints.push(n.to_string());
                        }
                    }
                } else {
                    flags.push(a);
                }
            }
        }
    }
    Args { cmd, lints, flags, root }
}

pub fn find_root(explicit: Option<PathBuf>) -> PathBuf {
    if let Some(r) = explicit {
        return r;
    }
    let mut dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    loop {
        if dir.join("deepquarry.dme").exists() {
            return dir;
        }
        if !dir.pop() {
            return std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        }
    }
}


#[cfg(test)]mod tests{use super::*;
#[test]fn original_command_arguments_preserve_order_commas_root_and_mode_transitions(){let args=parse(["analyze","check","--lint","sem/reads,tracked","sys","--root","E:/project root","--raw","positional"].into_iter().map(str::to_owned).collect());assert_eq!(args,Args{cmd:"check".into(),lints:vec!["sem/reads".into(),"tracked".into(),"sys".into()],flags:vec!["--raw".into(),"positional".into()],root:Some(PathBuf::from("E:/project root"))});}
#[test]fn original_command_arguments_keep_parity_positionals_and_missing_argument_behavior(){let parse_args=|args:&[&str]|parse(args.iter().map(|s|s.to_string()).collect());assert_eq!(parse_args(&["analyze"]).cmd,"help");assert_eq!(parse_args(&["analyze","parity","one,two","--all","three"]).lints,["one","two","three"]);let args=parse_args(&["analyze","gen","reads","--check"]);assert_eq!(args.flags,["reads","--check"]);assert!(args.lints.is_empty());let args=parse_args(&["analyze","check","--root"]);assert!(args.root.is_none());assert!(args.flags.is_empty());assert_eq!(parse_args(&["analyze","check","--lint",",first,,last,"]).lints,["first","last"]);}
#[test]fn explicit_root_selection_preserves_the_actual_argument_without_source_read(){let path=PathBuf::from("path not observed by argument selection");assert_eq!(find_root(Some(path.clone())),path);}
}
