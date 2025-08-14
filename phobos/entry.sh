#!/bin/bash

set -e

_IMAGE_VERSION="0.0.6"

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

# to download the image from the magalu objects
if [ "$1" == "image-download" ]; then
    # check if the /host/phobos.img file
    # if not we need to download it
    # and extract it
    if [ ! -f /host/phobos-${_IMAGE_VERSION}.img ]; then
        echo "phobos.img file not found!"
        echo "Downloading it ..."

        IMAGE_ARCH=$(arch)
        MACHINE=""

        if [ "${IMAGE_ARCH}" = "x86_64" ]; then
            MACHINE="qemux86-64"; \
        elif [ "${IMAGE_ARCH}" = "aarch64" ]; then
            MACHINE="qemuarm64"; \
        else
            echo "Unsupported architecture: ${IMAGE_ARCH}";
            exit 69
        fi

        curl -L -o img.tar.xz \
            https://br-se1.magaluobjects.com/gaia-imgs/${MACHINE}-ota-0-0-0.img.tar.xz
        tar -xf img.tar.xz
        rm img.tar.xz
        mv ${MACHINE}-ota-0-0-0.img /host/phobos.img

        # for arm64 we will need also the bios
        if [ "${IMAGE_ARCH}" = "aarch64" ]; then
            curl -L -o u-boot.bin \
                https://br-se1.magaluobjects.com/gaia-imgs/u-boot.bin

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
_ramSize=$(printf "%.0f" $RAM)
_instances=$INSTANCES
_name=$USER_VM_NAME
_ramSize=$(($_ramSize * 1024))

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

# set by arch
_ARCH=$(arch)
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
qemu-img resize -f raw $_name +${_hdSize}G

$_QEMU_CMD \
    -name "PhobOS Emulator" \
    $(if [ "$NO_KVM" != "1" ]; then echo "-cpu host"; fi) \
    $(if [ "$NO_KVM" == "1" ]; then echo "-cpu max"; fi) \
    -smp 4 \
    --netdev bridge,id=hn0,br=docker0 \
    -device virtio-net-pci,netdev=hn0,id=nic1,mac=$_random_mac \
    -machine $_MACHINE \
    -vga none \
    -device virtio-gpu-pci \
    -device virtio-tablet-pci \
    -display gtk,zoom-to-fit=off \
    -m $_ramSize \
    -drive file=$_name,format=raw,if=virtio \
    $(if [ "$_ARCH" == "x86_64" ]; then echo "-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd"; fi) \
    $(if [ "$_ARCH" == "x86_64" ]; then echo "-drive if=pflash,format=raw,file=/tmp/OVMF_VARS.fd"; fi) \
    $(if [ "$_ARCH" == "aarch64" ]; then echo "-bios /host/u-boot.bin"; fi) \
    -chardev socket,id=chrtpm,path=/tmp/pemsafe/swtpm-sock \
    -tpmdev emulator,id=tpm0,chardev=chrtpm \
    $(if [ "$_ARCH" == "x86_64" ]; then echo "-device tpm-tis,tpmdev=tpm0"; fi) \
    $(if [ "$_ARCH" == "aarch64" ]; then echo "-device tpm-tis-device,tpmdev=tpm0"; fi) \
    -serial mon:stdio \
    $(if [ "$NO_KVM" != "1" ]; then echo "-enable-kvm"; fi)
