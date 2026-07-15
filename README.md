<p align="center">
  <img src="assets/images/banner.png" alt="Vault OS banner" width="100%" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/built%20with-Flutter-46c3f7" alt="Built With" />
  <img src="https://img.shields.io/badge/biometric-Python%20%2B%20OpenCV-gold" alt="Biometric Bridge" />
  <img src="https://img.shields.io/badge/status-active-2ea043" alt="Status" />
  <img src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-orange" alt="License" />
</p>

<p align="center">
  A local-first, hidden vault for Windows — unlocked by your passphrase, your face, your blink, and a gesture only you know.<br />
  No cloud. No account. No "we value your privacy" email six months before a breach notice.
</p>

<p align="center">
  <a href="https://github.com/CraftedWebPro/vault-os/releases">
    <img src="https://img.shields.io/badge/download-VaultOS%20Installer-blueviolet?style=for-the-badge" alt="Download Installer" />
  </a>
</p>

---

## Table of Contents

- [Why I Made This](#why-i-made-this)
- [What Vault OS Does](#what-vault-os-does)
- [How It Works](#how-it-works)
- [Screenshots](#screenshots)
- [Current Stack](#current-stack)
- [Current Platform](#current-platform)
- [Releases](#releases)
- [Project Setup](#project-setup)
- [First-Time Use](#first-time-use)
- [Importing Files](#importing-files)
- [Recovery / Rescan](#recovery--rescan)
- [Important Notes](#important-notes)
- [Troubleshooting](#troubleshooting)
- [Repo Notes](#repo-notes)
- [Folder Overview](#folder-overview)
- [Support](#support)
- [License](#license)

---

## Why I Made This

I first made Vault OS for myself. I wanted somewhere to put files I didn't want syncing to a server I don't control, and every "private" cloud tool I found still wanted an account, an internet connection, or my trust — usually all three.

I wanted something that:

- stays local
- works without internet
- does not need an account
- feels private
- does not depend on cloud syncing

I didn't want another app asking me to sign up before it would let me hide my own files on my own computer. So I built the thing I actually wanted: a vault that lives on my machine, opens for my face and nobody else's (well — mostly, see the [Face Scan](#screenshots) notes below), and doesn't care whether the internet exists.

Then I figured, if I already wanted this badly enough to build it, someone else probably does too. So here it is.

## What Vault OS Does

Vault OS helps you:

- create one or more hidden vaults
- unlock them with a passphrase **and** biometrics — face, blink, gesture
- import files into a working vault space
- lock everything back into encrypted storage when you're done
- switch between multiple vaults
- rescan and recover a vault if the app's local state ever goes missing
- change your passphrase, refresh biometrics, and manage wallpapers from settings

Basically: your files disappear into a folder that looks like nothing, and only open back up for you.

## How It Works

Each vault stores:

- encrypted file blobs
- encrypted registry data
- encrypted biometric profile data
- recovery info needed to reconnect the vault later

**Unlock flow**

1. Choose a vault
2. Enter the passphrase
3. Complete face verification
4. Blink twice
5. Hold the enrolled hand gesture
6. Vault workspace opens

**Lock flow**

1. Workspace contents get packed back into the vault
2. Metadata is updated
3. The unlocked workspace is wiped clean

No half-open state hanging around — it's either sealed or it's open, nothing in between.

## Screenshots

I'll keep adding screenshots here as the app grows.

### Theme Collection

Theme picker with built-in wallpaper options.

![Theme Collection](assets/screenshots/themes-collection.webp)

### Biometric Scan

Live face and hand verification, side by side — the app checks your face, waits for a double blink, then reads your enrolled hand gesture, all in one webcam session.

![Biometric Scan](assets/screenshots/biometric-scan.webp)

### Vault Home

Main vault workspace with file library, details, and actions.

![Vault Home](assets/screenshots/vault-home.webp)

### Settings

Settings screen for wallpapers, security, recovery, and vault tools.

![Settings](assets/screenshots/settings.webp)

## Current Stack

- Flutter
- Dart
- Python
- OpenCV
- MediaPipe
- ONNX Runtime
- Windows desktop runner

## Current Platform

- Windows — supported now
- macOS — not done yet

If you want a macOS version too, message me on Instagram: **[@riki_vivek](https://instagram.com/riki_vivek)**
If enough people want it, I'll build it.

## Releases

**Easiest way to get Vault OS:** Download the installer from [GitHub Releases](https://github.com/CraftedWebPro/vault-os/releases).

Just run `VaultOS-Setup.exe`, follow the prompts, and you're done. The installer handles everything — Python packages, model files, shortcuts, the works. No terminal commands, no manual setup, no "wait, which folder was it?"

If you don't want to set up Flutter and Python by hand, this is the path for you. Click, install, done.

For the adventurous folks who want to run from source or poke around the code, keep reading below.

### Why is the installer ~250 MB?

No, we didn't accidentally bundle a game engine. The installer ships with three AI models — one for your face, one for your hand, and one for confirming it's actually you and not a poster of you. These things aren't exactly featherweight. But hey, at least none of them are crypto miners. That's more than most "free" software can say.

## Project Setup

**Don't want to do any of this?** Just grab the installer from [Releases](https://github.com/CraftedWebPro/vault-os/releases) and skip the rest of this page.

For the rest of you — running from source takes a few steps — none of them hard, just sequential. Follow them in order and you'll be fine.

### 1. Install Flutter

Install Flutter for Windows:

- [Flutter Windows install guide](https://docs.flutter.dev/get-started/install/windows)

Then make sure this works:

```powershell
flutter --version
```

### 2. Enable Windows Desktop Support

```powershell
flutter config --enable-windows-desktop
flutter doctor
```

### 3. Install Visual Studio Build Tools

For Flutter Windows apps, you need Visual Studio with the **Desktop development with C++** workload.

If `flutter doctor` complains about the Windows toolchain, fix that first — everything downstream depends on it.

### 4. Install Python

Install Python 3.10 or newer:

- [Python downloads](https://www.python.org/downloads/windows/)

During install, turn on:

- `Add Python to PATH`

Then check:

```powershell
python --version
```

### 5. Clone The Project

```powershell
git clone https://github.com/CraftedWebPro/vault-os.git
cd vault-os
```

### 6. Install Flutter Packages

```powershell
flutter pub get
```

### 7. Install Python Packages

```powershell
cd python_service
pip install -r requirements.txt
cd ..
```

### 8. Add The Required Model Files

Place these files inside:

```text
python_service/models/
```

Required files:

- `face_landmarker.task`
- `hand_landmarker.task`
- `face_embedding.onnx`

The face embedding model handles:

- face alignment
- embedding extraction
- cosine similarity matching

One example source used for the face model:

- [OpenVINO ArcFace ONNX model](https://storage.openvinotoolkit.org/repositories/open_model_zoo/public/2022.1/face-recognition-resnet100-arcface-onnx/arcfaceresnet100-8.onnx)

After downloading, rename it to:

```text
face_embedding.onnx
```

These three files aren't in the repo on purpose — they're large, and everyone's setup should point at a model they've actually checked the license on. See [Repo Notes](#repo-notes) for why.

### 9. Run The App

From the project root:

```powershell
flutter run -d windows
```

If it opens and asks you to create a vault, you did it right.

## First-Time Use

1. Open the app
2. Create a vault name
3. Choose a parent folder
4. Continue to security
5. Set a master passphrase
6. Start webcam enrollment or Webcam app of your phone on same wifi (eg:Iriun Webcam)
7. Align your face
8. Blink twice
9. Hold your chosen gesture
10. Vault opens

Ten steps sounds like a lot written out, but it's about ninety seconds in practice — most of that is just holding still for the webcam.

## Importing Files

You can add files by:

- drag and drop
- `Add Files`
- `Import Files`

Files go into the unlocked workspace first, then back into encrypted storage the moment you lock the vault.

## Recovery / Rescan

If the local app state is lost but your vault folders still exist on disk:

1. open the app
2. choose recovery / rescan
3. select the folder to scan

You can also do this later from Settings, if you're not in the middle of a small panic.

## Important Notes

Read this part. Genuinely.

- deleting app state does **not** automatically delete your vault data
- deleting the actual vault folder **does** destroy the data — no undo, no recycle bin, no second chance
- renaming or manually editing vault files can break unlock or recovery
- this app protects privacy, but it cannot bring files back if the vault folder itself is gone

Basically: the app is forgiving about its own state, but not about you deleting the vault folder directly. Treat that folder the way you'd treat the only copy of something important — because it is.

## Troubleshooting

### Those error messages are intentional

If the app throws an error in your face during unlock — wrong passphrase, face not recognized, blink missed, gesture drifted — that's not a crash. That's the vault doing its job.

Vault OS is built to be paranoid on purpose. It would rather reject you ten times than let the wrong person in once. So if you see a red error box, read it, fix whatever it's complaining about, and try again. The app isn't broken. It's just... careful.

Think of it like a bouncer who actually checks IDs.

### Python not found

If you're running from source, make sure this works:

```powershell
python --version
```

**Using the installer?** The installer will warn you if Python is missing. You can still install Vault OS, but biometric features won't work until you install Python from [python.org](https://www.python.org/downloads/windows/) and add it to PATH.

### Webcam not working

Check these:

- webcam isn't being used by another app (yes, that video call you forgot to close)
- Python dependencies are installed
- all required model files are present inside `python_service/models/`

### File picker or native window changes not updating

Do a full restart:

```powershell
flutter clean
flutter pub get
flutter run -d windows
```

### Recovery does not find the vault

- choose the exact vault folder, or its parent folder
- make sure the vault files still exist on disk

## Repo Notes

This repo does not track local-only folders and big runtime files such as:

- `md_files/`
- `python_service/models/`
- Python cache files

That's on purpose, so the repo stays clean and nobody accidentally commits a 90MB face recognition model.

## Folder Overview

- `lib/` → Flutter UI, controllers, services, models
- `python_service/` → biometric service and model integration
- `assets/themes/` → wallpapers
- `assets/images/` → logos and static images
- `assets/json/` → lottie and animation files

## Support

If you like the project, use it, test it, or share it — that's genuinely all the support I need.

If you want to reach me:

- Instagram: **[@riki_vivek](https://instagram.com/riki_vivek)**

## License

This project is licensed under the **PolyForm Noncommercial License 1.0.0**.

So people can use it, learn from it, and modify it for non-commercial use. Just don't turn it into a business and start selling my vault's gym homework.

See [LICENSE](LICENSE) for full details.