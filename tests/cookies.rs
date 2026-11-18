use sisu_core::cookies::{SameSite, parse_export};
#[test]
fn preserves_cookie_security_and_expiry() {
    let data=br#"[{"name":"__Host-session","value":"fixture-token","domain":"example.test","hostOnly":true,"path":"/","secure":true,"httpOnly":true,"sameSite":"strict","expirationDate":2000000000},{"name":"old","value":"gone","domain":"example.test","expirationDate":1}]"#;
    let export = parse_export(data, 100).unwrap();
    assert_eq!(export.cookies.len(), 1);
    assert_eq!(export.expired, 1);
    let cookie = &export.cookies[0];
    assert!(cookie.secure && cookie.http_only && cookie.host_only);
    assert_eq!(cookie.same_site, SameSite::Strict);
    assert_eq!(cookie.expires, Some(2000000000));
}
#[test]
fn refuses_scope_loss_and_invalid_values_before_writes() {
    for data in [
        r#"[{"name":"session","value":"x","domain":"example.test","partitionKey":{"topLevelSite":"https://elsewhere.test"}}]"#,
        r#"[{"name":"__Host-session","value":"x","domain":".example.test","secure":true}]"#,
        r#"[{"name":"session","value":"x","domain":"example.test","sameSite":"none"}]"#,
        r#"[{"name":"session","value":"x;injected=y","domain":"example.test"}]"#,
        r#"[{"name":"session","value":"x","domain":"example.test/path"}]"#,
        r#"[{"name":"session","value":"x","domain":"..example.test"}]"#,
        r#"[{"name":"session","value":"x","domain":".com"}]"#,
        r#"[{"name":"session","value":"x","domain":".github.io"}]"#,
        r#"[{"name":"session","value":"x","domain":".127.0.0.1"}]"#,
        r#"[{"name":"session","value":"x","domain":"example.test","path":"/; Path=/"}]"#,
        r#"[{"name":"session","value":"x","domain":"example.test"},{"name":"session","value":"y","domain":"example.test"}]"#,
    ] {
        assert!(parse_export(data.as_bytes(), 100).is_err());
    }
}
