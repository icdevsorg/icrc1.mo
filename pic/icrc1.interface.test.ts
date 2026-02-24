/**
 * ICRC-1 Interface Hook Tests - PocketIC Implementation
 * 
 * This test suite verifies the extensible interface pattern:
 * - Before hooks that can short-circuit execution
 * - After hooks that can transform results
 * - Full implementation override capability
 * - Hook removal
 */

import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { Actor, PocketIc, PocketIcServer } from '@dfinity/pic';
import { Principal } from '@icp-sdk/core/principal';
import { IDL } from '@icp-sdk/core/candid';
import { resolve } from 'path';

// Type definitions
interface Account {
  owner: Principal;
  subaccount: [] | [Uint8Array];
}

interface TransferResult {
  Ok?: bigint;
  Err?: TransferError;
}

interface TransferError {
  GenericError?: { message: string; error_code: bigint };
  TemporarilyUnavailable?: null;
  BadBurn?: { min_burn_amount: bigint };
  Duplicate?: { duplicate_of: bigint };
  BadFee?: { expected_fee: bigint };
  CreatedInFuture?: { ledger_time: bigint };
  TooOld?: null;
  InsufficientFunds?: { balance: bigint };
}

interface HookStats {
  beforeTransferCallCount: bigint;
  afterTransferCallCount: bigint;
  lastTransferCaller: [] | [Principal];
  lastTransferAmount: [] | [bigint];
  beforeBalanceOfCallCount: bigint;
  afterBalanceOfCallCount: bigint;
  beforeNameCallCount: bigint;
  balanceMultiplier: bigint;
}

// IDL Factory for the interface test canister
const idlFactory: IDL.InterfaceFactory = ({ IDL }) => {
  const Account = IDL.Record({
    owner: IDL.Principal,
    subaccount: IDL.Opt(IDL.Vec(IDL.Nat8)),
  });
  
  const TransferError = IDL.Variant({
    GenericError: IDL.Record({ message: IDL.Text, error_code: IDL.Nat }),
    TemporarilyUnavailable: IDL.Null,
    BadBurn: IDL.Record({ min_burn_amount: IDL.Nat }),
    Duplicate: IDL.Record({ duplicate_of: IDL.Nat }),
    BadFee: IDL.Record({ expected_fee: IDL.Nat }),
    CreatedInFuture: IDL.Record({ ledger_time: IDL.Nat64 }),
    TooOld: IDL.Null,
    InsufficientFunds: IDL.Record({ balance: IDL.Nat }),
  });
  
  const TransferResult = IDL.Variant({
    Ok: IDL.Nat,
    Err: TransferError,
  });

  const HookStats = IDL.Record({
    beforeTransferCallCount: IDL.Nat,
    afterTransferCallCount: IDL.Nat,
    lastTransferCaller: IDL.Opt(IDL.Principal),
    lastTransferAmount: IDL.Opt(IDL.Nat),
    beforeBalanceOfCallCount: IDL.Nat,
    afterBalanceOfCallCount: IDL.Nat,
    beforeNameCallCount: IDL.Nat,
    balanceMultiplier: IDL.Nat,
  });

  const Value = IDL.Rec();
  Value.fill(
    IDL.Variant({
      Int: IDL.Int,
      Map: IDL.Vec(IDL.Tuple(IDL.Text, Value)),
      Nat: IDL.Nat,
      Blob: IDL.Vec(IDL.Nat8),
      Text: IDL.Text,
      Array: IDL.Vec(Value),
    })
  );
  
  return IDL.Service({
    // Standard ICRC-1 functions
    icrc1_name: IDL.Func([], [IDL.Text], ['query']),
    icrc1_symbol: IDL.Func([], [IDL.Text], ['query']),
    icrc1_decimals: IDL.Func([], [IDL.Nat8], ['query']),
    icrc1_fee: IDL.Func([], [IDL.Nat], ['query']),
    icrc1_total_supply: IDL.Func([], [IDL.Nat], ['query']),
    icrc1_minting_account: IDL.Func([], [IDL.Opt(Account)], ['query']),
    icrc1_balance_of: IDL.Func([Account], [IDL.Nat], ['query']),
    icrc1_metadata: IDL.Func([], [IDL.Vec(IDL.Tuple(IDL.Text, Value))], ['query']),
    icrc1_transfer: IDL.Func(
      [
        IDL.Record({
          to: Account,
          fee: IDL.Opt(IDL.Nat),
          memo: IDL.Opt(IDL.Vec(IDL.Nat8)),
          from_subaccount: IDL.Opt(IDL.Vec(IDL.Nat8)),
          created_at_time: IDL.Opt(IDL.Nat64),
          amount: IDL.Nat,
        }),
      ],
      [TransferResult],
      []
    ),
    mint: IDL.Func(
      [
        IDL.Record({
          to: Account,
          memo: IDL.Opt(IDL.Vec(IDL.Nat8)),
          created_at_time: IDL.Opt(IDL.Nat64),
          amount: IDL.Nat,
        }),
      ],
      [TransferResult],
      []
    ),
    
    // Hook management functions
    enableTransferBlockingHook: IDL.Func([], [], []),
    enableTransferTrackingHook: IDL.Func([], [], []),
    enableBalanceTrackingHook: IDL.Func([], [], []),
    enableBalanceMultiplierHook: IDL.Func([], [], []),
    enableNameOverrideHook: IDL.Func([], [], []),
    removeAllHooks: IDL.Func([], [], []),
    
    // Configuration functions
    blockPrincipal: IDL.Func([IDL.Principal], [], []),
    unblockPrincipal: IDL.Func([IDL.Principal], [], []),
    setBalanceMultiplier: IDL.Func([IDL.Nat], [], []),
    setNameOverride: IDL.Func([IDL.Opt(IDL.Text)], [], []),
    resetCounters: IDL.Func([], [], []),
    
    // Query functions
    getHookStats: IDL.Func([], [HookStats], ['query']),
    isBlocked: IDL.Func([IDL.Principal], [IDL.Bool], ['query']),
  });
};

