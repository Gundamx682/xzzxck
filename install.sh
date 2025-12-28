#!/bin/bash

# APK自动下载和代理服务一键安装脚本（带Token输入功能和多仓库交互式添加）
# 适用于CentOS 7/8/9 系统
# 服务器IP: 45.130.146.21
# 项目地址: https://github.com/Gundamx682/xzzxck

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置参数
INSTALL_DIR="/opt/apk-downloader"
PROXY_DIR="/opt/apk-proxy"
APK_DIR="/var/www/apk-downloads"
SERVICE_USER="root"
SERVER_IP="45.130.146.21"
SERVER_PORT="8080"

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

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请以root权限运行此脚本"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    log_step "检查系统版本..."
    
    if [ -f /etc/centos-release ]; then
        CENTOS_VERSION=$(cat /etc/centos-release | grep -oE '[0-9]+' | head -1)
        log_info "检测到CentOS $CENTOS_VERSION"
    elif [ -f /etc/redhat-release ]; then
        CENTOS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)
        log_info "检测到RHEL $CENTOS_VERSION"
    else
        log_error "此脚本仅支持CentOS/RHEL系统"
        exit 1
    fi
}

# 检查可用内存
check_memory() {
    log_step "检查系统内存..."
    
    AVAILABLE_MEMORY=$(free -m | awk 'NR==2{printf "%.0f", $7/1024}')
    log_info "可用内存: ${AVAILABLE_MEMORY}GB"
    
    if [ "$AVAILABLE_MEMORY" -lt 1 ]; then
        log_warn "可用内存较少，可能影响安装过程"
    fi
}

# 获取GitHub Token
get_github_token() {
    log_step "获取GitHub Token..."
    
    echo
    log_info "========================================="
    log_info "GitHub Token 配置"
    log_info "========================================="
    echo
    log_info "为了绕过GitHub API速率限制，请提供您的GitHub Personal Access Token"
    echo
    log_info "获取Token方法："
    log_info "1. 访问 https://github.com/settings/tokens"
    log_info "2. 点击 'Generate new token'"
    log_info "3. 选择 'Fine-grained personal access tokens' 或 'Classic personal access tokens'"
    log_info "4. 生成并复制Token"
    echo
    
    while true; do
        read -s -p "请输入您的GitHub Token: " GITHUB_TOKEN
        echo  # 换行
        
        if [ -z "$GITHUB_TOKEN" ]; then
            log_error "Token不能为空，请重新输入"
            continue
        fi
        
        # 验证Token是否有效
        log_info "验证Token..."
        if curl -s -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "https://api.github.com/user" | grep -q '"login"'; then
            log_info "✓ Token验证成功"
            break
        else
            log_error "✗ Token验证失败，请检查Token是否正确"
            continue
        fi
    done
    
    # 将Token存储为全局变量，供后续函数使用
    export GITHUB_TOKEN="$GITHUB_TOKEN"
}

# 安装系统依赖
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
    
    # 如果有缺失的工具，下载并执行no-yum-install.sh
    log_info "正在安装缺失的工具: ${missing[*]}"
    
    # 创建临时的no-yum-install.sh
    cat > /tmp/no-yum-install.sh << 'NOYUMEOF'
#!/bin/bash

# 无YUM依赖安装脚本
# 直接下载RPM包进行安装，避免yum内存问题

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

# 检测系统版本
detect_system() {
    if [ -f /etc/centos-release ]; then
        CENTOS_VERSION=$(cat /etc/centos-release | grep -oE '[0-9]+' | head -1)
        log_info "检测到CentOS $CENTOS_VERSION"
    elif [ -f /etc/redhat-release ]; then
        CENTOS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+' | head -1)
        log_info "检测到RHEL $CENTOS_VERSION"
    else
        log_error "不支持的系统"
        exit 1
    fi
    
    ARCH=$(uname -m)
    log_info "系统架构: $ARCH"
}

