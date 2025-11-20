import { describe, it, expect } from "vitest";
import { Cl } from "@stacks/transactions";

// The `simnet` object is provided globally by vitest-environment-clarinet.
// It exposes high-level helpers to call public and read-only functions.

describe("survey-liquidity contract", () => {
  it("creates a campaign and stores config with initial liquidity", () => {
    const accounts = simnet.getAccounts();
    const deployer = accounts.get("deployer");
    if (!deployer) throw new Error("Missing deployer account");

    const create = simnet.callPublicFn(
      "survey-liquidity",
      "create-campaign",
      [Cl.uint(100_000), Cl.uint(1_000_000)],
      deployer
    );

    expect(create.result).toBeOk(Cl.uint(0));
    // Detailed campaign tuple behavior is validated indirectly
    // via unclaimed-balance and reward-claim flows in later tests.
  });

  it("allows depositing additional liquidity into a campaign", () => {
    const accounts = simnet.getAccounts();
    const deployer = accounts.get("deployer");
    const sponsor = accounts.get("wallet_1");
    if (!deployer || !sponsor) throw new Error("Missing test accounts");

    simnet.callPublicFn(
      "survey-liquidity",
      "create-campaign",
      [Cl.uint(100_000), Cl.uint(1_000_000)],
      deployer
    );

    const deposit = simnet.callPublicFn(
      "survey-liquidity",
      "deposit-liquidity",
      [Cl.uint(0), Cl.uint(500_000)],
      sponsor
    );

    expect(deposit.result).toBeOk(Cl.uint(500_000));

    const unclaimed = simnet.callReadOnlyFn(
      "survey-liquidity",
      "get-unclaimed-balance",
      [Cl.uint(0)],
      deployer
    );

    expect(unclaimed.result).toBeOk(Cl.uint(1_500_000));
  });

  it("lets a respondent claim once and rejects double claims", () => {
    const accounts = simnet.getAccounts();
    const deployer = accounts.get("deployer");
    const respondent = accounts.get("wallet_2");
    if (!deployer || !respondent) throw new Error("Missing test accounts");

    simnet.callPublicFn(
      "survey-liquidity",
      "create-campaign",
      [Cl.uint(100_000), Cl.uint(1_000_000)],
      deployer
    );

    const firstClaim = simnet.callPublicFn(
      "survey-liquidity",
      "claim-reward",
      [Cl.uint(0)],
      respondent
    );

    expect(firstClaim.result).toBeOk(Cl.uint(100_000));

    const secondClaim = simnet.callPublicFn(
      "survey-liquidity",
      "claim-reward",
      [Cl.uint(0)],
      respondent
    );

    // ERR-ALREADY-CLAIMED = u103
    expect(secondClaim.result).toBeErr(Cl.uint(103));
  });

  it("allows the owner to close campaign and withdraw unclaimed liquidity", () => {
    const accounts = simnet.getAccounts();
    const deployer = accounts.get("deployer");
    const respondent = accounts.get("wallet_3");
    if (!deployer || !respondent) throw new Error("Missing test accounts");

    simnet.callPublicFn(
      "survey-liquidity",
      "create-campaign",
      [Cl.uint(100_000), Cl.uint(1_000_000)],
      deployer
    );

    simnet.callPublicFn(
      "survey-liquidity",
      "claim-reward",
      [Cl.uint(0)],
      respondent
    );

    const close = simnet.callPublicFn(
      "survey-liquidity",
      "close-campaign",
      [Cl.uint(0)],
      deployer
    );

    // 1_000_000 - 100_000 = 900_000 left to withdraw
    expect(close.result).toBeOk(Cl.uint(900_000));
  });
});
