# Counter on Robinhood Chain

A contracts-only Foundry project. The sole application is
[`src/Counter.sol`](src/Counter.sol); it has no runtime dependencies.

## Behavior

- `count()` returns a `uint256` shared by all callers, initially zero.
- Anyone, including another contract, may call `increment()` repeatedly. Each
  successful call adds exactly one and emits
  `Incremented(address indexed caller, uint256 newCount)` once. `caller` is the
  immediate `msg.sender`; `newCount` is the value after the increment.
- At `type(uint256).max`, incrementing reverts with Solidity `Panic(0x11)` and
  preserves the count. There is no reset or wraparound.
- There are no constructor arguments, initializer, owner, admin, upgrade, pause,
  fees, token, external calls, or token approvals. Callers pay network gas.
- Deployment and both functions are nonpayable. Ordinary value transfers,
  empty calldata, and unknown function selectors revert. No deposit or
  withdrawal mechanism exists.

"No funds held" means the application never solicits or accepts payments and
has no custody responsibilities. An EVM address cannot prevent every unsolicited
balance credit, including forced ETH transfers; externally transferred ERC-20s
can also be assigned to it. Such assets are unrecoverable here and have no effect
on counting. See the [Solidity 0.8.26 discussion of forced transfers](https://docs.soliditylang.org/en/v0.8.26/security-considerations.html#sending-and-receiving-ether).

## Build and check

Use Foundry with native Solidity **0.8.26** available locally:

```sh
forge build
forge test
forge fmt --check
```

[`foundry.toml`](foundry.toml) pins Solidity 0.8.26, the Paris EVM target, optimizer
enabled with 200 runs, `via_ir = false`, and `bytecode_hash = "none"`. Paris avoids
relying on newer EVM instructions for this simple application. FFI is disabled
and filesystem cheatcode permissions are empty. No project environment variables,
RPC, wallet, fork, or network access are needed for build or tests once the
compiler and Foundry are installed.

The test-only `forge-std` v1.9.7 dependency is vendored as ordinary files in
[`lib/forge-std`](lib/forge-std), with its upstream commit, archive checksum and
licenses. There are no submodules or dependency installation steps. The Solidity
compiler and Foundry are build tools supplied by the checking environment, not
repository dependencies.

## Tests

[`test/Counter.t.sol`](test/Counter.t.sol) covers initial state, repeated increments,
exact event count/topics/data/emitter, 64 distinct callers returning for a second
round, contract caller attribution, arbitrary nonmax storage states, randomized
caller sequences, overflow, value rejection at creation and both functions,
empty/short/unknown calldata rejection, argument-free CREATE2 deployment, and
counting with an unsolicited balance.

[`test/Counter.invariant.t.sol`](test/Counter.invariant.t.sol) mixes increments
from arbitrary callers with rejected payments. Its model checks that the count
equals successful calls and accepted payment balance stays zero. That balance
property applies to normal calls, not forced credits. Defaults are 256 cases per
fuzz test and 128 invariant sequences of 64 calls. Every test starts with a fresh
deployment and neither reads nor changes environment variables.

The overflow test seeds storage with `vm.store`, since reaching the boundary by
real transactions is impractical. The unsolicited-balance test uses `vm.deal` to
model a credit without a message call. Neither ability exists in the application.

## Deployment parameters and handoff

[`launch.json`](launch.json) specifies one `evm_contracts` application:

| Parameter | Value |
| --- | --- |
| Artifact | `src/Counter.sol:Counter` |
| Contract name | `Counter` |
| Constructor arguments | `[]` (encoded as empty bytes `0x`) |
| Deployment value | `0` wei |
| Initial count | `0` |
| Linked libraries / external addresses | None |
| Post-deployment configuration / role transfers | None |
| Target | Robinhood Chain; exact network to be confirmed by the deployment service |
| RPC, chain ID, project factory, CREATE2 salt | Supplied and verified by the deployment service |
| Deployed address | Computed by the deployment service and confirmed by its receipt |

The provided inputs contain no authoritative network configuration or factory
address. No chain ID, endpoint, wallet, or application address is guessed here.
The code is chain-independent and assumes standard EVM checked arithmetic,
storage and log semantics. It uses no block number, timestamp, randomness,
precompile, oracle, bridge, or chain-specific contract.

Before deployment, the release operator must obtain the **independent contributor
security review** described in [`docs/SECURITY_REVIEW.md`](docs/SECURITY_REVIEW.md).
The local implementation checks are not that sign-off. Review must cover the
final source, configuration and launch manifest; any subsequent change requires
revalidation.

After that review, the deployment service is responsible for verifying its
configured Robinhood network using the RPC's chain ID, confirming EVM support
and project factory identity, choosing the salt, reproducing the pinned build,
and simulating creation with zero value and no appended constructor arguments.
Constructor execution through a factory confers no privilege on the factory.

The creation and deployed bytecode can be inspected locally:

```sh
forge inspect src/Counter.sol:Counter bytecode
forge inspect src/Counter.sol:Counter deployedBytecode
forge inspect src/Counter.sol:Counter abi
```

The deployment operator controls transaction signing and broadcasting. After
deployment, they record the network, address, transaction, source revision and
compiler settings, compare on-chain runtime with the approved artifact, verify
the source on the explorer, and check `count()` at deployment. Anyone can
increment immediately, so a later nonzero value is not an initialization failure.
No deployment transaction or signing was performed in this assignment.

## Operation

There is no application administrator or maintenance job. Callers need gas and
must submit zero value. Integrators should use the confirmed deployment address,
read `count()` for current state, and index `Incremented` in canonical transaction
order with normal reorg handling. A read before submission does not reserve the
next count; other callers can increment first. The counter measures successful
calls, not unique people or votes.

Network availability, transaction inclusion/ordering, finality and gas charges
remain the target chain's responsibility. Local tests do not model its sequencer
or governance. An immutable deployment has no emergency pause or upgrade route;
any future replacement requires a separately reviewed deployment and explicit
integrator migration.
