#!/bin/bash
set -ex

yum install -y bc

DATA_DIR=/var/lib/containerd/devmapper
POOL_NAME=devpool

mkdir -p ${DATA_DIR}

# Create data file
sudo touch "${DATA_DIR}/data"
sudo truncate -s 100G "${DATA_DIR}/data"

# Create metadata file
sudo touch "${DATA_DIR}/meta"
sudo truncate -s 10G "${DATA_DIR}/meta"

# Allocate loop devices
DATA_DEV=$(sudo losetup --find --show "${DATA_DIR}/data")
META_DEV=$(sudo losetup --find --show "${DATA_DIR}/meta")

# Define thin-pool parameters.
# See https://www.kernel.org/doc/Documentation/device-mapper/thin-provisioning.txt for details.
SECTOR_SIZE=512
DATA_SIZE="$(sudo blockdev --getsize64 -q ${DATA_DEV})"
LENGTH_IN_SECTORS=$(bc <<< "${DATA_SIZE}/${SECTOR_SIZE}")
DATA_BLOCK_SIZE=128
LOW_WATER_MARK=32768

# Create a thin-pool device
sudo dmsetup create "${POOL_NAME}" \
    --table "0 ${LENGTH_IN_SECTORS} thin-pool ${META_DEV} ${DATA_DEV} ${DATA_BLOCK_SIZE} ${LOW_WATER_MARK}"

# Determine plugin name based on containerd config version
CONFIG_VERSION=$(containerd config dump | awk '/^version/ {print $3}')
if [ "$CONFIG_VERSION" -ge 2 ]; then
    PLUGIN="io.containerd.snapshotter.v1.devmapper"
else
    PLUGIN="devmapper"
fi

cat >> /etc/containerd/config.toml << EOF

[plugins."io.containerd.cri.v1.images".runtime_platforms.kata-fc]
  snapshotter = "devmapper"

[plugins."io.containerd.grpc.v1.cri".containerd]
  discard_unpacked_layers = false

[plugins."${PLUGIN}"]
  pool_name = "${POOL_NAME}"
  root_path = "${DATA_DIR}"
  base_image_size = "10GB"
  discard_blocks = true
EOF

systemctl restart containerd

cat > /usr/local/bin/init-devmapper-pool.sh <<-EOF
#!/bin/bash
set -ex

DATA_DIR=/var/lib/containerd/devmapper
POOL_NAME=devpool

# Allocate loop devices
DATA_DEV=$(sudo losetup --find --show "${DATA_DIR}/data")
META_DEV=$(sudo losetup --find --show "${DATA_DIR}/meta")

# Define thin-pool parameters.
# See https://www.kernel.org/doc/Documentation/device-mapper/thin-provisioning.txt for details.
SECTOR_SIZE=512
DATA_SIZE="$(sudo blockdev --getsize64 -q ${DATA_DEV})"
LENGTH_IN_SECTORS=$(bc <<< "${DATA_SIZE}/${SECTOR_SIZE}")
DATA_BLOCK_SIZE=128
LOW_WATER_MARK=32768

# Create a thin-pool device
sudo dmsetup create "${POOL_NAME}" \
    --table "0 ${LENGTH_IN_SECTORS} thin-pool ${META_DEV} ${DATA_DEV} ${DATA_BLOCK_SIZE} ${LOW_WATER_MARK}"
EOF

chmod +x /usr/local/bin/init-devmapper-pool.sh

cat > /lib/systemd/system/devmapper_reload.service <<EOF
[Unit]
Description=Devmapper reload script

[Service]
ExecStart=/usr/local/bin/init-devmapper-pool.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable devmapper_reload.service
