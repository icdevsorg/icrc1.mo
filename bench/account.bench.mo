/// ICRC1 Account Operations Benchmark
/// 
/// Benchmarks for ICRC1 account operations directly using 
/// the library's Account and Utils modules.

import Bench "mo:bench";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Iter "mo:core/Iter";
import Principal "mo:core/Principal";
import Blob "mo:core/Blob";
import Array "mo:core/Array";

// Import ICRC1 modules directly
import Account "../src/ICRC1/Account";
import Utils "../src/ICRC1/Utils";
import MigrationTypes "../src/ICRC1/migrations/types";

module {
  public func init() : Bench.Bench {
    let bench = Bench.Bench();

    bench.name("ICRC1 Account Operations");
    bench.description("Account validation, encoding, decoding using ICRC1 modules");

    bench.rows(["validate", "encode", "decode", "hash"]);
    bench.cols(["100", "1000", "10000"]);

    type AccountType = MigrationTypes.Current.Account;

    // Generate test accounts with valid principal sizes (<=29 bytes)
    func generateAccount(i : Nat) : AccountType {
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

      if (row == "validate") {
        for (i in Iter.range(0, n - 1)) {
          ignore Account.validate(generateAccount(i));
        };
      };

      if (row == "encode") {
        for (i in Iter.range(0, n - 1)) {
          ignore Account.encodeAccount(generateAccount(i));
        };
      };

      if (row == "decode") {
        let encoded = Array.tabulate<Text>(n, func(i : Nat) : Text {
          Account.encodeAccount(generateAccount(i));
        });
        for (i in Iter.range(0, n - 1)) {
          ignore Account.decodeAccount(encoded[i]);
        };
      };

      if (row == "hash") {
        for (i in Iter.range(0, n - 1)) {
          ignore Utils.hash(i);
        };
      };
    });

    bench;
  };
};
