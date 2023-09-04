#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}


REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "Note: Please run the script under the root user" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "Does not support the current VPS system, please use the mainstream operating system" && exit 1

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

realip(){
    ip=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || ip=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
}

inst_cert(){
    green "Methods of applying certificate ："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Bing self-signed certificate ${YELLOW} (default) ${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} Acme script auto-apply"
    echo -e " ${GREEN}3.${PLAIN} Custom Certificate Path"
    echo ""
    read -rp "please enter options [1-3]: " certInput
    if [[ $certInput == 2 ]]; then
        cert_path="/root/cert.crt"
        key_path="/root/private.key"
        if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
            domain=$(cat /root/ca.log)
            green "Legacy domain name detected: certificate for $domain, applying"
            hy_domain=$domain
        else
            WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
                wg-quick down wgcf >/dev/null 2>&1
                systemctl stop warp-go >/dev/null 2>&1
                ip=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || ip=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
                wg-quick up wgcf >/dev/null 2>&1
                systemctl start warp-go >/dev/null 2>&1
            else
                ip=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || ip=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
            fi
            
            read -p "Please enter the domain name to apply for a certificate：" domain
            [[ -z $domain ]] && red "No domain name entered, unable to perform operation！" && exit 1
            green "Domain name entered：$domain" && sleep 1
            domainIP=$(curl -sm8 ipget.net/?ip="${domain}")
            if [[ $domainIP == $ip ]]; then
                ${PACKAGE_INSTALL[int]} curl wget sudo socat openssl
                if [[ $SYSTEM == "CentOS" ]]; then
                    ${PACKAGE_INSTALL[int]} cronie
                    systemctl start crond
                    systemctl enable crond
                else
                    ${PACKAGE_INSTALL[int]} cron
                    systemctl start cron
                    systemctl enable cron
                fi
                curl https://get.acme.sh | sh -s email=$(date +%s%N | md5sum | cut -c 1-16)@gmail.com
                source ~/.bashrc
                bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
                bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                if [[ -n $(echo $ip | grep ":") ]]; then
                    bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --listen-v6 --insecure
                else
                    bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --insecure
                fi
                bash ~/.acme.sh/acme.sh --install-cert -d ${domain} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
                if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]]; then
                    echo $domain > /root/ca.log
                    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
                    echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
                    green "Successful! The certificate (cer.crt) and private key (private.key) files applied by the script have been saved to the /root folder"
                    yellow "The certificate crt file path is as follows: /root/cert.crt"
                    yellow "The private key file path is as follows: /root/private.key"
                    hy_domain=$domain
                fi
            else
                red "The IP resolved by the current domain name does not match the real IP used by the current VPS"
                green "suggestions below:"
                yellow "1. Please make sure CloudFlare is turned off (DNS only), other domain name resolution or CDN website settings are the same"
                yellow "2. Please check whether the IP set by the DNS resolution is the real IP of the VPS"
                yellow "3. The script may not keep up with the times, it is recommended to post screenshots to GitHub Issues, or TG groups for inquiries"
                exit 1
            fi
        fi
    elif [[ $certInput == 3 ]]; then
        read -p "Please enter the path of the public key file crt: " certpath
        yellow "The path of the public key file crt: $certpath"
        read -p "Please enter the path of the key file key: " keypath
        yellow "The path of the key file key: $keypath"
        read -p "Please enter the domain name of the certificate: " domain
        yellow "Certificate domain name: $domain"
        hy_domain=$domain
    else
        green "will use Bing self-signed certificates as node certificates for Hysteria 2"

        cert_path="/etc/hysteria/cert.crt"
        key_path="/etc/hysteria/private.key"
        openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
        openssl req -new -x509 -days 36500 -key /etc/hysteria/private.key -out /etc/hysteria/cert.crt -subj "/CN=www.bing.com"
        chmod 777 /etc/hysteria/cert.crt
        chmod 777 /etc/hysteria/private.key
        hy_domain="www.bing.com"
        domain="www.bing.com"
    fi
}

