const fs = require('fs');
const path = require('path');
const HDWalletProvider = require('truffle-hdwallet-provider');
const cwd = path.resolve('.');


module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 9656,
      network_id: "*" // Match any network id
    },

    volta: {
      network_id: "73799",
      gasPrice: "1",
      confirmations: 1,
      from: process.env.FROM,
      provider: () => new HDWalletProvider(fs.readFileSync(path.resolve(cwd, process.env.SECRET_PATH), 'utf-8').trim(), 'https://volta-rpc.energyweb.org'),
      production: true
    },

    ewc: {
      network_id: "246",
      gasPrice: "1",
      confirmations: 1,
      from: process.env.FROM,
      provider: () => new HDWalletProvider(fs.readFileSync(path.resolve(cwd, process.env.SECRET_PATH), 'utf-8').trim(), 'https://rpc.energyweb.org'),
      production: true
    },
  },
  compilers: {
     solc: {
       version: "0.4.24"
     }
  }
};
