# Flutter + Android Studio — Windows Install Checklist

Easiest path: let the VS Code Flutter extension download the SDK and set your PATH automatically.
Tick each box as you go. If anything errors, paste the message to Claude Code — it can fix most of it.

## A. Android Studio
- [ ] Download Android Studio from https://developer.android.com/studio and run the installer (defaults).
- [ ] Launch it; let the **Setup Wizard** finish the "Standard" install (this pulls the core Android SDK).

## B. Flutter SDK (via VS Code)
- [ ] Confirm **Git for Windows** and **VS Code** are installed.
- [ ] In VS Code: Extensions panel → search **Flutter** → Install (Dart comes with it).
- [ ] Ctrl+Shift+P → `Flutter` → **Flutter: New Project**.
- [ ] When prompted for the SDK, click **Download SDK** → choose `C:\dev` (no spaces, not OneDrive) → **Clone Flutter**.
- [ ] When asked **"Add the Flutter SDK to PATH?"** → click **Add SDK to PATH**.
- [ ] Close and reopen **VS Code** and all **PowerShell** windows so PATH updates.

## C. Android SDK components (in Android Studio → Tools → SDK Manager)
- [ ] **SDK Platforms** tab → tick **Android API 35** (or whatever `flutter doctor` names later).
- [ ] **SDK Tools** tab → tick: **Command-line Tools**, **Build-Tools**, **Platform-Tools**, **Android Emulator**.
- [ ] Click **Apply → OK** and let them install.

## D. Emulator (phone on screen)
- [ ] Tools → **Device Manager** → **Create Device**.
- [ ] Pick a phone (e.g. Pixel 7) → Next → choose an **x86 system image** (download if needed) → Next.
- [ ] **Show Advanced Settings** → **Graphics: Hardware - GLES 2.0** → **Finish**.
- [ ] Press **▶ Run** next to the device to boot it.

## E. Licenses + verify (PowerShell)
- [ ] `flutter doctor --android-licenses` → type `y` to accept each.
- [ ] `flutter doctor` → green checks for **Flutter**, **Android toolchain**, **Android Studio**, **VS Code**, **Connected device**.

## What's OK to ignore for now
- `[!] Chrome` — only needed for the web build (matters from Phase 2+); install Chrome later.
- `[!] Visual Studio - develop Windows apps` — only for a Windows desktop build, which you're not doing.

## If flutter doctor shows a red X
- Run `flutter doctor -v` for detail.
- Common fixes: re-run `flutter doctor --android-licenses`; reopen the terminal so PATH refreshes;
  a missing SDK component — go back to step C.
- Or paste the full output to Claude Code and ask it to walk you through the fix.