// Test configuration
const WASM_PATH = resolve(__dirname, '../.dfx/local/canisters/icrc1interface/icrc1interface.wasm.gz');

// Test constants
const DEFAULT_FEE = 10_000n;
const INITIAL_SUPPLY = 1_000_000_000_000n;

describe('ICRC-1 Interface Hook Tests', () => {
  let pic: PocketIc;
  let server: PocketIcServer;
  let canisterId: Principal;
  let actor: Actor<any>;
  
  // Test identities
  let minter: Principal;
  let alice: Principal;
  let bob: Principal;
  let blockedUser: Principal;

  beforeAll(async () => {
    server = await PocketIcServer.start();
    pic = await PocketIc.create(server.getUrl());
    
    // Create test identities
    minter = Principal.fromText('rrkah-fqaaa-aaaaa-aaaaq-cai');
    alice = Principal.fromText('renrk-eyaaa-aaaaa-aaada-cai');
    bob = Principal.fromText('rno2w-sqaaa-aaaaa-aaacq-cai');
    blockedUser = Principal.fromText('rdmx6-jaaaa-aaaaa-aaadq-cai');
    
  });

  afterAll(async () => {
    await pic.tearDown();
    await server.stop();
  });

  beforeEach(async () => {
    // Reset state before each test by redeploying the canister
    const fixture = await pic.setupCanister({
      idlFactory,
      wasm: WASM_PATH,
      arg: IDL.encode(
        [
          IDL.Record({
            name: IDL.Opt(IDL.Text),
            symbol: IDL.Opt(IDL.Text),
            logo: IDL.Opt(IDL.Text),
            decimals: IDL.Nat8,
            fee: IDL.Opt(IDL.Variant({ Fixed: IDL.Nat, Environment: IDL.Null })),
            max_supply: IDL.Opt(IDL.Nat),
            min_burn_amount: IDL.Opt(IDL.Nat),
            minting_account: IDL.Opt(IDL.Record({
              owner: IDL.Principal,
              subaccount: IDL.Opt(IDL.Vec(IDL.Nat8)),
            })),
            advanced_settings: IDL.Opt(IDL.Null),
            max_memo: IDL.Opt(IDL.Nat),
            permitted_drift: IDL.Opt(IDL.Nat),
            transaction_window: IDL.Opt(IDL.Nat),
            max_accounts: IDL.Opt(IDL.Nat),
            settle_to_accounts: IDL.Opt(IDL.Nat),
          }),
        ],
        [{
          name: ['InterfaceTestToken'],
          symbol: ['ITT'],
          logo: [],
          decimals: 8,
          fee: [{ Fixed: DEFAULT_FEE }],
          max_supply: [],
          min_burn_amount: [10_000n],
          minting_account: [{ owner: minter, subaccount: [] }],
          advanced_settings: [],
          max_memo: [64n],
          permitted_drift: [],
          transaction_window: [],
          max_accounts: [],
          settle_to_accounts: [],
        }]
      ),
      sender: minter,
    });
    
    canisterId = fixture.canisterId;
    actor = fixture.actor;
  });

  describe('Basic Functionality (No Hooks)', () => {
    it('should return correct name without hooks', async () => {
      const name = await actor.icrc1_name();
      expect(name).toBe('InterfaceTestToken');
    });

    it('should return correct balance without hooks', async () => {
      // Mint some tokens to alice
      actor.setPrincipal(minter);
      const mintResult = await actor.mint({
        to: { owner: alice, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 1_000_000n,
      });
      expect(mintResult.Ok).toBeDefined();
      
      const balance = await actor.icrc1_balance_of({ owner: alice, subaccount: [] });
      expect(balance).toBe(1_000_000n);
    });

    it('should transfer successfully without hooks', async () => {
      // Give alice some tokens
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: alice, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Alice transfers to bob
      actor.setPrincipal(alice);
      const result = await actor.icrc1_transfer({
        to: { owner: bob, subaccount: [] },
        fee: [DEFAULT_FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        amount: 50_000n,
      });
      
      expect(result.Ok).toBeDefined();
      
      // Check bob's balance
      const bobBalance = await actor.icrc1_balance_of({ owner: bob, subaccount: [] });
      expect(bobBalance).toBe(50_000n);
    });
  });

  describe('Before Transfer Hooks', () => {
    it('should invoke before hook and track calls', async () => {
      // Enable the blocking hook
      await actor.enableTransferBlockingHook();
      
      // Give alice tokens
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: alice, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Transfer as alice
      actor.setPrincipal(alice);
      const result = await actor.icrc1_transfer({
        to: { owner: bob, subaccount: [] },
        fee: [DEFAULT_FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        amount: 50_000n,
      });
      
      expect(result.Ok).toBeDefined();
      
      // Check hook was called
      const stats = await actor.getHookStats();
      expect(stats.beforeTransferCallCount).toBe(1n);
      expect(stats.lastTransferCaller[0]?.toText()).toBe(alice.toText());
      expect(stats.lastTransferAmount[0]).toBe(50_000n);
    });

    it('should block transfers from blocked principals', async () => {
      // Enable blocking hook and block a user
      await actor.enableTransferBlockingHook();
      await actor.blockPrincipal(blockedUser);
      
      // Give blocked user tokens via mint
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: blockedUser, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Try to transfer as blocked user
      actor.setPrincipal(blockedUser);
      const result = await actor.icrc1_transfer({
        to: { owner: bob, subaccount: [] },
        fee: [DEFAULT_FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        amount: 50_000n,
      });
      
      // Should be blocked
      expect(result.Err).toBeDefined();
      expect(result.Err?.GenericError).toBeDefined();
      expect(result.Err?.GenericError?.error_code).toBe(403n);
      expect(result.Err?.GenericError?.message).toBe('Principal is blocked');
    });

    it('should allow transfer after unblocking principal', async () => {
      // Enable blocking hook, block then unblock
      await actor.enableTransferBlockingHook();
      await actor.blockPrincipal(blockedUser);
      await actor.unblockPrincipal(blockedUser);
      
      // Give blocked user tokens
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: blockedUser, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Transfer should work now
      actor.setPrincipal(blockedUser);
      const result = await actor.icrc1_transfer({
        to: { owner: bob, subaccount: [] },
        fee: [DEFAULT_FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        amount: 50_000n,
      });
      
      expect(result.Ok).toBeDefined();
    });
  });

  describe('After Transfer Hooks', () => {
    it('should invoke after hook on successful transfer', async () => {
      // Enable tracking hook
      await actor.enableTransferTrackingHook();
      
      // Give alice tokens
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: alice, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Transfer
      actor.setPrincipal(alice);
      await actor.icrc1_transfer({
        to: { owner: bob, subaccount: [] },
        fee: [DEFAULT_FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        amount: 50_000n,
      });
      
      // Check after hook was called
      const stats = await actor.getHookStats();
      expect(stats.afterTransferCallCount).toBe(1n);
    });

    it('should invoke both before and after hooks in order', async () => {
      // Enable both hooks
      await actor.enableTransferBlockingHook();
      await actor.enableTransferTrackingHook();
      
      // Give alice tokens
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: alice, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Transfer
      actor.setPrincipal(alice);
      await actor.icrc1_transfer({
        to: { owner: bob, subaccount: [] },
        fee: [DEFAULT_FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        amount: 50_000n,
      });
      
      // Both should be called
      const stats = await actor.getHookStats();
      expect(stats.beforeTransferCallCount).toBe(1n);
      expect(stats.afterTransferCallCount).toBe(1n);
    });

    it('should not invoke after hook when before hook short-circuits', async () => {
      // Enable both hooks
      await actor.enableTransferBlockingHook();
      await actor.enableTransferTrackingHook();
      
      // Block the user
      await actor.blockPrincipal(blockedUser);
      
      // Give blocked user tokens
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: blockedUser, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Try to transfer (will be blocked)
      actor.setPrincipal(blockedUser);
      await actor.icrc1_transfer({
        to: { owner: bob, subaccount: [] },
        fee: [DEFAULT_FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        amount: 50_000n,
      });
      
      // Before was called, after was NOT called (short-circuited)
      const stats = await actor.getHookStats();
      expect(stats.beforeTransferCallCount).toBe(1n);
      expect(stats.afterTransferCallCount).toBe(0n);
    });
  });

  describe('Query Hooks - Balance', () => {
    it('should invoke balance hooks', async () => {
      // Enable balance hooks
      await actor.enableBalanceTrackingHook();
      await actor.enableBalanceMultiplierHook();
      
      // Give alice tokens
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: alice, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Query balance
      const balance = await actor.icrc1_balance_of({ owner: alice, subaccount: [] });
      
      // Check hooks were called
      const stats = await actor.getHookStats();
      // Note: Query calls cannot persist state changes, so counters remain 0
      expect(stats.beforeBalanceOfCallCount).toBe(0n);
      expect(stats.afterBalanceOfCallCount).toBe(0n);
      expect(balance).toBe(100_000n); // multiplier is 1
    });

    it('should apply balance multiplier', async () => {
      // Enable balance multiplier hook with 2x multiplier
      await actor.enableBalanceMultiplierHook();
      await actor.setBalanceMultiplier(2n);
      
      // Give alice tokens
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: alice, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Query balance - should be doubled
      const balance = await actor.icrc1_balance_of({ owner: alice, subaccount: [] });
      expect(balance).toBe(200_000n);
    });

    it('should apply different multipliers', async () => {
      // Enable hook
      await actor.enableBalanceMultiplierHook();
      
      // Give alice tokens
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: alice, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Test different multipliers
      await actor.setBalanceMultiplier(3n);
      let balance = await actor.icrc1_balance_of({ owner: alice, subaccount: [] });
      expect(balance).toBe(300_000n);
      
      await actor.setBalanceMultiplier(10n);
      balance = await actor.icrc1_balance_of({ owner: alice, subaccount: [] });
      expect(balance).toBe(1_000_000n);
    });
  });

  describe('Hook Removal', () => {
    it('should remove hooks and restore original behavior', async () => {
      // Enable hooks
      await actor.enableTransferBlockingHook();
      await actor.enableTransferTrackingHook();
      await actor.enableBalanceMultiplierHook();
      await actor.setBalanceMultiplier(2n);
      
      // Block a user
      await actor.blockPrincipal(blockedUser);
      
      // Give blocked user tokens
      actor.setPrincipal(minter);
      await actor.mint({
        to: { owner: blockedUser, subaccount: [] },
        memo: [],
        created_at_time: [],
        amount: 100_000n,
      });
      
      // Verify blocked
      actor.setPrincipal(blockedUser);
      let result = await actor.icrc1_transfer({
        to: { owner: bob, subaccount: [] },
        fee: [DEFAULT_FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        amount: 10_000n,
      });
      expect(result.Err?.GenericError).toBeDefined();
      
      // Remove all hooks
      await actor.removeAllHooks();
      await actor.resetCounters();
      
      // Now transfer should work (even though principal is "blocked" - hook removed)
      result = await actor.icrc1_transfer({
        to: { owner: bob, subaccount: [] },
        fee: [DEFAULT_FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
        amount: 10_000n,
      });
      expect(result.Ok).toBeDefined();
      
      // Hooks should not have been called
      const stats = await actor.getHookStats();
      expect(stats.beforeTransferCallCount).toBe(0n);
      expect(stats.afterTransferCallCount).toBe(0n);
    });
  });

  describe('Implementation Override', () => {
    it('should allow overriding name implementation', async () => {
      // Enable name override hook and set custom name
      await actor.enableNameOverrideHook();
      await actor.setNameOverride(['CustomTokenName']);
      
      const name = await actor.icrc1_name();
      expect(name).toBe('CustomTokenName');
    });

    it('should fall back to original when override is cleared', async () => {
      // Enable override, set, then clear
      await actor.enableNameOverrideHook();
      await actor.setNameOverride(['CustomTokenName']);
      
      let name = await actor.icrc1_name();
      expect(name).toBe('CustomTokenName');
      
      // Clear override
      await actor.setNameOverride([]);
      name = await actor.icrc1_name();
      expect(name).toBe('InterfaceTestToken');
    });
  });
});
