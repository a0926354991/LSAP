#!/usr/bin/env bash
set -euo pipefail
D="${1:?usage: route_analyze.sh <domain>}"
OUT_CSV="data/route_${D}.csv"
OUT_MMD="report/route_${D}.mmd"
TR="$(command -v traceroute || true)"
[ -z "$TR" ] && { echo "traceroute not found"; exit 1; }

echo "hop,ip,hostname,org,country,location,avg_ms" > "$OUT_CSV"

$TR -n -q 3 -w 2 "$D" | awk 'NR>1' | while read -r line; do
  hop="$(echo "$line" | awk "{print \$1}")"
  ip="$(echo "$line" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)"
  if [ -z "$ip" ]; then
    echo "$line" | grep -q '\* \* \*' && ip="*"
  fi
  if [ "$ip" = "*" ] || [ -z "$ip" ]; then
    hn="*"; org=""; ctry=""; loc=""; avg="-1"
  else
    hn="$(dig +short -x "$ip" | sed 's/\.$//' | head -1)"
    [ -z "$hn" ] && hn="-"
    ms_raw="$(echo "$line" | grep -Eo '[0-9]+\.[0-9]+ ms' | awk '{print $1}')"
    if [ -z "$ms_raw" ]; then avg="-1"; else
      c=0; s=0; echo "$ms_raw" | while read -r v; do c=$((c+1)); s=$(awk -v a="$s" -v b="$v" 'BEGIN{printf "%.6f", a+b}'); done
      avg="$(awk -v s="$s" -v c="$c" 'BEGIN{ if(c>0) printf "%.3f", s/c; else print "-1"}')"
    fi
    wf="$(whois "$ip" 2>/dev/null || true)"
    org="$(printf "%s\n" "$wf" | awk -F': *' 'tolower($1)~/^(orgname|org-name|owner|organization|descr|netname)$/ {print $2; exit}')"
    ctry="$(printf "%s\n" "$wf" | awk -F': *' 'tolower($1)~/^country$/ {print $2; exit}')"
    [ -z "$org" ] && org="-"; [ -z "$ctry" ] && ctry="-"
    ji="$(curl -m 3 -s "https://ipinfo.io/$ip" || true)"
    city="$(printf "%s" "$ji" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    region="$(printf "%s" "$ji" | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
    if [ -n "$city$region" ]; then loc="$city/$region"; else loc="-"; fi
  fi
  echo "$hop,$ip,$hn,$org,$ctry,$loc,$avg" >> "$OUT_CSV"
done

echo "flowchart LR" > "$OUT_MMD"
echo "  classDef hop fill:#eef,stroke:#999,rx:10,ry:10;" >> "$OUT_MMD"
i=0
while IFS=, read -r hop ip hn org ctry loc avg; do
  [ "$hop" = "hop" ] && continue
  label="Hop ${hop}\n${ip}\n${hn}\n${org}\n${ctry} ${loc}\n${avg} ms"
  echo "  N${hop}[\"$label\"]:::hop" >> "$OUT_MMD"
  if [ "$i" -gt 0 ]; then prev=$((hop-1)); echo "  N${prev} --> N${hop}" >> "$OUT_MMD"; fi
  i=$((i+1))
done < "$OUT_CSV"

echo "Done"
echo "$OUT_CSV"
echo "$OUT_MMD"
