# APK自动下载服务

一个用于自动监控GitHub仓库最新release并提供HTTP下载服务的CentOS系统服务。

## 功能特性

- **自动监控** - 每10分钟检查指定GitHub仓库的最新release
- **APK下载** - 自动识别并下载APK文件，删除旧版本
- **HTTP服务** - 提供Web界面和API接口
- **多仓库支持** - 可同时监控多个GitHub仓库
- **Token认证** - 绕过GitHub API速率限制
- **系统服务** - 以systemd服务运行，支持自启动

## 安装方法



### 手动安装

```bash
# 下载安装脚本
curl -fsSL https://raw.githubusercontent.com/Gundamx682/xzzxck/main/install.sh -o install.sh

# 运行安装脚本
sudo bash install.sh
```

## 安装过程

1. **系统检测** - 自动检测CentOS版本和可用内存
2. **Token配置** - 提示输入GitHub Personal Access Token
3. **依赖安装** - 安装必需的系统工具
4. **仓库配置** - 交互式添加需要监控的GitHub仓库
5. **服务配置** - 配置systemd服务和防火墙

## 使用说明

### 访问服务

- **主页**: http://45.130.146.21:8080
- **直接下载**: http://45.130.146.21:8080/xiazai
- **仓库下载**: http://45.130.146.21:8080/xiazai/[仓库名]
- **API接口**: http://45.130.146.21:8080/api/repos

### 管理命令

```bash
# 查看服务状态
systemctl status apk-downloader apk-server

# 重启服务
systemctl restart apk-downloader apk-server

# 查看服务日志
journalctl -u apk-downloader -f
journalctl -u apk-server -f

# 停止服务
systemctl stop apk-downloader apk-server

# 禁用服务（开机不自启）
systemctl disable apk-downloader apk-server
```

### 配置文件

配置文件位于: `/opt/apk-downloader/config.json`

可手动编辑以添加或删除监控仓库。

## 项目信息

- **项目地址**: https://github.com/Gundamx682/xzzxck
- **原监控仓库**: https://github.com/z0brk/netamade-releases

## 常见问题

### GitHub API速率限制

安装过程中需要提供GitHub Personal Access Token来绕过API速率限制。

### 内存不足

如果系统内存小于1GB，可能会在安装过程中遇到问题。

### 端口冲突

默认使用8080端口，如果该端口被占用，请先释放端口或修改配置文件。

## 故障排除

### 服务未启动

```bash
# 检查服务状态
systemctl status apk-downloader apk-server

# 检查日志
journalctl -u apk-downloader
journalctl -u apk-server
```

### 无法下载APK

- 检查GitHub Token是否有效
- 确认目标仓库存在且有APK文件
- 检查网络连接是否正常

### 防火墙问题

```bash
# 检查防火墙状态
systemctl status firewalld
firewall-cmd --list-ports
```

## 许可证

MIT License
