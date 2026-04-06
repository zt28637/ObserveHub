#!/bin/bash
###############################################################################
# 脚本: install-docker-openeuler.sh
# 修复: 解决 docker-ce-rootless-extras 依赖冲突，支持 openEuler 离线安装
###############################################################################

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# --- 1. 系统检测 ---
check_system() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法识别操作系统"
    fi

    . /etc/os-release
    OS_ID=$ID
    OS_VERSION=$VERSION_ID
    
    log_info "检测到系统: $OS_ID $OS_VERSION"
    
    if [[ "$OS_ID" != "openEuler" ]]; then
        log_warn "本脚本为 openEuler 优化，但也可用于其他系统"
    fi
}

# --- 2. 清理旧环境 ---
cleanup_old() {
    log_step "清理旧版本 Docker..."
    yum remove -y docker docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate docker-engine \
        docker-ce docker-ce-cli containerd.io docker-compose-plugin \
        docker-buildx-plugin docker-ce-rootless-extras 2>/dev/null || true
    
    rm -rf /var/lib/docker
    rm -f /usr/bin/docker-compose /usr/local/bin/docker-compose
    log_info "旧环境清理完成"
}

# --- 3. 【核心修复】完整的 RPM 列表安装 ---
install_docker_complete() {
    log_step "安装 Docker CE 26.x（完整依赖版）..."
    
    # 设置超长超时
    echo "timeout=600" >> /etc/yum.conf
    echo "retries=10" >> /etc/yum.conf
    
    TEMP_DIR=$(mktemp -d)
    cd $TEMP_DIR
    
    # 完整的 RPM 包列表（按依赖顺序）
    PACKAGES=(
        "containerd.io-1.6.31-3.1.el7.x86_64.rpm"
        "docker-ce-cli-26.1.4-1.el7.x86_64.rpm"
        "docker-ce-rootless-extras-26.1.4-1.el7.x86_64.rpm"
        "docker-ce-26.1.4-1.el7.x86_64.rpm"
        "docker-buildx-plugin-0.14.0-1.el7.x86_64.rpm"
        "docker-compose-plugin-2.27.0-1.el7.x86_64.rpm"
    )
    
    BASE_URL="https://mirrors.aliyun.com/docker-ce/linux/centos/7/x86_64/stable/Packages"
    
    log_info "开始下载 Docker 26.1.4 及完整依赖..."
    FAILED_PKGS=""
    
    for pkg in "${PACKAGES[@]}"; do
        log_info "下载: $pkg"
        if curl -fsSL --connect-timeout 120 --max-time 600 --retry 3 \
            "$BASE_URL/$pkg" -o "$pkg" 2>/dev/null; then
            log_info "✓ $pkg 成功"
        else
            log_warn "✗ $pkg 下载失败"
            FAILED_PKGS="$FAILED_PKGS $pkg"
        fi
    done
    
    # 如果网络下载失败，检查预下载的离线包
    if [[ -n "$FAILED_PKGS" ]]; then
        if [[ -d "/root/docker-rpms" && $(ls /root/docker-rpms/*.rpm 2>/dev/null | wc -l) -ge 4 ]]; then
            log_info "使用预下载的离线包 (/root/docker-rpms/)..."
            cp /root/docker-rpms/*.rpm $TEMP_DIR/ 2>/dev/null || true
        else
            log_warn "部分包下载失败，尝试用 --nobest 模式安装可用版本..."
        fi
    fi
    
    # 安装策略（优先完整安装，失败则用 --nobest）
    cd $TEMP_DIR
    
    log_step "安装 RPM 包..."
    if ls *.rpm 1>/dev/null 2>&1; then
        # 尝试完整安装
        if yum localinstall -y *.rpm 2>/dev/null; then
            log_info "✓ 完整安装成功"
        else
            log_warn "完整安装失败，尝试 --nobest 模式（自动解决依赖）..."
            yum localinstall -y --nobest *.rpm || {
                log_warn "--nobest 也失败，尝试 --skip-broken..."
                yum localinstall -y --skip-broken *.rpm || log_error "安装失败，请检查系统兼容性"
            }
        fi
    else
        log_error "没有找到 RPM 包，请检查网络或预下载目录"
    fi
    
    # 验证安装
    if command -v docker &> /dev/null; then
        INSTALLED_VER=$(docker --version | awk '{print $3}' | tr -d ',')
        log_info "✓ Docker 安装成功: $INSTALLED_VER"
    else
        log_error "Docker 命令未找到，安装可能失败"
    fi
    
    # 清理
    cd /
    rm -rf $TEMP_DIR
}

# --- 4. 配置与启动 ---
configure_and_start() {
    log_step "配置 Docker 守护进程..."
    
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'CONFIG'
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
CONFIG
    
    log_step "启动 Docker 服务..."
    systemctl daemon-reload
    
    if systemctl restart docker 2>/dev/null; then
        systemctl enable docker
        log_info "✓ Docker 服务启动成功"
    else
        log_error "Docker 服务启动失败，请检查日志: journalctl -xe | grep docker"
    fi
}

# --- 5. 验证 ---
verify() {
    log_step "验证安装结果..."
    
    echo -e "\n${BLUE}=== Docker 版本信息 ===${NC}"
    docker --version || log_error "docker 命令不可用"
    
    echo -e "\n${BLUE}=== Docker Compose 版本 ===${NC}"
    docker compose version || log_warn "docker compose 插件可能未安装"
    
    echo -e "\n${BLUE}=== 服务状态 ===${NC}"
    systemctl is-active docker && log_info "服务运行正常" || log_warn "服务未运行"
    
    echo -e "\n${GREEN}✅ 安装流程完成！${NC}"
    echo -e "${YELLOW}提示：如果版本不是 26.1.4，可能是仓库最新版，功能正常即可使用。${NC}"
    echo -e "${YELLOW}查看日志: journalctl -u docker -n 50${NC}"
}

# --- 主流程 ---
main() {
    check_system
    cleanup_old
    install_docker_complete
    configure_and_start
    verify
}

main