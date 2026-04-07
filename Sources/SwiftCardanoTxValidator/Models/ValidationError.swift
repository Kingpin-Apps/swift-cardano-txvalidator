import Foundation

/// A single validation error found in a Cardano transaction.
public struct ValidationError: Sendable, Codable, Equatable {

    // MARK: - Error kinds

    public enum Kind: String, Sendable, Codable, Equatable {
        // Phase-1 errors
        case feeTooSmall
        case feeTooBig  // warning: fee more than 10% above minimum
        case valueNotConserved
        case tooManyCollateralInputs
        case noCollateralInputs
        case insufficientCollateral
        case incorrectTotalCollateral
        case collateralLockedByScript
        case collateralContainsNonAdaAssets
        case collateralReturnTooSmall
        case collateralUnnecessary  // warning
        case totalCollateralNotDeclared  // warning
        case collateralUsesRewardAddress  // warning
        case scriptDataHashMismatch
        case outsideValidityInterval
        case missingRequiredSigner
        case missingVKeyWitness
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
        case badInput  // input UTxO not found in resolved set
        case inputsNotSorted  // warning
        // Phase-2 errors
        case plutusScriptFailed
        case missingRedeemer
        case missingDatum
        case missingScript
        case extraneousRedeemer
        case executionBudgetExceeded
        case excessiveExecutionUnits  // warning: declared >> calculated
        // Witness errors
        case extraneousScript  // warning: script in witness set not required
        case extraneousDatum  // warning: datum in witness set not referenced
        case nativeScriptFailed  // timelock or multisig evaluation failed
        case depositMismatch  // cert/proposal deposit ≠ protocol param
        // Balance — withdrawal / treasury errors (Batch 6)
        case treasuryValueMismatch
        case wrongWithdrawalAmount
        case withdrawalNotDelegatedToDRep
        case rewardAccountNotExisting
        // Balance — refund warnings (Batch 6)
        case cannotCheckStakeDeregistrationRefund  // warning
        case cannotCheckDRepDeregistrationRefund  // warning
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
        case poolAlreadyRegistered  // warning
        case drepAlreadyRegistered  // warning
        case committeeAlreadyAuthorized  // warning
        case drepNotRegistered  // warning
        case duplicateRegistrationInTx  // warning
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
        // Byron / bootstrap witness errors (Batch 8)
        case missingBootstrapWitness  // Byron-addressed spending input has no matching bootstrap witness
        // Parse errors
        case malformedCBOR
        // Generic fallback
        case unknown

