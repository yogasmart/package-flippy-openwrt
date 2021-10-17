#!/bin/bash

echo "========================= begin $0 ==========================="
source make.env
source public_funcs
init_work_env
check_k510

# 盒子型号识别参数 
SOC=s922x
BOARD=gtking

SUBVER=$1

# Kernel image sources
###################################################################
MODULES_TGZ=${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz
check_file ${MODULES_TGZ}
BOOT_TGZ=${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz
check_file ${BOOT_TGZ}
DTBS_TGZ=${KERNEL_PKG_HOME}/dtb-amlogic-${KERNEL_VERSION}.tar.gz
check_file ${DTBS_TGZ}
###########################################################################

# Openwrt root 源文件
OP_ROOT_TGZ="openwrt-armvirt-64-default-rootfs.tar.gz"
OPWRT_ROOTFS_GZ="${PWD}/${OP_ROOT_TGZ}"
check_file ${OPWRT_ROOTFS_GZ}
echo "Use $OPWRT_ROOTFS_GZ as openwrt rootfs!"

# 目标镜像文件
TGT_IMG="${WORK_DIR}/openwrt_${SOC}_${BOARD}_${OPENWRT_VER}_k${KERNEL_VERSION}${SUBVER}.img"

# 补丁和脚本
###########################################################################
REGULATORY_DB="${PWD}/files/regulatory.db.tar.gz"
KMOD="${PWD}/files/kmod"
KMOD_BLACKLIST="${PWD}/files/kmod_blacklist"
MAC_SCRIPT1="${PWD}/files/fix_wifi_macaddr.sh"
MAC_SCRIPT2="${PWD}/files/find_macaddr.pl"
MAC_SCRIPT3="${PWD}/files/inc_macaddr.pl"
CPUSTAT_SCRIPT="${PWD}/files/cpustat"
CPUSTAT_SCRIPT_PY="${PWD}/files/cpustat.py"
CPUSTAT_PATCH="${PWD}/files/luci-admin-status-index-html.patch"
CPUSTAT_PATCH_02="${PWD}/files/luci-admin-status-index-html-02.patch"
GETCPU_SCRIPT="${PWD}/files/getcpu"
TTYD="${PWD}/files/ttyd"
FLIPPY="${PWD}/files/scripts_deprecated/flippy_cn"
BANNER="${PWD}/files/banner"

# 20200314 add
FMW_HOME="${PWD}/files/firmware"
SMB4_PATCH="${PWD}/files/smb4.11_enable_smb1.patch"
SYSCTL_CUSTOM_CONF="${PWD}/files/99-custom.conf"

# 20200709 add
COREMARK="${PWD}/files/coremark.sh"

# 20200930 add
SND_MOD="${PWD}/files/s922x/snd-meson-g12"
DAEMON_JSON="${PWD}/files/s922x/daemon.json"

# 20201006 add
FORCE_REBOOT="${PWD}/files/s922x/reboot"
# 20201017 add
BAL_ETH_IRQ="${PWD}/files/balethirq.pl"
# 20201026 add
FIX_CPU_FREQ="${PWD}/files/fixcpufreq.pl"
SYSFIXTIME_PATCH="${PWD}/files/sysfixtime.patch"

# 20201128 add
SSL_CNF_PATCH="${PWD}/files/openssl_engine.patch"

# 20201212 add
BAL_CONFIG="${PWD}/files/s922x/balance_irq"
CPUFREQ_INIT="${PWD}/files/s922x/cpufreq"

# 20210302 modify
FIP_HOME="${PWD}/files/meson_btld/with_fip/s922x"
UBOOT_WITH_FIP="${FIP_HOME}/gtkingpro-u-boot.bin.sd.bin"
UBOOT_WITHOUT_FIP_HOME="${PWD}/files/meson_btld/without_fip"
UBOOT_WITHOUT_FIP="u-boot-gtkingpro.bin"

# 20210208 add
WIRELESS_CONFIG="${PWD}/files/s922x/wireless"

# 20210307 add
SS_LIB="${PWD}/files/ss-glibc/lib-glibc.tar.xz"
SS_BIN="${PWD}/files/ss-glibc/ss-bin-glibc.tar.xz"
JQ="${PWD}/files/jq"

# 20210330 add
DOCKERD_PATCH="${PWD}/files/dockerd.patch"

# 20200416 add
FIRMWARE_TXZ="${PWD}/files/firmware_armbian.tar.xz"
BOOTFILES_HOME="${PWD}/files/bootfiles/amlogic"
GET_RANDOM_MAC="${PWD}/files/get_random_mac.sh"

# 20210618 add
DOCKER_README="${PWD}/files/DockerReadme.pdf"

# 20210704 add
SYSINFO_SCRIPT="${PWD}/files/30-sysinfo.sh"

# 20210923 add
OPENWRT_INSTALL="${PWD}/files/openwrt-install-amlogic"
OPENWRT_UPDATE="${PWD}/files/openwrt-update-amlogic"
OPENWRT_KERNEL="${PWD}/files/openwrt-kernel"
OPENWRT_BACKUP="${PWD}/files/openwrt-backup"
###########################################################################

check_depends

SKIP_MB=4
BOOT_MB=256
ROOTFS_MB=640
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB))
create_image "$TGT_IMG" "$SIZE"
create_partition "$TGT_DEV" "msdos" "$SKIP_MB" "$BOOT_MB" "fat32" "0" "-1" "btrfs"
make_filesystem "$TGT_DEV" "B" "fat32" "BOOT" "R" "btrfs" "ROOTFS"
mount_fs "${TGT_DEV}p1" "${TGT_BOOT}" "vfat"
mount_fs "${TGT_DEV}p2" "${TGT_ROOT}" "btrfs" "compress=zstd"
echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc
extract_rootfs_files
extract_amlogic_boot_files

