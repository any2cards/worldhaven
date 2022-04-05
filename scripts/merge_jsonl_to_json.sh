#!/bin/sh
json="${1}"
jsonl="${2}"
key="${3:-image}"

tmp=$(mktemp)
cleanup() {
  rm -rf "${tmp}"
}
trap cleanup EXIT

jq '. + [inputs] |group_by(.'${key}') |map(add)' "${json}" "${jsonl}" > "${tmp}"
mv "${tmp}" "${json}"
