#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import logging
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

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
        
        if parsed_path.path == '/xiazai':
            self.handle_download()
        elif parsed_path.path == '/':
            self.send_simple_response()
        else:
            self.send_error(404, "Not Found")
    
    def handle_download(self):
        """处理直接下载请求"""
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
            max-width: 600px;
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
            margin: 20px 0;
        }}
        .download-btn:hover {{
            background: #45a049;
        }}
        .info {{
            color: #666;
            margin: 10px 0;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>📱 APK下载</h1>
        <p class="info">最新版本: {latest_apk['name']}</p>
        <p class="info">文件大小: {latest_apk['size_mb']} MB</p>
        <p class="info">更新时间: {latest_apk['modified'][:19].replace('T', ' ')}</p>
        <a href="/xiazai" class="download-btn">立即下载</a>
        <p class="info">或直接访问: <code>http://45.130.146.21:8080/xiazai</code></p>
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
    
    def get_latest_apk(self):
        """获取最新的APK文件"""
        try:
            if not os.path.exists(self.apk_dir):
                return None
            
            apk_files = []
            for filename in os.listdir(self.apk_dir):
                if filename.endswith('.apk'):
                    filepath = os.path.join(self.apk_dir, filename)
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