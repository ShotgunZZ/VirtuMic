import Foundation

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

let signalCallback: sig_t = { _ in
    daemon.stop()
    exit(0)
}
signal(SIGINT, signalCallback)
signal(SIGTERM, signalCallback)

do {
    try daemon.start()
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

// Keep the process alive
dispatchMain()
