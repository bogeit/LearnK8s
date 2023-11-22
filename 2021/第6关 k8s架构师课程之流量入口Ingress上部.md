### 第6关 k8s架构师课程之流量入口Ingress上部

大家好，我是博哥爱运维，这节课带来k8s的流量入口ingress，作为业务对外服务的公网入口，它的重要性不言而喻，大家一定要仔细阅读，跟着博哥的教程一步步实操去理解。

我们上面学习了通过Service服务来访问pod资源，另外通过修改Service的类型为NodePort，然后通过一些手段作公网IP的端口映射来提供K8s集群外的访问，但这并不是一种很优雅的方式。

```
通常，services和Pod只能通过集群内网络访问。 所有在边界路由器上的流量都被丢弃或转发到别处。 
从概念上讲，这可能看起来像：

    internet
        |
  ------------
  [ Services ]
```



另外可以我们通过LoadBalancer负载均衡来提供外部流量的的访问，但这种模式对于实际生产来说，用起来不是很方便，而且用这种模式就意味着每个服务都需要有自己的的负载均衡器以及独立的公有IP。

我们这是用Ingress，因为Ingress只需要一个公网IP就能为K8s上所有的服务提供访问，Ingress工作在7层（HTTP），Ingress会根据请求的主机名以及路径来决定把请求转发到相应的服务，如下图所示：



![ingress](f:\update\博哥IT-bogoit.com\images\ingress.png)



```
Ingress是允许入站连接到达集群服务的一组规则。即介于物理网络和群集svc之间的一组转发规则。 
其实就是实现L4 L7的负载均衡:
注意：这里的Ingress并非将外部流量通过Service来转发到服务pod上，而只是通过Service来找到对应的Endpoint来发现pod进行转发

   
    internet
        |
   [ Ingress ]   ---> [ Services ] ---> [ Endpoint ]
   --|-----|--                                 |
   [ Pod,pod,...... ]<-------------------------|
```



要在K8s上面使用Ingress，我们就需要在K8s上部署Ingress-controller控制器，只有它在K8s集群中运行，Ingress依次才能正常工作。Ingress-controller控制器有很多种，比如traefik，但我们这里要用到ingress-nginx这个控制器，它的底层就是用Openresty融合nginx和一些lua规则等实现的。

重点来了，我在讲课中一直强调，本课程带给大家的都是基于生产中实战经验，所以这里我们用的ingress-nginx不是普通的社区版本，而是经过了超大生产流量检验，国内最大的云平台阿里云基于社区版分支出来，进行了魔改而成，更符合生产，基本属于开箱即用，下面是`aliyun-ingress-controller`的介绍：

> 下面介绍只截取了最新的一部分，更多文档资源可以查阅官档：https://developer.aliyun.com/article/598075

```
服务简介
在Kubernetes集群中，Ingress是授权入站连接到达集群服务的规则集合，为您提供七层负载均衡能力，您可以通过 Ingress 配置提供外部可访问的 URL、负载均衡、SSL、基于名称的虚拟主机，阿里云容器服务K8S Ingress Controller在完全兼容社区版本的基础上提供了更多的特性和优化。

版本说明
v0.30.0.2-9597b3685-aliyun:
新增FastCGI Backend支持
默认启用Dynamic SSL Cert Update模式
新增流量Mirror配置支持
升级NGINX版本到1.17.8，OpenResty版本到1.15.8，更新基础镜像为Alpine
新增Ingress Validating Webhook支持
修复CVE-2018-16843、CVE-2018-16844、CVE-2019-9511、CVE-2019-9513和CVE-2019-9516漏洞
[Breaking Change] lua-resty-waf、session-cookie-hash、force-namespace-isolation等配置被废弃；x-forwarded-prefix类型从boolean转成string类型；log-format配置中的the_real_ip变量下个版本将被废弃，统一采用remote_addr替代
同步更新到社区0.30.0版本，更多详细变更记录参考社区Changelog
```



