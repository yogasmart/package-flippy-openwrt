#!/bin/bash

echo "========================= begin $0 ================="
WORK_DIR="${PWD}/tmp"
if [ ! -d ${WORK_DIR} ];then
	mkdir -p ${WORK_DIR}
fi

# Image sources
###################################################################
source make.env
SOC=h6
BOARD=vplus
SUBVER=$1

SKIP_MB=16
BOOT_MB=160
ROOTFS_MB=720

MODULES_TGZ=${KERNEL_PKG_HOME}/modules-${KERNEL_VERSION}.tar.gz
BOOT_TGZ=${KERNEL_PKG_HOME}/boot-${KERNEL_VERSION}.tar.gz
DTBS_TGZ=${KERNEL_PKG_HOME}/dtb-allwinner-${KERNEL_VERSION}.tar.gz
if [ ! -f ${MODULES_TGZ} ];then
	echo "${MODULES_TGZ} not exists!"
	exit 1
fi
if [ ! -f ${BOOT_TGZ} ];then
	echo "${BOOT_TGZ} not exists!"
	exit 1
fi
if [ ! -f ${DTBS_TGZ} ];then
	echo "${DTBS_TGZ} not exists!"
	exit 1
fi

# Openwrt 
OP_ROOT_TGZ="openwrt-armvirt-64-default-rootfs.tar.gz"
OPWRT_ROOTFS_GZ="${PWD}/${OP_ROOT_TGZ}"
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

# work dir
cd $WORK_DIR
TEMP_DIR=$(mktemp -p $WORK_DIR)
rm -rf $TEMP_DIR
mkdir -p $TEMP_DIR
echo $TEMP_DIR

losetup -D

# temp dir
cd $TEMP_DIR

# mk tgt_img
SIZE=$((SKIP_MB + BOOT_MB + ROOTFS_MB))
echo "DISK SIZE = $SIZE MB"
dd if=/dev/zero of=$TGT_IMG bs=1M count=$SIZE conv=fsync && sync
losetup -f -P $TGT_IMG
TGT_DEV=$(losetup | grep "$TGT_IMG" | gawk '{print $1}')
echo "Target dev is $TGT_DEV"

# make partition
echo "开始分区 ..."
parted -s $TGT_DEV mklabel msdos 2>/dev/null
START=$((SKIP_MB * 1024 * 1024))
END=$((BOOT_MB * 1024 * 1024 + START -1))
parted -s $TGT_DEV mkpart primary fat32 ${START}b ${END}b 2>/dev/null
START=$((END + 1))
END=$((ROOTFS_MB * 1024 * 1024 + START -1))
parted -s $TGT_DEV mkpart primary btrfs ${START}b 100% 2>/dev/null
parted -s $TGT_DEV print 2>/dev/null
echo "分区完成"
echo

function wait_dev {
    while [ ! -b $1 ];do
        echo "wait for $1 ..."
        sleep 1
    done
}

# mk boot filesystem (ext4)
echo "格式化 boot分区： ${TGT_DEV}p1 ..."
wait_dev ${TGT_DEV}p1
mkfs.vfat -n EMMC_BOOT ${TGT_DEV}p1
echo "完成"
# mk root filesystem (btrfs)
echo "格式化 ROOTFS分区：${TGT_DEV}p2 ..."
wait_dev ${TGT_DEV}p2
ROOTFS_UUID=$(uuidgen)
mkfs.btrfs -U ${ROOTFS_UUID} -L EMMC_ROOTFS1 -m single ${TGT_DEV}p2
echo "ROOTFS UUID IS $ROOTFS_UUID"
sync
echo "完成"
echo

TGT_BOOT=${TEMP_DIR}/tgt_boot
TGT_ROOT=${TEMP_DIR}/tgt_root
mkdir $TGT_BOOT $TGT_ROOT
mount -t vfat ${TGT_DEV}p1 $TGT_BOOT
mount -t btrfs -o compress=zstd ${TGT_DEV}p2 $TGT_ROOT

echo "创建 /etc 子卷 ..."
btrfs subvolume create $TGT_ROOT/etc

