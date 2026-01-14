#!/bin/bash

LIMIT="${1:-100}"
TOKENS_FILE="${2:-tokens.json}"
OUTPUT_DIR="${3:-pools}"
SCANNER_URL="${4:-https://www.storyscan.io}"

 
# Create pools directory if it doesn't exist
mkdir -p $OUTPUT_DIR

# Get total number of tokens
TOTAL_TOKENS=$(jq 'length' "$TOKENS_FILE")

echo "Processing $TOTAL_TOKENS tokens..."
echo ""

# ANSI color codes
GREY='\033[90m'
GREEN='\033[32m'
RESET='\033[0m'

# Loop through all tokens
jq -c '.[]' "$TOKENS_FILE" | while read -r TOKEN; do
    TOKEN_ADDRESS=$(jq -r '.address_hash' <<< "$TOKEN")
    TOKEN_NAME=$(jq -r '.name' <<< "$TOKEN")
    TOKEN_SYMBOL=$(jq -r '.symbol' <<< "$TOKEN")
    TOKEN_TYPE=$(jq -r '.type // "ERC-20"' <<< "$TOKEN")
    
    # Skip non-fungible tokens (ERC-721, ERC-1155)
    if [[ "$TOKEN_TYPE" == "ERC-721" ]] || [[ "$TOKEN_TYPE" == "ERC-1155" ]]; then
        echo -e "$TOKEN_NAME ($TOKEN_SYMBOL) - $TOKEN_ADDRESS - ${GREY}[SKIPPED] - $TOKEN_TYPE${RESET}"
        continue
    fi
    TOKEN_DECIMALS=$(jq -r '.decimals // "0"' <<< "$TOKEN")
    TOKEN_SUPPLY=$(jq -r '.total_supply // "0"' <<< "$TOKEN")
    
    # Handle null values for NFTs
    if [ "$TOKEN_DECIMALS" = "null" ] || [ -z "$TOKEN_DECIMALS" ]; then
        TOKEN_DECIMALS="0"
    fi
    
    if [ "$TOKEN_SUPPLY" = "null" ] || [ -z "$TOKEN_SUPPLY" ]; then
        TOKEN_SUPPLY="0"
    fi
    
    # Calculate supply in decimals
    if [ "$TOKEN_DECIMALS" != "0" ] && [ "$TOKEN_SUPPLY" != "0" ]; then
        TOKEN_SUPPLY_IN_DECIMALS=$(echo "scale=5; $TOKEN_SUPPLY / 10^$TOKEN_DECIMALS" | bc 2>/dev/null || echo "$TOKEN_SUPPLY")
    else
        TOKEN_SUPPLY_IN_DECIMALS="$TOKEN_SUPPLY"
    fi
    
    # Get address prefix (first and last 4 chars after 0x)
    ADDRESS_PREFIX=$(echo "$TOKEN_ADDRESS" | cut -c 1-6)_$(echo "$TOKEN_ADDRESS" | tail -c 5)
    
    # Create filename: {SYMBOL}-{0x1234_5678}.json
    FILENAME="${TOKEN_SYMBOL}-${ADDRESS_PREFIX}.json"
    FILEPATH="$OUTPUT_DIR/$FILENAME"
    
    # Fetch contract holders
    CONTRACT_HOLDERS=$(./blockscout-cli.sh $SCANNER_URL --paginate --limit $LIMIT holders $TOKEN_ADDRESS 2>/dev/null | jq '[.[] | select(.address.is_contract == true)]' 2>/dev/null)
    
    if [ -z "$CONTRACT_HOLDERS" ] || [ "$CONTRACT_HOLDERS" = "null" ]; then
        CONTRACT_HOLDERS="[]"
    fi
    
    # Skip tokens with no contract holders
    HOLDERS_COUNT=$(echo "$CONTRACT_HOLDERS" | jq 'length')
    if [ "$HOLDERS_COUNT" -eq 0 ]; then
        echo -e "$TOKEN_NAME ($TOKEN_SYMBOL) - $TOKEN_ADDRESS - ${GREY}[SKIPPED] - No contract holders${RESET}"
        continue
    fi
    
    # Build JSON output
    jq -n \
        --arg address "$TOKEN_ADDRESS" \
        --arg name "$TOKEN_NAME" \
        --arg symbol "$TOKEN_SYMBOL" \
        --arg token_type "$TOKEN_TYPE" \
        --arg decimals "$TOKEN_DECIMALS" \
        --arg supply "$TOKEN_SUPPLY" \
        --arg supply_formatted "$TOKEN_SUPPLY_IN_DECIMALS" \
        --argjson holders "$CONTRACT_HOLDERS" \
        '{
            token: {
                address: $address,
                name: $name,
                symbol: $symbol,
                type: $token_type,
                decimals: (if $decimals == "null" then null else ($decimals | tonumber) end),
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
    
    echo -e "$TOKEN_NAME ($TOKEN_SYMBOL) - $TOKEN_ADDRESS - ${GREEN}[SUCCESS]${RESET}"
done

echo "Done! All results saved to $OUTPUT_DIR directory"