`aliyun-ingress-controller`有一个很重要的修改，就是它支持路由配置的动态更新，大家用过Nginx的可以知道，在修改完Nginx的配置，我们是需要进行nginx -s reload来重加载配置才能生效的，在K8s上，这个行为也是一样的，但由于K8s运行的服务会非常多，所以它的配置更新是非常频繁的，因此，如果不支持配置动态更新，对于在高频率变化的场景下，Nginx频繁Reload会带来较明显的请求访问问题：

1. 造成一定的QPS抖动和访问失败情况
2. 对于长连接服务会被频繁断掉
3. 造成大量的处于shutting down的Nginx Worker进程，进而引起内存膨胀

详细原理分析见这篇文章： https://developer.aliyun.com/article/692732



我们准备来部署`aliyun-ingress-controller`，下面直接是生产中在用的yaml配置，我们保存了aliyun-ingress-nginx.yaml准备开始部署：

> 详细讲解下面yaml配置的每个部分

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-nginx
  labels:
    app: ingress-nginx

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nginx-ingress-controller
  namespace: ingress-nginx
  labels:
    app: ingress-nginx

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: nginx-ingress-controller
  labels:
    app: ingress-nginx
rules:
  - apiGroups:
      - ""
    resources:
      - configmaps
      - endpoints
      - nodes
      - pods
      - secrets
      - namespaces
      - services
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - "extensions"
      - "networking.k8s.io"
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - ""
    resources:
      - events
    verbs:
      - create
      - patch
  - apiGroups:
      - "extensions"
      - "networking.k8s.io"
    resources:
      - ingresses/status
    verbs:
      - update
  - apiGroups:
      - ""
    resources:
      - configmaps
    verbs:
      - create
  - apiGroups:
      - ""
    resources:
      - configmaps
    resourceNames:
      - "ingress-controller-leader-nginx"
    verbs:
      - get
      - update

---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: nginx-ingress-controller
  labels:
    app: ingress-nginx
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: nginx-ingress-controller
subjects:
  - kind: ServiceAccount
    name: nginx-ingress-controller
    namespace: ingress-nginx

---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: ingress-nginx
  name: nginx-ingress-lb
  namespace: ingress-nginx
spec:
  # DaemonSet need:
  # ----------------
  type: ClusterIP
  # ----------------
  # Deployment need:
  # ----------------
#  type: NodePort
  # ----------------
  ports:
  - name: http
    port: 80
    targetPort: 80
    protocol: TCP
  - name: https
    port: 443
    targetPort: 443
    protocol: TCP
  - name: metrics
    port: 10254
    protocol: TCP
    targetPort: 10254
  selector:
    app: ingress-nginx

---
kind: ConfigMap
apiVersion: v1
metadata:
  name: nginx-configuration
  namespace: ingress-nginx
  labels:
    app: ingress-nginx
data:
  keep-alive: "75"
  keep-alive-requests: "100"
  upstream-keepalive-connections: "10000"
  upstream-keepalive-requests: "100"
  upstream-keepalive-timeout: "60"
  allow-backend-server-header: "true"
  enable-underscores-in-headers: "true"
  generate-request-id: "true"
  http-redirect-code: "301"
  ignore-invalid-headers: "true"
  log-format-upstream: '{"@timestamp": "$time_iso8601","remote_addr": "$remote_addr","x-forward-for": "$proxy_add_x_forwarded_for","request_id": "$req_id","remote_user": "$remote_user","bytes_sent": $bytes_sent,"request_time": $request_time,"status": $status,"vhost": "$host","request_proto": "$server_protocol","path": "$uri","request_query": "$args","request_length": $request_length,"duration": $request_time,"method": "$request_method","http_referrer": "$http_referer","http_user_agent":  "$http_user_agent","upstream-sever":"$proxy_upstream_name","proxy_alternative_upstream_name":"$proxy_alternative_upstream_name","upstream_addr":"$upstream_addr","upstream_response_length":$upstream_response_length,"upstream_response_time":$upstream_response_time,"upstream_status":$upstream_status}'
  max-worker-connections: "65536"
  worker-processes: "2"
  proxy-body-size: 20m
  proxy-connect-timeout: "10"
  proxy_next_upstream: error timeout http_502
  reuse-port: "true"
  server-tokens: "false"
  ssl-ciphers: ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA
  ssl-protocols: TLSv1 TLSv1.1 TLSv1.2
  ssl-redirect: "false"
  worker-cpu-affinity: auto

