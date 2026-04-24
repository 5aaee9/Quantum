#!/usr/bin/env bash
set -euo pipefail

VMID_OFFSET="${VMID:-9000}"
SYSTEM_PASSWORD="${PASSWORD:-ch@ang#MeP@ssw0rd}"

# Ensure depends exist
if ! command -v jq &> /dev/null; then
    apt-get update -y
    apt-get install jq -y
fi

if [[ "${SKIP_CLEANUP_TEMPLATE:-}" == "" ]]; then
    TEMPLATE_VMID_LIST=$(pvesh get /cluster/resources --type vm --output-format json | jq ".[] | select(.template == 1) | .vmid")
    for vmid in $TEMPLATE_VMID_LIST; do
        FOUND_TEMPLATE=$(qm config $vmid | { grep description || true; } | { grep "IndexTemplate" || true; } | wc -l)
        if [[ "$FOUND_TEMPLATE" == "1" ]]; then
            echo Remove VM $vmid
            qm destroy $vmid --destroy-unreferenced-disks 1
        fi
    done
fi


find_max_available_storage() {
    pvesm status --content=images --enabled=1 | awk '
    NR > 1 {
        if (NR == 2 || $6 > max_available) {
            max_available = $6
            max_storage = $1
        }
    }
    END {
        print max_storage
    }
    '
}

if [ ! -z "${STORAGE:-}" ]; then
    VM_STORAGE="${STORAGE}"
else
    echo "Finding best storage to store driver"
    VM_STORAGE="$(find_max_available_storage)"
    
    echo "Find storage => ${VM_STORAGE}"
fi

VM_STORAGE_TYPE=$(pvesm status --content=images --enabled=1 | grep "^${VM_STORAGE}" | awk '{print $2}'  )
echo "Storage Type: $VM_STORAGE_TYPE"

import_virtual_machine() {
    download_url=$1
    name=$2
    id_index=$3

    current_id=$(($VMID_OFFSET + $id_index))

    qm create "$current_id" \
        --name "$name" \
        --memory 4096 \
        --cpu host \
        --cores 4 \
        --bios ovmf \
        --machine q35 \
        --efidisk0 "${VM_STORAGE}:0,pre-enrolled-keys=0" \
        --net0 virtio,bridge=vmbr0 \
        --scsihw virtio-scsi-pci \
        --ide2 "${VM_STORAGE}:cloudinit" \
        --serial0 socket --vga serial0 \
        --agent enabled=1 \
        --ciuser "root" \
        --cipassword "${SYSTEM_PASSWORD}" \
        --description IndexTemplate \
        --ipconfig0 ip=dhcp

    wget -O current.qcow2 "$download_url"
    
    qm importdisk "$current_id" current.qcow2 "${VM_STORAGE}" --format qcow2
    
    rm -f current.qcow2
    
    if [[ $VM_STORAGE_TYPE == "zfspool" ]] || [[ $VM_STORAGE_TYPE == "lvmthin" ]]; then
        qm set "$current_id" \
            --scsi0 "${VM_STORAGE}:vm-$current_id-disk-1,discard=on" \
            --boot c --bootdisk scsi0
    elif [[ $VM_STORAGE_TYPE == "btrfs" ]]; then
        # BTRFS disk is raw format even import with qcow2 flag
        qm set "$current_id" \
            --scsi0 "${VM_STORAGE}:$current_id/vm-$current_id-disk-1.raw,discard=on" \
            --boot c --bootdisk scsi0
    else 
        qm set "$current_id" \
            --scsi0 "${VM_STORAGE}:$current_id/vm-$current_id-disk-1.qcow2,discard=on" \
            --boot c --bootdisk scsi0
    fi
    
    qm template "$current_id"
}

import_virtual_machine "https://alist.indexyz.me/d/Local/VirtualMachineImages/debian-11.qcow2" "Debian-11" 0
import_virtual_machine "https://alist.indexyz.me/d/Local/VirtualMachineImages/debian-12.qcow2" "Debian-12" 1
import_virtual_machine "https://alist.indexyz.me/d/Local/VirtualMachineImages/debian-13.qcow2" "Debian-13" 2
import_virtual_machine "https://alist.indexyz.me/d/Local/VirtualMachineImages/debian-testing.qcow2" "Debian-Testing" 3
import_virtual_machine "https://alist.indexyz.me/d/Local/VirtualMachineImages/almalinux-8.qcow2" "AlmaLinux-8" 4
import_virtual_machine "https://alist.indexyz.me/d/Local/VirtualMachineImages/almalinux-9.qcow2" "AlmaLinux-9" 5
import_virtual_machine "https://alist.indexyz.me/d/Local/VirtualMachineImages/ubuntu-24_04.qcow2" "Ubuntu-24.04" 6
import_virtual_machine "https://alist.indexyz.me/d/Local/VirtualMachineImages/ubuntu-26_04.qcow2" "Ubuntu-26.04" 7
import_virtual_machine "https://alist.indexyz.me/d/Local/VirtualMachineImages/archlinux.qcow2" "ArchLinux" 8

if [ ! -z "${WITH_APP_IMAGES:-}" ]; then
    import_virtual_machine "https://alist.indexyz.me/d/Local/VirtualMachineImages/vibe-coding.qcow2" "Vibe-Coding" 50
fi
