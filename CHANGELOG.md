## 0.4.0 (2026-09-26)

### Feat

- **phase2**: report consumed and declared execution units
- **view**: add certificates, governance, datums, scripts and redeemers
- **era**: take the era from the transaction, not the chain tip

### Fix

- **witness**: warn when a missing script may be on an unresolved input
- **phase1**: size transactions as the ledger does for fees and limits
- **phase1**: check signatures and metadata hash over the written bytes

## 0.3.4 (2026-09-24)

### Fix

- carry tag-258 indefinite datum sets through script data hashing
- hash the empty redeemer map when a witness set has no redeemers

## 0.3.3 (2026-09-24)

### Fix

- stop reporting script data hash and unused witnesses from unresolved inputs

## 0.3.2 (2026-09-24)

### Fix

- give Phase-2 the chain's slot timeline so scripts see real POSIX deadlines

## 0.3.1 (2026-09-23)

### Fix

- accept a governance proposal that names no ancestor

## 0.3.0 (2026-09-23)

### Feat

- report whether a redeemer budget was measured and detect scripts via redeemers

### Fix

- stop reporting input ordering the decoded model cannot observe
- stop trapping on negative net collateral when an input cannot be resolved
- include reference scripts when building the script data hash language views

## 0.2.3 (2026-07-08)

### Fix

- **resources**: drop stray Resources/cz.json bundle (iOS codesign-invalid nested layout)

## 0.2.2 (2026-06-10)

### Fix

- update dependencies and add more tests

## 0.2.1 (2026-06-02)

### Fix

- update dependencies and minor fixes

## 0.2.0 (2026-05-29)

### Feat

- widen money/slot/epoch types and migrate to CBORCodable for core 0.4.x
- rename SwiftNcal imports to SwiftNaCl

## 0.1.11 (2026-05-15)

### Fix

- use latest uplc

## 0.1.10 (2026-05-15)

### Fix

- improve swift version compatibility

## 0.1.9 (2026-05-01)

### Fix

- update dependencies

## 0.1.8 (2026-04-08)

### Fix

- dont check phase 2 if not needed

## 0.1.7 (2026-04-08)

### Fix

- handle spent utxos and fix script data hash

## 0.1.6 (2026-04-07)

### Fix

- check for datum in all places

## 0.1.5 (2026-04-07)

### Fix

- update swift-uplc and handle missing input

## 0.1.4 (2026-04-07)

### Fix

- improve script data hash check

## 0.1.3 (2026-04-06)

### Fix

- add missingVKeyWitness error kind and implement CustomStringConvertible for ValidationError.Kind

## 0.1.2 (2026-04-06)

### Fix

- add missing input context checks and rules

## 0.1.1 (2026-04-02)

### Fix

- add byron address support
