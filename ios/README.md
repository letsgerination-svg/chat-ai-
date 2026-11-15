# Native iOS application

This directory contains the native iOS foundation and the first SwiftUI app shell. The original repository root remains a React/Rspack web application.

## Implemented

- `Package.swift`: Swift Package Manager core module and XCTest target.
- `ChatProvider.swift`: provider-neutral messages, streaming contract, and chat modes.
- `ProviderRouter.swift`: Automatic, Offline only, and Online only routing.
- `ConversationStore.swift`: local JSON history with atomic writes.
- `KeychainAPIKeyStore.swift`: API credential storage in iOS Keychain.
- `DeepSeekChatProvider.swift`: streaming DeepSeek Chat Completions adapter.
- `NetworkStatusMonitor.swift`: native Network framework reachability monitor.
- `LlamaRuntime`: linked to the official `llama.cpp` b12387 Apple XCFramework, including the Metal backend; provides a local GGUF inference provider and on-demand Qwen3 model download.
- `App/HybridChatApp.swift`: initial Russian SwiftUI chat screen, mode selector, local history, and API-key settings.
- `project.yml`: XcodeGen specification for the iOS app target.
- `Tests/HybridChatCoreTests`: routing and persistence tests.
- `.github/workflows/ios-core-tests.yml`: Swift package build and tests.
- `.github/workflows/ios-app-build.yml`: generates the Xcode project, builds for the iOS device SDK, archives the app without signing, packages an unsigned IPA, and uploads it as a GitHub Actions artifact.

## Current limitations

- The llama.cpp adapter and model downloader are implemented in source. A complete simulator/device build and real-device inference still need to pass verification before offline generation can be considered proven.
- The app can use DeepSeek after the user adds their own API key in Settings. The key is kept in Keychain and is not bundled into the app.
- The current history UI opens the most recent conversation; a multi-conversation sidebar/list is still pending.
- CI can package an unsigned IPA for inspection and later signing. An unsigned IPA cannot be installed directly on a standard iPhone; installation requires valid Apple signing and provisioning.

## Next steps

1. Confirm the Xcode Simulator build is green and fix any compiler issues.
2. Implement the Swift adapter over the linked llama.cpp C API, then load and run a local GGUF model with Metal.
3. Verify Qwen GGUF download, model loading, memory use, and inference on the iPhone.
4. Add multi-chat history, cancellation, and improved error handling.
5. Configure Apple signing and provisioning, then export and test an installable IPA on a physical iPhone.

## Model and licensing

The app offers a user-initiated download of Qwen3 1.7B Q4_K_M (approximately 1.28 GB) from the ggml-org Hugging Face repository. The model is not bundled in the IPA. Third-party notices are included in `THIRD_PARTY_NOTICES.md` and copied into the app bundle.

## Privacy invariants

- Conversation history is stored in the app sandbox.
- DeepSeek receives messages only when an online provider is selected and a request is sent.
- Switching modes does not automatically upload stored local history.
- API credentials are stored in Keychain, never hard-coded into the app bundle.
