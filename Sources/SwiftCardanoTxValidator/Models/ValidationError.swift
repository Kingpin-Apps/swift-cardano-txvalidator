import Foundation

/// A single validation error found in a Cardano transaction.
public struct ValidationError: Sendable, Codable, Equatable {

    // MARK: - Error kinds

    public enum Kind: String, Sendable, Codable, Equatable {
        // Phase-1 errors
        case feeTooSmall
        case feeTooBig                      // warning: fee more than 10% above minimum
        case valueNotConserved
        case missingInput
        case tooManyCollateralInputs
        case noCollateralInputs
        case insufficientCollateral
        case incorrectTotalCollateral
        case collateralLockedByScript
        case collateralContainsNonAdaAssets
        case collateralReturnTooSmall
        case collateralUnnecessary           // warning
        case totalCollateralNotDeclared      // warning
        case collateralUsesRewardAddress     // warning
        case scriptDataHashMismatch
        case outsideValidityInterval
        case missingRequiredSigner
        case extraneousSignature
        case invalidSignature
        case outputTooSmall
        case outputValueTooBig
        case networkIdMismatch
        case auxiliaryDataHashMissing
        case auxiliaryDataHashUnexpected
        case auxiliaryDataHashMismatch
        case inputSetEmpty
        case maximumTransactionSizeExceeded
        case executionUnitsTooLarge
        case referenceInputOverlapsWithInput
        case badInput                         // input UTxO not found in resolved set
        case inputsNotSorted                 // warning
        // Phase-2 errors
        case plutusScriptFailed
        case missingRedeemer
        case missingDatum
        case missingScript
        case extraneousRedeemer
        case executionBudgetExceeded
        case excessiveExecutionUnits         // warning: declared >> calculated
        // Witness errors
        case extraneousScript                // warning: script in witness set not required
        case extraneousDatum                 // warning: datum in witness set not referenced
        case nativeScriptFailed              // timelock or multisig evaluation failed
        case depositMismatch                 // cert/proposal deposit ≠ protocol param
        // Balance — withdrawal / treasury errors (Batch 6)
        case treasuryValueMismatch
        case wrongWithdrawalAmount
        case withdrawalNotDelegatedToDRep
        case rewardAccountNotExisting
        // Balance — refund warnings (Batch 6)
        case cannotCheckStakeDeregistrationRefund  // warning
        case cannotCheckDRepDeregistrationRefund    // warning
        // Registration errors (Batch 6)
        case stakeAlreadyRegistered
        case stakeNotRegistered
        case stakeNonZeroAccountBalance
        case stakePoolNotRegistered
        case wrongRetirementEpoch
        case stakePoolCostTooLow
        case committeeIsUnknown
        case committeeHasPreviouslyResigned
        // Registration warnings (Batch 6)
        case poolAlreadyRegistered               // warning
        case drepAlreadyRegistered               // warning
        case committeeAlreadyAuthorized          // warning
        case drepNotRegistered                   // warning
        case duplicateRegistrationInTx           // warning
        case duplicateCommitteeColdResignationInTx  // warning
        case duplicateCommitteeHotRegistrationInTx  // warning
        // Governance proposal errors (Batch 7)
        case govActionsDoNotExist
        case invalidPrevGovActionId
        case proposalCantFollow
        case malformedProposal
        case conflictingCommitteeUpdate
        case expirationEpochTooSmall
        case invalidConstitutionPolicyHash
        case proposalProcedureNetworkIdMismatch
        case treasuryWithdrawalsNetworkIdMismatch
        case zeroTreasuryWithdrawals
        case proposalReturnAccountDoesNotExist
        case treasuryWithdrawalReturnAccountDoesNotExist
        // Voting errors (Batch 7)
        case disallowedVoter
        case votingOnExpiredGovAction
        case voterDoesNotExist
        // Parse errors
        case malformedCBOR
        // Generic fallback
        case unknown
    }

    // MARK: - Properties

    /// The category of validation failure.
    public let kind: Kind

    /// Dot-separated CBOR field path, e.g. `"transaction_body.fee"`.
    public let fieldPath: String

    /// Human-readable description of what went wrong.
    public let message: String

    /// Suggested remediation, if available.
    public let hint: String?

    /// Whether this is a warning rather than a hard error.
    public let isWarning: Bool

    // MARK: - Init

    public init(
        kind: Kind,
        fieldPath: String,
        message: String,
        hint: String? = nil,
        isWarning: Bool = false
    ) {
        self.kind = kind
        self.fieldPath = fieldPath
        self.message = message
        self.hint = hint
        self.isWarning = isWarning
    }
}
