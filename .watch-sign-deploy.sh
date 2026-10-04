#!/bin/bash
# 等待 DevEco 自动签名写入 build-profile.json5，然后自动部署到真机
ROOT="C:/Users/12991/Desktop/YiBook"
for i in $(seq 1 180); do
  if grep -q '"certpath"' "$ROOT/build-profile.json5" 2>/dev/null; then
    echo "== 签名配置已就绪，开始部署 =="
    bash "$ROOT/device-run.sh"
    exit $?
  fi
  sleep 5
done
echo "TIMEOUT: 15 分钟内未检测到签名配置（signingConfigs 仍为空）"
exit 1
