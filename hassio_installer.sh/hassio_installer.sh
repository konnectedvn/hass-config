#!/usr/bin/env bash
set -e

function info { echo -e "[Info] $*"; }
function error { echo -e "[Error] $*"; exit 1; }
function warn  { echo -e "[Warning] $*"; }

warn "This installer is supported by Konnect ED Vietnam."
warn ""
warn "Home Assistant might work today, tomorrow maybe not."
warn ""
warn "If you want more control over your own system, run"
warn "Home Assistant as a VM or run Home Assistant Core"
warn "via a Docker container."
warn ""
warn "konnectED.vn modified version 25 Sep 2020"
info ""
info "Original script:"
info "https://github.com/home-assistant/supervised-installer"

ARCH=$(uname -m)
info "Your server structure: ${ARCH}"

IP_ADDRESS=$(hostname -I | awk '{ print $1 }')

DOCKER_BINARY=/usr/bin/docker
DOCKER_REPO=homeassistant
SERVICE_DOCKER=docker.service
SERVICE_NM="NetworkManager.service"
DOCKER_DAEMON_CONFIG=/etc/docker/daemon.json

FILE_NM_CONF="/etc/NetworkManager/NetworkManager.conf"
FILE_NM_CONNECTION="/etc/NetworkManager/system-connections/default"

URL_RAW_BASE="https://raw.githubusercontent.com/home-assistant/supervised-installer/master/files"
URL_VERSION="https://version.home-assistant.io/stable.json"
URL_NM_CONF="${URL_RAW_BASE}/NetworkManager.conf"
URL_NM_CONNECTION="${URL_RAW_BASE}/system-connection-default"
URL_HA="${URL_RAW_BASE}/ha"
URL_BIN_HASSIO="${URL_RAW_BASE}/hassio-supervisor"
URL_BIN_APPARMOR="${URL_RAW_BASE}/hassio-apparmor"
URL_SERVICE_HASSIO="${URL_RAW_BASE}/hassio-supervisor.service"
URL_SERVICE_APPARMOR="${URL_RAW_BASE}/hassio-apparmor.service"
URL_APPARMOR_PROFILE="https://version.home-assistant.io/apparmor.txt"
URL_UPDATER="https://raw.githubusercontent.com/konnectedvn/hass-config/master/hassio_installer.sh/updater.json"
# Check env
command -v systemctl > /dev/null 2>&1 || error "Only systemd is supported!"
command -v docker > /dev/null 2>&1 || error "Please install docker first"
command -v jq > /dev/null 2>&1 || error "Please install jq first"
command -v curl > /dev/null 2>&1 || error "Please install curl first"
command -v avahi-daemon > /dev/null 2>&1 || error "Please install avahi first"
command -v dbus-daemon > /dev/null 2>&1 || error "Please install dbus first"
command -v nmcli > /dev/null 2>&1 || error "Please install NetworkManager first"
command -v apparmor_parser > /dev/null 2>&1 || warn "No AppArmor support on host."


# Check if Modem Manager is enabled
if systemctl list-unit-files ModemManager.service | grep enabled; then
    warn "ModemManager service is enabled. This might cause issue when using serial devices."
fi

# Detect wrong docker logger config
if [ ! -f "$DOCKER_DAEMON_CONFIG" ]; then
  # Write default configuration
  info "Creating default docker deamon configuration $DOCKER_DAEMON_CONFIG"
  cat > "$DOCKER_DAEMON_CONFIG" <<- EOF
    {
        "log-driver": "journald",
        "storage-driver": "overlay2"
    }
EOF
  # Restart Docker service
  info "Restarting docker service"
  systemctl restart "$SERVICE_DOCKER"
else
  STORRAGE_DRIVER=$(docker info -f "{{json .}}" | jq -r -e .Driver)
  LOGGING_DRIVER=$(docker info -f "{{json .}}" | jq -r -e .LoggingDriver)
  if [[ "$STORRAGE_DRIVER" != "overlay2" ]]; then 
    warn "Docker is using $STORRAGE_DRIVER and not 'overlay2' as the storrage driver, this is not supported."
  fi
  if [[ "$LOGGING_DRIVER"  != "journald" ]]; then 
    warn "Docker is using $LOGGING_DRIVER and not 'journald' as the logging driver, this is not supported."
  fi
