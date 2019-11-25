# Chainlink client contracts

Collection of Chainlink client contracts

### Getting started

```
git clone https://github.com/ngyam/chainlink-client-contracts.git
cd "chainlink-client-contracts"
npm install
```

After install the Link token related contracts are in `node_modules/LinkToken/contracts` and the original `chainlink` contracts are in `node_modules/chainlink/contracts`.

## Addresses
Some already deployed contract addresses:

| Chain | Contract | Address |
| ----- |:--------:| -------:|
| Volta | LinkToken | `0xe76d478383327b83eE0FE6b3F0ec675315340E18` |
| Volta | Pointer | `0x859a5A7bBe21C56AbB8AAc36B0A0B5D258D0445b` |
| Volta | LinkTokenSale | `0x3f312acB7c48Eb4e2A2E2B6C89FD7a2011F45915` |
| Volta | ExecutorPublicPriceAggregator | `0xfAae940028a5dce6d99D4F716A26289Ee40bc417` |

## Linting

2 linters are set up:
- Solhint:
  ```
  npm run lint:solhint
  ```
- Solium
  ```
  npm run lint:solium
  ```

## Contributing

Please read the [CONTRIBUTING guide](./CONTRIBUTING.md) for code of conduct and for the process of submitting pull requests.

## Versioning

[SemVer](http://semver.org/)

## License

This project is licensed under the GPLv3 License - see the [LICENSE](./LICENSE) file for details.

## FAQ
