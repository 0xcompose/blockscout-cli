#!/bin/bash

STORY_SCAN="https://www.storyscan.io"
LIMIT="${1:-100}"
TOKENS_FILE="${2:-tokens.json}"
OUTPUT_DIR="${3:-pools}"


# Create pools directory if it doesn't exist
mkdir -p $OUTPUT_DIR

# Get total number of tokens
TOTAL_TOKENS=$(jq 'length' "$TOKENS_FILE")

echo "Processing $TOTAL_TOKENS tokens..."

# Loop through all tokens
jq -c '.[]' "$TOKENS_FILE" | while read -r TOKEN; do
    TOKEN_ADDRESS=$(jq -r '.address_hash' <<< "$TOKEN")
    TOKEN_NAME=$(jq -r '.name' <<< "$TOKEN")
    TOKEN_SYMBOL=$(jq -r '.symbol' <<< "$TOKEN")
    TOKEN_DECIMALS=$(jq -r '.decimals' <<< "$TOKEN")
    TOKEN_SUPPLY=$(jq -r '.total_supply' <<< "$TOKEN")
    
    # Calculate supply in decimals
    TOKEN_SUPPLY_IN_DECIMALS=$(echo "scale=5; $TOKEN_SUPPLY / 10^$TOKEN_DECIMALS" | bc 2>/dev/null || echo "0")
    
    # Get address prefix (first and last 4 chars after 0x)
    ADDRESS_PREFIX=$(echo "$TOKEN_ADDRESS" | cut -c 1-6)_$(echo "$TOKEN_ADDRESS" | tail -c 5)
    
    # Create filename: {SYMBOL}-{0x1234_5678}.json
    FILENAME="${TOKEN_SYMBOL}-${ADDRESS_PREFIX}.json"
    FILEPATH="$OUTPUT_DIR/$FILENAME"
    
    echo "Processing: $TOKEN_NAME ($TOKEN_SYMBOL) - $TOKEN_ADDRESS"
    
    # Fetch contract holders
    CONTRACT_HOLDERS=$(./blockscout-cli.sh $STORY_SCAN --paginate --limit $LIMIT holders $TOKEN_ADDRESS 2>/dev/null | jq '[.[] | select(.address.is_contract == true)]' 2>/dev/null)
    
    if [ -z "$CONTRACT_HOLDERS" ] || [ "$CONTRACT_HOLDERS" = "null" ]; then
        CONTRACT_HOLDERS="[]"
    fi
    
    # Build JSON output
    jq -n \
        --arg address "$TOKEN_ADDRESS" \
        --arg name "$TOKEN_NAME" \
        --arg symbol "$TOKEN_SYMBOL" \
        --arg decimals "$TOKEN_DECIMALS" \
        --arg supply "$TOKEN_SUPPLY" \
        --arg supply_formatted "$TOKEN_SUPPLY_IN_DECIMALS" \
        --argjson holders "$CONTRACT_HOLDERS" \
        '{
            token: {
                address: $address,
                name: $name,
                symbol: $symbol,
                decimals: ($decimals | tonumber),
                total_supply: $supply,
                total_supply_formatted: $supply_formatted
            },
            contract_holders: $holders | map({
                name: .address.name,
                address: .address.hash,
                balance: .value,
                is_verified: .address.is_verified
            }),
            total_contract_holders: ($holders | length)
        }' > "$FILEPATH"
    
    echo "  → Saved to: $FILEPATH ($(jq '.total_contract_holders' "$FILEPATH") contract holders)"
    echo ""
done

echo "Done! All results saved to $OUTPUT_DIR directory"