#!/bin/bash

echo "========================= begin $0 ================="
source make.env
source public_funcs
init_work_env

PLATFORM=allwinner
SOC=h6
BOARD=vplus
SUBVER=$1

# Kernel image sources
###################################################################
MODULES_TGZ=${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz
check_file ${MODULES_TGZ}
BOOT_TGZ=${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz
check_file ${BOOT_TGZ}
DTBS_TGZ=${KERNEL_PKG_HOME}/dtb-allwinner-${KERNEL_VERSION}.tar.gz
check_file ${DTBS_TGZ}
###################################################################

# Openwrt 
OP_ROOT_TGZ="openwrt-armvirt-64-default-rootfs.tar.gz"
OPWRT_ROOTFS_GZ="${PWD}/${OP_ROOT_TGZ}"
check_file ${OP_ROOT_TGZ}
echo "Use $OPWRT_ROOTFS_GZ as openwrt rootfs!"

# Target Image
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# patches、scripts
####################################################################
REGULATORY_DB="${PWD}/files/regulatory.db.tar.gz"
CPUSTAT_SCRIPT="${PWD}/files/cpustat"
CPUSTAT_SCRIPT_PY="${PWD}/files/cpustat.py"
CPUSTAT_PATCH="${PWD}/files/luci-admin-status-index-html.patch"
CPUSTAT_PATCH_02="${PWD}/files/luci-admin-status-index-html-02.patch"
GETCPU_SCRIPT="${PWD}/files/getcpu"
KMOD="${PWD}/files/kmod"
KMOD_BLACKLIST="${PWD}/files/vplus/kmod_blacklist"

FIRSTRUN_SCRIPT="${PWD}/files/mk_newpart.sh"
BOOT_CMD="${PWD}/files/vplus/boot/boot.cmd"
BOOT_SCR="${PWD}/files/vplus/boot/boot.scr"

DAEMON_JSON="${PWD}/files/vplus/daemon.json"

TTYD="${PWD}/files/ttyd"
FLIPPY="${PWD}/files/scripts_deprecated/flippy_cn"
BANNER="${PWD}/files/banner"

# 20200314 add
FMW_HOME="${PWD}/files/firmware"
SMB4_PATCH="${PWD}/files/smb4.11_enable_smb1.patch"
SYSCTL_CUSTOM_CONF="${PWD}/files/99-custom.conf"

# 20200709 add
COREMARK="${PWD}/files/coremark.sh"

# 20201024 add
BAL_ETH_IRQ="${PWD}/files/balethirq.pl"
# 20201026 add
FIX_CPU_FREQ="${PWD}/files/fixcpufreq.pl"
SYSFIXTIME_PATCH="${PWD}/files/sysfixtime.patch"

# 20201128 add
SSL_CNF_PATCH="${PWD}/files/vplus/openssl_engine.patch"

# 20201212 add
BAL_CONFIG="${PWD}/files/vplus/balance_irq"

# 20210424 modify
UBOOT_BIN="${PWD}/files/vplus/u-boot-v2021.04/u-boot-sunxi-with-spl.bin"
WRITE_UBOOT_SCRIPT="${PWD}/files/vplus/u-boot-v2021.04/update-u-boot.sh"

# 20210307 add
SS_LIB="${PWD}/files/ss-glibc/lib-glibc.tar.xz"
SS_BIN="${PWD}/files/ss-glibc/ss-bin-glibc.tar.xz"
JQ="${PWD}/files/jq"

# 20210330 add
DOCKERD_PATCH="${PWD}/files/dockerd.patch"

# 20200416 add
FIRMWARE_TXZ="${PWD}/files/firmware_armbian.tar.xz"
BOOTFILES_HOME="${PWD}/files/bootfiles/allwinner"

# 20210618 add
DOCKER_README="${PWD}/files/DockerReadme.pdf"

# 20210704 add
SYSINFO_SCRIPT="${PWD}/files/30-sysinfo.sh"
FORCE_REBOOT="${PWD}/files/vplus/reboot"

# 20210923 add
OPENWRT_KERNEL="${PWD}/files/openwrt-kernel"
OPENWRT_BACKUP="${PWD}/files/openwrt-backup"
OPENWRT_UPDATE="${PWD}/files/openwrt-update-allwinner"
####################################################################

check_depends
SKIP_MB=16
BOOT_MB=160
ROOTFS_MB=720
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB))
create_image "$TGT_IMG" "$SIZE"
create_partition "$TGT_DEV" "msdos" "$SKIP_MB" "$BOOT_MB" "fat32" "0" "-1" "btrfs"
make_filesystem "$TGT_DEV" "B" "fat32" "EMMC_BOOT" "R" "btrfs" "EMMC_ROOTFS1"
mount_fs "${TGT_DEV}p1" "${TGT_BOOT}" "vfat"
mount_fs "${TGT_DEV}p2" "${TGT_ROOT}" "btrfs" "compress=zstd"
echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc
extract_rootfs_files
extract_allwinner_boot_files

