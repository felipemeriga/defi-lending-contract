# DeFi Lending Smart Contract

This repo consists of a smart-contract that users can deposit collateral(USDC),
for lending this to another user, earning interest.

## Installing

To install dependencies, you need to execute the following commands:

```shell
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
```

Since the `remappings.txt` file is already present, there is no need to
adjust the dependencies in Solidity code.

## Running

For building the smart-contract, you can run:
```shell
forge build
```

For executing tests:
```shell
forge test -vv
```

## Deploying

Since we are using a proxy smart-contract, we have a first deployment script, and another script
for updating the proxy contract to point to the new implementation contract.

### First time deployment:

Since this smart-contract uses USDC as a collateral for deposits, you need to add a valid contract address on
`./script/DeployDeFiLending.sol`.

If you want to build your custom USDC, you can check over: [usdc-smart-contract](https://github.com/felipemeriga/usdc-smart-contract).

To deploy this smart-contract to Sepolia network, you can execute the following command:

```shell
forge script script/DeployDeFiLending.s.sol --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY --broadcast
```
Remember to set the `SEPOLIA_RPC`, and `PRIVATE_KEY` environment variables.

### Update deployment:

As we are using a proxy contract, by default, you don't need to change the proxy contract, you just point it to the new
implementation contract address.
Therefore, remember to add the proxy address on `./script/UpgradeDeFiLending.sol`.

To update this smart-contract on Sepolia network, you can execute the following command:
```shell
forge script script/UpgradeDeFiLending.s.sol --rpc-url $SEPOLIA_RPC --private-key $PRIVATE_KEY --broadcast
```

Remember to set the `SEPOLIA_RPC`, and `PRIVATE_KEY` environment variables.

## Generating ABI

After building the smart-contract, you can generate the ABI with that command:
```shell
jq '.abi' out/DeFiLending.sol/DeFiLending.json > DeFiLending.abi
```

If you are using a tool like `abigen`, for interacting with the smart-contract in your
Go code, you can execute this following command, after generating the ABI:
```shell
abigen --abi DeFiLending.abi --pkg defi --out defi_lending.go
```

For the same ABI generator in Rust, you could use: [ethers-contract-abigen](https://crates.io/crates/ethers-contract-abigen)