---
kind: ConfigMap
apiVersion: v1
metadata:
  name: tcp-services
  namespace: ingress-nginx
  labels:
    app: ingress-nginx

---
kind: ConfigMap
apiVersion: v1
metadata:
  name: udp-services
  namespace: ingress-nginx
  labels:
    app: ingress-nginx

---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nginx-ingress-controller
  namespace: ingress-nginx
  labels:
    app: ingress-nginx
  annotations:
    component.version: "v0.30.0"
    component.revision: "v1"
spec:
  # Deployment need:
  # ----------------
#  replicas: 1
  # ----------------
  selector:
    matchLabels:
      app: ingress-nginx
  template:
    metadata:
      labels:
        app: ingress-nginx
      annotations:
        prometheus.io/port: "10254"
        prometheus.io/scrape: "true"
        scheduler.alpha.kubernetes.io/critical-pod: ""
    spec:
      # DaemonSet need:
      # ----------------
      hostNetwork: true
      # ----------------
      serviceAccountName: nginx-ingress-controller
      priorityClassName: system-node-critical
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - ingress-nginx
              topologyKey: kubernetes.io/hostname
            weight: 100
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: type
                operator: NotIn
                values:
                - virtual-kubelet
      containers:
        - name: nginx-ingress-controller
          image: registry.cn-beijing.aliyuncs.com/acs/aliyun-ingress-controller:v0.30.0.2-9597b3685-aliyun
          args:
            - /nginx-ingress-controller
            - --configmap=$(POD_NAMESPACE)/nginx-configuration
            - --tcp-services-configmap=$(POD_NAMESPACE)/tcp-services
            - --udp-services-configmap=$(POD_NAMESPACE)/udp-services
            - --publish-service=$(POD_NAMESPACE)/nginx-ingress-lb
            - --annotations-prefix=nginx.ingress.kubernetes.io
            - --enable-dynamic-certificates=true
            - --v=2
          securityContext:
            allowPrivilegeEscalation: true
            capabilities:
              drop:
                - ALL
              add:
                - NET_BIND_SERVICE
            runAsUser: 101
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          ports:
            - name: http
              containerPort: 80
            - name: https
              containerPort: 443
          livenessProbe:
            failureThreshold: 3
            httpGet:
              path: /healthz
              port: 10254
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 10
          readinessProbe:
            failureThreshold: 3
            httpGet:
              path: /healthz
              port: 10254
              scheme: HTTP
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 10
#          resources:
#            limits:
#              cpu: "1"
#              memory: 2Gi
#            requests:
#              cpu: "1"
#              memory: 2Gi
          volumeMounts:
          - mountPath: /etc/localtime
            name: localtime
            readOnly: true
      volumes:
      - name: localtime
        hostPath:
          path: /etc/localtime
          type: File
      nodeSelector:
        boge/ingress-controller-ready: "true"
      tolerations:
      - operator: Exists

      initContainers:
      - command:
        - /bin/sh
        - -c
        - |
          mount -o remount rw /proc/sys
          sysctl -w net.core.somaxconn=65535
          sysctl -w net.ipv4.ip_local_port_range="1024 65535"
          sysctl -w fs.file-max=1048576
          sysctl -w fs.inotify.max_user_instances=16384
          sysctl -w fs.inotify.max_user_watches=524288
          sysctl -w fs.inotify.max_queued_events=16384
        image: registry.cn-beijing.aliyuncs.com/acs/busybox:v1.29.2
        imagePullPolicy: Always
        name: init-sysctl
        securityContext:
          privileged: true
          procMount: Default

