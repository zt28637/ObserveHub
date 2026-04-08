#!/bin/bash
# auto_diagnose.sh - 一键故障诊断脚本
# 用法：./auto_diagnose.sh <服务名> <日志文件>

SERVICE=$1
LOG_FILE=$2
#[]内侧必须有空格
if [ -z "$SERVICE" ] || [ -z "$LOG_FILE" ];then
   echo "用法：$0 <服务名> <日志文件>"
   exit 1
fi

# 再检查文件是否存在，然后才计算
if [ ! -f "$LOG_FILE" ]; then
   echo "错误：日志文件不存在"
   exit 1
fi

ERROR_TIME=$(grep -ic "ERROR" $LOG_FILE)
WARN_TIME=$(grep -ic "WARN" $LOG_FILE)

echo "========== <$SERVICE> 故障诊断报告 =========="
echo "诊断时间：$(date)"

echo "ERROR出现$ERROR_TIME次 | WARN出现$WARN_TIME次"

echo "最近3条ERROR详情"
grep -i "ERROR" $LOG_FILE | head -3

echo "错误时间分布"
egrep -i "ERROR" $LOG_FILE | 
awk '{print $1}' | sort | uniq -c

echo "高频IP统计"
grep -i "ERROR" $LOG_FILE | 
grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | 
sort | uniq -c | sort -rn | head -3

echo "========== 诊断完成 =========="

