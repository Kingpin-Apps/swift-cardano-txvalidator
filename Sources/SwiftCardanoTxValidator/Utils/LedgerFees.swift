import BigInt
import Foundation
import SwiftCardanoCore

/// The ledger's fee arithmetic, done in exact rationals as the ledger does it.
enum LedgerFees {
    /// Conway's reference-script tiers, fixed by the ledger when protocol
    /// parameters state only the price per byte: a stride of 25 KiB, each
    /// tier 6/5 the price of the last.
    static let conwayReferenceScriptStride: UInt32 = 25_600
    static let conwayReferenceScriptMultiplier = NonNegativeInterval(numerator: 6, denominator: 5)

    /// The ledger's `txscriptfee`: the exact cost of all memory and steps,
    /// rounded up once.
    static func scriptFee(prices: ExecutionUnitPrices, memory: BigInt, steps: BigInt) -> BigInt {
        (Rational(prices.priceMemory) * Rational(memory) + Rational(prices.priceSteps) * Rational(steps)).ceiling
    }

    /// The ledger's `tierRefScriptFee`: `bytes` charged in tiers of `stride`
    /// bytes, each `multiplier` times the price of the last, summed exactly
    /// and rounded down once. `nil` when the parameters price nothing.
    static func referenceScriptFee(bytes: Int, parameters: ProtocolParameters) -> BigInt? {
        let base: NonNegativeInterval, stride: UInt32, multiplier: NonNegativeInterval
        if let tiers = parameters.minFeeReferenceScripts,
           let tierBase = tiers.base, let tierStride = tiers.range, let tierMultiplier = tiers.multiplier {
            (base, stride, multiplier) = (tierBase, tierStride, tierMultiplier)
        } else if let perByte = parameters.minFeeRefScriptCostPerByte {
            (base, stride, multiplier) = (perByte, conwayReferenceScriptStride, conwayReferenceScriptMultiplier)
        } else {
            return nil
        }
        guard stride > 0, base.denominator > 0, multiplier.denominator > 0 else { return nil }

        var total = Rational(0)
        var price = Rational(base)
        var remaining = BigInt(bytes)
        let size = BigInt(stride)
        while remaining >= size {
            total = total + price * Rational(size)
            price = price * Rational(multiplier)
            remaining -= size
        }
        return (total + price * Rational(remaining)).floor
    }
}

/// An exact non-negative fraction.
struct Rational {
    let numerator: BigInt
    let denominator: BigInt

    init(_ numerator: BigInt, _ denominator: BigInt = 1) {
        let divisor = numerator.greatestCommonDivisor(with: denominator)
        let d = divisor == 0 ? BigInt(1) : divisor
        self.numerator = numerator / d
        self.denominator = denominator / d
    }

    init(_ interval: NonNegativeInterval) {
        self.init(BigInt(interval.numerator), BigInt(interval.denominator))
    }

    static func + (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator, lhs.denominator * rhs.denominator)
    }

    static func * (lhs: Rational, rhs: Rational) -> Rational {
        Rational(lhs.numerator * rhs.numerator, lhs.denominator * rhs.denominator)
    }

    /// Rounded down; the value is never negative.
    var floor: BigInt { numerator / denominator }

    /// Rounded up; the value is never negative.
    var ceiling: BigInt { (numerator + denominator - 1) / denominator }
}
