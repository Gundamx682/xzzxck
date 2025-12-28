#!/bin/bash

# 综合APK下载和代理服务安装脚本
# 用于CentOS系统，IP: 45.130.146.21

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置参数
INSTALL_DIR="/opt/apk-downloader"
PROXY_DIR="/opt/apk-proxy"
APK_DIR="/var/www/apk-downloads"
LOG_DIR="/var/log"
SERVER_IP="45.130.146.21"

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

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请以root权限运行此脚本"
        exit 1
    fi
}

# 检查系统
check_system() {
    log_step "检查系统信息..."
    
    if [ ! -f /etc/centos-release ] && [ ! -f /etc/redhat-release ]; then
        log_error "此脚本仅支持CentOS/RHEL系统"
        exit 1
    fi
    
    if [ -f /etc/centos-release ]; then
        log_info "检测到: $(cat /etc/centos-release)"
    else
        log_info "检测到: $(cat /etc/redhat-release)"
    fi
}

# 安装依赖（无YUM方式）
install_dependencies() {
    log_step "安装系统依赖..."
    
    # 检查关键工具
    local tools=("curl" "python3" "systemctl")
    local missing=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [ ${#missing[@]} -eq 0 ]; then
        log_info "✓ 所有关键工具已安装"
        return 0
    fi
    
    log_info "安装缺失工具: ${missing[*]}"
    
    # 尝试安装关键工具
    for tool in "${missing[@]}"; do
        case "$tool" in
            "curl")
                if command -v dnf &> /dev/null; then
                    dnf install -y curl --setopt=install_weak_deps=False 2>/dev/null || log_warn "curl安装可能失败"
                else
                    yum install -y curl --setopt=install_weak_deps=False 2>/dev/null || log_warn "curl安装可能失败"
                fi
                ;;
            "python3")
                if command -v dnf &> /dev/null; then
                    dnf install -y python3 --setopt=install_weak_deps=False 2>/dev/null || log_warn "python3安装可能失败"
                else
                    yum install -y python3 --setopt=install_weak_deps=False 2>/dev/null || log_warn "python3安装可能失败"
                fi
                ;;
        esac
    done
    
    # 验证安装
    local still_missing=()
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            still_missing+=("$tool")
        fi
    done
    
    if [ ${#still_missing[@]} -gt 0 ]; then
        log_error "关键工具缺失: ${still_missing[*]}"
        exit 1
    fi
    
    log_info "✓ 依赖安装完成"
}

# 创建目录
create_directories() {
    log_step "创建目录结构..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$PROXY_DIR"
    mkdir -p "$APK_DIR"
    mkdir -p "$LOG_DIR"
    
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$PROXY_DIR"
    chmod 755 "$APK_DIR"
    
    log_info "目录结构创建完成"
}

# 部署代理服务脚本
deploy_proxy_service() {
    log_step "部署代理服务..."
    
    # 创建代理服务脚本
    cat > "$PROXY_DIR/apk-proxy.sh" << 'EOF'
#!/bin/bash

# APK代理下载服务
# 用于通过代理服务器下载GitHub releases中的APK文件

set -e

# 配置参数
REPO_OWNER="z0brk"
REPO_NAME="netamade-releases"
GITHUB_API="https://api.github.com"
APK_DIR="/var/www/apk-downloads"
LOG_FILE="/var/log/apk-proxy.log"
CHECK_INTERVAL=600  # 10分钟
SERVER_IP="45.130.146.21"

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" | tee -a "$LOG_FILE"
}

# 创建目录
setup_directories() {
    mkdir -p "$APK_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    chmod 755 "$APK_DIR"
}

# 获取最新release信息
get_latest_release() {
    local api_url="${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest"
    log_info "获取最新release: $api_url"
    
    local response
    response=$(curl -s -H "Accept: application/vnd.github+json" -H "User-Agent: APK-Proxy-Service" "$api_url")
    
    if [ $? -ne 0 ]; then
        log_error "无法获取GitHub API响应"
        return 1
    fi
    
    if echo "$response" | grep -q '"message":'; then
        log_error "GitHub API错误: $response"
        return 1
    fi
    
    echo "$response"
}

# 下载APK文件
download_apk_via_proxy() {
    local release_info="$1"
    
    # 提取APK下载链接
    local apk_urls
    apk_urls=$(echo "$release_info" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'].lower().endswith('.apk'):
        print(asset['browser_download_url'])
")
    
    if [ -z "$apk_urls" ]; then
        log_error "未找到APK文件"
        return 1
    fi
    
    # 下载每个APK
    while IFS= read -r download_url; do
        if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
            local apk_name
            apk_name=$(basename "$download_url")
            local apk_path="${APK_DIR}/${apk_name}"
            
            log_info "下载APK: $apk_name"
            
            # 使用curl下载APK文件
            if curl -L -o "$apk_path" -H "User-Agent: APK-Proxy-Service" "$download_url"; then
                log_info "下载成功: $apk_name"
                chmod 644 "$apk_path"
                
                # 记录版本信息
                local version
                version=$(echo "$release_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('tag_name', 'unknown'))")
                echo "$version" > "${APK_DIR}/current_version.txt"
                
                return 0
            else
                log_error "下载失败: $apk_name"
                return 1
            fi
        fi
    done <<< "$apk_urls"
    
    return 0
}

# 清理旧文件
cleanup_old_apks() {
    log_info "清理旧APK文件..."
    
    # 保留最新的3个APK文件
    cd "$APK_DIR" || return 1
    ls -t *.apk 2>/dev/null | tail -n +4 | xargs -r rm -f
    
    log_info "旧文件清理完成"
}

# 检查更新
check_for_updates() {
    local current_version new_version release_info
    
    # 获取当前版本
    if [ -f "${APK_DIR}/current_version.txt" ]; then
        current_version=$(cat "${APK_DIR}/current_version.txt")
    else
        current_version=""
    fi
    
    # 获取最新release
    release_info=$(get_latest_release)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # 提取版本号
    new_version=$(echo "$release_info" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('tag_name', 'unknown'))")
    
    if [ -z "$new_version" ] || [ "$new_version" = "null" ]; then
        log_error "无法获取版本号"
        return 1
    fi
    
    log_info "当前版本: $current_version, 最新版本: $new_version"
    
    # 检查是否有更新
    if [ "$current_version" != "$new_version" ]; then
        log_info "发现新版本: $new_version"
        
        if download_apk_via_proxy "$release_info"; then
            cleanup_old_apks
            log_info "更新完成"
            return 0
        else
            log_error "下载失败"
            return 1
        fi
    else
        log_info "已是最新版本"
        return 0
    fi
}

# 主循环
main_loop() {
    log_info "APK代理下载服务启动"
    log_info "服务器IP: $SERVER_IP"
    log_info "检查间隔: ${CHECK_INTERVAL}秒"
    
    setup_directories
    
    # 首次检查
    check_for_updates
    
    # 主循环
    while true; do
        sleep "$CHECK_INTERVAL"
        check_for_updates
    done
}

# 主函数
main() {
    if [ "$EUID" -ne 0 ]; then
        echo "请使用root权限运行"
        exit 1
    fi
    
    main_loop
}

# 信号处理
trap 'log_info "服务停止"; exit 0' SIGTERM SIGINT

main "$@"
EOF

    chmod +x "$PROXY_DIR/apk-proxy.sh"
    log_info "代理服务脚本部署完成"
}

# 创建systemd服务文件
create_systemd_service() {
    log_step "创建systemd服务..."
    
    cat > /etc/systemd/system/apk-proxy.service << EOF
[Unit]
Description=APK Proxy Download Service
Documentation=https://github.com/z0brk/netamade-releases
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/apk-proxy
ExecStart=/opt/apk-proxy/apk-proxy.sh
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=apk-proxy

# 安全设置
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/www/apk-downloads /var/log

# 资源限制
LimitNOFILE=65536
LimitNPROC=4096

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载systemd
    systemctl daemon-reload
    log_info "systemd服务文件创建完成"
}

# 配置防火墙
configure_firewall() {
    log_step "配置防火墙..."
    
    if command -v firewall-cmd &> /dev/null; then
        systemctl enable firewalld 2>/dev/null || true
        systemctl start firewalld 2>/dev/null || true
        
        # 开放必要端口
        firewall-cmd --permanent --add-port=8080/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=8081/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        
        log_info "防火墙配置完成"
    else
        log_warn "firewalld未安装，跳过防火墙配置"
    fi
}

# 启动服务
start_services() {
    log_step "启动服务..."
    
    # 启用并启动apk-proxy服务
    systemctl enable apk-proxy 2>/dev/null || true
    systemctl start apk-proxy 2>/dev/null || true
    
    sleep 3
    
    if systemctl is-active --quiet apk-proxy; then
        log_info "✓ APK代理服务启动成功"
    else
        log_warn "⚠ APK代理服务可能未完全启动"
    fi
}

# 验证安装
verify_installation() {
    log_step "验证安装..."
    
    log_info "服务器IP: $SERVER_IP"
    log_info "APK目录: $APK_DIR"
    log_info "服务状态:"
    
    if systemctl is-active --quiet apk-proxy; then
        log_info "✓ apk-proxy 服务: 运行中"
    else
        log_info "○ apk-proxy 服务: 未运行"
    fi
    
    log_info "安装的脚本:"
    ls -la "$PROXY_DIR/"
    ls -la "$INSTALL_DIR/"
    
    log_info "========================================="
    log_info "安装完成！"
    log_info "========================================="
    echo ""
    log_info "🔄 APK代理服务正在后台运行"
    log_info "📱 服务自动下载 https://github.com/z0brk/netamade-releases/releases 最新APK"
    log_info "📋 管理命令:"
    echo "  状态: systemctl status apk-proxy"
    echo "  重启: systemctl restart apk-proxy"
    echo "  日志: journalctl -u apk-proxy -f"
    echo ""
    log_info "💾 最新APK文件将保存在: $APK_DIR"
}

# 主函数
main() {
    log_info "开始安装APK代理下载服务..."
    log_info "服务器IP: $SERVER_IP"
    
    check_root
    check_system
    install_dependencies
    create_directories
    deploy_proxy_service
    create_systemd_service
    configure_firewall
    start_services
    verify_installation
}

main "$@"