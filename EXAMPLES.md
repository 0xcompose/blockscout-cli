# BlockScout CLI Examples

## Basic Usage

All scripts output JSON to stdout, perfect for piping with Unix utilities.

## Pagination

BlockScout API returns paginated results (50 items per page). Use `--paginate` or `--all` flags to automatically fetch all pages:

```bash
# Get all token holders (all pages)
./blockscout-cli.sh --paginate holders 0x...

# Get first 100 holders only
./blockscout-cli.sh --paginate --limit 100 holders 0x...

# Get all tokens with pagination
./blockscout-cli.sh --all tokens | jq 'length'
```

### Get Token Info

```bash
# Get WETH token info
./get-token.sh | jq '{name, symbol, type}'
```

### Get All Tokens

```bash
# Get all tokens
./get-tokens.sh | jq '.items[] | {name, symbol, address: .address}'

# Get only ERC-20 tokens
./get-tokens.sh ERC-20 | jq '.items[] | .symbol'

# Count tokens
./get-tokens.sh | jq '.items | length'
```

### Get Token Holders

```bash
# Get first page of holders (50 items)
./blockscout-cli.sh holders 0x... | jq '.items[]'

# Get ALL holders across all pages
./blockscout-cli.sh --paginate holders 0x... | jq '.[] | {address: .address.hash, balance: .value}'

# Top 10 holders by balance (with pagination)
./blockscout-cli.sh --paginate holders 0x... \
  | jq 'sort_by(.value | tonumber) | reverse | .[:10]'

# Get first 200 holders only
./blockscout-cli.sh --paginate --limit 200 holders 0x... | jq 'length'

# Export ALL holders to CSV
./blockscout-cli.sh --paginate holders 0x... \
  | jq -r '.[] | [.address.hash, .value] | @csv' > holders.csv
```

### Get Transaction

```bash
# Get transaction details
./get-transaction.sh 0x... | jq '{hash, from, to, value, gas_used}'

# Extract gas info
./get-transaction.sh 0x... | jq '{gas_used, gas_price, total_cost: (.gas_used * .gas_price)}'

# Check transaction status
./get-transaction.sh 0x... | jq -r '.status'
```

### Get Token Transfers in Transaction

```bash
# Get all token transfers
./get-token-transfers.sh 0x... | jq '.items[]'

# Find specific token transfers
./get-token-transfers.sh 0x... \
  | jq '.items[] | select(.token.symbol == "USDT")'

# Sum all transfer values
./get-token-transfers.sh 0x... \
  | jq '[.items[].total.value | tonumber] | add'

# Format as table
./get-token-transfers.sh 0x... \
  | jq -r '.items[] | [.from.hash, .to.hash, .total.value, .token.symbol] | @tsv'
```

### Get Transaction Logs

```bash
# Get all logs
./get-transaction-logs.sh 0x...

# Find Transfer events (topic0)
./get-transaction-logs.sh 0x... \
  | jq '.items[] | select(.topics[0] == "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")'

# Extract decoded data
./get-transaction-logs.sh 0x... \
  | jq '.items[] | {address: .address.hash, topics: .topics, data}'
```

### Get Address Data

```bash
# Get address info
./get-address.sh 0x... | jq '{hash, balance: .coin_balance, is_contract}'

# Check if verified contract
./get-address.sh 0x... | jq -r '.is_verified'

# Get contract name
./get-address.sh 0x... | jq -r '.name // "Not available"'
```

## Advanced Piping Examples

### Chain Multiple Requests

```bash
# Get token address, then get its holders
TOKEN=$(./get-tokens.sh | jq -r '.items[0].address')
./get-token-holders.sh "$TOKEN" | jq '.items | length'
```

### Filter and Transform

```bash
# Get all ERC-20 tokens with more than 1000 holders
./get-tokens.sh ERC-20 \
  | jq '.items[] | select(.holders_count > 1000) | {name, symbol, holders_count}'
```

### Monitoring Transactions

```bash
# Watch for new transactions (with pagination)
while true; do
  ./get-transaction.sh 0x... | jq '.status'
  sleep 10
done
```

### Export to Different Formats

```bash
# CSV
./get-tokens.sh | jq -r '.items[] | [.name, .symbol, .type] | @csv'

# TSV
./get-token-holders.sh 0x... | jq -r '.items[] | [.address.hash, .value] | @tsv'

# Pretty table with column
./get-tokens.sh | jq -r '.items[] | [.symbol, .name] | @tsv' | column -t
```

### Combining with Other Tools

```bash
# Use with grep
./get-transaction-logs.sh 0x... | jq -r '.items[].topics[]' | grep "0xddf252ad"

# Use with awk
./get-token-holders.sh 0x... | jq -r '.items[].value' | awk '{sum+=$1} END {print sum}'

# Use with sed
./get-address.sh 0x... | jq -r '.hash' | sed 's/0x//'

# Save to file with tee
./get-transaction.sh 0x... | tee transaction.json | jq '.status'
```

## Environment Variables

Set a custom BlockScout instance:

```bash
# Edit scripts to use environment variable
export BLOCKSCOUT_HOST="https://arbitrum.blockscout.com/api/v2"
```

Or create a wrapper script that accepts network as parameter.
