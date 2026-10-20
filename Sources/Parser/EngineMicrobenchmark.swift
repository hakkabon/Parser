import Dispatch
import Foundation

/// A parser-engine-owned microbenchmark suite expressed through a neutral Parser contract.
///
/// Parser owns the envelope and validation rules. The repository named by `owner`
/// owns every workload, fixture, boundary description, and observation.
public struct ParserEngineMicrobenchmarkSuite: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "parser-engine-microbenchmark-suite"

    public let schemaVersion: Int
    public let kind: String
    public let owner: Owner
    public let engineID: String
    public let id: String
    public let title: String
    public let buildConfiguration: BuildConfiguration
    public let warmupIterations: Int
    public let measurementIterations: Int
    public let cases: [Case]

    public struct Owner: Hashable, Codable, Sendable {
        public let repository: String
        public let version: String

        public init(repository: String, version: String) {
            self.repository = repository
            self.version = version
        }
    }

    public enum BuildConfiguration: String, Hashable, Codable, Sendable {
        case debug
        case release
    }

    public enum Operation: String, Hashable, Codable, Sendable {
        case construction
        case recognition
        case parsing
        case forestConstruction
    }

    public struct Case: Identifiable, Hashable, Codable, Sendable {
        public let id: String
        public let title: String
        public let operation: Operation
        /// Exact measured boundary, written by the owning engine.
        public let boundary: String
        /// Fingerprint of the grammar, input, options, and scale owned by the engine.
        public let workloadFingerprint: String
        /// Optional cross-engine group. Equal names alone do not establish comparability.
        public let comparisonGroup: String?
        public let scale: Int

        public init(
            id: String,
            title: String,
            operation: Operation,
            boundary: String,
            workloadFingerprint: String,
            comparisonGroup: String? = nil,
            scale: Int
        ) {
            self.id = id
            self.title = title
            self.operation = operation
            self.boundary = boundary
            self.workloadFingerprint = workloadFingerprint
            self.comparisonGroup = comparisonGroup
            self.scale = scale
        }
    }

    public init(
        owner: Owner,
        engineID: String,
        id: String,
        title: String,
        buildConfiguration: BuildConfiguration,
        warmupIterations: Int,
        measurementIterations: Int,
        cases: [Case]
    ) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindIdentifier
        self.owner = owner
        self.engineID = engineID
        self.id = id
        self.title = title
        self.buildConfiguration = buildConfiguration
        self.warmupIterations = warmupIterations
        self.measurementIterations = measurementIterations
        self.cases = cases
    }
}

public struct ParserEngineMicrobenchmarkObservation: Hashable, Codable, Sendable {
    /// Stable correctness evidence produced by the engine, never timing data.
    public let evidenceFingerprint: String
    /// Deterministic engine-owned counters such as accepted inputs or forest nodes.
    public let counters: [String: Int]

    public init(evidenceFingerprint: String, counters: [String: Int]) {
        self.evidenceFingerprint = evidenceFingerprint
        self.counters = counters
    }
}

public struct ParserEngineMicrobenchmarkEnvironment: Hashable, Codable, Sendable {
    public let operatingSystem: String
    public let architecture: String
    public let processorCount: Int
    public let physicalMemoryBytes: UInt64

    public init(
        operatingSystem: String,
        architecture: String,
        processorCount: Int,
        physicalMemoryBytes: UInt64
    ) {
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.processorCount = processorCount
        self.physicalMemoryBytes = physicalMemoryBytes
    }

    public static var current: Self {
        let process = ProcessInfo.processInfo
        return Self(
            operatingSystem: process.operatingSystemVersionString,
            architecture: architectureName,
            processorCount: process.processorCount,
            physicalMemoryBytes: process.physicalMemory
        )
    }

    private static var architectureName: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #elseif arch(arm)
        return "arm"
        #elseif arch(i386)
        return "i386"
        #else
        return "unknown"
        #endif
    }
}

public struct ParserEngineMicrobenchmarkTiming: Hashable, Codable, Sendable {
    public let minimumNanoseconds: UInt64
    public let medianNanoseconds: UInt64
    public let percentile95Nanoseconds: UInt64
    public let maximumNanoseconds: UInt64
}

public struct ParserEngineMicrobenchmarkResult: Identifiable, Hashable, Codable, Sendable {
    public var id: String { caseID }
    public let caseID: String
    public let evidenceFingerprint: String
    public let counters: [String: Int]
    public let durationsNanoseconds: [UInt64]
    public let timing: ParserEngineMicrobenchmarkTiming
}

