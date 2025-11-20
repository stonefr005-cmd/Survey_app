# Survey Liquidity Pools – Documentary

## Concept

The **Survey Liquidity Pools** app is a Stacks smart-contract powered protocol that lets sponsors
fund survey campaigns with STX liquidity and lets respondents claim rewards trustlessly.

Instead of hard‑coding survey questions on-chain, this design focuses on **liquidity and incentive
management**, which is what blockchains are best at:

- A **campaign** corresponds to an incentivized survey (questions live off-chain).
- A **sponsor** deposits STX into a per‑campaign liquidity pool.
- **Respondents** claim a fixed STX reward at most once per campaign.
- The **campaign owner** can close the campaign and withdraw any unclaimed liquidity.

This gives survey platforms a reusable on-chain primitive for funding and settling rewards while
keeping the heavy survey UX and analytics off-chain.

## Smart contract design

Contract: `contracts/survey-liquidity.clar`

### Data model

- `next-campaign-id: uint`
  - Monotonic counter used as campaign identifier; the first campaign has id `u0`.
- `campaigns: { id: uint } -> { owner, reward-per-response, total-deposited, total-claimed, active }`
  - `owner`: principal that created the campaign and controls closing/refunds.
  - `reward-per-response`: fixed STX reward paid per successful claim.
  - `total-deposited`: total STX ever deposited into the pool.
  - `total-claimed`: cumulative STX paid out to respondents.
  - `active`: boolean flag; when `false`, new claims and deposits are rejected.
- `claims: { id: uint, user: principal } -> { claimed: bool }`
  - Tracks which principals have already claimed for a given campaign.

### Public functions

1. `create-campaign (reward-per-response uint) (initial-liquidity uint)`

   - Validates that `reward-per-response > 0` and `initial-liquidity >= reward-per-response`.
   - Transfers `initial-liquidity` STX from `tx-sender` into the contract using
     `stx-transfer? initial-liquidity tx-sender (as-contract tx-sender)`.
   - Mints a new campaign entry in `campaigns` with `active = true`.
   - Returns the assigned `campaign-id` (`u0`, `u1`, ...).

2. `deposit-liquidity (id uint) (amount uint)`

   - Requires `amount > 0`.
   - Fails with `ERR-CAMPAIGN-NOT-FOUND (err u100)` if the id is unknown.
   - Fails with `ERR-CAMPAIGN-INACTIVE (err u102)` if the campaign is closed.
   - Transfers `amount` STX from `tx-sender` into the contract.
   - Increases `total-deposited` while preserving other campaign fields.
   - Returns `amount` on success.

3. `claim-reward (id uint)`

   - Loads the campaign, failing with `ERR-CAMPAIGN-NOT-FOUND (err u100)` if missing.
   - Rejects if `active = false` (`ERR-CAMPAIGN-INACTIVE (err u102)`).
   - Binds three locals:
     - `user = tx-sender`
     - `reward = reward-per-response`
     - `unclaimed = total-deposited - total-claimed`
   - If `claims` already has an entry for `{ id, user }`, returns `ERR-ALREADY-CLAIMED (err u103)`.
   - If `unclaimed < reward`, returns `ERR-INSUFFICIENT-LIQUIDITY (err u104)`.
   - Otherwise:
     - Marks `{ id, user }` as `{ claimed: true }`.
     - Increments `total-claimed` by `reward`.
     - From within `as-contract`, transfers `reward` STX from the contract
       to `user` using `stx-transfer?`.
     - Returns `reward` in the `ok` branch.

4. `close-campaign (id uint)`

   - Only the `owner` of the campaign may close it; others receive `ERR-NOT-OWNER (err u101)`.
   - Marks `active = false` to permanently disable new deposits and claims.
   - Computes `unclaimed = total-deposited - total-claimed`.
   - From within `as-contract`, transfers any positive `unclaimed` amount from the contract
     back to the owner.
   - Returns the amount refunded (possibly `u0`).

### Read-only helpers

- `get-next-campaign-id` – returns the current value of `next-campaign-id`.
- `get-campaign (id)` – returns campaign tuple or `ERR-CAMPAIGN-NOT-FOUND`.
- `get-claim-status (id user)` – boolean flag for `claims` membership.
- `get-unclaimed-balance (id)` – derived view of `total-deposited - total-claimed`.

### Error codes

- `u100` – campaign not found
- `u101` – not owner
- `u102` – campaign inactive
- `u103` – already claimed
- `u104` – insufficient liquidity
- `u105` – invalid parameters

These are intentionally compact so that UI code can branch on small integers.

## Testing strategy

Tests live in `tests/survey-liquidity.test.ts` and run via Vitest with the
`vitest-environment-clarinet` environment. The environment exposes a global
`simnet` object representing the Clarinet simnet.

Key patterns in the tests:

- Use `simnet.getAccounts()` to fetch named wallets like `deployer`, `wallet_1`, etc.
- Call public functions with `simnet.callPublicFn("survey-liquidity", "fn-name", args, sender)`.
- Call read‑only functions with `simnet.callReadOnlyFn`.
- Build Clarity values with the `Cl` helper from `@stacks/transactions` (e.g. `Cl.uint(100_000)`).
- Assert on responses and values using custom matchers like `toBeOk`, `toBeErr`, `toBeUint`.

Covered flows:

1. **Campaign creation** – verifies that `create-campaign` returns `ok u0`.
2. **Liquidity deposits** – verifies that third parties can call `deposit-liquidity` and that
   `get-unclaimed-balance` reflects the increased pool size.
3. **Reward claims** – ensures a respondent can claim once for a funded campaign and that a
   second attempt fails with `ERR-ALREADY-CLAIMED`.
4. **Campaign closure** – ensures the owner recovers exactly the remaining unclaimed STX when
   closing a campaign after one successful claim.

All tests pass via `npm test` in the `survey-liquidity-app` directory.

## UI concept (high level)

A minimal but meaningful UI for this app would include:

- **Campaign sponsor view**
  - Form to create a campaign:
    - Reward per response (in microSTX)
    - Initial liquidity (microSTX)
  - List of owned campaigns showing:
    - Campaign id, reward per response, unclaimed balance, and active/closed status.
  - Actions:
    - Deposit more liquidity into an active campaign.
    - Close a campaign to reclaim unclaimed funds.

- **Respondent view**
  - Input for a campaign id shared off‑chain (e.g., via survey link).
  - Button to claim reward for that campaign, wired to `claim-reward`.
  - Clear error messages when:
    - The campaign does not exist.
    - The campaign is inactive.
    - The respondent already claimed.
    - The pool is out of liquidity.

The UI would connect to the contract via a Stacks wallet (e.g. Hiro Wallet) and use
`@stacks/transactions` or stacks.js to build and broadcast transactions that call the
public functions documented above.

## How to run locally

From `survey-liquidity-app/`:

```sh
npm install   # already run once, but safe to repeat
npm test      # runs the Clarinet/Vitest suite against the simnet
clarinet console  # optional: open an interactive console to play with the contract
```

This documentary, combined with the contract and tests, should give a clear picture of how the
Survey Liquidity Pools protocol works end‑to‑end.