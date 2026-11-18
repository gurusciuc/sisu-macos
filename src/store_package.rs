//! CRX3 proof format and production publisher key from Chromium's
//! components/crx_file/{crx3.proto,crx_verifier.cc}. Never accept its test key.
use prost::Message;
use ring::signature;
use sha2::{Digest, Sha256};
use spki::SubjectPublicKeyInfoRef;
use std::ffi::{CStr, CString, c_char};
use std::fs::{self, File};
use std::io::{self, Cursor, Read};
use std::path::{Component, Path};

const MAX_PACKAGE: usize = 32 * 1024 * 1024;
const MAX_EXPANDED: u64 = 128 * 1024 * 1024;
const PUBLISHER: [u8; 32] = [
    0x61, 0xf7, 0xf2, 0xa6, 0xbf, 0xcf, 0x74, 0xcd, 0x0b, 0xc1, 0xfe, 0x24, 0x97, 0xcc, 0x9b, 0x04,
    0x25, 0x4c, 0x65, 0x8f, 0x79, 0xf2, 0x14, 0x53, 0x92, 0x86, 0x7e, 0xa8, 0x36, 0x63, 0x67, 0xcf,
];
#[derive(Message)]
struct Header {
    #[prost(message, repeated, tag = "2")]
    rsa: Vec<Proof>,
    #[prost(message, repeated, tag = "3")]
    ec: Vec<Proof>,
    #[prost(bytes, tag = "10000")]
    signed: Vec<u8>,
}
#[derive(Message)]
struct Proof {
    #[prost(bytes, tag = "1")]
    key: Vec<u8>,
    #[prost(bytes, tag = "2")]
    signature: Vec<u8>,
}
#[derive(Message)]
struct SignedHeader {
    #[prost(bytes, tag = "1")]
    id: Vec<u8>,
}

type Result<T> = std::result::Result<T, &'static str>;

fn verified_archive<'a>(package: &'a [u8], listing: &str) -> Result<&'a [u8]> {
    if package.len() > MAX_PACKAGE || package.get(..8) != Some(b"Cr24\x03\0\0\0") {
        return Err("The Store did not return a supported CRX3 package.");
    }
    let length = u32::from_le_bytes(
        package
            .get(8..12)
            .ok_or("Missing CRX header.")?
            .try_into()
            .unwrap(),
    ) as usize;
    if length > 1024 * 1024 || 12 + length >= package.len() {
        return Err("Invalid CRX header length.");
    }
    let (encoded, archive) = package[12..].split_at(length);
    let header = Header::decode(encoded).map_err(|_| "Invalid CRX header.")?;
    let signed =
        SignedHeader::decode(header.signed.as_slice()).map_err(|_| "Invalid signed header.")?;
    let id: String = signed
        .id
        .iter()
        .flat_map(|b| [char::from(b'a' + (b >> 4)), char::from(b'a' + (b & 15))])
        .collect();
    if signed.id.len() != 16 || id != listing {
        return Err("The package does not match this Store listing.");
    }
    if header.rsa.len() + header.ec.len() > 8 {
        return Err("Too many package signatures.");
    }
    let mut message = Vec::with_capacity(20 + header.signed.len() + archive.len());
    message.extend_from_slice(b"CRX3 SignedData\0");
    message.extend_from_slice(&(header.signed.len() as u32).to_le_bytes());
    message.extend_from_slice(&header.signed);
    message.extend_from_slice(archive);
    let mut publisher = false;
    let mut developer = false;
    let proofs = header
        .rsa
        .iter()
        .map(|p| (p, false))
        .chain(header.ec.iter().map(|p| (p, true)));
    for (proof, ec) in proofs {
        let spki = SubjectPublicKeyInfoRef::try_from(proof.key.as_slice())
            .map_err(|_| "Invalid signing key.")?;
        let key = spki
            .subject_public_key
            .as_bytes()
            .ok_or("Invalid signing key.")?;
        let algorithm: &dyn signature::VerificationAlgorithm = if ec {
            &signature::ECDSA_P256_SHA256_ASN1
        } else {
            &signature::RSA_PKCS1_2048_8192_SHA256
        };
        signature::UnparsedPublicKey::new(algorithm, key)
            .verify(&message, &proof.signature)
            .map_err(|_| "The extension signature is invalid.")?;
        let hash = Sha256::digest(&proof.key);
        publisher |= hash[..] == PUBLISHER;
        developer |= hash[..16] == signed.id;
    }
    if !publisher || !developer {
        return Err("The publisher and Chrome Web Store signatures are both required.");
    }
    Ok(archive)
}

// The caller owns a newly created, private directory and removes it on failure.
fn unpack(bytes: &[u8], root: &Path) -> Result<()> {
    let mut zip = zip::ZipArchive::new(Cursor::new(bytes)).map_err(|_| "Invalid ZIP payload.")?;
    if zip.len() > 4096 {
        return Err("The extension contains too many files.");
    }
    let mut remaining = MAX_EXPANDED;
    for i in 0..zip.len() {
        let mut entry = zip
            .by_index(i)
            .map_err(|_| "Cannot read an extension resource.")?;
        let name = std::str::from_utf8(entry.name_raw()).map_err(|_| "Invalid resource name.")?;
        let rel = Path::new(name);
        if name.len() > 1024
            || name.contains(['\\', ':'])
            || name.chars().any(char::is_control)
            || !rel.components().all(|c| matches!(c, Component::Normal(_)))
            || rel.as_os_str().is_empty()
        {
            return Err("Invalid resource path.");
        }
        let kind = entry.unix_mode().unwrap_or(0) & 0o170000;
        if !matches!(kind, 0 | 0o040000 | 0o100000) || entry.is_symlink() {
            return Err("An extension resource is not a regular file or directory.");
        }
        let path = root.join(rel);
        if entry.is_dir() {
            fs::create_dir_all(path).map_err(|_| "Cannot prepare the extension directory.")?;
            continue;
        }
        let size = entry.size();
        if size > remaining || size > 32 * 1024 * 1024 {
            return Err("The expanded extension is too large.");
        }
        fs::create_dir_all(path.parent().ok_or("Missing resource directory.")?)
            .map_err(|_| "Cannot create resource directory.")?;
        let mut out = File::create_new(path).map_err(|_| "Duplicate or unwritable resource.")?;
        let written = io::copy(&mut entry.by_ref().take(size + 1), &mut out)
            .map_err(|_| "Invalid compressed data.")?;
        if written != size {
            return Err("Unexpected resource length.");
        }
        remaining -= size;
    }
    if !root.join("manifest.json").is_file() {
        return Err("The extension has no manifest.");
    }
    Ok(())
}

/// The three inputs are supplied only by the native installer. A null return means success.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sisu_unpack_store_package(
    bytes: *const u8,
    len: usize,
    id: *const c_char,
    destination: *const c_char,
) -> *mut c_char {
    let result = (|| {
        if bytes.is_null() || id.is_null() || destination.is_null() || len > MAX_PACKAGE {
            return Err("Invalid extension package.");
        }
        let package = unsafe { std::slice::from_raw_parts(bytes, len) };
        let listing = unsafe { CStr::from_ptr(id) }
            .to_str()
            .map_err(|_| "Invalid listing.")?;
        let root = unsafe { CStr::from_ptr(destination) }
            .to_str()
            .map_err(|_| "Invalid directory.")?;
        unpack(verified_archive(package, listing)?, Path::new(root))
    })();
    result.err().map_or(std::ptr::null_mut(), |e| {
        CString::new(e).unwrap().into_raw()
    })
}
