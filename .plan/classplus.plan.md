# ICRC-1 ClassPlus Implementation Plan

## Overview

This plan details the steps to refactor ICRC-1 to use the ClassPlus initialization pattern, matching the approach used in ICRC-3. This enables proper async initialization (needed for ICRC-85 OVS timer setup) while maintaining backward compatibility.

## Reference Implementation

**ICRC-3** (`icrc3.mo/src/lib.mo`) serves as the reference. Key patterns:
- `Init()` function wrapping ClassPlus
- Constructor signature: `ICRC3(stored: ?State, caller: Principal, canister: Principal, args: ?InitArgs, environment_passed: ?Environment, storageChanged: (State) -> ())`

## Current ICRC-1 State

**Constructor signature**: `ICRC1(stored: ?State, canister: Principal, environment: Environment)`

**Gap Analysis**:
1. Missing `caller` parameter (required by ClassPlus)
2. Missing `args` parameter (required by ClassPlus)
3. Missing `storageChanged` callback (required by ClassPlus)
4. `environment` is required, not optional (ClassPlus expects optional)

---

## Phase 1: Update Constructor Signature

### Task 1.1: Modify ICRC1 Class Constructor

**File**: `src/ICRC1/lib.mo`

**Current** (line ~131):
```motoko
public class ICRC1(stored: ?State, canister: Principal, environment: Environment){
```

**Target**:
```motoko
public class ICRC1(stored: ?State, caller: Principal, canister: Principal, args: ?InitArgs, environment_passed: ?Environment, storageChanged: (State) -> ()){
```

### Task 1.2: Add Environment Unwrapping

**Add after constructor signature**:
```motoko
public let environment = switch(environment_passed){
  case(null) Runtime.trap("No Environment Provided");
  case(?val) val;
};
```

### Task 1.3: Update State Initialization

**Current** (line ~135):
```motoko
var state : CurrentState = switch(stored){
  case(null) {
    let result = init(initialState(),currentStateVersion, null, canister);
    ...
  };
  case(?val) {
    let result = init(val,currentStateVersion, null, canister);
    ...
  };
};
```

**Target**:
```motoko
var state : CurrentState = switch(stored){
  case(null) {
    let result = init(initialState(), currentStateVersion, args, caller);
    switch(result) {
      case(#v0_2_0(#data(foundState))) foundState;
      case(_) Runtime.trap("Unexpected state after initialization");
    };
  };
  case(?val) {
    let result = init(val, currentStateVersion, args, caller);
    switch(result) {
      case(#v0_2_0(#data(foundState))) foundState;
      case(_) Runtime.trap("Unexpected state after migration");
    };
  };
};

storageChanged(#v0_2_0(#data(state)));
```

---

## Phase 2: Add ClassPlus Init Functions

### Task 2.1: Add ClassPlus Import

**File**: `src/ICRC1/lib.mo`

**Add to imports** (near line 24):
```motoko
import ClassPlusLib "mo:class-plus";
```

### Task 2.2: Add Init Function

**Add after `public let init = Migration.migrate;`** (around line 112):

