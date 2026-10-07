
# FreelanceEscrow

A Solidity smart contract that provides an escrow system for freelance jobs, helping clients and freelancers manage job payments and milestones securely.

## Testing

The project uses Foundry for automated testing.

- Tests: 13
- Passed: 13
- Failed: 0
- Line coverage: 97.62%
- Statement coverage: 97.44%
- Function coverage: 100%
- Branch coverage: 60.61%

Test file: `test/FreelanceEscrow.t.sol`

Run tests:

```bash
forge test
forge coverage
## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
