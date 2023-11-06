#!/bin/bash
set -x
set -e 

source "/etc/parallelcluster/cfnconfig"

installENROOT() {

  arch=$(dpkg --print-architecture)
  curl -fSsL -O https://github.com/NVIDIA/enroot/releases/download/v3.4.1/enroot_3.4.1-1_${arch}.deb
  curl -fSsL -O https://github.com/NVIDIA/enroot/releases/download/v3.4.1/enroot+caps_3.4.1-1_${arch}.deb # optional
  sudo apt-get -q -o DPkg::Lock::Timeout=240 install -y ./enroot*.deb

  mkdir -p /scratch && chmod -R 1777 /scratch
  mkdir -p /scratch/enroot && chmod -R 1777 /scratch/enroot

  # slurm 22.05 requires pyxis to be recompiled against slurm.h so the below includes now the spank.h location
  git clone https://github.com/NVIDIA/pyxis.git /tmp/pyxis
  cd /tmp/pyxis && CFLAGS="-I /opt/slurm/include" make install

  if [ "${cfn_node_type}" == "HeadNode" ];then
    echo "include /opt/slurm/etc/plugstack.conf.d/*" > /opt/slurm/etc/plugstack.conf
    mkdir -p /opt/slurm/etc/plugstack.conf.d
    ln -sf /usr/local/share/pyxis/pyxis.conf /opt/slurm/etc/plugstack.conf.d/pyxis.conf
  fi

  rm /etc/enroot/enroot.conf
  cat > /etc/enroot/enroot.conf << EOF
#ENROOT_LIBRARY_PATH       /usr/lib/enroot
#ENROOT_SYSCONF_PATH       /etc/enroot
ENROOT_RUNTIME_PATH        /scratch/enroot/run-user-\$(id -u)
ENROOT_CONFIG_PATH         \${HOME}/enroot
ENROOT_CACHE_PATH          /scratch/enroot/cache-user-\$(id -u)
ENROOT_DATA_PATH           /scratch/enroot/data-user-\$(id -u)
#ENROOT_TEMP_PATH          \${TMPDIR:-/scratch}

# Gzip program used to uncompress digest layers.
#ENROOT_GZIP_PROGRAM        gzip

# Options passed to zstd to compress digest layers.
#ENROOT_ZSTD_OPTIONS        -1

# Options passed to mksquashfs to produce container images.
#ENROOT_SQUASH_OPTIONS      -comp lzo -noD

# Make the container root filesystem writable by default.
ENROOT_ROOTFS_WRITABLE     yes

# Remap the current user to root inside containers by default.
#ENROOT_REMAP_ROOT          no

# Maximum number of processors to use for parallel tasks (0 means unlimited).
#ENROOT_MAX_PROCESSORS      \$(nproc)

# Maximum number of concurrent connections (0 means unlimited).
#ENROOT_MAX_CONNECTIONS     10

# Maximum time in seconds to wait for connections establishment (0 means unlimited).
#ENROOT_CONNECT_TIMEOUT     30

# Maximum time in seconds to wait for network operations to complete (0 means unlimited).
#ENROOT_TRANSFER_TIMEOUT    0

# Number of times network operations should be retried.
#ENROOT_TRANSFER_RETRIES    0

# Use a login shell to run the container initialization.
#ENROOT_LOGIN_SHELL         yes

# Allow root to retain his superuser privileges inside containers.
#ENROOT_ALLOW_SUPERUSER     no

# Use HTTP for outgoing requests instead of HTTPS (UNSECURE!).
#ENROOT_ALLOW_HTTP          no

# Include user-specific configuration inside bundles by default.
#ENROOT_BUNDLE_ALL          no

# Generate an embedded checksum inside bundles by default.
#ENROOT_BUNDLE_CHECKSUM     no

# Mount the current user's home directory by default.
#ENROOT_MOUNT_HOME          no

# Restrict /dev inside the container to a minimal set of devices.
ENROOT_RESTRICT_DEV        no

# Always use --force on command invocations.
#ENROOT_FORCE_OVERRIDE      no

# SSL certificates settings:
#SSL_CERT_DIR
#SSL_CERT_FILE

# Proxy settings:
#all_proxy
#no_proxy
#http_proxy
#https_proxy
EOF

  systemctl restart slurm*
}

activateNkernels () {
  TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
  type=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/instance-type)
    if [ "p4d.24xlarge" = "$type" ] || [ "p4de.24xlarge" = "$type" ]; then
      # fix cuda in containers
      /sbin/modprobe nvidia

      if [ "$?" -eq 0 ]; then
        # Count the number of NVIDIA controllers found.
        NVDEVS=`lspci | grep -i NVIDIA`
        N3D=`echo "$NVDEVS" | grep "3D controller" | wc -l`
        NVGA=`echo "$NVDEVS" | grep "VGA compatible controller" | wc -l`

        N=`expr $N3D + $NVGA - 1`
        for i in `seq 0 $N`; do
          [ ! -f "/dev/nvidia$i" ] && mknod -m 666 /dev/nvidia$i c 195 $i || echo "/dev/nvidia$i already exists"
        done

        [ ! -f "/dev/nvidiactl" ] && mknod -m 666 /dev/nvidiactl c 195 255 || echo "/dev/nvidiactl already exists"
      fi

      /sbin/modprobe nvidia-uvm

      if [ "$?" -eq 0 ]; then
        # Find out the major device number used by the nvidia-uvm driver
        D=`grep nvidia-uvm /proc/devices | awk '{print $1}'`

        [ ! -f "/dev/nvidia-uvm" ] && mknod -m 666 /dev/nvidia-uvm c $D 0 || echo "/dev/nvidia-uvm already exists"
      fi
  fi
}

# main
# ----------------------------------------------------------------------------
main() {
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')] 70.install.enroot.pyxis.sh: START" >&2
    installENROOT
    #activateNkernels
    echo "[INFO][$(date '+%Y-%m-%d %H:%M:%S')] 70.install.enroot.pyxis.sh: STOP" >&2
}

main "$@"