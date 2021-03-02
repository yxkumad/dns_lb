# DNS 负载均衡

由 Cloudflare API 或 华为云 API 加 go-torch 实现的 DNS 负载均衡

## 配置
* Cloudflare DNS
  ```
  curl https://raw.githubusercontent.com/yxkumad/dns_lb/master/dns_lb_cloudflare.sh > /usr/local/bin/dns_lb_cloudflare.sh && chmod +x /usr/local/bin/dns_lb_cloudflare.sh
  ```
  
* 华为云 DNS
  ```
  curl https://raw.githubusercontent.com/yxkumad/dns_lb/master/dns_lb_huaweicloud.sh > /usr/local/bin/dns_lb_huaweicloud.sh && chmod +x /usr/local/bin/dns_lb_huaweicloud.sh
  ```

详情可参考旧版教程 https://www.blueskyxn.com/202102/4210.html

## 需要
https://github.com/TorchPing/go-torch

## 参考
https://github.com/yulewang/cloudflare-api-v4-ddns
https://github.com/lllvcs/huaweicloud_ddns