# 安装curl（如果不存在）
install_curl() {
    if command -v curl &> /dev/null; then
        log_info "✓ curl 已安装"
        return 0
    fi
    
    log_step "安装curl..."
    
    # CentOS 9
    if [ "$CENTOS_VERSION" = "9" ]; then
        rpm -Uvh --nodeps --force https://vault.centos.org/centos/9/BaseOS/x86_64/os/Packages/curl-7.76.1-19.el9.x86_64.rpm 2>/dev/null || {
            log_warn "无法直接安装curl，尝试使用dnf..."
            dnf install -y curl --setopt=install_weak_deps=False 2>/dev/null || log_error "curl安装失败"
        }
    # CentOS 8
    elif [ "$CENTOS_VERSION" = "8" ]; then
        rpm -Uvh --nodeps --force https://vault.centos.org/centos/8/BaseOS/x86_64/os/Packages/curl-7.61.1-22.el8.x86_64.rpm 2>/dev/null || {
            log_warn "无法直接安装curl，尝试使用dnf..."
            dnf install -y curl --setopt=install_weak_deps=False 2>/dev/null || log_error "curl安装失败"
        }
    # CentOS 7
    elif [ "$CENTOS_VERSION" = "7" ]; then
        rpm -Uvh --nodeps --force https://vault.centos.org/centos/7/os/x86_64/Packages/curl-7.29.0-59.el7.x86_64.rpm 2>/dev/null || {
            log_warn "无法直接安装curl，尝试使用yum..."
            yum install -y curl --setopt=install_weak_deps=False 2>/dev/null || log_error "curl安装失败"
        }
    fi
    
    if command -v curl &> /dev/null; then
        log_info "✓ curl 安装成功"
        return 0
    else
        log_error "curl安装失败"
        return 1
    fi
}

# 安装python3（如果不存在）
install_python3() {
    if command -v python3 &> /dev/null; then
        log_info "✓ python3 已安装"
        return 0
    fi
    
    log_step "安装python3..."
    
    # CentOS 9
    if [ "$CENTOS_VERSION" = "9" ]; then
        rpm -Uvh --nodeps --force https://vault.centos.org/centos/9/AppStream/x86_64/os/Packages/python3-3.9.16-1.el9.x86_64.rpm 2>/dev/null || {
            log_warn "无法直接安装python3，尝试使用dnf..."
            dnf install -y python3 --setopt=install_weak_deps=False 2>/dev/null || log_error "python3安装失败"
        }
    # CentOS 8
    elif [ "$CENTOS_VERSION" = "8" ]; then
        rpm -Uvh --nodeps --force https://vault.centos.org/centos/8/AppStream/x86_64/os/Packages/python3-3.6.8-48.el8.x86_64.rpm 2>/dev/null || {
            log_warn "无法直接安装python3，尝试使用dnf..."
            dnf install -y python3 --setopt=install_weak_deps=False 2>/dev/null || log_error "python3安装失败"
        }
    # CentOS 7
    elif [ "$CENTOS_VERSION" = "7" ]; then
        rpm -Uvh --nodeps --force https://vault.centos.org/centos/7/extras/x86_64/Packages/python3-3.6.8-18.el7.x86_64.rpm 2>/dev/null || {
            log_warn "无法直接安装python3，尝试使用yum..."
            yum install -y python3 --setopt=install_weak_deps=False 2>/dev/null || log_error "python3安装失败"
        }
    fi
    
    if command -v python3 &> /dev/null; then
        log_info "✓ python3 安装成功"
        return 0
    else
        log_error "python3安装失败"
        return 1
    fi
}

# 检查systemd（通常已内置）
check_systemd() {
    if command -v systemctl &> /dev/null; then
        log_info "✓ systemd 已安装"
        return 0
    else
        log_warn "systemctl 命令不可用，但通常应该内置在系统中"
        return 0
    fi
}

