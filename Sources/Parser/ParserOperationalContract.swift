import Foundation
import Grammar

/// Portable parser behaviors that an engine can truthfully expose.
public enum ParseOperationalFeature: String, CaseIterable, Hashable, Codable, Sendable {
    case productionTree
    case packedForest
    case ambiguityEvidence
    case replay
    case recovery
    case cancellation
    case normalizationProvenance
}

/// Named, dimensionless counters shared by parser implementations.
///
/// Engines report only counters they can measure without inventing equivalence
/// between unlike internal operations. `workItems`, for example, is not a
/// substitute for a chart item or LR action unless the adapter declares it so.
public enum ParseOperationalCounter: String, CaseIterable, Hashable, Codable, Sendable {
    case inputTokens
    case workItems
    case chartItems
    case configurations
    case peakConfigurations
    case forestNodes
    case packedFamilies
    case concreteTrees
    case replayEvents
    case diagnostics
    case recoveryEdits
    case ambiguitySites
}

public struct ParseOperationalValue: Hashable, Codable, Sendable {
    public let counter: ParseOperationalCounter
    public let value: Int

    public init(_ counter: ParseOperationalCounter, _ value: Int) {
        self.counter = counter
        self.value = value
    }
}

/// An engine's stable, inspectable operational surface.
public struct ParseOperationalCapabilities: Hashable, Codable, Sendable {
    public let features: [ParseOperationalFeature]
    public let reportedCounters: [ParseOperationalCounter]
    public let limitableCounters: [ParseOperationalCounter]
    public let normalizationTargets: [Grammar.GrammarForm]

    public init(
        features: [ParseOperationalFeature] = [],
        reportedCounters: [ParseOperationalCounter] = [],
        limitableCounters: [ParseOperationalCounter] = [],
        normalizationTargets: [Grammar.GrammarForm] = []
    ) {
        self.features = Array(Set(features)).sorted { $0.rawValue < $1.rawValue }
        self.reportedCounters = Array(Set(reportedCounters)).sorted { $0.rawValue < $1.rawValue }
        self.limitableCounters = Array(Set(limitableCounters)).sorted { $0.rawValue < $1.rawValue }
        self.normalizationTargets = Array(Set(normalizationTargets)).sorted { $0.rawValue < $1.rawValue }
    }

    public func supports(_ feature: ParseOperationalFeature) -> Bool {
        features.contains(feature)
    }
}

/// Why an engine invocation stopped. Rejection of an input is a completed
/// parse whose semantic result has status `.rejected`, not an operational
/// failure.
public enum ParseOperationDisposition: String, Hashable, Codable, Sendable {
    case completed
    case unsupported
    case limited
    case cancelled
    case failed
}

public enum ParseOperationalContractError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedSchema(Int)
    case emptyEngineIdentity
    case duplicateCapability(String)
    case invalidValue(counter: ParseOperationalCounter, value: Int, isLimit: Bool)
    case undeclaredCounter(ParseOperationalCounter)
    case unsupportedLimit(ParseOperationalCounter)
    case unreachedLimit(ParseOperationalCounter)
    case measurementExceedsLimit(ParseOperationalCounter)
    case dispositionRequiresResult(ParseOperationDisposition)
    case dispositionRequiresReachedLimit
    case unexpectedReachedLimit(ParseOperationDisposition)
    case dispositionForbidsResult(ParseOperationDisposition)
    case engineMismatch
    case unsupportedFeature(ParseOperationalFeature)
    case unsupportedNormalizationTarget(Grammar.GrammarForm)
    case missingInputTokenMeasurement
    case incompleteNormalizationProvenance
    case invalidResultEvidence
    case observableCounterMismatch(ParseOperationalCounter)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "Parser operational schema \(version) is not supported."
        case .emptyEngineIdentity:
            "The parser engine identity, display name, and algorithm must be non-empty."
        case .duplicateCapability(let field):
            "The operational capability field ‘\(field)’ contains duplicates."
        case .invalidValue(let counter, let value, let isLimit):
            "The \(isLimit ? "limit" : "measurement") for \(counter.rawValue) has invalid value \(value)."
        case .undeclaredCounter(let counter):
            "The engine did not declare the reported counter \(counter.rawValue)."
        case .unsupportedLimit(let counter):
            "The engine did not declare \(counter.rawValue) as limitable."
        case .unreachedLimit(let counter):
            "The reached limit \(counter.rawValue) was not requested."
        case .measurementExceedsLimit(let counter):
            "The \(counter.rawValue) measurement exceeds its requested limit."
        case .dispositionRequiresResult(let disposition):
            "The \(disposition.rawValue) disposition requires a parse result."
        case .dispositionRequiresReachedLimit:
            "A limited operation must identify at least one reached limit."
        case .unexpectedReachedLimit(let disposition):
            "The \(disposition.rawValue) disposition cannot contain reached limits."
        case .dispositionForbidsResult(let disposition):
            "The \(disposition.rawValue) disposition cannot contain a semantic parse result."
        case .engineMismatch:
            "The operational and semantic result engine descriptors differ."
        case .unsupportedFeature(let feature):
            "The result contains undeclared \(feature.rawValue) evidence."
        case .unsupportedNormalizationTarget(let target):
            "The engine did not declare support for \(target.rawValue) normalization."
        case .missingInputTokenMeasurement:
            "Normalization-backed result validation requires an inputTokens measurement."
        case .incompleteNormalizationProvenance:
            "The normalization report does not preserve complete provenance."
        case .invalidResultEvidence:
            "The parse result does not satisfy Parser's structural laws for the normalized grammar."
        case .observableCounterMismatch(let counter):
            "The \(counter.rawValue) measurement disagrees with the portable result."
        }
    }
}