public struct ParserEngineMicrobenchmarkReport: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindIdentifier = "parser-engine-microbenchmark-report"
    public static let fingerprintAlgorithm = "fnv1a64"

    public let schemaVersion: Int
    public let kind: String
    public let suite: ParserEngineMicrobenchmarkSuite
    public let suiteFingerprint: String
    public let environment: ParserEngineMicrobenchmarkEnvironment
    public let results: [ParserEngineMicrobenchmarkResult]
    public let fingerprintAlgorithm: String
    public let measurementFingerprint: String
}

public struct ParserEngineMicrobenchmarkComparison: Hashable, Codable, Sendable {
    public let compatible: Bool
    public let reason: String
    /// Candidate median divided by baseline median. Values below one are faster.
    public let medianRatios: [String: Double]
}

public enum ParserEngineMicrobenchmarkError: Error, LocalizedError, Sendable {
    case unsupportedSchema(Int)
    case invalidKind(String)
    case invalidSuite(String)
    case invalidReport(String)
    case unstableEvidence(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "Unsupported parser microbenchmark schema \(version)."
        case .invalidKind(let kind):
            "Unsupported parser microbenchmark kind ‘\(kind)’."
        case .invalidSuite(let reason):
            "Invalid parser microbenchmark suite: \(reason)"
        case .invalidReport(let reason):
            "Invalid parser microbenchmark report: \(reason)"
        case .unstableEvidence(let id):
            "Microbenchmark case ‘\(id)’ changed correctness evidence between iterations."
        }
    }
}

public enum ParserEngineMicrobenchmarkCodec {
    public static let maximumEncodedBytes = 8 * 1_024 * 1_024

    public static func encode(_ suite: ParserEngineMicrobenchmarkSuite) throws -> Data {
        try validate(suite)
        return try encoder.encode(suite)
    }

    public static func decodeSuite(_ data: Data) throws -> ParserEngineMicrobenchmarkSuite {
        guard data.count <= maximumEncodedBytes else {
            throw ParserEngineMicrobenchmarkError.invalidSuite("Encoded suite exceeds 8 MiB.")
        }
        let suite = try decoder.decode(ParserEngineMicrobenchmarkSuite.self, from: data)
        try validate(suite)
        return suite
    }

    public static func encode(_ report: ParserEngineMicrobenchmarkReport) throws -> Data {
        try validate(report)
        return try encoder.encode(report)
    }

    public static func decodeReport(_ data: Data) throws -> ParserEngineMicrobenchmarkReport {
        guard data.count <= maximumEncodedBytes else {
            throw ParserEngineMicrobenchmarkError.invalidReport("Encoded report exceeds 8 MiB.")
        }
        let report = try decoder.decode(ParserEngineMicrobenchmarkReport.self, from: data)
        try validate(report)
        return report
    }

    public static func fingerprint(_ suite: ParserEngineMicrobenchmarkSuite) throws -> String {
        try validate(suite)
        return fnv1a64(try encoder.encode(suite))
    }

    /// Stable evidence helper for engine-owned observations.
    public static func evidenceFingerprint(_ components: [String]) -> String {
        fnv1a64(Data(components.joined(separator: "\u{1f}").utf8))
    }

    static func makeReport(
        suite: ParserEngineMicrobenchmarkSuite,
        environment: ParserEngineMicrobenchmarkEnvironment,
        results: [ParserEngineMicrobenchmarkResult]
    ) throws -> ParserEngineMicrobenchmarkReport {
        let suiteFingerprint = try fingerprint(suite)
        let measurementFingerprint = try reportFingerprint(
            suiteFingerprint: suiteFingerprint, environment: environment, results: results
        )
        return ParserEngineMicrobenchmarkReport(
            schemaVersion: ParserEngineMicrobenchmarkReport.currentSchemaVersion,
            kind: ParserEngineMicrobenchmarkReport.kindIdentifier,
            suite: suite,
            suiteFingerprint: suiteFingerprint,
            environment: environment,
            results: results,
            fingerprintAlgorithm: ParserEngineMicrobenchmarkReport.fingerprintAlgorithm,
            measurementFingerprint: measurementFingerprint
        )
    }