echo "modify boot ... "
# modify boot
cd $TGT_BOOT
[ -f $BOOT_CMD ] && cp -v $BOOT_CMD boot.cmd
[ -f $BOOT_SCR ] && cp -v $BOOT_SCR boot.scr
rm -f boot-emmc.cmd boot-emmc.scr
cat > uEnv.txt <<EOF
LINUX=/zImage
INITRD=/uInitrd

#  普通版 1800Mhz
FDT=/dtb/allwinner/sun50i-h6-vplus-cloud.dtb
#  超频版 2016Mhz
#FDT=/dtb/allwinner/sun50i-h6-vplus-cloud-2ghz.dtb

APPEND=root=UUID=${ROOTFS_UUID} rootfstype=btrfs rootflags=compress=zstd console=ttyS0,115200n8 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF
echo "uEnv.txt"
echo "======================================================================================"
cat uEnv.txt
echo "======================================================================================"
echo

echo "modify root ... "
# modify root
cd $TGT_ROOT
( [ -f "$SS_LIB" ] &&  cd lib && tar xJf "$SS_LIB" )
if [ -f "$SS_BIN" ];then
    (
        cd usr/bin
        mkdir -p ss-bin-musl && mv -f ss-server ss-redir ss-local ss-tunnel ss-bin-musl/ 2>/dev/null
       	tar xJf "$SS_BIN"
    )
fi
if [ -f "$JQ" ] && [ ! -f "./usr/bin/jq" ];then
	cp -v ${JQ} ./usr/bin
fi

if [ -f "$FIRSTRUN_SCRIPT" ];then
	chmod 755 "$FIRSTRUN_SCRIPT"
 	cp "$FIRSTRUN_SCRIPT" ./usr/bin/ 
	mv ./etc/rc.local ./etc/rc.local.orig
	cat > ./etc/part_size <<EOF
${SKIP_MB}	${BOOT_MB}	${ROOTFS_MB}
EOF

	cat > "./etc/rc.local" <<EOF
# Put your custom commands here that should be executed once
# the system init finished. By default this file does nothing.
/usr/bin/mk_newpart.sh 1>/dev/null 2>&1
exit 0
EOF
fi

[ -f $DAEMON_JSON ] && mkdir -p "etc/docker" && cp $DAEMON_JSON "etc/docker/daemon.json"
[ -f $COREMARK ] && [ -f "etc/coremark.sh" ] && cp -f $COREMARK "etc/coremark.sh" && chmod 755 "etc/coremark.sh"
#[ -f $TTYD ] && cp $TTYD etc/init.d/
[ -f $FLIPPY ] && cp $FLIPPY usr/sbin/
[ -f ${OPENWRT_KERNEL} ] && cp ${OPENWRT_KERNEL} usr/sbin/
[ -f ${OPENWRT_BACKUP} ] && cp ${OPENWRT_BACKUP} usr/sbin/ && (cd usr/sbin && ln -sf openwrt-backup flippy)
[ -f ${OPENWRT_UPDATE} ] && cp ${OPENWRT_UPDATE} usr/sbin/

