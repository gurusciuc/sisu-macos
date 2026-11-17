fn main() -> std::io::Result<()> {
    let out = std::path::PathBuf::from(
        std::env::args_os()
            .nth(1)
            .expect("Expected resource directory"),
    );
    std::fs::create_dir_all(&out)?;
    std::fs::write(
        out.join("webkit-rules.json"),
        include_bytes!(concat!(env!("OUT_DIR"), "/webkit-rules.json")),
    )?;
    std::fs::write(
        out.join("webkit-rules-report.json"),
        include_bytes!(concat!(env!("OUT_DIR"), "/webkit-rules-report.json")),
    )
}
