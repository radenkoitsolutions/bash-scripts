# This script sets up a basic OpenVPN server and generates a client configuration file.
# It performs the following steps:
# 1. Installs necessary dependencies (`curl` and `openssl`).
# 2. Ensures the `/dev/net/tun` device exists, creating it if necessary.
# 3. Creates a working directory (`openvpn-build`) and navigates into it.
# 4. Generates Diffie-Hellman parameters (`dh.pem`) if not already present.
# 5. Generates a private key (`key.pem`) if not already present, with restricted permissions.
# 6. Creates a Certificate Signing Request (CSR) (`csr.pem`) if not already present.
# 7. Generates a self-signed certificate (`cert.pem`) if not already present.
# 8. Creates a default OpenVPN server configuration file (`server.conf`) if not already present.
# 9. Retrieves the public IP address of the server using an external service.
#    - If the public IP cannot be determined, the script exits with an error message.
# 10. Generates a client configuration file (`client.ovpn`) if not already present.
#     - Embeds the private key, certificate, CA certificate, and Diffie-Hellman parameters.
#     - Configures the client to connect to the server's public IP address on port 1194 using UDP.
# 11. Outputs an example `iptables` command to enable NAT for the VPN subnet.
# 12. Displays the generated client configuration file (`client.ovpn`) for review.

#!/bin/sh
apt install curl openssl -y

set -e

[ -d /dev/net ] ||
    mkdir -p /dev/net
[ -c /dev/net/tun ] ||
    mknod /dev/net/tun c 10 200

mkdir -p openvpn-build
cd openvpn-build

touch placeholder

[ -f dh.pem ] ||
    openssl dhparam -out dh.pem 2048

[ -f key.pem ] ||
    openssl genrsa -out key.pem 2048
chmod 600 key.pem

[ -f csr.pem ] ||
    openssl req -new -key key.pem -out csr.pem -subj /CN=OpenVPN/

[ -f cert.pem ] ||
    openssl x509 -req -in csr.pem -out cert.pem -signkey key.pem -days 24855

[ -f server.conf ] || cat >server.conf <<EOF
server 192.168.135.0 255.255.255.0
verb 3
duplicate-cn
key key.pem
ca cert.pem
cert cert.pem
dh dh.pem
keepalive 10 60
persist-key
persist-tun
push "dhcp-option DNS 192.168.135.1"
proto udp
port 11941
dev tun1194
status openvpn-status-server.log
EOF

MY_IP_ADDR=$(curl -s http://myip.enix.org/REMOTE_ADDR)
[ "$MY_IP_ADDR" ] || {
    echo "Sorry, I could not figure out my public IP address."
    echo "(I use http://myip.enix.org/REMOTE_ADDR/ for that purpose.)"
    exit 1
}

[ -f client.ovpn ] || cat >client.ovpn <<EOF
client
nobind
dev tun
redirect-gateway def1

<key>
$(cat key.pem)
</key>
<cert>
$(cat cert.pem)
</cert>
<ca>
$(cat cert.pem)
</ca>
<dh>
$(cat dh.pem)
</dh>

<connection>
remote $MY_IP_ADDR 1194 udp
</connection>
EOF
echo "iptables script"
echo "
iptables -t nat -A POSTROUTING -s 192.168.135.0/24 -o eth0 -j MASQUERADE
iptables -n -L -v -t nat
"
cat client.ovpn