fi

# Check dmesg access
if [[ "$(sysctl --values kernel.dmesg_restrict)" != "0" ]]; then
    info "Fix kernel dmesg restriction"
    echo 0 > /proc/sys/kernel/dmesg_restrict
    echo "kernel.dmesg_restrict=0" >> /etc/sysctl.conf
fi

# Create config for NetworkManager
info "Creating NetworkManager configuration"
rm -f /etc/network/interfaces
curl -sL "${URL_NM_CONF}" > "${FILE_NM_CONF}"
if [ ! -f "$FILE_NM_CONNECTION" ]; then
    curl -sL "${URL_NM_CONNECTION}" > "${FILE_NM_CONNECTION}"
fi
info "Restarting NetworkManager"
systemctl restart "${SERVICE_NM}"

# Parse command line parameters
while [[ $# -gt 0 ]]; do
    arg="$1"

    case $arg in
        -m|--machine)
            MACHINE=$2
            shift
            ;;
        -d|--data-share)
            DATA_SHARE=$2
            shift
            ;;
        -p|--prefix)
            PREFIX=$2
            shift
            ;;
        -s|--sysconfdir)
            SYSCONFDIR=$2
            shift
            ;;
        *)
            error "Unrecognized option $1"
            ;;
    esac
    shift
done

PREFIX=${PREFIX:-/usr}
SYSCONFDIR=${SYSCONFDIR:-/etc}
DATA_SHARE=${DATA_SHARE:-$PREFIX/share/hassio}
CONFIG=$SYSCONFDIR/hassio.json

# Generate hardware options
case $ARCH in
    "i386" | "i686")
        MACHINE=${MACHINE:=qemux86}
        HOMEASSISTANT_DOCKER="$DOCKER_REPO/$MACHINE-homeassistant"
        HASSIO_DOCKER="$DOCKER_REPO/i386-hassio-supervisor"
    ;;
    "x86_64")
        MACHINE=${MACHINE:=qemux86-64}
        HOMEASSISTANT_DOCKER="$DOCKER_REPO/$MACHINE-homeassistant"
        HASSIO_DOCKER="$DOCKER_REPO/amd64-hassio-supervisor"
    ;;
    "arm" |"armv6l")
        if [ -z $MACHINE ]; then
            error "Please set machine for $ARCH"
        fi
        HOMEASSISTANT_DOCKER="$DOCKER_REPO/$MACHINE-homeassistant"
        HASSIO_DOCKER="$DOCKER_REPO/armhf-hassio-supervisor"
    ;;
    "armv7l")
        if [ -z $MACHINE ]; then
            error "Please set machine for $ARCH"
        fi
        HOMEASSISTANT_DOCKER="$DOCKER_REPO/$MACHINE-homeassistant"
        HASSIO_DOCKER="$DOCKER_REPO/armv7-hassio-supervisor"
    ;;
    "aarch64")
        if [ -z $MACHINE ]; then
            error "Please set machine for $ARCH"
        fi
        HOMEASSISTANT_DOCKER="$DOCKER_REPO/$MACHINE-homeassistant"
        HASSIO_DOCKER="$DOCKER_REPO/aarch64-hassio-supervisor"
    ;;
    *)
        error "$ARCH unknown!"
    ;;
esac

if [ -z "${HOMEASSISTANT_DOCKER}" ]; then
    error "Found no Home Assistant Docker images for this host!"
    error "uname -m to get machine structure"
    error "for x86_64 use -m qemux86-64"
    error "https://konnected.vn/home-assistant/home-assistant-cai-dat-tren-docker-2020-03-20#ftoc-chay-script-cai-dat-voi-tuy-chon"
fi

if [[ ! "intel-nuc odroid-c2 odroid-n2 odroid-xu qemuarm qemuarm-64 qemux86 qemux86-64 raspberrypi raspberrypi2 raspberrypi3 raspberrypi4 raspberrypi3-64 raspberrypi4-64 tinker" = *"${MACHINE}"* ]]; then
    error "Unknown machine type ${MACHINE}!"
