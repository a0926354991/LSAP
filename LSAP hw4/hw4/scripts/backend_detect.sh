#!/usr/bin/env bash
set -euo pipefail
DOMAINS_FILE="${DOMAINS_FILE:-domains.txt}"
OUT_RAW="data/backend_raw.csv"
OUT_SUM="data/backend_summary.csv"
TIMEOUT="${TIMEOUT:-8}"
UA="${UA:-Mozilla/5.0}"
SCHEMES="${SCHEMES:-https http}"
VARIANTS="${VARIANTS:-apex www}"
echo "domain,variant,scheme,status,server,via,x_powered_by,cdn_hint,app_hint" > "$OUT_RAW"
fetch(){
  u="$1"; h="$(curl -m "$TIMEOUT" -A "$UA" -sS -I -L -k "$u" -D - -o /dev/null || true)"
  st="$(printf "%s" "$h" | awk 'BEGIN{RS="\r?\n\r?\n"} NR==1{print}' | awk 'toupper($0) ~ /^HTTP/{code=$2} END{print code+0}')"
  sv="$(printf "%s" "$h" | awk -F': *' 'BEGIN{IGNORECASE=1} tolower($1)=="server"{print $2; exit}')"
  via="$(printf "%s" "$h" | awk -F': *' 'BEGIN{IGNORECASE=1} tolower($1)=="via"{print $2; exit}')"
  xp="$(printf "%s" "$h" | awk -F': *' 'BEGIN{IGNORECASE=1} tolower($1)=="x-powered-by"{print $2; exit}')"
  cf="$(printf "%s" "$h" | awk -F': *' 'BEGIN{IGNORECASE=1} tolower($1)=="cf-ray"{print "Cloudflare"; exit}')"
  ak="$(printf "%s" "$h" | awk -F': *' 'BEGIN{IGNORECASE=1} tolower($1)~/^server-timing$/{if(tolower($2)~/(ak_)/) print "Akamai"}')"
  fa="$(printf "%s" "$h" | awk -F': *' 'BEGIN{IGNORECASE=1} tolower($1)=="x-served-by"{if(tolower($2)~/(fastly)/) print "Fastly"}')"
  ec="$(printf "%s" "$h" | awk -F': *' 'BEGIN{IGNORECASE=1} tolower($1)~/^(x-ec-)/{print "Edgio_Limelight"; exit}')"
  lb="$(printf "%s" "$h" | awk -F': *' 'BEGIN{IGNORECASE=1} tolower($1)=="server"{if(tolower($2)~/(gws|tsa)/) print "Google"; else if(tolower($2)~/(cloudfront)/) print "AWS_CloudFront"; else if(tolower($2)~/(azure)/) print "Azure"}')"
  ch="${cf:-}${ak:+;$ak}${fa:+;$fa}${ec:+;$ec}${lb:+;$lb}"; ch="$(printf "%s" "$ch" | sed 's/^;*//;s/;*$//' | tr ';' '\n' | sort -u | paste -sd ';' -)"
  app="$(printf "%s" "$sv;$xp" | tr '[:upper:]' '[:lower:]')"
  app=$(printf "%s" "$app" | awk -F';' '{for(i=1;i<=NF;i++){s=$i; if(s~/nginx/) a="nginx"; if(s~/apache/) a=(a?a";":"")"apache"; if(s~/litespeed/) a=(a?a";":"")"litespeed"; if(s~/iis/) a=(a?a";":"")"microsoft_iis"; if(s~/gws/) a=(a?a";":"")"google_gws"; if(s~/tsa/) a=(a?a";":"")"google_tsa"; if(s~/cloudflare/) a=(a?a";":"")"cloudflare"; if(s~/cloudfront/) a=(a?a";":"")"aws_cloudfront"; if(s~/ats|apache traffic server/) a=(a?a";":"")"apache_traffic_server"}; print a; exit}')
  echo "$st|$sv|$via|$xp|$ch|$app"
}
run_one(){
  d="$1"; v="$2"; s="$3"; t="$d"; [ "$v" = "www" ] && t="www.$d"; u="$s://$t/"
  r="$(fetch "$u")"; st="${r%%|*}"; rest="${r#*|}"; sv="${rest%%|*}"; rest="${rest#*|}"; vi="${rest%%|*}"; rest="${rest#*|}"; xp="${rest%%|*}"; rest="${rest#*|}"; cdn="${rest%%|*}"; app="${rest#*|}"
  echo "$d,$v,$s,${st:-},${sv:-},${vi:-},${xp:-},${cdn:-},${app:-}" >> "$OUT_RAW"
}
while IFS= read -r d; do
  [ -z "${d// }" ] && continue
  case "$d" in \#*) continue;; esac
  for v in $VARIANTS; do for s in $SCHEMES; do run_one "$d" "$v" "$s"; done; done
done < "$DOMAINS_FILE"
awk -F, 'BEGIN{OFS=","; print "domain,server_guess,cdn_hint,examples"}
NR>1{
  k=$1
  if($9!=""){split($9,a,/;/); for(i in a) app[k":"a[i]]=1}
  if($8!=""){split($8,c,/;/); for(i in c) cdn[k":"c[i]]=1}
  ex[k]=$2" " $3 " " $4 " " $5
  seen[k]=1
}
END{
  for(d in seen){
    sg=""; sep=""
    for(x in app){ n=split(x,p,":"); if(p[1]==d){ sg=sg sep p[2]; sep=";"} }
    cg=""; sep=""
    for(x in cdn){ n=split(x,p,":"); if(p[1]==d){ cg=cg sep p[2]; sep=";"} }
    if(sg=="") sg="-"; if(cg=="") cg="-"
    print d,sg,cg,ex[d]
  }
}' "$OUT_RAW" | sort -t, -k1,1 > "$OUT_SUM"
echo "Done:"
echo "  - $OUT_RAW"
echo "  - $OUT_SUM"
