import Foundation
import LlamaFramework

/// Confirms that the official llama.cpp Apple XCFramework is linked.
/// The model-loading and token-generation adapter is implemented in the next layer.
public enum LlamaRuntimeBuildInfo {
    public static let version = "b12387"
    public static let metalBackendIncluded = true
}