```motoko
/// ClassPlus-compatible initialization function
///
/// This function wraps the ICRC1 class with ClassPlus for proper async
/// initialization, enabling automatic ICRC-85 timer setup.
///
/// Example:
/// ```motoko
/// transient let icrc1 = ICRC1.Init({
///   org_icdevs_class_plus_manager = manager;
///   initialState = icrc1_migration_state;
///   args = ?icrc1Args;
///   pullEnvironment = ?getEnvironment;
///   onInitialize = null;
///   onStorageChange = func(state: ICRC1.State) {
///     icrc1_migration_state := state;
///   };
/// });
/// ```
public func Init(config : {
  org_icdevs_class_plus_manager: ClassPlusLib.ClassPlusInitializationManager;
  initialState: State;
  args : ?InitArgs;
  pullEnvironment : ?(() -> Environment);
  onInitialize: ?(ICRC1 -> async*());
  onStorageChange : ((State) ->())
}) : () -> ICRC1 {
  
  debug if(debug_channel.announce) Debug.print("ICRC1 Init");
  
  // Wrap onInitialize to ensure ICRC-85 timer is started
  let wrappedOnInitialize = func(instance: ICRC1) : async* () {
    debug if(debug_channel.icrc85) Debug.print("Auto-initializing ICRC-85 timer for ICRC-1");
    await* instance.init_icrc85_timer<system>();
    
    switch(config.onInitialize){
      case(?cb) await* cb(instance);
      case(null) {};
    };
  };

  ClassPlusLib.ClassPlus<
    ICRC1, 
    State,
    InitArgs,
    Environment>({config with 
      constructor = ICRC1;
      onInitialize = ?wrappedOnInitialize
    }).get;
};
```

### Task 2.3: Add InitDirect Function

**Add after Init function**:

```motoko
/// Direct initialization for use in mixins (bypasses ClassPlus)
/// 
/// Use this when system capability is not available (e.g., inside mixins).
/// The caller is responsible for ensuring proper initialization order and
/// calling init_icrc85_timer() manually.
///
/// Example:
/// ```motoko
/// stable var icrc1_state = ICRC1.init(ICRC1.initialState(), ...);
/// transient var _icrc1 : ?ICRC1.ICRC1 = null;
/// 
/// func icrc1() : ICRC1.ICRC1 {
///   switch(_icrc1) {
///     case(?v) v;
///     case(null) {
///       let instance = ICRC1.InitDirect({...});
///       _icrc1 := ?instance;
///       instance;
///     };
///   };
/// };
/// ```
public func InitDirect(config : {
  initialState: State;
  args : ?InitArgs;
  caller : Principal;
  canister : Principal;
  environment : Environment;
  onStorageChange : ((State) ->())
}) : ICRC1 {
  ICRC1(?config.initialState, config.caller, config.canister, config.args, ?config.environment, config.onStorageChange);
};
```

---

## Phase 3: Update Mixin

### Task 3.1: Update mixin.mo to use ClassPlus

**File**: `src/ICRC1/mixin.mo`

**Replace entire file with ClassPlus-compatible version**:

```motoko
/////////
// ICRC1 Mixin - Standard Token Interface
//
// This mixin provides ICRC-1 token functionality with automatic ICRC-85 OVS integration.
// It uses ClassPlus for proper async initialization.
//
// Usage:
// ```motoko
// import ICRC1Mixin "mo:icrc1-mo/ICRC1/mixin";
// import ICRC1 "mo:icrc1-mo/ICRC1";
// import ClassPlus "mo:class-plus";
// import Principal "mo:core/Principal";
//
// shared ({ caller = _owner }) persistent actor class MyToken() = this {
//   transient let canisterId = Principal.fromActor(this);
//   transient let org_icdevs_class_plus_manager = ClassPlus.ClassPlusInitializationManager<system>(_owner, canisterId, true);
//
//   include ICRC1Mixin.mixin(
//     icrc1Args,
//     getEnvironment,
//     _owner,
//     canisterId,
//     manager,
//     null
//   );
//
//   // Access via icrc1()
// };
// ```
/////////

import ICRC1 ".";
import Principal "mo:core/Principal";
import ClassPlus "mo:class-plus";

