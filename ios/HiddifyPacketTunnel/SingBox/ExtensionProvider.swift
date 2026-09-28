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

    override open func startTunnel(options: [String: NSObject]?) async throws {
        // Clear previous logs
        try? FileManager.default.removeItem(at: ExtensionProvider.errorFile)
        try? FileManager.default.removeItem(at: FilePath.workingDirectory.appendingPathComponent("TestLog"))
        
        do {
            writeMessage("(packet-tunnel) starting")
            
            // Extract options with better error handling
            let disableMemoryLimit = false && (options?["DisableMemoryLimit"] as? NSString as? String ?? "NO") == "YES" 
            let grpcServiceModePort = (options?["GrpcServiceModePort"] as? NSNumber)?.intValue ?? 17079
            
            let config = options?["Config"] as? NSString as? String ?? ""
            
            // guard let config = SingBox.setupConfig(config: config2) else {
            //             writeFatalError("(packet-tunnel) error: config is invalid")
            //             return
            // }
//            self.config = config

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
            // Libcore 3.1.8: MobileSetup(base, working, temp, mode, listen, secret, debug, &error)
            var setupError: NSError?
            let listen = "127.0.0.1:\(grpcServiceModePort)"
            let setupOK = MobileSetup(
                sharedDir,
                workDir,
                cacheDir,
                4,
                listen,
                "",
                false,
                &setupError
            )
            if let setupError {
                throw setupError
            }
            if !setupOK {
                throw NSError(domain: "MobileSetup", code: 0, userInfo: [NSLocalizedDescriptionKey: "MobileSetup failed"])
            }
            
            
            LibboxSetMemoryLimit(!disableMemoryLimit)
            
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
            sharedDir,
            workDir,
            cacheDir,
            4,
            listen,
            "",
            false,
            configContent,
            configPath,
            platformInterface,
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
//        reasserting = true
//        defer { reasserting = false }
//        
//        stopService()
//        do {
//            guard let config = try? String(contentsOf: FilePath.configFile) else {
//                writeFatalError("(packet-tunnel) error: cannot read config file")
//                return
//            }
//            try await startService(config)
//        } catch {
//            writeFatalError("(packet-tunnel) error: reload service: \(error.localizedDescription)")
//        }
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
