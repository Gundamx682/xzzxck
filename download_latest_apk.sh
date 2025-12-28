#!/bin/bash

# 简单的APK下载脚本 - xzzxck项目版
# 用于手动下载最新APK

set -e

# 从环境变量获取GitHub Token
GITHUB_TOKEN="$(grep -E "^export GITHUB_TOKEN=" /etc/profile 2>/dev/null | cut -d'"' -f2)"

# 配置参数
REPO_OWNER="z0brk"
REPO_NAME="netamade-releases"
DOWNLOAD_DIR="${1:-.}"  # 使用第一个参数作为下载目录，默认为当前目录

echo "开始下载最新的APK..."

# 获取最新release信息
echo "获取 $REPO_OWNER/$REPO_NAME 最新release信息..."
API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"

if [ -n "$GITHUB_TOKEN" ]; then
    RESPONSE=$(curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" "$API_URL")
else
    RESPONSE=$(curl -s -H "Accept: application/vnd.github+json" "$API_URL")
fi

if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
    echo "错误: 无法获取release信息"
    exit 1
fi

# 提取APK下载链接
APK_URL=$(echo "$RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'].lower().endswith('.apk'):
        print(asset['browser_download_url'])
        break
")

if [ -z "$APK_URL" ]; then
    echo "错误: 未找到APK文件"
    exit 1
fi

# 获取APK文件名
APK_NAME=$(basename "$APK_URL")

echo "找到APK文件: $APK_NAME"
echo "开始下载..."

# 下载APK
if [ -n "$GITHUB_TOKEN" ]; then
    curl -L -H "Authorization: Bearer $GITHUB_TOKEN" "$APK_URL" -o "$DOWNLOAD_DIR/$APK_NAME"
else
    curl -L "$APK_URL" -o "$DOWNLOAD_DIR/$APK_NAME"
fi

if [ $? -eq 0 ]; then
    echo "下载完成: $DOWNLOAD_DIR/$APK_NAME"
    echo "文件大小: $(ls -lh "$DOWNLOAD_DIR/$APK_NAME" | awk '{print $5}')"
else
    echo "下载失败"
    exit 1
fi