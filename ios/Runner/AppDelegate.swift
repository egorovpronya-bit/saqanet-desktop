import UIKit
import Flutter
import Libcore
import Sentry
@main
@objc class AppDelegate: FlutterAppDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // On real iOS devices (few CPU cores), goroutines inside Libcore that make
        // blocking native calls can exhaust GOMAXPROCS OS threads, starving the
        // goroutine that Serve()s the gRPC listener - it never gets scheduled, so
        // sayHello() times out even though the port is open. Simulators/Macs have
        // enough cores that this doesn't surface. Go's runtime reads GOMAXPROCS
        // from the environment at startup, so raise it before any Go code runs.
        // See: https://github.com/golang/go/issues/65603
        setenv("GOMAXPROCS", "16", 1)
        setupFileManager()
        registerHandlers()
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    func setupFileManager() {
        try? FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
        FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
    }
    
    func registerHandlers() {
        MethodHandler.register(with: self.registrar(forPlugin: MethodHandler.name)!)
        PlatformMethodHandler.register(with: self.registrar(forPlugin: PlatformMethodHandler.name)!)
        FileMethodHandler.register(with: self.registrar(forPlugin: FileMethodHandler.name)!)
        StatusEventHandler.register(with: self.registrar(forPlugin: StatusEventHandler.name)!)
        AlertsEventHandler.register(with: self.registrar(forPlugin: AlertsEventHandler.name)!)
//        LogsEventHandler.register(with: self.registrar(forPlugin: LogsEventHandler.name)!)
//        GroupsEventHandler.register(with: self.registrar(forPlugin: GroupsEventHandler.name)!)
//        ActiveGroupsEventHandler.register(with: self.registrar(forPlugin: ActiveGroupsEventHandler.name)!)
//        StatsEventHandler.register(with: self.registrar(forPlugin: StatsEventHandler.name)!)
    }
}

