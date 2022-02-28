#!/bin/bash
set -euo pipefail


function assemble_chroot()
{
    local chroot_mount="$1"

    # Mount the specials in the chroot
    mount --bind /dev "${chroot_mount}"/dev -v
    mount proc "${chroot_mount}"/proc --types proc -v
    mount sys "${chroot_mount}"/sys --types sysfs -v
    mount none "${chroot_mount}"/dev/pts --types devpts -v
    mount --bind /run "${chroot_mount}"/run -v
    mount tmp "${chroot_mount}"/tmp --types tmpfs --options mode=1777 -v

    # Use the host resolver config so the chroot has connectivity
    override_chroot_resolver "${chroot_mount}"

    # Make sure apt install can work correctly in the chroot
    override_chroot_apt "${chroot_mount}"
}

function dismantle_chroot()
{
    local chroot_mount="$1"
    if [[ -z "${chroot_mount}" ]]; then
        return 1
    fi

    # Undo chroot apt config override
    restore_chroot_apt "${chroot_mount}"

    # Undo chroot resolveconf override
    restore_chroot_resolver "${chroot_mount}"
    sync

    # Unmount chroot special mounts
    for mnt in "${chroot_mount}"/proc "${chroot_mount}"/sys "${chroot_mount}"/dev/pts "${chroot_mount}"/run "${chroot_mount}"/tmp "${chroot_mount}"/dev; do
        while mountpoint --quiet "${mnt}" && ! umount --recursive "${mnt}"; do
            sleep 1
        done
    done
}

function override_chroot_apt()
{
    local chroot_mount="$1"

    chroot "${chroot_mount}" dbus-uuidgen > "${chroot_mount}"/etc/machine-id
    ln -fs /etc/machine-id "${chroot_mount}"/var/lib/dbus/machine-id
    chroot "${chroot_mount}" dpkg-divert --local --rename --add /sbin/initctl
    ln -fs /bin/true "${chroot_mount}"/sbin/initctl
}

function restore_chroot_apt()
{
    local chroot_mount="$1"

    if [[ -e "${chroot_mount}"/etc/machine-id ]]; then
        truncate -s 0 "${chroot_mount}"/etc/machine-id
    fi
    chroot "${chroot_mount}" dpkg-divert --rename --remove /sbin/initctl || true
    rm --force "${chroot_mount}"/sbin/initctl
}

function override_chroot_resolver()
{
    local chroot_mount="$1"

    # Use the host resolver config so the chroot has connectivity
    mv ${chroot_mount}/etc/resolv.conf ${chroot_mount}/etc/resolv.conf.orig
    cp --dereference --force /etc/resolv.conf "${chroot_mount}"/etc/resolv.conf
}

function restore_chroot_resolver()
{
    local chroot_mount="$1"

    # Fix resolv.conf in the chroot
    if [[ -e "${chroot_mount}"/etc ]]; then
        (
            cd "${chroot_mount}"/etc
            rm --one-file-system --force resolv.conf
            if [[ -e resolv.conf.orig ]]; then
                mv resolv.conf.orig resolv.conf
            else
                ln -s ../run/systemd/resolve/stub-resolv.conf resolv.conf
            fi
        )
    fi
}

function mount_image()
{
    local image_file="$1"
    if ! losetup --all --output NAME,BACK-FILE | grep -q "${image_file}"; then
        losetup --find --partscan "${image_file}"
    fi
    lodev=$(losetup --associated "${image_file}" --noheadings --output NAME)

    # Workaround udev not existing in container, so we need to create the partition devices manually
    major_min=$(lsblk --noheadings --output NAME,MAJ:MIN  --list ${lodev} | grep $(basename ${lodev})p1 | awk '{print $2}' | tr ':' ' ')
    mknod ${lodev}p1 b ${major_min}
    major_min=$(lsblk --noheadings --output NAME,MAJ:MIN  --list ${lodev} | grep $(basename ${lodev})p2 | awk '{print $2}' | tr ':' ' ')
    mknod ${lodev}p2 b ${major_min}

    echo -n "${lodev}"
}

function mount_lodev_chroot()
{
    local chroot_mount="$1"
    local lodev=$2

    mount --options rw ${lodev}p2 "${chroot_mount}"
    mkdir --parents "${chroot_mount}"/boot/firmware
    mount --options rw ${lodev}p1 "${chroot_mount}"/boot/firmware
}

function unmount_lodev_chroot()
{
    local chroot_mount="$1"

    for mnt in "${chroot_mount}"/boot/firmware "${chroot_mount}"; do
        while mountpoint --quiet "${mnt}" && ! umount --recursive "${mnt}"; do
            sleep 1
        done
    done
}
function unmount_image()
{
    local image_file="$1"

    lodev=$(losetup --associated "${image_file}" --noheadings --output NAME)
    if [[ -n "${lodev}" ]]; then
         losetup --detach ${lodev}
    fi
}

function _cleanup
{
    echo ">>> Cleanup image mount"
    local chroot_mount="$1"
    local lodev=$2

    set +eu
    unmount_chroot "${chroot_mount}"
    unmount_image ${lodev}
    rm --one-file-system --force --recursive "${chroot_mount}"
    exit
}

function explore_image()
{
    local image_file="$1"
    local chroot_location=/tmp/chroot

    trap "_cleanup ${chroot_location} ${image_file}" EXIT INT TERM HUP

    echo ">>> Mounting image"
    mkdir --parents "${chroot_location}"
    lodev=$(mount_image "${image_file}")
    echo ">>> Preparing chroot"
    prepare_chroot "${chroot_location}" ${lodev}
    echo ">>> Entering chroot"
    chroot "${chroot_location}" /bin/bash
}
