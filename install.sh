#!/bin/bash
# Install or update the multiwan-balance service.
# Usage:     sudo bash install.sh
# Uninstall: sudo systemctl disable --now multiwan-balance
#            sudo rm /usr/local/sbin/multiwan-balance /etc/systemd/system/multiwan-balance.service /etc/sysctl.d/90-multiwan.conf
set -e
SRC=$(dirname "$(readlink -f "$0")")
install -m 0755 "$SRC/multiwan-balance" /usr/local/sbin/multiwan-balance
install -m 0644 "$SRC/multiwan-balance.service" /etc/systemd/system/multiwan-balance.service
printf 'net.ipv4.fib_multipath_hash_policy = 1\nnet.ipv4.fib_multipath_use_neigh = 1\n' > /etc/sysctl.d/90-multiwan.conf
sysctl -q -p /etc/sysctl.d/90-multiwan.conf
systemctl daemon-reload
systemctl enable multiwan-balance
systemctl restart multiwan-balance
sleep 8
systemctl --no-pager --lines=5 status multiwan-balance | tail -6
echo; ip -4 route show default
