import Foundation
import GestureCore
import Runtime

setvbuf(stdout, nil, _IOLBF, 0)

let usage = """
hof: developer tool for Hand of Freedom

  hof log [--seconds N] [--raw] [--config file]
      Print trackpad frames and what the engine would do. Posts nothing; needs no permission.
  hof record [--guided | --seconds N] [--inactive] [--config file] out.hoftrace.jsonl
      Record raw frames and engine decisions to a trace. Posts nothing. --guided prompts through
      a one-minute calibration session and marks each gesture in the trace.
  hof replay [--stats | --trace] [--config file] [--sens N] file.hoftrace.jsonl
      Re-run a trace through the engine. --stats prints frame-rate, thread and lift-phase facts
      and contact-size distributions; --trace prints per-frame engine internals.
  hof live [--any-app] [--sens N] [--config file] [--no-tap] [--record out.hoftrace.jsonl] [--seconds N]
      Drive the game from this terminal. Developer-only: uses this terminal's Accessibility and
      Input Monitoring permissions.
  hof permissions [--request]
      Show which privacy grants this process has. --request shows the system prompts for missing ones.
  hof probe [--force]
      Move the pointer one pixel and back through the injector and wait for the event to come back.
      Needs Accessibility to post and Input Monitoring to hear the echo. --force tries regardless.
  hof check [--request] [--out report.txt]
      Permission isolation report: preflight results, whether the event gate installs, and whether
      posted input arrives. Run it from the app bundle (Scripts/bundle.sh).
  hof config
      Print the default engine configuration as JSON, a starting point for --config.
"""

@MainActor func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { print(usage); exit(2) }
    do {
        let options = try Options(Array(args.dropFirst()))
        switch command {
        case "log": try logCommand(options)
        case "record": try recordCommand(options)
        case "replay": try replayCommand(options)
        case "live": try liveCommand(options)
        case "permissions": permissionsCommand(options)
        case "probe": runAsync { await probeCommand(options) }
        case "check": runAsync { await checkCommand(options) }
        case "config":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(EngineConfig.default), as: UTF8.self))
        case "help", "-h", "--help": print(usage)
        default:
            print(usage)
            exit(2)
        }
    } catch {
        FileHandle.standardError.write(Data("hof: \(error)\n".utf8))
        exit(1)
    }
}

/// Runs an async command on the main actor with the run loop going, then exits.
@MainActor func runAsync(_ body: @escaping @MainActor () async -> Void) -> Never {
    Task { @MainActor in
        await body()
        exit(0)
    }
    CFRunLoopRun()
    exit(0)
}

main()
