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
_ramSize=$(($_ramSize * 1024))

# check if _instances is null or string than parse it as number
if [ -z "$_instances" ]; then
    _instances=0
elif ! [[ "$_instances" =~ ^[0-9]+$ ]]; then
    echo "INSTANCES value is: '$INSTANCES'"
    _instances=0
fi

if [ $_instances -gt 1 ]; then
    for i in $(seq 1 $_instances); do
        _random_mac=$(printf 'DE:AD:BE:EF:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)))
        cp /phobos.img /phobos$i.img

        qemu-img resize -f raw /phobos$i.img +${_hdSize}G

        qemu-system-x86_64 \
            -name "PhobOS Emulator" \
            $(if [ "$NO_KVM" != "1" ]; then echo "-cpu host"; else echo "-cpu qemu64"; fi) \
            -smp 4 \
            --netdev bridge,id=hn0,br=docker0 \
            -device virtio-net-pci,netdev=hn0,id=nic1,mac=$_random_mac \
            -machine pc \
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

    while [ $(ps aux | grep qemu-system-x86_64 | wc -l) -gt 1 ]; do
        sleep 15
    done

    exit 0
fi

echo "Starting PhobOS Emulator, please wait ..."

_random_mac=$(printf 'DE:AD:BE:EF:%02X:%02X' $((RANDOM%256)) $((RANDOM%256)))
qemu-img resize -f raw /phobos.img +${_hdSize}G

qemu-system-x86_64 \
    -name "PhobOS Emulator" \
    $(if [ "$NO_KVM" != "1" ]; then echo "-cpu host"; else echo "-cpu qemu64"; fi) \
    -smp 4 \
    --netdev bridge,id=hn0,br=docker0 \
    -device virtio-net-pci,netdev=hn0,id=nic1,mac=$_random_mac \
    -machine pc \
    -vga none \
    -device virtio-gpu-pci \
    -device virtio-tablet-pci \
    -display gtk,zoom-to-fit=off \
    -m $_ramSize \
    -drive file=/phobos.img,format=raw \
    -bios /usr/share/ovmf/OVMF.fd \
    -serial mon:stdio \
    $(if [ "$NO_KVM" != "1" ]; then echo "-enable-kvm"; fi)
