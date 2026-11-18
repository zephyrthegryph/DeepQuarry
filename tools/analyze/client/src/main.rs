//! Native-only executable client. It never loads the legacy Analyze engine.
fn main()->std::process::ExitCode{
 let args=std::env::args().skip(1).collect::<Vec<_>>();
 if args.len()==1&&args[0]=="--client-version"{println!("native-analyze-client-v2");return std::process::ExitCode::SUCCESS;}
 let utility=matches!(args.first().map(String::as_str),Some("codemod"|"parity"))||args.first().is_some_and(|arg|arg=="sem")&&args.get(1).is_some_and(|arg|arg=="fixture");
 if utility&&args.iter().any(|arg|arg=="--native-dmbc"||arg.starts_with("--native-dmbc=")){return dq_analyze_client::native_cli_client::codemod_fixture_cli(&args);}

 if args.first().is_some_and(|arg|arg=="ordinary"){return dq_analyze_client::native_cli_client::ordinary_native_cli(&args[1..]);}
 if args.first().is_some_and(|arg|arg=="selftest"){return dq_analyze_client::native_cli_client::standalone_selftest_cli(&args);}
 if let Some(exit)=dq_analyze_client::native_cli_client::metadata_utility_cli(&args){return exit;}
 match args.first().map(String::as_str){
  Some("query"|"native-query")=>return dq_analyze_client::native_cli_client::cli(&args[1..]),
  Some("native-exclusions")=>return dq_analyze_client::native_cli_client::exclusions_cli(&args[1..]),
  Some("native-image-dir")=>return dq_analyze_client::native_cli_client::image_dir_cli(&args[1..]),
  Some("native-checker")=>return dq_analyze_client::native_cli_client::checker_text_cli(&args[1..]),
  Some("native-check")=>return dq_analyze_client::native_cli_client::policy_cli(&args[1..],false),
  Some("native-baseline")=>return dq_analyze_client::native_cli_client::policy_cli(&args[1..],true),
  Some("gen")=>return dq_analyze_client::native_cli_client::ordinary_generation_cli(&args[1..]),
  Some("native-gen")=>return dq_analyze_client::native_cli_client::generation_cli(&args[1..]),
  _=>{}
 }
 if let Some(exit)=dq_analyze_client::native_cli_client::workspace_check(&args){return exit;}
 eprintln!("usage: analyze-native (query|native-check|native-checker|native-baseline|native-exclusions|native-image-dir|gen) [options]");std::process::ExitCode::from(2)
}
