#!/bin/bash
# auther: boge
# descriptions:  the shell scripts will use ansible to deploy K8S at binary for siample

# 传参检测
[ $# -ne 6 ] && echo -e "Usage: $0 rootpasswd netnum nethosts cri cni k8s-cluster-name\nExample: bash $0 bogedevops 10.0.1 201\ 202\ 203\ 204 [containerd|docker] [calico|flannel] test\n" && exit 11 

# 变量定义
export release=3.0.0
export k8s_ver=v1.19.7  # v1.20.2, v1.19.7, v1.18.15, v1.17.17
rootpasswd=$1
netnum=$2
nethosts=$3
cri=$4
cni=$5
clustername=$6
if ls -1v ./kubeasz*.tar.gz &>/dev/null;then software_packet="$(ls -1v ./kubeasz*.tar.gz )";else software_packet="";fi
pwd="/etc/kubeasz"


# deploy机器升级软件库
if cat /etc/redhat-release &>/dev/null;then
    yum update -y
else
    apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y
    [ $? -ne 0 ] && apt-get -yf install
fi

# deploy机器检测python环境
python2 -V &>/dev/null
if [ $? -ne 0 ];then
    if cat /etc/redhat-release &>/dev/null;then
        yum install gcc openssl-devel bzip2-devel 
        wget https://www.python.org/ftp/python/2.7.16/Python-2.7.16.tgz
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

# deploy机器设置pip安装加速源
if [[ $clustername != 'aws' ]]; then
mkdir ~/.pip
cat > ~/.pip/pip.conf <<CB
[global]
index-url = https://mirrors.aliyun.com/pypi/simple
[install]
trusted-host=mirrors.aliyun.com

CB
fi


# deploy机器安装相应软件包
if cat /etc/redhat-release &>/dev/null;then
    yum install git python-pip sshpass -y
    [ -f ./get-pip.py ] && python ./get-pip.py || {
    wget https://bootstrap.pypa.io/2.7/get-pip.py && python get-pip.py
    }
else
    apt-get install git python-pip sshpass -y
    [ -f ./get-pip.py ] && python ./get-pip.py || {
    wget https://bootstrap.pypa.io/2.7/get-pip.py && python get-pip.py
    }
fi
python -m pip install --upgrade "pip < 21.0"

pip -V
pip install --no-cache-dir ansible netaddr


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
    else
        ssh -o StrictHostKeyChecking=no ${USER}@${netnum}.${host} "apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y"
        [ $? -ne 0 ] && ssh -o StrictHostKeyChecking=no ${USER}@${netnum}.${host} "apt-get -yf install"
    fi
done


# deploy机器下载k8s二进制安装脚本

if [[ ${software_packet} == '' ]];then
    curl -C- -fLO --retry 3 https://github.com/easzlab/kubeasz/releases/download/${release}/ezdown
    sed -ri "s+^(K8S_BIN_VER=).*$+\1${k8s_ver}+g" ezdown
    chmod +x ./ezdown
    # 使用工具脚本下载
    ./ezdown -D && ./ezdown -P
else
    tar xvf ${software_packet} -C /etc/
    chmod +x ${pwd}/{ezctl,ezdown}
fi

# 初始化一个名为my的k8s集群配置

CLUSTER_NAME="$clustername"
${pwd}/ezctl new ${CLUSTER_NAME}
if [[ $? -ne 0 ]];then
    echo "cluster name [${CLUSTER_NAME}] was exist in ${pwd}/clusters/${CLUSTER_NAME}."
    exit 1
fi

if [[ ${software_packet} != '' ]];then
    # 设置参数，启用离线安装
    sed -i 's/^INSTALL_SOURCE.*$/INSTALL_SOURCE: "offline"/g' ${pwd}/clusters/${CLUSTER_NAME}/config.yml
fi


# to check ansible service
ansible all -m ping

#---------------------------------------------------------------------------------------------------




#修改二进制安装脚本配置 config.yml

sed -ri "s+^(CLUSTER_NAME:).*$+\1 \"${CLUSTER_NAME}\"+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml

## k8s上日志及容器数据存独立磁盘步骤（参考阿里云的）

[ ! -d /var/lib/container ] && mkdir -p /var/lib/container/{kubelet,docker}

## cat /etc/fstab     
# UUID=105fa8ff-bacd-491f-a6d0-f99865afc3d6 /                       ext4    defaults        1 1
# /dev/vdb /var/lib/container/ ext4 defaults 0 0
# /var/lib/container/kubelet /var/lib/kubelet none defaults,bind 0 0
# /var/lib/container/docker /var/lib/docker none defaults,bind 0 0

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


# 融合配置准备
CLUSEER_WEBSITE="${CLUSTER_NAME}k8s.gtapp.xyz"
lb_num=$(grep -wn '^MASTER_CERT_HOSTS:' ${pwd}/clusters/${CLUSTER_NAME}/config.yml |awk -F: '{print $1}')
lb_num1=$(expr ${lb_num} + 1)
lb_num2=$(expr ${lb_num} + 2)
sed -ri "${lb_num1}s+.*$+  - "${CLUSEER_WEBSITE}"+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml
sed -ri "${lb_num2}s+(.*)$+#\1+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml

# node节点最大pod 数
MAX_PODS="120"
sed -ri "s+^(MAX_PODS:).*$+\1 ${MAX_PODS}+g" ${pwd}/clusters/${CLUSTER_NAME}/config.yml



# 修改二进制安装脚本配置 hosts
# clean old ip
sed -ri '/192.168.1.1/d' ${pwd}/clusters/${CLUSTER_NAME}/hosts
sed -ri '/192.168.1.2/d' ${pwd}/clusters/${CLUSTER_NAME}/hosts
sed -ri '/192.168.1.3/d' ${pwd}/clusters/${CLUSTER_NAME}/hosts
sed -ri '/192.168.1.4/d' ${pwd}/clusters/${CLUSTER_NAME}/hosts

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
    *)
    echo "cni need be flannel or calico."
    exit 11
