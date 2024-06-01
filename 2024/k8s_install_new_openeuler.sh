#!/bin/bash
# auther: boge
# descriptions:  the shell scripts will use ansible to deploy K8S at binary for siample
# github:   https://github.com/easzlab/kubeasz
#########################################################################
# 此脚本安装过的操作系统 CentOS/RedHat 7, Ubuntu 16.04/18.04/20.04/22.04, openEuler-22.03(LTS-SP3)
#########################################################################

echo "记得先把数据盘挂载弄好，已经弄好直接回车，否则ctrl+c终止脚本.(Remember to mount the data disk first, and press Enter directly, otherwise ctrl+c terminates the script.)"
read -p "" xxxxxx
# 传参检测
[ $# -ne 7 ] && echo -e "Usage: $0 rootpasswd netnum nethosts cri cni k8s-cluster-name\nExample: bash $0 rootPassword 10.0.1 201\ 202\ 203\ 204 [containerd|docker] [calico|flannel|cilium] boge.com test-cn\n" && exit 11 

# 变量定义
export release=3.6.4
export k8s_ver=v1.30.1
rootpasswd=$1
netnum=$2
nethosts=$3
cri=$4
cni=$5
domainName=$6
clustername=$7
if ls -1v ./kubeasz*.tar.gz &>/dev/null;then software_packet="$(ls -1v ./kubeasz*.tar.gz )";else software_packet="";fi
pwd="/etc/kubeasz"


# deploy机器升级软件库
if cat /etc/redhat-release &>/dev/null;then
    yum update -y
elif cat /etc/openEuler-release &>/dev/null;then
    yum update -y
    yum install bash-completion -y
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
        echo "source /usr/share/bash-completion/bash_completion" >> ~/.bashrc
    fi
    systemctl stop firewalld.service
    systemctl disable firewalld.service
else
    apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y
    [ $? -ne 0 ] && apt-get -yf install
fi

# deploy机器检测python环境
if ! cat /etc/openEuler-release &>/dev/null;then
    python2 -V &>/dev/null
    if [ $? -ne 0 ];then
        if cat /etc/redhat-release &>/dev/null;then
            yum install gcc openssl-devel bzip2-devel 
            [ -f Python-2.7.16.tgz ] || wget https://www.python.org/ftp/python/2.7.16/Python-2.7.16.tgz
            tar xzf Python-2.7.16.tgz
            cd Python-2.7.16
            ./configure --enable-optimizations
            make altinstall
            ln -s /usr/bin/python2.7 /usr/bin/python
            cd -
        else
            apt-get install -y python2.7 && ln -s /usr/bin/python2.7 /usr/bin/python
        fi
    fi
fi

python3 -V &>/dev/null
if [ $? -ne 0 ];then
    if cat /etc/redhat-release &>/dev/null;then
        yum install python3 -y
        which iptables || yum install iptables -y
    elif cat /etc/openEuler-release &>/dev/null;then
        yum install python3 -y
        which iptables || yum install iptables -y
    else
        apt-get install -y python3
        which iptables || apt-get install iptables -y
    fi
fi

# deploy机器设置pip安装加速源
if `echo $clustername |grep -iwE cn &>/dev/null`; then
mkdir ~/.pip
cat > ~/.pip/pip.conf <<CB
[global]
index-url = https://mirrors.aliyun.com/pypi/simple
[install]
trusted-host=mirrors.aliyun.com

CB
fi


# deploy机器安装相应软件包
if cat /etc/openEuler-release &>/dev/null;then
    pip3 install --no-cache-dir ansible netaddr
else
    which python || ln -svf `which python2.7` /usr/bin/python

    if cat /etc/redhat-release &>/dev/null;then
        yum install git epel-release python-pip sshpass -y
        [ -f ./get-pip.py ] && python ./get-pip.py || {
        wget https://bootstrap.pypa.io/pip/2.7/get-pip.py && python get-pip.py
        }
    else
        if grep -Ew '20.04|22.04' /etc/issue &>/dev/null;then apt-get install sshpass -y;else apt-get install python-pip sshpass -y;fi
        [ -f ./get-pip.py ] && python ./get-pip.py || {
        wget https://bootstrap.pypa.io/pip/2.7/get-pip.py && python get-pip.py
        }
    fi
    python -m pip install --upgrade "pip < 21.0"

    which pip || ln -svf `which pip` /usr/bin/pip

    pip -V
    pip install setuptools -U
    pip install --no-cache-dir ansible netaddr
fi




# 在deploy机器做其他node的ssh免密操作
for host in `echo "${nethosts}"`
do
    echo "============ ${netnum}.${host} ===========";

    if [[ ${USER} == 'root' ]];then
        [ ! -f /${USER}/.ssh/id_rsa ] &&\
        ssh-keygen -t rsa -P '' -f /${USER}/.ssh/id_rsa
    else
        [ ! -f /home/${USER}/.ssh/id_rsa ] &&\
        ssh-keygen -t rsa -P '' -f /home/${USER}/.ssh/id_rsa
    fi
    sshpass -p ${rootpasswd} ssh-copy-id -o StrictHostKeyChecking=no ${USER}@${netnum}.${host}

    if cat /etc/redhat-release &>/dev/null;then
        ssh -o StrictHostKeyChecking=no ${USER}@${netnum}.${host} "yum update -y"
    elif cat /etc/openEuler-release &>/dev/null;then
        ssh -o StrictHostKeyChecking=no ${USER}@${netnum}.${host} "yum update -y"
    else
        ssh -o StrictHostKeyChecking=no ${USER}@${netnum}.${host} "apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y"
        [ $? -ne 0 ] && ssh -o StrictHostKeyChecking=no ${USER}@${netnum}.${host} "apt-get -yf install"
    fi
done


# deploy机器下载k8s二进制安装脚本(注：这里下载可能会因网络原因失败，可以多尝试运行该脚本几次)

if [[ ${software_packet} == '' ]];then
    if [[ ! -f ./ezdown ]];then
        curl -C- -fLO --retry 3 https://github.com/easzlab/kubeasz/releases/download/${release}/ezdown
    fi
    # 使用工具脚本下载
    sed -ri "s+^(K8S_BIN_VER=).*$+\1${k8s_ver}+g" ezdown
    chmod +x ./ezdown
    # ubuntu_22         to download package of Ubuntu 22.04
    ./ezdown -D && ./ezdown -P ubuntu_22
    if [[ ${cni} == "cilium" ]];then ./ezdown -X cilium;fi
else
    tar xvf ${software_packet} -C /etc/
    sed -ri "s+^(K8S_BIN_VER=).*$+\1${k8s_ver}+g" ${pwd}/ezdown
    chmod +x ${pwd}/{ezctl,ezdown}
    chmod +x ./ezdown
    ./ezdown -D  # 离线安装 docker，检查本地文件，正常会提示所有文件已经下载完成，并上传到本地私有镜像仓库
    ./ezdown -S  # 启动 kubeasz 容器
fi

# 初始化一个名为$clustername的k8s集群配置

CLUSTER_NAME="$clustername"
${pwd}/ezctl new ${CLUSTER_NAME}
if [[ $? -ne 0 ]];then
    echo "cluster name [${CLUSTER_NAME}] was exist in ${pwd}/clusters/${CLUSTER_NAME}."
    exit 1
fi

if [[ ${software_packet} != '' ]];then
    # 设置参数，启用离线安装
    # 离线安装文档：https://github.com/easzlab/kubeasz/blob/3.6.2/docs/setup/offline_install.md
    sed -i 's/^INSTALL_SOURCE.*$/INSTALL_SOURCE: "offline"/g' ${pwd}/clusters/${CLUSTER_NAME}/config.yml
fi


# to check ansible service
ansible all -m ping

#---------------------------------------------------------------------------------------------------




#修改二进制安装脚本配置 config.yml

sed -ri "s+^(CLUSTER_NAME:).*$+\1 \"${CLUSTER_NAME}\"+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml

## k8s上日志及容器数据存独立磁盘步骤（参考阿里云的）

mkdir -p /var/lib/container/{kubelet,docker,nfs_dir} /var/lib/{kubelet,docker} /nfs_dir

## 不用fdisk分区，直接格式化数据盘 mkfs.ext4 /dev/vdb，按下面添加到fstab后，再mount -a刷新挂载(blkid /dev/sdx)
## cat /etc/fstab     
# UUID=105fa8ff-bacd-491f-a6d0-f99865afc3d6 /                       ext4    defaults        1 1
# /dev/vdb /var/lib/container/ ext4 defaults 0 0
# /var/lib/container/kubelet /var/lib/kubelet none defaults,bind 0 0
# /var/lib/container/docker /var/lib/docker none defaults,bind 0 0
# /var/lib/container/nfs_dir /nfs_dir none defaults,bind 0 0

## tree -L 1 /var/lib/container
# /var/lib/container
# ├── docker
# ├── kubelet
# └── lost+found

# docker data dir
DOCKER_STORAGE_DIR="/var/lib/container/docker"
sed -ri "s+^(STORAGE_DIR:).*$+STORAGE_DIR: \"${DOCKER_STORAGE_DIR}\"+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml
# containerd data dir
CONTAINERD_STORAGE_DIR="/var/lib/container/containerd"
sed -ri "s+^(STORAGE_DIR:).*$+STORAGE_DIR: \"${CONTAINERD_STORAGE_DIR}\"+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml
# kubelet logs dir
KUBELET_ROOT_DIR="/var/lib/container/kubelet"
sed -ri "s+^(KUBELET_ROOT_DIR:).*$+KUBELET_ROOT_DIR: \"${KUBELET_ROOT_DIR}\"+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml
if [[ $clustername != 'aws' ]]; then
    # docker aliyun repo
    REG_MIRRORS="https://pqbap4ya.mirror.aliyuncs.com"
    sed -ri "s+^REG_MIRRORS:.*$+REG_MIRRORS: \'[\"${REG_MIRRORS}\"]\'+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml
fi
# [docker]信任的HTTP仓库
sed -ri "s+127.0.0.1/8+${netnum}.0/24+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml
# disable dashboard auto install
sed -ri "s+^(dashboard_install:).*$+\1 \"no\"+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml


# 融合配置准备(按示例部署命令这里会生成testk8s.boge.com这个域名，部署脚本会基于这个域名签证书，优势是后面访问kube-apiserver，可以基于此域名解析任意IP来访问，灵活性更高)
CLUSEER_WEBSITE="${CLUSTER_NAME}k8s.${domainName}"
lb_num=$(grep -wn '^MASTER_CERT_HOSTS:' ${pwd}/clusters/${CLUSTER_NAME}/config.yml |awk -F: '{print $1}')
lb_num1=$(expr ${lb_num} + 1)
lb_num2=$(expr ${lb_num} + 2)
sed -ri "${lb_num1}s+.*$+  - "${CLUSEER_WEBSITE}"+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml
sed -ri "${lb_num2}s+(.*)$+#\1+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml

# node节点最大pod 数
MAX_PODS="120"
sed -ri "s+^(MAX_PODS:).*$+\1 ${MAX_PODS}+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml

# calico 自建机房都在二层网络可以设置 CALICO_IPV4POOL_IPIP=“off”,以提高网络性能; 公有云上VPC在三层网络，需设置CALICO_IPV4POOL_IPIP: "Always"开启ipip隧道
#sed -ri "s+^(CALICO_IPV4POOL_IPIP:).*$+\1 \"off\"+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml

# 修改二进制安装脚本配置 hosts
# clean old ip
sed -ri '/192.168.1.1/d' ${pwd}/clusters/${CLUSTER_NAME}/hosts
sed -ri '/192.168.1.2/d' ${pwd}/clusters/${CLUSTER_NAME}/hosts
sed -ri '/192.168.1.3/d' ${pwd}/clusters/${CLUSTER_NAME}/hosts
sed -ri '/192.168.1.4/d' ${pwd}/clusters/${CLUSTER_NAME}/hosts
sed -ri '/192.168.1.5/d' ${pwd}/clusters/${CLUSTER_NAME}/hosts

# 输入准备创建ETCD集群的主机位
echo "enter etcd hosts here (example: 203 202 201) ↓"
read -p "" ipnums
for ipnum in `echo ${ipnums}`
do
    echo $netnum.$ipnum
    sed -i "/\[etcd/a $netnum.$ipnum"  ${pwd}/clusters/${CLUSTER_NAME}/hosts
done

# 输入准备创建KUBE-MASTER集群的主机位
echo "enter kube-master hosts here (example: 202 201) ↓"
read -p "" ipnums
for ipnum in `echo ${ipnums}`
do
    echo $netnum.$ipnum
    sed -i "/\[kube_master/a $netnum.$ipnum"  ${pwd}/clusters/${CLUSTER_NAME}/hosts
done

# 输入准备创建KUBE-NODE集群的主机位
echo "enter kube-node hosts here (example: 204 203) ↓"
read -p "" ipnums
for ipnum in `echo ${ipnums}`
do
    echo $netnum.$ipnum
    sed -i "/\[kube_node/a $netnum.$ipnum"  ${pwd}/clusters/${CLUSTER_NAME}/hosts
done

# 配置容器运行时CNI
case ${cni} in
    flannel)
    sed -ri "s+^CLUSTER_NETWORK=.*$+CLUSTER_NETWORK=\"${cni}\"+g" ${pwd}/clusters/${CLUSTER_NAME}/hosts
    ;;
    calico)
    sed -ri "s+^CLUSTER_NETWORK=.*$+CLUSTER_NETWORK=\"${cni}\"+g" ${pwd}/clusters/${CLUSTER_NAME}/hosts
    ;;
    cilium)
    sed -ri "s+^CLUSTER_NETWORK=.*$+CLUSTER_NETWORK=\"${cni}\"+g" ${pwd}/clusters/${CLUSTER_NAME}/hosts
    ;;
    *)
    echo "cni need be flannel or calico or cilium."
    exit 11
