// Keeps the host app alive while the schema probe runs, and says how it
// went. Only when asked: TEND_SCHEMA_PROBE=1 in the host's environment,
// on a development-signed run against the real store — which is what
// `xcodebuild test -destination 'id=<this Mac>'` gives on Apple silicon.

import Foundation
import Testing
@testable import Tend

struct SchemaProbeTests {
    @Test("the probe writes every record type to CloudKit Development and cleans up", .enabled(if: SchemaProbe.asked))
    func materialise() async throws {
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            let outcome = await SchemaProbe.outcome
            switch outcome {
            case .exported:
                let log = await SchemaProbe.log
                print("SCHEMA PROBE OK\n\(log.joined(separator: "\n"))")
                return
            case .failed(let why):
                let log = await SchemaProbe.log
                Issue.record("schema probe failed: \(why)\n\(log.joined(separator: "\n"))")
                return
            case .notAsked, .running:
                try await Task.sleep(for: .seconds(2))
            }
        }
        let log = await SchemaProbe.log
        Issue.record("schema probe did not finish in time\n\(log.joined(separator: "\n"))")
    }
}