mixin(
  init_args: ICRC1.InitArgs,
  get_environment: () -> ICRC1.Environment,
  _owner: Principal,
  _canister: Principal,
  org_icdevs_class_plus_manager: ClassPlus.ClassPlusInitializationManager,
  onInit: ?((ICRC1.ICRC1) -> async*())
) {
  
  stable var icrc1_migration_state = ICRC1.init(ICRC1.initialState(), #v0_1_0(#id), ?init_args, _owner);

  transient let icrc1 = ICRC1.Init({
    org_icdevs_class_plus_manager = manager;
    initialState = icrc1_migration_state;
    args = ?init_args;
    pullEnvironment = ?get_environment;
    onInitialize = onInit;
    onStorageChange = func(state: ICRC1.State) {
      icrc1_migration_state := state;
    };
  });

  /// Functions for the ICRC1 token standard
  public shared query func icrc1_name() : async Text {
    icrc1().name();
  };

  public shared query func icrc1_symbol() : async Text {
    icrc1().symbol();
  };

  public shared query func icrc1_decimals() : async Nat8 {
    icrc1().decimals();
  };

  public shared query func icrc1_fee() : async ICRC1.Balance {
    icrc1().fee();
  };

  public shared query func icrc1_metadata() : async [ICRC1.MetaDatum] {
    icrc1().metadata()
  };

  public shared query func get_icrc85_stats() : async { activeActions: Nat; lastActionReported: ?Nat; nextCycleActionId: ?Nat } {
    icrc1().get_icrc85_stats()
  };

  public shared func init_icrc85_timer() : async () {
     await* icrc1().init_icrc85_timer<system>();
  };

  public shared query func icrc1_total_supply() : async ICRC1.Balance {
    icrc1().total_supply();
  };

  public shared query func icrc1_minting_account() : async ?ICRC1.Account {
    ?icrc1().minting_account();
  };

  public shared query func icrc1_balance_of(args : ICRC1.Account) : async ICRC1.Balance {
    icrc1().balance_of(args);
  };

  public shared query func icrc1_supported_standards() : async [ICRC1.SupportedStandard] {
    icrc1().supported_standards();
  };

  public shared query func icrc10_supported_standards() : async [ICRC1.SupportedStandard] {
    icrc1().supported_standards();
  };

  public shared ({ caller }) func icrc1_transfer(args : ICRC1.TransferArgs) : async ICRC1.TransferResult {
    await* icrc1().transfer(caller, args);
  };
};
```

---

## Phase 4: Update Token Canister Examples

### Task 4.1: Update Token.mo (Non-mixin)

**File**: `src/ICRC1/Canisters/Token.mo`

Update to use ClassPlus pattern with the manager.

### Task 4.2: Update Token-mixin.mo

**File**: `src/ICRC1/Canisters/Token-mixin.mo`

Update to pass manager to mixin.

---

## Phase 5: Verify Compilation & Tests

### Task 5.1: Run Build Check
```bash
cd /Users/afat/Dropbox/development/PanIndustrial/code/ICRC1.mo
dfx build --check
```

### Task 5.2: Run Unit Tests
```bash
cd /Users/afat/Dropbox/development/PanIndustrial/code/ICRC1.mo
dfx test
```

### Task 5.3: Run PocketIC Tests
```bash
cd /Users/afat/Dropbox/development/PanIndustrial/code/ICRC1.mo/pic
npm test
```

---

## Checklist

- [ ] Phase 1: Update Constructor Signature
  - [ ] Task 1.1: Modify ICRC1 class constructor signature
  - [ ] Task 1.2: Add environment unwrapping
  - [ ] Task 1.3: Update state initialization with storageChanged callback

- [ ] Phase 2: Add ClassPlus Init Functions
  - [ ] Task 2.1: Add ClassPlus import
  - [ ] Task 2.2: Add Init() function
  - [ ] Task 2.3: Add InitDirect() function

- [ ] Phase 3: Update Mixin
  - [ ] Task 3.1: Update mixin.mo to use ClassPlus

- [ ] Phase 4: Update Token Canister Examples
  - [ ] Task 4.1: Update Token.mo
  - [ ] Task 4.2: Update Token-mixin.mo

- [ ] Phase 5: Verify Compilation & Tests
  - [ ] Task 5.1: Run build check
  - [ ] Task 5.2: Run unit tests
  - [ ] Task 5.3: Run PocketIC tests

---

## Breaking Changes

This is a **BREAKING CHANGE** for direct class instantiation:

**Before**:
```motoko
ICRC1.ICRC1(?state, canister, environment)
```

**After**:
```motoko
ICRC1.ICRC1(?state, caller, canister, args, ?environment, storageChanged)
```

### Migration Path for Existing Users

1. **Using ClassPlus (recommended)**:
   ```motoko
   transient let icrc1 = ICRC1.Init({
     org_icdevs_class_plus_manager = manager;
     initialState = state;
     args = ?initArgs;
     pullEnvironment = ?getEnv;
     onInitialize = null;
     onStorageChange = func(s) { state := s; };
   });
   ```

2. **Direct instantiation (backward compat)**:
   ```motoko
   let instance = ICRC1.InitDirect({
     initialState = state;
     args = ?initArgs;
     caller = owner;
     canister = canisterId;
     environment = env;
     onStorageChange = func(s) { state := s; };
   });
   ```

---

## Dependencies

Ensure `mops.toml` includes:
```toml
class-plus = "0.0.2"  # Already present
```

---

## Notes

1. The `caller` parameter is used for permission checks during initialization
2. The `args` parameter allows passing `InitArgs` at construction time (vs. via `init()`)
3. The `storageChanged` callback enables state persistence notification
4. The `wrappedOnInitialize` pattern in `Init()` ensures ICRC-85 timer auto-starts
5. `InitDirect()` is provided for cases where ClassPlus is not suitable (e.g., testing, simple deployments)