esac

# 配置K8S的ETCD数据备份的定时任务
#  https://github.com/easzlab/kubeasz/blob/master/docs/op/cluster_restore.md
if cat /etc/redhat-release &>/dev/null;then
    if ! grep -w '94.backup.yml' /var/spool/cron/root &>/dev/null;then echo "00 00 * * * /usr/local/bin/ansible-playbook -i /etc/kubeasz/clusters/${CLUSTER_NAME}/hosts -e @/etc/kubeasz/clusters/${CLUSTER_NAME}/config.yml /etc/kubeasz/playbooks/94.backup.yml &> /dev/null; find /etc/kubeasz/clusters/${CLUSTER_NAME}/backup/ -type f -name '*.db' -mtime +3|xargs rm -f" >> /var/spool/cron/root;else echo exists ;fi
    chown root.crontab /var/spool/cron/root
    chmod 600 /var/spool/cron/root
    rm -f /var/run/cron.reboot
    service crond restart
elif cat /etc/openEuler-release &>/dev/null;then
    if ! grep -w '94.backup.yml' /var/spool/cron/root &>/dev/null;then echo "00 00 * * * /usr/local/bin/ansible-playbook -i /etc/kubeasz/clusters/${CLUSTER_NAME}/hosts -e @/etc/kubeasz/clusters/${CLUSTER_NAME}/config.yml /etc/kubeasz/playbooks/94.backup.yml &> /dev/null; find /etc/kubeasz/clusters/${CLUSTER_NAME}/backup/ -type f -name '*.db' -mtime +3|xargs rm -f" >> /var/spool/cron/root;else echo exists ;fi
    chown root.crontab /var/spool/cron/root
    chmod 600 /var/spool/cron/root
    rm -f /var/run/cron.reboot
    service crond restart
