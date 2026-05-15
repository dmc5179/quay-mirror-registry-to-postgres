#!/bin/bash

# TODO: Different args if root or non-root

QUAY_ROOT=/home/ec2-user/quay
SYSTEMCTL="systemctl --user"
SERVICE_FILE="${HOME}/.config/systemd/user/quay-postgres.service"

systemctl --user stop quay-app.service

sleep 5

mkdir -pv ${QUAY_ROOT}/postgres
# chmod 26:26 ${QUAY_ROOT}/postgres  # set proper permissions
podman pull registry.redhat.io/rhel9/postgresql-16:9.7

#cat >> /etc/systemd/system/quay-postgres.service << EOF
cat >> ${HOME}/.config/systemd/user/quay-postgres.service << EOF
[Unit]
Description=PostgreSQL Podman Container for Quay
Wants=network.target
After=network-online.target quay-pod.service
Requires=quay-pod.service

[Service]
Type=simple
TimeoutStartSec=5m
ExecStartPre=-/bin/rm -f %t/%n-pid %t/%n-cid
ExecStart=/usr/bin/podman run \
   --name postgres \
   -v ${QUAY_ROOT}/postgres:/var/lib/pgsql/data:Z \
   --image-volume=ignore \
   -e POSTGRESQL_USER=user \
   -e POSTGRESQL_DATABASE=quay \
   -e POSTGRESQL_PASSWORD=password \
   -e POSTGRESQL_MAX_CONNECTIONS=500 \
   --pod=quay-pod \
   --conmon-pidfile %t/%n-pid \
   --cidfile %t/%n-cid \
   --cgroups=no-conmon \
   --replace \
   registry.redhat.io/rhel9/postgresql-16:9.7
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/%n-cid -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/%n-cid
PIDFile=%t/%n-pid
KillMode=none
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target default.target
EOF

systemctl daemon-reload
systemctl start quay-postgres

sleep 10

podman exec -it quay-postgres psql
...
postgres=# \l                # <--- to list all databases
postgres=# \c quay
You are now connected to database "quay" as user "postgres".
quay=# CREATE EXTENSION pg_trgm;
CREATE EXTENSION
quay=# exit




