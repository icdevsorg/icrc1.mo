import Array "mo:core/Array";
import Blob "mo:core/Blob";
import D "mo:core/Debug";
import Int "mo:core/Int";
import Iter "mo:core/Iter";
import Nat "mo:core/Nat";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import Nat8 "mo:core/Nat8";
import Opt "mo:core/Option";
import Principal "mo:core/Principal";
import Result "mo:core/Result";
import Text "mo:core/Text";
import Time "mo:core/Time";

import Itertools "mo:itertools/Iter";
import Sha256 "mo:sha2/Sha256";
import Star "mo:star/star";
import List "mo:core/List";
import Map "mo:core/Map";

import ActorSpec "../utils/ActorSpec";
import Fake "../fake";
import ICRC1 "../../src/ICRC1";
import MigrationTypes = "../../src/ICRC1/migrations/types";
import T "../../src/ICRC1/migrations/types";
import U "../../src/ICRC1/Utils";
import ClassPlusLib "mo:class-plus";

module {



  type TransferResult = MigrationTypes.Current.TransferResult;
  type Account = MigrationTypes.Current.Account;
  type Balance = MigrationTypes.Current.Balance;
  let account_compare = ICRC1.account_compare;

  let e8s = 100000000;


    public func test() : async ActorSpec.Group {
        D.print("in test");

        let {
            assertTrue;
            assertFalse;
            assertAllTrue;
            describe;
            it;
            skip;
            pending;
            run;
        } = ActorSpec;

        func add_decimals(n : Nat, decimals : Nat) : Nat {
            n * (10 ** decimals);
        };

        func mock_tx(to : T.Current.Account, index : Nat) : T.Current.Transaction {
            {
                burn = null;
                transfer = null;
                kind = "MINT";
                timestamp = 0;
                index;
                mint = ?{
                    to;
                    amount = index + 1;
                    memo = null;
                    created_at_time = null;
                };
            };
        };

        let canister : T.Current.Account = {
            owner = Principal.fromText("x4ocp-k7ot7-oiqws-rg7if-j4q2v-ewcel-2x6we-l2eqz-rfz3e-6di6e-jae");
            subaccount = null;
        };

        let user1 : T.Current.Account = {
            owner = Principal.fromText("prb4z-5pc7u-zdfqi-cgv7o-fdyqf-n6afm-xh6hz-v4bk4-kpg3y-rvgxf-iae");
            subaccount = null;
        };

        let user2 : T.Current.Account = {
            owner = Principal.fromText("ygyq4-mf2rf-qmcou-h24oc-qwqvv-gt6lp-ifvxd-zaw3i-celt7-blnoc-5ae");
            subaccount = null;
        };

        func txs_range(start : Nat, end : Nat) : [T.Current.Transaction] {
            Array.tabulate(
                (end - start) : Nat,
                func(i : Nat) : T.Current.Transaction {
                    mock_tx(user1, start + i);
                },
            );
        };

        func is_tx_equal(t1 : T.Current.Transaction, t2 : T.Current.Transaction) : Bool {
            { t1 with timestamp = 0 } == { t2 with timestamp = 0 };
        };

        func is_opt_tx_equal(t1 : ?T.Current.Transaction, t2 : ?T.Current.Transaction) : Bool {
            switch (t1, t2) {
                case (?t1, ?t2) {
                    is_tx_equal(t1, t2);
                };
                case (_, ?t2) { false };
                case (?t1, _) { false };
                case (_, _) { true };
            };
        };

        func are_txs_equal(t1 : [T.Current.Transaction], t2 : [T.Current.Transaction]) : Bool {
            Itertools.equal<T.Current.Transaction>(t1.vals(), t2.vals(), is_tx_equal);
        };

        func create_mints(icrc1 : ICRC1.ICRC1, minting_principal : Principal, n : Nat) : async () {
            for (i in Itertools.range(0, n)) {
                ignore await* icrc1.mint_tokens(
                   minting_principal,
                    {
                        to = user1;
                        amount = i + 1;
                        memo = null;
                        created_at_time = null;
                    },
                   
                );
            };
        };

        let base_fee = 5 * (10 ** 8);
        let max_supply = 1_000_000_000 * (10 ** 8);

        let default_token_args : T.Current.InitArgs = {
            name = ?"Under-Collaterised Lending Tokens";
            symbol = ?"UCLTs";
            logo = ?"data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbGw9InJlZCIvPjwvc3ZnPg==";
            decimals = 8;
            fee = ?#Fixed(base_fee);
            max_supply = ?(max_supply);
            minting_account = ?canister;
            min_burn_amount = ?(10 * (10 ** 8));
            advanced_settings = null;
            metadata = null;
            max_memo = null;
            fee_collector = null;
            permitted_drift = null;
            transaction_window = null;
            max_accounts = null;
            settle_to_accounts = null;
        };
        var test_time : Int = Time.now();

        // Default test environment
        var test_environment : ICRC1.Environment = {
          advanced = null;
          add_ledger_transaction = null;
          var org_icdevs_timer_tool = null;
          var org_icdevs_class_plus_manager = null;
        };

        var stored_state = ICRC1.initialState();

        func pullTestEnvironment() : ICRC1.Environment {
          test_environment;
        };

        func get_icrc<system>(args : ICRC1.InitArgs) : ICRC1.ICRC1{
          let manager = ClassPlusLib.ClassPlusInitializationManager<system>(canister.owner, canister.owner, false);
          let getIcrc1 = ICRC1.Init({
            org_icdevs_class_plus_manager = manager;
            initialState = ICRC1.initialState();
            args = ?args;
            pullEnvironment = ?pullTestEnvironment;
            onInitialize = null;
            onStorageChange = func(_state : ICRC1.State) {
              stored_state := _state;
            };
          });
          getIcrc1();
        };

        func get_icrc_env<system>(args : ICRC1.InitArgs, env : ICRC1.Environment) : ICRC1.ICRC1{
          test_environment := env;
          let manager = ClassPlusLib.ClassPlusInitializationManager<system>(canister.owner, canister.owner, false);
          let getIcrc1 = ICRC1.Init({
            org_icdevs_class_plus_manager = manager;
            initialState = ICRC1.initialState();
            args = ?args;
            pullEnvironment = ?pullTestEnvironment;
            onInitialize = null;
            onStorageChange = func(_state : ICRC1.State) {
              stored_state := _state;
            };
          });
          getIcrc1();
        };

        let externalCanTransferFalseSync = func <system>(trx: ICRC1.Value, trxtop: ?ICRC1.Value, notification: ICRC1.TransactionRequestNotification) : Result.Result<(trx: ICRC1.Value, trxtop: ?ICRC1.Value, notification: ICRC1.TransactionRequestNotification), Text> {

            switch(notification.kind){
              case(#transfer(val)){
                return #err("always false");
              };
              case(_){
                return #ok(trx, trxtop, notification);
              }
            }
            // This mock externalCanTransfer function always returns false,
            // indicating the transfer should not proceed.
            
        };

        let externalCanTransferFalseAsync = func <system>(trx: ICRC1.Value, trxtop: ?ICRC1.Value, notification: ICRC1.TransactionRequestNotification) : async* Star.Star<(trx: ICRC1.Value, trxtop: ?ICRC1.Value, notification: ICRC1.TransactionRequestNotification), Text> {
            // This mock externalCanTransfer function always returns false,
            // indicating the transfer should not proceed.
            let fake = await Fake.Fake();
            switch(notification.kind){
              case(#transfer(val)){
                return #err(#awaited("always false"));
              };
              case(_){
                return #awaited(trx, trxtop, notification);
              }
            }
        };

        let externalCanTransferUpdateSync = func <system>(trx: ICRC1.Value, trxtop: ?ICRC1.Value, notification: ICRC1.TransactionRequestNotification) : Result.Result<(trx: ICRC1.Value, trxtop: ?ICRC1.Value, notification: ICRC1.TransactionRequestNotification), Text> {
            let results = List.empty<(Text,ICRC1.Value)>();
            switch(notification.kind){
              case(#transfer){};
              case(_){
                return #ok(trx,trxtop,notification);
              };
            };
            switch(trx){
              case(#Map(val)){
                for(thisItem in val.vals()){
                  if(thisItem.0 == "amt"){
                    List.add(results, ("amt", #Nat(2)));
                  } else {
                    List.add(results, thisItem);
                  };
                }
              };
              case(_) return #err("not a map");
            };

            return #ok(#Map(List.toArray(results)), trxtop, {notification with
              amount = 2;
            });
        };

        let externalCanTransferUpdateAsync = func <system>(trx: ICRC1.Value, trxtop: ?ICRC1.Value, notification: ICRC1.TransactionRequestNotification) : async* Star.Star<(trx: ICRC1.Value, trxtop: ?ICRC1.Value, notification: ICRC1.TransactionRequestNotification), Text> {
            let fake = await Fake.Fake();
            switch(notification.kind){
              case(#transfer){};
              case(_){
                return #awaited(trx,trxtop,notification);
              };
            };
            let results = List.empty<(Text,ICRC1.Value)>();
            switch(trx){
              case(#Map(val)){
                for(thisItem in val.vals()){
                  if(thisItem.0 == "amt"){
                    List.add(results, ("amt", #Nat(2)));
                  } else {
                    List.add(results, thisItem);
                  };
                }
              };
              case(_) return #err(#awaited("not a map"))
            };

            return #awaited(#Map(List.toArray(results)), trxtop, {notification with
              amount = 2;
            });
        };

        // Sample settings for update tests
        let updatedName = "Updated Name";
        let updatedLogo = "newlogo";
        let updatedSymbol = "UPD";
        let updatedDecimals : Nat8 = 10;
        let updatedFee : MigrationTypes.Current.Fee = #Fixed(2000);
        let updatedMaxSupply : Nat = 500000000;
        let updatedMinBurnAmount : Nat = 500;
        let updatedMaxAccounts : Nat = 10000;
        let updatedSettleToAccounts : Nat = 8000;

        // Helper function to check if metadata contains a specific key-value pair
        func metadataContains(metadata: [ICRC1.MetaDatum], key: Text, expectedValue: ICRC1.Value) : Bool {
            Array.find<ICRC1.MetaDatum>(metadata, func(item : ICRC1.MetaDatum) { item.0 == key and item.1 == expectedValue }) != null
        };

        return describe(
            "ICRC1 Token Implementation Tessts",
            [
                it(
                    "init()",
                    do {
                        let icrc1  = get_icrc<system>(default_token_args);

                        let minting_account = icrc1.minting_account();

                        // returns without trapping
                        assertAllTrue([
                            ?icrc1.name() == default_token_args.name,
                            ?icrc1.symbol() == default_token_args.symbol,
                            icrc1.decimals() == default_token_args.decimals,
                            icrc1.fee() == base_fee,
                            icrc1.max_supply() == default_token_args.max_supply,

                            minting_account.owner == canister.owner,
                            minting_account.subaccount == canister.subaccount,
                            icrc1.supported_standards() == [U.default_standard],
                            List.size(icrc1.get_local_transactions()) == 0,
                        ]);
                    },
                ),

                it(
                    "name()",
                    do {
                        D.print("testing name");
                        let icrc1 =  get_icrc<system>(default_token_args);

                        assertTrue(
                            ?icrc1.name() == default_token_args.name,
                        );
                    },
                ),

                it(
                    "symbol()",
                    do {
                        D.print("testing symbol");
                        

                        let icrc1 =  get_icrc<system>(default_token_args);

                        assertTrue(
                            ?icrc1.symbol() == default_token_args.symbol,
                        );
                    },
                ),

                it(
                    "decimals()",
                    do {
                        D.print("testing decimals");
                       

                        let icrc1 =  get_icrc<system>(default_token_args);

                        assertTrue(
                            icrc1.decimals() == default_token_args.decimals,
                        );
                    },
                ),
                it(
                    "fee()",
                    do {
                        D.print("testing fee");

                        let icrc1 =  get_icrc<system>(default_token_args);

                        let ?#Fixed(base_fee) = default_token_args.fee;

                        assertTrue(
                            icrc1.fee() == base_fee,
                        );
                    },
                ),
                it(
                    "minting_account()",
                    do {
                        D.print("testing minting_account");
                        

                        let icrc1 =  get_icrc<system>(default_token_args);

                        let init_minting = icrc1.minting_account();

                        let ?base_minting = default_token_args.minting_account;

                        ignore assertTrue(
                            init_minting.owner == base_minting.owner,
                        );

                        assertTrue(
                            init_minting.subaccount == base_minting.subaccount,
                        );
                    },
                ),
                it(
                    "balance_of()",
                    do {
                        D.print("testing balance_of");

                        let icrc1 =  get_icrc<system>(default_token_args);

                        for(thisItem in  [
                                (user1, 100),
                                (user2, 200),
                            ].vals()){
                          ignore await* icrc1.mint_tokens(icrc1.minting_account().owner,
                          {
                            to = thisItem.0;
                            amount = thisItem.1;
                            memo = ?Text.encodeUtf8("init");
                            created_at_time = null;
                          })
                        };

                        assertAllTrue([
                            icrc1.balance_of(user1) == 100,
                            icrc1.balance_of(user2) == 200,
                        ]);
                    },
                ),
                it(
                    "total_supply()",
                    do {
                        D.print("testing total_supply");
                       

                        let icrc1 =  get_icrc<system>(default_token_args);

                        for(thisItem in  [
                                (user1, 100),
                                (user2, 200),
                            ].vals()){
                          ignore await* icrc1.mint_tokens(icrc1.minting_account().owner, {
                            to = thisItem.0;
                            amount = thisItem.1;
                            memo = ?Text.encodeUtf8("init");
                            created_at_time = null;
                          })
                        };

                        assertTrue(
                            icrc1.total_supply() == 300,
                        );
                    },
                ),

                it(
                    "metadata()",
                    do {
                        

                        let icrc1 =  get_icrc<system>(default_token_args);
                        D.print("testing metadata" # debug_show(icrc1.metadata()));

                        assertTrue(
                            icrc1.metadata() == [
                                ("icrc1:fee", #Nat(5 * (10 ** 8))),
                                ("icrc1:name", #Text(Opt.get<Text>(default_token_args.name, "yuck"))),
                                ("icrc1:symbol", #Text(Opt.get<Text>(default_token_args.symbol, "yuk"))),
                                ("icrc1:decimals", #Nat(Nat8.toNat(default_token_args.decimals))),
                                ("icrc1:logo", #Text("data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbGw9InJlZCIvPjwvc3ZnPg=="))
                            ],
                        );
                    },
                ),

                it(
                    "supported_standards()",
                    do {
                        D.print("testing supported_standards");
                        
                        let icrc1 =  get_icrc<system>(default_token_args);

                        assertTrue(
                            icrc1.supported_standards() == [{
                                name = "ICRC-1";
                                url = "https://github.com/dfinity/ICRC-1";
                            }],
                        );
                    },
                ),
                it("Update Token Name", do {
                    let icrc1 =  get_icrc<system>(default_token_args);
                    ignore icrc1.update_ledger_info([#Name(updatedName)]);
                    assertAllTrue([
                    icrc1.name() == updatedName,
                    metadataContains(icrc1.metadata(), "icrc1:name", #Text(updatedName))]);
                }),
                it("Update Token Logo", do {
                    let icrc1 =  get_icrc<system>(default_token_args);
                    ignore icrc1.update_ledger_info([#Logo(updatedLogo)]);
                    assertAllTrue([
                    icrc1.get_state().logo == ?updatedLogo,
                    metadataContains(icrc1.metadata(), "icrc1:logo", #Text(updatedLogo))]);
                }),

                it("Update Token Symbol", do {
                    let icrc1 =  get_icrc<system>(default_token_args);
                    ignore icrc1.update_ledger_info([#Symbol(updatedSymbol)]);
                    assertAllTrue([
                      icrc1.symbol() == updatedSymbol,
                    metadataContains(icrc1.metadata(), "icrc1:symbol", #Text(updatedSymbol))]);
                }),

                it("Update Token Decimals", do {
                    let icrc1 =  get_icrc<system>(default_token_args);
                    ignore icrc1.update_ledger_info([#Decimals(updatedDecimals)]);
                    assertAllTrue([icrc1.decimals() == updatedDecimals, 
                    metadataContains(icrc1.metadata(), "icrc1:decimals", #Nat(Nat8.toNat(updatedDecimals)))]);
                }),

                it("Update Transfer Fee", do {
                    let icrc1 =  get_icrc<system>(default_token_args);
                    ignore icrc1.update_ledger_info([#Fee(updatedFee)]);
                    assertAllTrue([icrc1.get_state()._fee == ?#Fixed(2000),
                    metadataContains(icrc1.metadata(), "icrc1:fee", #Nat(2000))]);
                }),

                it("Update Max Supply", do {
                    let icrc1 =  get_icrc<system>(default_token_args);
                    ignore icrc1.update_ledger_info([#MaxSupply(?updatedMaxSupply)]);
                    assertAllTrue([icrc1.max_supply() == ?updatedMaxSupply]);
                }),

                it("Update Min Burn Amount", do {
                    let icrc1 =  get_icrc<system>(default_token_args);
                    ignore icrc1.update_ledger_info([#MinBurnAmount(?updatedMinBurnAmount)]);
                    assertAllTrue([icrc1.get_state().min_burn_amount == ?updatedMinBurnAmount]);
                }),

                it("Update Max Accounts", do {
                    let icrc1 =  get_icrc<system>(default_token_args);
                    ignore icrc1.update_ledger_info([#MaxAccounts(updatedMaxAccounts)]);
                    assertAllTrue([icrc1.get_state().max_accounts == updatedMaxAccounts]);
                }),

                it("Update Settle To Accounts", do {
                    let icrc1 =  get_icrc<system>(default_token_args);
                    ignore  icrc1.update_ledger_info([#SettleToAccounts(updatedSettleToAccounts)]);
                    assertAllTrue([icrc1.get_state().settle_to_accounts == updatedSettleToAccounts]);
                }),
                it("Can register metadata", do {
                    let icrc1 =  get_icrc<system>(default_token_args);
                    D.print("testing register metadata 1 " # debug_show(icrc1.metadata()));
                    ignore  icrc1.register_metadata([("test",#Text("test"))]);
                    D.print("testing register metadata 2 " # debug_show(icrc1.metadata()));
                    assertAllTrue([icrc1.metadata() == [
                                ("icrc1:fee", #Nat(5 * (10 ** 8))),
                                ("icrc1:name", #Text(Opt.get<Text>(default_token_args.name, "yuck"))),
                                ("icrc1:symbol", #Text(Opt.get<Text>(default_token_args.symbol, "yuk"))),
                                ("icrc1:decimals", #Nat(Nat8.toNat(default_token_args.decimals))),
                                ("icrc1:logo", #Text("data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbGw9InJlZCIvPjwvc3ZnPg==")),
                                ("test", #Text("test")),
                            ]]);
                }),

                it(
                    "mint()",
                    do {
                        D.print("testing mint");
                       

                        let icrc1 = get_icrc<system>(default_token_args);

                        let mint_args : T.Current.Mint = {
                            to = user1;
                            amount = 200 * (10 ** Nat8.toNat(default_token_args.decimals));
                            memo = null;
                            created_at_time = null;
                        };

                        let #trappable(res) = await* icrc1.mint_tokens(
                            canister.owner,
                            mint_args,
                            
                        );

                        assertAllTrue([
                            res == #Ok(0),
                            icrc1.balance_of( user1) == mint_args.amount,
                            icrc1.balance_of( canister) == 0,
                            icrc1.total_supply() == mint_args.amount,
                        ]);
                    },
                ),

                describe(
                    "burn()",
                    [
                        it(
                            "from funded account",
                            do {
                                D.print("testing burn");
                                let icrc1 = get_icrc<system>(default_token_args);

                                D.print("have class");
                                let mint_args : T.Current.Mint = {
                                    to = user1;
                                    amount = 200 * (10 ** Nat8.toNat(default_token_args.decimals));
                                    memo = null;
                                    created_at_time = null;
                                };

                                D.print("minting");
                                ignore await* icrc1.mint_tokens(
                                    canister.owner,
                                    mint_args,
                                    
                                );

                                let burn_args : T.Current.BurnArgs = {
                                    from_subaccount = user1.subaccount;
                                    amount = 50 * (10 ** Nat8.toNat(default_token_args.decimals));
                                    memo = null;
                                    created_at_time = null;
                                };

                                let prev_balance = icrc1.balance_of(user1);
                                let prev_total_supply = icrc1.total_supply();

                                D.print("burnin");
                                let #trappable(res) = await* icrc1.burn_tokens( user1.owner, burn_args,  false);
                                D.print("tests" # debug_show(prev_balance, burn_args, prev_total_supply));
                                assertAllTrue([
                                    res == #Ok(1),
                                    icrc1.balance_of(user1) == ((prev_balance - burn_args.amount) : Nat),
                                    icrc1.total_supply() == ((prev_total_supply - burn_args.amount) : Nat),
                                ]);
                            },
                        ),
                        it(
                            "from an empty account",
                            do {
                                D.print(" testing burn2");
                                let icrc1 = get_icrc<system>(default_token_args);

                                let burn_args : T.Current.BurnArgs = {
                                    from_subaccount = user1.subaccount;
                                    amount = 200 * (10 ** Nat8.toNat(default_token_args.decimals));
                                    memo = null;
                                    created_at_time = null;
                                };

                                let prev_balance = icrc1.balance_of(user1);
                                let prev_total_supply = icrc1.total_supply();
                                let #trappable(res) = await* icrc1.burn_tokens(user1.owner, burn_args,  false);

                                assertAllTrue([
                                    res == #Err(
                                        #InsufficientFunds {
                                            balance = 0;
                                        },
                                    ),
                                ]);
                            },
                        ),
                        it(
                            "burn amount less than min_burn_amount",
                            do {
                                D.print("burn3");
                                let icrc1 = get_icrc<system>(default_token_args);

                                let mint_args : T.Current.Mint = {
                                    to = user1;
                                    amount = 200 * (10 ** Nat8.toNat(default_token_args.decimals));
                                    memo = null;
                                    created_at_time = null;
                                };

                                ignore await* icrc1.mint_tokens(
                                    canister.owner,
                                    mint_args,
                                    
                                );

                                let burn_args : T.Current.BurnArgs = {
                                    from_subaccount = user1.subaccount;
                                    amount = 5 * (10 ** Nat8.toNat(default_token_args.decimals));
                                    memo = null;
                                    created_at_time = null;
                                };

                                let #trappable(res) = await* icrc1.burn_tokens(user1.owner, burn_args,  false);

                                assertAllTrue([
                                    res == #Err(
                                        #BadBurn {
                                            min_burn_amount = 10 * (10 ** 8);
                                        },
                                    ),
                                ]);
                            },
                        ),
                    ],
                ),
                describe(
                    "transfer()",
                    [
                        it(
                            "Transfer from funded account",
                            do {
                                D.print(" testing transfer");
                                let icrc1 = get_icrc<system>(default_token_args);

                                let mint_args = {
                                    to = user1;
                                    amount = 200 * (10 ** Nat8.toNat(icrc1.decimals()));
                                    memo = null;
                                    created_at_time = null;
                                };

                                ignore await* icrc1.mint_tokens(
                                    canister.owner,
                                    mint_args,
                                    
                                );

                                let transfer_args : T.Current.TransferArgs = {
                                    from_subaccount = user1.subaccount;
                                    to = user2;
                                    amount = 50 * (10 ** Nat8.toNat(icrc1.decimals()));
                                    fee = ?icrc1.fee();
                                    memo = null;
                                    created_at_time = null;
                                };

                                

                                let res_ = await* icrc1.transfer_tokens(
                                    user1.owner,
                                    transfer_args,
                                    false,
                                    null
                                );

                                 D.print("testing transfe" # debug_show(res_, icrc1.balance_of(user1), icrc1.get_state()._burned_tokens, icrc1.balance_of( user2), icrc1.total_supply()));

                                let #trappable(res) = res_;


                                assertAllTrue([
                                    res == #Ok(1),
                                    icrc1.balance_of(user1) == 14_500_000_000,
                                    icrc1.get_state()._burned_tokens ==  500_000_000,
                                    icrc1.balance_of( user2) == 5_000_000_000,
                                    icrc1.total_supply() == 19_500_000_000,
                                ]);
                            },
                        ),
                      it("Max Accounts Cleanup", do {

                          let icrc1 = get_icrc<system>({default_token_args with
                            max_accounts = ?100;
                            settle_to_accounts = ?75;
                          } : ICRC1.InitArgs);
                          
                          // Assuming an ICRC1 interface that allows setting a max number of accounts.
                          let max_accounts = 100; // Set the max accounts limit
                          let initial_accounts = Array.tabulate<ICRC1.Account>(max_accounts + 1, func(i : Nat) : ICRC1.Account {
                              { owner = user1.owner; subaccount = ?Blob.fromArray([ 
                                1,2,0,0,0,0,0,0,
                                0,0,0,0,0,0,0,0,
                                0,0,0,0,0,0,0,0,
                                0,0,0,0,0,0,0, Nat8.fromNat(i)])}
                          });

                          

                          // Add initial accounts to reach the limit
                          var tracker = 1;
                          for(thisItem in initial_accounts.vals()){
                            let result =  await* icrc1.mint_tokens(icrc1.minting_account().owner,
                            { to = thisItem; amount = tracker; memo = null; created_at_time = null; });
                            tracker +=1;
                            D.print(debug_show(result));
                          };

                          let fake1 = await Fake.Fake();
                          D.print("faking ");
                          let fake2 = await Fake.Fake();
                          let fake3 = await Fake.Fake();
                          let fake4 = await Fake.Fake();

                          D.print("size of items = " # debug_show(Map.size(icrc1.get_state().accounts)));

                          //simulate time

                          // Check that the account count is still within the limit and that the smallest account has been cleaned up
                          assertAllTrue([Map.size(icrc1.get_state().accounts) > 50,
                          Map.size(icrc1.get_state().accounts) < 80, //25 should have been deleted
                          List.size(icrc1.get_state().local_transactions) > 120, //removals should be in the trx log
                          Map.get(icrc1.get_state().accounts, account_compare, initial_accounts[0]) == null]); // Assuming 1 is the smallest
                        }
                      ),
                      it("Different Memos Pass Deduplication", do {

                        let icrc1 = get_icrc<system>(default_token_args);
                       
                        let tx_amount = 1000*e8s;
                        let mint =  await* icrc1.mint_tokens(canister.owner, 
                        { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                        
                         D.print("result for mint 1 was " # debug_show(mint));
                        // First transfer
                        let result1 = await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=?500_000_000; memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);
                        D.print("result for memo 1 was " # debug_show(result1));
                        // Second transfer with a different memo
                        let res = await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; fee=?500_000_000; created_at_time=null; memo = ?Text.encodeUtf8("Memo 2") },  false,
                                    null);

                        D.print("result for memo 2 was " # debug_show(res));
                        let #trappable(#Ok(result)) = res;

                        assertTrue(result > 0); // Check transaction index or proper variant
                      }), 
                      it("Different created_at_time Pass Deduplication", do {

                        let icrc1 = get_icrc<system>(default_token_args);
                       
                        let tx_amount = 1000*e8s;
                        let mint =  await* icrc1.mint_tokens(canister.owner, 
                        { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                        
                        D.print("result for mint 1 was " # debug_show(mint));
                        // First transfer
                        let result1 =  await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time =?Nat64.fromNat(Int.abs(Time.now())); fee=?500_000_000;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                        D.print("result for date 1 was " # debug_show(result1));

                        // Second transfer with a different memo
                        let res= await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; fee=?500_000_000; created_at_time= ?(Nat64.fromNat(Int.abs(Time.now() + 10_000))); memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);
                         D.print("result for date 2 was " # debug_show(res));

                        let #trappable(#Ok(result)) = res;

                       

                        assertTrue(result > 0); // Check transaction index or proper variant
                      }),
                      it("Different created_at_time Pass Deduplication", do {

                        let icrc1 = get_icrc<system>(default_token_args);
                       
                        let tx_amount = 1000*e8s;
                        let mint =  await* icrc1.mint_tokens(canister.owner,
                        { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                        
                        D.print("result for mint 1 was " # debug_show(mint));
                        // First transfer
                        let result1 =  await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time =?Nat64.fromNat(Int.abs(Time.now())); fee=?500_000_000;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                        D.print("result for date 1 was " # debug_show(result1));

                        // Second transfer with a different memo
                        let res= await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; fee=?500_000_000; created_at_time= ?(Nat64.fromNat(Int.abs(Time.now() + 10_000))); memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);
                         D.print("result for date 2 was " # debug_show(res));

                        let #trappable(#Ok(result)) = res;

                       

                        assertTrue(result > 0); // Check transaction index or proper variant
                      }),
                      /*
                      Deduplication is not supposed to be peformed if the created at time is null according otthe icrc1 spec, so this test was deactivated

                      it("Deduplication with Test Time", do {
                        test_time := Time.now();

                        let icrc1 = get_icrc<system>(default_token_args);
                       
                        let tx_amount = 1000*e8s;
                        let mint =  await* icrc1.mint_tokens(canister.owner,
                        { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                        
                         D.print("Deduplication result for mint 1 was " # debug_show(mint));
                        // First transfer
                        let result1 = await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=?500_000_000;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);
                        D.print(" Deduplication result for memo 1 was " # debug_show(result1));

                        // Second exact transfer should fail
                        let result2 = await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=?500_000_000;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                        D.print("Deduplication result for memo 2 was " # debug_show(result2));
                        let #trappable(#Err(#Duplicate(result))) = result2;

                       

                        //advance time past the window
                        
                        test_time := test_time + 86_400_000_000_001 + 60_000_000_000;

                        //let fake1 = await Fake.Fake();

                        let result3 = await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=?500_000_000;memo = ?Text.encodeUtf8("Memo 1") },  false, null);

                        D.print("Dedup result for memo 3 was " # debug_show(result3));
                        let #trappable(#Ok(res3)) = result3;

                         

                        assertAllTrue([res3 == 2 ,
                        result.duplicate_of == 1]); // Check transaction index or proper variant
                      }),*/
                      it("Transfer with Insufficient Funds", do {
                        let icrc1 = get_icrc<system>(default_token_args);
                       
                        let tx_amount = 1000*e8s;
                        let mint =  await* icrc1.mint_tokens(canister.owner,
                        { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                        // First transfer
                        let result1 = await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = tx_amount * 2; created_at_time=null; fee=?500_000_000;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                        D.print("Insufficent 1 was " # debug_show(result1));

                        let #trappable(#Err(#InsufficientFunds(res))) = result1;

                        assertTrue(res.balance == tx_amount);
                      }),
                      it("Transfer with higher fee ok", do {
                        let icrc1 = get_icrc<system>(default_token_args);
                        let tx_amount = 1000*e8s;
                        let mint =  await* icrc1.mint_tokens(canister.owner,
                        { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                        
                        // First transfer
                        let result1 = await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=?(icrc1.fee() + 1);memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                        D.print("valid fee " # debug_show(result1));

                        let #trappable(#Ok(res)) = result1;

                        D.print(debug_show(icrc1.balance_of(user1)));

                        assertAllTrue([
                          assertTrue(res == 1),
                          icrc1.balance_of(user1) == (1000*e8s) - 1 - (icrc1.fee() + 1),
                          icrc1.get_state()._burned_tokens == icrc1.fee() + 1
                          ]);
                      }),
                      it("Transfer with null fee ok", do {
                        let icrc1 = get_icrc<system>(default_token_args);
                        let tx_amount = 1000*e8s;
                        let mint =  await* icrc1.mint_tokens(canister.owner,
                        { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                        
                        // First transfer
                        let result1 = await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=null;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                        D.print("valid fee " # debug_show(result1));

                        let #trappable(#Ok(res)) = result1;

                        D.print(debug_show(icrc1.balance_of(user1)));

                        assertAllTrue([
                          assertTrue(res == 1),
                          icrc1.balance_of(user1) == (1000*e8s) - 1 - (icrc1.fee()),
                          icrc1.get_state()._burned_tokens == icrc1.fee()
                          ]);
                      }),
                      it("Transfer with lower fee fails", do {
                        let icrc1 = get_icrc<system>(default_token_args);
                        let tx_amount = 1000*e8s;
                        let mint =  await* icrc1.mint_tokens(canister.owner,
                        { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                        
                        // First transfer
                        let result1 = await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=?(icrc1.fee() - 1);memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                        D.print("invalid fee " # debug_show(result1));

                        let #trappable(#Err(#BadFee(res))) = result1;

                        assertTrue(res.expected_fee == icrc1.fee());
                      }),
                      it("Transfer created in future fails", do {
                        let icrc1 = get_icrc<system>(default_token_args);
                        let tx_amount = 1000*e8s;
                        let mint =  await* icrc1.mint_tokens(canister.owner,
                        { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                        
                        // First transfer
                        let result1 = await* icrc1.transfer_tokens(user1.owner,
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=?(U.get_time64() + icrc1.get_state().permitted_drift + 1); fee=null;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                        D.print("future " # debug_show(result1));

                        let #trappable(#Err(#CreatedInFuture(res))) = result1;

                        assertTrue(res.ledger_time == U.get_time64());
                      }),
                      it("Transfer too old fails", do {
                        let icrc1 = get_icrc<system>(default_token_args);
                        let tx_amount = 1000*e8s;
                        let mint =  await* icrc1.mint_tokens(canister.owner,
                        { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                        
                        // First transfer
                        let result1 = await* icrc1.transfer_tokens(user1.owner, 
                        { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=?(U.get_time64() - icrc1.get_state().transaction_window - icrc1.get_state().permitted_drift - 1); fee=null;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                        D.print("too old " # debug_show(result1));

                        let #trappable(#Err(#TooOld(res))) = result1;

                        assertTrue(result1 == #trappable(#Err(#TooOld)));
                      }),
                      it("External sync can_transfer invalidates a transaction",
                          do {
                              
                              let icrc1 = get_icrc<system>(default_token_args);
                              let tx_amount = 1000*e8s;

                              let mint =  await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                              
                              // First transfer
                              let result1 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=null;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    ?#Sync(externalCanTransferFalseSync));

                              D.print("reject sync " # debug_show(result1));

                              let #trappable(#Err(#GenericError(res))) = result1;

                              assertTrue(res.message == "always false");
                          }),
                          it("External async can_transfer invalidates a transaction",
                          do {
                              
                              let icrc1 = get_icrc<system>(default_token_args);
                              let tx_amount = 1000*e8s;

                              let mint =  await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                              
                              // First transfer
                              let result1 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=null;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    ?#Async(externalCanTransferFalseAsync));

                              D.print("reject async " # debug_show(result1));

                              let #awaited(#Err(#GenericError(res))) = result1;

                              assertTrue(res.message == "always false");
                          }),
                          it("External sync can_transfer updates a transaction",
                          do {
                              
                              let icrc1 = get_icrc<system>(default_token_args);
                              let tx_amount = 1000*e8s;

                              let mint =  await* icrc1.mint_tokens(canister.owner, { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                              
                              // First transfer
                              let result1 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=null;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    ?#Sync(externalCanTransferUpdateSync));

                              D.print("update sync " # debug_show(result1));

                              let #trappable(#Ok(res)) = result1;
                              let ledger = List.toArray(icrc1.get_local_transactions());
                              let ?trn = ledger[1].transfer;

                              assertAllTrue([
                                res == 1,
                                trn.amount == 2
                              ]);
                          }),
                          it("External async can_transfer updates a transaction",
                          do {
                              
                              let icrc1 = get_icrc<system>(default_token_args);
                              let tx_amount = 1000*e8s;

                              let mint =  await* icrc1.mint_tokens( canister.owner, { to = user1; amount = tx_amount; memo = null; created_at_time = null; },);
                              
                              // First transfer
                              let result1 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=null;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    ?#Async(externalCanTransferUpdateAsync));

                              D.print("update async " # debug_show(result1));

                              let #awaited(#Ok(res)) = result1;
                              let ledger = List.toArray(icrc1.get_local_transactions());
                              let ?trn = ledger[1].transfer;

                               assertAllTrue([
                                res == 1,
                                trn.amount == 2
                              ]);
                          }),
                          it("Cant transfer to self",
                          do {
                              
                              let icrc1 = get_icrc<system>(default_token_args);
                              let tx_amount = 1000*e8s;

                              let mint =  await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                              
                              // First transfer
                              let result1 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user1; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=null;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                              D.print("update self send " # debug_show(result1));

                              let #trappable(#Err(#GenericError(res))) = result1;

                               assertAllTrue([
                                res.error_code == 1,
                              ]);
                          }),
                          it("Cant have 0 amount in transfer",
                          do {
                              
                              let icrc1 = get_icrc<system>(default_token_args);
                              let tx_amount = 1000*e8s;

                              let mint =  await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                              
                              // First transfer
                              let result1 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 0; created_at_time=null; fee=null;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                              D.print("update self send " # debug_show(result1));

                              let #trappable(#Err(#GenericError(res))) = result1;

                               assertAllTrue([
                                res.error_code == 5,
                              ]);
                          }),

                          it("Minting account cannot transfer to itself (ICRC-3 refinement)",
                          do {
                              // Per ICRC-3 refinement: If both the sender and the recipient 
                              // resolve to the minting account in the same call, the ledger MUST reject the call
                              let icrc1 = get_icrc<system>(default_token_args);
                              
                              // Attempt to transfer from minting account to minting account
                              let result = await* icrc1.transfer_tokens(canister.owner,
                              { 
                                to = canister; // minting account is canister
                                from_subaccount = canister.subaccount; 
                                amount = 1000; 
                                created_at_time = null; 
                                fee = null;
                                memo = null;
                              },  false, null);

                              D.print("minting account self transfer " # debug_show(result));

                              let #trappable(#Err(#GenericError(res))) = result;

                              assertAllTrue([
                                res.error_code == 7,
                                Text.contains(res.message, #text "minting account"),
                              ]);
                          }),

                          it("Can listen for tranfers",
                          do {
                              
                              let icrc1 = get_icrc<system>(default_token_args);
                              let tx_amount = 1000*e8s;

                               var called_count = 0;

                              let a_func = func<system>(trx: ICRC1.Transaction, trxid: Nat){
                                 D.print("listner called " # debug_show(trx));
                                called_count += 1;
                              };
                              
                              icrc1.register_token_transferred_listener("icrc_test", a_func);

                              let mint =  await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = tx_amount; memo = null; created_at_time = null; });

                             
                              
                              // First transfer
                              let result1 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=null;memo = ?Text.encodeUtf8("Memo 1") },  false,
                                    null);

                              D.print("listner result " # debug_show(result1));

                              

                               assertAllTrue([
                                called_count == 2,
                              ]);
                          }),

                          // ========== DEDUPLICATION EDGE CASES ==========

                          it("Null created_at_time skips deduplication per ICRC-1 spec", do {
                              // Per ICRC-1: if created_at_time is null, deduplication is NOT performed
                              let icrc1 = get_icrc<system>(default_token_args);
                              let tx_amount = 1000*e8s;

                              ignore await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                              
                              // Two identical transfers with null created_at_time should both succeed
                              let result1 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=null; memo = ?Text.encodeUtf8("Same Memo") },  false, null);

                              let result2 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=null; fee=null; memo = ?Text.encodeUtf8("Same Memo") },  false, null);

                              D.print("null created_at_time dedup test: " # debug_show(result1, result2));

                              // Both should succeed (no deduplication when created_at_time is null)
                              let #trappable(#Ok(idx1)) = result1;
                              let #trappable(#Ok(idx2)) = result2;

                              assertAllTrue([
                                idx2 > idx1,
                              ]);
                          }),

                          it("Same memo and created_at_time triggers deduplication", do {
                              let icrc1 = get_icrc<system>(default_token_args);
                              let tx_amount = 1000*e8s;

                              ignore await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                              
                              let created_time = Nat64.fromNat(Int.abs(Time.now()));
                              
                              // First transfer with created_at_time set
                              let result1 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=?created_time; fee=null; memo = ?Text.encodeUtf8("Dedup Test") },  false, null);

                              // Second identical transfer should be deduplicated
                              let result2 = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 1; created_at_time=?created_time; fee=null; memo = ?Text.encodeUtf8("Dedup Test") },  false, null);

                              D.print("deduplication test: " # debug_show(result1, result2));

                              let #trappable(#Ok(idx1)) = result1;
                              let #trappable(#Err(#Duplicate(dup))) = result2;

                              assertAllTrue([
                                dup.duplicate_of == idx1,
                              ]);
                          }),

                          // ========== ACCOUNT PRUNING TESTS ==========

                          it("Pruning removes smallest balances first", do {
                              let icrc1 = get_icrc<system>({default_token_args with
                                max_accounts = ?20;
                                settle_to_accounts = ?10;
                              } : ICRC1.InitArgs);
                              
                              // Create 21 accounts with different balances (1 to 21 tokens)
                              let accounts = Array.tabulate<ICRC1.Account>(21, func(i : Nat) : ICRC1.Account {
                                  { owner = user1.owner; subaccount = ?Blob.fromArray([ 
                                    1,2,0,0,0,0,0,0,
                                    0,0,0,0,0,0,0,0,
                                    0,0,0,0,0,0,0,0,
                                    0,0,0,0,0,0,0, Nat8.fromNat(i)])}
                              });

                              // Mint increasing amounts to each account
                              var amount = 1;
                              for(acct in accounts.vals()){
                                ignore await* icrc1.mint_tokens(icrc1.minting_account().owner,
                                { to = acct; amount = amount; memo = null; created_at_time = null; });
                                amount += 1;
                              };

                              // Wait for timer to process cleanup
                              let fake1 = await Fake.Fake();
                              let fake2 = await Fake.Fake();
                              let fake3 = await Fake.Fake();

                              D.print("Pruning test - accounts after cleanup: " # debug_show(Map.size(icrc1.get_state().accounts)));

                              // Check that smallest accounts were pruned
                              // Account with 1 token (first account) should be gone
                              let account0Exists = Map.get(icrc1.get_state().accounts, account_compare, accounts[0]) != null;
                              // Account with 21 tokens (last account) should exist
                              let account20Exists = Map.get(icrc1.get_state().accounts, account_compare, accounts[20]) != null;

                              assertAllTrue([
                                Map.size(icrc1.get_state().accounts) <= 15, // Should be around settle_to_accounts
                                not account0Exists, // Smallest balance should be pruned
                                account20Exists, // Largest balance should remain
                              ]);
                          }),

                          it("Pruning creates burn transactions with clean memo", do {
                              let icrc1 = get_icrc<system>({default_token_args with
                                max_accounts = ?10;
                                settle_to_accounts = ?5;
                              } : ICRC1.InitArgs);
                              
                              // Create 11 accounts
                              for(i in Itertools.range(0, 11)){
                                let acct = { owner = user1.owner; subaccount = ?Blob.fromArray([ 
                                    1,2,0,0,0,0,0,0,
                                    0,0,0,0,0,0,0,0,
                                    0,0,0,0,0,0,0,0,
                                    0,0,0,0,0,0,0, Nat8.fromNat(i)])};
                                ignore await* icrc1.mint_tokens(icrc1.minting_account().owner,
                                { to = acct; amount = i + 1; memo = null; created_at_time = null; });
                              };

                              // Wait for cleanup
                              let fake1 = await Fake.Fake();
                              let fake2 = await Fake.Fake();

                              // Check transaction log for burn transactions with "clean" memo
                              let txLog = List.toArray(icrc1.get_local_transactions());
                              var cleanBurnCount = 0;
                              for(tx in txLog.vals()){
                                switch(tx.burn){
                                  case(?burn){
                                    switch(burn.memo){
                                      case(?memo){
                                        if(Text.decodeUtf8(memo) == ?"clean"){
                                          cleanBurnCount += 1;
                                        };
                                      };
                                      case(null){};
                                    };
                                  };
                                  case(null){};
                                };
                              };

                              D.print("Clean burn count: " # debug_show(cleanBurnCount));

                              assertTrue(cleanBurnCount > 0);
                          }),

                          // ========== FEE COLLECTOR TESTS (ICRC-107) ==========

                          it("Fee collector receives transfer fees", do {
                              let fee_collector : ICRC1.Account = {
                                owner = Principal.fromText("2dzql-vc5j3-p5nyh-vidom-fhtyt-edvv6-bqewt-j63fn-ovwug-h67hb-yqe"); 
                                subaccount = null
                              };
                              
                              let icrc1 = get_icrc<system>({default_token_args with
                                fee_collector = ?fee_collector;
                              } : ICRC1.InitArgs);
                              
                              let tx_amount = 1000*e8s;
                              ignore await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                              
                              let initial_collector_balance = icrc1.balance_of(fee_collector);
                              let initial_burned = icrc1.get_state()._burned_tokens;
                              
                              // Do a transfer
                              let result = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 100; created_at_time=null; fee=null; memo = null },  false, null);

                              D.print("Fee collector test: " # debug_show(result));

                              let final_collector_balance = icrc1.balance_of(fee_collector);
                              let final_burned = icrc1.get_state()._burned_tokens;
                              let expected_fee = icrc1.fee();

                              assertAllTrue([
                                final_collector_balance == initial_collector_balance + expected_fee,
                                final_burned == initial_burned, // Fee should NOT be burned
                              ]);
                          }),

                          it("Removing fee collector causes fees to be burned (ICRC-107)", do {
                              let fee_collector : ICRC1.Account = {
                                owner = Principal.fromText("2dzql-vc5j3-p5nyh-vidom-fhtyt-edvv6-bqewt-j63fn-ovwug-h67hb-yqe"); 
                                subaccount = null
                              };
                              
                              let icrc1 = get_icrc<system>({default_token_args with
                                fee_collector = ?fee_collector;
                              } : ICRC1.InitArgs);
                              
                              let tx_amount = 1000*e8s;
                              ignore await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                              
                              // Do first transfer - fee goes to collector
                              ignore await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 100; created_at_time=null; fee=null; memo = null },  false, null);
                              
                              let collector_balance_after_first = icrc1.balance_of(fee_collector);
                              
                              // Remove fee collector
                              ignore icrc1.update_ledger_info([#FeeCollector(null)]);
                              
                              let burned_before_second = icrc1.get_state()._burned_tokens;
                              
                              // Do second transfer - fee should now be burned
                              ignore await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 100; created_at_time=null; fee=null; memo = ?Text.encodeUtf8("after removal") },  false, null);
                              
                              let collector_balance_after_second = icrc1.balance_of(fee_collector);
                              let burned_after_second = icrc1.get_state()._burned_tokens;
                              let expected_fee = icrc1.fee();

                              D.print("ICRC-107 removal test: collector before=" # debug_show(collector_balance_after_first) # 
                                     " after=" # debug_show(collector_balance_after_second) #
                                     " burned before=" # debug_show(burned_before_second) #
                                     " after=" # debug_show(burned_after_second));

                              assertAllTrue([
                                collector_balance_after_first > 0, // First transfer went to collector
                                collector_balance_after_second == collector_balance_after_first, // Collector didn't get more
                                burned_after_second == burned_before_second + expected_fee, // Fee was burned
                              ]);
                          }),

                          // ========== MAX SUPPLY ENFORCEMENT ==========

                          it("Cannot mint beyond max_supply", do {
                              let icrc1 = get_icrc<system>({default_token_args with
                                max_supply = ?(1000);
                              } : ICRC1.InitArgs);
                              
                              // Mint exactly max supply
                              ignore await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = 1000; memo = null; created_at_time = null; });
                              
                              // Try to mint 1 more
                              let result = await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = 1; memo = null; created_at_time = null; });

                              D.print("Max supply enforcement: " # debug_show(result));

                              let #trappable(#Err(#GenericError(err))) = result;

                              assertAllTrue([
                                err.error_code == 6,
                                Text.contains(err.message, #text "Cannot mint"),
                              ]);
                          }),

                          it("Burns allow re-minting up to max_supply", do {
                              let icrc1 = get_icrc<system>({default_token_args with
                                max_supply = ?(1000);
                                min_burn_amount = ?(1);
                              } : ICRC1.InitArgs);
                              
                              // Mint to max
                              ignore await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = 1000; memo = null; created_at_time = null; });
                              
                              // Burn some
                              ignore await* icrc1.burn_tokens(user1.owner,
                              { from_subaccount = user1.subaccount; amount = 100; memo = null; created_at_time = null; }, false);
                              
                              // Should be able to mint again
                              let result = await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = 50; memo = null; created_at_time = null; });

                              D.print("Re-mint after burn: " # debug_show(result));

                              let #trappable(#Ok(idx)) = result;

                              assertTrue(idx > 0);
                          }),

                          // ========== ASYNC CAN_TRANSFER TESTS ==========

                          it("Async can_transfer rejection preserves state", do {
                              let icrc1 = get_icrc<system>(default_token_args);
                              let tx_amount = 1000*e8s;

                              ignore await* icrc1.mint_tokens(canister.owner,
                              { to = user1; amount = tx_amount; memo = null; created_at_time = null; });
                              
                              let initial_balance = icrc1.balance_of(user1);
                              let initial_supply = icrc1.total_supply();
                              
                              // Transfer with async rejection
                              let result = await* icrc1.transfer_tokens(user1.owner,
                              { to = user2; from_subaccount = user1.subaccount; amount = 100; created_at_time=null; fee=null; memo = null },  false,
                              ?#Async(externalCanTransferFalseAsync));

                              D.print("Async rejection state test: " # debug_show(result));

                              // State should be unchanged
                              assertAllTrue([
                                icrc1.balance_of(user1) == initial_balance,
                                icrc1.total_supply() == initial_supply,
                              ]);
                          })

                    ],
                ),

            ],
        );
    };

    public func testInitInvalidParameters() : async ActorSpec.Group {
      D.print("in testInitInvalidParameters");
      let spender1 : ICRC1.Account = {owner = Principal.fromText("2dzql-vc5j3-p5nyh-vidom-fhtyt-edvv6-bqewt-j63fn-ovwug-h67hb-yqe"); subaccount = ?Blob.fromArray([ 1,2,0,0,0,0,0,0,
                  0,0,0,0,0,0,0,0,
                  0,0,0,0,0,0,0,0,
                  0,0,0,0,0,0,0,0])};
      let spender2 : ICRC1.Account = {owner = Principal.fromText("32fn4-qqaaa-aaaak-ad65a-cai"); subaccount = ?Blob.fromArray([3,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0])};
      let owner : ICRC1.Account = {owner = Principal.fromText("zfcdd-tqaaa-aaaaq-aaaga-cai"); subaccount = ?Blob.fromArray([5,6,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0])};
      let spender4 : ICRC1.Account = {owner = Principal.fromText("x33ed-h457x-bsgyx-oqxqf-6pzwv-wkhzr-rm2j3-npodi-purzm-n66cg-gae"); subaccount = ?Blob.fromArray([7,8,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0])};
      let spender5 : ICRC1.Account = {owner = Principal.fromText("dtnbn-kyaaa-aaaak-aeigq-cai"); subaccount = ?Blob.fromArray([9,10,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0])};

    let {
      assertAllTrue;
      it;
      describe;
      run;
    } = ActorSpec;

    let faultyInitialBalances : [(T.Current.Account, Nat)] = [
      (spender1, 100),   // Make more initial than possibl max
      (spender2, 100),    // Positive initial balance
    ];

    // Negative max_supply
    let negativeMaxSupplyArgs : T.Current.InitArgs = {
      name = ?"Invalid Token";
      symbol = ?"INV";
      logo = ?"data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMSIgaGVpZ2h0PSIxIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPjxyZWN0IHdpZHRoPSIxMDAlIiBoZWlnaHQ9IjEwMCUiIGZpbGw9InJlZCIvPjwvc3ZnPg==";
      decimals = 8;
      fee = ?#Fixed(5 * (10 ** 8));
      max_supply = ?(100);
      minting_account = null;
      min_burn_amount = ?(10 * (10 ** 8));
      advanced_settings = null;
      metadata = null;
      max_memo = null;
      fee_collector = null;
      permitted_drift = null;
            transaction_window = null;
            max_accounts = null;
            settle_to_accounts = null;
    };

    let canister : T.Current.Account = {
        owner = Principal.fromText("x4ocp-k7ot7-oiqws-rg7if-j4q2v-ewcel-2x6we-l2eqz-rfz3e-6di6e-jae");
        subaccount = null;
    };

    var test_environment : T.Current.Environment = {
      advanced = null;
      add_ledger_transaction = null;
      var org_icdevs_timer_tool = null;
      var org_icdevs_class_plus_manager = null;
    };

    var stored_state = ICRC1.initialState();

    func pullEnv() : ICRC1.Environment {
      test_environment;
    };

    let manager = ClassPlusLib.ClassPlusInitializationManager<system>(canister.owner, canister.owner, false);
    let getIcrc1 = ICRC1.Init({
      org_icdevs_class_plus_manager = manager;
      initialState = ICRC1.initialState();
      args = ?negativeMaxSupplyArgs;
      pullEnvironment = ?pullEnv;
      onInitialize = null;
      onStorageChange = func(_state : ICRC1.State) {
        stored_state := _state;
      };
    });
    let icrc1 = getIcrc1();

   for(thisItem in faultyInitialBalances.vals()){
    ignore await* icrc1.mint_tokens(icrc1.minting_account().owner,
    {
      to = thisItem.0;
      amount = thisItem.1;
      memo = ?Text.encodeUtf8("init");
      created_at_time = null;
    })
  };

    return describe("ICRC-1 Token Initialization with initial balances over max supply only mints to max supply", [
      it("Only mints  up to the max supply", do {
        D.print("total supply over " # debug_show(icrc1.total_supply()));
        assertAllTrue([icrc1.total_supply() == 100]);
      }),
      
    ]);
  };
};