inst_port(){
    iptables -t nat -F PREROUTING >/dev/null 2>&1

    read -p "Set the Hysteria2 port [1-65535] (Enter will randomly assign the port): " port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} The port is already occupied by another program, please change the port and try again!  "
            read -p "Set the Hysteria2 port [1-65535] (Enter will randomly assign the port): " port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    yellow "The port that will be used on the Hysteria2 node is: $port"
    inst_jump
}

inst_jump(){
    green "The Hysteria 2 port usage mode is as follows:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} single port ${YELLOW}（default）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} port hopping"
    echo ""
    read -rp "Please enter options [1-2]: " jumpInput
    if [[ $jumpInput == 2 ]]; then
        read -p "Set the starting port of the range port (recommended between 10000-65535)：" firstport
        read -p "Set the end port of a range port (recommended between 10000-65535, must be larger than the start port above)：" endport
        if [[ $firstport -ge $endport ]]; then
            until [[ $firstport -le $endport ]]; do
                if [[ $firstport -ge $endport ]]; then
                    red "The start port you set is less than the end port, please re-enter the start and end port"
                    read -p "Set the starting port of the range port (recommended between 10000-65535): " firstport
                    read -p "Set the end port of a range port (recommended between 10000-65535, must be larger than the start port above):" endport
                fi
            done
        fi
        iptables -t nat -A PREROUTING -p udp --dport $firstport:$endport  -j DNAT --to-destination :$port
        ip6tables -t nat -A PREROUTING -p udp --dport $firstport:$endport  -j DNAT --to-destination :$port
        netfilter-persistent save >/dev/null 2>&1
    else
        red "will continue to use single port mode"
    fi
}

inst_pwd(){
    read -p "Set Hysteria2 password ( Enter for random password) :  " auth_pwd
    [[ -z $auth_pwd ]] && auth_pwd=$(date +%s%N | md5sum | cut -c 1-8)
    yellow "The password used on the Hysteria2 node is: $auth_pwd"
}

inst_site(){
    read -rp "Please enter the fake website address of Hysteria 2 (remove https://) [Default : speedtest.net]: " proxysite
    [[ -z $proxysite ]] && proxysite="speedtest.net"
    yellow "The masquerading site used on the Hysteria 2 node is: $proxysite"
}

insthysteria(){
    warpv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warpv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $warpv4 =~ on|plus || $warpv6 =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        systemctl stop warp-go >/dev/null 2>&1
        realip
        systemctl start warp-go >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
    else
        realip
    fi

    if [[ ! ${SYSTEM} == "CentOS" ]]; then
        ${PACKAGE_UPDATE}
    fi
    ${PACKAGE_INSTALL} curl wget sudo qrencode procps iptables-persistent netfilter-persistent

    wget -N https://raw.githubusercontent.com/Misaka-blog/hysteria-install/main/hy2/install_server.sh
    bash install_server.sh
    rm -f install_server.sh

    if [[ -f "/usr/local/bin/hysteria" ]]; then
        green "Hysteria 2 installed successfully!  "
    else
        red "Hysteria 2 installation failed!  "
    fi

    # Ask user for Hysteria configuration
    inst_cert
    inst_port
    inst_pwd
    inst_site

    # Set up the Hysteria configuration file
    cat << EOF > /etc/hysteria/config.yaml
listen: :$port

tls:
  cert: $cert_path
  key: $key_path

obfs:
  type: salamander
  salamander:
    password: $auth_pwd

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

auth:
  type: password
  password: $auth_pwd

masquerade:
  type: proxy
  proxy:
    url: https://$proxysite
    rewriteHost: true
EOF

    # Determine the final inbound port range
    if [[ -n $firstport ]]; then
        last_port="$port,$firstport-$endport"
    else
        last_port=$port
    fi

    mkdir /root/hy
    cat << EOF > /root/hy/hy-client.yaml
server: $ip:$last_port

auth: $auth_pwd

tls:
  sni: $hy_domain
  insecure: true

obfs: $auth_pwd

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

fastOpen: true

socks5:
  listen: 127.0.0.1:5080

transport:
  udp:
    hopInterval: 30s 
EOF
    cat << EOF > /root/hy/hy-client.json
{
  "server": "$ip:$last_port",
  "auth": "$auth_pwd",
  "tls": {
    "sni": "$hy_domain",
    "insecure": true
  },
  "obfs": "$auth_pwd",
  "quic": {
    "initStreamReceiveWindow": 16777216,
    "maxStreamReceiveWindow": 16777216,
    "initConnReceiveWindow": 33554432,
    "maxConnReceiveWindow": 33554432
  },
  "socks5": {
    "listen": "127.0.0.1:5080"
  },
  "transport": {
    "udp": {
      "hopInterval": "30s"
    }
  }
}
EOF

    url="hysteria2://$auth_pwd@$ip:$last_port/?insecure=1&sni=$hy_domain&obfs=$auth_pwd"
    echo $url > /root/hy/url.txt

    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl start hysteria-server
    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) && -f '/etc/hysteria/config.yaml' ]]; then
        green "Hysteria 2 service started successfully"
    else
        red "The Hysteria 2 service failed to start, please run systemctl status hysteria-server to view the service status and give feedback, the script exits " && exit 1
    fi
    red "======================================================================================"
    green "Hysteria 2 proxy service installation complete"
    yellow "The content of the Hysteria 2 client YML configuration file hy-client.yaml is as follows and saved to /root/hy/hy-client.yaml"
    red "$(cat /root/hy/hy-client.yaml)"
    yellow "The content of the Hysteria 2 client JSON configuration file hy-client.json is as follows and saved to /root/hy/hy-client.json"
    red "$(cat /root/hy/hy-client.json)"
    yellow "The Hysteria 2 node sharing link is as follows and saved to /root/hy/url.txt"
    red "$(cat /root/hy/url.txt)"
}

