#!/bin/bash
set -e

# check distro and root 
if [ -f /etc/debian_version ]; then
    echo "Debian/Ubuntu detected"
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
elif [ -f /etc/redhat-release ]; then
    echo "Redhat/CentOS detected"
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
else
    echo "Unsupported distro"
    exit 1
fi

# check to see if the OS is systemd-based
if [ ! -d /run/systemd/system ]; then
    echo "Systemd not detected, exiting"
    exit 1
fi

# prompt before removing stub resolver 
echo "This script will remove the stub resolver from /etc/resolv.conf"
echo "and replace it with 9.9.9.9"
echo "Press Ctrl-C to abort or Enter to continue"
read

# check to see if sed is installed
if ! command -v sed &> /dev/null; then
    echo "sed could not be found"
    exit 1
fi

# remove stub resolver
sed -i 's/#DNS=/DNS=9.9.9.9/; s/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf 
systemctl restart systemd-resolved

# check if stub resolver is removed by checking netstat for port 53 udp 
if netstat -lntu | grep -q 53; then
    echo "Failed to remove stub resolver"
    exit 1
else
    echo "Stub resolver removed"
fi

# create a folder under /opt for sniproxy
mkdir -p /opt/sniproxy

# download sniproxy
wget -O /opt/sniproxy/sniproxy http://bin.n0p.me/sniproxy
# make it executable
chmod +x /opt/sniproxy/sniproxy

# ask which domains to proxy
echo "sniproxy can proxy all HTTPS traffic or only specific domains, if you have a domain list URL, enter it below, otherwise press Enter to proxy all HTTPS traffic"
read domainlist

execCommand="/opt/sniproxy/sniproxy"

# if domainslist is not empty, there should be a --domainListPath argument added to sniproxy execute command
if [ -n "$domainlist" ]; then
    execCommand="$execCommand --domainListPath $domainlist"
fi

# ask if DNS over TCP should be enabled
echo "Do you want to enable DNS over TCP? (y/n)"
read dnsOverTCP
# if yes, add --bindDnsOverTcp argument to sniproxy execute command
if [ "$dnsOverTCP" = "y" ]; then
    execCommand="$execCommand --bindDnsOverTcp"
fi

# ask if DNS over TLS should be enabled
echo "Do you want to enable DNS over TLS? (y/n)"
read dnsOverTLS
# if yes, add --bindDnsOverTls argument to sniproxy execute command
if [ "$dnsOverTLS" = "y" ]; then
    execCommand="$execCommand --bindDnsOverTls"
fi

# ask for DNS over QUIC
echo "Do you want to enable DNS over QUIC? (y/n)"
read dnsOverQUIC
# if yes, add --bindDnsOverQuic argument to sniproxy execute command
if [ "$dnsOverQUIC" = "y" ]; then
    execCommand="$execCommand --bindDnsOverQuic"
fi

# if any of DNS over TLS or DNS over QUIC is enabled, ask for the certificate path and key path
if [ "$dnsOverTLS" = "y" ] || [ "$dnsOverQUIC" = "y" ]; then
    echo "Enter the path to the certificate file, if you don't have one, press Enter to use a self-signed certificate"
    read certPath
    echo "Enter the path to the key file, if you don't have one, press Enter to use a self-signed certificate"
    read keyPath

    # if any of the paths are empty, omit both arguments and print a warning for self-signed certificates
    if [ -z "$certPath" ] || [ -z "$keyPath" ]; then
        echo "WARNING: Using self-signed certificates"
    else
        execCommand="$execCommand --certPath $certPath --keyPath $keyPath"
    fi
fi

# create a systemd service file
cat <<EOF > /etc/systemd/system/sniproxy.service
[Unit]
Description=sniproxy
After=network.target

[Service]
Type=simple
ExecStart=$execCommand
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# enable and start the service
systemctl enable sniproxy
systemctl start sniproxy

# check if sniproxy is running
if systemctl is-active --quiet sniproxy; then
    echo "sniproxy is running"
else
    echo "sniproxy is not running"
fi

# get the public IP of the server by curl 4.ident.me
publicIP=$(curl -s 4.ident.me)

# print some instructions for setting up DNS in clients to this
echo "sniproxy is now running, you can set up DNS in your clients to $publicIP"
echo "you can check the status of sniproxy by running: systemctl status sniproxy"
echo "you can check the logs of sniproxy by running: journalctl -u sniproxy"
echo "some of the features of sniproxy are not covered by this script, please refer to the GitHub page for more information: github.com/moasjjal/sniproxy"

echo "if journal shows empty, you might need to reboot the server, sniproxy is set up as a service so it should start automatically after reboot"

# we're done
echo "Done"
exit 0