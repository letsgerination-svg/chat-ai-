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
- `LlamaRuntime`: linked to the official `llama.cpp` b12387 Apple XCFramework, including the Metal backend.
- `App/HybridChatApp.swift`: initial Russian SwiftUI chat screen, mode selector, local history, and API-key settings.
- `project.yml`: XcodeGen specification for the iOS app target.
- `Tests/HybridChatCoreTests`: routing and persistence tests.
- `.github/workflows/ios-core-tests.yml`: Swift package build and tests.
- `.github/workflows/ios-app-build.yml`: generated Xcode project and iOS Simulator build.

## Current limitations

- The official llama.cpp XCFramework is pinned and linked, but the Swift model-loading/token-generation adapter and GGUF model manager are not implemented yet. Offline generation is not available in the app at this stage.
- The app can use DeepSeek after the user adds their own API key in Settings. The key is kept in Keychain and is not bundled into the app.
- The current history UI opens the most recent conversation; a multi-conversation sidebar/list is still pending.
- The current simulator workflow verifies compilation only. It does not create a signed IPA.

## Next steps

1. Confirm the Xcode Simulator build is green and fix any compiler issues.
2. Implement the Swift adapter over the linked llama.cpp C API, then load and run a local GGUF model with Metal.
3. Add model download/storage controls and model selection.
4. Add multi-chat history, cancellation, and improved error handling.
5. Configure Apple signing and produce a distributable IPA.

## Privacy invariants

- Conversation history is stored in the app sandbox.
- DeepSeek receives messages only when an online provider is selected and a request is sent.
- Switching modes does not automatically upload stored local history.
- API credentials are stored in Keychain, never hard-coded into the app bundle.
