import Testing
import Foundation
@testable import SwiftCardanoTxValidator

@Suite("ValidationError")
struct ValidationErrorTests {

    @Test("ValidationError Codable round-trip")
    func codableRoundTrip() throws {
        let error = ValidationError(
            kind: .feeTooSmall,
            fieldPath: "transaction_body.fee",
            message: "Fee too small",
            hint: "Increase the fee",
            isWarning: false
        )
        let data = try JSONEncoder().encode(error)
        let decoded = try JSONDecoder().decode(ValidationError.self, from: data)
        #expect(decoded == error)
    }

    @Test("ValidationError warning defaults to false")
    func warningDefault() {
        let error = ValidationError(kind: .unknown, fieldPath: "test", message: "test")
        #expect(error.isWarning == false)
        #expect(error.hint == nil)
    }

    @Test("ValidationError equality by kind, fieldPath, message")
    func equality() {
        let a = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "too small")
        let b = ValidationError(kind: .feeTooSmall, fieldPath: "fee", message: "too small")
        let c = ValidationError(kind: .feeTooBig, fieldPath: "fee", message: "too small")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("ValidationError.Kind raw values are stable strings")
    func kindRawValues() {
        #expect(ValidationError.Kind.feeTooSmall.rawValue == "feeTooSmall")
        #expect(ValidationError.Kind.badInput.rawValue == "badInput")
        #expect(ValidationError.Kind.stakeAlreadyRegistered.rawValue == "stakeAlreadyRegistered")
        #expect(ValidationError.Kind.committeeAlreadyAuthorized.rawValue == "committeeAlreadyAuthorized")
    }

    // MARK: - Kind.description

    /// Every `Kind` case, so `description` is exercised for all of them.
    static let allKinds: [ValidationError.Kind] = [
        .feeTooSmall, .feeTooBig, .valueNotConserved, .tooManyCollateralInputs,
        .noCollateralInputs, .insufficientCollateral, .incorrectTotalCollateral,
        .collateralLockedByScript, .collateralContainsNonAdaAssets, .collateralReturnTooSmall,
        .collateralUnnecessary, .totalCollateralNotDeclared, .collateralUsesRewardAddress,
        .scriptDataHashMismatch, .outsideValidityInterval, .missingRequiredSigner,
        .missingVKeyWitness, .extraneousSignature, .invalidSignature, .outputTooSmall,
        .outputValueTooBig, .networkIdMismatch, .auxiliaryDataHashMissing,
        .auxiliaryDataHashUnexpected, .auxiliaryDataHashMismatch, .inputSetEmpty,
        .maximumTransactionSizeExceeded, .executionUnitsTooLarge, .referenceInputOverlapsWithInput,
        .badInput, .inputAlreadySpent, .inputsNotSorted, .plutusScriptFailed, .missingRedeemer,
        .missingDatum, .missingScript, .extraneousRedeemer, .executionBudgetExceeded,
        .excessiveExecutionUnits, .extraneousScript, .extraneousDatum, .nativeScriptFailed,
        .depositMismatch, .treasuryValueMismatch, .wrongWithdrawalAmount,
        .withdrawalNotDelegatedToDRep, .rewardAccountNotExisting,
        .cannotCheckStakeDeregistrationRefund, .cannotCheckDRepDeregistrationRefund,
        .stakeAlreadyRegistered, .stakeNotRegistered, .stakeNonZeroAccountBalance,
        .stakePoolNotRegistered, .wrongRetirementEpoch, .stakePoolCostTooLow,
        .committeeIsUnknown, .committeeHasPreviouslyResigned, .poolAlreadyRegistered,
        .drepAlreadyRegistered, .committeeAlreadyAuthorized, .drepNotRegistered,
        .duplicateRegistrationInTx, .duplicateCommitteeColdResignationInTx,
        .duplicateCommitteeHotRegistrationInTx, .govActionsDoNotExist, .invalidPrevGovActionId,
        .proposalCantFollow, .malformedProposal, .conflictingCommitteeUpdate,
        .expirationEpochTooSmall, .invalidConstitutionPolicyHash,
        .proposalProcedureNetworkIdMismatch, .treasuryWithdrawalsNetworkIdMismatch,
        .zeroTreasuryWithdrawals, .proposalReturnAccountDoesNotExist,
        .treasuryWithdrawalReturnAccountDoesNotExist, .disallowedVoter, .votingOnExpiredGovAction,
        .voterDoesNotExist, .missingBootstrapWitness, .malformedCBOR, .unknown,
    ]

    @Test("Kind.description is non-empty for every kind")
    func descriptionNonEmptyForAllKinds() {
        for kind in Self.allKinds {
            #expect(!kind.description.isEmpty, "description was empty for \(kind.rawValue)")
        }
    }

    @Test("Kind.description returns expected human-readable strings")
    func descriptionSpotChecks() {
        #expect(ValidationError.Kind.feeTooSmall.description == "Fee Too Small")
        #expect(ValidationError.Kind.collateralContainsNonAdaAssets.description
            == "Collateral Contains Non-Ada Assets")
        #expect(ValidationError.Kind.missingVKeyWitness.description == "Missing Verification Key witness")
        #expect(ValidationError.Kind.unknown.description == "Unknown")
        #expect(ValidationError.Kind.malformedCBOR.description == "Malformed CBOR")
    }

    @Test("Kind.description is unique per kind")
    func descriptionUnique() {
        let descriptions = Self.allKinds.map { $0.description }
        #expect(Set(descriptions).count == descriptions.count)
    }
}