else
    if ! grep -w '94.backup.yml' /var/spool/cron/crontabs/root &>/dev/null;then echo "00 00 * * * /usr/local/bin/ansible-playbook -i /etc/kubeasz/clusters/${CLUSTER_NAME}/hosts -e @/etc/kubeasz/clusters/${CLUSTER_NAME}/config.yml /etc/kubeasz/playbooks/94.backup.yml &> /dev/null; find /etc/kubeasz/clusters/${CLUSTER_NAME}/backup/ -type f -name '*.db' -mtime +3|xargs rm -f" >> /var/spool/cron/crontabs/root;else echo exists ;fi
    chown root.crontab /var/spool/cron/crontabs/root
    chmod 600 /var/spool/cron/crontabs/root
    rm -f /var/run/crond.reboot
    service cron restart
fi





#---------------------------------------------------------------------------------------------------
# 准备开始安装了
rm -rf ${pwd}/{dockerfiles,docs,.gitignore,pics,dockerfiles} &&\
find ${pwd}/ -name '*.md'|xargs rm -f
read -p "Enter to continue deploy k8s to all nodes >>>" YesNobbb

# now start deploy k8s cluster 
cd ${pwd}/

# to prepare CA/certs & kubeconfig & other system settings 
${pwd}/ezctl setup ${CLUSTER_NAME} 01
sleep 1
# to setup the etcd cluster
${pwd}/ezctl setup ${CLUSTER_NAME} 02
sleep 1
# to setup the container runtime(docker or containerd)
case ${cri} in
    containerd)
    sed -ri "s+^CONTAINER_RUNTIME=.*$+CONTAINER_RUNTIME=\"${cri}\"+g" ${pwd}/clusters/${CLUSTER_NAME}/hosts
    ${pwd}/ezctl setup ${CLUSTER_NAME} 03
    ;;
    docker)
    sed -ri "s+^CONTAINER_RUNTIME=.*$+CONTAINER_RUNTIME=\"${cri}\"+g" ${pwd}/clusters/${CLUSTER_NAME}/hosts
    ${pwd}/ezctl setup ${CLUSTER_NAME} 03
    ;;
    *)
    echo "cri need be containerd or docker."
    exit 11
