#!/bin/bash

# 无YUM依赖安装脚本 - xzzxck项目版
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