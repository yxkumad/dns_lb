#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Configuration
echo " *******   ****     **  ********       **       ******  
/**////** /**/**   /** **//////       /**      /*////** 
/**    /**/**//**  /**/**             /**      /*   /** 
/**    /**/** //** /**/*********      /**      /******  
/**    /**/**  //**/**////////**      /**      /*//// **
/**    ** /**   //****       /**      /**      /*    /**
/*******  /**    //*** ********  *****/********/******* 
///////   //      /// ////////  ///// //////// ///////  "
echo "Github: https://github.com/yxkumad/dns_lb"
echo "Telegram: https://t.me/yxkumad"
echo "正在初始化..."

# Ping API 使用 https://github.com/TorchPing/go-torch 搭建，新版本脚本只需要输入 API 的 IP 和 端口（默认 8080）
PING_API=x.x.x.x:8080
echo "您的 Ping API $PING_API"

# 原服务器 IP
ORG_IP=x.x.x.x
echo "您的原服务器 IP: $ORG_IP"

# 备用服务器 IP
FAIL_IP=x.x.x.x
echo "您的备用服务器 IP: $FAIL_IP"

# 端口（默认为 22）
PORT=22

# Telegram 机器人 Token
TG_BOT_TOKEN=

# Telegram 发送用户/群组/频道 ID
TG_CHATID=

#华为云用户名
username=""

#华为云账户名
accountname=""

#华为云密码
password=""

#域名（如 985.moe）
domain=""

#DNS 段名（如 www）
host=""

echo "您的域名: $host.$domain"

#华为云 IAM API 终端地址 请根据地域选择
iam="iam.myhuaweicloud.com"
#iam="iam.ap-southeast-1.myhuaweicloud.com"
#iam="iam.ap-southeast-3.myhuaweicloud.com"

#华为云 DNS API 终端地址 请根据地域选择
dns="dns.myhuaweicloud.com"
#dns="dns.ap-southeast-1.myhuaweicloud.com"
#dns="dns.ap-southeast-3.myhuaweicloud.com"

echo "正在获取华为云 Token..."

token_X="$(
    curl -L -k -s -D - -X POST \
        "https://$iam/v3/auth/tokens" \
        -H 'content-type: application/json' \
        -d '{
    "auth": {
        "identity": {
            "methods": ["password"],
            "password": {
                "user": {
                    "name": "'$username'",
                    "password": "'$password'",
                    "domain": {
                        "name": "'$accountname'"
                    }
                }
            }
        },
        "scope": {
            "domain": {
                "name": "'$accountname'"
            }
        }
    }
  }' | grep X-Subject-Token
)"

token="$(echo $token_X | awk -F ' ' '{print $2}')"

echo "获取华为云 Token 完成"

recordsets="$(
    curl -L -k -s -D - \
        "https://$dns/v2/recordsets?name=$host.$domain." \
        -H 'content-type: application/json' \
        -H 'X-Auth-Token: '$token | grep -o "id\":\"[0-9a-z]*\"" | awk -F : '{print $2}' | grep -o "[a-z0-9]*"
)"

RECORDSET_ID=$(echo $recordsets | cut -d ' ' -f 1)
ZONE_ID=$(echo $recordsets | cut -d ' ' -f 2 | cut -d ' ' -f 2)

# 存放 IP 文件
PRESENT_IP_FILE=$HOME/.ip_$host.$domain.txt
if [ -f $PRESENT_IP_FILE ]; then
  OLD_PRESENT_IP=`cat $PRESENT_IP_FILE`
else
  echo "不存在 IP 文件，正在建立"
  OLD_PRESENT_IP=""
fi

# 检测服务器故障
echo "正在检测服务器 $ORG_IP 的状态..."
CHECK=$(curl -s "http://$PING_API/ping/$ORG_IP/$PORT")

# 存放故障次数文件
ERROR=$HOME/.error_$host.$domain.txt

if [ "$(echo $CHECK | grep "\"status\":true")" != "" ]; then
  if [ "$ORG_IP" = "$OLD_PRESENT_IP" ]; then
    echo "原服务器 $ORG_IP 的状态为正常，无需切换 DNS 解析至备用服务器 $FAIL_IP"
    exit 0
  fi
  echo "原服务器 $ORG_IP 的状态已回复正常，正在切换 DNS 解析至原服务器 $ORG_IP"
  RESPONSE=$(curl -X PUT -L -k -s \
    "https://$dns/v2/zones/$ZONE_ID/recordsets/$RECORDSET_ID" \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: $token" \
    -d "{\"records\": [\"$ORG_IP\"],\"ttl\": 1}")  
  echo "正在发送信息到 Telegram..."
  curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage?chat_id=$TG_CHATID&text=域名 $host.$domain 的原服务器 $ORG_IP 的状态已回复正常，正在切换 DNS 解析至原服务器 $ORG_IP"
  echo "0" > $ERROR 
  echo $ORG_IP > $PRESENT_IP_FILE
else
  if [ "$FAIL_IP" = "$OLD_PRESENT_IP" ]; then
    echo "原服务器 $ORG_IP 的状态为异常，已于过去切换 DNS 解析至备用服务器 $FAIL_IP，无需再次切换"
        exit 0
  elif [ `cat $ERROR` -eq 1 ]; then
    echo "原服务器 $ORG_IP 的状态为异常，并已累计 1 次故障次数，正在切换 DNS 解析至备用服务器 $FAIL_IP"
    RESPONSE=$(curl -X PUT -L -k -s \
      "https://$dns/v2/zones/$ZONE_ID/recordsets/$RECORDSET_ID" \
      -H "Content-Type: application/json" \
      -H "X-Auth-Token: $token" \
      -d "{\"records\": [\"$FAIL_IP\"],\"ttl\": 1}") 
    echo "正在发送信息到 Telegram..."
    curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage?chat_id=$TG_CHATID&text=域名 $host.$domain 的原服务器 $ORG_IP 的状态为异常并已累计 1 次故障次数，正在切换 DNS 解析至备用服务器 $FAIL_IP"
    echo $FAIL_IP > $PRESENT_IP_FILE
  else
    echo "1" > $ERROR  
    echo "原服务器 $ORG_IP 的状态为异常，已累计 1 次故障次数"
    exit 0
  fi
fi

if [ "$RESPONSE" != "${RESPONSE%success*}" ] && [ "$(echo $RESPONSE | grep "\"success\":true")" != "" ]; then
  echo "切换 DNS 解析成功！"
  exit
else
  echo '切换 DNS 解析失败！'
  echo "错误: $RESPONSE"
  exit 1
fi
