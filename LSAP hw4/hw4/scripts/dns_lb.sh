#!/usr/bin/env bash
set -euo pipefail
DOMAINS_FILE="${DOMAINS_FILE:-domains.txt}"
OUT_RAW="data/dns_lb_raw.csv"
OUT_SUM="data/dns_lb_summary.csv"
RESOLVER="${RESOLVER:-1.1.1.1}"
RECORD_TYPE="${RECORD_TYPE:-A}"
TRIALS="${TRIALS:-20}"
SUBNET_OPT="${SUBNET:++subnet=${SUBNET}}"
mkdir -p data
echo "domain,trial,ips_ordered" > "$OUT_RAW"
run_for_domain() {
  d="$1"
  [ -z "${d// }" ] && return
  case "$d" in \#*) return;; esac
  for t in $(seq 1 "$TRIALS"); do
    ans="$(dig @"$RESOLVER" $SUBNET_OPT +tries=1 +time=2 "$d" "$RECORD_TYPE" +noall +answer 2>/dev/null || true)"
    ips="$(printf "%s\n" "$ans" | awk -v rt="$RECORD_TYPE" '$4==rt {print $5}' | sed 's/\.$//' | paste -sd ';' -)"
    [ -z "$ips" ] && ips="(no-answer)"
    echo "$d,$t,$ips" >> "$OUT_RAW"
    sleep "0.$((RANDOM%3))"
  done
}
if [ -n "${DOMAINS:-}" ]; then
  set -- $DOMAINS
  for d in "$@"; do run_for_domain "$d"; done
else
  while IFS= read -r d; do run_for_domain "$d"; done < "$DOMAINS_FILE"
fi
awk -F, -v RT="$RECORD_TYPE" '
BEGIN{OFS=","; print "domain,trials,record_type,unique_ip_count,unique_sequences,changed_in_pct,all_ips"}
NR>1{
  dom=$1; seq=$3; cnt[dom]++
  key=dom SUBSEP seq
  if(!(key in seqseen)) seqseen[key]=1
  n=split(seq,a,/;/)
  for(i=1;i<=n;i++){ ip=a[i]; if(ip!="" && ip!="(no-answer)") ipseen[dom SUBSEP ip]=1 }
  if(!(dom in first)) first[dom]=seq
  if(seq!=first[dom]) chg[dom]++
}
END{
  for(k in ipseen){ split(k,p,SUBSEP); d=p[1]; ip=p[2]; if(!(d in uipcount)) uipcount[d]=0; if(!( (d SUBSEP ip) in touched)){ touched[d SUBSEP ip]=1; uiplist[d]=(uiplist[d] ";" ip); uipcount[d]++ } }
  for(k in seqseen){ split(k,p,SUBSEP); d=p[1]; useq[d]++ }
  for(d in cnt){
    ips = (d in uiplist)? substr(uiplist[d],2) : ""
    u = (d in uipcount)? uipcount[d] : 0
    us = (d in useq)? useq[d] : 0
    p = (chg[d]+0) * 100.0 / cnt[d]
    print d, cnt[d], RT, u, us, p, ips
  }
}
' "$OUT_RAW" | sort -t, -k1,1 > "$OUT_SUM"
echo "Done:"
echo "  - $OUT_RAW"
echo "  - $OUT_SUM"
