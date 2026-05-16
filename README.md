# Apex Finance — L2 DeFi Ecosystem 

A decentralized financial ecosystem designed for Layer 2 networks, featuring an Automated Market Maker (AMM), a Governance system (DAO), and utility-driven VIP NFT passes. 

This project is built and managed using the **Foundry** smart contract development framework.

---

##  Architecture Overview Phase 1: Participant 1

In this initial infrastructure phase, the core tokenomics, factory design, and upgradeable proxy patterns have been successfully deployed and tested:

1. **`ApexToken (APEX)`**: Governance token implemented using the `ERC20` standard. It features `ERC20Permit` for gasless approvals (EIP-2612 signatures) and `ERC20Votes` for checkpoint-based DAO voting weight snapshots, eliminating flash-loan governance manipulation. Total maximum supply is capped at 100,000,000 APEX.
2. **`ApexNFT (APEX_VIP)`**: An `ERC721URIStorage` compliant contract managing VIP membership passes. These NFTs will integrate with the core AMM to provide dynamic trading fee discounts for holders.
3. **`PoolFactory`**: The core deploying mechanism for liquidity pools. It demonstrates two deployment strategies required by the specifications: standard deployment (`CREATE`) and deterministic, pre-computable deployment (`CREATE2`) using a cryptographic `salt`.
4. **`ApexPlatformV1`**: The central configuration registry for global protocol variables (fees, treasury addresses, and emergency circuit breakers). It is deployed behind a **UUPS Proxy (Universal Upgradeable Proxy Standard)** to allow safe logic upgrades without disturbing the persistent storage state.

---

##  Quick Start (Guide for Participant 2 & Participant 3)

### Prerequisites
* [Foundry / Forge](https://book.getfoundry.sh/getting-started/installation) installed.
* Linux / WSL2 environment recommended.

### 1. Clone the Repository & Install Dependencies
```bash
git clone [https://github.com/Ulannnnnnn/apex-finance.git](https://github.com/Ulannnnnnn/apex-finance.git)
cd apex-finance
forge install
2. Compile Smart Contracts
Bash
forge build
3. Run the Test Suite
Bash
forge test -vvv
Gas Optimization & Compiler Configuration
The compiler settings in foundry.toml have been tightly optimized for low-gas deployment and execution in L2 environments:

Solc Version: 0.8.24 (Strictly enforced across all environments)

Optimizer: Enabled with runs = 200

via-ir: Enabled to optimize complex Yul intermediate representations and prevent Stack too deep compilation errors in future phases.

CI/CD Pipeline & Code Quality
An automated GitHub Actions workflow (ci.yml) is active. It triggers automatically on every push or Pull Request targeting the main branch, ensuring code safety by running:

Code formatting validation (forge fmt --check)

Contract size audits to prevent exceeding the 24KB EVM limit (forge build --sizes)

Full automated unit testing execution 