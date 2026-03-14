# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-03-14

### Updates

- Updated to core 2.1.0
- Updatex to moc 1.3.0

## [0.2.0] - 2026-02-24

### Added

- Mixin pattern (`mo:icrc1-mo/ICRC1/mixin`) for automatic endpoint generation using `persistent actor class` and Class+
- Inspect module (`mo:icrc1-mo/ICRC1/Inspect`) for cycle drain protection with two-layer defense:
  - `inspect*` functions (return `Bool`) for use in `system func inspect()`
  - `guard*` functions (trap on invalid) for inter-canister protection
  - Built-in guards in mixin for `icrc1_transfer`, `icrc1_balance_of`, `icrc107_set_fee_collector`, `icrc21_canister_call_consent_message`
  - Configurable limits via `Config` type and `configWith()` helper
- Interface module (`mo:icrc1-mo/ICRC1/Interface`) with extensible before/after hooks for all ICRC-1 endpoints
- ICRC-107 fee collector management: `icrc107_set_fee_collector`, `icrc107_get_fee_collector` with authorization via `canSetFeeCollector`
- ICRC-106 index principal: `icrc106_get_index_principal`, `set_icrc106_index_principal` with authorization via `canSetIndexPrincipal`
- ICRC-21 consent message support: `icrc21_canister_call_consent_message` with pluggable consent builders
- ICRC-10 supported standards alias: `icrc10_supported_standards` mirrors `icrc1_supported_standards`
- ICRC-85 Open Value Sharing integration via `ovs-fixed` for sustainable open-source funding
- `defaultMixinArgs()` helper for ergonomic mixin configuration with `with` syntax
- `MixinFunctionArgs` type with `canTransfer`, `canSetFeeCollector`, `canSetIndexPrincipal` fields
- `Init()` ClassPlus-compatible initialization function
- Complete README with mixin usage examples, inspect documentation, and API reference tables
- Performance benchmarks for account operations and balance operations

### Changed

- Migrated to `mo:core` (Map, Set, List) from `mo:map`/`mo:vector`
- Migrated to Motoko 1.1.0 with Enhanced Orthogonal Persistence (64-bit heap)
- Removed `mo:base` dependency in favor of `mo:core`
- Created migration `v000_002_000` for state type conversions
- Updated `mops.toml` to require `moc = "1.1.0"` toolchain

### Technical Details

- Uses `persistent actor class` syntax (Motoko 1.1.0+)
- ClassPlus async initialization with `ClassPlusInitializationManager`
- Star monad error handling for transfer/mint/burn operations
- Representational Independent Hash-based deduplication
- Automatic account pruning when exceeding `max_accounts`