# extract root
echo "extract openwrt rootfs ... "
(
  cd $TGT_ROOT && \
  tar --exclude="./lib/firmware/*" --exclude="./lib/modules/*" -xzf $OPWRT_ROOTFS_GZ && \
  rm -rf ./lib/firmware/* ./lib/modules/* && \
  mkdir -p .reserved boot rom proc sys run
)

echo "extract armbian firmware ... "
( 
  cd ${TGT_ROOT} && \
  tar xJf $FIRMWARE_TXZ
)
  
echo "extract kernel modules ... "
( 
  cd ${TGT_ROOT} && \
  mkdir -p lib/modules && \
  cd lib/modules && \
  tar xzf ${MODULES_TGZ}
)

echo "extract boot files ... "
( 
  cd ${TGT_BOOT} && \
  cp -v "${BOOTFILES_HOME}"/* . && \
  tar xzf "${BOOT_TGZ}" && \
  rm -f initrd.img-${KERNEL_VERSION} && \
  cp -v vmlinuz-${KERNEL_VERSION} zImage && \
  cp -v uInitrd-${KERNEL_VERSION} uInitrd && \
  mkdir -p dtb/allwinner && \
  cd dtb/allwinner && \
  tar xzf "${DTBS_TGZ}" && \
  sync
)

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
if [ -x usr/bin/perl ];then
	[ -f $CPUSTAT_SCRIPT ] && cp $CPUSTAT_SCRIPT usr/bin/cpustat && chmod 755 usr/bin/cpustat  
	[ -f $GETCPU_SCRIPT ] && cp $GETCPU_SCRIPT bin/
else
	[ -f $CPUSTAT_SCRIPT_PY ] && cp $CPUSTAT_SCRIPT_PY usr/bin/cpustat && chmod 755 usr/bin/cpustat
fi
#[ -f $TTYD ] && cp $TTYD etc/init.d/
[ -f $FLIPPY ] && cp $FLIPPY usr/sbin/
[ -f ${OPENWRT_KERNEL} ] && cp ${OPENWRT_KERNEL} usr/sbin/
[ -f ${OPENWRT_BACKUP} ] && cp ${OPENWRT_BACKUP} usr/sbin/ && (cd usr/sbin && ln -sf openwrt-backup flippy)
[ -f ${OPENWRT_UPDATE} ] && cp ${OPENWRT_UPDATE} usr/sbin/
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

[ -d ${FMW_HOME} ] && cp -a ${FMW_HOME}/* lib/firmware/
[ -f $FORCE_REBOOT ] && cp $FORCE_REBOOT usr/sbin/
[ -f ${SYSCTL_CUSTOM_CONF} ] && cp ${SYSCTL_CUSTOM_CONF} etc/sysctl.d/
[ -d overlay ] || mkdir -p overlay
[ -d rom ] || mkdir -p rom
[ -d sys ] || mkdir -p sys
[ -d proc ] || mkdir -p proc
[ -d run ] || mkdir -p run

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

cat > etc/fstab <<EOF
UUID=${ROOTFS_UUID} / btrfs compress=zstd 0 1
LABEL=EMMC_BOOT /boot vfat defaults 0 2
#tmpfs /tmp tmpfs defaults,nosuid 0 0
EOF

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
        option label 'EMMC_BOOT'
        option enabled '1'
        option enabled_fsck '1'
        option fstype 'vfat'

EOF

[ -f ./etc/docker-init ] && rm -f ./etc/docker-init
[ -f ./sbin/firstboot ] && rm -f ./sbin/firstboot
[ -f ./sbin/jffs2reset ] && rm -f ./sbin/jffs2reset ./sbin/jffs2mark
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

cd $TGT_ROOT/lib/modules/${KERNEL_VERSION}/
find . -name '*.ko' -exec ln -sf {} . \;
rm -f ntfs.ko

cd $TGT_ROOT/sbin
if [ ! -x kmod ];then
	cp $KMOD .
fi
ln -sf kmod depmod
ln -sf kmod insmod
ln -sf kmod lsmod
ln -sf kmod modinfo
ln -sf kmod modprobe
ln -sf kmod rmmod
if [ -f mount.ntfs3 ];then
    ln -sf mount.ntfs3 mount.ntfs
elif [ -f ../usr/bin/ntfs-3g ];then
    ln -sf /usr/bin/ntfs-3g mount.ntfs
fi

cd $TGT_ROOT/lib/firmware
mv *.hcd brcm/ 2>/dev/null
if [ -f "$REGULATORY_DB" ];then
	tar xvzf "$REGULATORY_DB"
fi

[ -f $CPUSTAT_PATCH ] && cd $TGT_ROOT && patch -p1 < ${CPUSTAT_PATCH}
[ -x "${TGT_ROOT}/usr/bin/perl" ] && [ -f "${CPUSTAT_PATCH_02}" ] && cd ${TGT_ROOT} && patch -p1 < ${CPUSTAT_PATCH_02}

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
umount -f $TGT_ROOT $TGT_BOOT
( losetup -D && cd $WORK_DIR && rm -rf $TEMP_DIR && losetup -D)
sync
echo "镜像已生成!"
echo "========================== end $0 ================================"
echo
