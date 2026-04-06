#!/bin/bash

# ==============================================================
# 基线采集脚本 - 云原生可观测平台运维全流程
# 基于项目流程文档：资产与现状基线采集
#
# 功能：
# 1. 系统配置基线采集（主机名、OS版本、内核、架构）
# 2. 性能基线采集（CPU、内存、磁盘、网络）
# 3. 安全基线采集（系统安全配置）
# 4. 网络拓扑与带宽测试
# 5. 存储IO能力测试
# 6. 健康分计算与瓶颈识别
# ==============================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 告警阈值定义
CPU_WARN_THRESHOLD=80
MEM_WARN_THRESHOLD=80
DISK_WARN_THRESHOLD=80
IO_WARN_THRESHOLD=100  # IO延迟警告阈值（ms）

# 采集时间戳
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
# 采集目录
REPORT_DIR="../reports"
if [ ! -d "${REPORT_DIR}" ]; then
    mkdir -p "${REPORT_DIR}"
fi

# 主机名
HOSTNAME=$(hostname -f)
# 采集信息文件
REPORT_FILE="${REPORT_DIR}/baseline_${HOSTNAME}_${TIMESTAMP}.log"

echo -e "${BLUE}开始采集系统基线信息...${NC}"
echo -e "${BLUE}-----------------${NC}"
echo -e "${BLUE}采集时间: ${TIMESTAMP}${NC}"

# 健康分初始化
HEALTH_SCORE=100
BOTTLENECK_ITEMS=""

# ==============================================================
# 1. 系统配置基线采集
# ==============================================================
echo -e "\n${YELLOW}1. 系统配置基线采集${NC}"

# 系统版本
SYSTEM_VERSION=$(grep "^PRETTY_NAME" /etc/os-release | cut -d '"' -f2)
# 内核版本
KERNEL_VERSION=$(uname -r)
# 系统架构
SYSTEM_ARCH=$(uname -m)

{
    echo "-----------------"
    echo "【系统配置基线】"
    echo "主机名: ${HOSTNAME}"
    echo "系统版本: ${SYSTEM_VERSION}"
    echo "内核版本: ${KERNEL_VERSION}"
    echo "系统架构: ${SYSTEM_ARCH}"
    echo "-----------------"
} >> "${REPORT_FILE}"

# ==============================================================
# 2. CPU性能基线采集
# ==============================================================
echo -e "\n${YELLOW}2. CPU性能基线采集${NC}"

# 物理CPU数量
CPU_COUNT=$(grep "[p]hysical id" /proc/cpuinfo | sort | uniq | wc -l)
# 核心数
CORE_COUNT=$(grep "[c]pu cores" /proc/cpuinfo | head -1 | awk '{print $4}')
# 逻辑线程数
THREAD_COUNT=$(grep "[p]rocessor" /proc/cpuinfo | wc -l)
# CPU使用率（5秒采样）
if command -v mpstat &> /dev/null; then
    CPU_USAGE=$(mpstat 1 5 | awk '/Average:/ {print 100 - $12 "%"}')
else
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1 "%"}')
fi
CPU_USAGE_NUM=$(echo "$CPU_USAGE" | sed 's/%//')

# 告警判断
CPU_STATUS="正常"
if awk -v usage="$CPU_USAGE_NUM" -v threshold="$CPU_WARN_THRESHOLD" 'BEGIN { exit (usage > threshold ? 0 : 1) }'; then
    CPU_STATUS="【告警】"
    HEALTH_SCORE=$((HEALTH_SCORE - 10))
    BOTTLENECK_ITEMS="$BOTTLENECK_ITEMS CPU使用率过高"
fi

{
    echo "-----------------"
    echo "【CPU性能基线】"
    echo "物理CPU数: ${CPU_COUNT}"
    echo "核心数: ${CORE_COUNT}"
    echo "逻辑线程数: ${THREAD_COUNT}"
    echo "CPU使用率: ${CPU_USAGE} ${CPU_STATUS}"
    echo "-----------------"
} >> "${REPORT_FILE}"

