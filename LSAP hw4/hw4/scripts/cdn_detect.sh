#!/usr/bin/env bash
set -euo pipefail
DOMAINS_FILE="${DOMAINS_FILE:-domains.txt}"
OUT_RAW="data/cdn_raw.csv"
OUT_SUM="data/cdn_summary.csv"
RESOLVER="${RESOLVER:-1.1.1.1}"
RECORD="${RECORD:-A}"
CHECK_WWW="${CHECK_WWW:-1}"

echo "domain,variant,record,ips,cname_chain,whois_orgs,whois_countries,cdn_guess" > "$OUT_RAW"

dig_ips(){ dig @"$RESOLVER" +short "$1" "$2" | sed 's/\.$//' | paste -sd ';' -; }
cname_chain(){ d="$1"; chain=""; for _ in 1 2 3 4 5; do c=$(dig @"$RESOLVER" +short CNAME "$d" | sed 's/\.$//'); [ -z "$c" ] && break; chain="${chain:+$chain -> }$c"; d="$c"; done; echo "${chain:--}"; }
whois_fields(){
  ips="$1"; orgs=""; ctry=""
  [ -z "$ips" ] && { echo "|"; return; }
  for ip in $(printf "%s" "$ips" | tr ';' ' '); do
    [ -z "$ip" ] && continue
    w=$(whois "$ip" 2>/dev/null || true)
    o=$(printf "%s\n" "$w" | awk -F': *' '/^(OrgName|org-name|owner|Organization|descr|netname)/{print $2; exit}')
    co=$(printf "%s\n" "$w" | awk -F': *' '/^(Country|country)/{print $2; exit}')
    [ -n "$o" ] && orgs="${orgs:+$orgs;}$o"
    [ -n "$co" ] && ctry="${ctry:+$ctry;}$co"
  done
  orgs=$(printf "%s\n" "$orgs" | tr ';' '\n' | awk 'NF' | sort -u | paste -sd ';' -)
  ctry=$(printf "%s\n" "$ctry" | tr ';' '\n' | awk 'NF' | sort -u | paste -sd ';' -)
  echo "$orgs|$ctry"
}
guess(){
  lc_c=$(printf "%s" "$1" | tr 'A-Z' 'a-z'); lc_o=$(printf "%s" "$2" | tr 'A-Z' 'a-z')
  case "$lc_c" in
    *cloudflare.com*|*cf-ipfs.com*|*cdn.cloudflare.net*) echo Cloudflare; return;;
    *akamai*|*akadns.net*|*akamaiedge.net*|*edgekey.net*) echo Akamai; return;;
    *fastly.net*|*fastlylb.net*) echo Fastly; return;;
    *cloudfront.net*) echo AWS_CloudFront; return;;
    *azureedge.net*|*a-msedge.net*) echo Azure_CDN; return;;
    *googleusercontent.com*|*googlehosted.com*) echo Google; return;;
    *fbcdn.net*|*facebook.com*) echo Meta; return;;
  esac
  case "$lc_o" in
    *cloudflare*) echo Cloudflare;;
    *akamai*) echo Akamai;;
    *fastly*) echo Fastly;;
    *amazon*|*aws*) echo AWS_CloudFront_or_AWS;;
    *google*) echo Google;;
    *microsoft*) echo Azure_or_Microsoft;;
    *edgecast*|*verizon*) echo EdgeCast_Verizon;;
    *limelight*|*edgio*) echo Edgio_Limelight;;
    *alibaba*|*alicloud*) echo Alibaba_Cloud_CDN;;
    *) echo Unknown;;
  esac
}
run_one(){
  dom="$1"; var="$2"; target="$dom"; [ "$var" = "www" ] && target="www.$dom"
  ips=$(dig_ips "$target" "$RECORD"); cn=$(cname_chain "$target")
  wf=$(whois_fields "$ips"); orgs="${wf%%|*}"; ctry="${wf#*|}"
  cdn=$(guess "$cn" "$orgs")
  echo "$dom,$var,$RECORD,${ips:-},${cn:-},${orgs:-},${ctry:-},$cdn"
}
while IFS= read -r d; do
  [ -z "${d// }" ] && continue
  case "$d" in \#*) continue;; esac
  run_one "$d" apex >> "$OUT_RAW"
  [ "$CHECK_WWW" = "1" ] && run_one "$d" www >> "$OUT_RAW"
done < "$DOMAINS_FILE"

awk -F, 'BEGIN{OFS=",";print "domain,variants,record,unique_ips,orgs,whois_countries,cdn_guess"}
NR>1{
  k=$1 FS $3
  if($4!=""){ n=split($4,a,/;/); for(i=1;i<=n;i++) ip[k":"a[i]]=1 }
  org[$1]=$6; c[$1]=$7; cdn[$1]=$8; seen[$1]=1
}
END{
  for(d in seen){
    uA=0; for(x in ip) if (x ~ "^" d ",A:") uA++
    uAAAA=0; for(x in ip) if (x ~ "^" d ",AAAA:") uAAAA++
    ips=(uA>0?uA" (A)":"-"); if(uAAAA>0) ips=ips"; "uAAAA" (AAAA)"
    print d,"apex;www","A/AAAA",ips,org[d],c[d],cdn[d]
  }
}' "$OUT_RAW" > "$OUT_SUM"

echo "Done:"
echo "  - $OUT_RAW"
echo "  - $OUT_SUM"
