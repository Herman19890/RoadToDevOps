#!/bin/bash

gcc_new_version=11.2.0
src_dir=$(pwd)/00src00
mydir=$(pwd)

# 获取gcc老版本
gcc --help &> /dev/null
if [ $? -eq 0 ];then
    gcc_old_version=$(gcc --version | head -1 | awk '{print $3}')
else
    gcc_old_version=''
    echo_info 安装初始gcc
    yum install -y gcc
    if [ $? -ne 0 ];then
        echo_error 安装gcc失败，退出
        exit 1
    fi
    gcc_old_version=$(gcc --version | head -1 | awk '{print $3}')
fi

# 带格式的echo函数
function echo_info() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m$@\033[0m"
}
function echo_warning() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m$@\033[0m"
}
function echo_error() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m$@\033[0m"
}

# 解压
function untar_tgz(){
    echo_info 解压 $1 中
    tar xf $1
    if [ $? -ne 0 ];then
        echo_error 解压出错，请检查！
        exit 2
    fi
}

# 首先判断当前目录是否有压缩包：
#   I. 如果有压缩包，那么就在当前目录解压；
#   II.如果没有压缩包，那么就检查有没有 ${src_dir} 表示的目录;
#       1) 如果有目录，那么检查有没有压缩包
#           ① 有压缩包就解压
#           ② 没有压缩包则下载压缩包
#       2) 如果没有,那么就创建这个目录，然后 cd 到目录中，然后下载压缩包，然
#       后解压
# 解压的步骤都在后面，故此处只做下载

# 语法： download_tar_gz 保存的目录 下载链接
# 使用示例： download_tar_gz /data/openssh-update https://mirrors.cloud.tencent.com/openssl/source/openssl-1.1.1h.tar.gz
function download_tar_gz(){
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IsS $2 | head -1 | awk '{print $2}')
    if [ $http_code -eq 404 ];then
        echo_error $2
        echo_error 服务端文件不存在，退出
        exit 98
    fi
    
    download_file_name=$(echo $2 |  awk -F"/" '{print $NF}')
    back_dir=$(pwd)
    file_in_the_dir=''  # 这个目录是后面编译目录的父目录

    ls $download_file_name &> /dev/null
    if [ $? -ne 0 ];then
        # 进入此处表示脚本所在目录没有压缩包
        ls -d $1 &> /dev/null
        if [ $? -ne 0 ];then
            # 进入此处表示没有${src_dir}目录
            mkdir -p $1 && cd $1
            echo_info 下载 $download_file_name 至 $(pwd)/
            # 检测是否有wget工具
            if [ ! -f /usr/bin/wget ];then
                echo_info 安装wget工具
                yum install -y wget
            fi
            wget $2
            if [ $? -ne 0 ];then
                echo_error 下载 $2 失败！
                exit 1
            fi
            file_in_the_dir=$(pwd)
            # 返回脚本所在目录，这样这个函数才可以多次使用
            cd ${back_dir}
        else
            # 进入此处表示有${src_dir}目录
            cd $1
            ls $download_file_name &> /dev/null
            if [ $? -ne 0 ];then
            # 进入此处表示${src_dir}目录内没有压缩包
                echo_info 下载 $download_file_name 至 $(pwd)/
                # 检测是否有wget工具
                if [ ! -f /usr/bin/wget ];then
                    echo_info 安装wget工具
                    yum install -y wget
                fi
                wget $2
                if [ $? -ne 0 ];then
                    echo_error 下载 $2 失败！
                    exit 1
                fi
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            else
                # 进入此处，表示${src_dir}目录内有压缩包
                echo_info 发现压缩包$(pwd)/$download_file_name
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            fi
        fi
    else
        # 进入此处表示脚本所在目录有压缩包
        echo_info 发现压缩包$(pwd)/$download_file_name
        file_in_the_dir=$(pwd)
    fi
}

