#!/bin/bash
# ============================================
# 监控告警诊断脚本
# ============================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HOST_IP=$(hostname -I | awk '{print $1}')

echo "=========================================="
echo "🔍 监控告警链路诊断"
echo "=========================================="

# 检查函数
check_service() {
    local name=$1
    local url=$2
    echo -e "\n${BLUE}检查 $name...${NC}"
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200"; then
        echo -e "${GREEN}✓ $name 运行正常 ($url)${NC}"
        return 0
    else
        echo -e "${RED}✗ $name 无法访问 ($url)${NC}"
        return 1
    fi
}

# 1. 检查容器状态
echo -e "\n${YELLOW}[1/8] 检查容器状态...${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(prometheus|alertmanager|grafana|loki|cadvisor|node-exporter)" || true

# 2. 检查 Prometheus
echo -e "\n${YELLOW}[2/8] 检查 Prometheus 状态...${NC}"
check_service "Prometheus" "http://localhost:9090/-/healthy"

# 3. 检查 Alertmanager
echo -e "\n${YELLOW}[3/8] 检查 Alertmanager 状态...${NC}"
check_service "Alertmanager" "http://localhost:9093/-/healthy"

# 4. 检查 Prometheus 告警规则
echo -e "\n${YELLOW}[4/8] 检查 Prometheus 告警规则...${NC}"
ALERTS=$(curl -s http://localhost:9090/api/v1/rules | jq -r '.data.groups[].rules | length' 2>/dev/null | awk '{sum+=$1} END {print sum}')
if [ -n "$ALERTS" ] && [ "$ALERTS" -gt 0 ]; then
    echo -e "${GREEN}✓ Prometheus 配置了 $ALERTS 条告警规则${NC}"
else
    echo -e "${RED}✗ Prometheus 告警规则未加载或配置错误${NC}"
fi

# 5. 检查当前触发的告警
echo -e "\n${YELLOW}[5/8] 检查当前触发的告警...${NC}"
ACTIVE_ALERTS=$(curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts | length')
if [ "$ACTIVE_ALERTS" -gt 0 ]; then
    echo -e "${YELLOW}! 当前有 $ACTIVE_ALERTS 个活跃告警${NC}"
    curl -s http://localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | "  - \(.labels.alertname): \(.state)"' 2>/dev/null || true
else
    echo -e "${GREEN}✓ 当前没有活跃告警${NC}"
fi

# 6. 检查 Alertmanager 接收的告警
echo -e "\n${YELLOW}[6/8] 检查 Alertmanager 接收的告警...${NC}"
AM_ALERTS=$(curl -s http://localhost:9093/api/v1/alerts | jq '.data | length' 2>/dev/null || echo "0")
if [ "$AM_ALERTS" -gt 0 ]; then
    echo -e "${GREEN}✓ Alertmanager 收到 $AM_ALERTS 条告警${NC}"
else
    echo -e "${YELLOW}! Alertmanager 暂未收到告警（可能是没有触发）${NC}"
fi

# 7. 检查网络连通性
echo -e "\n${YELLOW}[7/8] 检查容器间网络连通性...${NC}"
# 从 prometheus 容器访问 alertmanager
if docker exec prometheus wget -q -O - http://alertmanager:9093/-/healthy > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Prometheus 可以访问 Alertmanager${NC}"
else
    echo -e "${RED}✗ Prometheus 无法访问 Alertmanager${NC}"
fi

# 8. 检查钉钉 webhook 连通性
echo -e "\n${YELLOW}[8/8] 检查钉钉 webhook 连通性...${NC}"
# 从 alertmanager 容器访问钉钉
if docker exec alertmanager wget -q -O - --timeout=5 https://oapi.dingtalk.com/robot/send > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Alertmanager 可以访问钉钉 API${NC}"
else
    echo -e "${YELLOW}! 无法从容器访问钉钉（可能需要检查网络或代理配置）${NC}"
fi

# 查看 Alertmanager 日志
echo -e "\n${YELLOW}最近10条 Alertmanager 日志：${NC}"
docker logs --tail=10 alertmanager 2>&1 || echo "无法获取日志"

echo -e "\n=========================================="
echo "📋 诊断完成"
echo "=========================================="

echo -e "\n${YELLOW}常用调试命令：${NC}"
echo "  查看 Prometheus 告警: curl http://localhost:9090/api/v1/alerts | jq"
echo "  查看 Alertmanager 告警: curl http://localhost:9093/api/v1/alerts | jq"
echo "  查看 Alertmanager 日志: docker logs -f alertmanager"
echo "  手动发送测试告警: ./send-test-alert.sh"
echo ""
echo "  Prometheus UI: http://$HOST_IP:9090"
echo "  Alertmanager UI: http://$HOST_IP:9093"
echo "  Grafana UI: http://$HOST_IP:3000 (admin/admin123)"
