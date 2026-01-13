#!/bin/bash

STORY_SCAN="https://www.storyscan.io"
LIMIT=100
TOKEN=$1

if [ -z "$TOKEN" ]; then
    echo "Usage: $0 <token address>"
    exit 1
fi

TOKEN_ADDRESS=$(jq -r '.address_hash' <<< "$TOKEN")
TOKEN_NAME=$(jq -r '.name' <<< "$TOKEN")
TOKEN_DECIMALS=$(jq -r '.decimals' <<< "$TOKEN")
TOKEN_SUPPLY=$(jq -r '.total_supply' <<< "$TOKEN")

TOKEN_SUPPLY_IN_DECIMALS=$(echo "scale=5; $TOKEN_SUPPLY / 10^$TOKEN_DECIMALS" | bc)

echo "Token Address: $TOKEN_ADDRESS"
echo "Token Name: $TOKEN_NAME"
echo "Token Supply: $TOKEN_SUPPLY_IN_DECIMALS"
echo "Token Decimals: $TOKEN_DECIMALS"

echo ""
echo "Contract Holders:"

CONTRACT_HOLDERS=$(./blockscout-cli.sh $STORY_SCAN --paginate --limit $LIMIT holders $TOKEN_ADDRESS | jq '[.[] | select (.address.is_contract == true)]')

echo $CONTRACT_HOLDERS | jq '.[] | {name: .address.name, address: .address.hash, balance: .value}'