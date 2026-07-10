#!/bin/bash

set -e

_IMAGE_AMD64_VERSION="0.1.0"
_IMAGE_AMD64_VERSION_DASH="0-1-0"
_IMAGE_ARM64_VERSION="0.1.1"
_IMAGE_ARM64_VERSION_DASH="0-1-1"

if [ "$1" == "dhcp" ]; then
    echo "Starting DHCP server ..."

    touch /var/lib/dhcp/dhcpd.leases
    /usr/sbin/dhcpd -d --no-pid

    exit 0
fi

# for the virtual TPM v2
if [ "$1" == "tpm2" ]; then
    echo "Starting virtual TPM v2 ..."

    # Clean state
    rm -rf /tmp/mytpm1
    rm -rf /tmp/pemsafe
    mkdir -p /tmp/pemsafe

    swtpm socket --tpmstate dir=/tmp/pemsafe \
        --ctrl type=unixio,path=/tmp/pemsafe/swtpm-sock \
        --tpm2 \
        --log level=20

    exit 0
fi


_IMAGE_VERSION=""
IMAGE_ARCH=$(arch)
MACHINE=""

if [ "${IMAGE_ARCH}" = "x86_64" ]; then
    MACHINE="qemux86-64"; \
    _IMAGE_VERSION=$_IMAGE_AMD64_VERSION
    _IMAGE_VERSION_DASH=$_IMAGE_AMD64_VERSION_DASH
elif [ "${IMAGE_ARCH}" = "aarch64" ]; then
    MACHINE="qemuarm64"; \
    _IMAGE_VERSION=$_IMAGE_ARM64_VERSION
    _IMAGE_VERSION_DASH=$_IMAGE_ARM64_VERSION_DASH
else
    echo "Unsupported architecture: ${IMAGE_ARCH}";
    exit 69
fi


# to download the image from the magalu objects
if [ "$1" == "image-download" ]; then
    # check if the /host/phobos.img file
    # if not we need to download it
    # and extract it
    if [ ! -f /host/phobos-${_IMAGE_VERSION}.img ]; then
        echo "phobos.img file not found!"
        echo "Downloading it ..."

        curl -L -o img.zip \
            https://github.com/gaiaBuildSystem/phobos-releases/releases/download/v${_IMAGE_VERSION}/PhobOS-${MACHINE}-ota-${_IMAGE_VERSION_DASH}.zip

        unzip -o img.zip
        rm img.zip
        mv PhobOS-${MACHINE}-ota-${_IMAGE_VERSION_DASH}.img /host/phobos.img

        # if there is the u-boot.bin file in the current directory, move it to /host/u-boot.bin
        if [ -f u-boot.bin ]; then
            mv u-boot.bin /host/u-boot.bin
        fi

        # lock file for the version ok
        touch /host/phobos-${_IMAGE_VERSION}.img
    fi

    exit 0
fi


chmod +s /usr/lib/qemu/qemu-bridge-helper
mkdir /etc/qemu
echo "allow docker0" > /etc/qemu/bridge.conf
cp /usr/share/OVMF/OVMF_VARS_4M.fd /tmp/OVMF_VARS.fd


_hdSize=$STORAGE
_hdSize=$(printf "%.0f" $_hdSize)
_ramSize=$(printf "%.0f" $RAM)
_instances=$INSTANCES
_name=$USER_VM_NAME
_ramSize=$(($_ramSize * 1024))

# workaround for the u-boot.bin file
# if it exists in the current directory, use it,
# otherwise use the one in the firmware directory
if [ -f /host/u-boot.bin ]; then
    _FIRMWARE_PATH="/host/u-boot.bin"
else
    _FIRMWARE_PATH="/firmware/u-boot.bin"
fi

# check if _instances is null or string than parse it as number
if [ -z "$_instances" ]; then
    _instances=0
elif ! [[ "$_instances" =~ ^[0-9]+$ ]]; then
    echo "INSTANCES value is: '$INSTANCES'"
    _instances=0
fi

# check if it comes from a user vm named
if [ -z "$_name" ] || [ "$_name" = '""' ] || [ "$_name" = "None" ]; then
    _name="/host/phobos.img"
else
    _name="/root/.pem/phobos-$USER_VM_NAME.img"

    # check if the file exists
    if [ ! -f "$_name" ]; then
        echo "File $_name not found, first time running it ..."
        cp /host/phobos.img $_name
    fi

    echo "Using $_name as the image file"
fi

# check if the PHOBOS_OVERRIDE_ARCH variable is set
if [ -n "$PHOBOS_OVERRIDE_ARCH" ]; then
    _ARCH="$PHOBOS_OVERRIDE_ARCH"
    echo "Overriding architecture to: $_ARCH"

    # if we are overriding the architecture and we are on a foreign architecture
    # we cannot use KVM, so we need to set the NO_KVM variable to 1
    if [ "$_ARCH" != "$(arch)" ]; then
        echo "Warning: Overriding architecture to $_ARCH while running on $(arch), running without KVM support."
        export NO_KVM=1
    fi
