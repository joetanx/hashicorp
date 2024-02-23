#!/bin/bash
# Installs the boundary as a service for systemd on linux
# Usage: ./install_boundary.sh <worker|controller>

TYPE=$1

tee /etc/systemd/system/boundary-${TYPE}.service >/dev/null<< EOF
[Unit]
Description=boundary ${TYPE}

[Service]
ExecStart=/usr/bin/boundary server -config /etc/boundary.d/${TYPE}.hcl
User=boundary
Group=boundary
LimitMEMLOCK=infinity
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK

[Install]
WantedBy=multi-user.target
EOF

adduser --system boundary || true
chown boundary:boundary /etc/boundary.d/${TYPE}.hcl

chmod 664 /etc/systemd/system/boundary-${TYPE}.service
systemctl daemon-reload
systemctl enable --now boundary-${TYPE}