        public var description: String {
            switch self {
            case .feeTooSmall: return "Fee Too Small"
            case .feeTooBig: return "Fee Too Big"
            case .valueNotConserved: return "Value Not Conserved"
            case .tooManyCollateralInputs: return "Too Many Collateral Inputs"
            case .noCollateralInputs: return "No Collateral Inputs"
            case .insufficientCollateral: return "Insufficient Collateral"
            case .incorrectTotalCollateral: return "Incorrect Total Collateral"
            case .collateralLockedByScript: return "Collateral Locked By Script"
            case .collateralContainsNonAdaAssets: return "Collateral Contains Non-Ada Assets"
            case .collateralReturnTooSmall: return "Collateral Return Too Small"
            case .collateralUnnecessary: return "Collateral Unnecessary"
            case .totalCollateralNotDeclared: return "Total Collateral Not Declared"
            case .collateralUsesRewardAddress: return "Collateral Uses Reward Address"
            case .scriptDataHashMismatch: return "Script Data Hash Mismatch"
            case .outsideValidityInterval: return "Outside Validity Interval"
            case .missingRequiredSigner: return "Missing Required Signer"
            case .missingVKeyWitness: return "Missing Verification Key witness"
            case .extraneousSignature: return "Extraneous Signature"
            case .invalidSignature: return "Invalid Signature"
            case .outputTooSmall: return "Output Too Small"
            case .outputValueTooBig: return "Output Value Too Big"
            case .networkIdMismatch: return "Network ID Mismatch"
            case .auxiliaryDataHashMissing: return "Auxiliary Data Hash Missing"
            case .auxiliaryDataHashUnexpected: return "Auxiliary Data Hash Unexpected"
            case .auxiliaryDataHashMismatch: return "Auxiliary Data Hash Mismatch"
            case .inputSetEmpty: return "Input Set Empty"
            case .maximumTransactionSizeExceeded: return "Maximum Transaction Size Exceeded"
            case .executionUnitsTooLarge: return "Execution Units Too Large"
            case .referenceInputOverlapsWithInput: return "Reference Input Overlaps With Input"
            case .badInput: return "Bad Input"
            case .inputsNotSorted: return "Inputs Not Sorted"
            case .plutusScriptFailed: return "Plutus Script Failed"
            case .missingRedeemer: return "Missing Redeemer"
            case .missingDatum: return "Missing Datum"
            case .missingScript: return "Missing Script"
            case .extraneousRedeemer: return "Extraneous Redeemer"
            case .executionBudgetExceeded: return "Execution Budget Exceeded"
            case .excessiveExecutionUnits: return "Excessive Execution Units"
            case .extraneousScript: return "Extraneous Script"
            case .extraneousDatum: return "Extraneous Datum"
            case .nativeScriptFailed: return "Native Script Failed"
            case .depositMismatch: return "Deposit Mismatch"
            case .treasuryValueMismatch: return "Treasury Value Mismatch"
            case .wrongWithdrawalAmount: return "Wrong Withdrawal Amount"
            case .withdrawalNotDelegatedToDRep: return "Withdrawal Not Delegated To DRep"
            case .rewardAccountNotExisting: return "Reward Account Not Existing"
            case .cannotCheckStakeDeregistrationRefund:
                return "Cannot Check Stake Deregistration Refund"
            case .cannotCheckDRepDeregistrationRefund:
                return "Cannot Check DRep Deregistration Refund"
            case .stakeAlreadyRegistered: return "Stake Already Registered"
            case .stakeNotRegistered: return "Stake Not Registered"
            case .stakeNonZeroAccountBalance: return "Stake Non-Zero Account Balance"
            case .stakePoolNotRegistered: return "Stake Pool Not Registered"
            case .wrongRetirementEpoch: return "Wrong Retirement Epoch"
            case .stakePoolCostTooLow: return "Stake Pool Cost Too Low"
            case .committeeIsUnknown: return "Committee Is Unknown"
            case .committeeHasPreviouslyResigned: return "Committee Has Previously Resigned"
            case .poolAlreadyRegistered: return "Pool Already Registered"
            case .drepAlreadyRegistered: return "DRep Already Registered"
            case .committeeAlreadyAuthorized: return "Committee Already Authorized"
            case .drepNotRegistered: return "DRep Not Registered"
            case .duplicateRegistrationInTx: return "Duplicate Registration In Tx"
            case .duplicateCommitteeColdResignationInTx:
                return "Duplicate Committee Cold Resignation In Tx"
            case .duplicateCommitteeHotRegistrationInTx:
                return "Duplicate Committee Hot Registration In Tx"
            case .govActionsDoNotExist: return "Gov Actions Do Not Exist"
            case .invalidPrevGovActionId: return "Invalid Prev Gov Action Id"
            case .proposalCantFollow: return "Proposal Can't Follow"
            case .malformedProposal: return "Malformed Proposal"
            case .conflictingCommitteeUpdate: return "Conflicting Committee Update"
            case .expirationEpochTooSmall: return "Expiration Epoch Too Small"
            case .invalidConstitutionPolicyHash: return "Invalid Constitution Policy Hash"
            case .proposalProcedureNetworkIdMismatch:
                return "Proposal Procedure Network ID Mismatch"
            case .treasuryWithdrawalsNetworkIdMismatch:
                return "Treasury Withdrawals Network ID Mismatch"
            case .zeroTreasuryWithdrawals: return "Zero Treasury Withdrawals"
            case .proposalReturnAccountDoesNotExist: return "Proposal Return Account Does Not Exist"
            case .treasuryWithdrawalReturnAccountDoesNotExist:
                return "Treasury Withdrawal Return Account Does Not Exist"
            case .disallowedVoter: return "Disallowed Voter"
            case .votingOnExpiredGovAction: return "Voting On Expired Gov Action"
            case .voterDoesNotExist: return "Voter Does Not Exist"
            case .missingBootstrapWitness: return "Missing Bootstrap Witness"
            case .malformedCBOR: return "Malformed CBOR"
            case .unknown: return "Unknown"
            }
        }
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
