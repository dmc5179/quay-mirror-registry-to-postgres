#!/bin/bash

# TODO: Different args if root or non-root

QUAY_ROOT=/home/ec2-user/quay

SYSTEMCTL="systemctl"
SERVICE_FILE="/usr/lib/systemd/system/quay-postgres.service"

if [ "$(id -u)" -ne 0 ]
then
    SYSTEMCTL="systemctl --user"
    SERVICE_FILE="${HOME}/.config/systemd/user/quay-postgres.service"
else
fi

${SYSTEMCTL} stop quay-app.service

sleep 5

mkdir -pv ${QUAY_ROOT}/postgres
# chmod 26:26 ${QUAY_ROOT}/postgres  # set proper permissions
podman pull registry.redhat.io/rhel9/postgresql-16:9.7

cat << EOF > ${SERVICE_FILE}
[Unit]
Description=PostgreSQL Podman Container for Quay
Wants=network.target
After=network-online.target quay-pod.service
Requires=quay-pod.service

[Service]
Type=simple
TimeoutStartSec=5m
ExecStartPre=-/bin/rm -f %t/%n-pid %t/%n-cid
ExecStart=/usr/bin/podman run \\
   --name quay-postgres \\
   -v ${QUAY_ROOT}/postgres:/var/lib/pgsql/data:Z,U \\
   --image-volume=ignore \\
   -e POSTGRESQL_USER=postgres \\
   -e POSTGRESQL_DATABASE=quay \\
   -e POSTGRESQL_PASSWORD=password \\
   -e POSTGRES_MAX_CONNECTIONS=500 \\
   --pod=quay-pod \\
   --conmon-pidfile %t/%n-pid \\
   --cidfile %t/%n-cid \\
   --cgroups=no-conmon \\
   --replace \\
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

${SYSTEMCTL} daemon-reload
${SYSTEMCTL} start quay-postgres

sleep 15

podman exec -it postgre psql -U postgres -d quay -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

${SYSTEMCTL} enable quay-postgres

