# BlockScout CLI

Command Line Interface to retrieve data from BlockScout network explorers.

Simple bash scripts that output JSON for easy piping with Unix utilities like `jq`, `grep`, `awk`, etc.

## Usage

### Unified CLI (Recommended)

```bash
./blockscout-cli.sh <network|url> [--paginate] [--limit N] <command> [args...]
```

**Supported Networks (REQUIRED):** `eth`, `arbitrum`, `optimism`, `polygon`, `gnosis`, `base`
Or provide a custom URL: `https://your-blockscout.com`

**Pagination Options:**

-   `--paginate` or `--all` - Automatically fetch all pages
-   `--limit N` - Limit total results to N items

**Commands:**

-   `token <address>` - Get token info
-   `tokens [type]` - Get list of tokens (types: `ERC-20`, `ERC-721`, `ERC-1155`)
-   `holders <token>` - Get token holders
-   `tx <hash>` - Get transaction details
-   `transfers <hash>` - Get token transfers in transaction
-   `logs <hash>` - Get transaction logs
-   `address <address>` - Get address/account info

### Individual Scripts

-   `get-token.sh` - Get specific token info
-   `get-tokens.sh` - Get list of tokens
-   `get-token-holders.sh <address>` - Get token holders
-   `get-transaction.sh <hash>` - Get transaction by hash
-   `get-token-transfers.sh <hash>` - Get token transfers in transaction
-   `get-transaction-logs.sh <hash>` - Get transaction logs
-   `get-address.sh <address>` - Get account/address data

## Quick Examples

### Using Unified CLI

```bash
# Get WETH token info on Ethereum (network is REQUIRED)
./blockscout-cli.sh eth token 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2 | jq '{name, symbol}'

# Get transaction on Arbitrum
./blockscout-cli.sh arbitrum tx 0x... | jq '.status'

# Get token holders on Optimism
./blockscout-cli.sh optimism holders 0x... | jq '.items | length'

# Get address balance with jq (network always required!)
./blockscout-cli.sh eth address 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045 | jq -r '.coin_balance'

# Use Story network with custom URL
./blockscout-cli.sh https://www.storyscan.io tokens ERC-20 | jq 'length'

# Get ALL token holders on Ethereum (auto-pagination)
./blockscout-cli.sh eth --paginate holders 0x... | jq 'length'

# Get first 100 holders only
./blockscout-cli.sh eth --paginate --limit 100 holders 0x... | jq '.[] | .address.hash'

# Get only ERC-20 tokens on Story network (note the hyphen!)
./blockscout-cli.sh https://www.storyscan.io --paginate tokens ERC-20 > erc20-tokens.json

# Get only NFTs on Ethereum
./blockscout-cli.sh eth --paginate tokens ERC-721 | jq 'length'
```

### Using Individual Scripts

```bash
# Get WETH token info
./get-token.sh | jq '{name, symbol, type}'

# Get USDT holders and export to CSV
./get-token-holders.sh 0xdAC17F958D2ee523a2206206994597C13D831ec7 \
  | jq -r '.items[] | [.address.hash, .value] | @csv'

# Get token transfers with filtering
./get-token-transfers.sh 0x... | jq '.items[] | select(.token.symbol == "USDT")'
```

See [EXAMPLES.md](./EXAMPLES.md) for more advanced usage and piping examples.

## Requirements

-   `bash`
-   `curl`
-   `jq` (recommended for JSON processing)

## Configuration

Individual scripts use Ethereum mainnet by default: `https://eth.blockscout.com/api/v2`

To use different networks, either:

1. Use the unified CLI: `./blockscout-cli.sh <network> ...`
2. Edit the `HOST` variable in individual scripts
