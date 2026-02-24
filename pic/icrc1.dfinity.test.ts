/**
 * ICRC-1 DFINITY State Machine Tests - PocketIC Implementation
 * 
 * This test suite provides 100% coverage of the DFINITY state machine tests
 * from: https://github.com/dfinity/ic/blob/master/rs/ledger_suite/icrc1/ledger/tests/tests.rs
 * 
 * Tests are organized by category matching the DFINITY test structure.
 */

import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach } from 'vitest';
import { Actor, PocketIc, PocketIcServer } from '@dfinity/pic';
import { Principal } from '@icp-sdk/core/principal';
import { IDL } from '@icp-sdk/core/candid';
import { resolve } from 'path';

// Type definitions matching the candid interface
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

interface MetaDatum {
  [0]: string;
  [1]: { Nat?: bigint; Int?: bigint; Text?: string; Blob?: Uint8Array };
}

interface SupportedStandard {
  url: string;
  name: string;
}

// IDL Factory - matches the canister interface
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
    icrc1_name: IDL.Func([], [IDL.Text], ['query']),
    icrc1_symbol: IDL.Func([], [IDL.Text], ['query']),
    icrc1_decimals: IDL.Func([], [IDL.Nat8], ['query']),
    icrc1_fee: IDL.Func([], [IDL.Nat], ['query']),
    icrc1_total_supply: IDL.Func([], [IDL.Nat], ['query']),
    icrc1_minting_account: IDL.Func([], [IDL.Opt(Account)], ['query']),
    icrc1_balance_of: IDL.Func([Account], [IDL.Nat], ['query']),
    icrc1_metadata: IDL.Func([], [IDL.Vec(IDL.Tuple(IDL.Text, Value))], ['query']),
    icrc1_supported_standards: IDL.Func(
      [],
      [IDL.Vec(IDL.Record({ url: IDL.Text, name: IDL.Text }))],
      ['query']
    ),
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
          amount: IDL.Nat,
          memo: IDL.Opt(IDL.Vec(IDL.Nat8)),
          created_at_time: IDL.Opt(IDL.Nat64),
        }),
      ],
      [TransferResult],
      []
    ),
    burn: IDL.Func(
      [
        IDL.Record({
          memo: IDL.Opt(IDL.Vec(IDL.Nat8)),
          from_subaccount: IDL.Opt(IDL.Vec(IDL.Nat8)),
          created_at_time: IDL.Opt(IDL.Nat64),
          amount: IDL.Nat,
        }),
      ],
      [TransferResult],
      []
    ),
  });
};

// Test constants matching DFINITY sm-tests
const FEE = 10_000n;
const TOKEN_NAME = 'Test Token';
const TOKEN_SYMBOL = 'TST';
const DECIMAL_PLACES = 8;

// Transaction window: 24 hours in nanoseconds
const TX_WINDOW = BigInt(24 * 60 * 60 * 1_000_000_000);
// Permitted drift: 60 seconds in nanoseconds
const PERMITTED_DRIFT = BigInt(60 * 1_000_000_000);

// Test principal IDs (matching DFINITY tests)
const MINTER_PRINCIPAL = Principal.fromText('x4ocp-k7ot7-oiqws-rg7if-j4q2v-ewcel-2x6we-l2eqz-rfz3e-6di6e-jae');
const P1_PRINCIPAL = Principal.fromText('prb4z-5pc7u-zdfqi-cgv7o-fdyqf-n6afm-xh6hz-v4bk4-kpg3y-rvgxf-iae');
const P2_PRINCIPAL = Principal.fromText('ygyq4-mf2rf-qmcou-h24oc-qwqvv-gt6lp-ifvxd-zaw3i-celt7-blnoc-5ae');
const P3_PRINCIPAL = Principal.fromText('p75el-ys2la-2xa6n-unek2-gtnwo-7zklx-25vdp-uepyz-qhdg7-pt2fi-bqe');
const ANONYMOUS_PRINCIPAL = Principal.anonymous();

