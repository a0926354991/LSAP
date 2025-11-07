#!/usr/bin/env bash
# dns_lb.sh — 檢測 DNS 層級的負載平衡（是否回傳多組 IP / 多種順序）
# 用法：
#   ./scripts/dns_lb.sh                 # 用預設 domains.txt
#   ./scripts/dns_lb.sh my_domains.txt  # 指定清單
# 可用環境變數覆蓋：
#   RESOLVER=8.8.8.8 RECORD_TYPE=AAAA TRIALS=30 SUBNET=1.2.3.0/24 ./scripts/dns_lb.sh
set -euo pipefail

DOMAINS_FILE="${1:-domains.txt}"
OUT_RAW="data/dns_lb_raw.csv"
OUT_SUM="data/dns_lb_summary.csv"

RESOLVER="${RESOLVER:-1.1.1.1}"   # e.g., 8.8.8.8
RECORD_TYPE="${RECORD_TYPE:-A}"   # A / AAAA / CNAME
TRIALS="${TRIALS:-20}"            # 每個網域嘗試次數
SUBNET_OPT="${SUBNET:++subnet=${SUBNET}}"   # EDNS Client Subnet（選用）

mkdir -p data
echo "domain,trial,ips_ordered" > "$OUT_RAW"

run_for_domain() {
  local d="$1"
  [ -z "${d// }" ] && return
  case "$d" in \#*) return;; esac

  for t in $(seq 1 "$TRIALS"); do
    # 只取 answer 區；逾時不丟錯（用 || true）
    ans="$(dig @"$RESOLVER" $SUBNET_OPT +tries=1 +time=2 "$d" "$RECORD_TYPE" +noall +answer 2>/dev/null || true)"
    # 取出記錄的第 5 欄；A/AAAA 是 IP、CNAME 是別名（尾巴的 . 會去掉）
    ips="$(printf "%s\n" "$ans" | awk -v rt="$RECORD_TYPE" '$4==rt {print $5}' | sed 's/\.$//' | paste -sd ';' -)"
    [ -z "$ips" ] && ips="(no-answer)"
    echo "$d,$t,$ips" >> "$OUT_RAW"
    sleep "0.$((RANDOM%3))"
  done
}

# 來源可以用 DOMAINS 環境變數（空白分隔），或檔案
if [ -n "${DOMAINS:-}" ]; then
  set -- $DOMAINS
  for d in "$@"; do run_for_domain "$d"; done
else
  while IFS= read -r d; do run_for_domain "$d"; done < "$DOMAINS_FILE"
fi

# 彙總：每個 domain 的
#  - trials：有效樣本數（排除 "(no-answer)"）
#  - unique_ip_count：去重之後的 IP 數
#  - unique_sequences：不同的回應順序出現幾種
#  - changed_in_pct：與首次序列不同的比例（偵測輪詢/順序變化）
#  - all_ips：所有觀察到的 IP（去重；以 ; 連）
awk -F, -v RT="$RECORD_TYPE" '
BEGIN{
  OFS=","; print "domain,trials,record_type,unique_ip_count,unique_sequences,changed_in_pct,all_ips"
}
NR>1{
  dom=$1; seq=$3;

  # 記錄總次數（包含 no-answer，用於基數計算用不到；後面會改用有效次數）
  tot[dom]++;

  # 把 (no-answer) 當成失敗樣本，不納入統計
  if (seq=="(no-answer)") { fail[dom]++; next }

  cnt[dom]++;                              # 有效樣本數
  key=dom SUBSEP seq; seqSeen[key]=1;      # 序列去重

  n=split(seq, a, /;/);
  for(i=1;i<=n;i++){
    ip=a[i];
    if(ip!=""){
      ipSeen[dom SUBSEP ip]=1;            # IP 去重（per-domain）
    }
  }

  if(!(dom in firstSeq)) firstSeq[dom]=seq;    # 第一個序列
  if(seq!=firstSeq[dom]) changed[dom]++;       # 與第一序列不同者計數
}
END{
  # 彙整 IP 清單與計數
  for(k in ipSeen){
    split(k, parts, SUBSEP); d=parts[1]; ip=parts[2];
    if(!((d SUBSEP ip) in touched)){
      touched[d SUBSEP ip]=1;
      ipList[d]=(ipList[d] ";" ip);
      uniqIpCount[d]++;
    }
  }

  # 彙整不同序列數
  for(k in seqSeen){
    split(k, parts, SUBSEP); d=parts[1];
    uniqSeqCount[d]++;
  }

  # 輸出各網域
  for(d in cnt){
    ips = (d in ipList)     ? substr(ipList[d],2) : "";
    u   = (d in uniqIpCount)? uniqIpCount[d]      : 0;
    us  = (d in uniqSeqCount)? uniqSeqCount[d]    : 0;
    # 以有效樣本數為分母；若 0（全失敗）則給 0
    denom = (cnt[d]>0 ? cnt[d] : 1);
    pct = (changed[d]+0) * 100.0 / denom;
    print d, cnt[d], RT, u, us, pct, ips;
  }
}
' "$OUT_RAW" | sort -t, -k1,1 > "$OUT_SUM"

echo "Done:"
echo "  - $OUT_RAW"
echo "  - $OUT_SUM"
