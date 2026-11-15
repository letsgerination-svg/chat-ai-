# Native iOS application

This directory contains the native iOS foundation. The existing repository root is a React/Rspack web application and does not produce an IPA.

## Implemented foundation

- `Package.swift`: Swift Package Manager module and XCTest target.
- `ChatProvider.swift`: provider-neutral message types and streaming provider contract.
- `ProviderRouter.swift`: explicit Automatic, Offline only, and Online only routing.
- `ConversationStore.swift`: JSON conversation history stored in the app sandbox with atomic writes.
- `Tests/HybridChatCoreTests`: routing and local-history tests.
- `.github/workflows/ios-core-tests.yml`: macOS GitHub Actions workflow for `swift test --package-path ios`.

## Next implementation layers

1. SwiftUI app target and app lifecycle.
2. Network reachability monitor and deterministic provider routing integration.
3. Remote DeepSeek adapter with credentials stored in iOS Keychain.
4. Local model runtime adapter backed by llama.cpp with Metal.
5. Model download/storage manager and model selection UI.
6. UI integration, Russian localization, device testing, and signed IPA archive.

## Build environment and verification

A real iOS app target, Xcode project, Apple signing configuration, and macOS/Xcode build environment are required to create and sign an IPA. The Swift package is designed to be checked independently with Swift Package Manager.

The repository changes have not yet been compiled in this environment. The GitHub Actions workflow is intended to provide the first reproducible Swift build/test result; a green result must be observed before treating the core as verified.

## Privacy invariants

- The local provider processes prompts and conversation history on-device.
- Conversation history is persisted locally in the app sandbox.
- Local history is never uploaded automatically when switching to the online provider.
- API credentials must be stored in Keychain, never hard-coded into the app bundle.