esac

# 配置K8S的ETCD数据备份的定时任务
if cat /etc/redhat-release &>/dev/null;then
    if ! grep -w '94.backup.yml' /var/spool/cron/root &>/dev/null;then echo "00 00 * * * `which ansible-playbook` ${pwd}/playbooks/94.backup.yml &> /dev/null" >> /var/spool/cron/root;else echo exists ;fi
    chown root.crontab /var/spool/cron/root
    chmod 600 /var/spool/cron/root
else
    if ! grep -w '94.backup.yml' /var/spool/cron/crontabs/root &>/dev/null;then echo "00 00 * * * `which ansible-playbook` ${pwd}/playbooks/94.backup.yml &> /dev/null" >> /var/spool/cron/crontabs/root;else echo exists ;fi
    chown root.crontab /var/spool/cron/crontabs/root
    chmod 600 /var/spool/cron/crontabs/root
fi
rm /var/run/cron.reboot
service crond restart 




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
# [可选]对集群所有节点进行操作系统层面的安全加固  https://github.com/dev-sec/ansible-os-hardening
#ansible-playbook roles/os-harden/os-harden.yml
#sleep 1
cd `dirname ${software_packet:-/tmp}`


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
#echo ">>>>>>>>>>>>>>>>> You can excute command [ source ~/.bashrc ] <<<<<<<<<<<<<<<<<<<<"
echo ">>>>>>>>>>>>>>>>> You need to excute command [ reboot ] to restart all nodes <<<<<<<<<<<<<<<<<<<<"
rm -f $0
[ -f ${software_packet} ] && rm -f ${software_packet}
#rm -f ${pwd}/roles/deploy/templates/${USER_NAME}-csr.json.j2
#sed -ri "s+${USER_NAME}+admin+g" ${pwd}/roles/prepare/tasks/main.yml