---
## Deployment need for aliyun'k8s:
#apiVersion: v1
#kind: Service
#metadata:
#  annotations:
#    service.beta.kubernetes.io/alibaba-cloud-loadbalancer-id: "lb-xxxxxxxxxxxxxxxxxxx"
#    service.beta.kubernetes.io/alibaba-cloud-loadbalancer-force-override-listeners: "true"
#  labels:
#    app: nginx-ingress-lb
#  name: nginx-ingress-lb-local
#  namespace: ingress-nginx
#spec:
#  externalTrafficPolicy: Local
#  ports:
#  - name: http
#    port: 80
#    protocol: TCP
#    targetPort: 80
#  - name: https
#    port: 443
#    protocol: TCP
#    targetPort: 443
#  selector:
#    app: ingress-nginx
#  type: LoadBalancer


```



##### DaemonSet

开始部署：

```shell
# kubectl  apply -f aliyun-ingress-nginx.yaml 
namespace/ingress-nginx created
serviceaccount/nginx-ingress-controller created
clusterrole.rbac.authorization.k8s.io/nginx-ingress-controller created
clusterrolebinding.rbac.authorization.k8s.io/nginx-ingress-controller created
service/nginx-ingress-lb created
configmap/nginx-configuration created
configmap/tcp-services created
configmap/udp-services created
daemonset.apps/nginx-ingress-controller created

# 这里是以daemonset资源的形式进行的安装
# DaemonSet资源和Deployment的yaml配置类似，但不同的是Deployment可以在每个node上运行多个pod副本，但daemonset在每个node上只能运行一个pod副本
# 这里正好就借运行ingress-nginx的情况下，把daemonset这个资源做下讲解

# 我们查看下pod，会发现空空如也，为什么会这样呢？
# kubectl -n ingress-nginx get pod
注意上面的yaml配置里面，我使用了节点选择配置，只有打了我指定lable标签的node节点，也会被允许调度pod上去运行
      nodeSelector:
        boge/ingress-controller-ready: "true"

# 我们现在来打标签
# kubectl label node 10.0.1.201 boge/ingress-controller-ready=true
node/10.0.1.201 labeled
# kubectl label node 10.0.1.202 boge/ingress-controller-ready=true
node/10.0.1.202 labeled

# 接着可以看到pod就被调试到这两台node上启动了
# kubectl -n ingress-nginx get pod -o wide
NAME                             READY   STATUS    RESTARTS   AGE    IP           NODE         NOMINATED NODE   READINESS GATES
nginx-ingress-controller-lchgr   1/1     Running   0          9m1s   10.0.1.202   10.0.1.202   <none>           <none>
nginx-ingress-controller-x87rp   1/1     Running   0          9m6s   10.0.1.201   10.0.1.201   <none>           <none>
```

我们基于前面学到的deployment和service，来创建一个nginx的相应服务资源，保存为nginx.yaml：

> 注意：记得把前面测试的资源删除掉，以防冲突

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx
  name: nginx
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: nginx

---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginx
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - image: nginx
        name: nginx

```

运行它：

```shell
# kubectl apply -f nginx.yaml 
service/nginx created
deployment.apps/nginx created
```

然后准备nginx的ingress配置，保留为nginx-ingress.yaml，并执行它：

```yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: nginx-ingress
spec:
  rules:
    - host: nginx.boge.com
      http:
        paths:
          - backend:
              serviceName: nginx
              servicePort: 80
            path: /
```

