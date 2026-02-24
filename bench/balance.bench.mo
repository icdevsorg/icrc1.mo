/// ICRC1 Balance Operations Benchmark
/// 
/// Benchmarks for ICRC1 balance lookup and update operations
/// directly using the library's Utils module.

import Bench "mo:bench";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Iter "mo:core/Iter";
import Principal "mo:core/Principal";
import Blob "mo:core/Blob";
import Array "mo:core/Array";
import Map "mo:core/Map";

// Import ICRC1 Utils directly
import Utils "../src/ICRC1/Utils";
import MigrationTypes "../src/ICRC1/migrations/types";

module {
  public func init() : Bench.Bench {
    let bench = Bench.Bench();

    bench.name("ICRC1 Balance Operations");
    bench.description("Balance lookup and update using ICRC1.Utils functions");

    bench.rows(["get_balance", "update_balance"]);
    bench.cols(["100", "1000", "10000"]);

    type Account = MigrationTypes.Current.Account;
    type Balance = MigrationTypes.Current.Balance;
    let account_compare = MigrationTypes.Current.account_compare;

    // Generate test accounts with valid principal sizes (<=29 bytes)
    func generateAccount(i : Nat) : Account {
      let bytes = Array.tabulate<Nat8>(29, func(j : Nat) : Nat8 {
        if (j < 4) {
          let shifted = (i / Nat.pow(256, j)) % 256;
          Nat8.fromNat(shifted);
        } else {
          0;
        };
      });
      {
        owner = Principal.fromBlob(Blob.fromArray(bytes));
        subaccount = null;
      };
    };

    bench.runner(func(row, col) {
      let ?n = Nat.fromText(col) else return;

      // Create and populate accounts map
      let accounts = Map.empty<Account, Balance>();
      for (i in Iter.range(0, n - 1)) {
        Map.add(accounts, account_compare, generateAccount(i), 1000000);
      };

      if (row == "get_balance") {
        for (i in Iter.range(0, n - 1)) {
          ignore Utils.get_balance(accounts, generateAccount(i));
        };
      };

      if (row == "update_balance") {
        for (i in Iter.range(0, n - 1)) {
          Utils.update_balance(accounts, generateAccount(i), func(b) { b + 100 });
        };
      };
    });

    bench;
  };
};
