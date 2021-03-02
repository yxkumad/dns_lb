#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# 下载:
# curl https://raw.githubusercontent.com/yxkumad/dns_lb/master/dns_lb_cloudflare.sh > /usr/local/bin/dns_lb_cloudflare.sh && chmod +x /usr/local/bin/dns_lb_cloudflare.sh
# 定时任务 `crontab -e` 输入以下指令:
# */1 * * * * /usr/local/bin/dns_lb_cloudflare.sh >/dev/null 2>&1

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

# 配置

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

# Cloudflare API key，参考 https://www.cloudflare.com/a/account/my-account
CFKEY=

# Cloudflare 邮箱（如 user@example.com）
CFUSER=

# 域名（如 985.moe）
CFZONE_NAME=

# 域名（连子域名，如 www.985.moe）
CFRECORD_NAME=

# DNS 记录（A(IPv4)|AAAA(IPv6)，默认为 A(IPv4)）
CFRECORD_TYPE=A

# TTL（120 至 86400 秒）
CFTTL=120

echo "您的域名: $CFRECORD_NAME"
echo "正在获取 CLoudflare 资源 ID..."

# If required settings are missing just exit
if [ "$CFKEY" = "" ]; then
  echo "Missing api-key, get at: https://www.cloudflare.com/a/account/my-account"
  echo "and save in ${0} or using the -k flag"
  exit 2
fi
if [ "$CFUSER" = "" ]; then
  echo "Missing username, probably your email-address"
  echo "and save in ${0} or using the -u flag"
  exit 2
fi
if [ "$CFRECORD_NAME" = "" ]; then 
  echo "Missing hostname, what host do you want to update?"
  echo "save in ${0} or using the -h flag"
  exit 2
fi
# If the hostname is not a FQDN
if [ "$CFRECORD_NAME" != "$CFZONE_NAME" ] && ! [ -z "${CFRECORD_NAME##*$CFZONE_NAME}" ]; then
  CFRECORD_NAME="$CFRECORD_NAME.$CFZONE_NAME"
  echo " => Hostname is not a FQDN, assuming $CFRECORD_NAME"
fi
# Get zone_identifier & record_identifier
ID_FILE=$HOME/.cf-id_$CFRECORD_NAME.txt
if [ -f $ID_FILE ] && [ $(wc -l $ID_FILE | cut -d " " -f 1) == 4 ] \
  && [ "$(sed -n '3,1p' "$ID_FILE")" == "$CFZONE_NAME" ] \
  && [ "$(sed -n '4,1p' "$ID_FILE")" == "$CFRECORD_NAME" ]; then
    CFZONE_ID=$(sed -n '1,1p' "$ID_FILE")
    CFRECORD_ID=$(sed -n '2,1p' "$ID_FILE")
else
    echo "Updating zone_identifier & record_identifier"
    CFZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CFZONE_NAME" -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json" | grep -Po '(?<="id":")[^"]*' | head -1 )
    CFRECORD_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records?name=$CFRECORD_NAME" -H "X-Auth-Email: $CFUSER" -H "X-Auth-Key: $CFKEY" -H "Content-Type: application/json"  | grep -Po '(?<="id":")[^"]*' | head -1 )
    echo "$CFZONE_ID" > $ID_FILE
    echo "$CFRECORD_ID" >> $ID_FILE
    echo "$CFZONE_NAME" >> $ID_FILE
    echo "$CFRECORD_NAME" >> $ID_FILE
fi

echo "获取 Cloudflare 资源 ID 完成"

# 存放 IP 文件
PRESENT_IP_FILE=$HOME/.ip_$CFRECORD_NAME.txt
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
ERROR=$HOME/.error_$CFRECORD_NAME.txt

if [ "$(echo $CHECK | grep "\"status\":true")" != "" ]; then
  if [ "$ORG_IP" = "$OLD_PRESENT_IP" ]; then
    echo "原服务器 $ORG_IP 的状态为正常，无需切换 DNS 解析至备用服务器 $FAIL_IP"
    exit 0
  fi
  echo "原服务器 $ORG_IP 的状态已回复正常，正在切换 DNS 解析至原服务器 $ORG_IP"
  RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" \
  --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$ORG_IP\", \"ttl\":$CFTTL}")  
  echo "正在发送信息到 Telegram..."
  curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage?chat_id=$TG_CHATID&text=域名 $CFRECORD_NAME 的原服务器 $ORG_IP 的状态已回复正常，正在切换 DNS 解析至原服务器 $ORG_IP"
  echo "0" > $ERROR 
  echo $ORG_IP > $PRESENT_IP_FILE
else
  if [ "$FAIL_IP" = "$OLD_PRESENT_IP" ]; then
    echo "原服务器 $ORG_IP 的状态为异常，已于过去切换 DNS 解析至备用服务器 $FAIL_IP，无需再次切换"
        exit 0
  elif [ `cat $ERROR` -eq 1 ]; then
    echo "原服务器 $ORG_IP 的状态为异常，并已累计 1 次故障次数，正在切换 DNS 解析至备用服务器 $FAIL_IP"
    RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
    -H "X-Auth-Email: $CFUSER" \
    -H "X-Auth-Key: $CFKEY" \
    -H "Content-Type: application/json" \
    --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$FAIL_IP\", \"ttl\":$CFTTL}")
    echo "正在发送信息到 Telegram..."
    curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage?chat_id=$TG_CHATID&text=域名 $CFRECORD_NAME 的原服务器 $ORG_IP 的状态为异常并已累计 1 次故障次数，正在切换 DNS 解析至备用服务器 $FAIL_IP"
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