# ==============================================================
# 3. 内存性能基线采集
# ==============================================================
echo -e "\n${YELLOW}3. 内存性能基线采集${NC}"

# 内存使用情况
MEM_TOTAL=$(free -h | grep "Mem" | awk '{print $2}')
MEM_USED=$(free -h | grep "Mem" | awk '{print $3}')
MEM_USAGE=$(free | grep "Mem" | awk '{print $3/$2*100 "%"}')
MEM_USAGE_NUM=$(echo "$MEM_USAGE" | sed 's/%//')

# 告警判断
MEM_STATUS="正常"
if awk -v usage="$MEM_USAGE_NUM" -v threshold="$MEM_WARN_THRESHOLD" 'BEGIN { exit (usage > threshold ? 0 : 1) }'; then
    MEM_STATUS="【告警】"
    HEALTH_SCORE=$((HEALTH_SCORE - 10))
    BOTTLENECK_ITEMS="$BOTTLENECK_ITEMS 内存使用率过高"
fi

{
    echo "-----------------"
    echo "【内存性能基线】"
    echo "内存使用率: ${MEM_USAGE} (${MEM_USED}/${MEM_TOTAL}) ${MEM_STATUS}"
    echo "-----------------"
} >> "${REPORT_FILE}"

# ==============================================================
# 4. 磁盘性能基线采集
# ==============================================================
echo -e "\n${YELLOW}4. 磁盘性能基线采集${NC}"

{
    echo "-----------------"
    echo "【磁盘性能基线】"
} >> "${REPORT_FILE}"

# 磁盘使用率
df -h | grep -v "[tmp]mpfs" | grep -v "devtmpfs" | while read -r line; do
    if [[ "$line" != Filesystem* ]]; then
        MOUNT=$(echo "$line" | awk '{print $6}')
        USAGE=$(echo "$line" | awk '{print $5}')
        SIZE=$(echo "$line" | awk '{print $2}')
        USED=$(echo "$line" | awk '{print $3}')
        
        USAGE_NUM=$(echo "$USAGE" | sed 's/%//')
        DISK_STATUS="正常"
        
        if awk -v usage="$USAGE_NUM" -v threshold="$DISK_WARN_THRESHOLD" 'BEGIN { exit (usage > threshold ? 0 : 1) }'; then
            DISK_STATUS="【告警】"
            HEALTH_SCORE=$((HEALTH_SCORE - 5))
            BOTTLENECK_ITEMS="$BOTTLENECK_ITEMS 磁盘$MOUNT使用率过高"
        fi
        
        echo "$MOUNT: ${USAGE} (${USED}/${SIZE}) ${DISK_STATUS}" >> "${REPORT_FILE}"
    fi
done

echo "-----------------" >> "${REPORT_FILE}"

# ==============================================================
# 5. 存储IO能力测试
# ==============================================================
echo -e "\n${YELLOW}5. 存储IO能力测试${NC}"

# 创建测试文件
TEST_FILE="/tmp/io_test_${TIMESTAMP}"
dd if=/dev/zero of="$TEST_FILE" bs=1M count=1024 conv=fdatasync 2>&1 | grep -E "(bytes|seconds)" > /tmp/io_result.txt

# 读取测试结果
IO_RESULT=$(cat /tmp/io_result.txt)
WRITE_SPEED=$(echo "$IO_RESULT" | awk '{print $1/1024 " MB/s"}')
WRITE_TIME=$(echo "$IO_RESULT" | awk '{print $10}')

# IO延迟测试
IO_LATENCY=$(dd if=/dev/zero of="$TEST_FILE" bs=4k count=1000 conv=fdatasync 2>&1 | awk '{print $10}')

# 清理测试文件
rm -f "$TEST_FILE" /tmp/io_result.txt

