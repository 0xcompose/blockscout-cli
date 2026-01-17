#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Filter `contract-holders/*/*.json` produced by `get-contract-holders.sh` by detecting which holder addresses are AMM pools
using `which-dex` bytecode inspection.

Requirements:
  - jq
  - which-dex (installed from https://github.com/0xcompose/which-dex-rs)

Usage:
  RPC_URL=<rpc> ./filter-pools.sh --input-dir <contract-holders/network> [--out-dir <dir>] [--which-dex-bin <bin>]
  ./filter-pools.sh --rpc-url <rpc> --input-dir <contract-holders/network> [--out-dir <dir>] [--which-dex-bin <bin>]

Examples:
  RPC_URL="https://..." ./filter-pools.sh --input-dir ./contract-holders/fuse --out-dir ./dex-pools/fuse
  RPC_URL="https://..." ./filter-pools.sh --input-dir ./contract-holders/story --which-dex-bin which-dex
  ./filter-pools.sh --rpc-url https://mainnet.storyrpc.io --input-dir ./contract-holders/story --out-dir ./pools/story

Outputs (in --out-dir):
  - pools.jsonl   (one JSON object per *deduped* detected pool; minimal fields)
  - pools.json    (array form of pools.jsonl)
  - unknown.jsonl (addresses that which-dex couldn't classify or errored; minimal fields)
  - .which-dex-cache/<address>.json (raw which-dex JSON per address)

Note:
  - Pools are deduped by pool address (lowercased), because the same pool can hold multiple tokens.
  - Output schema (pools.jsonl/pools.json):
      { address, name, protocol, is_proxy, is_verified }
EOF
}

INPUT_DIR=""
OUT_DIR=""
WHICH_DEX_BIN="${WHICH_DEX_BIN:-which-dex}"
RPC_URL="${RPC_URL:-}"
CONTRACT_HOLDERS_DIR="${CONTRACT_HOLDERS_DIR:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --rpc-url)
      RPC_URL="${2:-}"
      shift 2
      ;;
    --input-dir)
      INPUT_DIR="${2:-}"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="${2:-}"
      shift 2
      ;;
    --which-dex-bin)
      WHICH_DEX_BIN="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$INPUT_DIR" ]; then
  if [ -n "$CONTRACT_HOLDERS_DIR" ]; then
    INPUT_DIR="$CONTRACT_HOLDERS_DIR"
  else
    echo "Error: --input-dir is required (or set CONTRACT_HOLDERS_DIR env var)" >&2
    usage >&2
    exit 1
  fi
fi

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is required (env var)" >&2
  usage >&2
  exit 1
fi

if [ -z "$OUT_DIR" ]; then
  OUT_DIR="$(pwd)/dex-pools"
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required" >&2
  exit 1
fi

if ! command -v "$WHICH_DEX_BIN" >/dev/null 2>&1; then
  echo "Error: which-dex binary not found: $WHICH_DEX_BIN" >&2
  echo "Install it from https://github.com/0xcompose/which-dex-rs" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
CACHE_DIR="$OUT_DIR/.which-dex-cache"
mkdir -p "$CACHE_DIR"

POOLS_JSONL="$OUT_DIR/pools.jsonl"
POOLS_RAW_JSONL="$OUT_DIR/pools.raw.jsonl"
UNKNOWN_JSONL="$OUT_DIR/unknown.jsonl"
: > "$POOLS_JSONL"
: > "$POOLS_RAW_JSONL"
: > "$UNKNOWN_JSONL"

echo "Input:  $INPUT_DIR"
echo "RPC:    (provided via RPC_URL env var)"
echo "Output: $OUT_DIR"
echo ""

ANALYZE_LAST_ERROR=""

analyze_address() {
  local address="$1"
  local address_lc
  address_lc="$(echo "$address" | tr '[:upper:]' '[:lower:]')"
  local cache_file="$CACHE_DIR/${address_lc}.json"
  ANALYZE_LAST_ERROR=""

  if [ -f "$cache_file" ]; then
    # Cache must be valid JSON (story RPC / which-dex can occasionally return non-JSON text)
    if jq -e . "$cache_file" >/dev/null 2>&1; then
      cat "$cache_file"
      return 0
    fi
    rm -f "$cache_file" >/dev/null 2>&1 || true
  fi

  # Normalize + validate which-dex output (avoid writing invalid JSON to cache)
  local out_tmp="${cache_file}.out.tmp"
  local err_tmp="${cache_file}.err.tmp"

  if ! "$WHICH_DEX_BIN" analyze --rpc-url "$RPC_URL" --address "$address" --json >"$out_tmp" 2>"$err_tmp"; then
    ANALYZE_LAST_ERROR="$(head -n 50 "$err_tmp" 2>/dev/null || true)"
    rm -f "$out_tmp" "$err_tmp" >/dev/null 2>&1 || true
    return 1
  fi

  if ! jq -c . "$out_tmp" > "${cache_file}.tmp" 2>/dev/null; then
    # Sometimes tools print non-JSON text on stdout; keep a snippet for debugging.
    ANALYZE_LAST_ERROR="invalid JSON stdout from which-dex (first 50 lines): $(head -n 50 "$out_tmp" 2>/dev/null | tr '\n' ' ' | head -c 400)"
    rm -f "${cache_file}.tmp" "$cache_file" >/dev/null 2>&1 || true
    rm -f "$out_tmp" "$err_tmp" >/dev/null 2>&1 || true
    return 1
  fi

  rm -f "$out_tmp" "$err_tmp" >/dev/null 2>&1 || true
  mv "${cache_file}.tmp" "$cache_file"

  cat "$cache_file"
}

