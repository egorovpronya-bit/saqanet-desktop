import Foundation
import Libcore
import NetworkExtension
import os.log

open class ExtensionProvider: NEPacketTunnelProvider {
    public static let errorFile = FilePath.workingDirectory.appendingPathComponent("network_extension_error.log")
    private let logger = Logger(subsystem: "apple.hiddify.com.HiddifyPacketTunnel", category: "PacketTunnel")
    
//    private var commandServer: LibboxCommandServer!
    private var systemProxyAvailable = false
    private var systemProxyEnabled = false
    private var platformInterface: ExtensionPlatformInterface!
    private var config: String!

    // Saved so reloadService() can restart the core with the same params the
    // OS-driven startTunnel() used, without the app having to pass options again.
    private var lastSharedDir: String!
    private var lastWorkDir: String!
    private var lastCacheDir: String!
    private var lastListen: String!

    override open func startTunnel(options: [String: NSObject]?) async throws {
        // Clear previous logs
        try? FileManager.default.removeItem(at: ExtensionProvider.errorFile)
        try? FileManager.default.removeItem(at: FilePath.workingDirectory.appendingPathComponent("TestLog"))
        
        do {
            writeMessage("(packet-tunnel) starting")
            
            // Extract options with better error handling
            let disableMemoryLimit = (options?["DisableMemoryLimit"] as? NSString as? String ?? "NO") == "YES"
            let grpcServiceModePort = (options?["GrpcServiceModePort"] as? NSNumber)?.intValue ?? 17079

            var config = options?["Config"] as? NSString as? String ?? ""
            if !config.isEmpty {
                try? config.write(to: FilePath.configFile, atomically: true, encoding: .utf8)
            } else {
                // iOS restarted the extension itself (sleep, network change, on-demand) without
                // the app re-passing options - options["Config"] is empty in that case. Fall back
                // to the last config the app handed us, instead of starting with an empty config.
                config = (try? String(contentsOf: FilePath.configFile, encoding: .utf8)) ?? ""
                if !config.isEmpty {
                    writeMessage("(packet-tunnel) options had no config, restored saved config from disk")
                }
            }
            self.config = config

            do {
                try FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
            } catch {
                writeFatalError("(packet-tunnel) error: create working directory: \(error.localizedDescription)")
                return
            }
            
            // Ensure directories exist
            try createRequiredDirectories()
            
            // Log directory paths for debugging
            let sharedDir = FilePath.sharedDirectory.relativePath
            let workDir = FilePath.workingDirectory.relativePath
            let cacheDir = FilePath.cacheDirectory.relativePath
            if platformInterface == nil {
                platformInterface = ExtensionPlatformInterface(self)
            }
            // Libcore 4.1.0: MobileSetup(opt: MobileSetupOptions, platformInterface, &error)
            var setupError: NSError?
            let listen = "127.0.0.1:\(grpcServiceModePort)"
            let setupOptions = MobileSetupOptions()
            setupOptions.basePath = sharedDir
            setupOptions.workingDir = workDir
            setupOptions.tempDir = cacheDir
            setupOptions.listen = listen
            setupOptions.secret = ""
            setupOptions.debug = false
            setupOptions.mode = 4
            setupOptions.fixAndroidStack = false
            let setupOK = MobileSetup(
                setupOptions,
                platformInterface,
                &setupError
            )
            if let setupError {
                throw setupError
            }
            if !setupOK {
                throw NSError(domain: "MobileSetup", code: 0, userInfo: [NSLocalizedDescriptionKey: "MobileSetup failed"])
            }
            
            
            LibboxSetMemoryLimit(!disableMemoryLimit)

            lastSharedDir = sharedDir
            lastWorkDir = workDir
            lastCacheDir = cacheDir
            lastListen = listen

            writeMessage("(packet-tunnel) setup completed successfully")
            try await startService1(config, sharedDir: sharedDir, workDir: workDir, cacheDir: cacheDir, listen: listen)


        } catch {
            logger.error("Tunnel setup failed: \(error.localizedDescription)")
            writeFatalError("(packet-tunnel) setup failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func startService1(_ config: String, sharedDir: String, workDir: String, cacheDir: String, listen: String) async throws {
        writeMessage("Starting service")
        var error: NSError?
        let configPath = FileManager.default.fileExists(atPath: config) ? config : ""
        let configContent = configPath.isEmpty ? config : ""
        let started = MobileStart(
            configPath,
            configContent,
            &error
        )
        if let error {
            writeFatalError("(packet-tunnel) error: start service: \(error.localizedDescription)")
            throw error
        }
        if !started {
            let failed = NSError(domain: "MobileStart", code: 0, userInfo: [NSLocalizedDescriptionKey: "MobileStart failed"])
            writeFatalError("(packet-tunnel) error: start service: \(failed.localizedDescription)")
            throw failed
        }
        writeMessage("(packet-tunnel) service started successfully")
    }
    
    private func createRequiredDirectories() throws {
        let directories = [
            FilePath.workingDirectory,
            FilePath.sharedDirectory,
            FilePath.cacheDirectory
        ]
        
        for directory in directories {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                logger.error("Failed to create directory at \(directory.path): \(error.localizedDescription)")
                throw error
            }
        }
    }
    
    func writeMessage(_ message: String) {
        logger.debug("\(message)")
        writeError(message)
    }
    
    func writeError(_ message: String) {
        let messageWithNewline = "[\(Date())] \(message)\n"
        do {
            if FileManager.default.fileExists(atPath: ExtensionProvider.errorFile.path) {
                if let fileHandle = try? FileHandle(forWritingTo: ExtensionProvider.errorFile) {
                    defer { fileHandle.closeFile() }
                    fileHandle.seekToEndOfFile()
                    if let data = messageWithNewline.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                }
            } else {
                try messageWithNewline.write(to: ExtensionProvider.errorFile, atomically: true, encoding: .utf8)
            }
        } catch {
            logger.error("Failed to write to error file: \(error.localizedDescription)")
        }
    }
    
    public func writeFatalError(_ message: String) {
        logger.fault("Fatal error: \(message)")
        writeError("FATAL: \(message)")
        cancelTunnelWithError(NSError(domain: "ExtensionProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: message]))
    }
    
    override open func stopTunnel(with reason: NEProviderStopReason) async {
//        logger.debug("Stopping tunnel with reason: \(reason)")
        writeMessage("(packet-tunnel) stopping, reason: \(reason)")
        stopService()
        
//        // Allow time for cleanup
//        try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
//        
//        if let server = commandServer {
//            try? server.close()
//            commandServer = nil
//        }
    }
    
    private func stopService() {
        logger.debug("Stopping service")
        var stopError: NSError?
        MobileStop(&stopError)
        if let platformInterface {
            platformInterface.reset()
        }
    }
    
    func reloadService() async {
        logger.debug("Reloading service")
        writeMessage("(packet-tunnel) reloading service")

        guard let sharedDir = lastSharedDir, let workDir = lastWorkDir,
              let cacheDir = lastCacheDir, let listen = lastListen else {
            writeFatalError("(packet-tunnel) error: reload requested before first start, nothing to reload")
            return
        }
        guard let config = try? String(contentsOf: FilePath.configFile, encoding: .utf8), !config.isEmpty else {
            writeFatalError("(packet-tunnel) error: cannot read saved config file for reload")
            return
        }

        reasserting = true
        defer { reasserting = false }

        stopService()
        do {
            try await startService1(config, sharedDir: sharedDir, workDir: workDir, cacheDir: cacheDir, listen: listen)
        } catch {
            writeFatalError("(packet-tunnel) error: reload service: \(error.localizedDescription)")
        }
    }
    
    override open func handleAppMessage(_ messageData: Data) async -> Data? {
        logger.debug("Handling app message")
        return messageData
    }
    
    override open func sleep() async {
        logger.debug("Entering sleep mode")
//        MobilePause()
        // Add any sleep mode handling if needed
    }
    
    override open func wake() {
        logger.debug("Waking from sleep")
    }
}

// Extension to support error handling
extension ExtensionProvider {
    enum ExtensionError: Error {
        case configurationMissing
        case directoryCreationFailed
        case serviceStartFailed
        
        var localizedDescription: String {
            switch self {
            case .configurationMissing:
                return "Configuration not provided"
            case .directoryCreationFailed:
                return "Failed to create required directories"
            case .serviceStartFailed:
                return "Failed to start the service"
            }
        }
    }
}
