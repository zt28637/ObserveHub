# Docker安装配置文档

## 1. Docker安装配置

### 1.1 安装Docker Engine（推荐使用脚本安装）

使用提供的脚本 `install-docker-openeuler.sh` 进行安装，脚本特点：
- 支持openEuler系统
- 解决docker-ce-rootless-extras依赖冲突
- 支持离线安装模式
- 自动配置daemon.json

```bash
# 执行安装脚本
sudo bash install-docker-openeuler.sh

# 脚本执行流程：
# 1. 系统检测
# 2. 清理旧环境
# 3. 下载并安装Docker CE 26.x及完整依赖
# 4. 配置daemon.json
# 5. 启动Docker服务并验证
```

### 1.2 手动安装步骤

如果需要手动安装，可参考以下步骤：

```bash
# 卸载旧版本
sudo yum remove -y docker docker-client docker-client-latest docker-common \
    docker-latest docker-latest-logrotate docker-logrotate docker-engine \
    docker-ce docker-ce-cli containerd.io docker-compose-plugin \
    docker-buildx-plugin docker-ce-rootless-extras 2>/dev/null || true

# 创建临时目录
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# 下载Docker RPM包（按依赖顺序）
PACKAGES=(
    "containerd.io-1.6.31-3.1.el7.x86_64.rpm"
    "docker-ce-cli-26.1.4-1.el7.x86_64.rpm"
    "docker-ce-rootless-extras-26.1.4-1.el7.x86_64.rpm"
    "docker-ce-26.1.4-1.el7.x86_64.rpm"
    "docker-buildx-plugin-0.14.0-1.el7.x86_64.rpm"
    "docker-compose-plugin-2.27.0-1.el7.x86_64.rpm"
)

BASE_URL="https://mirrors.aliyun.com/docker-ce/linux/centos/7/x86_64/stable/Packages"

for pkg in "${PACKAGES[@]}"; do
    curl -fsSL "$BASE_URL/$pkg" -o "$pkg"
done

# 安装RPM包
sudo yum localinstall -y *.rpm

# 清理临时目录
cd /
rm -rf $TEMP_DIR
```

## 2. Docker守护进程配置

### 2.1 daemon.json配置文件

```json
{
  "registry-mirrors": [
    "https://wqzgelty.mirror.aliyuncs.com",
    "https://docker.m.daocloud.io",
    "https://huecker.io",
    "https://dockerhub.timeweb.cloud",
    "https://noohub.ru"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "exec-opts": ["native.cgroupdriver=systemd"],
  "storage-driver": "overlay2"
}
```

**配置说明**：
- `registry-mirrors`: 配置多个镜像源，加速镜像拉取
- `log-driver`: 使用json-file日志驱动
- `log-opts`: 限制日志大小为10MB，保留3个文件
- `exec-opts`: 设置cgroup驱动为systemd，提高容器性能
- `storage-driver`: 使用overlay2存储驱动，提高存储效率

### 2.2 应用配置

```bash
# 创建Docker配置目录
sudo mkdir -p /etc/docker

# 写入配置文件
sudo cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://05f073ad3c0010ea0f4bc00b7105ec20.mirror.swr.myhuaweicloud.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://m.daocloud.io"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "exec-opts": ["native.cgroupdriver=systemd"],
  "storage-driver": "overlay2"
}
EOF

# 重启Docker服务
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl enable docker

# 验证配置
docker info | grep -E "(Logging Driver|Storage Driver|Registry Mirrors)"
```

## 3. Docker用户配置

### 3.1 添加用户到docker组

```bash
# 将opsadmin用户添加到docker组
sudo usermod -aG docker opsadmin

# 验证用户组
groups opsadmin
```

### 3.2 权限验证

```bash
# 切换到opsadmin用户
su - opsadmin

# 验证Docker命令执行
docker info
```



## 5. Docker安全配置

### 5.1 启用Docker服务安全选项

```bash
# 修改Docker服务配置
sudo vi /usr/lib/systemd/system/docker.service

# 在ExecStart行添加安全选项
# ExecStart=/usr/bin/dockerd --containerd=/run/containerd/containerd.sock --tlsverify --tlscacert=/etc/docker/ca.pem --tlscert=/etc/docker/server.pem --tlskey=/etc/docker/server-key.pem -H tcp://0.0.0.0:2376 -H unix:///var/run/docker.sock

# 重新加载配置
sudo systemctl daemon-reload
sudo systemctl restart docker
```

### 5.2 SELinux配置

```bash
# 启用Docker SELinux策略
sudo setsebool -P docker_connect_any 1
```

## 6. Docker监控配置

### 6.1 启用Docker内置监控

```bash
# 在daemon.json中添加监控配置
sudo cat >> /etc/docker/daemon.json << 'EOF'
  ,
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
EOF

# 重启Docker服务
sudo systemctl restart docker
```

### 6.2 验证监控端口

```bash
# 检查监控端口是否监听
netstat -tlnp | grep 9323

# 测试监控API
curl http://localhost:9323/metrics
```

## 7. 环境验证

### 7.1 基础验证

```bash
# 验证Docker服务状态
sudo systemctl status docker

# 验证Docker版本
docker --version

# 验证Docker Compose版本
docker compose version

# 验证Docker配置
docker info | grep -E "(Logging Driver|Storage Driver|Registry Mirrors)"
```

### 7.2 功能验证

```bash
# 拉取测试镜像
docker pull nginx:latest

# 运行测试容器
docker run -d --name test-nginx -p 8080:80 nginx:latest

# 验证容器运行
docker ps

# 访问测试页面
curl http://localhost:8080

# 清理测试容器
docker stop test-nginx
docker rm test-nginx
```

## 8. 故障排除

### 8.1 常见问题

| 问题 | 可能原因 | 解决方案 |
|-----|---------|---------|
| Docker服务启动失败 | 配置文件错误 | 检查/etc/docker/daemon.json语法 |
| 镜像拉取失败 | 网络问题或镜像源配置错误 | 检查网络连接和registry-mirrors配置 |
| 权限不足 | 用户未加入docker组 | 将用户添加到docker组并重新登录 |
| 端口冲突 | 端口被占用 | 使用不同端口或停止占用端口的服务 |

### 8.2 日志查看

```bash
# 查看Docker服务日志
sudo journalctl -u docker -f

# 查看容器日志
docker logs <container_id>

# 查看Docker事件
docker events
```

## 9. 维护建议

### 9.1 定期维护

```bash
# 清理未使用的镜像
docker image prune -f

# 清理停止的容器
docker container prune -f

# 清理未使用的网络
docker network prune -f

# 清理未使用的数据卷
docker volume prune -f

# 清理所有未使用的资源
docker system prune -af
```

### 9.2 监控建议

- 监控Docker服务状态
- 监控容器运行状态
- 监控镜像存储使用情况
- 监控网络连接状态

## 10. 文档信息

- **版本**：1.0
- **创建日期**：2026-03-29
- **适用环境**：openEuler 22.03 (LTS-SP3)
- **Docker版本**：20.10+
- **Docker Compose版本**：2.24.6

---

**配置完成时间**：2026-03-29  
**配置人员**：Au  
**审核人员**：Au