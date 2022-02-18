require('dotenv').config();
require('hardhat-klaytn-patch');
require('@nomiclabs/hardhat-waffle');
require('@openzeppelin/hardhat-upgrades');

const PRIVATE_KEY = process.env.PRIVATE_KEY;

module.exports = {
    solidity: {
        version: '0.6.12',
        settings: {
            evmVersion: 'constantinople',
            optimizer: {
                enabled: true,
                runs: 999999,
            },
        },
    },
    networks: {
        baobab: {
            url: 'https://kaikas.baobab.klaytn.net:8651/',
            accounts: [PRIVATE_KEY],
        },
        cypress: {
            url: 'https://public-node-api.klaytnapi.com/v1/cypress/',
            accounts: [PRIVATE_KEY],
        },
    },
};