```shell
# kubectl apply -f nginx-ingress.yaml 
ingress.extensions/nginx-ingress created

#查看创建的ingress资源
# kubectl get ingress
NAME            CLASS    HOSTS            ADDRESS   PORTS   AGE
nginx-ingress   <none>   nginx.boge.com             80      13s

# 我们在其它节点上，加下本地hosts，来测试下效果
10.0.1.201 nginx.boge.com

# 可以看到请求成功了
[root@node-2 ~]# curl nginx.boge.com
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>

# 回到201节点上，看下ingress-nginx的日志
[root@node-1 ~]# kubectl -n ingress-nginx logs --tail=1 nginx-ingress-controller-x87rp  
{"@timestamp": "2020-11-26T18:16:53+08:00","remote_addr": "10.0.1.202","x-forward-for": "10.0.1.202","request_id": "74440b6d92aca4d64600ffa85c1dee15","remote_user": "-","bytes_sent": 851,"request_time": 0.004,"status": 200,"vhost": "nginx.boge.com","request_proto": "HTTP/1.1","path": "/","request_query": "-","request_length": 78,"duration": 0.004,"method": "GET","http_referrer": "-","http_user_agent":  "curl/7.29.0","upstream-sever":"default-nginx-80","proxy_alternative_upstream_name":"","upstream_addr":"172.20.217.65:80","upstream_response_length":612,"upstream_response_time":0.003,"upstream_status":200}
```



在生产环境中，如果是自建机房，我们通常会在至少2台node节点上运行有ingress-nginx的pod，那么有必要在这两台node上面部署负载均衡软件做调度，来起到高可用的作用，这里我们用haproxy+keepalived，如果你的生产环境是在云上，假设是阿里云，那么你只需要购买一个负载均衡器SLB，将运行有ingress-nginx的pod的节点服务器加到这个SLB的后端来，然后将请求域名和这个SLB的公网IP做好解析即可，目前我们用二进制部署的K8s集群通信架构如下：

![k8s网络架构](f:\update\博哥IT-bogoit.com\images\k8s网络架构.png)

注意在每台node节点上有已经部署有了个haproxy软件，来转发apiserver的请求的，那么，我们只需要选取两台节点，部署keepalived软件并重新配置haproxy，来生成VIP达到ha的效果，这里我们选择在其中两台node节点（10.0.1.202、203）上部署

node上现在已有的haproxy配置：

```shell
# cat /etc/haproxy/haproxy.cfg 
global
        log /dev/log    local1 warning
        chroot /var/lib/haproxy
        user haproxy
        group haproxy
        daemon
        nbproc 1

defaults
        log     global
        timeout connect 5s
        timeout client  10m
        timeout server  10m

listen kube-master
        bind 127.0.0.1:6443
        mode tcp
        option tcplog
        option dontlognull
        option dontlog-normal
        balance roundrobin 
        server 10.0.1.201 10.0.1.201:6443 check inter 10s fall 2 rise 2 weight 1
        server 10.0.1.202 10.0.1.202:6443 check inter 10s fall 2 rise 2 weight 1
```

开始新增ingress端口的转发，修改haproxy配置如下（注意两台节点都记得修改）：

```shell
# cat /etc/haproxy/haproxy.cfg 
global
        log /dev/log    local1 warning
        chroot /var/lib/haproxy
        user haproxy
        group haproxy
        daemon
        nbproc 1

defaults
        log     global
        timeout connect 5s
        timeout client  10m
        timeout server  10m

listen kube-master
        bind 127.0.0.1:6443
        mode tcp
        option tcplog
        option dontlognull
        option dontlog-normal
        balance roundrobin 
        server 10.0.1.201 10.0.1.201:6443 check inter 10s fall 2 rise 2 weight 1
        server 10.0.1.202 10.0.1.202:6443 check inter 10s fall 2 rise 2 weight 1

listen ingress-http
        bind 0.0.0.0:80
        mode tcp
        option tcplog
        option dontlognull
        option dontlog-normal
        balance roundrobin
        server 10.0.1.201 10.0.1.201:80 check inter 2000 fall 2 rise 2 weight 1
        server 10.0.1.202 10.0.1.202:80 check inter 2000 fall 2 rise 2 weight 1

listen ingress-https
        bind 0.0.0.0:443
        mode tcp
        option tcplog
        option dontlognull
        option dontlog-normal
        balance roundrobin
        server 10.0.1.201 10.0.1.201:443 check inter 2000 fall 2 rise 2 weight 1
        server 10.0.1.202 10.0.1.202:443 check inter 2000 fall 2 rise 2 weight 1
```

然后在两台node上分别安装keepalived并进行配置：

