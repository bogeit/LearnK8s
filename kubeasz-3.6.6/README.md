## 将目录文件都下载好，执行下面命令安装（假设你的集群就一台节点10.0.1.201）：
> bash k8s_install_new.sh rootPassword 10.0.1 201 containerd calico boge.com test-cn

```

root@boge-virtual-machine:~# k get node -owide
NAME             STATUS   ROLES    AGE     VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
k8s-10-0-1-201   Ready    master   3h26m   v1.32.3   10.0.1.201    <none>        Ubuntu 22.04.5 LTS   6.8.0-48-generic   containerd://2.0.4

root@boge-virtual-machine:~# k get pod -A
NAMESPACE     NAME                                      READY   STATUS    RESTARTS   AGE
kube-system   calico-kube-controllers-54cdc99cb-lcjfq   1/1     Running   0          3h26m
kube-system   calico-node-5rstc                         1/1     Running   0          3h26m
kube-system   coredns-75dd46b86b-z22dl                  1/1     Running   0          3h25m
kube-system   metrics-server-74f6d6fdd5-mv4j9           1/1     Running   0          3h25m
kube-system   node-local-dns-rbtmw                      1/1     Running   0          3h25m

root@boge-virtual-machine:~# k top pod -A
NAMESPACE     NAME                                      CPU(cores)   MEMORY(bytes)
kube-system   calico-kube-controllers-54cdc99cb-lcjfq   2m           13Mi
kube-system   calico-node-5rstc                         40m          121Mi
kube-system   coredns-75dd46b86b-z22dl                  2m           14Mi
kube-system   metrics-server-74f6d6fdd5-mv4j9           3m           18Mi
kube-system   node-local-dns-rbtmw                      6m           10Mi

```
