#!/bin/bash

# TODO: Different args if root or non-root
#
# Assumes the following install command as a non-root user
# mirror-registry install --quayRoot /home/ec2-user/quay-root --quayStorage /home/ec2-user/quay-root/data --sqliteStorage /home/ec2-user/quay-root/sqlite
#
#

POSTGRESQL_USER=postgres
POSTGRESQL_DATABASE=quay
POSTGRESQL_PASSWORD=password

QUAY_ROOT=/home/ec2-user/quay-root

SYSTEMCTL="systemctl"
SERVICE_FILE="/usr/lib/systemd/system/quay-postgres.service"

if [ "$(id -u)" -ne 0 ]
then
    SYSTEMCTL="systemctl --user"
    SERVICE_FILE="${HOME}/.config/systemd/user/quay-postgres.service"
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
   -e POSTGRESQL_USER=${POSTGRESQL_USER} \\
   -e POSTGRESQL_DATABASE=${POSTGRESQL_DATABASE} \\
   -e POSTGRESQL_PASSWORD=${POSTGRESQL_PASSWORD} \\
   -e POSTGRES_MAX_CONNECTIONS=500 \\
   --pod=quay-pod \\
   --conmon-pidfile %t/%n-pid \\
   --cidfile %t/%n-cid \\
   --cgroups=no-conmon \\
   --pull missing \\
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

sleep 30 # Sometimes it takes a long time for it to show up and start

podman exec -it quay-postgres psql -U postgres -c "CREATE DATABASE quay;" || true  # don't fail if already exists

podman exec -it quay-postgres psql -U postgres -d quay -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

${SYSTEMCTL} enable quay-postgres

cp -a ${QUAY_ROOT}/quay-config/config.yaml ${QUAY_ROOT}/quay-config/config.yaml.orig

# RHEL 9 yq appears not to support the args substitution commands.....
#yq -y --arg val "postgresql://postgres:password@quay-postgres/quay" '.DB_URI = $val' ${QUAY_ROOT}/quay-config/config.yaml
sed -i "s/DB_URI:.*/DB_URI: postgresql:\/\/${POSTGRESQL_USER}:${POSTGRESQL_PASSWORD}@quay-postgres\/${POSTGRESQL_DATABASE}/" ${QUAY_ROOT}/quay-config/config.yaml

#### Add args to config.yaml
# TODO: Did this work ok??
cat << 'EOF' >> ${QUAY_ROOT}/quay-config/config.yaml
DB_CONNECTION_ARGS:
 max_connections: 5
 stale_timeout: 120
EOF

# TODO: Script this out
# Since this is not scripted yet, this block is commented out since it must be done manually
##### Update quay-app.service  #####
#   -e WORKER_COUNT_UNSUPPORTED_MINIMUM=1 \          # <--- remove this line
#   -e WORKER_COUNT=1 \                              # <--- remove this line
#   -e WORKER_COUNT_WEB=4 \                          # <--- add this line
#   -e WORKER_COUNT_REGISTRY=8 \                     # <--- add this line
#   -e WORKER_COUNT_SECSCAN=2 \                      # <--- add this line
##################################

#${SYSTEMCTL} daemon-reload
#${SYSTEMCTL} start quay-app.service

#sleep 20

#
#
#curl -I https://BASTION_HOST:8443/v2/
#curl -v https://BASTION_HOST:8443/health/instance