unsthysteria(){
    systemctl stop hysteria-server.service >/dev/null 2>&1
    systemctl disable hysteria-server.service >/dev/null 2>&1
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf /usr/local/bin/hysteria /etc/hysteria /root/hy /root/hysteria.sh
    iptables -t nat -F PREROUTING >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1

    green "Hysteria 2 has been completely uninstalled!  "
}

starthysteria(){
    systemctl start hysteria-server
    systemctl enable hysteria-server >/dev/null 2>&1
}

stophysteria(){
    systemctl stop hysteria-server
    systemctl disable hysteria-server >/dev/null 2>&1
}

hysteriaswitch(){
    yellow "Please select the operation you need:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Start Hysteria 2"
    echo -e " ${GREEN}2.${PLAIN} Stop Hysteria 2"
    echo -e " ${GREEN}3.${PLAIN} Restart Hysteria 2"
    echo ""
    read -rp "please enter options [0-3]: " switchInput
    case $switchInput in
        1 ) starthysteria ;;
        2 ) stophysteria ;;
        3 ) stophysteria && starthysteria ;;
        * ) exit 1 ;;
    esac
}

changeport(){
    oldport=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 1p | awk '{print $2}' | awk -F ":" '{print $2}')
    
    read -p "Set the Hysteria 2 port [1-65535] (Enter will randomly assign the port): " port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)

    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} The port is already occupied by other programs, please change the port and try again!  "
            read -p "Set the Hysteria 2 port [1-65535] (Enter will randomly assign the port): " port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    sed -i "1s#$oldport#$port#g" /etc/hysteria/config.yaml
    sed -i "1s#$oldport#$port#g" /root/hy/hy-client.yaml
    sed -i "2s#$oldport#$port#g" /root/hy/hy-client.json
    sed -i "s#$oldport#$port#g" /root/hy/url.txt

    stophysteria && starthysteria

    green "Hysteria 2 port successfully modified to: $port"
    yellow "Please manually update the client configuration file to use node"
    cat /root/hy/url.txt
}

