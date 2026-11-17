use sisu_core::bookmarks::{Bookmark, merge_export};
#[test]
fn html_exports_preserve_nested_folders_and_merge_safely() {
    let mut entries = vec![Bookmark::new("Saved", "https://example.org/").unwrap()];
    let html = br#"<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><p>
<DT><H3>Work &amp; study</H3><DL><p>
<DT><A HREF="https://example.org">Already here</A>
<DT><H3>Reading</H3><DL><DT><A HREF="https://example.net/a?b=1&amp;c=2">Notes &amp; maps</A></DL>
<DT><A HREF="javascript:alert(1)">Skip</A></DL></DL>"#;
    let report = merge_export(&mut entries, html).unwrap();
    assert_eq!((report.added, report.duplicates, report.skipped), (1, 1, 1));
    assert_eq!(entries[1].folders, ["Work & study", "Reading"]);
    assert_eq!(entries[1].url, "https://example.net/a?b=1&c=2");
    assert_eq!(entries[1].title, "Notes & maps");
    assert_eq!(merge_export(&mut entries, html).unwrap().added, 0);
}
#[test]
fn failed_import_does_not_damage_existing_bookmarks() {
    let mut records = vec![Bookmark::new("Local", "https://example.org/").unwrap()];
    assert!(merge_export(&mut records, b"not a bookmark export").is_err());
    assert_eq!(records.len(), 1);
}
