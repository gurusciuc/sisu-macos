use adblock::{
    Engine,
    lists::{FilterSet, ParseOptions},
};
use sha2::{Digest, Sha256};
use std::{env, fs, path::PathBuf};

fn main() {
    let mut rules = FilterSet::new(false);
    let export_webkit = env::var_os("CARGO_FEATURE_MAC_CORE").is_some();
    let mut webkit = FilterSet::new(true);
    let mut source_candidates = 0;
    for (name, digest) in [
        (
            "easylist.txt",
            "ff795ed6920935ee66e56e014e95e62e14e17ed6fcd186b43dba0feed2d5f26d",
        ),
        (
            "easyprivacy.txt",
            "042fefa0afb7ce2e61fe7f25ead218a98106725c3a578f724cd81a49ed2efba8",
        ),
        ("probe.txt", ""),
    ] {
        let path = format!("rules/{name}");
        println!("cargo:rerun-if-changed={path}");
        assert!(fs::metadata(&path).unwrap().len() <= 8 * 1024 * 1024);
        let input = fs::read(&path).unwrap();
        if !digest.is_empty() {
            assert_eq!(
                format!("{:x}", Sha256::digest(&input)),
                digest,
                "{name} integrity check"
            );
        }
        let input = String::from_utf8(input).unwrap();
        if export_webkit {
            source_candidates += input
                .lines()
                .filter(|s| !s.trim().is_empty() && !s.starts_with('!') && !s.starts_with('['))
                .count();
            webkit.add_filter_list(input.clone(), ParseOptions::default());
        }
        rules.add_filter_list(input, ParseOptions::default());
    }
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    fs::write(
        out.join("rules.bin"),
        Engine::new_with_filter_set(rules).serialize(),
    )
    .unwrap();
    if export_webkit {
        let (converted, used) = webkit.into_content_blocking().expect("debug filter set");
        let json = serde_json::to_vec(&converted).unwrap();
        assert!(
            converted.len() <= 150_000,
            "WebKit rule limit: do not split exceptions across lists"
        );
        fs::write(out.join("webkit-rules.json"), &json).unwrap();
        fs::write(out.join("webkit-rules-report.json"), serde_json::to_vec_pretty(&serde_json::json!({
            "schema":1,"rules":converted.len(),"source_candidate_lines":source_candidates,
            "converted_source_filters":used.len(),"sha256":format!("{:x}",Sha256::digest(&json)),
            "note":"Conversion is partial. Source candidate counts include unsupported syntax, duplicates and disabled rules. This does not establish parity with adblock-rust."
        })).unwrap()).unwrap();
    }
}
