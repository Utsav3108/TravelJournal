---
name: verify-apple-api
description: Use before writing code against an Apple framework API (especially new or Apple Intelligence APIs such as FoundationModels, Speech, Translation) to confirm it exists, its availability, and whether it is deprecated in the installed SDK.
---

# Verify an Apple API against the installed SDK

Do not answer from memory; the SDK on this machine is newer than most documentation.

1. Find the SDK: `SDK=$(xcrun --sdk macosx --show-sdk-path)` (use `--sdk iphoneos` for iOS-only APIs).
2. Find the interface: `$SDK/System/Library/Frameworks/<Name>.framework/Modules/<Name>.swiftmodule/arm64e-apple-macos.swiftinterface`. Objective-C APIs are in `<Name>.framework/Headers/*.h`. Underscore-prefixed frameworks (`_Foo`) are not public API.
3. `grep -n` for the type or function. Read the lines around it for the `@available(...)` annotations, `deprecated` messages and replacements. Example: `AVAudioNode.installTap(onBus:...)` without `error:` is deprecated in macOS 27; use the throwing variant.
4. Compile a small call to prove the signature; the build is the final check.
5. In your answer, say which APIs you verified in the SDK and which come from memory, and note availability limits (OS version, Apple Intelligence required, on-device vs cloud). `PrivateCloudComputeLanguageModel` is Apple's cloud model, not on-device.
