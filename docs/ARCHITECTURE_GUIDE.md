# Technical Architecture Guide — Phase 1 Infrastructure & Core


**Project:** Apex Finance

---

## 1. System Context Diagram (C4 Level 1)

The system context below describes how actors interact with the core contracts deployed during Phase 1 and establishes boundaries for future phases (AMM & Governance).

┌────────────────────────────────────────────────────────┐
│                     Web3 End User                      │
└───────┬───────────────────┬────────────────────┬───────┘
│                   │                    │
│ (1) Call functions│ (2) Gasless Appr.  │ (3) Mint/Trade
▼                   ▼                    ▼
┌────────────────────┐┌─────────────────┐┌────────────────────┐
│   ApexPlatform     ││    ApexToken    ││    PoolFactory     │
│   (UUPS Proxy)     ││ (ERC20 + Votes) ││   (CREATE/CREATE2) │
└──────────┬─────────┘└─────────────────┘└─────────┬──────────┘
│                                       │
▼ (DelegateCalls)                       ▼ (Deploys)
┌────────────────────┐                   ┌────────────────────┐
│   ApexPlatformV1   │                   │    Future Pools    │
│  Implementation    │                   │     By Part. 2     │
└────────────────────┘                   └────────────────────┘


---

## 2. Storage Layout & Proxy Collision Prevention

To ensure safe upgradeability via the **UUPS (Universal Upgradeable Proxy Standard)** pattern, `ApexPlatformV1` carefully manages its storage slots. 

Inheriting from OpenZeppelin’s upgradeable contracts introduces a specific layout matrix. In Solidity, state variables are allocated sequentially starting from slot 0.

### Slot Allocation Matrix for `ApexPlatformV1`:
* **OpenZeppelin Base Classes Slots:** Contained within namespaced storage slots (ERC-1967 storage slots) to mitigate collision risks (`0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc` for implementation pointer).
* **Slot 0:** `uint256 public platformFee` — Stores the global trading fee in basis points (e.g., 30 = 0.3%).
* **Slot 1:** `address public treasuryWallet` — Address where the accumulated protocol revenue is redirected.
* **Slot 2:** `bool public isTradingPaused` — Emergency circuit breaker state.

*Warning for Phase 2/3 Upgrades:* When migrating to `ApexPlatformV2`, **no existing variables can be reordered, deleted, or changed in type**. Any new state variables (e.g., `string public versionSignature`) must strictly be appended *after* `isTradingPaused` to prevent critical storage slot collisions.

---

## 3. Core Process Workflows (Sequence Diagrams)

### Flow A: Deterministic Pool Deployment via `CREATE2`
This flow guarantees that a liquidity pool will always resolve to the exact same contract address regardless of the deployment state, allowing frontend clients to pre-compute address metrics.

Participant 3/User          PoolFactory                 EVM (CREATE2)
│                         │                            │
│─── createPoolDeter... ─>│                            │
│    (tokenA, tokenB)     │─── Compute Address ───────>│ (Using Salt & bytecode)
│                         │                            │
│                         │─── Deploy Contract ───────>│
│                         │                            │
│<── Returns pool address ───│                            │


### Flow B: UUPS Upgrade Execution Path
Governance/Owner             UUPS Proxy             Implementation V1       Implementation V2
│                         │                          │                       │
│── upgradeToAndCall ────>│                          │                       │
│   (New Logic Address)   │─── _authorizeUpgrade() ─>│                       │
│                         │    (Access Control Check)│                       │
│                         │                          │                       │
│                         │─── Update Storage Pointer ──────────────────────>│
│<── Upgrade Success ─────│                          │                       │


---

## 4. Trust Assumptions & Centralization Risks

During Phase 1, the architecture contains specific structural trust dependencies:
1. **Developer Monopoly:** The `owner` of the proxy and the token initialization processes points directly to a single EOA (Externally Owned Account) controlled by the team.
2. **Upgrade Power:** The EOA owner has the immediate authority to change the underlying logic of `ApexPlatformV1` through `_authorizeUpgrade` without a timelock delay.
3. **Mitigation Strategy (Phase 3 Requirement):** These trust vectors are temporary. In Phase 3, ownership of the `Proxy` and `PoolFactory` contracts will be transferred strictly to the `TimelockController` contract, subordinating all system variables to on-chain decentralized DAO votes.