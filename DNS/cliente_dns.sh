#!/bin/bash

tee /etc/resolv.conf > /dev/null <<EOF
nameserver 192.168.10.66
EOF