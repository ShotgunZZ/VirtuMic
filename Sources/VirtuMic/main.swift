import Foundation

// Ensure output is not buffered
setbuf(stdout, nil)
setbuf(stderr, nil)

// MARK: - Parse arguments

let configPath: String
if let configIdx = CommandLine.arguments.firstIndex(of: "--config"),
   configIdx + 1 < CommandLine.arguments.count {
    configPath = CommandLine.arguments[configIdx + 1]
} else {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    configPath = "\(home)/.config/virtual-mic/config.json"
}

// MARK: - Load and validate config

let config: AudioConfig
do {
    print("Loading config from: \(configPath)")
    config = try AudioConfig.load(from: configPath)
    try config.validate()
    print("Config loaded successfully.")
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// MARK: - Start daemon

let daemon = AudioDaemon(config: config)

// MARK: - Signal handling for clean shutdown

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)

let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigintSource.setEventHandler { daemon.stop(); exit(0) }
sigtermSource.setEventHandler { daemon.stop(); exit(0) }
sigintSource.resume()
sigtermSource.resume()

do {
    try daemon.start()
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// Keep the process alive
dispatchMain()