echo "修改引导分区相关配置 ... "
# modify boot
cd $TGT_BOOT
rm -f uEnv.ini
cat > uEnv.txt <<EOF
LINUX=/zImage
INITRD=/uInitrd

# 下列 dtb，用到哪个就把哪个的#删除，其它的则加上 # 在行首

# 用于 Belink GT-King
#FDT=/dtb/amlogic/meson-g12b-gtking.dtb

# 用于 Belink GT-King Pro
FDT=/dtb/amlogic/meson-g12b-gtking-pro.dtb

APPEND=root=UUID=${ROOTFS_UUID} rootfstype=btrfs rootflags=compress=zstd console=ttyAML0,115200n8 console=tty0 no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1
EOF

echo "uEnv.txt --->"
cat uEnv.txt

echo "修改根文件系统相关配置 ... "
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

if [ -d "${FIP_HOME}" ];then
    mkdir -p lib/u-boot
    cp -v "${FIP_HOME}"/../*.sh lib/u-boot/
    cp -v "${FIP_HOME}"/*.sd.bin lib/u-boot/
fi

[ -f $OPENWRT_INSTALL ] && cp $OPENWRT_INSTALL usr/sbin/ && ln -s ../usr/sbin/openwrt-install-amlogic root/install-to-emmc.sh
[ -f $OPENWRT_UPDATE ] && cp $OPENWRT_UPDATE usr/sbin/
[ -f ${OPENWRT_KERNEL} ] && cp ${OPENWRT_KERNEL} usr/sbin/
[ -f ${OPENWRT_BACKUP} ] && cp ${OPENWRT_BACKUP} usr/sbin/ && (cd usr/sbin && ln -sf openwrt-backup flippy)
[ -f $MAC_SCRIPT1 ] && cp $MAC_SCRIPT1 usr/bin/
[ -f $MAC_SCRIPT2 ] && cp $MAC_SCRIPT2 usr/bin/
[ -f $MAC_SCRIPT3 ] && cp $MAC_SCRIPT3 usr/bin/
[ -f $DAEMON_JSON ] && mkdir -p "etc/docker" && cp $DAEMON_JSON "etc/docker/daemon.json"
[ -f $FORCE_REBOOT ] && cp $FORCE_REBOOT usr/sbin/
[ -f $COREMARK ] && [ -f "etc/coremark.sh" ] && cp -f $COREMARK "etc/coremark.sh" && chmod 755 "etc/coremark.sh"
if [ -x usr/bin/perl ];then
	[ -f $CPUSTAT_SCRIPT ] && cp $CPUSTAT_SCRIPT usr/bin/cpustat && chmod 755 usr/bin/cpustat
	[ -f $GETCPU_SCRIPT ] && cp $GETCPU_SCRIPT bin/
else
	[ -f $CPUSTAT_SCRIPT_PY ] && cp $CPUSTAT_SCRIPT_PY usr/bin/cpustat && chmod 755 usr/bin/cpustat
fi
#[ -f $TTYD ] && cp $TTYD etc/init.d/
[ -f $FLIPPY ] && cp $FLIPPY usr/sbin/
if [ -f $BANNER ];then
    cp -f $BANNER etc/banner
    echo " Base on OpenWrt ${OPENWRT_VER} by lean & lienol" >> etc/banner
    echo " Kernel ${KERNEL_VERSION}" >> etc/banner
    TODAY=$(date +%Y-%m-%d)
    echo " Packaged by ${WHOAMI} on ${TODAY}" >> etc/banner
    echo " SOC: ${SOC}	BOARD: ${BOARD}" >> etc/banner
    echo >> etc/banner
fi

if [ -f $BAL_ETH_IRQ ];then
    cp -v $BAL_ETH_IRQ usr/sbin
    chmod 755 usr/sbin/balethirq.pl
    sed -e "/exit/i\/usr/sbin/balethirq.pl" -i etc/rc.local
    [ -f ${BAL_CONFIG} ] && cp -v ${BAL_CONFIG} etc/config/
fi
[ -f $CPUFREQ_INIT ] && cp -v $CPUFREQ_INIT etc/init.d/ && chmod 755 etc/init.d/cpufreq
[ -f $WIRELESS_CONFIG ] && cp -v $WIRELESS_CONFIG etc/config/

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

[ -f ${SYSCTL_CUSTOM_CONF} ] && cp ${SYSCTL_CUSTOM_CONF} etc/sysctl.d/
[ -f ${GET_RANDOM_MAC} ] && cp ${GET_RANDOM_MAC} usr/bin/
sed -e 's/ttyAMA0/ttyAML0/' -i ./etc/inittab
sed -e 's/ttyS0/tty0/' -i ./etc/inittab
sed -e 's/\/opt/\/etc/' -i ./etc/config/qbittorrent
sed -e "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" -i ./etc/ssh/sshd_config 2>/dev/null
sss=$(date +%s)
ddd=$((sss/86400))
[ -x ./bin/bash ] && [ -f "${SYSINFO_SCRIPT}" ] && cp -v "${SYSINFO_SCRIPT}" ./etc/profile.d/ && sed -e "s/\/bin\/ash/\/bin\/bash/" -i ./etc/passwd && \
	sed -e "s/\/bin\/ash/\/bin\/bash/" -i ./usr/libexec/login.sh
sed -e "s/:0:0:99999:7:::/:${ddd}:0:99999:7:::/" -i ./etc/shadow
sed -e 's/root::/root:$1$NA6OM0Li$99nh752vw4oe7A.gkm2xk1:/' -i ./etc/shadow

# for collectd
#[ -f ./etc/ppp/options-opkg ] && mv ./etc/ppp/options-opkg ./etc/ppp/options

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
/mnt/mmcblk2p4 *(rw,fsid=1,sync,no_subtree_check,no_root_squash)
EOF
    cat > ./etc/config/nfs <<EOF

config share
        option clients '*'
        option enabled '1'
        option path '/mnt'
        option options 'ro,fsid=0,sync,nohide,no_subtree_check,insecure,no_root_squash'

config share
        option enabled '1'
        option path '/mnt/mmcblk2p4'
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

cat > ./etc/fstab <<EOF
UUID=${ROOTFS_UUID} / btrfs compress=zstd 0 1
LABEL=${BOOT_LABEL} /boot vfat defaults 0 2
#tmpfs /tmp tmpfs defaults,nosuid 0 0
EOF
echo "/etc/fstab --->"
cat ./etc/fstab

cat > ./etc/config/fstab <<EOF
config global
        option anon_swap '0'
        option auto_swap '0'
        option anon_mount '1'
        option auto_mount '1'
        option delay_root '5'
        option check_fs '0'

config mount
        option target '/overlay'
        option uuid '${ROOTFS_UUID}'
        option enabled '1'
        option enabled_fsck '1'
	option options 'compress=zstd'
	option fstype 'btrfs'

config mount
        option target '/boot'
        option label '${BOOT_LABEL}'
        option enabled '1'
        option enabled_fsck '1'
	option fstype 'vfat'
EOF

echo "/etc/config/fstab --->"
cat ./etc/config/fstab

[ -f ./www/DockerReadme.pdf ] && [ -f ${DOCKER_README} ] && cp -fv ${DOCKER_README} ./www/DockerReadme.pdf

mkdir -p ./etc/modprobe.d
cat > ./etc/modprobe.d/99-local.conf <<EOF
blacklist snd_soc_meson_aiu_i2s
alias brnf br_netfilter
alias pwm pwm_meson
alias wifi brcmfmac
EOF

if [ -f ./etc/config/turboacc ];then
    sed -e "s/option sw_flow '1'/option sw_flow '${SW_FLOWOFFLOAD}'/" -i ./etc/config/turboacc
    sed -e "s/option hw_flow '1'/option hw_flow '${HW_FLOWOFFLOAD}'/" -i ./etc/config/turboacc
    sed -e "s/option sfe_flow '1'/option sfe_flow '${SFE_FLOW}'/" -i ./etc/config/turboacc
else
    cat > ./etc/config/turboacc <<EOF

config turboacc 'config'
        option sw_flow '${SW_FLOWOFFLOAD}'
        option hw_flow '${HW_FLOWOFFLOAD}'
	option sfe_flow '${SFE_FLOW}'
        option bbr_cca '0'
        option fullcone_nat '1'
        option dns_caching '0'

EOF
fi

echo pwm_meson > ./etc/modules.d/pwm_meson
echo panfrost > ./etc/modules.d/panfrost
echo meson_gxbb_wdt > ./etc/modules.d/watchdog

mkdir ./etc/modules.d.remove
mod_blacklist=$(cat ${KMOD_BLACKLIST})
for mod in $mod_blacklist ;do
	mv -f ./etc/modules.d/${mod} ./etc/modules.d.remove/ 2>/dev/null
done

if [ $K510 -eq 1 ];then
    # 高版本内核下，如果ENABLE_WIFI_K510 = 0 则禁用wifi
    if [ $ENABLE_WIFI_K510 -eq 0 ];then
        mv -f ./etc/modules.d/brcm*  ./etc/modules.d.remove/ 2>/dev/null
    fi
else
    # 低版本内核下，如果ENABLE_WIFI_K504 = 0 则禁用wifi
    if [ $ENABLE_WIFI_K504 -eq 0 ];then
        mv -f ./etc/modules.d/brcm*  ./etc/modules.d.remove/ 2>/dev/null
    fi
fi

# 默认禁用sfe
[ -f ./etc/config/sfe ] && sed -e 's/option enabled '1'/option enabled '0'/' -i ./etc/config/sfe

[ -f ./etc/modules.d/usb-net-asix-ax88179 ] || echo "ax88179_178a" > ./etc/modules.d/usb-net-asix-ax88179
# +版内核，优先启用v2驱动, +o内核则启用v1驱动
if echo $KERNEL_VERSION | grep -E '*\+$' ;then
	echo "r8152" > ./etc/modules.d/usb-net-rtl8152
else
	echo "r8152" > ./etc/modules.d/usb-net-rtl8152
fi
[ -f ./etc/config/shairport-sync ] && [ -f ${SND_MOD} ] && cp ${SND_MOD} ./etc/modules.d/
echo "r8188eu" > ./etc/modules.d/rtl8188eu

rm -f ./etc/rc.d/S*dockerd

# 写入版本信息
cat > ./etc/flippy-openwrt-release <<EOF
SOC=${SOC}
BOARD=${BOARD}
KERNEL_VERSION=${KERNEL_VERSION}
K510=${K510}
SFE_FLAG=${SFE_FLAG}
FLOWOFFLOAD_FLAG=${FLOWOFFLOAD_FLAG}
EOF

if [ $K510 -eq 1 ];then
    cat >> ./etc/flippy-openwrt-release <<EOF
UBOOT_OVERLOAD=${UBOOT_WITHOUT_FIP}
EOF
fi

adjust_ntfs_config
patch_admin_status_index_html

rm -f ${TGT_ROOT}/etc/bench.log
cat >> ${TGT_ROOT}/etc/crontabs/root << EOF
37 5 * * * /etc/coremark.sh
EOF

# 创建 /etc 初始快照
echo "创建初始快照: /etc -> /.snapshots/etc-000"
cd $TGT_ROOT && \
mkdir -p .snapshots && \
btrfs subvolume snapshot -r etc .snapshots/etc-000

# 2021.04.01添加
# 强制锁定fstab,防止用户擅自修改挂载点
# 开启了快照功能之后，不再需要锁定fstab
#chattr +ia ./etc/config/fstab

# clean temp_dir
cd $TEMP_DIR
umount -f $TGT_BOOT $TGT_ROOT 

if [ -f ${UBOOT_WITH_FIP} ];then
    dd if=${UBOOT_WITH_FIP}  of=${TGT_DEV} conv=fsync,notrunc bs=512 skip=1 seek=1
    dd if=${UBOOT_WITH_FIP}  of=${TGT_DEV} conv=fsync,notrunc bs=1 count=444
fi

( losetup -D && cd $WORK_DIR && rm -rf $TEMP_DIR && losetup -D)
sync
mv ${TGT_IMG} ${OUTPUT_DIR} && sync
echo "镜像已生成! 存放在 ${OUTPUT_DIR} 下面!"
echo "========================== end $0 ================================"
echo
