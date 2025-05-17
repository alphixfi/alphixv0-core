# Alphix

## A Uniswap v4 Hook 🦄

Alphix is a smart contract built on top of Uniswap v4, leveraging its new **[Hook Feature](#hooks)** to enhance liquidity efficiency in Decentralized Finance markets, particularly Automated Market Makers(AMMs) and Concentrated Liquidity AMMs(CLMMs). Our implementation follows the official **[Uniswap v4 template](https://github.com/uniswapfoundation/v4-template)**, ensuring compatibility and best practices.

### **Why Uniswap**

- **Innovative Hook Feature**: Uniswap v4 introduces **[Hooks](#hooks)**, enabling developers to customize and extend core pool logic without modifying the base protocol.
- **Trusted Protocol**: Uniswap is a well-established  decentralized exchange with robust security and liquidity.
- **Concentrated Liquidity AMM (CLMM)**: By utilizing CLMM, Uniswap v4 achieves higher capital efficiency and better price execution.
- **Minimal or No Royalties**: Uniswap v4 operates with zero or low royalty fees, maximizing returns for our users.

### **Hooks**

Hooks are modular smart contracts that execute custom logic before or after key pool actions, such as minting, swapping, or settling liquidity. For example, the Uniswap team’s `Counter.sol` contract demonstrates how hooks can extend functionality seamlessly. 

## Project Description

Alphix leverages this powerful feature to implement a **dynamic fee adjustment mechanism** based on real-time pool conditions. Specifically, it leverages Volume and Total Value Locked (TVL) — two key pool-level metrics — to determine the optimal trading fee at any given time.

At a high level:
- When the **Volume/TVL ratio is low**, it signals a lack of trading activity relative to liquidity; fees are reduced to attract more volume.
- When the **Volume/TVL ratio is high**, it suggests a relative scarcity of liquidity; fees are increased to incentivize LPs.
- When the **Volume/TVL ratio ~ target ratio**, fees remain unchanged.

Unlike static fee tiers that lead to fragmented liquidity across pools, Alphix continuously adapts to market dynamics. Its goal is to **unify liquidity**, improve **capital efficiency**, and ensure fees remain **fair** for both traders and liquidity providers (LPs).

Furthermore, Alphix does not treat the target ratio as a constant. Instead, it is recalculated over time using an **Exponential Moving Average (EMA)**, which also incorporates user behavior and broader market trends. To prevent manipulation and volatility, **hard fee bounds** and **adaptive step limits** are enforced.

---
<details>
<summary><strong>Challenges</strong></summary>

<br>

First, to remain **fully decentralized** and avoid reliance on oracles — which introduce latency and increase the attack surface — Alphix computes all necessary metrics directly on-chain.

Uniswap V4 Pools' Volume and TVL are complex to retrieve on-chain (known limitation with no public solution). We built an accurate solution that remains efficient in gas and memory. 

Then, developing the adaptive fee algorithm at the core of the Alphix Hook also posed a significant challenge. The inherent complexity of simulating stakeholder behaviour in a complex game-theoretical problem can only be achieved by setting assumptions. Using various data sourced through different subgraphs we were able to create initial Response Functions for LPs and Traders that were sufficiently accurate to start modelling simple simulations.

With these Response Functions, initial simulations were conducted to confirm our hypothesis: Dynamic Fee Pools using a Vol/TVL ratio outperform static fee pools. During this phase, the importance of adding an adaptive target ratio as well as parameters such as max_step and consecutive multipliers to said step was uncovered.

*Note: Our above mentioned followed steps and solutions are not publicly available and will be publicly shared upon the Beta release in Q3-Q4 2025*

</details>

---

<details>
<summary><strong>Fee Adjustment Mechanics</strong></summary>

<br>

At regular time intervals (e.g., once daily), the Alphix Hook updates each pool’s trading fee based on the latest Volume/TVL ratio. This mechanism enables:

- Lower fees during periods of low volume to stimulate trading.
- Higher fees when liquidity becomes scarce, attracting more LPs.
- Adaptive targeting using an EMA, smoothing fee fluctuations while remaining responsive.
- Min/max fee bounds to maintain predictability.
- Step bounds to prevent sudden spikes in fee changes, improving LP trust and trader experience.


</details>

---

<details>
<summary><strong>Security, UX, and Deployment Roadmap</strong></summary>

<br>

Alphix prioritizes security, decentralization, robustness, and user experience. While the V1 smart contract is undergoing rigorous testing and will be audited shortly, we have already deployed a simplified and centralized version to test our interface and for the Base-Batch-Europe.

This approach allows us to:

- Focus on security-first DApp development.
- Deliver an intuitive experience to early users.
- Prepare for a seamless transition to the fully decentralized hook once audits are complete.

</details>

---


## Repository Structure

### Alphix Hook V0

> *[AlphixV0.sol](./src/AlphixV0.sol)*

This is the simplified and centralized version of the Alphix Hook. It helps us to test out our dApp. 

### Alphix Hook V0 Test

> *[AlphixV0.t.sol](./test/alphix_v0/AlphixV0.t.sol)*

The testing file of the Alphix V0 Hook.

### Alphix Hook V0 Script

> *[AlphixV0.s.sol](./script/alphix_v0/00_AlphixV0.s.sol)*

The script file to deploy the Alphix V0 Hook.

### Pre-Seed Deck

> *[Alphix Pre-Seed Deck](./Base_Batch_Alphix.pdf)*

Our Pre-Seed Deck for additional information.

## Set up

For the setup please refer to [`this`](https://github.com/uniswapfoundation/v4-template?tab=readme-ov-file#set-up).


## Contact

For questions and recommendations please reach out on Telegram @layanbrk and @ShuiTangs