esac
sleep 1
# to setup the master nodes
${pwd}/ezctl setup ${CLUSTER_NAME} 04
sleep 1
# to setup the worker nodes
${pwd}/ezctl setup ${CLUSTER_NAME} 05
sleep 1
# to setup the network plugin(flannel、calico...)
${pwd}/ezctl setup ${CLUSTER_NAME} 06
sleep 1
# to setup other useful plugins(metrics-server、coredns...)
${pwd}/ezctl setup ${CLUSTER_NAME} 07
sleep 1


k8s_bin_path='/opt/kube/bin'


echo "-------------------------  k8s version list  ---------------------------"
${k8s_bin_path}/kubectl version
echo
echo "-------------------------  All Healthy status check  -------------------"
${k8s_bin_path}/kubectl get componentstatus
echo
echo "-------------------------  k8s cluster info list  ----------------------"
${k8s_bin_path}/kubectl cluster-info
echo
echo "-------------------------  k8s all nodes list  -------------------------"
${k8s_bin_path}/kubectl get node -o wide
echo
echo "-------------------------  k8s all-namespaces's pods list   ------------"
${k8s_bin_path}/kubectl get pod --all-namespaces
echo
echo "-------------------------  k8s all-namespaces's service network   ------"
${k8s_bin_path}/kubectl get svc --all-namespaces
echo
echo "-------------------------  k8s welcome for you   -----------------------"
echo

# you can use k alias kubectl to siample
echo "alias k=kubectl && complete -F __start_kubectl k" >> ~/.bashrc

# get dashboard url
${k8s_bin_path}/kubectl cluster-info|grep dashboard|awk '{print $NF}'|tee -a /root/k8s_results

# get login token
${k8s_bin_path}/kubectl -n kube-system describe secret $(${k8s_bin_path}/kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')|grep 'token:'|awk '{print $NF}'|tee -a /root/k8s_results
echo
echo "you can look again dashboard and token info at  >>> /root/k8s_results <<<"
echo ">>>>>>>>>>>>>>>>> You need to excute command [ reboot ] to restart all nodes <<<<<<<<<<<<<<<<<<<<"
