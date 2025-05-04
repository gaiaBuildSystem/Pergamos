#!/bin/bash

if [ "$1" == "dhcp" ]; then
    echo "Starting DHCP server ..."

    touch /var/lib/dhcp/dhcpd.leases
    /usr/sbin/dhcpd -d --no-pid

    exit 0
fi

chmod +s /usr/lib/qemu/qemu-bridge-helper
mkdir /etc/qemu
echo "allow docker0" > /etc/qemu/bridge.conf

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
    _name="/phobos.img"
else
    _name="/root/.pem/phobos-$USER_VM_NAME.img"

    # check if the file exists
    if [ ! -f "$_name" ]; then
        echo "File $_name not found, first time running it ..."
        cp /phobos.img $_name
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
    _MACHINE=pc
    _CPU=host
elif [ "$_ARCH" == "aarch64" ]; then
    _QEMU_CMD=qemu-system-aarch64
    _MACHINE="virt,highmem=off"
    _CPU=host
else
    echo "Unsupported architecture: $_ARCH"
    exit 1
fi

if [ $_instances -gt 1 ]; then
    for i in $(seq 1 $_instances); do
        _random_mac=$(printf 'DE:AD:BE:EF:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)))
        cp /phobos.img /phobos$i.img

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
    -drive file=$_name,format=raw \
    -bios /usr/share/ovmf/OVMF.fd \
    -serial mon:stdio \
    $(if [ "$NO_KVM" != "1" ]; then echo "-enable-kvm"; fi)