```shell
# 安装keepalived
yum install -y keepalived

# 编辑配置修改为如下：
# 这里是node 10.0.1.203
global_defs {
    router_id lb-master
}

vrrp_script check-haproxy {
    script "killall -0 haproxy"
    interval 5
    weight -60
}

vrrp_instance VI-kube-master {
    state MASTER
    priority 120
    unicast_src_ip 10.0.1.203
    unicast_peer {
        10.0.1.204
    }
    dont_track_primary
    interface ens32  # 注意这里的网卡名称修改成你机器真实的内网网卡名称，可用命令ip addr查看
    virtual_router_id 111
    advert_int 3
    track_script {
        check-haproxy
    }
    virtual_ipaddress {
        10.0.1.222
    }
}


# 这里是node 10.0.1.204
global_defs {
    router_id lb-master
}

vrrp_script check-haproxy {
    script "killall -0 haproxy"
    interval 5
    weight -60
}

vrrp_instance VI-kube-master {
    state MASTER
    priority 120
    unicast_src_ip 10.0.1.204
    unicast_peer {
        10.0.1.203
    }
    dont_track_primary
    interface ens32
    virtual_router_id 111
    advert_int 3
    track_script {
        check-haproxy
    }
    virtual_ipaddress {
        10.0.1.222
    }
}

```

全部安装配置完成后，在两台node上重启服务：

```shell
# 重启服务
systemctl restart haproxy.service
systemctl restart keepalived.service

# 查看运行状态
systemctl status haproxy.service 
systemctl status keepalived.service

# 添加开机自启动（haproxy默认安装好就添加了自启动）
systemctl enable keepalived.service
# 查看是否添加成功
systemctl is-enabled keepalived.service 
enabled就代表添加成功了

# 同时我可查看下VIP是否已经生成
[root@node-4 ~]# ip a|grep 222                           
    inet 10.0.1.222/32 scope global ens32
```

现在我们找一台带图形桌面的机器，绑定下hosts，来试试ingress吧

```shell
# 添加一条hosts
10.0.1.222 nginx.boge.com
```

打开浏览器，输入域名回车测试下：

![test-ingress](f:\update\博哥IT-bogoit.com\images\test-ingress.png)









做到这里，是不是有点成就感了呢，在已经知道了ingress能给我们带来什么后，我们回过头来理解Ingress的工作原理，这样掌握ingress会更加稳固，这也是我平时学习的方法

如下图，Client客户端对`nginx.boge.com`进行DNS查询，DNS服务器（我们这里是配的本地hosts）返回了Ingress控制器的IP（也就是我们的VIP：10.0.1.222）。然后Client客户端向Ingress控制器发送HTTP请求，并在请求Host头中指定`nginx.boge.com`。Ingress控制器从该头部确定Client客户端是想访问哪个服务，通过与该服务并联的Endpoint对象查看具体的Pod IP，并将Client客户端的请求转发给其中一个pod。

![ingress-working](f:\update\博哥IT-bogoit.com\images\ingress-working.png)

生产环境正常情况下大部分是一个Ingress对应一个Service服务，但在一些特殊情况，需要复用一个Ingress来访问多个服务的，下面我们来实践下

再创建一个nginx的deployment和service，注意名称修改下不要冲突了

