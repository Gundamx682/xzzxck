#!/bin/bash
# 多仓库APK下载脚本

# 从环境变量获取GitHub Token
GITHUB_TOKEN="$(grep -E "^export GITHUB_TOKEN=" /etc/profile 2>/dev/null | cut -d'"' -f2)"
CONFIG_FILE="/opt/apk-downloader/config.json"
LOG_FILE="/var/log/apk-downloader.log"

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE"
}

# 获取仓库列表
get_repositories() {
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r', encoding='utf-8') as f:
        config = json.load(f)
    for repo in config.get('repositories', []):
        if repo.get('enabled', True):
            print(f'{repo[\"owner\"]}/{repo[\"name\"]}:{repo.get(\"download_dir\", \"/var/www/apk-downloads\")}:{repo.get(\"check_interval\", 600)}')
except Exception as e:
    print('z0brk/netamade-releases:/var/www/apk-downloads:600')  # 默认仓库
"
}

# 下载单个仓库的APK
download_repo_apk() {
    local full_repo="$1"
    local owner name download_dir
    IFS=':' read -r repo_path download_dir interval <<< "$full_repo"
    IFS='/' read -r owner name <<< "$repo_path"
    
    log_info "检查仓库: $owner/$name"
    
    local api_url="https://api.github.com/repos/${owner}/${name}/releases/latest"
    local response
    response=$(curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer $GITHUB_TOKEN" -H "X-GitHub-Api-Version: 2022-11-28" "$api_url")
    
    if [ $? -ne 0 ] || [ -z "$response" ] || echo "$response" | grep -q "API rate limit exceeded"; then
        log_error "无法获取仓库信息: $owner/$name"
        return 1
    fi
    
    # 确保下载目录存在
    mkdir -p "$download_dir"
    
    # 提取APK下载链接
    local apk_urls
    apk_urls=$(echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'].lower().endswith('.apk'):
        print(asset['browser_download_url'])
")
    
    if [ -z "$apk_urls" ]; then
        log_warn "仓库 $owner/$name 中未找到APK文件"
        return 1
    fi
    
    # 下载每个APK
    while IFS= read -r download_url; do
        if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
            local apk_name
            apk_name=$(basename "$download_url")
            local apk_path="${download_dir}/${apk_name}"
            
            log_info "下载APK: $apk_name 从 $owner/$name"
            if curl -L -o "$apk_path" -H "Authorization: Bearer $GITHUB_TOKEN" "$download_url"; then
                log_info "下载成功: $apk_name"
                chmod 644 "$apk_path"
                
                # 清理旧文件，只保留最新的3个
                cd "$download_dir" 2>/dev/null || return 0
                ls -t *.apk 2>/dev/null | tail -n +4 | xargs -r rm -f
                
                return 0
            else
                log_error "下载失败: $apk_name"
                rm -f "$apk_path"  # 删除可能的不完整文件
                return 1
            fi
        fi
    done <<< "$apk_urls"
}

# 主循环 - 检查所有仓库
check_all_repos() {
    log_info "开始检查所有仓库..."
    
    while IFS= read -r repo; do
        if [ -n "$repo" ]; then
            download_repo_apk "$repo"
            # 为了避免API限制，在请求之间添加延迟
            sleep 2
        fi
    done <<< "$(get_repositories)"
}

main_loop() {
    log_info "多仓库APK下载服务启动"
    
    # 首次检查
    check_all_repos
    
    # 主循环 - 使用最短的检查间隔
    while true; do
        check_all_repos
        sleep 600  # 默认每10分钟检查一次
    done
}

main_loop
