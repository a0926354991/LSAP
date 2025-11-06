#!/usr/bin/env bash
set -euo pipefail

DOMAINS_FILE="${1:-domains.txt}"
OUT_RAW="data/dns_time_raw.csv"
OUT_SUM="data/dns_time_avg.csv"
RESOLVER="${RESOLVER:-1.1.1.1}"
RECORD_TYPE="${RECORD_TYPE:-A}"
TRIALS="${TRIALS:-7}"

mkdir -p data
echo "domain,trial,ms" > "$OUT_RAW"

while IFS= read -r domain; do
  [[ -z "${domain// }" || "$domain" =~ ^# ]] && continue
  for t in $(seq 1 "$TRIALS"); do
    out="$(dig @"$RESOLVER" +tries=1 +time=2 "$domain" "$RECORD_TYPE" +noall +answer +stats 2>/dev/null || true)"
    ms="$(printf "%s\n" "$out" | awk -F': ' '/^;; Query time:/{print $2}' | awk '{print $1}')"
    [[ -z "$ms" ]] && ms="-1"
    echo "$domain,$t,$ms" >> "$OUT_RAW"
    sleep "0.$(( RANDOM % 4 ))"
  done
done < "$DOMAINS_FILE"

awk -F, 'BEGIN{
  OFS=","; print "domain,trials,avg_ms,min_ms,max_ms,std_ms"
}
NR>1 {
  if ($3 >= 0) {
    n[$1]++; s[$1]+=$3; ss[$1]+=$3*$3;
    if (!($1 in min) || $3<min[$1]) min[$1]=$3;
    if (!($1 in max) || $3>max[$1]) max[$1]=$3;
  }
}
END{
  for (d in n) {
    avg = s[d]/n[d];
    var = (ss[d]/n[d]) - (avg*avg); if (var < 0) var = 0;
    std = sqrt(var);
    print d, n[d], avg, min[d], max[d], std;
  }
}' "$OUT_RAW" | sort -t, -k3,3n > "$OUT_SUM"

echo "Done:"
echo "  - $OUT_RAW"
echo "  - $OUT_SUM"
