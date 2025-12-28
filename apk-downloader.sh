#!/bin/bash
# 基础APK下载脚本

REPO_OWNER="z0brk"
REPO_NAME="netamade-releases"
APK_DIR="/var/www/apk-downloads"
CHECK_INTERVAL=600

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a /var/log/apk-downloader.log
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" | tee -a /var/log/apk-downloader.log
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a /var/log/apk-downloader.log
}

get_latest_release() {
    local api_url="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
    local response
    response=$(curl -s -H "Accept: application/vnd.github+json" -H "User-Agent: APK-Downloader" "$api_url")
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        log_error "无法获取GitHub API响应"
        return 1
    fi
    
    if echo "$response" | grep -q '"message":'; then
        log_error "GitHub API错误"
        return 1
    fi
    
    echo "$response"
}

download_apk() {
    local release_info="$1"
    local apk_urls
    apk_urls=$(echo "$release_info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'].lower().endswith('.apk'):
        print(asset['browser_download_url'])
")
    
    if [ -z "$apk_urls" ]; then
        log_warn "未找到APK文件"
        return 1
    fi
    
    # 下载每个APK
    while IFS= read -r download_url; do
        if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
            local apk_name
            apk_name=$(basename "$download_url")
            local apk_path="${APK_DIR}/${apk_name}"
            
            log_info "下载APK: $apk_name"
            if curl -L -o "$apk_path" -H "User-Agent: APK-Downloader" "$download_url"; then
                log_info "下载成功: $apk_name"
                chmod 644 "$apk_path"
                
                # 清理旧文件，只保留最新的3个
                cd "$APK_DIR" 2>/dev/null || return 0
                ls -t *.apk 2>/dev/null | tail -n +4 | xargs -r rm -f
                
                return 0
            else
                log_error "下载失败: $apk_name"
                return 1
            fi
        fi
    done <<< "$apk_urls"
}

main_loop() {
    log_info "APK下载服务启动"
    log_info "监控仓库: $REPO_OWNER/$REPO_NAME"
    log_info "检查间隔: ${CHECK_INTERVAL}秒"
    
    # 首次检查
    local release_info
    release_info=$(get_latest_release)
    if [ $? -eq 0 ]; then
        download_apk "$release_info"
    fi
    
    # 主循环
    while true; do
        sleep "$CHECK_INTERVAL"
        release_info=$(get_latest_release)
        if [ $? -eq 0 ]; then
            download_apk "$release_info"
        fi
    done
}

main_loop