# 多核编译
function multi_core_compile(){
    echo_info 多核编译
    assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
    cpucores=$(cat /proc/cpuinfo | grep -c processor)
    compilecore=$(($cpucores - $assumeused - 1))
    if [ $compilecore -ge 1 ];then
        make -j $compilecore && make -j $compilecore install
        if [ $? -ne 0 ];then
            echo_error 编译安装出错，请检查脚本
            exit 1
        fi
    else
        make && make install
        if [ $? -ne 0 ];then
            echo_error 编译安装出错，请检查脚本
            exit 1
        fi 
    fi
}

# 比较版本号
tempfile=gcc_version_compare.tmp
echo ${gcc_new_version} >> ${tempfile}
echo ${gcc_old_version} >> ${tempfile}
latest_version=$(cat ${tempfile} | sort -V | tail -1)
rm -f ${tempfile}

if [[ ${latest_version} == ${gcc_old_version} ]];then
    echo_error "升级版本（${gcc_new_version}）小于等于已安装版本（${gcc_old_version}），请查看网址http://mirrors.cloud.tencent.com/gnu/gcc/ 获取最新版本，并修改脚本中的最新版本号"
    exit 1
fi

echo_info 安装依赖
yum -y install bison bzip2 gcc-c++

########################
# 需要 GMP 4.2+, MPFR 2.4.0+ and MPC 0.8.0+
gmp_version=6.2.1
mpfr_version=4.1.1
mpc_version=1.2.1
########################
download_tar_gz ${src_dir} http://mirrors.cloud.tencent.com/gnu/gmp/gmp-${gmp_version}.tar.xz
cd ${file_in_the_dir}
untar_tgz gmp-${gmp_version}.tar.xz
cd gmp-${gmp_version}
./configure
multi_core_compile
echo_info --------------- GMP ${gmp_version} DONE ---------------
download_tar_gz ${src_dir} http://mirrors.cloud.tencent.com/gnu/mpfr/mpfr-${mpfr_version}.tar.xz
cd ${file_in_the_dir}
untar_tgz mpfr-${mpfr_version}.tar.xz
cd mpfr-${mpfr_version}
./configure
multi_core_compile
# gcc需要libmpfr.so.6，但编译后是libmpfr.so.4，所以做个软链接
if [ -f /usr/lib64/libmpfr.so.4 ];then
    if [ -f /usr/lib64/libmpfr.so.6 ];then
        temp_a=$(ls -l /usr/lib64/libmpfr.so.6)
        if [[ ${temp_a:0:1} == l ]];then
            rm -f /usr/lib64/libmpfr.so.6
            ln -s  /usr/lib64/libmpfr.so.4 /usr/lib64/libmpfr.so.6
        fi
    else
        ln -s  /usr/lib64/libmpfr.so.4 /usr/lib64/libmpfr.so.6
    fi
fi
echo_info --------------- MPFR ${mpfr_version} DONE ---------------
download_tar_gz ${src_dir} http://mirrors.cloud.tencent.com/gnu/mpc/mpc-${mpc_version}.tar.gz
cd ${file_in_the_dir}
untar_tgz mpc-${mpc_version}.tar.gz
cd mpc-${mpc_version}
./configure
multi_core_compile
echo_info --------------- MPFR ${mpfr_version} DONE ---------------
echo

echo_info 安装gcc本体
download_tar_gz ${src_dir} http://mirrors.cloud.tencent.com/gnu/gcc/gcc-${gcc_new_version}/gcc-${gcc_new_version}.tar.xz
cd ${file_in_the_dir}
untar_tgz gcc-${gcc_new_version}.tar.xz

cd ${file_in_the_dir}/gcc-${gcc_new_version}
mkdir build
cd build/
# --prefix=/usr/local 配置安装目录
# –enable-languages表示你要让你的gcc支持那些语言，
# –disable-multilib不生成编译为其他平台可执行代码的交叉编译器。
# –disable-checking生成的编译器在编译过程中不做额外检查，
# 也可以使用*–enable-checking=xxx*来增加一些检查
../configure -enable-checking=release -enable-languages=c,c++ -disable-multilib
if [ $? -ne 0 ];then
    echo_error 编译失败，退出
    exit 1
fi
multi_core_compile

echo_info gcc安装完毕，版本：${gcc_new_version}