```shell
# kubectl create deployment web --image=nginx
deployment.apps/web created

# kubectl expose deployment web --port=80 --target-port=80
service/web exposed

# 确认下创建结果
# kubectl  get deployments.apps 
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
nginx   1/1     1            1           16h
web     1/1     1            1           45s
# kubectl  get pod
NAME                    READY   STATUS    RESTARTS   AGE
nginx-f89759699-6vgr8   1/1     Running   1          16h
web-5dcb957ccc-nr2m7    1/1     Running   0          54s
# kubectl  get svc
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
kubernetes   ClusterIP   10.68.0.1       <none>        443/TCP   17h
nginx        ClusterIP   10.68.238.54    <none>        80/TCP    16h
web          ClusterIP   10.68.229.231   <none>        80/TCP    16s

# 接着来修改Ingress
# 注意：这里可以通过两种方式来修改K8s正在运行的资源
# 第一种：直接通过edit修改在线服务的资源来生效，这个通常用在测试环境，在实际生产中不建议这么用
kubectl edit ingress nginx-ingress

# 第二种： 通过之前创建ingress的yaml配置，在上面进行修改，再apply更新进K8s，在生产中是建议这么用的，我们这里也用这种方式来修改
# vim nginx-ingress.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /    # 注意这里需要把进来到服务的请求重定向到/，这个和传统的nginx配置是一样的，不配会404
  name: nginx-ingress
spec:
  rules:
    - host: nginx.boge.com
      http:
        paths:
          - backend:
              serviceName: nginx
              servicePort: 80
            path: /nginx  # 注意这里的路由名称要是唯一的
          - backend:       # 从这里开始是新增加的
              serviceName: web
              servicePort: 80
            path: /web  # 注意这里的路由名称要是唯一的
# 开始创建
[root@node-1 ~]# kubectl  apply -f nginx-ingress.yaml 
ingress.extensions/nginx-ingress configured

# 同时为了更直观的看到效果，我们按前面讲到的方法来修改下nginx默认的展示页面
# kubectl exec -it nginx-f89759699-6vgr8 -- bash
echo "i am nginx" > /usr/share/nginx/html/index.html

# kubectl exec -it web-5dcb957ccc-nr2m7 -- bash
echo "i am web" > /usr/share/nginx/html/index.html
```

看下效果吧：

![test-ingress-1](f:\update\博哥IT-bogoit.com\images\test-ingress-1.png)

![test-ingress-2](f:\update\博哥IT-bogoit.com\images\test-ingress-2.png)





因为http属于是明文传输数据不安全，在生产中我们通常会配置https加密通信，现在实战下Ingress的tls配置

```shell
# 这里我先自签一个https的证书

#1. 先生成私钥key
# openssl genrsa -out tls.key 2048
Generating RSA private key, 2048 bit long modulus
..............................................................................................+++
.....+++
e is 65537 (0x10001)

#2.再基于key生成tls证书(注意：这里我用的*.boge.com，这是生成泛域名的证书，后面所有新增加的三级域名都是可以用这个证书的)
# openssl req -new -x509 -key tls.key -out tls.cert -days 360 -subj /CN=*.boge.com

# 看下创建结果
# ll
total 8
-rw-r--r-- 1 root root 1099 Nov 27 11:44 tls.cert
-rw-r--r-- 1 root root 1679 Nov 27 11:43 tls.key

# 在K8s上创建tls的secret（注意默认ns是default）
# kubectl create secret tls mytls --cert=tls.cert --key=tls.key 
secret/mytls created

# 然后修改先的ingress的yaml配置
# cat nginx-ingress.yaml 
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /    # 注意这里需要把进来到服务的请求重定向到/，这个和传统的nginx配置是一样的，不配会404
  name: nginx-ingress
spec:
  rules:
    - host: nginx.boge.com
      http:
        paths:
          - backend:
              serviceName: nginx
              servicePort: 80
            path: /nginx  # 注意这里的路由名称要是唯一的
          - backend:       # 从这里开始是新增加的
              serviceName: web
              servicePort: 80
            path: /web  # 注意这里的路由名称要是唯一的
  tls:    # 增加下面这段，注意缩进格式
      - hosts:
          - nginx.boge.com   # 这里域名和上面的对应
        secretName: mytls    # 这是我先生成的secret

# 进行更新
# kubectl  apply -f nginx-ingress.yaml         
ingress.extensions/nginx-ingress configured
```

现在再来看看https访问的效果：

> 注意：这里因为是我自签的证书，所以浏览器地访问时会提示`您的连接不是私密连接` ，我这里用的谷歌浏览器，直接点`高级`，再点击`继续前往nginx.boge.com（不安全）`

![ingress-tls](f:\update\博哥IT-bogoit.com\images\ingress-tls.png)