    static func validate(_ suite: ParserEngineMicrobenchmarkSuite) throws {
        guard suite.schemaVersion == ParserEngineMicrobenchmarkSuite.currentSchemaVersion else {
            throw ParserEngineMicrobenchmarkError.unsupportedSchema(suite.schemaVersion)
        }
        guard suite.kind == ParserEngineMicrobenchmarkSuite.kindIdentifier else {
            throw ParserEngineMicrobenchmarkError.invalidKind(suite.kind)
        }
        guard validIdentity(suite.owner.repository), validIdentity(suite.owner.version),
              validIdentity(suite.engineID), validIdentity(suite.id),
              !suite.title.isEmpty, suite.title.count <= 256 else {
            throw ParserEngineMicrobenchmarkError.invalidSuite("Owner and suite identities are required.")
        }
        guard (0...20).contains(suite.warmupIterations),
              (3...100).contains(suite.measurementIterations),
              !suite.cases.isEmpty, suite.cases.count <= 100 else {
            throw ParserEngineMicrobenchmarkError.invalidSuite(
                "Warmups must be 0...20, measurements 3...100, and cases 1...100."
            )
        }
        let ids = suite.cases.map(\.id)
        guard ids == ids.sorted(), Set(ids).count == ids.count else {
            throw ParserEngineMicrobenchmarkError.invalidSuite("Case identifiers must be sorted and unique.")
        }
        for item in suite.cases {
            guard validIdentity(item.id), !item.title.isEmpty, item.title.count <= 256,
                  !item.boundary.isEmpty, item.boundary.count <= 2_048,
                  item.scale > 0, item.scale <= 1_000_000_000,
                  item.workloadFingerprint.range(
                    of: "^[0-9a-f]{16}$", options: .regularExpression
                  ) != nil,
                  item.comparisonGroup?.isEmpty != true,
                  item.comparisonGroup?.count ?? 0 <= 128 else {
                throw ParserEngineMicrobenchmarkError.invalidSuite(
                    "Every case requires bounded metadata and a workload fingerprint."
                )
            }
        }
    }

    static func validate(_ report: ParserEngineMicrobenchmarkReport) throws {
        guard report.schemaVersion == ParserEngineMicrobenchmarkReport.currentSchemaVersion else {
            throw ParserEngineMicrobenchmarkError.unsupportedSchema(report.schemaVersion)
        }
        guard report.kind == ParserEngineMicrobenchmarkReport.kindIdentifier else {
            throw ParserEngineMicrobenchmarkError.invalidKind(report.kind)
        }
        try validate(report.suite)
        let expectedSuiteFingerprint = try fingerprint(report.suite)
        guard report.suiteFingerprint == expectedSuiteFingerprint,
              report.fingerprintAlgorithm == ParserEngineMicrobenchmarkReport.fingerprintAlgorithm,
              report.results.map(\.caseID) == report.suite.cases.map(\.id),
              report.environment.processorCount > 0,
              report.environment.physicalMemoryBytes > 0,
              validIdentity(report.environment.operatingSystem, maximum: 256),
              validIdentity(report.environment.architecture) else {
            throw ParserEngineMicrobenchmarkError.invalidReport("Header or result inventory is inconsistent.")
        }
        for result in report.results {
            guard result.evidenceFingerprint.range(
                of: "^[0-9a-f]{16}$", options: .regularExpression
            ) != nil,
            validCounters(result.counters),
            result.durationsNanoseconds.count == report.suite.measurementIterations,
            result.durationsNanoseconds.allSatisfy({ $0 > 0 }),
            result.timing == timing(result.durationsNanoseconds) else {
                throw ParserEngineMicrobenchmarkError.invalidReport(
                    "Result ‘\(result.caseID)’ has invalid evidence, samples, or summary."
                )
            }
        }
        let expectedMeasurementFingerprint = try reportFingerprint(
            suiteFingerprint: report.suiteFingerprint,
            environment: report.environment,
            results: report.results
        )
        guard report.measurementFingerprint == expectedMeasurementFingerprint else {
            throw ParserEngineMicrobenchmarkError.invalidReport("Measurement fingerprint does not match.")
        }
    }

    static func timing(_ durations: [UInt64]) -> ParserEngineMicrobenchmarkTiming {
        let ordered = durations.sorted()
        return .init(
            minimumNanoseconds: ordered[0],
            medianNanoseconds: ordered[(ordered.count - 1) / 2],
            percentile95Nanoseconds: ordered[min(ordered.count - 1, Int(ceil(Double(ordered.count) * 0.95)) - 1)],
            maximumNanoseconds: ordered[ordered.count - 1]
        )
    }