changepasswd(){
    oldpasswd=$(cat /etc/hysteria/config.yaml 2>/dev/null | sed -n 15p | awk '{print $2}')

    read -p "Set Hysteria 2 password (carriage return is skipped for random characters): " passwd
    [[ -z $passwd ]] && passwd=$(date +%s%N | md5sum | cut -c 1-8)

    sed -i "1s#$oldpasswd#$passwd#g" /etc/hysteria/config.yaml
    sed -i "1s#$oldpasswd#$passwd#g" /root/hy/hy-client.yaml
    sed -i "3s#$oldpasswd#$passwd#g" /root/hy/hy-client.json
    sed -i "s#$oldpasswd#$passwd#g" /root/hy/url.txt

    stophysteria && starthysteria

    green "Hysteria 2 node password successfully changed to: $passwd"
    yellow "Please manually update the client configuration file to use node"
    cat /root/hy/url.txt
}

change_cert(){
    old_cert=$(cat /etc/hysteria/config.yaml | grep cert | awk -F " " '{print $2}')
    old_key=$(cat /etc/hysteria/config.yaml | grep key | awk -F " " '{print $2}')
    old_hydomain=$(cat /root/hy/hy-client.yaml | grep sni | awk '{print $2}')

    inst_cert

    sed -i "s!$old_cert!$cert_path!g" /etc/hysteria/config.yaml
    sed -i "s!$old_key!$key_path!g" /etc/hysteria/config.yaml
    sed -i "6s/$old_hydomain/$hy_domain/g" /root/hy/hy-client.yaml
    sed -i "5s/$old_hydomain/$hy_domain/g" /root/hy/hy-client.json

    stophysteria && starthysteria

    green "Hysteria 2 node certificate type successfully modified"
    yellow "Please manually update the client configuration file to use node"
}

changeproxysite(){
    oldproxysite=$(cat /etc/hysteria/config.yaml | grep url | awk -F " " '{print $2}' | awk -F "https://" '{print $2}')
    
    inst_site

    sed -i "s#$oldproxysite#$proxysite#g" /etc/hysteria/config.yaml

    stophysteria && starthysteria

    green "Hysteria 2 node masquerading website has been successfully modified to: $proxysite"
}

changeconf(){
    green "The Hysteria 2 configuration change options are as follows:"
    echo -e " ${GREEN}1.${PLAIN} Change port"
    echo -e " ${GREEN}2.${PLAIN} change Password"
    echo -e " ${GREEN}3.${PLAIN} Change certificate type"
    echo -e " ${GREEN}4.${PLAIN} Change website"
    echo ""
    read -p " Please enter options [1-4]：" confAnswer
    case $confAnswer in
        1 ) changeport ;;
        2 ) changepasswd ;;
        3 ) change_cert ;;
        4 ) changeproxysite ;;
        * ) exit 1 ;;
    esac
}

showconf(){
    yellow "The content of the Hysteria 2 client YML configuration file hy-client.yaml is as follows and saved to /root/hy/hy-client.yaml"
    red "$(cat /root/hy/hy-client.yaml)"
    yellow "The content of the Hysteria 2 client JSON configuration file hy-client.json is as follows and saved to /root/hy/hy-client.json"
    red "$(cat /root/hy/hy-client.json)"
    yellow "The Hysteria 2 node sharing link is as follows and saved to /root/hy/url.txt"
    red "$(cat /root/hy/url.txt)"
}

menu() {
    clear
    echo "1###########################################################"
    echo -e "#        ${RED}Hysteria 一one-click installation script${PLAIN}         #"
    echo -e "# ${GREEN}Gihub ${PLAIN}: https://gitlab.com/Ptechgithub                  #"
    echo -e "# ${GREEN}Telegram ${PLAIN}: https://t.me/P_tech2024                      #"
    echo -e "# ${GREEN}YouTube ${PLAIN}: https://www.youtube.com/@IR_TECH              #"
    echo "###########################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Install Hysteria 2"
    echo -e " ${GREEN}2.${PLAIN} ${RED}Uninstall Hysteria 2${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} Start/Stop/Restart"
    echo -e " ${GREEN}4.${PLAIN} Change configuration"
    echo -e " ${GREEN}5.${PLAIN} Show configuration file"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} exit script"
    echo ""
    read -rp "Please enter options [0-5]: " menuInput
    case $menuInput in
        1 ) insthysteria ;;
        2 ) unsthysteria ;;
        3 ) hysteriaswitch ;;
        4 ) changeconf ;;
        5 ) showconf ;;
        * ) exit 1 ;;
    esac
}

menu