if [ -f $BAL_ETH_IRQ ];then
    cp -v $BAL_ETH_IRQ usr/sbin
    chmod 755 usr/sbin/balethirq.pl
    sed -e "/exit/i\/usr/sbin/balethirq.pl" -i etc/rc.local
    [ -f $BAL_CONFIG ] && cp -v $BAL_CONFIG etc/config/
fi

if [ -f $FIX_CPU_FREQ ];then
    cp -v $FIX_CPU_FREQ usr/sbin
    chmod 755 usr/sbin/fixcpufreq.pl
fi
if [ -f etc/config/cpufreq ];then
    sed -e "s/ondemand/schedutil/" -i etc/config/cpufreq
fi
if [ -f $SYSFIXTIME_PATCH ];then
    patch -p1 < $SYSFIXTIME_PATCH
fi
if [ -f $SSL_CNF_PATCH ];then
    patch -p1 < $SSL_CNF_PATCH
fi
if [ -f etc/init.d/dockerd ] && [ -f $DOCKERD_PATCH ];then
    patch -p1 < $DOCKERD_PATCH
fi
if [ -f usr/bin/xray-plugin ] && [ -f usr/bin/v2ray-plugin ];then
   ( cd usr/bin && rm -f v2ray-plugin && ln -s xray-plugin v2ray-plugin )
fi

[ -f $FORCE_REBOOT ] && cp $FORCE_REBOOT usr/sbin/
[ -f ${SYSCTL_CUSTOM_CONF} ] && cp ${SYSCTL_CUSTOM_CONF} etc/sysctl.d/

mkdir -p ./etc/modules.d.remove
mv -f ./etc/modules.d/brcm* ./etc/modules.d.remove/ 2>/dev/null
mod_blacklist=$(cat ${KMOD_BLACKLIST})
for mod in $mod_blacklist ;do
	mv -f ./etc/modules.d/${mod} ./etc/modules.d.remove/ 2>/dev/null
done
[ -f ./etc/modules.d/usb-net-asix-ax88179 ] || echo "ax88179_178a" > ./etc/modules.d/usb-net-asix-ax88179
if echo $KERNEL_VERSION | grep -E '*\+$' ;then
	echo "r8152" > ./etc/modules.d/usb-net-rtl8152
else
	echo "r8152" > ./etc/modules.d/usb-net-rtl8152
fi
echo "r8188eu" > ./etc/modules.d/rtl8188eu
echo "sunxi_wdt" > ./etc/modules.d/watchdog

cat > ./etc/inittab <<EOF
::sysinit:/etc/init.d/rcS S boot
::shutdown:/etc/init.d/rcS K shutdown
ttyS0::askfirst:/usr/libexec/login.sh
EOF

sed -e 's/\/opt/\/etc/' -i ./etc/config/qbittorrent
sed -e "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" -i ./etc/ssh/sshd_config 2>/dev/null
sss=$(date +%s)
ddd=$((sss/86400))
[ -x ./bin/bash ] && [ -f "${SYSINFO_SCRIPT}" ] && cp -v "${SYSINFO_SCRIPT}" ./etc/profile.d/ && sed -e "s/\/bin\/ash/\/bin\/bash/" -i ./etc/passwd && \
	sed -e "s/\/bin\/ash/\/bin\/bash/" -i ./usr/libexec/login.sh
sed -e "s/:0:0:99999:7:::/:${ddd}:0:99999:7:::/" -i ./etc/shadow
sed -e 's/root::/root:$1$NA6OM0Li$99nh752vw4oe7A.gkm2xk1:/' -i ./etc/shadow

# for collectd
# [ -f ./etc/ppp/options-opkg ] && mv ./etc/ppp/options-opkg ./etc/ppp/options
# for cifsd
[ -f ./etc/init.d/cifsd ] && rm -f ./etc/rc.d/S98samba4
# for smbd
[ -f ./etc/init.d/smbd ] && rm -f ./etc/rc.d/S98samba4
# for ksmbd
[ -f ./etc/init.d/ksmbd ] && rm -f ./etc/rc.d/S98samba4 && sed -e 's/modprobe ksmbd/sleep 1 \&\& modprobe ksmbd/' -i ./etc/init.d/ksmbd
# for samba4 enable smbv1 protocol
[ -f ./etc/config/samba4 ] && \
	sed -e 's/services/nas/g' -i ./usr/lib/lua/luci/controller/samba4.lua && \
	[ -f ${SMB4_PATCH} ] && \
	patch -p1 < ${SMB4_PATCH}