/// Versioned evidence describing one bounded parser invocation.
///
/// The semantic result remains in `ParseContractSnapshot`. This envelope adds
/// only operational facts and can carry Grammar's normalization report so
/// production identities remain traceable to the source grammar.
public struct ParseOperationalSnapshot: Hashable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let engine: ParseEngineDescriptor
    public let capabilities: ParseOperationalCapabilities
    public let disposition: ParseOperationDisposition
    public let result: ParseContractSnapshot?
    public let normalization: GrammarNormalizationReport?
    public let limits: [ParseOperationalValue]
    public let measurements: [ParseOperationalValue]
    public let reachedLimits: [ParseOperationalCounter]
    public let message: String?

    public init(
        engine: ParseEngineDescriptor,
        capabilities: ParseOperationalCapabilities,
        disposition: ParseOperationDisposition,
        result: ParseContractSnapshot? = nil,
        normalization: GrammarNormalizationReport? = nil,
        limits: [ParseOperationalValue] = [],
        measurements: [ParseOperationalValue] = [],
        reachedLimits: [ParseOperationalCounter] = [],
        message: String? = nil
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.engine = engine
        self.capabilities = capabilities
        self.disposition = disposition
        self.result = result
        self.normalization = normalization
        self.limits = limits.sorted { $0.counter.rawValue < $1.counter.rawValue }
        self.measurements = measurements.sorted { $0.counter.rawValue < $1.counter.rawValue }
        self.reachedLimits = reachedLimits.sorted { $0.rawValue < $1.rawValue }
        self.message = message
        try validate()
    }

    public func measurement(_ counter: ParseOperationalCounter) -> Int? {
        measurements.first { $0.counter == counter }?.value
    }

    public func provenance(
        for outputProductionID: GrammarProductionID
    ) -> GrammarProductionProvenance? {
        normalization?.provenance.first {
            $0.outputProductionID == outputProductionID
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, engine, capabilities, disposition, result, normalization
        case limits, measurements, reachedLimits, message
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ParseOperationalContractError.unsupportedSchema(schemaVersion)
        }
        engine = try values.decode(ParseEngineDescriptor.self, forKey: .engine)
        capabilities = try values.decode(ParseOperationalCapabilities.self, forKey: .capabilities)
        disposition = try values.decode(ParseOperationDisposition.self, forKey: .disposition)
        result = try values.decodeIfPresent(ParseContractSnapshot.self, forKey: .result)
        normalization = try values.decodeIfPresent(
            GrammarNormalizationReport.self, forKey: .normalization
        )
        limits = try values.decode([ParseOperationalValue].self, forKey: .limits)
        measurements = try values.decode([ParseOperationalValue].self, forKey: .measurements)
        reachedLimits = try values.decode([ParseOperationalCounter].self, forKey: .reachedLimits)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        try validate()
    }

    private func validate() throws {
        guard !engine.identity.isEmpty, !engine.displayName.isEmpty, !engine.algorithm.isEmpty else {
            throw ParseOperationalContractError.emptyEngineIdentity
        }
        try requireUnique(capabilities.features.map(\.rawValue), field: "features")
        try requireUnique(capabilities.reportedCounters.map(\.rawValue), field: "reportedCounters")
        try requireUnique(capabilities.limitableCounters.map(\.rawValue), field: "limitableCounters")
        try requireUnique(capabilities.normalizationTargets.map(\.rawValue), field: "normalizationTargets")
        try requireUnique(limits.map { $0.counter.rawValue }, field: "limits")
        try requireUnique(measurements.map { $0.counter.rawValue }, field: "measurements")
        try requireUnique(reachedLimits.map(\.rawValue), field: "reachedLimits")

        let reported = Set(capabilities.reportedCounters)
        let limitable = Set(capabilities.limitableCounters)
        for value in measurements {
            guard value.value >= 0 else {
                throw ParseOperationalContractError.invalidValue(
                    counter: value.counter, value: value.value, isLimit: false
                )
            }
            guard reported.contains(value.counter) else {
                throw ParseOperationalContractError.undeclaredCounter(value.counter)
            }
        }
        for value in limits {
            guard value.value > 0 else {
                throw ParseOperationalContractError.invalidValue(
                    counter: value.counter, value: value.value, isLimit: true
                )
            }
            guard limitable.contains(value.counter) else {
                throw ParseOperationalContractError.unsupportedLimit(value.counter)
            }
        }
        let requested = Set(limits.map(\.counter))
        for counter in reachedLimits where !requested.contains(counter) {
            throw ParseOperationalContractError.unreachedLimit(counter)
        }
        for limit in limits {
            if let measured = measurement(limit.counter), measured > limit.value {
                throw ParseOperationalContractError.measurementExceedsLimit(limit.counter)
            }
        }

        let supportsProvenance = capabilities.supports(.normalizationProvenance)
        if supportsProvenance != !capabilities.normalizationTargets.isEmpty {
            throw ParseOperationalContractError.unsupportedFeature(.normalizationProvenance)
        }

        switch disposition {
        case .completed:
            guard result != nil else {
                throw ParseOperationalContractError.dispositionRequiresResult(disposition)
            }
            guard reachedLimits.isEmpty else {
                throw ParseOperationalContractError.unexpectedReachedLimit(disposition)
            }
        case .limited:
            guard !reachedLimits.isEmpty else {
                throw ParseOperationalContractError.dispositionRequiresReachedLimit
            }
        case .unsupported:
            guard reachedLimits.isEmpty else {
                throw ParseOperationalContractError.unexpectedReachedLimit(disposition)
            }
            guard result == nil else {
                throw ParseOperationalContractError.dispositionForbidsResult(disposition)
            }
        case .cancelled:
            guard capabilities.supports(.cancellation) else {
                throw ParseOperationalContractError.unsupportedFeature(.cancellation)
            }
            guard reachedLimits.isEmpty else {
                throw ParseOperationalContractError.unexpectedReachedLimit(disposition)
            }
        case .failed:
            guard reachedLimits.isEmpty else {
                throw ParseOperationalContractError.unexpectedReachedLimit(disposition)
            }
        }

        if let result {
            guard result.engine == engine else {
                throw ParseOperationalContractError.engineMismatch
            }
            if result.tree != nil, !capabilities.supports(.productionTree) {
                throw ParseOperationalContractError.unsupportedFeature(.productionTree)
            }
            if let forest = result.forest {
                guard capabilities.supports(.packedForest) else {
                    throw ParseOperationalContractError.unsupportedFeature(.packedForest)
                }
                if forest.isAmbiguous, !capabilities.supports(.ambiguityEvidence) {
                    throw ParseOperationalContractError.unsupportedFeature(.ambiguityEvidence)
                }
            }
            if !result.replay.isEmpty, !capabilities.supports(.replay) {
                throw ParseOperationalContractError.unsupportedFeature(.replay)
            }
            if !result.recoveryEdits.isEmpty, !capabilities.supports(.recovery) {
                throw ParseOperationalContractError.unsupportedFeature(.recovery)
            }
            if result.status == .recovered, !capabilities.supports(.recovery) {
                throw ParseOperationalContractError.unsupportedFeature(.recovery)
            }
            try validateObservableMeasurements(result)
        }

        if let normalization {
            guard capabilities.supports(.normalizationProvenance) else {
                throw ParseOperationalContractError.unsupportedFeature(.normalizationProvenance)
            }
            guard capabilities.normalizationTargets.contains(normalization.target) else {
                throw ParseOperationalContractError.unsupportedNormalizationTarget(normalization.target)
            }
            guard normalization.preservesCompleteProvenance else {
                throw ParseOperationalContractError.incompleteNormalizationProvenance
            }
            if let result {
                guard let tokenCount = measurement(.inputTokens) else {
                    throw ParseOperationalContractError.missingInputTokenMeasurement
                }
                let laws = try ParseLawVerifier.validate(
                    result, grammar: normalization.output, tokenCount: tokenCount
                )
                guard laws.passed else {
                    throw ParseOperationalContractError.invalidResultEvidence
                }
            }
        }
    }

    private func validateObservableMeasurements(_ result: ParseContractSnapshot) throws {
        let observable: [(ParseOperationalCounter, Int)] = [
            (.replayEvents, result.replay.count),
            (.diagnostics, result.diagnostics.count),
            (.recoveryEdits, result.recoveryEdits.count),
            (.forestNodes, result.forest?.nodes.count ?? 0),
            (.ambiguitySites, result.forest?.ambiguityNodes.count ?? 0),
        ]
        for (counter, actual) in observable {
            if let reported = measurement(counter), reported != actual {
                throw ParseOperationalContractError.observableCounterMismatch(counter)
            }
        }
    }

    private func requireUnique(_ values: [String], field: String) throws {
        guard Set(values).count == values.count else {
            throw ParseOperationalContractError.duplicateCapability(field)
        }
    }
}
