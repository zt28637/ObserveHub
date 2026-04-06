#!/bin/bash

# 服务器初始化脚本 - 云原生可观测平台运维全流程
# 基于项目流程文档：服务器初始化（关键！）章节

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置参数
LOG_FILE="/var/log/server-init.log"
BACKUP_DIR="/backup"
INIT_STATUS_FILE="/var/log/server-init.status"
CHECKPOINT_DIR="/var/log/server-init/checkpoints"
SSH_PORT="22"

# 阶段定义
PHASE_PRECHECK="precheck"
PHASE_USER="user_config"
PHASE_UPDATE="system_update"
PHASE_FIREWALL="firewall_config"
PHASE_SELINUX="selinux_config"
PHASE_TIME="time_sync"
PHASE_AUDIT="audit_config"

# 创建检查点目录
mkdir -p "$CHECKPOINT_DIR"

# 初始化日志文件
echo "$(date '+%Y-%m-%d %H:%M:%S') - 服务器初始化开始" > "$LOG_FILE"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1" >> "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$LOG_FILE"
}

# 阶段开始函数
start_phase() {
    local phase_name="$1"
    local phase_desc="$2"
    
    log_info "=========================================="
    log_info "阶段开始: $phase_desc"
    log_info "=========================================="
    
    # 记录阶段开始状态
    echo "PHASE=$phase_name" > "$INIT_STATUS_FILE"
    echo "STATUS=in_progress" >> "$INIT_STATUS_FILE"
    echo "START_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$INIT_STATUS_FILE"
}

# 阶段完成函数
complete_phase() {
    local phase_name="$1"
    local phase_desc="$2"
    
    log_success "=========================================="
    log_success "阶段完成: $phase_desc"
    log_success "=========================================="
    
    # 更新阶段状态
    sed -i 's/STATUS=in_progress/STATUS=completed/' "$INIT_STATUS_FILE"
    echo "END_TIME=$(date '+%Y-%m-%d %H:%M:%S')" >> "$INIT_STATUS_FILE"
}

# 阶段失败函数
fail_phase() {
    local phase_name="$1"
    local phase_desc="$2"
    local error_msg="$3"
    
    log_error "=========================================="
    log_error "阶段失败: $phase_desc"
    log_error "错误信息: $error_msg"
    log_error "=========================================="
    
    # 自动回滚
    rollback "$phase_name"
    
    # 更新阶段状态
    sed -i 's/STATUS=in_progress/STATUS=failed/' "$INIT_STATUS_FILE"
    echo "ERROR_MSG=$error_msg" >> "$INIT_STATUS_FILE"
    
    exit 1
}

# 检查点函数
checkpoint() {
    local check_name="$1"
    local check_command="$2"
    local success_msg="$3"
    local fail_msg="$4"
    local flag_file="$CHECKPOINT_DIR/${check_name// /_}.flag"
    
    log_info "检查点: $check_name"
    
    # 检查是否已经完成（支持分阶段重跑）
    if [ -f "$flag_file" ]; then
        log_info "检查点已完成，跳过"
        return 0
    fi
    
    # 使用子shell执行命令，避免set -e导致脚本退出
    if ( eval "$check_command" ); then
        log_success "$success_msg"
        # 创建标记文件
        touch "$flag_file"
        return 0
    else
        log_error "$fail_msg"
        return 1
    fi
}

# 回滚函数
rollback() {
    local phase_name="$1"
    log_warning "开始回滚阶段: $phase_name"
    
    case "$phase_name" in
        "$PHASE_USER")
            # 回滚SSH配置
            if [ -f "/etc/ssh/sshd_config.bak" ]; then
                log_info "回滚SSH配置..."
                cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
                systemctl reload sshd
                log_success "SSH配置已回滚"
            fi
            ;;
        "$PHASE_FIREWALL")
            # 回滚防火墙配置
            log_info "回滚防火墙配置..."
            firewall-cmd --permanent --remove-port=$CURRENT_SSH_PORT/tcp
            firewall-cmd --permanent --remove-port=9090/tcp
            firewall-cmd --permanent --remove-port=3000/tcp
            firewall-cmd --permanent --remove-port=3100/tcp
            firewall-cmd --reload
            log_success "防火墙配置已回滚"
            ;;
        *)
            log_warning "该阶段无回滚操作"
            ;;
    esac
}

# 阶段1: 预检
start_phase "$PHASE_PRECHECK" "服务器预检"

# 检查基线报告
checkpoint "基线报告检查" \
    "find ~ -name 'baseline_*.log' -type f 2>/dev/null | grep -q baseline" \
    "基线报告已找到" \
    "基线报告未找到，请先运行 baseline.sh"

# 检查网络连接
checkpoint "网络连接检查" \
    "ping -c 2 www.baidu.com >/dev/null" \
    "网络连接正常" \
    "网络连接失败"

# 检查内存
checkpoint "内存检查" \
    "free -g | awk 'NR==2 {exit (\$2 < 2 ? 1 : 0)}'" \
    "内存达标 (≥2GB)" \
    "内存不足 (需要≥2GB)"

# 检查磁盘空间
checkpoint "磁盘空间检查" \
    "df -BG / | awk 'NR==2 {gsub(\"G\", \"\", \$4); exit (\$4 < 20 ? 1 : 0)}'" \
    "磁盘空间达标 (≥20GB)" \
    "磁盘空间不足 (需要≥20GB)"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 备份系统配置
checkpoint "系统配置备份" \
    "tar -czf \"$BACKUP_DIR/sys-$(date +%Y%m%d).tar.gz\" /etc /var/spool/cron 2>/dev/null" \
    "系统配置已备份" \
    "系统配置备份失败"

