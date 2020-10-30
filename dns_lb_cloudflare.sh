#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Place at:
# curl https://raw.githubusercontent.com/yxkumad/dns_lb/master/dns_lb_cloudflare.sh > /usr/local/bin/dns_lb_cloudflare.sh && chmod +x /usr/local/bin/dns_lb_cloudflare.sh
# run `crontab -e` and add next line:
# */1 * * * * /usr/local/bin/dns_lb_cloudflare.sh >/dev/null 2>&1
# or you need log:
# */1 * * * * /usr/local/bin/dns_lb_cloudflare.sh >> /var/log/dns_lb.log 2>&1

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

# API key, see https://www.cloudflare.com/a/account/my-account,
# incorrect api-key results in E_UNAUTH error
CFKEY=

# Username, eg: user@example.com
CFUSER=

# Zone name, eg: example.com
CFZONE_NAME=

# Hostname to update, eg: homeserver.example.com
CFRECORD_NAME=

# Record type, A(IPv4)|AAAA(IPv6), default IPv4
CFRECORD_TYPE=A

# Cloudflare TTL for record, between 120 and 86400 seconds
CFTTL=120

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

# Get current and old WAN ip
PRESENT_IP_FILE=$HOME/.ip_$CFRECORD_NAME.txt
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
  RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" \
  --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$ORG_IP\", \"ttl\":$CFTTL}")  
  curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage?chat_id=$TG_CHATID&text=No service failure found. Updating DNS record $CFZONE_NAME to $ORG_IP"
  echo $ORG_IP > $PRESENT_IP_FILE
else
  if [ "$FAIL_IP" = "$OLD_PRESENT_IP" ]; then
    echo "Service failure found. No DNS record update required. "
    exit 0
  fi
  echo "Service failure found. Updating DNS to $FAIL_IP"
  RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CFZONE_ID/dns_records/$CFRECORD_ID" \
  -H "X-Auth-Email: $CFUSER" \
  -H "X-Auth-Key: $CFKEY" \
  -H "Content-Type: application/json" \
  --data "{\"id\":\"$CFZONE_ID\",\"type\":\"$CFRECORD_TYPE\",\"name\":\"$CFRECORD_NAME\",\"content\":\"$FAIL_IP\", \"ttl\":$CFTTL}")
  curl -s "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage?chat_id=$TG_CHATID&text=Service failure found. Updating DNS record $CFZONE_NAME to $FAIL_IP"
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
