<div align="center">

<img src="./docs/QiwiiLogo.png" alt="Qiwii Logo" width="80" height="80" />

# Qiwii

**Fast, Private and Seamless Contact Sharing**

A privacy-first, offline-capable mobile utility built to transfer contacts instantly between devices with zero cloud servers, 4-digit PIN encryption, and optical QR technology.

[![Flutter](https://img.shields.io/badge/Flutter-3.13+-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?style=flat-square&logo=dart&logoColor=white)](https://dart.dev/)
[![Riverpod](https://img.shields.io/badge/Riverpod-2.6-385072?style=flat-square)](https://riverpod.dev/)
[![UI](https://img.shields.io/badge/UI-Material_3_Ember-FF7A1A?style=flat-square)](https://m3.material.io/)
[![Storage](https://img.shields.io/badge/Storage-100%25_Offline-10B981?style=flat-square)](./PRIVACY.md)
[![Security](https://img.shields.io/badge/Security-AES_GCM_256_+_PBKDF2-blue?style=flat-square)](./PRIVACY.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](./LICENSE)

[Download APK](https://github.com/kuroi17/Qiwii/releases) | [Web Bridge](https://kuroi17.github.io/Qiwii/) | [Privacy Policy](./PRIVACY.md)

</div>

---

## Overview

Traditional contact sharing usually forces an all-or-nothing choice: either sync your entire address book to remote cloud databases, or manually export messy `.vcf` card files over messaging apps.

**Qiwii** eliminates the middleman. It is a cross-platform mobile utility that moves specific contacts directly between devices in seconds. Sharing works camera-to-screen using pure optical QR technology or encrypted local peer-to-peer transport, with zero cloud storage, zero tracking, and zero account sign-ins.

---

## Key Features

- **100% Offline Optical Transfer:** Share contacts screen-to-camera even in Airplane Mode. Requires zero internet, Wi-Fi, or cellular data.
- **ZLIB Compression and Animated Multi-Frame QR:** Employs pure-Dart Deflate/Zlib payload compression and an auto-looping multi-frame QR carousel to stream 10 to 100+ contacts seamlessly.
- **End-to-End PIN Protection:** Payloads can be encrypted with PBKDF2 HMAC-SHA256 key derivation and AES-GCM-256 authenticated encryption using an optional 4-digit PIN, backed by persistent brute-force attempt lockout.
- **Smart Duplicate Resolution & Merge:** Normalizes phone numbers to E.164 standards, flags potential duplicates against the local address book, and lets the recipient Skip duplicates or Merge new information into existing contact cards.
- **Multi-Channel Ingestion:**
  - High-performance live camera scanner with target reticle and torch control.
  - Gallery and screenshot picker for decoding QR images stored on device.
  - Automatic clipboard detection on app resume with quick-import prompts.
  - Universal web bridge (`https://kuroi17.github.io/Qiwii/`) to handle cross-app link sharing.
- **Privacy-First Architecture:** No analytics SDKs, no telemetry, no tracking, and no external APIs. All encryption keys and temporary transfer states are purged from memory immediately after transfer.

---

## Tech Stack

| Component | Technology |
|---|---|
| Framework | Flutter 3.13+ (Dart 3.0+) |
| State Management | Flutter Riverpod 2.6 |
| Design System | Custom Material 3 (Warm Almond `#FAF1E8` and Orange Ember `#FF7A1A`) |
| Cryptography | AES-GCM-256 and PBKDF2 HMAC-SHA256 (`crypto`) |
| Compression | Deflate / ZLIB (`archive`) |
| QR Code Generation & Scanning | `qr_flutter`, `mobile_scanner`, `qr_code_dart_decoder` |
| Deep Linking & Web Bridge | `app_links` (`qiwii://`, `contactqr://`, GitHub Pages) |
| Native Contacts Integration | `flutter_contacts` with background Dart isolate parsing |

---

## Project Structure

```text
ContactShareQR/
├── docs/                         # GitHub Pages web redirector (live bridge)
│   ├── index.html
│   └── QiwiiLogo.png
├── contactqr_flutter/
│   ├── lib/
│   │   ├── core/                 # Constants, theme, crypto, and QR codecs
│   │   ├── data/                 # AppContact models and contact repositories
│   │   ├── features/
│   │   │   ├── home/             # Main screen, clipboard watcher, deep links
│   │   │   ├── contacts/         # Contact selector and review list
│   │   │   ├── qr/               # QR generator, multi-frame scanner, PIN modals
│   │   │   ├── transfer/         # Local P2P transfer server and client
│   │   │   └── import/           # Received contacts, duplicate detection & merge
│   │   └── main.dart             # Application entry point
│   ├── test/                     # Unit, widget, and integration tests
│   └── pubspec.yaml
├── LICENSE                       # MIT License
├── PRIVACY.md                    # Privacy policy
└── README.md
```

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev) (v3.13 or newer)
- Android SDK (API level 21+) or Chrome browser for web preview
- Git

Verify your Flutter installation:

```bash
flutter doctor
```

### Installation and Setup

1. **Clone the repository:**

   ```bash
   git clone https://github.com/kuroi17/Qiwii.git
   cd Qiwii/contactqr_flutter
   ```

2. **Install project dependencies:**

   ```bash
   flutter pub get
   ```

3. **Run code analysis and tests:**

   ```bash
   flutter analyze
   flutter test
   ```

4. **Launch the application:**

   ```bash
   # Run on connected Android device or emulator
   flutter run

   # Run on Chrome web browser
   flutter run -d chrome
   ```

---

## Contributing

Contributions, bug reports, and suggestions are welcome.

1. Fork the repository.
2. Create your branch (`git checkout -b feature/your-feature-name`).
3. Ensure all tests pass (`flutter test` and `flutter analyze`).
4. Commit your changes with descriptive messages (`git commit -m 'feat: add feature description'`).
5. Push to your branch (`git push origin feature/your-feature-name`).
6. Submit a Pull Request.

---

## License

This project is open-source software licensed under the [MIT License](./LICENSE).
