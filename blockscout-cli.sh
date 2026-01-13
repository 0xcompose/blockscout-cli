#!/bin/bash

# BlockScout CLI wrapper with network support
# Usage: ./blockscout-cli.sh [network] <command> [args...]

set -e

# Pagination settings
PAGINATE=false
LIMIT=""

# Default network
NETWORK="eth"

# Network resolver function
get_network_host() {
    case "$1" in
        eth) echo "https://eth.blockscout.com/api/v2" ;;
        mainnet) echo "https://eth.blockscout.com/api/v2" ;;
        ethereum) echo "https://eth.blockscout.com/api/v2" ;;
        arbitrum) echo "https://arbitrum.blockscout.com/api/v2" ;;
        optimism) echo "https://optimism.blockscout.com/api/v2" ;;
        polygon) echo "https://polygon.blockscout.com/api/v2" ;;
        gnosis) echo "https://gnosis.blockscout.com/api/v2" ;;
        base) echo "https://base.blockscout.com/api/v2" ;;
        *) echo "" ;;
    esac
}

# Check if first arg is a network name or custom host
if [[ "$1" =~ ^https?:// ]]; then
    # Custom host URL provided
    HOST="$1"
    # Ensure URL ends with /api/v2
    if [[ ! "$HOST" =~ /api/v2/?$ ]]; then
        HOST="${HOST%/}/api/v2"  # Remove trailing slash if any, then add /api/v2
    fi
    shift
else
    # Try known network names
    FIRST_ARG_HOST=$(get_network_host "$1")
    if [ -n "$FIRST_ARG_HOST" ]; then
        NETWORK="$1"
        HOST="$FIRST_ARG_HOST"
        shift
    else
        # Use default network
        HOST=$(get_network_host "$NETWORK")
    fi
fi

if [ -z "$HOST" ]; then
    echo "Error: Unknown network '$NETWORK'" >&2
    echo "Available networks: eth, arbitrum, optimism, polygon, gnosis, base" >&2
    echo "Or provide a custom host: https://your-blockscout.com/api/v2" >&2
    exit 1
fi

# Parse flags
while [[ "$1" =~ ^-- ]]; do
    case "$1" in
        --paginate|--all)
            PAGINATE=true
            shift
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        *)
            echo "Unknown flag: $1" >&2
            exit 1
            ;;
    esac
done

# Parse command
COMMAND="$1"
shift

# Helper function to fetch paginated results
fetch_paginated() {
    local url="$1"
    local total_fetched=0
    local next_params=""
    
    while true; do
        # Build URL with pagination params
        local full_url="$url"
        if [ -n "$next_params" ]; then
            full_url="${url}?${next_params}"
        fi
        
        # Fetch page
        local response=$(curl -s -H "Accept: application/json" "$full_url")
        
        # Extract items
        local items=$(echo "$response" | jq -c '.items[]')
        local items_count=$(echo "$items" | wc -l | tr -d ' ')
        
        # Output items
        echo "$items"
        
        total_fetched=$((total_fetched + items_count))
        
        # Check limit
        if [ -n "$LIMIT" ] && [ "$total_fetched" -ge "$LIMIT" ]; then
            break
        fi
        
        # Check for next page
        local has_next=$(echo "$response" | jq -r '.next_page_params != null')
        if [ "$has_next" != "true" ]; then
            break
        fi
        
        # Build next page params
        next_params=$(echo "$response" | jq -r '.next_page_params | to_entries | map("\(.key)=\(.value)") | join("&")')
        
        if [ -z "$next_params" ] || [ "$next_params" = "null" ]; then
            break
        fi
    done | if [ -n "$LIMIT" ]; then head -n "$LIMIT"; else cat; fi | jq -s '.'
}

case "$COMMAND" in
    token)
        TOKEN="${1:-$(cat)}"
        curl -s -H "Accept: application/json" "$HOST/tokens/$TOKEN"
        ;;
    tokens)
        TYPE="${1:-}"
        if [ "$PAGINATE" = true ]; then
            if [ -n "$TYPE" ]; then
                fetch_paginated "$HOST/tokens?type=$TYPE"
            else
                fetch_paginated "$HOST/tokens"
            fi
        else
            if [ -n "$TYPE" ]; then
                curl -s -H "Accept: application/json" "$HOST/tokens?type=$TYPE"
            else
                curl -s -H "Accept: application/json" "$HOST/tokens"
            fi
        fi
        ;;
    holders)
        TOKEN="${1:-}"
        if [ -z "$TOKEN" ]; then
            echo "Error: Token address required" >&2
            exit 1
        fi
        if [ "$PAGINATE" = true ]; then
            fetch_paginated "$HOST/tokens/$TOKEN/holders"
        else
            curl -s -H "Accept: application/json" "$HOST/tokens/$TOKEN/holders"
        fi
        ;;
    tx|transaction)
        TX="${1:-}"
        if [ -z "$TX" ]; then
            echo "Error: Transaction hash required" >&2
            exit 1
        fi
        curl -s -H "Accept: application/json" "$HOST/transactions/$TX"
        ;;
    transfers)
        TX="${1:-}"
        if [ -z "$TX" ]; then
            echo "Error: Transaction hash required" >&2
            exit 1
        fi
        curl -s -H "Accept: application/json" "$HOST/transactions/$TX/token-transfers"
        ;;
    logs)
        TX="${1:-}"
        if [ -z "$TX" ]; then
            echo "Error: Transaction hash required" >&2
            exit 1
        fi
        curl -s -H "Accept: application/json" "$HOST/transactions/$TX/logs"
        ;;
    address)
        ADDR="${1:-}"
        if [ -z "$ADDR" ]; then
            echo "Error: Address required" >&2
            exit 1
        fi
        curl -s -H "Accept: application/json" "$HOST/addresses/$ADDR"
        ;;
    help|--help|-h)
        cat <<EOF
BlockScout CLI - Retrieve data from BlockScout explorers

Usage:
  $0 [network|host] [--paginate|--all] [--limit N] <command> [args...]

Options:
  --paginate, --all    Fetch all pages automatically
  --limit N           Limit total results to N items

Networks:
  eth, arbitrum, optimism, polygon, gnosis, base
  (default: eth)

Custom Host:
  You can also provide a custom BlockScout URL:
  https://your-blockscout.com (automatically appends /api/v2)
  https://your-blockscout.com/api/v2 (or full API path)

Commands:
  token <address>           Get token info
  tokens [type]            Get list of tokens (optional: ERC-20, ERC-721, ERC-1155)
  holders <token>          Get token holders
  tx <hash>                Get transaction details
  transfers <hash>         Get token transfers in transaction
  logs <hash>              Get transaction logs
  address <address>        Get address/account info

Examples:
  # Get WETH token on Ethereum
  $0 token 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2

  # Get transaction on Arbitrum
  $0 arbitrum tx 0x...

  # Get all token holders across all pages
  $0 --paginate holders 0x...

  # Get first 100 holders only
  $0 --paginate --limit 100 holders 0x...

  # Get all ERC-20 tokens on Optimism
  $0 optimism tokens ERC-20

  # Use custom BlockScout instance (base URL or full API path)
  $0 https://www.storyscan.io token 0x...
  $0 https://custom-chain.blockscout.com/api/v2 token 0x...

  # Pipe with jq
  $0 address 0x... | jq '.coin_balance'
  
  # Get all holders and filter top 10 by balance
  $0 --paginate holders 0x... | jq 'sort_by(.value | tonumber) | reverse | .[0:10]'
EOF
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'" >&2
        echo "Run '$0 help' for usage" >&2
        exit 1
        ;;
esac
