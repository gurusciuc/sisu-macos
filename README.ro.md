<p align="center"><a href="README.md">English</a> · <strong>Română</strong></p>

<p align="center"><img src="resources/branding/sisu.png" alt="Sisu" width="88" height="88"></p>

<h1 align="center">Sisu</h1>

<p align="center">Browser nativ pentru Mac, cu file sus sau în lateral și pagini redate de WebKit.</p>

<p align="center">
  <a href="https://github.com/gurusciuc/sisu-macos/releases/tag/v0.1.0-alpha.7"><img alt="0.1.0-alpha.7" src="https://img.shields.io/badge/release-0.1.0--alpha.7-46546A"></a>
  <a href="https://github.com/gurusciuc/sisu-macos/actions/workflows/check.yml"><img alt="macOS CI" src="https://github.com/gurusciuc/sisu-macos/actions/workflows/check.yml/badge.svg?branch=main"></a>
  <img alt="macOS 14+ · Apple Silicon" src="https://img.shields.io/badge/macOS-14%2B%20%7C%20Apple%20Silicon-30343B">
  <a href="LICENSE"><img alt="Apache 2.0" src="https://img.shields.io/badge/license-Apache%202.0-586A48"></a>
</p>

<p align="center"><strong><a href="https://github.com/gurusciuc/sisu-macos/releases/download/v0.1.0-alpha.7/Sisu-0.1.0-alpha.7-macOS-arm64.dmg">Descarcă pentru Apple Silicon</a></strong> · <a href="https://github.com/gurusciuc/sisu-macos/releases/tag/v0.1.0-alpha.7">Ce e nou</a> · <a href="https://github.com/gurusciuc/sisu">Sisu for Windows</a></p>

## Instalare

Ai nevoie de un Mac cu cip Apple Silicon și macOS 14 sau mai nou. Deschide DMG-ul, trage **Sisu** în **Applications**, apoi ejectează imaginea de disc. Dacă foloseai Sisu WebKit Preview, închide-l înainte să deschizi Sisu. Aplicația folosește același profil.

Această versiune alfa are semnătură ad-hoc. Apple nu a notarizat aplicația, iar Gatekeeper poate bloca prima deschidere. [Ghidul Apple](https://support.apple.com/en-us/102445)

## Ce poți folosi

- Mută filele sus sau în lateral. Paginile deschise își păstrează conținutul când schimbi poziția filelor.
- Alege tema, motorul de căutare și blocarea conținutului din Settings. Pagina de filă nouă folosește fundalul punctat *Inner Citadel* și respectă opțiunea Reduce Motion.
- Importă cookie-uri dintr-un fișier JSON cu **Settings → Browser data → Import cookies…**. Poți adăuga și scurtături pe pagina de filă nouă cu **File → Import Site Shortcuts…**.
- Deschide o fereastră privată cu **⌘⇧N**. Sesiunile private au date separate de profilul obișnuit.

- De la macOS 15.4, deschide **Settings → Extensions → Manage Extensions** pentru magazin, sau apasă **Add to Sisu** în bara Sisu când ești pe pagina unei extensii. Sisu verifică semnăturile pachetului și afișează permisiunile înainte de instalare. Extensiile care cer API-uri Chrome indisponibile în WebKit, precum `offscreen` și `proxy`, sunt respinse.
- Sisu încearcă HTTPS și afișează **Not Secure** pentru pagini HTTP. **Browser menu → Allow Web Inspector** face fila curentă disponibilă în meniul **Develop** din Safari.
- Sisu cere confirmare dacă închizi o filă, o fereastră sau aplicația cu modificări de formular detectate.

Actualizările acestei versiuni se descarcă manual de pe GitHub. [Stadiul testelor](docs/checkpoint.md)

## Compilare și verificare

Instalează Apple Command Line Tools și versiunea Rust din `rust-toolchain.toml`, apoi rulează:

```sh
./tools/build-macos.sh dist/alpha7
```

Scriptul rulează testele Rust și creează un DMG pentru arhitectura Mac-ului pe care îl folosești. Pentru testele native cu un profil separat, urmează instrucțiunile din [README în engleză](README.md#validation).

## Contribuții și licență

Codul original Sisu este publicat sub Apache License 2.0. Licența permite folosirea, modificarea și redistribuirea, inclusiv comercială, cu respectarea condițiilor ei. Componentele externe și listele de filtrare își păstrează licențele. [Licență](LICENSE) · [Atribuiri](NOTICE) · [Componente externe](THIRD_PARTY.md)

Pentru modificări și raportarea problemelor de securitate, consultă [ghidul de contribuții](CONTRIBUTING.md) și [politica de securitate](SECURITY.md).
