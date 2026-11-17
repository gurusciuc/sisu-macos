use sisu_core::Filter;
#[test]
fn rules_distinguish_hosts_types_exceptions_and_cosmetic_sites() {
    let rules = Filter::bundled().unwrap();
    assert!(rules.blocks(
        "http://localhost/probe-ad.js",
        "http://localhost/",
        "script",
        "GET"
    ));
    assert!(!rules.blocks(
        "http://localhost/probe-ad.js",
        "http://localhost/",
        "image",
        "GET"
    ));
    assert!(!rules.blocks(
        "http://localhost/probe-ad.js?allowed",
        "http://localhost/",
        "script",
        "GET"
    ));
    assert!(!rules.blocks(
        "https://example.org/probe-ad.js",
        "https://example.org/",
        "script",
        "GET"
    ));
    assert!(rules.css("http://localhost/").contains(".fixture-ad"));
    assert!(!rules.css("https://example.org/").contains(".fixture-ad"));
    assert!(rules.blocks(
        "https://example.com/ads/!rotator/control.js",
        "https://example.org/",
        "image",
        "GET"
    ));
}

#[test]
fn address_entry_keeps_http_explicit_and_encodes_search() {
    use sisu_core::destination;
    assert_eq!(
        destination("example.org").as_deref(),
        Some("https://example.org/")
    );
    assert_eq!(
        destination("http://localhost:9876").as_deref(),
        Some("http://localhost:9876/")
    );
    assert_eq!(
        destination("salt & pepper").as_deref(),
        Some("https://duckduckgo.com/?q=salt+%26+pepper")
    );
    assert_eq!(destination("javascript:alert(1)"), None);
    assert_eq!(destination(""), None);
}
