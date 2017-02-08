#!/bin/bash
#
# Copyright (C) 2016 Canonical Ltd
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -e

if [ $(id -u) -ne 0 ] ; then
	echo "ERROR: needs to be executed as root"
	exit 1
fi

model=pc
arch=amd64
if [ ! -z "$1" ] ; then
    model=$1
    if [ "$model" = "pc" ] ; then
        arch=amd64
    elif [ "$model" = "pi2" ] ; then
        arch=armhf
    elif [ "$model" = "pi3" ] ; then
        arch=armhf
    elif [ "$model" = "dragonboard" ] ; then
        arch=arm64
    else
        echo "Model can either be pc|pi2|pi3|dragonboard"
        exit 1
    fi
fi

channel=candidate
if [ ! -z "$2" ] ; then
	channel=$2
fi

# Optionally provide the snap file you want pre-built into the image
# as third parameter.
snap=
if [ ! -z "$3" ] ; then
	snap=$3
fi

image_name=ubuntu-core-16-$model-$arch.img
ubuntu_image_extra_args=

if [ ! -z "$snap" ] ; then
	ubuntu_image_extra_args="--extra-snaps $snap"
fi

ubuntu-image \
	--channel $channel \
	-o $image_name \
	--image-size 4G \
	$ubuntu_image_extra_args \
	$model.model

kpartx -a $image_name
sleep 0.5

loop_path=`findfs LABEL=writable`
tmp_mount=`mktemp -d`

mount $loop_path $tmp_mount

# Migrate all systemd units from core snap into the writable area. This
# would be normally done on firstboot by the initramfs but we can't rely
# on that because we  are adding another file in there and that will
# prevent the initramfs from transitioning any files.
core_snap=$(find $tmp_mount/system-data/var/lib/snapd/snaps -name "core_*.snap")
tmp_core=`mktemp -d`
mount $core_snap $tmp_core
mkdir -p $tmp_mount/system-data/etc/systemd
cp -rav $tmp_core/etc/systemd/* \
	$tmp_mount/system-data/etc/systemd/
umount $tmp_core
rm -rf $tmp_core

# system-user assertion which gives us our test:test user we use to
# log into the system
mkdir -p $tmp_mount/system-data/var/lib/snapd/seed/assertions
cp test-user.assertion $tmp_mount/system-data/var/lib/snapd/seed/assertions

# Disable console-conf for the first boot
mkdir -p $tmp_mount/system-data/var/lib/console-conf/
touch $tmp_mount/system-data/var/lib/console-conf/complete

# Create systemd service which is running on firstboot and sets up
# various things for us.
mkdir -p $tmp_mount/system-data/etc/systemd/system
cat << 'EOF' > $tmp_mount/system-data/etc/systemd/system/devmode-firstboot.service
[Unit]
Description=Run devmode firstboot setup
After=snapd.service snapd.socket

[Service]
Type=oneshot
ExecStart=/writable/system-data/var/lib/devmode-firstboot/run.sh
RemainAfterExit=yes
TimeoutSec=3min
EOF

mkdir -p $tmp_mount/system-data/etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/devmode-firstboot.service \
	$tmp_mount/system-data/etc/systemd/system/multi-user.target.wants/devmode-firstboot.service

mkdir $tmp_mount/system-data/var/lib/devmode-firstboot
cat << EOF > $tmp_mount/system-data/var/lib/devmode-firstboot/00-snapd-config.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
EOF

cat << 'EOF' > $tmp_mount/system-data/var/lib/devmode-firstboot/run.sh
#!/bin/bash

set -e

# Don't start again if we're already done
if [ -e /writable/system-data/var/lib/devmode-firstboot/complete ] ; then
	exit 0
fi

echo "Start devmode-firstboot $(date -Iseconds --utc)"

if [ "$(snap managed)" = "true" ]; then
	echo "System already managed, exiting"
	exit 0
fi

# no changes at all
while ! snap changes ; do
	echo "No changes yet, waiting"
	sleep 1
done

while snap changes | grep -qE '(Do|Doing) .*Initialize system state' ;  do
	echo "Initialize system state is in progress, waiting"
	sleep 1
done

if [ -n "$(snap known system-user)" ]; then
	echo "Trying to create known user"
	snap create-user --known --sudoer
fi

cp /writable/system-data/var/lib/devmode-firstboot/00-snapd-config.yaml /writable/system-data/etc/netplan

# Enable console-conf again
rm /writable/system-data/var/lib/console-conf/complete

# Mark us done
touch /writable/system-data/var/lib/devmode-firstboot/complete

# Reboot the system as its now prepared for the user
reboot
EOF

chmod +x $tmp_mount/system-data/var/lib/devmode-firstboot/run.sh

umount $tmp_mount
kpartx -d $image_name
rm -rf $tmp_mount