complete_phase "$PHASE_PRECHECK" "服务器预检"

# 阶段2: 用户配置
start_phase "$PHASE_USER" "用户配置初始化"

# 创建opsadmin用户（如果不存在）
checkpoint "创建opsadmin用户" \
    "id opsadmin >/dev/null 2>&1 || useradd -m -s /bin/bash opsadmin" \
    "opsadmin用户已创建或已存在" \
    "opsadmin用户创建失败"

# 配置免密sudo
checkpoint "配置免密sudo" \
    "echo 'opsadmin ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/opsadmin && chmod 440 /etc/sudoers.d/opsadmin" \
    "免密sudo已配置" \
    "免密sudo配置失败"

# 上传SSH公钥
log_info "上传用户公钥到opsadmin用户目录"
mkdir -p /home/opsadmin/.ssh

PUB_KEY="${1:-}" 
if [ -z "$PUB_KEY" ]; then 
    read -p "请粘贴你的SSH公钥: "  PUB_KEY 
fi 

checkpoint "配置SSH公钥" \
    "echo \"$PUB_KEY\" >> /home/opsadmin/.ssh/authorized_keys && chmod 700 /home/opsadmin/.ssh && chmod 600 /home/opsadmin/.ssh/authorized_keys" \
    "SSH公钥已配置" \
    "SSH公钥配置失败"

# 注意：为了安全，不修改SSH配置文件，避免影响现有连接
log_info "保持原有SSH配置不变，确保连接安全"

# 获取当前SSH端口
CURRENT_SSH_PORT=$(grep -E '^#?Port' /etc/ssh/sshd_config | awk '{print $2}' || echo "22")

# 交互式验证
log_warning "关键验证：请立即新开终端测试: ssh -p $CURRENT_SSH_PORT opsadmin@$(hostname -I | awk '{print $1}')"
read -p "新终端能登录吗？(y/n) " confirm

if [ "$confirm" != "y" ]; then
    fail_phase "$PHASE_USER" "用户配置初始化" "SSH登录验证失败"
fi

log_success "SSH登录验证成功"
complete_phase "$PHASE_USER" "用户配置初始化"

# 阶段3: 系统更新
start_phase "$PHASE_UPDATE" "系统更新"

checkpoint "系统更新" \
    "dnf upgrade -y" \
    "系统更新完成" \
    "系统更新失败"

checkpoint "清理系统缓存" \
    "dnf clean all" \
    "系统缓存已清理" \
    "系统缓存清理失败"

complete_phase "$PHASE_UPDATE" "系统更新"

# 阶段4: 防火墙配置
start_phase "$PHASE_FIREWALL" "防火墙配置"

# 添加防火墙规则
checkpoint "添加SSH端口" \
    "firewall-cmd --permanent --add-port=$CURRENT_SSH_PORT/tcp" \
    "SSH端口$CURRENT_SSH_PORT已添加" \
    "SSH端口添加失败"

checkpoint "添加Prometheus端口" \
    "firewall-cmd --permanent --add-port=9090/tcp" \
    "Prometheus端口已添加" \
    "Prometheus端口添加失败"

checkpoint "添加Grafana端口" \
    "firewall-cmd --permanent --add-port=3000/tcp" \
    "Grafana端口已添加" \
    "Grafana端口添加失败"

checkpoint "添加Loki端口" \
    "firewall-cmd --permanent --add-port=3100/tcp" \
    "Loki端口已添加" \
    "Loki端口添加失败"

checkpoint "重新加载防火墙" \
    "firewall-cmd --reload" \
    "防火墙已重新加载" \
    "防火墙重新加载失败"

complete_phase "$PHASE_FIREWALL" "防火墙配置"

# 阶段5: SELinux配置
start_phase "$PHASE_SELINUX" "SELinux配置"

checkpoint "临时禁用SELinux" \
    "setenforce 0" \
    "SELinux已临时禁用" \
    "SELinux临时禁用失败"

checkpoint "永久配置SELinux" \
    "sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config" \
    "SELinux已配置为permissive模式" \
    "SELinux配置失败"

complete_phase "$PHASE_SELINUX" "SELinux配置"

# 阶段6: 时间同步
start_phase "$PHASE_TIME" "时间同步配置"

checkpoint "安装chrony" \
    "dnf install -y chrony" \
    "chrony已安装" \
    "chrony安装失败"

checkpoint "启用chrony服务" \
    "systemctl enable --now chronyd" \
    "chrony服务已启用" \
    "chrony服务启用失败"

complete_phase "$PHASE_TIME" "时间同步配置"

# 阶段7: 日志审计
start_phase "$PHASE_AUDIT" "日志审计配置"

checkpoint "安装audit" \
    "dnf install -y audit" \
    "auditd已安装" \
    "auditd安装失败"

checkpoint "启用auditd服务" \
    "systemctl enable --now auditd" \
    "auditd服务已启用" \
    "auditd服务启用失败"

# 配置审计规则
log_info "配置日志审计规则"
cat > /etc/audit/rules.d/monitor.rules <<EOF
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k priv_esc
EOF

checkpoint "重载auditd规则" \
    "auditctl -D >/dev/null 2>&1 && auditctl -R /etc/audit/rules.d/monitor.rules >/dev/null 2>&1" \
    "auditd规则已重新加载" \
    "auditd规则重新加载失败"

complete_phase "$PHASE_AUDIT" "日志审计配置"

# 完成初始化
log_info "=========================================="
log_success "服务器初始化全部完成！"
log_info "=========================================="
log_info "初始化日志: $LOG_FILE"
log_info "初始化状态: $INIT_STATUS_FILE"
log_success "服务器已准备就绪，可以进行后续部署操作"