else
    _ARCH=$(arch)
    echo "Detected architecture: $_ARCH"
fi

_QEMU_CMD=qemu-system-x86_64
_MACHINE=pc
_CPU=host

if [ "$_ARCH" == "x86_64" ]; then
    _QEMU_CMD=qemu-system-x86_64
    _MACHINE="q35,smm=on"
    _CPU=host
elif [ "$_ARCH" == "aarch64" ]; then
    _QEMU_CMD=qemu-system-aarch64
    _MACHINE="virt,gic-version=3,highmem=on,highmem-redists=on"
    _CPU=host
else
    echo "Unsupported architecture: $_ARCH"
    exit 1
fi

if [ $_instances -gt 1 ]; then
    for i in $(seq 1 $_instances); do
        _random_mac=$(printf 'DE:AD:BE:EF:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)))
        cp /host/phobos.img /phobos$i.img

        qemu-img resize -f raw /phobos$i.img +${_hdSize}G

        $_QEMU_CMD \
            -name "PhobOS Emulator" \
            -cpu host \
            -smp 4 \
            --netdev bridge,id=hn0,br=docker0 \
            -device virtio-net-pci,netdev=hn0,id=nic1,mac=$_random_mac \
            -machine $_MACHINE \
            -vga none \
            -device virtio-gpu-pci \
            $(if [ "$_ARCH" == "aarch64" ]; then echo "-device virtio-keyboard-pci"; fi) \
            -device virtio-tablet-pci \
            -display gtk,zoom-to-fit=off \
            -m $_ramSize \
            -drive file=/phobos$i.img,format=raw \
            -bios /usr/share/ovmf/OVMF.fd \
            $(if [ "$NO_KVM" != "1" ]; then echo "-enable-kvm"; fi) \
            &

    done

    while [ $(ps aux | grep $_QEMU_CMD | wc -l) -gt 1 ]; do
        sleep 15
    done

    exit 0
fi

echo "Starting PhobOS Emulator, please wait ..."

_random_mac=$(printf 'DE:AD:BE:EF:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)))

# check the file size
_file_bytes=$(stat -c%s "$_name" 2>/dev/null || echo 0)
_target_bytes=$(( _hdSize * 1073741824 ))

if [ "$_file_bytes" -lt "$_target_bytes" ]; then
    _current_gb=$(awk "BEGIN {printf \"%.2f\", $_file_bytes/1073741824}")
    echo "Resizing disk image from ${_current_gb}G to ${_hdSize}G ..."
    qemu-img resize -f raw $_name ${_hdSize}G
fi

_SMBIOS_ARGS=()
if [ "$_ARCH" == "x86_64" ]; then
    _SMBIOS_ARGS+=(
        -smbios "type=1,manufacturer=MicroHobby,product=PhobOS Emulator,version=0.0,serial=VMlionkiller,uuid=5270e529-9710-4fca-ba1a-1a9a07fca3aa"
        -smbios "type=2,manufacturer=MicroHobby,product=PhobOS Emulator,version=0.0,serial=VMlionkiller"
    )
fi

$_QEMU_CMD \
    -name "PhobOS Emulator" \
    $(if [ "$NO_KVM" != "1" ]; then echo "-cpu host"; fi) \
    $(if [ "$NO_KVM" == "1" ]; then echo "-cpu max"; fi) \
    -smp 4 \
    "${_SMBIOS_ARGS[@]}" \
    --netdev bridge,id=hn0,br=docker0 \
    -device virtio-net-pci,netdev=hn0,id=nic1,mac=$_random_mac \
    -machine $_MACHINE \
    -vga none \
    -device virtio-gpu-pci \
    $(if [ "$_ARCH" == "aarch64" ]; then echo "-device virtio-keyboard-pci"; fi) \
    -device virtio-tablet-pci \
    -display gtk,zoom-to-fit=off \
    -m $_ramSize \
    -drive file=$_name,format=raw,if=virtio \
    $(if [ "$_ARCH" == "x86_64" ]; then echo "-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd"; fi) \
    $(if [ "$_ARCH" == "x86_64" ]; then echo "-drive if=pflash,format=raw,file=/tmp/OVMF_VARS.fd"; fi) \
    $(if [ "$_ARCH" == "aarch64" ]; then echo "-bios ${_FIRMWARE_PATH}"; fi) \
    -chardev socket,id=chrtpm,path=/tmp/pemsafe/swtpm-sock \
    -tpmdev emulator,id=tpm0,chardev=chrtpm \
    $(if [ "$_ARCH" == "x86_64" ]; then echo "-device tpm-tis,tpmdev=tpm0"; fi) \
    $(if [ "$_ARCH" == "aarch64" ]; then echo "-device tpm-tis-device,tpmdev=tpm0"; fi) \
    -serial mon:stdio \
    $(if [ "$NO_KVM" != "1" ]; then echo "-enable-kvm"; fi)
