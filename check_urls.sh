#!/bin/bash

# 检查脚本URL引用的验证工具
# 验证meishi仓库中的文件引用是否正确

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查URL可访问性
check_url() {
    local url="$1"
    local description="$2"
    
    if curl -fsSL --max-time 10 --head "$url" >/dev/null 2>&1; then
        log_info "✓ $description: $url"
        return 0
    else
        log_error "✗ $description: $url (不可访问)"
        return 1
    fi
}

# 主函数
main() {
    log_step "开始检查GitHub仓库URL引用..."
    
    # 定义要检查的URL
    local base_url="https://raw.githubusercontent.com/Gundamx682/meishi/main"
    local files_to_check=(
        "install.sh"
        "apk-downloader.sh"
        "apk-server.py"
        "apk-downloader.service"
        "apk-server.service"
        "no-yum-install.sh"
        "simple-deps-install.sh"
        "download_latest_apk.sh"
        "install_apk_proxy.sh"
    )
    
    log_info "检查基础URL..."
    check_url "$base_url/install.sh" "基础URL"
    
    log_info "检查各个文件..."
    local failed_count=0
    local total_count=${#files_to_check[@]}
    
    for file in "${files_to_check[@]}"; do
        if ! check_url "$base_url/$file" "$file"; then
            ((failed_count++))
        fi
    done
    
    log_step "检查结果:"
    log_info "总文件数: $total_count"
    log_info "成功: $((total_count - failed_count))"
    log_error "失败: $failed_count"
    
    if [ $failed_count -gt 0 ]; then
        log_error "发现 $failed_count 个文件无法访问，请检查GitHub仓库中的文件是否正确上传"
        return 1
    else
        log_info "✓ 所有文件引用正确"
        return 0
    fi
}

main "$@"