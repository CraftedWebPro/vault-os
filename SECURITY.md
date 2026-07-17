# Security Model — Vault OS

This document describes how Vault OS protects your data. It is intended as a
threat model for security reviewers and contributors.

---

## Design Principles

- **Local-first.** No network calls, no cloud storage, no accounts.
- **Sealed-or-open.** The workspace exists as plaintext only while the vault is
  unlocked. On lock, every file is re-encrypted and the workspace is deleted.
- **Two-factor vault key.** The vault encryption key is derived from **both** a
  passphrase and a biometric factor. Neither alone is sufficient.

---

## Encryption

| Property | Value |
|---|---|
| Algorithm | AES-256-GCM (authenticated encryption) |
| Key size | 256 bits (32 bytes) |
| Nonce size | 96 bits (12 bytes), randomly generated per encryption |
| MAC size | 128 bits (16 bytes), appended to ciphertext |
| Library | [`cryptography`](https://pub.dev/packages/cryptography) (Dart), which delegates to BoringCrypto / platform AES-NI |

Every encrypted blob on disk is stored as: `nonce ‖ MAC ‖ ciphertext`.

Tampered or truncated ciphertext is rejected at decryption time (GCM
authentication tag verification).

---

## Key Derivation

| Property | Value |
|---|---|
| Algorithm | PBKDF2-HMAC-SHA256 |
| Iterations | 120,000 |
| Output bits | 256 |
| Salt | 16 bytes, cryptographically random per vault |

The salt is stored in the vault manifest (`saltBase64`) and is **not** secret —
its purpose is to prevent rainbow-table / precomputation attacks on the
passphrase.

Source: `lib/services/crypto_service.dart:13-17`

---

## Vault Key Construction

```
userKey  = PBKDF2(passphrase, salt)          // 32 bytes
bioKey   = random 32 bytes, generated once    // stored inside the biometric profile
vaultKey = userKey  XOR  bioKey               // used to encrypt vault data
```

- **`userKey`** is derived from the passphrase + salt via PBKDF2.
- **`bioKey`** is 32 random bytes generated at vault creation and embedded in
  the encrypted biometric profile. It is returned by the Python biometric
  service only after successful face + blink + gesture verification.
- **`vaultKey`** (XOR of both) is the key used to encrypt/decrypt every file
  blob and the vault metadata.

**The passphrase is the foundation of the security model.** It is never stored
in plaintext, JSON, or any recoverable form on disk. It exists only in the
user's memory and in the derived `userKey` during the brief moment of unlock.
The biometric factor is an additional layer — not a replacement for the
passphrase. An attacker who obtains the biometric profile (which is encrypted)
still cannot decrypt the vault without the passphrase. An attacker who
obtains the passphrase still cannot decrypt the vault without passing the
biometric check with a live webcam.

Source: `lib/controllers/vault_app_controller.dart:136-142`

---

## Biometric Profile Storage

| Property | Value |
|---|---|
| Stored at | `<vault_dir>/profile.dat` |
| Encryption | AES-256-GCM, keyed with `userKey` |
| Contents | Face embedding (ONNX), blink thresholds, gesture landmarks, `bio_key` (base64) |
| Lifetime | Encrypted at rest. Decrypted to a temporary `.runtime.json` file only during Python verification, then immediately deleted. |

The biometric profile is **never** stored in plaintext on disk. The Python
biometric service receives the decrypted profile path as a CLI argument and
returns the `bio_key` on stdout — no persistent IPC channel or network socket
is used.

Source: `lib/services/storage_service.dart:423-441`

---

## How Unlock Works

1. User enters passphrase → `userKey = PBKDF2(passphrase, salt)`
2. Vault's encrypted biometric profile is decrypted with `userKey` → temp file
3. Python CLI process is spawned with the temp profile path
4. Webcam captures face + blink + hand gesture; verifies against stored
   embeddings
5. If verification passes → Python returns `bio_key` on stdout
6. Temp profile is deleted
7. `vaultKey = userKey XOR bioKey`
8. Encrypted file blobs are decrypted into a temporary workspace directory

If **any** step fails (wrong passphrase, face mismatch, missed blink, wrong
gesture), the vault remains sealed.

Source: `lib/controllers/vault_app_controller.dart:544-586`

---

## How Lock Works

1. Workspace files are read, re-encrypted with `vaultKey`, and written back as
   blob files in the vault directory
2. `_vaultKey` is set to `null` in memory
3. The plaintext workspace directory is **deleted**
4. The vault returns to the sealed state

Source: `lib/controllers/vault_app_controller.dart:1018-1036`

---

## Workspace Lifecycle

| State | What exists on disk |
|---|---|
| **Locked** | Encrypted blobs + encrypted metadata + encrypted profile + manifest. No plaintext. |
| **Unlocked** | All of the above, plus a temporary `<vault>_unlocked/` directory containing decrypted files. |

The `_unlocked` directory is created on unlock and deleted on lock (or app
exit via `autoLockIfNeeded`).

---

## Vault Manifest (Plaintext)

The `index.dat` manifest stores **non-secret** metadata in plaintext:

- `vaultName`, `vaultId`
- `saltBase64` (salt for PBKDF2 — not secret)
- `gestureLabel` (name of the enrolled gesture — not secret)
- `createdAtIso`, `wallpaperAsset`

This file allows the Recovery / Rescan feature to locate and re-attach to a
vault without relying on app-local state.

---

## Recovery

If app state is lost but the vault folder still exists on disk, the user can
point the app at the vault folder. The app reads the manifest to recover the
salt and configuration, then prompts for the passphrase and biometric
verification to re-derive the vault key.

---

## Rate Limiting and Brute-Force Protection

Vault OS relies on the **cost of PBKDF2** (120,000 iterations) as the primary
brute-force mitigation. Each passphrase guess requires one full PBKDF2
derivation plus a biometric verification step (webcam capture + ML inference).

There is **no** account lockout or exponential delay. This is a conscious
trade-off for an offline, single-user tool — the attacker must have local file
access and the cost per guess is dominated by PBKDF2 + webcam capture, not by
app-level throttling.

For high-threat scenarios, users should combine Vault OS with OS-level disk
encryption (BitLocker, VeraCrypt) to protect the vault folder at rest.

---

## Attack Surface

### Python Biometric Service

- Communicates via **CLI subprocess** (`Process.run`), not a network socket or
  named pipe.
- Receives arguments on the command line, returns JSON on stdout.
- No persistent daemon, no open ports.
- The decrypted biometric profile is passed as a file path; the temp file is
  deleted after the call returns.

### What an attacker with local file access can obtain

| Asset | Encrypted? | Notes |
|---|---|---|
| Vault blobs | Yes | AES-256-GCM, key = `vaultKey` |
| Vault metadata (registry) | Yes | AES-256-GCM, key = `vaultKey` |
| Biometric profile | Yes | AES-256-GCM, key = `userKey` |
| Salt | No | Public, not secret |
| Gesture label | No | Public, not secret |
| Vault manifest | No | Public, not secret |

### What an attacker would need to decrypt a vault

1. The user's passphrase (to derive `userKey`)
2. The `bioKey` (returned only after passing face + blink + gesture verification
   with the live webcam)

### Shared capture path caveat

Face recognition, blink detection, and gesture recognition all flow through
the same Python/OpenCV/MediaPipe pipeline and the same webcam. An attacker who
compromises this pipeline (e.g., malware hooking the Python process) could
intercept the `bio_key` from stdout. This is mitigated by:

- The Python process is short-lived (spawned per verification, not a long-running
  daemon).
- The `bio_key` is passed via stdout and consumed immediately — it is never
  written to disk by the Dart side.
- The vault folder itself can be protected with OS-level encryption (BitLocker,
  VeraCrypt) as a defense-in-depth layer.

**Important:** If an attacker has compromised the Python scripts, the webcam,
or any other component on the user's machine, they already have **physical
access** to the device. Physical access is a threat model boundary that no
software-only vault can fully solve — at that level, the attacker could also
install a keylogger, modify the running application, or extract data from
memory. The appropriate defense at this layer is OS-level full-disk encryption
(BitLocker, VeraCrypt) combined with a strong boot PIN, which protects the
vault folder even if the machine is powered off.

---

## What We Don't Do (and Why)

| Feature | Status | Rationale |
|---|---|---|
| Account lockout / cooldown | Not implemented | Offline single-user tool; PBKDF2 + webcam cost is the throttle |
| Key stretching beyond PBKDF2 | AES-256-GCM is the cipher | PBKDF2 at 120k iterations is sufficient for passphrase-derived keys in a local threat model |
| Secure enclave / TPM integration | Not yet | Requires platform-specific native code; planned for future |
| Two-person recovery | Not implemented | Single-user design; recovery is passphrase + biometrics |
| Physical access protection | OS-level responsibility | If an attacker has local file access, full-disk encryption (BitLocker/VeraCrypt) is the correct defense layer — not the vault app

---

## Reporting Security Issues

If you discover a vulnerability, please report it privately via
[GitHub Security Advisories](https://github.com/CraftedWebPro/vault-os/security/advisories/new)
or by contacting the maintainer on Instagram
[@riki_vivek](https://instagram.com/riki_vivek).

Please do **not** open a public issue for security vulnerabilities.

---

## Changes

| Date | Change |
|---|---|
| 2026-07-17 | Initial security model documentation |
