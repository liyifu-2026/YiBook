#!/bin/bash
# devtap.sh "<文本>" [dy] — 在当前屏幕上找包含文本的节点，点击其中心（可加纵向偏移）
export MSYS_NO_PATHCONV=1
HDC="F:/deveco/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
ROOT="C:/Users/12991/Desktop/YiBook"
"$HDC" shell uitest dumpLayout -p /data/local/tmp/_nav.json >/dev/null 2>&1
"$HDC" file recv /data/local/tmp/_nav.json 'C:\Users\12991\Desktop\YiBook\.device-shots\_nav.json' >/dev/null 2>&1
read -r X Y <<< "$(node -e "
const t=JSON.parse(require('fs').readFileSync('$ROOT/.device-shots/_nav.json','utf8'));
const needle=process.argv[1]; const dy=parseInt(process.argv[2]||'0');
let hit=null;
const walk=(n)=>{const a=n.attributes||{};
  if((a.text||'').includes(needle)&&a.bounds){hit=a;}
  (n.children||[]).forEach(walk);};
walk(t);
if(!hit){console.error('NOT_FOUND: '+needle);process.exit(1);}
const m=hit.bounds.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
console.log(Math.round((+m[1]+ +m[3])/2)+' '+Math.round((+m[2]+ +m[4])/2+dy));
" "$1" "${2:-0}")"
if [ -z "$X" ]; then echo "tap failed: $1"; exit 1; fi
echo "tap '$1' at ($X,$Y)"
"$HDC" shell uitest uiInput click "$X" "$Y"
