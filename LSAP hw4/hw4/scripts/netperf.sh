#!/usr/bin/env bash
set -euo pipefail
DOMAINS_FILE="${DOMAINS_FILE:-domains.txt}"
OUT_RAW="data/netperf_raw.csv"
OUT_SUM="data/netperf_summary.csv"
TRIALS="${TRIALS:-5}"
PING_COUNT="${PING_COUNT:-5}"
CURL_TIMEOUT="${CURL_TIMEOUT:-8}"

echo "domain,trial,rtt_ms,loss_pct,speed_Bps" > "$OUT_RAW"

run_one() {
  d="$1"
  [ -z "${d// }" ] && return
  case "$d" in \#*) return;; esac
  for t in $(seq 1 "$TRIALS"); do
    p="$(ping -c "$PING_COUNT" "$d" 2>&1 || true)"
    loss="$(printf "%s\n" "$p" | grep -Eo '[0-9.]+% packet loss' | head -1 | sed 's/%.*//')"
    [ -z "$loss" ] && loss="-1"
    rtt="$(printf "%s\n" "$p" | grep -E 'round-trip|rtt' | awk -F'=' '{print $2}' | awk '{print $1}' | awk -F'/' '{print $2}')"
    [ -z "$rtt" ] && rtt="-1"
    sp="$(curl -m "$CURL_TIMEOUT" -s -o /dev/null -w "%{speed_download}" "https://$d/" || true)"
    [ -z "$sp" ] && sp="-1"
    echo "$d,$t,$rtt,$loss,$sp" >> "$OUT_RAW"
    sleep "0.$((RANDOM%3))"
  done
}

while IFS= read -r d; do run_one "$d"; done < "$DOMAINS_FILE"

awk -F, '
function add(a,x){if(x>=0){a["n"]++;a["s"]+=x;a["ss"]+=x*x}}
function avg(a){return a["n"]?a["s"]/a["n"]:-1}
function std(a){return a["n"]?sqrt(a["ss"]/a["n"]- (a["s"]/a["n"])^2):-1}
BEGIN{
  OFS=","
  print "domain","trials_ok","avg_rtt_ms","std_rtt_ms","avg_loss_pct","avg_speed_Mbps","std_speed_Mbps"
}
NR>1{
  d=$1; rtt=$3+0; loss=$4+0; sp=$5+0
  if(rtt>=0){rt[d,"n"]++; add(rt[d], rtt)}
  if(loss>=0){ls[d,"n"]++; add(ls[d], loss)}
  if(sp>=0){sd[d,"n"]++; add(sd[d], sp)}
  seen[d]=1
}
END{
  for(d in seen){
    rta=avg(rt[d]); rts=std(rt[d])
    lsa=avg(ls[d])
    sda=avg(sd[d]); sds=std(sd[d])
    mbps=(sda>=0)? sda*8/1000000 : -1
    mbpss=(sds>=0)? sds*8/1000000 : -1
    n_ok=(rt[d,"n"]>sd[d,"n"]? rt[d,"n"] : sd[d,"n"])
    if(lsa>=0 && lsa < 0) lsa=0
    print d, n_ok, rta, rts, lsa, mbps, mbpss
  }
}' "$OUT_RAW" | sort -t, -k1,1 > "$OUT_SUM"

echo "Done:"
echo "  - $OUT_RAW"
echo "  - $OUT_SUM"