# for nfs server
if [ -f ./etc/init.d/nfsd ];then
    cat > ./etc/exports <<EOF
# /etc/exports: the access control list for filesystems which may be exported
#               to NFS clients.  See exports(5).
#
# Example for NFSv2 and NFSv3:
# /srv/homes       hostname1(rw,sync,no_subtree_check) hostname2(ro,sync,no_subtree_check)
#
# Example for NFSv4:
# /srv/nfs4        gss/krb5i(rw,sync,fsid=0,crossmnt,no_subtree_check)
# /srv/nfs4/homes  gss/krb5i(rw,sync,no_subtree_check)
#

/mnt *(ro,fsid=0,sync,nohide,no_subtree_check,insecure,no_root_squash)
/mnt/mmcblk0p4 *(rw,fsid=1,sync,no_subtree_check,no_root_squash)
EOF
    cat > ./etc/config/nfs <<EOF

config share
        option clients '*'
        option enabled '1'
        option path '/mnt'
        option options 'ro,fsid=0,sync,nohide,no_subtree_check,insecure,no_root_squash'

config share
        option enabled '1'
        option path '/mnt/mmcblk0p4'
        option clients '*'
        option options 'rw,fsid=1,sync,no_subtree_check,no_root_squash'
EOF
fi

# for openclash
if [ -d ./etc/openclash/core ];then
    (
        mkdir -p ./usr/share/openclash/core && \
	cd ./etc/openclash && \
	mv core ../../usr/share/openclash/ && \
	ln -s ../../usr/share/openclash/core .
    )
fi

chmod 755 ./etc/init.d/*

sed -e "s/option wan_mode 'false'/option wan_mode 'true'/" -i ./etc/config/dockerman 2>/dev/null
mv -f ./etc/rc.d/S??dockerd ./etc/rc.d/S99dockerd 2>/dev/null
rm -f ./etc/rc.d/S80nginx 2>/dev/null

create_fstab_config

[ -f ./www/DockerReadme.pdf ] && [ -f ${DOCKER_README} ] && cp -fv ${DOCKER_README} ./www/DockerReadme.pdf

# 写入版本信息
cat > ./etc/flippy-openwrt-release <<EOF
SOC=${SOC}
BOARD=${BOARD}
KERNEL_VERSION=${KERNEL_VERSION}
EOF

rm -f ./etc/bench.log
cat >> ./etc/crontabs/root << EOF
17 3 * * * /etc/coremark.sh
EOF

mkdir -p ./etc/modprobe.d

adjust_turboacc_config
adjust_ntfs_config
patch_admin_status_index_html

if [ -f ${UBOOT_BIN} ];then
    mkdir -p $TGT_ROOT/lib/u-boot && cp -v ${UBOOT_BIN} $TGT_ROOT/lib/u-boot
    cp -v ${WRITE_UBOOT_SCRIPT} ${TGT_ROOT}/lib/u-boot
    echo "写入 bootloader ..."
    echo "dd if=${UBOOT_BIN} of=${TGT_DEV} bs=1024 seek=8"
    dd if="${UBOOT_BIN}" of="${TGT_DEV}" bs=1024 seek=8
    sync
    echo "写入完毕"
    echo
fi

write_banner
# 创建 /etc 初始快照
echo "创建初始快照: /etc -> /.snapshots/etc-000"
cd $TGT_ROOT && \
mkdir -p .snapshots && \
btrfs subvolume snapshot -r etc .snapshots/etc-000

# clean temp_dir
cd $TEMP_DIR
umount -f $TGT_ROOT $TGT_BOOT
( losetup -D && cd $WORK_DIR && rm -rf $TEMP_DIR && losetup -D)
sync
mv $TGT_IMG $OUTPUT_DIR && sync
echo "镜像已生成, 存放在 ${OUTPUT_DIR} 下面"
echo "========================== end $0 ================================"
echo
