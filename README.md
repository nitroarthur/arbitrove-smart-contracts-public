# Arbitrove

> Solidity Compiler Version: `0.8.17`; Vyper Compiler Version: `0.3.7`

# General
Arbitrove Protocol is a yield-bearing index protocol that allows people to one-click mint an index that give exposure to a batch of strategies consist of yield-bearing assets. Unlike traditional index protocol that only hold tokens, Arbitrove Protocol dynamically deploy capital to strategies. 

## Folder structure
```
.
├── src/
│   ├── contracts/
│   │   ├── farm (Out of scope)
│   │   ├── strategy
│   │   ├── vault
│   │   └── tokens (Out of scope)
│   ├── mocks (Out of scope)
│   ├── structs
│   └── tests
└── script (Out of scope)
```

`FactoryTokens.sol` under `contracts` is also out of scope for Arbitrove audit.

# Core Contract Overview

#### FactoryArbitrove.sol

`FactoryArbitrove.sol` is responsible for deploying and managing instances of the Vault and AddressRegistry contracts.

#### Router.vy

`Router.vy` is the single point of entry for users to interact with the Vault. Users can deposit and withdraw assets from the Vault through the Router. To do so, the user must first approve the Router and submit a `MintRequest` or `BurnRequest` to the Router. The request will be stored into its respective queue. The oracle will then call the Router to process the request or refund the user if the request is invalid.

#### Vault.sol

`Vault.sol` facilitates the deposit and withdrawal of funds and helps manage assets across different strategies. It is interacted with through the Router.

#### Strategy.sol

`Strategy.sol` is an example strategy. Down the line, we will have more strategies that generally fall in the range of single-side staking, yield farming, and lending.

#### AddressRegistry.sol

`AddressRegistry.sol` is used to manage the mapping of strategies to supported coins. 

#### FeeOracle.sol

`FeeOracle.sol` implements a fee oracle that provides deposit and withdrawal fees to be used by the Vault contract. The fees are based on the current weight of a coin in the vault compared to its target weight.


# General compiling and deployment

Install vyper first before running deployment scripts

## Test Vault
> forge test -vv --ffi --match-contract VaultTest

## Deploy Single

> forge create --rpc-url <your_rpc_url> --private-key <your_private_key> src/MyContract.sol:MyContract

## Deploy All
You may dry run without the `--broadcast` flag

### Arbitrove
> forge script script/FactoryArbitrove.s.sol:DeployFactory --broadcast --rpc-url ${GOERLI_RPC_URL} --private-key ${PRIVATE_KEY} --ffi

### Token staking
> forge script script/FactoryStaking.s.sol:DeployFactory --broadcast --rpc-url <your_rpc_url> --private-key <your_private_key>


## Compile Vyper Contracts

> pip3 install vyper

or

> docker run -v $(pwd):/code vyperlang/vyper /code/<contract_file.vy>

Add this to your `.zshrc`

This might work or not work depending on your system
```
vyper() {
    #do things with parameters like $1 such as
    docker run -v $(pwd):/code vyperlang/vyper /code/$1
}
```

## Enviroment variables
You might need to run `source .env` before running scripts depending on your system, an example for `.env` is in `.env.example`

```
GOERLI_RPC_URL=https://goerli.infura.io/v3/[INFURA_KEY]
ETHERSCAN_API_KEY=...
```