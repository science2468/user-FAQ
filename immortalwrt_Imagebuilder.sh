#!/bin/bash
# 结合 https://firmware-selector.immortalwrt.org/ 使用，选择好设备后在复制页面上的型号、平台、版本
# 设置默认版本号
VERSION="24.10.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 让用户输入平台信息并传递给变量 platform
echo "请输入平台（例如 ramips/mt7621）："
read PLATFORM

# 获取 ImmortalWRT 版本信息，并根据输入更新 VERSION 变量
echo "请输入 ImmortalWRT 的版本（默认版本为 24.10.0）："
read USER_VERSION
if [ -n "$USER_VERSION" ]; then
    VERSION="$USER_VERSION"  # 如果用户输入版本，则更新 VERSION 变量
fi

# 根据平台和版本号构造 ImageBuilder 路径
FORMATTED_PLATFORM=$(echo "$PLATFORM" | sed 's/\//-/g')  # 将 / 替换为 -
IMAGEBUILDER_DIR="$SCRIPT_DIR/immortalwrt-imagebuilder-${VERSION}-${FORMATTED_PLATFORM}.Linux-x86_64"
IMAGEBUILDER_URL="https://mirror.nju.edu.cn/immortalwrt/releases/${VERSION}/targets/${PLATFORM}/immortalwrt-imagebuilder-${VERSION}-${FORMATTED_PLATFORM}.Linux-x86_64.tar.zst"

# 检查 Linux 发行版并安装依赖
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                sudo apt update && sudo apt install -y build-essential libncurses5-dev libncursesw5-dev zlib1g-dev gawk git ccache gettext libssl-dev xsltproc rsync wget unzip zstd
                ;;
            fedora|centos|rocky)
                sudo dnf install -y make gcc ncurses-devel zlib-devel gawk git ccache gettext openssl-devel xsltproc rsync wget unzip zstd
                ;;
            arch)
                sudo pacman -Sy --noconfirm base-devel ncurses zlib gawk git ccache gettext openssl xsltproc rsync wget unzip zstd
                ;;
            *)
                echo "Unsupported Linux distribution: $ID"
                exit 1
                ;;
        esac
    else
        echo "无法检测到 Linux 发行版"
        exit 1
    fi
}

# 执行系统检测和依赖安装
detect_os

# 下载并解压 ImageBuilder
echo "正在下载 ImageBuilder..."
wget "$IMAGEBUILDER_URL" -O "$SCRIPT_DIR/immortalwrt-imagebuilder-${VERSION}-${FORMATTED_PLATFORM}.Linux-x86_64.tar.zst"
if [ $? -ne 0 ]; then
    echo "下载失败，请检查 URL 或网络连接。"
    exit 1
fi

echo "正在解压 ImageBuilder..."
zstd -d "$SCRIPT_DIR/immortalwrt-imagebuilder-${VERSION}-${FORMATTED_PLATFORM}.Linux-x86_64.tar.zst" -o "$SCRIPT_DIR/immortalwrt-imagebuilder-${VERSION}-${FORMATTED_PLATFORM}.Linux-x86_64.tar"
if [ $? -ne 0 ]; then
    echo "解压 .zst 文件失败。"
    exit 1
fi

tar -xf "$SCRIPT_DIR/immortalwrt-imagebuilder-${VERSION}-${FORMATTED_PLATFORM}.Linux-x86_64.tar" -C "$SCRIPT_DIR"
if [ $? -ne 0 ]; then
    echo "解压 .tar 文件失败。"
    exit 1
fi

rm -rf "$SCRIPT_DIR/immortalwrt-imagebuilder-${VERSION}-${FORMATTED_PLATFORM}.Linux-x86_64.tar.zst"
rm -rf "$SCRIPT_DIR/immortalwrt-imagebuilder-${VERSION}-${FORMATTED_PLATFORM}.Linux-x86_64.tar"

# 进入 ImageBuilder 目录
cd "$IMAGEBUILDER_DIR" || exit 1

#软件源改为nju
sed -i 's#downloads.immortalwrt.org#mirror.nju.edu.cn/immortalwrt#g' repositories.conf

# 运行命令后，将输出结果用特别的符号围起来显示
OUTPUT=$(make info)  # 捕获 make info 的输出
if [ $? -ne 0 ]; then
    echo "make info 执行失败，请检查环境配置。"
    exit 1
fi
echo "========= Make Info 输出开始 ========="
echo "$OUTPUT"
echo "========= Make Info 输出结束 ========="

# 等待用户按下 Enter 键继续
echo "设备型号在一行的开头，复制不要带：。按下 Enter 键继续..."
read

# 获取设备型号信息
echo "请输入设备型号信息（从 'make info' 中获取）："
read MODEL

# 获取需要添加或删除的软件包信息
echo "请输入要添加或删除的软件包（空格分隔）："
read PACKAGES

# 获取根文件系统大小
echo "请输入根文件系统大小（例如 4096，单位为MB）。如果不需要设置，请直接按回车："
read ROOTFS_PARTSIZE

# 更新软件包索引
make clean
make manifest

# 判断是否输入了根文件系统大小，如果没有输入，则不传递 ROOTFS_PARTSIZE
if [ -n "$ROOTFS_PARTSIZE" ]; then
    if ! [[ "$ROOTFS_PARTSIZE" =~ ^[0-9]+$ ]]; then
        echo "根文件系统大小必须为数字。"
        exit 1
    fi
    make image PROFILE="$MODEL" PACKAGES="$PACKAGES" ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"
else
    make image PROFILE="$MODEL" PACKAGES="$PACKAGES"
fi

# 检查构建是否成功
if [ $? -eq 0 ]; then
    echo "固件构建成功，已存放在 $IMAGEBUILDER_DIR 目录下。"
else
    echo "固件构建失败，请检查日志信息。"
fi