fi

### Main

# Init folders
if [ ! -d "$DATA_SHARE" ]; then
    mkdir -p "$DATA_SHARE"
fi

# Read infos from web
HASSIO_VERSION=$(curl -s $URL_VERSION | jq -e -r '.supervisor')

##
# Write configuration
cat > "$CONFIG" <<- EOF
{
    "supervisor": "${HASSIO_DOCKER}",
    "homeassistant": "${HOMEASSISTANT_DOCKER}",
    "data": "${DATA_SHARE}"
}
EOF
#Konnected.vn
echo "[Info] Pre-set version of Supervisor component"
echo "[Info] Modified by KonnectED.vn"
curl -sL ${URL_UPDATER} > "${DATA_SHARE}/updater.json"
sed -i "s/{machine}/${MACHINE}/g" "${DATA_SHARE}/updater.json"
#sed -i "s/{arch}/${ARCH}/g" "${DATA_SHARE}/updater.json"
#
# Pull supervisor image
echo "[Info] Install supervisor Docker container"
docker pull "$HASSIO_DOCKER:$HASSIO_VERSION" > /dev/null
docker tag "$HASSIO_DOCKER:$HASSIO_VERSION" "$HASSIO_DOCKER:latest" > /dev/null

##
# Install Hass.io Supervisor
echo "[Info] Install supervisor startup scripts"
curl -sL ${URL_BIN_HASSIO} > "${PREFIX}/sbin/hassio-supervisor"
curl -sL ${URL_SERVICE_HASSIO} > "${SYSCONFDIR}/systemd/system/hassio-supervisor.service"

sed -i "s,%%HASSIO_CONFIG%%,${CONFIG},g" "${PREFIX}"/sbin/hassio-supervisor
sed -i -e "s,%%BINARY_DOCKER%%,${DOCKER_BINARY},g" \
       -e "s,%%SERVICE_DOCKER%%,${SERVICE_DOCKER},g" \
       -e "s,%%BINARY_HASSIO%%,${PREFIX}/sbin/hassio-supervisor,g" \
       "${SYSCONFDIR}/systemd/system/hassio-supervisor.service"

chmod a+x "${PREFIX}/sbin/hassio-supervisor"
systemctl enable hassio-supervisor.service

#
# Install Hass.io AppArmor
if command -v apparmor_parser > /dev/null 2>&1; then
    echo "[Info] Install AppArmor scripts"
    mkdir -p "${DATA_SHARE}/apparmor"
    curl -sL ${URL_BIN_APPARMOR} > "${PREFIX}/sbin/hassio-apparmor"
    curl -sL ${URL_SERVICE_APPARMOR} > "${SYSCONFDIR}/systemd/system/hassio-apparmor.service"
    curl -sL ${URL_APPARMOR_PROFILE} > "${DATA_SHARE}/apparmor/hassio-supervisor"

    sed -i "s,%%HASSIO_CONFIG%%,${CONFIG},g" "${PREFIX}/sbin/hassio-apparmor"
    sed -i -e "s,%%SERVICE_DOCKER%%,${SERVICE_DOCKER},g" \
	   -e "s,%%HASSIO_APPARMOR_BINARY%%,${PREFIX}/sbin/hassio-apparmor,g" \
	   "${SYSCONFDIR}/systemd/system/hassio-apparmor.service"

    chmod a+x "${PREFIX}/sbin/hassio-apparmor"
    systemctl enable hassio-apparmor.service
    systemctl start hassio-apparmor.service
fi

##
# Init system
echo "[Info] Run Hass.io"
systemctl start hassio-supervisor.service

##
# Setup CLI
echo "[Info] Install cli 'ha'"
curl -sL ${URL_HA} > "${PREFIX}/bin/ha"
chmod a+x "${PREFIX}/bin/ha"

info
info "Home Assistant supervised is now installed"
info "First setup will take some time, when it's ready you can reach it here:"
info "http://${IP_ADDRESS}:8123"
info
warn "You may need to reboot the system to install Core"
info "docker ps -a"
info " to find out if Core is installed or not"