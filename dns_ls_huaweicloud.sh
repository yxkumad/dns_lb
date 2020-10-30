#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Place at:
# curl https://raw.githubusercontent.com/yxkumad/dns_lb/master/dns_lb_huaweicloud.sh > /usr/local/bin/dns_lb_huaweicloud.sh && chmod +x /usr/local/bin/dns_lb_huaweicloud.sh
# run `crontab -e` and add next line:
# */1 * * * * /usr/local/bin/dns_lb_huaweicloud.sh >/dev/null 2>&1
# or you need log:
# */1 * * * * /usr/local/bin/dns_lb_huaweicloud.sh >> /var/log/dns_lb.log 2>&1

# Configuration

# Ping API
PING_API=http://yourapi/ping
# Original IP
ORG_IP=

# Failure IP
FAIL_IP=

# Telegram Bot Token
TG_BOT_TOKEN=

# Telegram Chat ID
TG_CHATID=

#用户名
username=""
#账户名
accountname=""
#密码
password=""

#域名
domain="example.com"
#主机名
host="www"

#End Point 终端地址 请根据地域选择
iam="iam.myhuaweicloud.com"
#iam="iam.ap-southeast-1.myhuaweicloud.com"
#iam="iam.ap-southeast-3.myhuaweicloud.com"

dns="dns.myhuaweicloud.com"
#dns="dns.ap-southeast-1.myhuaweicloud.com"
#dns="dns.ap-southeast-3.myhuaweicloud.com"

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

recordsets="$(
    curl -L -k -s -D - \
        "https://$dns/v2/recordsets?name=$host.$domain." \
        -H 'content-type: application/json' \
        -H 'X-Auth-Token: '$token | grep -o "id\":\"[0-9a-z]*\"" | awk -F : '{print $2}' | grep -o "[a-z0-9]*"
)"

RECORDSET_ID=$(echo $recordsets | cut -d ' ' -f 1)
ZONE_ID=$(echo $recordsets | cut -d ' ' -f 2 | cut -d ' ' -f 2)


# Get current and old WAN ip
PRESENT_IP_FILE=$HOME/.ip_$host.$domain.txt
if [ -f $PRESENT_IP_FILE ]; then
  OLD_PRESENT_IP=`cat $PRESENT_IP_FILE`
else
  echo "No file, need IP"
  OLD_PRESENT_IP=""
fi

# Check service failure
CHECK=$(curl -s "$PING_API/$ORG_IP/22")

if [ "$(echo $CHECK | grep "\"status\":true")" != "" ]; then
  if [ "$ORG_IP" = "$OLD_PRESENT_IP" ]; then
    echo "No service failure found. No DNS record update required. "
    exit 0
  fi
  echo "No service failure found. Updating DNS to $ORG_IP"
  RESPONSE=$(curl -X PUT -L -k -s \
    "https://$dns/v2/zones/$ZONE_ID/recordsets/$RECORDSET_ID" \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: $token" \
    -d "{\"records\": [\"$ORG_IP\"],\"ttl\": 1}")  
  curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage?chat_id=$TG_CHATID&text=No service failure found. Updating DNS record $host.$domain to $ORG_IP"
  echo $ORG_IP > $PRESENT_IP_FILE
else
  if [ "$FAIL_IP" = "$OLD_PRESENT_IP" ]; then
    echo "Service failure found. No DNS record update required. "
    exit 0
  fi
  echo "Service failure found. Updating DNS to $FAIL_IP"
  RESPONSE=$(curl -X PUT -L -k -s \
    "https://$dns/v2/zones/$ZONE_ID/recordsets/$RECORDSET_ID" \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: $token" \
    -d "{\"records\": [\"$FAIL_IP\"],\"ttl\": 1}") 
  curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage?chat_id=$TG_CHATID&text=Service failure found. Updating DNS record $host.$domain to $FAIL_IP"
  echo $FAIL_IP > $PRESENT_IP_FILE
fi

if [ "$RESPONSE" != "${RESPONSE%success*}" ] && [ "$(echo $RESPONSE | grep "\"success\":true")" != "" ]; then
  echo "Updated succesfuly!"
  exit
else
  echo 'Something went wrong :('
  echo "Response: $RESPONSE"
  exit 1
fi