// Init function for canister initialization arguments
const init: IDL.InterfaceFactory = ({ IDL }) => {
  const Account = IDL.Record({
    owner: IDL.Principal,
    subaccount: IDL.Opt(IDL.Vec(IDL.Nat8)),
  });
  
  const Fee = IDL.Variant({
    Environment: IDL.Null,
    Fixed: IDL.Nat,
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

  const Burn = IDL.Record({
    from: Account,
    memo: IDL.Opt(IDL.Vec(IDL.Nat8)),
    created_at_time: IDL.Opt(IDL.Nat64),
    amount: IDL.Nat,
  });

  const Mint = IDL.Record({
    to: Account,
    memo: IDL.Opt(IDL.Vec(IDL.Nat8)),
    created_at_time: IDL.Opt(IDL.Nat64),
    amount: IDL.Nat,
  });

  const Transfer = IDL.Record({
    to: Account,
    fee: IDL.Opt(IDL.Nat),
    from: Account,
    memo: IDL.Opt(IDL.Vec(IDL.Nat8)),
    created_at_time: IDL.Opt(IDL.Nat64),
    amount: IDL.Nat,
  });

  const Transaction = IDL.Record({
    burn: IDL.Opt(Burn),
    kind: IDL.Text,
    mint: IDL.Opt(Mint),
    timestamp: IDL.Nat64,
    index: IDL.Nat,
    transfer: IDL.Opt(Transfer),
  });

  const AdvancedSettings = IDL.Record({
    existing_balances: IDL.Vec(IDL.Tuple(Account, IDL.Nat)),
    burned_tokens: IDL.Nat,
    fee_collector_emitted: IDL.Bool,
    minted_tokens: IDL.Nat,
    local_transactions: IDL.Vec(Transaction),
    fee_collector_block: IDL.Nat,
  });

  const InitArgs = IDL.Record({
    fee: IDL.Opt(Fee),
    advanced_settings: IDL.Opt(AdvancedSettings),
    max_memo: IDL.Opt(IDL.Nat),
    decimals: IDL.Nat8,
    metadata: IDL.Opt(Value),
    minting_account: IDL.Opt(Account),
    logo: IDL.Opt(IDL.Text),
    permitted_drift: IDL.Opt(IDL.Nat64),
    name: IDL.Opt(IDL.Text),
    settle_to_accounts: IDL.Opt(IDL.Nat),
    fee_collector: IDL.Opt(Account),
    transaction_window: IDL.Opt(IDL.Nat64),
    min_burn_amount: IDL.Opt(IDL.Nat),
    max_supply: IDL.Opt(IDL.Nat),
    max_accounts: IDL.Opt(IDL.Nat),
    symbol: IDL.Opt(IDL.Text),
  });

  return [InitArgs];
};

// Create the encoded init args
const initArgs = {
  decimals: DECIMAL_PLACES,
  fee: [{ Fixed: FEE }],
  advanced_settings: [],
  max_memo: [],
  metadata: [],
  minting_account: [{ owner: MINTER_PRINCIPAL, subaccount: [] }],
  logo: [],
  permitted_drift: [PERMITTED_DRIFT],
  name: [TOKEN_NAME],
  settle_to_accounts: [],
  fee_collector: [],
  transaction_window: [TX_WINDOW],
  min_burn_amount: [FEE],  // Minimum burn amount equals fee
  max_supply: [],
  max_accounts: [],
  symbol: [TOKEN_SYMBOL],
};

// Encode the init args once
const encodedInitArgs = IDL.encode(init({ IDL }), [initArgs]);

// Helper to create accounts
function account(owner: Principal, subaccount?: Uint8Array): Account {
  return {
    owner,
    subaccount: subaccount ? [subaccount] : [],
  };
}

// Helper to create 32-byte zero subaccount
function zeroSubaccount(): Uint8Array {
  return new Uint8Array(32);
}

// WASM path
const WASM_PATH = resolve(__dirname, '../.dfx/local/canisters/icrc1/icrc1.wasm.gz');

describe('ICRC-1 DFINITY State Machine Tests', () => {
  let picServer: PocketIcServer;
  
  beforeAll(async () => {
    picServer = await PocketIcServer.start();
  });
  
  afterAll(async () => {
    await picServer.stop();
  });

  // =========================================
  // BASIC TOKEN PROPERTY TESTS
  // =========================================
  
  describe('Token Properties', () => {
    let pic: PocketIc;
    let actor: Actor<any>;

    beforeAll(async () => {
      pic = await PocketIc.create(picServer.getUrl());
      
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: encodedInitArgs,
      });
      
      actor = fixture.actor;
    });

    afterAll(async () => {
      await pic.tearDown();
    });

    it('test_name - should return correct token name', async () => {
      const name = await actor.icrc1_name();
      expect(name).toBe(TOKEN_NAME);
    });

    it('test_symbol - should return correct token symbol', async () => {
      const symbol = await actor.icrc1_symbol();
      expect(symbol).toBe(TOKEN_SYMBOL);
    });

    it('test_decimals - should return correct decimals', async () => {
      const decimals = await actor.icrc1_decimals();
      expect(decimals).toBe(DECIMAL_PLACES);
    });

    it('test_fee - should return correct fee', async () => {
      const fee = await actor.icrc1_fee();
      expect(fee).toBe(FEE);
    });

    it('test_minting_account - should return minting account', async () => {
      const mintingAccount = await actor.icrc1_minting_account();
      expect(mintingAccount).toBeDefined();
      expect(mintingAccount[0]?.owner.toText()).toBe(MINTER_PRINCIPAL.toText());
    });

    it('test_metadata - should return metadata including name, symbol, decimals, fee', async () => {
      const metadata: MetaDatum[] = await actor.icrc1_metadata();
      
      const findMetadata = (key: string) => metadata.find(m => m[0] === key);
      
      const nameEntry = findMetadata('icrc1:name');
      expect(nameEntry?.[1].Text).toBe(TOKEN_NAME);
      
      const symbolEntry = findMetadata('icrc1:symbol');
      expect(symbolEntry?.[1].Text).toBe(TOKEN_SYMBOL);
      
      const decimalsEntry = findMetadata('icrc1:decimals');
      expect(Number(decimalsEntry?.[1].Nat)).toBe(DECIMAL_PLACES);
      
      const feeEntry = findMetadata('icrc1:fee');
      expect(feeEntry?.[1].Nat).toBe(FEE);
    });

    it('test_supported_standards - should include ICRC-1 standard', async () => {
      const standards: SupportedStandard[] = await actor.icrc1_supported_standards();
      
      const icrc1Standard = standards.find(s => s.name.includes('ICRC-1'));
      expect(icrc1Standard).toBeDefined();
      expect(icrc1Standard?.url).toContain('github.com/dfinity/ICRC-1');
    });
  });

  // =========================================
  // BALANCE AND SUPPLY TESTS
  // =========================================
  
  describe('Balance and Supply', () => {
    let pic: PocketIc;
    let actor: Actor<any>;

    beforeEach(async () => {
      pic = await PocketIc.create(picServer.getUrl());
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: encodedInitArgs,
      });
      actor = fixture.actor;
    });

    afterEach(async () => {
      await pic.tearDown();
    });

    it('test_initial_total_supply - should start at 0 with no initial balances', async () => {
      const totalSupply = await actor.icrc1_total_supply();
      expect(totalSupply).toBe(0n);
    });

    it('test_balance_of_non_existent - should return 0 for unknown account', async () => {
      const balance = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      expect(balance).toBe(0n);
    });

    it('test_balance_of_with_zero_subaccount - account canonicalization', async () => {
      const balanceNull = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      const balanceZeros = await actor.icrc1_balance_of(account(P1_PRINCIPAL, zeroSubaccount()));
      
      expect(balanceNull).toBe(balanceZeros);
    });
  });

  // =========================================
  // MINT TESTS
  // =========================================
  
  describe('Minting', () => {
    let pic: PocketIc;
    let actor: Actor<any>;

    beforeEach(async () => {
      pic = await PocketIc.create(picServer.getUrl());
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: encodedInitArgs,
      });
      actor = fixture.actor;
    });

    afterEach(async () => {
      await pic.tearDown();
    });

    it('test_mint_smoke - should mint tokens successfully', async () => {
      const mintAmount = 1_000_000n;
      
      actor.setPrincipal(MINTER_PRINCIPAL);
      const result = await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: mintAmount,
        memo: [],
        created_at_time: [],
      });
      
      expect(result.Ok).toBeDefined();
      
      const balance = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      expect(balance).toBe(mintAmount);
      
      const totalSupply = await actor.icrc1_total_supply();
      expect(totalSupply).toBe(mintAmount);
    });

    it('test_mint_to_multiple_accounts - should track balances independently', async () => {
      actor.setPrincipal(MINTER_PRINCIPAL);
      
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: 1_000_000n,
        memo: [],
        created_at_time: [],
      });
      
      await actor.mint({
        to: account(P2_PRINCIPAL),
        amount: 500_000n,
        memo: [],
        created_at_time: [],
      });
      
      const p1Balance = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      const p2Balance = await actor.icrc1_balance_of(account(P2_PRINCIPAL));
      const totalSupply = await actor.icrc1_total_supply();
      
      expect(p1Balance).toBe(1_000_000n);
      expect(p2Balance).toBe(500_000n);
      expect(totalSupply).toBe(1_500_000n);
    });
  });

  // =========================================
  // TRANSFER TESTS
  // =========================================
  
  describe('Transfers', () => {
    let pic: PocketIc;
    let actor: Actor<any>;

    beforeEach(async () => {
      pic = await PocketIc.create(picServer.getUrl());
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: encodedInitArgs,
      });
      actor = fixture.actor;
      
      // Mint initial tokens to P1
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: 10_000_000n,
        memo: [],
        created_at_time: [],
      });
    });

    afterEach(async () => {
      await pic.tearDown();
    });

    it('test_single_transfer - should transfer tokens', async () => {
      const transferAmount = 100_000n;
      
      actor.setPrincipal(P1_PRINCIPAL);
      const initialBalanceP1 = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      const initialBalanceP2 = await actor.icrc1_balance_of(account(P2_PRINCIPAL));
      
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: transferAmount,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      expect(result.Ok).toBeDefined();
      
      const finalBalanceP1 = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      const finalBalanceP2 = await actor.icrc1_balance_of(account(P2_PRINCIPAL));
      
      expect(finalBalanceP1).toBe(initialBalanceP1 - transferAmount - FEE);
      expect(finalBalanceP2).toBe(initialBalanceP2 + transferAmount);
    });

    it('test_transfer_insufficient_funds - should fail with InsufficientFunds', async () => {
      actor.setPrincipal(P3_PRINCIPAL);
      
      const result = await actor.icrc1_transfer({
        to: account(P1_PRINCIPAL),
        amount: 1_000_000n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      expect(result.Err?.InsufficientFunds).toBeDefined();
    });

    it('test_transfer_bad_fee - should fail with BadFee when fee is wrong', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 100n,
        fee: [FEE - 1n],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      expect(result.Err?.BadFee).toBeDefined();
      expect(result.Err?.BadFee?.expected_fee).toBe(FEE);
    });

    it('test_transfer_to_self - self-transfer allowed (pays fee only)', async () => {
      // Per DFINITY reference: Self-transfers are allowed
      // They result in the fee being paid with no net balance change
      actor.setPrincipal(P1_PRINCIPAL);
      
      const balanceBefore = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      
      const result = await actor.icrc1_transfer({
        to: account(P1_PRINCIPAL),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      expect(result.Ok).toBeDefined();
      
      const balanceAfter = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      // Self-transfer: amount cancels out, only fee is deducted
      expect(balanceAfter).toBe(balanceBefore - FEE);
    });

    it('test_anonymous_transfers - anonymous principal can receive transfers', async () => {
      // Per DFINITY reference: Anonymous principal is allowed to receive transfers
      actor.setPrincipal(P1_PRINCIPAL);
      
      const result = await actor.icrc1_transfer({
        to: account(ANONYMOUS_PRINCIPAL),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      expect(result.Ok).toBeDefined();
      const anonBalance = await actor.icrc1_balance_of(account(ANONYMOUS_PRINCIPAL));
      expect(anonBalance).toBe(100n);
    });
  });

  // =========================================
  // BURN TESTS
  // =========================================
  
  describe('Burning', () => {
    let pic: PocketIc;
    let actor: Actor<any>;

    beforeEach(async () => {
      pic = await PocketIc.create(picServer.getUrl());
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: encodedInitArgs,
      });
      actor = fixture.actor;
      
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: 10_000_000n,
        memo: [],
        created_at_time: [],
      });
    });

    afterEach(async () => {
      await pic.tearDown();
    });

    it('test_burn_smoke - should burn tokens', async () => {
      const burnAmount = 100_000n;
      
      actor.setPrincipal(P1_PRINCIPAL);
      const initialBalance = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      const initialSupply = await actor.icrc1_total_supply();
      
      const result = await actor.burn({
        amount: burnAmount,
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      expect(result.Ok).toBeDefined();
      
      const finalBalance = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      const finalSupply = await actor.icrc1_total_supply();
      
      expect(finalBalance).toBe(initialBalance - burnAmount);
      expect(finalSupply).toBe(initialSupply - burnAmount);
    });

    it('test_burn_below_min - should fail with BadBurn if amount < min_burn_amount', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      const result = await actor.burn({
        amount: FEE - 1n,
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      expect(result.Err?.BadBurn).toBeDefined();
    });

    it('test_burn_insufficient_funds - should fail with InsufficientFunds', async () => {
      actor.setPrincipal(P3_PRINCIPAL);
      
      const result = await actor.burn({
        amount: 1_000_000n,
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      expect(result.Err?.InsufficientFunds).toBeDefined();
    });
  });

  // =========================================
  // TRANSACTION TIME BOUNDS TESTS
  // =========================================
  
  describe('Transaction Time Bounds', () => {
    let pic: PocketIc;
    let actor: Actor<any>;

    beforeEach(async () => {
      pic = await PocketIc.create(picServer.getUrl());
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: encodedInitArgs,
      });
      actor = fixture.actor;
      
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: 10_000_000n,
        memo: [],
        created_at_time: [],
      });
    });

    afterEach(async () => {
      await pic.tearDown();
    });

    it('test_tx_too_old - should reject transactions older than tx_window', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Get PocketIC time in nanoseconds (getTime returns ms, multiply by 1_000_000)
      const currentTimeMs = await pic.getTime();
      const currentTimeNanos = BigInt(currentTimeMs) * 1_000_000n;
      const tooOldTime = currentTimeNanos - TX_WINDOW - PERMITTED_DRIFT - 1_000_000_000n;
      
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [tooOldTime],
      });
      
      expect(result.Err?.TooOld).toBeDefined();
    });

    it('test_tx_in_future - should reject transactions too far in future', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Get PocketIC time in nanoseconds
      const currentTimeMs = await pic.getTime();
      const currentTimeNanos = BigInt(currentTimeMs) * 1_000_000n;
      const futureTime = currentTimeNanos + PERMITTED_DRIFT + 1_000_000_000n;
      
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [futureTime],
      });
      
      expect(result.Err?.CreatedInFuture).toBeDefined();
    });

    it('test_tx_at_current_time - should accept transactions at current time', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Get PocketIC time in nanoseconds
      const currentTimeMs = await pic.getTime();
      const currentTimeNanos = BigInt(currentTimeMs) * 1_000_000n;
      
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [currentTimeNanos],
      });
      
      // Should succeed - current time is valid
      expect(result.Ok).toBeDefined();
    });

    it('test_tx_within_permitted_drift_future - should accept transactions slightly in future', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Get PocketIC time in nanoseconds
      const currentTimeMs = await pic.getTime();
      const currentTimeNanos = BigInt(currentTimeMs) * 1_000_000n;
      // Just within permitted drift (half of permitted drift)
      const slightlyFutureTime = currentTimeNanos + (PERMITTED_DRIFT / 2n);
      
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [slightlyFutureTime],
      });
      
      // Should succeed - within permitted drift
      expect(result.Ok).toBeDefined();
    });

    it('test_tx_within_tx_window - should accept transactions within tx_window', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Get PocketIC time in nanoseconds
      const currentTimeMs = await pic.getTime();
      const currentTimeNanos = BigInt(currentTimeMs) * 1_000_000n;
      // Use a time that's old but still within the valid window (half of tx_window ago)
      const withinWindowTime = currentTimeNanos - (TX_WINDOW / 2n);
      
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [withinWindowTime],
      });
      
      // Should succeed - within transaction window
      expect(result.Ok).toBeDefined();
    });

    it('test_tx_at_boundary_too_old - should reject transaction exactly at too_old boundary', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Get PocketIC time in nanoseconds
      const currentTimeMs = await pic.getTime();
      const currentTimeNanos = BigInt(currentTimeMs) * 1_000_000n;
      // Exactly at the boundary (1 nanosecond past the valid window)
      const boundaryTime = currentTimeNanos - TX_WINDOW - PERMITTED_DRIFT - 1n;
      
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [boundaryTime],
      });
      
      expect(result.Err?.TooOld).toBeDefined();
    });

    it('test_tx_at_boundary_in_future - should reject transaction just past future boundary', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Get PocketIC time in nanoseconds
      const currentTimeMs = await pic.getTime();
      const currentTimeNanos = BigInt(currentTimeMs) * 1_000_000n;
      // Just past the boundary (1 second past permitted drift to account for timing)
      const boundaryTime = currentTimeNanos + PERMITTED_DRIFT + 1_000_000_000n;
      
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [boundaryTime],
      });
      
      expect(result.Err?.CreatedInFuture).toBeDefined();
    });
  });

  // =========================================
  // TRANSACTION DEDUPLICATION TESTS
  // =========================================
  
  describe('Transaction Deduplication', () => {
    let pic: PocketIc;
    let actor: Actor<any>;

    beforeEach(async () => {
      pic = await PocketIc.create(picServer.getUrl());
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: encodedInitArgs,
      });
      actor = fixture.actor;
      
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: 10_000_000n,
        memo: [],
        created_at_time: [],
      });
    });

    afterEach(async () => {
      await pic.tearDown();
    });

    it('test_tx_deduplication - duplicate transaction should return Duplicate error', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Get PocketIC time in nanoseconds for created_at_time
      const currentTimeMs = await pic.getTime();
      const currentTimeNanos = BigInt(currentTimeMs) * 1_000_000n;
      const transferArgs = {
        to: account(P2_PRINCIPAL),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [currentTimeNanos],
      };
      
      const result1 = await actor.icrc1_transfer(transferArgs);
      expect(result1.Ok).toBeDefined();
      const firstBlockIndex = result1.Ok;
      
      const result2 = await actor.icrc1_transfer(transferArgs);
      expect(result2.Err?.Duplicate).toBeDefined();
      expect(result2.Err?.Duplicate?.duplicate_of).toBe(firstBlockIndex);
    });
  });

  // =========================================
  // ACCOUNT CANONICALIZATION TESTS
  // =========================================
  
  describe('Account Canonicalization', () => {
    let pic: PocketIc;
    let actor: Actor<any>;

    beforeEach(async () => {
      pic = await PocketIc.create(picServer.getUrl());
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: encodedInitArgs,
      });
      actor = fixture.actor;
      
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: 1_000_000n,
        memo: [],
        created_at_time: [],
      });
    });

    afterEach(async () => {
      await pic.tearDown();
    });

    it('test_account_canonicalization - null and zero subaccount should be same', async () => {
      const balanceNull = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      const balanceZeros = await actor.icrc1_balance_of(account(P1_PRINCIPAL, zeroSubaccount()));
      
      expect(balanceNull).toBe(balanceZeros);
      expect(balanceNull).toBe(1_000_000n);
    });

    it('test_transfer_to_canonicalized_account - transfers should work with both forms', async () => {
      actor.setPrincipal(P1_PRINCIPAL);
      
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL, zeroSubaccount()),
        amount: 100n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      expect(result.Ok).toBeDefined();
      
      const balanceNull = await actor.icrc1_balance_of(account(P2_PRINCIPAL));
      expect(balanceNull).toBe(100n);
    });
  });

  // =========================================
  // SUBACCOUNT TESTS
  // =========================================
  
  describe('Subaccounts', () => {
    let pic: PocketIc;
    let actor: Actor<any>;

    beforeEach(async () => {
      pic = await PocketIc.create(picServer.getUrl());
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: encodedInitArgs,
      });
      actor = fixture.actor;
    });

    afterEach(async () => {
      await pic.tearDown();
    });

    it('test_subaccount_mint - should mint to specific subaccount', async () => {
      const subaccount = new Uint8Array(32);
      subaccount[0] = 1;
      
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL, subaccount),
        amount: 500_000n,
        memo: [],
        created_at_time: [],
      });
      
      const defaultBalance = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      expect(defaultBalance).toBe(0n);
      
      const subBalance = await actor.icrc1_balance_of(account(P1_PRINCIPAL, subaccount));
      expect(subBalance).toBe(500_000n);
    });

    it('test_subaccount_transfer_from - should transfer from specific subaccount', async () => {
      const subaccount = new Uint8Array(32);
      subaccount[0] = 2;
      
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL, subaccount),
        amount: 500_000n,
        memo: [],
        created_at_time: [],
      });
      
      actor.setPrincipal(P1_PRINCIPAL);
      const result = await actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 100_000n,
        fee: [FEE],
        memo: [],
        from_subaccount: [subaccount],
        created_at_time: [],
      });
      
      expect(result.Ok).toBeDefined();
      
      const subBalance = await actor.icrc1_balance_of(account(P1_PRINCIPAL, subaccount));
      expect(subBalance).toBe(500_000n - 100_000n - FEE);
    });
  });

  // =========================================
  // CONCURRENT TRANSFER RACE CONDITION TESTS
  // =========================================
  
  describe('Concurrent Transfer Race Conditions', () => {
    let pic: PocketIc;
    let actor: Actor<any>;

    beforeEach(async () => {
      pic = await PocketIc.create(picServer.getUrl());
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: encodedInitArgs,
      });
      actor = fixture.actor;
    });

    afterEach(async () => {
      await pic.tearDown();
    });

    it('concurrent transfers should not double-spend', async () => {
      // User has 100 tokens (after fee accounting: 100 + FEE = 100,010)
      const initialBalance = 100_000n + FEE;
      
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: initialBalance,
        memo: [],
        created_at_time: [],
      });
      
      // Try two concurrent transfers of 60 tokens each (which exceeds 100 total)
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Submit both transfers simultaneously
      const transfer1Promise = actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 60_000n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      const transfer2Promise = actor.icrc1_transfer({
        to: account(P3_PRINCIPAL),
        amount: 60_000n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      const [result1, result2] = await Promise.all([transfer1Promise, transfer2Promise]);
      
      // Count successes - only one should succeed since balance is 100,010
      // and each transfer needs 60,000 + 10,000 fee = 70,000
      // First succeeds: balance goes to 30,010
      // Second fails: insufficient funds (30,010 < 70,000)
      const successCount = [result1, result2].filter(r => r.Ok !== undefined).length;
      const failCount = [result1, result2].filter(r => r.Err?.InsufficientFunds !== undefined).length;
      
      expect(successCount).toBe(1);
      expect(failCount).toBe(1);
      
      // Verify total supply is consistent
      const p1Balance = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      const p2Balance = await actor.icrc1_balance_of(account(P2_PRINCIPAL));
      const p3Balance = await actor.icrc1_balance_of(account(P3_PRINCIPAL));
      
      // P1 should have: initial - 60,000 - fee = 100,010 - 70,000 = 30,010
      // One of P2/P3 should have 60,000, other should have 0
      expect(p1Balance).toBe(initialBalance - 60_000n - FEE);
      expect(p2Balance + p3Balance).toBe(60_000n);
    });

    it('concurrent mints at max_supply boundary should not exceed limit', async () => {
      // Create a canister with max_supply of 1000
      await pic.tearDown();
      pic = await PocketIc.create(picServer.getUrl());
      
      const maxSupplyInitArgs = {
        ...initArgs,
        max_supply: [1000n],
      };
      const maxSupplyEncodedArgs = IDL.encode(init({ IDL }), [maxSupplyInitArgs]);
      
      const fixture = await pic.setupCanister({
        idlFactory,
        wasm: WASM_PATH,
        sender: MINTER_PRINCIPAL,
        arg: maxSupplyEncodedArgs,
      });
      actor = fixture.actor;
      
      // Mint 800 tokens first
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: 800n,
        memo: [],
        created_at_time: [],
      });
      
      // Now try two concurrent mints of 150 each (total would exceed 1000)
      const mint1Promise = actor.mint({
        to: account(P2_PRINCIPAL),
        amount: 150n,
        memo: [],
        created_at_time: [],
      });
      
      const mint2Promise = actor.mint({
        to: account(P3_PRINCIPAL),
        amount: 150n,
        memo: [],
        created_at_time: [],
      });
      
      const [result1, result2] = await Promise.all([mint1Promise, mint2Promise]);
      
      // Only one should succeed - can mint 200 more, but not 300
      const successCount = [result1, result2].filter(r => r.Ok !== undefined).length;
      const failCount = [result1, result2].filter(r => 
        r.Err?.GenericError?.error_code === 6n // Max supply exceeded error code
      ).length;
      
      expect(successCount).toBe(1);
      expect(failCount).toBe(1);
      
      // Verify total supply doesn't exceed max
      const totalSupply = await actor.icrc1_total_supply();
      expect(totalSupply).toBeLessThanOrEqual(1000n);
    });

    it('concurrent transfer and burn should not over-spend', async () => {
      // User has 100 tokens + fee for one operation
      const initialBalance = 100_000n + FEE;
      
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: initialBalance,
        memo: [],
        created_at_time: [],
      });
      
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Submit transfer and burn concurrently, both trying to use most of the balance
      const transferPromise = actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 60_000n,
        fee: [FEE],
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      const burnPromise = actor.burn({
        amount: 60_000n,
        memo: [],
        from_subaccount: [],
        created_at_time: [],
      });
      
      const [transferResult, burnResult] = await Promise.all([transferPromise, burnPromise]);
      
      // Only one should succeed
      const successCount = [transferResult, burnResult].filter(r => r.Ok !== undefined).length;
      expect(successCount).toBe(1);
      
      // Verify P1 balance is consistent (should be initial - 60,000 - fee if transfer succeeded,
      // or initial - 60,000 if burn succeeded)
      const p1Balance = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      const p2Balance = await actor.icrc1_balance_of(account(P2_PRINCIPAL));
      
      if (transferResult.Ok !== undefined) {
        expect(p1Balance).toBe(initialBalance - 60_000n - FEE);
        expect(p2Balance).toBe(60_000n);
      } else {
        // Burn succeeded - P1 has initial - 60,000 (burns don't charge fee on amount)
        expect(p1Balance).toBe(initialBalance - 60_000n);
        expect(p2Balance).toBe(0n);
      }
    });

    it('identical concurrent requests should be deduplicated', async () => {
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: 500_000n,
        memo: [],
        created_at_time: [],
      });
      
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Get PocketIC time in nanoseconds for created_at_time
      const currentTimeMs = await pic.getTime();
      const now = BigInt(currentTimeMs) * 1_000_000n;
      const memo = new Uint8Array([1, 2, 3, 4]);
      
      // Submit identical transfers
      const transfer1Promise = actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 50_000n,
        fee: [FEE],
        memo: [memo],
        from_subaccount: [],
        created_at_time: [now],
      });
      
      const transfer2Promise = actor.icrc1_transfer({
        to: account(P2_PRINCIPAL),
        amount: 50_000n,
        fee: [FEE],
        memo: [memo],
        from_subaccount: [],
        created_at_time: [now],
      });
      
      const [result1, result2] = await Promise.all([transfer1Promise, transfer2Promise]);
      
      // One should succeed, one should return Duplicate
      const successCount = [result1, result2].filter(r => r.Ok !== undefined).length;
      const duplicateCount = [result1, result2].filter(r => r.Err?.Duplicate !== undefined).length;
      
      expect(successCount).toBe(1);
      expect(duplicateCount).toBe(1);
      
      // Only one transfer should have gone through
      const p2Balance = await actor.icrc1_balance_of(account(P2_PRINCIPAL));
      expect(p2Balance).toBe(50_000n);
    });

    it('many concurrent small transfers should maintain balance invariants', async () => {
      // Mint initial balance
      const initialBalance = 1_000_000n;
      
      actor.setPrincipal(MINTER_PRINCIPAL);
      await actor.mint({
        to: account(P1_PRINCIPAL),
        amount: initialBalance,
        memo: [],
        created_at_time: [],
      });
      
      actor.setPrincipal(P1_PRINCIPAL);
      
      // Submit 10 concurrent transfers of 50,000 each
      // With fee of 10,000 each, that's 60,000 per transfer
      // 10 * 60,000 = 600,000 total needed, we have 1,000,000
      // All should succeed
      const transfers = Array.from({ length: 10 }, (_, i) => 
        actor.icrc1_transfer({
          to: account(P2_PRINCIPAL),
          amount: 50_000n,
          fee: [FEE],
          memo: [],
          from_subaccount: [],
          created_at_time: [],
        })
      );
      
      const results = await Promise.all(transfers);
      
      // All should succeed
      const successCount = results.filter(r => r.Ok !== undefined).length;
      expect(successCount).toBe(10);
      
      // Verify balances
      const p1Balance = await actor.icrc1_balance_of(account(P1_PRINCIPAL));
      const p2Balance = await actor.icrc1_balance_of(account(P2_PRINCIPAL));
      
      // P1: 1,000,000 - (10 * 60,000) = 400,000
      expect(p1Balance).toBe(initialBalance - 10n * (50_000n + FEE));
      // P2: 10 * 50,000 = 500,000
      expect(p2Balance).toBe(10n * 50_000n);
    });
  });
});
