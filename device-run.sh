#!/bin/bash
# 亦书真机一键部署：构建(签名) -> 安装 -> 启动 -> 跟日志
# 用法: bash device-run.sh          # 全流程
#       bash device-run.sh log      # 只跟 hilog（应用已装好后）
set -e
DEVECO="F:\\deveco\\DevEco Studio"
export DEVECO_SDK_HOME="F:\\deveco\\DevEco Studio\\sdk"
HDC="F:/deveco/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
HVIGOR="F:/deveco/DevEco Studio/tools/hvigor/bin/hvigorw.js"
NODE="F:/deveco/DevEco Studio/tools/node/node.exe"
BUNDLE="com.leaif.yibook"
ABILITY="EntryAbility"
ROOT="$(cd "$(dirname "$0")" && pwd)"

if [ "$1" = "log" ]; then
  exec "$HDC" hilog | grep --line-buffered -iE "yibook|myapplication|jscrash|cppcrash|FATAL"
fi

echo "[1/4] 构建 debug HAP..."
cd "$ROOT"
"$NODE" "$HVIGOR" assembleHap

HAP=$(ls -t entry/build/default/outputs/default/entry-default-signed.hap 2>/dev/null | head -1)
if [ -z "$HAP" ]; then
  echo ""
  echo "!! 未找到已签名 HAP（signingConfigs 为空）。"
  echo "   DevEco Studio: File > Project Structure > Signing Configs"
  echo "   勾选 Automatically generate signature，OK 后重跑本脚本。"
  exit 1
fi
echo "      产物: $HAP"

echo "[2/4] 安装到设备..."
"$HDC" list targets
"$HDC" install -r "$HAP"

echo "[3/4] 启动 $BUNDLE/$ABILITY ..."
"$HDC" shell aa start -a "$ABILITY" -b "$BUNDLE"

echo "[4/4] 跟踪 hilog（Ctrl+C 退出；单独看日志: bash device-run.sh log）"
"$HDC" hilog | grep --line-buffered -iE "yibook|myapplication|jscrash|cppcrash|FATAL"