files_total="$(find "$INPUT_DIR" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
if [ "$files_total" -eq 0 ]; then
  echo "No .json files found in: $INPUT_DIR" >&2
  exit 1
fi

file_idx=0
while IFS= read -r token_file; do
  file_idx=$((file_idx + 1))

  token_symbol="$(jq -r '.token.symbol // ""' "$token_file" 2>/dev/null || echo "")"
  token_address="$(jq -r '.token.address // ""' "$token_file" 2>/dev/null || echo "")"
  token_name="$(jq -r '.token.name // ""' "$token_file" 2>/dev/null || echo "")"

  if [ -z "$token_address" ]; then
    echo "[$file_idx/$files_total] Skipping (missing .token.address): $token_file" >&2
    continue
  fi

  holders_count="$(jq -r '.contract_holders | length' "$token_file" 2>/dev/null || echo "0")"
  echo "[$file_idx/$files_total] $token_symbol ($token_name) holders=$holders_count"

  # Iterate holders as compact JSON objects (loop must stay in the current shell for deduping).
  # shellcheck disable=SC2016
  while IFS= read -r holder; do
    holder_address="$(jq -r '.address // ""' <<<"$holder")"
    if [ -z "$holder_address" ]; then
      continue
    fi

    which_dex_json=""
    if ! which_dex_json="$(analyze_address "$holder_address")"; then
      jq -c -n \
        --arg holder_address "$holder_address" \
        --arg error "which-dex analyze failed" \
        --arg detail "${ANALYZE_LAST_ERROR:-}" \
        '{address:$holder_address, error:$error, detail:(if ($detail|length)==0 then null else $detail end)}' \
        >> "$UNKNOWN_JSONL"
      continue
    fi

    protocol="$(jq -r '.analysis.protocol // .protocol // "Unknown"' <<<"$which_dex_json" 2>/dev/null || echo "Unknown")"

    if [ "$protocol" = "Unknown" ] || [ "$protocol" = "null" ] || [ -z "$protocol" ]; then
      jq -c -n \
        --arg address "$holder_address" \
        --arg which_dex_raw "$which_dex_json" \
        '{address:$address, which_dex_raw:$which_dex_raw}' \
        >> "$UNKNOWN_JSONL"
      continue
    fi

    holder_name="$(jq -r '.name // ""' <<<"$holder" 2>/dev/null || echo "")"
    holder_is_verified="$(jq -r '.is_verified // false' <<<"$holder" 2>/dev/null || echo "false")"
    which_dex_is_proxy="$(jq -r '.is_eip1167_proxy // false' <<<"$which_dex_json" 2>/dev/null || echo "false")"

    jq -c -n \
      --arg address "$holder_address" \
      --arg protocol "$protocol" \
      --arg name "$holder_name" \
      --argjson is_verified "$holder_is_verified" \
      --argjson is_proxy "$which_dex_is_proxy" \
      '{
        address: $address,
        name: (if ($name | length) == 0 then null else $name end),
        protocol: $protocol,
        is_proxy: $is_proxy,
        is_verified: $is_verified
      }' \
      >> "$POOLS_RAW_JSONL"
  done < <(jq -c '.contract_holders[]? | {name, address, is_verified}' "$token_file" 2>/dev/null || true)
done < <(find "$INPUT_DIR" -maxdepth 1 -type f -name '*.json' | sort)

# Deduplicate pools by address across tokens and write both JSON + JSONL
if [ -s "$POOLS_RAW_JSONL" ]; then
  jq -s 'unique_by(.address | ascii_downcase)' "$POOLS_RAW_JSONL" > "$OUT_DIR/pools.json"
  jq -c '.[]' "$OUT_DIR/pools.json" > "$POOLS_JSONL"
else
  echo '[]' > "$OUT_DIR/pools.json"
  : > "$POOLS_JSONL"
fi

echo ""
echo "Done."
echo "Detected pools:  $(wc -l < "$POOLS_JSONL" | tr -d ' ')  ($POOLS_JSONL)"
echo "Unknown/errors:  $(wc -l < "$UNKNOWN_JSONL" | tr -d ' ')  ($UNKNOWN_JSONL)"