# 主函数
main() {
    log_info "开始无YUM依赖安装..."
    
    detect_system
    install_curl
    install_python3
    check_systemd
    
    log_info "✓ 无YUM依赖安装完成！"
    
    # 检查安装结果
    log_step "验证安装结果..."
    
    local tools=("curl" "python3" "systemctl")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_info "✓ $tool - 可用"
        else
            log_warn "○ $tool - 不可用"
        fi
    done
    
    log_info "现在可以继续主程序安装"
}

main "$@"
NOYUMEOF

    # 执行no-yum-install.sh
    bash /tmp/no-yum-install.sh
    
    # 验证安装
    local still_missing=()
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            still_missing+=("$tool")
        fi
    done
    
    if [ ${#still_missing[@]} -gt 0 ]; then
        log_warn "以下工具未安装: ${still_missing[*]}"
        log_info "继续安装，部分功能可能受限"
    fi
    
    log_info "✓ 依赖安装完成"
}

# 创建目录结构
create_directories() {
    log_step "创建目录结构..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$PROXY_DIR"
    mkdir -p "$APK_DIR"
    mkdir -p "/var/log"
    
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$PROXY_DIR"
    chmod 755 "$APK_DIR"
    
    log_info "目录结构创建完成"
}

# 部署脚本文件
deploy_scripts() {
    log_step "部署脚本文件..."
    
    # 创建多仓库下载脚本
    cat > "$INSTALL_DIR/apk-downloader.sh" << 'EOF'
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
EOF

    # 创建HTTP服务器脚本
    cat > "$INSTALL_DIR/apk-server.py" << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import logging
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
import json

class SimpleAPKHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        self.apk_dir = '/var/www/apk-downloads'
        super().__init__(*args, **kwargs)
    
    def log_message(self, format, *args):
        """自定义日志格式"""
        logging.info(f"{self.address_string()} - {format%args}")
    
    def do_GET(self):
        """处理GET请求"""
        parsed_path = urlparse(self.path)
        
        if parsed_path.path.startswith('/xiazai/'):
            # 下载特定仓库的最新APK
            repo_name = parsed_path.path.split('/')[-1]
            if repo_name:
                self.handle_repo_download(repo_name)
            else:
                self.handle_download()
        elif parsed_path.path == '/xiazai':
            self.handle_download()
        elif parsed_path.path == '/api/repos':
            self.handle_repos_list()
        elif parsed_path.path == '/':
            self.send_simple_response()
        else:
            self.send_error(404, "Not Found")
    
    def handle_download(self):
        """处理直接下载请求（默认仓库）"""
        try:
            # 获取最新的APK文件
            latest_apk = self.get_latest_apk()
            
            if not latest_apk:
                self.send_error(404, "No APK file available")
                return
            
            apk_path = os.path.join(self.apk_dir, latest_apk['name'])
            
            if not os.path.exists(apk_path):
                self.send_error(404, "APK file not found")
                return
            
            # 发送文件
            self.send_response(200)
            self.send_header('Content-Type', 'application/vnd.android.package-archive')
            self.send_header('Content-Disposition', f'attachment; filename="{latest_apk["name"]}"')
            self.send_header('Content-Length', str(latest_apk['size']))
            self.end_headers()
            
            with open(apk_path, 'rb') as f:
                self.wfile.write(f.read())
            
            logging.info(f"APK下载: {latest_apk['name']} ({latest_apk['size_mb']} MB)")
            
        except Exception as e:
            logging.error(f"下载处理错误: {e}")
            self.send_error(500, "Internal Server Error")
    
    def handle_repo_download(self, repo_name):
        """处理特定仓库的下载请求"""
        try:
            # 查找特定仓库目录下的最新APK
            repo_dir = os.path.join('/var/www/apk-downloads', repo_name)
            if not os.path.exists(repo_dir):
                # 如果仓库名不是目录，则在主目录中查找
                repo_dir = '/var/www/apk-downloads'
            
            latest_apk = self.get_latest_apk(repo_dir)
            
            if not latest_apk:
                self.send_error(404, "No APK file available")
                return
            
            apk_path = os.path.join(repo_dir, latest_apk['name'])
            
            if not os.path.exists(apk_path):
                self.send_error(404, "APK file not found")
                return
            
            # 发送文件
            self.send_response(200)
            self.send_header('Content-Type', 'application/vnd.android.package-archive')
            self.send_header('Content-Disposition', f'attachment; filename="{latest_apk["name"]}"')
            self.send_header('Content-Length', str(latest_apk['size']))
            self.end_headers()
            
            with open(apk_path, 'rb') as f:
                self.wfile.write(f.read())
            
            logging.info(f"仓库 {repo_name} APK下载: {latest_apk['name']} ({latest_apk['size_mb']} MB)")
            
        except Exception as e:
            logging.error(f"仓库 {repo_name} 下载处理错误: {e}")
            self.send_error(500, "Internal Server Error")
    
    def handle_repos_list(self):
        """处理仓库列表API请求"""
        try:
            repos_info = []
            
            # 扫描APK目录，查找所有仓库
            if os.path.exists('/var/www/apk-downloads'):
                for item in os.listdir('/var/www/apk-downloads'):
                    item_path = os.path.join('/var/www/apk-downloads', item)
                    if os.path.isdir(item_path):
                        # 检查该仓库目录下的APK文件
                        apk_files = []
                        for apk_file in os.listdir(item_path):
                            if apk_file.endswith('.apk'):
                                apk_path = os.path.join(item_path, apk_file)
                                stat = os.stat(apk_path)
                                apk_files.append({
                                    'name': apk_file,
                                    'size': stat.st_size,
                                    'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                                    'size_mb': round(stat.st_size / (1024 * 1024), 2)
                                })
                        
                        if apk_files:
                            apk_files.sort(key=lambda x: x['modified'], reverse=True)
                            repos_info.append({
                                'repo_name': item,
                                'latest_apk': apk_files[0],
                                'apk_count': len(apk_files)
                            })
            
            # 添加主目录的APK信息
            main_apk_files = []
            main_dir = '/var/www/apk-downloads'
            if os.path.exists(main_dir):
                for apk_file in os.listdir(main_dir):
                    if apk_file.endswith('.apk'):
                        apk_path = os.path.join(main_dir, apk_file)
                        if os.path.isfile(apk_path):  # 确保是文件，不是目录
                            stat = os.stat(apk_path)
                            main_apk_files.append({
                                'name': apk_file,
                                'size': stat.st_size,
                                'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                                'size_mb': round(stat.st_size / (1024 * 1024), 2)
                            })
            
            if main_apk_files:
                main_apk_files.sort(key=lambda x: x['modified'], reverse=True)
                repos_info.append({
                    'repo_name': 'main',
                    'latest_apk': main_apk_files[0],
                    'apk_count': len(main_apk_files)
                })
            
            # 发送JSON响应
            json_data = json.dumps(repos_info, indent=2, ensure_ascii=False)
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json; charset=utf-8')
            self.end_headers()
            self.wfile.write(json_data.encode('utf-8'))
            
        except Exception as e:
            logging.error(f"仓库列表API错误: {e}")
            self.send_error(500, "Internal Server Error")
    
    def send_simple_response(self):
        """发送简单响应"""
        try:
            latest_apk = self.get_latest_apk()
            
            if latest_apk:
                html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>APK下载</title>
    <style>
        body {{
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background-color: #f5f5f5;
        }}
        .container {{
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        .download-btn {{
            display: inline-block;
            background: #4CAF50;
            color: white;
            padding: 15px 30px;
            text-decoration: none;
            border-radius: 5px;
            font-size: 18px;
            margin: 10px 5px;
        }}
        .download-btn:hover {{
            background: #45a049;
        }}
        .info {{
            color: #666;
            margin: 10px 0;
        }}
        .repo-list {{
            text-align: left;
            margin: 20px 0;
            padding: 20px;
            background-color: #f9f9f9;
            border-radius: 5px;
        }}
        .repo-item {{
            margin: 10px 0;
            padding: 10px;
            background-color: white;
            border-radius: 3px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>📱 APK下载中心</h1>
        <p class="info">最新版本: {latest_apk['name']}</p>
        <p class="info">文件大小: {latest_apk['size_mb']} MB</p>
        <p class="info">更新时间: {latest_apk['modified'][:19].replace('T', ' ')}</p>
        <div>
            <a href="/xiazai" class="download-btn">下载最新APK</a>
        </div>
        <p class="info">或直接访问: <code>http://45.130.146.21:8080/xiazai</code></p>
        
        <div class="repo-list">
            <h3>📊 监控仓库列表</h3>
            <div class="repo-item">
                <strong>z0brk/netamade-releases</strong> - 
                <a href="/xiazai/netamade" class="download-btn">下载此仓库最新版</a>
            </div>
            <p class="info">API接口: <a href="/api/repos">/api/repos</a> - 获取所有仓库的APK信息</p>
        </div>
    </div>
</body>
</html>"""
            else:
                html_content = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>APK下载</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            text-align: center;
            padding: 50px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>📱 APK下载</h1>
        <p>暂无APK文件，系统正在同步中...</p>
        <p>请稍后再试</p>
    </div>
</body>
</html>"""
            
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(html_content.encode('utf-8'))
            
        except Exception as e:
            logging.error(f"响应生成错误: {e}")
            self.send_error(500, "Internal Server Error")
    
    def get_latest_apk(self, directory=None):
        """获取最新的APK文件"""
        if directory is None:
            directory = self.apk_dir
            
        try:
            if not os.path.exists(directory):
                return None
            
            apk_files = []
            for filename in os.listdir(directory):
                if filename.endswith('.apk'):
                    filepath = os.path.join(directory, filename)
                    if os.path.isfile(filepath):  # 确保是文件，不是目录
                        stat = os.stat(filepath)
                        
                        apk_files.append({
                            'name': filename,
                            'size': stat.st_size,
                            'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                            'size_mb': round(stat.st_size / (1024 * 1024), 2)
                        })
            
            if not apk_files:
                return None
            
            # 按修改时间排序，返回最新的
            apk_files.sort(key=lambda x: x['modified'], reverse=True)
            return apk_files[0]
            
        except Exception as e:
            logging.error(f"获取APK文件错误: {e}")
            return None

def setup_logging():
    """设置日志"""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('/var/log/apk-server.log'),
            logging.StreamHandler(sys.stdout)
        ]
    )

def main():
    """主函数"""
    # 设置日志
    setup_logging()
    
    # 确保APK目录存在
    apk_dir = '/var/www/apk-downloads'
    os.makedirs(apk_dir, exist_ok=True)
    
    # 服务器配置
    server_address = ('0.0.0.0', 8080)
    httpd = HTTPServer(server_address, SimpleAPKHandler)
    
    logging.info(f"APK下载服务器启动")
    logging.info(f"直接下载地址: http://45.130.146.21:8080/xiazai")
    logging.info(f"仓库下载: http://45.130.146.21:8080/xiazai/[仓库名]")
    logging.info(f"API接口: http://45.130.146.21:8080/api/repos")
    logging.info(f"主页地址: http://45.130.146.21:8080")
    logging.info(f"APK目录: {apk_dir}")
    logging.info("按 Ctrl+C 停止服务器")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logging.info("正在停止服务器...")
        httpd.server_close()
        logging.info("服务器已停止")

if __name__ == '__main__':
    main()
EOF

    # 创建初始配置文件
    cat > "$INSTALL_DIR/config.json" << 'EOF'
{
  "repositories": [],
  "server": {
    "port": 8080,
    "bind_address": "0.0.0.0"
  },
  "download": {
    "max_concurrent": 3,
    "retry_count": 3,
    "timeout": 300
  },
  "api": {
    "rate_limit_delay": 2
  }
}
EOF

    # 设置执行权限
    chmod +x "$INSTALL_DIR/apk-downloader.sh"
    chmod +x "$INSTALL_DIR/apk-server.py"
    
    # 将Token保存到系统环境
    echo "export GITHUB_TOKEN=\"${GITHUB_TOKEN}\"" >> /etc/profile
    
    log_info "脚本文件部署完成"
}

# 交互式添加仓库
add_repositories() {
    log_step "配置监控仓库..."
    
    log_info "开始添加监控仓库..."
    log_info "请输入格式: 用户名/仓库名 (例如: z0brk/netamade-releases)"
    
    # 如果没有仓库，添加默认仓库
    repo_count=$(python3 -c "
import json
config_file = '$INSTALL_DIR/config.json'
with open(config_file, 'r', encoding='utf-8') as f:
    config = json.load(f)
print(len(config['repositories']))
" 2>/dev/null || echo "0")
    
    if [ "$repo_count" -eq 0 ]; then
        log_info "添加默认仓库 z0brk/netamade-releases"
        python3 -c "
import json
config_file = '$INSTALL_DIR/config.json'
with open(config_file, 'r', encoding='utf-8') as f:
    config = json.load(f)

config['repositories'].append({
    'name': 'netamade-releases',
    'owner': 'z0brk',
    'enabled': True,
    'check_interval': 600,
    'download_dir': '/var/www/apk-downloads'
})

with open(config_file, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
"
    fi
    
    while true; do
        echo
        read -p "是否添加更多仓库? [Y/n] (默认Y): " continue_add
        case $continue_add in
            [Nn]* ) 
                log_info "仓库配置完成"
                return 0
                ;;
            [Yy]* | "" )
                # 继续添加仓库
                ;;
            * ) 
                log_warn "请输入 y (是) 或 n (否)"
                continue
                ;;
        esac
        
        echo
        read -p "请输入仓库地址 (格式: 用户名/仓库名): " repo_input
        
        if [ -z "$repo_input" ]; then
            log_warn "仓库地址不能为空，请重新输入"
            continue
        fi
        
        # 解析用户输入
        if [[ "$repo_input" =~ ^([^/]+)/(.+)$ ]]; then
            repo_owner="${BASH_REMATCH[1]}"
            repo_name="${BASH_REMATCH[2]}"
        else
            log_error "仓库地址格式错误，请使用 格式: 用户名/仓库名"
            continue
        fi
        
        # 验证仓库是否存在
        log_info "验证仓库: $repo_owner/$repo_name"
        if curl -s -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" "https://api.github.com/repos/$repo_owner/$repo_name" | grep -q "full_name"; then
            log_info "✓ 仓库验证成功: $repo_owner/$repo_name"
        else
            log_error "✗ 仓库不存在或无法访问: $repo_owner/$repo_name"
            log_warn "请确认仓库名正确且您有访问权限"
            continue
        fi
        
        # 检查仓库是否已存在
        repo_exists=$(python3 -c "
import json
config_file = '$INSTALL_DIR/config.json'
with open(config_file, 'r', encoding='utf-8') as f:
    config = json.load(f)
for repo in config['repositories']:
    if repo['owner'] == '$repo_owner' and repo['name'] == '$repo_name':
        print('true')
        exit(0)
print('false')
" 2>/dev/null || echo "false")
        
        if [ "$repo_exists" = "true" ]; then
            log_warn "仓库 $repo_owner/$repo_name 已存在，跳过添加"
            continue
        fi
        
        # 添加到配置文件
        python3 -c "
import json
config_file = '$INSTALL_DIR/config.json'
with open(config_file, 'r', encoding='utf-8') as f:
    config = json.load(f)

config['repositories'].append({
    'name': '$repo_name',
    'owner': '$repo_owner',
    'enabled': True,
    'check_interval': 600,
    'download_dir': f'/var/www/apk-downloads/$repo_name'
})

with open(config_file, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print('仓库已添加到配置文件')
"
        
        log_info "仓库 $repo_owner/$repo_name 已添加"
    done
}

# 配置防火墙
configure_firewall() {
    log_step "配置防火墙..."
    
    if command -v firewall-cmd &> /dev/null; then
        # 启用firewalld
        systemctl enable firewalld 2>/dev/null || true
        systemctl start firewalld 2>/dev/null || true
        
        # 开放必要端口
        firewall-cmd --permanent --add-port=8080/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        
        log_info "防火墙配置完成"
    else
        log_warn "firewalld未安装，跳过防火墙配置"
    fi
}

# 设置systemd服务
setup_services() {
    log_step "设置systemd服务..."
    
    # 创建下载服务配置
    cat > /etc/systemd/system/apk-downloader.service << EOF
[Unit]
Description=APK Auto Downloader Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/opt/apk-downloader/apk-downloader.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=apk-downloader

[Install]
WantedBy=multi-user.target
EOF

    # 创建HTTP服务配置
    cat > /etc/systemd/system/apk-server.service << EOF
[Unit]
Description=APK Download HTTP Server
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 /opt/apk-downloader/apk-server.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=apk-server

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载systemd配置
    systemctl daemon-reload
    
    log_info "systemd服务配置完成"
}

# 启动服务
start_services() {
    log_step "启动服务..."
    
    # 启用服务
    systemctl enable apk-downloader 2>/dev/null || true
    systemctl enable apk-server 2>/dev/null || true
    
    # 启动服务
    systemctl start apk-downloader 2>/dev/null || true
    systemctl start apk-server 2>/dev/null || true
    
    sleep 3
    
    # 检查服务状态
    if systemctl is-active --quiet apk-downloader; then
        log_info "✓ APK下载服务启动成功"
    else
        log_warn "⚠ APK下载服务可能未启动"
    fi
    
    if systemctl is-active --quiet apk-server; then
        log_info "✓ APK HTTP服务启动成功"
    else
        log_warn "⚠ APK HTTP服务可能未启动"
    fi
}

# 验证安装
verify_installation() {
    log_step "验证安装..."
    
    echo ""
    log_info "🎉 安装完成！"
    echo "========================================="
    log_info "🎯 服务信息"
    echo "========================================="
    log_info "🌐 访问地址: http://$SERVER_IP:$SERVER_PORT"
    log_info "🔄 直接下载: http://$SERVER_IP:$SERVER_PORT/xiazai"
    log_info "📊 仓库列表: http://$SERVER_IP:$SERVER_PORT/api/repos"
    log_info "📱 仓库下载: http://$SERVER_IP:$SERVER_PORT/xiazai/[仓库名]"
    echo ""
    log_info "🔧 管理命令:"
    echo "   查看状态: systemctl status apk-downloader apk-server"
    echo "   重启服务: systemctl restart apk-downloader apk-server"
    echo "   查看日志: journalctl -u apk-downloader -f"
    echo "   查看日志: journalctl -u apk-server -f"
    echo ""
    log_info "🎯 监控仓库: https://github.com/z0brk/netamade-releases"
    log_info "📦 新项目地址: https://github.com/Gundamx682/xzzxck"
    echo ""
    log_info "✅ GitHub Token已配置，API速率限制问题已解决"
}

# 主函数
main() {
    log_info "开始安装APK自动下载服务..."
    log_info "服务器IP: $SERVER_IP"
    log_info "项目地址: https://github.com/Gundamx682/xzzxck"
    
    check_root
    check_system
    check_memory
    get_github_token
    install_dependencies
    create_directories
    deploy_scripts
    add_repositories
    configure_firewall
    setup_services
    start_services
    verify_installation
}

# 执行主函数
main "$@"
