import ArgumentParser

@main
struct DigaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diga",
        abstract: "On-device neural text-to-speech — a drop-in replacement for /usr/bin/say.",
        version: "diga \(DigaVersion.current)"
    )

    func run() throws {
        // No arguments provided — print usage and exit.
        // ArgumentParser handles this automatically when no subcommands
        // or required arguments are defined, but since we have none yet,
        // we print help explicitly.
        throw CleanExit.helpRequest(self)
    }
}
