#!/usr/bin/env bash
set -euo pipefail

DOMAINS_FILE="${1:-domains.txt}"
OUT_CSV="data/dns_records.csv"
TRACE_DIR="data/trace"
RESOLVER="${RESOLVER:-1.1.1.1}"  # 可改 8.8.8.8

mkdir -p "$(dirname "$OUT_CSV")" "$TRACE_DIR"

echo "domain,ipv4,ipv6,cname,mx,dnssec_ad" > "$OUT_CSV"

join_semicolon() { sed 's/\.$//' | paste -sd ';' -; }

has_ad() {
  local d="$1"
  dig @"$RESOLVER" +dnssec "$d" A +cmd +nocmd +noall 2>/dev/null \
  | awk '/flags:/{ if ($0 ~ / ad[ ;]/) {print 1} else {print 0}; exit }'
}

while IFS= read -r domain; do
  [[ -z "${domain// }" || "$domain" =~ ^# ]] && continue

  ipv4=$(dig @"$RESOLVER" +short A "$domain"    | join_semicolon || true)
  ipv6=$(dig @"$RESOLVER" +short AAAA "$domain" | join_semicolon || true)
  cname=$(dig @"$RESOLVER" +short CNAME "$domain" | join_semicolon || true)
  mx=$(dig @"$RESOLVER" +short MX "$domain" | sed 's/\.$//' | paste -sd ';' - || true)
  dnssec_ad=$(has_ad "$domain" || echo 0)

  dig +trace "$domain" > "$TRACE_DIR/$domain.trace.txt" 2>/dev/null || true

  echo "$domain,${ipv4:-},${ipv6:-},${cname:-},${mx:-},$dnssec_ad" >> "$OUT_CSV"
done < "$DOMAINS_FILE"

echo "Done → $OUT_CSV  &  $TRACE_DIR/*.trace.txt"
