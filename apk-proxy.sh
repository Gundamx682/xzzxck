#!/bin/bash

# APK代理服务控制脚本

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

case "${1:-status}" in
    "start")
        log_info "启动APK代理服务..."
        systemctl start apk-proxy
        log_info "服务已启动"
        ;;
    "stop")
        log_info "停止APK代理服务..."
        systemctl stop apk-proxy
        log_info "服务已停止"
        ;;
    "restart")
        log_info "重启APK代理服务..."
        systemctl restart apk-proxy
        log_info "服务已重启"
        ;;
    "status")
        log_info "APK代理服务状态:"
        systemctl status apk-proxy
        ;;
    "logs")
        log_info "APK代理服务日志 (最近20行):"
        journalctl -u apk-proxy -n 20 --no-pager
        ;;
    "logs-follow")
        log_info "实时查看APK代理服务日志:"
        journalctl -u apk-proxy -f
        ;;
    "download-latest")
        log_info "手动下载最新APK..."
        /opt/apk-proxy/apk-proxy.sh
        ;;
    "help"|"-h"|"--help")
        echo "APK代理服务控制脚本"
        echo ""
        echo "用法: $0 [命令]"
        echo ""
        echo "命令:"
        echo "  start          启动服务"
        echo "  stop           停止服务"
        echo "  restart        重启服务"
        echo "  status         查看服务状态"
        echo "  logs           查看最近日志"
        echo "  logs-follow    实时查看日志"
        echo "  download-latest 手动下载最新APK"
        echo "  help           显示此帮助信息"
        ;;
    *)
        log_error "未知命令: $1"
        echo "使用 '$0 help' 查看帮助信息"
        exit 1
        ;;
esac