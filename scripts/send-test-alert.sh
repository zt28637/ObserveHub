#!/bin/bash
# ============================================
# 发送测试告警脚本
# ============================================

set -e

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "🧪 发送测试告警"
echo "=========================================="

# 获取当前时间
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# 发送测试告警到 Alertmanager
echo -e "\n${YELLOW}发送测试告警到 Alertmanager...${NC}"

curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d "[{
    \"labels\": {
      \"alertname\": \"TestAlert\",
      \"severity\": \"warning\",
      \"instance\": \"test-server-01\"
    },
    \"annotations\": {
      \"summary\": \"这是一条测试告警\",
      \"description\": \"用于验证告警链路是否正常，当前时间: $NOW\"
    },
    \"startsAt\": \"$NOW\"
  }]"

echo -e "\n${GREEN}✓ 测试告警已发送${NC}"

echo -e "\n${YELLOW}检查 Alertmanager 是否收到告警...${NC}"
sleep 2
curl -s http://localhost:9093/api/v1/alerts | jq -r '.data[] | select(.labels.alertname == "TestAlert") | "告警名称: \(.labels.alertname)\n告警级别: \(.labels.severity)\n实例: \(.labels.instance)\n状态: \(.status.state)\n开始时间: \(.startsAt)"' 2>/dev/null || echo "暂未收到告警"

echo -e "\n${YELLOW}提示：${NC}"
echo "1. 如果 Alertmanager 收到了告警，说明 Prometheus → Alertmanager 链路正常"
echo "2. 如果钉钉收到了消息，说明 Alertmanager → 钉钉 链路正常"
echo "3. 如果钉钉没收到，请检查 Alertmanager 日志: docker logs -f alertmanager"