IO_STATUS="正常"
if awk -v latency="$IO_LATENCY" -v threshold="$IO_WARN_THRESHOLD" 'BEGIN { exit (latency > threshold ? 0 : 1) }'; then
    IO_STATUS="【告警】"
    HEALTH_SCORE=$((HEALTH_SCORE - 5))
    BOTTLENECK_ITEMS="$BOTTLENECK_ITEMS 存储IO延迟过高"
fi

{
    echo "-----------------"
    echo "【存储IO能力】"
    echo "写入速度: ${WRITE_SPEED}"
    echo "写入延迟: ${IO_LATENCY} ms ${IO_STATUS}"
    echo "-----------------"
} >> "${REPORT_FILE}"

# ==============================================================
# 6. 网络拓扑与带宽测试
# ==============================================================
echo -e "\n${YELLOW}6. 网络拓扑与带宽测试${NC}"

# 获取网络接口信息
{
    echo "-----------------"
    echo "【网络拓扑】"
    echo "网络接口信息:"
    ip addr show | grep -E "(inet|inet6|link/ether)" | grep -v "127.0.0.1"
    echo ""
    echo "路由表:"
    route -n
    echo "-----------------"
} >> "${REPORT_FILE}"

# 带宽测试（使用speedtest-cli或ping测试）
if command -v speedtest-cli &> /dev/null; then
    echo "带宽测试结果:" >> "${REPORT_FILE}"
    speedtest-cli --simple >> "${REPORT_FILE}"
else
    echo "带宽测试: 未安装speedtest-cli，使用ping测试网络连通性" >> "${REPORT_FILE}"
    ping -c 5 www.baidu.com >> "${REPORT_FILE}"
fi

echo "-----------------" >> "${REPORT_FILE}"

# ==============================================================
# 7. 安全基线采集
# ==============================================================
echo -e "\n${YELLOW}7. 安全基线采集${NC}"

{
    echo "-----------------"
    echo "【安全基线】"
    echo "SELinux状态: $(getenforce)"
    echo "防火墙状态: $(systemctl is-active firewalld)"
    echo "SSH配置:"
    grep -E '^#?PermitRootLogin|^#?PasswordAuthentication' /etc/ssh/sshd_config
    echo "系统用户数: $(awk -F: '$3 >= 1000 {print $1}' /etc/passwd | wc -l)"
    echo "定时任务数: $(crontab -l 2>/dev/null | wc -l)"
    echo "-----------------"
} >> "${REPORT_FILE}"

# ==============================================================
# 8. 健康分计算与瓶颈识别
# ==============================================================
echo -e "\n${YELLOW}8. 健康分计算与瓶颈识别${NC}"

# 健康分评级
if [ $HEALTH_SCORE -ge 90 ]; then
    HEALTH_LEVEL="优秀"
elif [ $HEALTH_SCORE -ge 70 ]; then
    HEALTH_LEVEL="良好"
elif [ $HEALTH_SCORE -ge 50 ]; then
    HEALTH_LEVEL="一般"
else
    HEALTH_LEVEL="较差"
fi

{
    echo "-----------------"
    echo "【系统健康评估】"
    echo "健康分数: ${HEALTH_SCORE}/100 (${HEALTH_LEVEL})"
    echo "系统瓶颈:"
    if [ -z "$BOTTLENECK_ITEMS" ]; then
        echo "无明显瓶颈"
    else
        echo "$BOTTLENECK_ITEMS"
    fi
    echo "-----------------"
} >> "${REPORT_FILE}"

# ==============================================================
# 9. 生成报告
# ==============================================================
echo -e "\n${GREEN}基线采集完成！${NC}"
echo -e "${GREEN}报告文件: ${REPORT_FILE}${NC}"
echo -e "${GREEN}系统健康分: ${HEALTH_SCORE}/100 (${HEALTH_LEVEL})${NC}"

if [ -n "$BOTTLENECK_ITEMS" ]; then
    echo -e "${YELLOW}系统瓶颈: ${BOTTLENECK_ITEMS}${NC}"
fi

echo -e "\n${BLUE}请查看报告文件获取详细信息${NC}"