    private static func reportFingerprint(
        suiteFingerprint: String,
        environment: ParserEngineMicrobenchmarkEnvironment,
        results: [ParserEngineMicrobenchmarkResult]
    ) throws -> String {
        struct Payload: Encodable {
            let suiteFingerprint: String
            let environment: ParserEngineMicrobenchmarkEnvironment
            let results: [ParserEngineMicrobenchmarkResult]
        }
        return fnv1a64(try encoder.encode(Payload(
            suiteFingerprint: suiteFingerprint, environment: environment, results: results
        )))
    }

    private static func fnv1a64(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func validIdentity(_ value: String, maximum: Int = 128) -> Bool {
        !value.isEmpty && value.count <= maximum
    }

    private static func validCounters(_ counters: [String: Int]) -> Bool {
        counters.count <= 64 && counters.allSatisfy {
            validIdentity($0.key) && $0.value >= 0
        }
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }()
    private static let decoder = JSONDecoder()
}

public enum ParserEngineMicrobenchmarkRunner {
    public static func run(
        _ suite: ParserEngineMicrobenchmarkSuite,
        environment: ParserEngineMicrobenchmarkEnvironment = .current,
        execute: (ParserEngineMicrobenchmarkSuite.Case) throws
            -> ParserEngineMicrobenchmarkObservation
    ) throws -> ParserEngineMicrobenchmarkReport {
        _ = try ParserEngineMicrobenchmarkCodec.encode(suite)
        var results: [ParserEngineMicrobenchmarkResult] = []
        for item in suite.cases {
            let baseline = try execute(item)
            try validate(baseline, caseID: item.id)
            for _ in 0..<suite.warmupIterations {
                guard try execute(item) == baseline else {
                    throw ParserEngineMicrobenchmarkError.unstableEvidence(item.id)
                }
            }
            var durations: [UInt64] = []
            for _ in 0..<suite.measurementIterations {
                let start = DispatchTime.now().uptimeNanoseconds
                let observation = try execute(item)
                let elapsed = max(1, DispatchTime.now().uptimeNanoseconds - start)
                guard observation == baseline else {
                    throw ParserEngineMicrobenchmarkError.unstableEvidence(item.id)
                }
                durations.append(elapsed)
            }
            results.append(.init(
                caseID: item.id,
                evidenceFingerprint: baseline.evidenceFingerprint,
                counters: baseline.counters,
                durationsNanoseconds: durations,
                timing: ParserEngineMicrobenchmarkCodec.timing(durations)
            ))
        }
        let report = try ParserEngineMicrobenchmarkCodec.makeReport(
            suite: suite, environment: environment, results: results
        )
        return try ParserEngineMicrobenchmarkCodec.decodeReport(
            ParserEngineMicrobenchmarkCodec.encode(report)
        )
    }

    public static func compare(
        baseline: ParserEngineMicrobenchmarkReport,
        candidate: ParserEngineMicrobenchmarkReport
    ) -> ParserEngineMicrobenchmarkComparison {
        guard baseline.suiteFingerprint == candidate.suiteFingerprint else {
            return .init(compatible: false, reason: "suite-fingerprint-mismatch", medianRatios: [:])
        }
        guard baseline.environment == candidate.environment else {
            return .init(compatible: false, reason: "environment-mismatch", medianRatios: [:])
        }
        guard zip(baseline.results, candidate.results).allSatisfy({
            $0.evidenceFingerprint == $1.evidenceFingerprint && $0.counters == $1.counters
        }) else {
            return .init(compatible: false, reason: "correctness-evidence-mismatch", medianRatios: [:])
        }
        let ratios = Dictionary(uniqueKeysWithValues: zip(baseline.results, candidate.results).map {
            ($0.caseID, Double($1.timing.medianNanoseconds) / Double($0.timing.medianNanoseconds))
        })
        return .init(compatible: true, reason: "compatible", medianRatios: ratios)
    }

    private static func validate(
        _ observation: ParserEngineMicrobenchmarkObservation, caseID: String
    ) throws {
        guard observation.evidenceFingerprint.range(
            of: "^[0-9a-f]{16}$", options: .regularExpression
        ) != nil, observation.counters.count <= 64,
        observation.counters.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 128 && $0.value >= 0 }) else {
            throw ParserEngineMicrobenchmarkError.invalidReport(
                "Case ‘\(caseID)’ returned invalid correctness evidence."
            )
        }
    }
}
