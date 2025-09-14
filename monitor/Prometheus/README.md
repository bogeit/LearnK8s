## **Prometheus**：云原生监控领域的绝对王者，让海量指标抓取与查询变得轻而易举。

[https://prometheus.io](https://prometheus.io/)

Kubernetes 和 Prometheus 都是云计算领域非常重要的开源项目，它们都源自 Google 内部大规模生产环境的实践经验。简单来说：

Kubernetes 是 Google 内部容器编排系统 Borg 的开源实现。

Prometheus 则是 Google 内部监控系统 BorgMon 的开源实现。

![prometheus](../pics/prometheus.png)




### 开始部署

#### Kuernetes上

##### 采用prometheus-operator部署

```yaml
1. 解压下载的代码包
wget https://github.com/prometheus-operator/kube-prometheus/archive/refs/tags/v0.16.0.zip
unzip kube-prometheus-0.16.0.zip
rm -f kube-prometheus-0.16.0.zip && cd kube-prometheus-0.16.0


2. 查看当前目录下所有文件里面的image:信息
# find . -type f |xargs grep 'image: [a-z].*/'|sort|uniq|awk -F"image: " '{print $NF}'|sort|uniq

docker.io/cloudnativelabs/kube-router
gcr.io/google_containers/metrics-server-amd64:v0.2.0
ghcr.io/jimmidyson/configmap-reload:v0.15.0
gitpod/workspace-full
grafana/grafana:12.1.0
quay.io/brancz/kube-rbac-proxy:v0.19.1
quay.io/prometheus/alertmanager:v0.28.1
quay.io/prometheus/blackbox-exporter:v0.27.0
quay.io/prometheus/node-exporter:v1.9.1
quay.io/prometheus-operator/prometheus-operator:v0.85.0
quay.io/prometheus/prometheus:v3.5.0
registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.16.0
registry.k8s.io/prometheus-adapter/prometheus-adapter:v0.12.0
quay.io/prometheus-operator/prometheus-config-reloader:v0.85.0  # 注意：这个镜像配置比较特殊，上面命令过滤不出来
quay.io/fabxc/prometheus_demo_service  # 这个需要手动拉上传，github自动化会报错中断



# 由于上面的镜像中，国内网络无法正常摘取，所以博哥将上述所有镜像已转存至阿里云镜像仓库上，用下面命令批量替换下镜像地址即可

find ./ -type f |xargs  sed -ri 's+gcr.io/.*/+registry.cn-beijing.aliyuncs.com/bogeit/+g'
find ./ -type f |xargs  sed -ri 's+quay.io/.*/+registry.cn-beijing.aliyuncs.com/bogeit/+g'
find ./ -type f |xargs  sed -ri 's+docker.io/cloudnativelabs/+registry.cn-beijing.aliyuncs.com/bogeit/+g'
find ./ -type f |xargs  sed -ri 's+grafana/+registry.cn-beijing.aliyuncs.com/bogeit/+g'
find ./ -type f |xargs  sed -ri 's+registry.k8s.io/.*/+registry.cn-beijing.aliyuncs.com/bogeit/+g'
find ./ -type f |xargs  sed -ri 's+gitpod/+registry.cn-beijing.aliyuncs.com/bogeit/+g'
find ./ -type f |xargs  sed -ri 's+ghcr.io/.*/+registry.cn-beijing.aliyuncs.com/bogeit/+g'


3. 开始创建所有服务
kubectl create -f manifests/setup
kubectl create -f manifests/
过一会查看创建结果：
kubectl -n monitoring get all
kubectl -n monitoring get pod -w

# 注意：如果国内镜像也还是拉取很慢，注意观察下kubelet的日志有什么异常没。

# 注意：上面替换镜像地址时，会把grafana的yaml配置误修改两处，我们调整回来即可，不然grafana自带的dashboard模板就没有了
        volumeMounts:
        - mountPath: /var/lib/grafana
          name: grafana-storage
        - mountPath: /etc/registry.cn-beijing.aliyuncs.com/bogeit/provisioning/datasources  # /etc/grafana/provisioning/datasources
          name: grafana-datasources
        - mountPath: /etc/registry.cn-beijing.aliyuncs.com/bogeit/provisioning/dashboards  # /etc/grafana/provisioning/dashboards
          name: grafana-dashboards

# 注意：删除自带的网络策略，否则访问服务都会被阻塞
# https://github.com/prometheus-operator/kube-prometheus/issues/1763#issuecomment-1139553506
kubectl -n monitoring delete networkpolicies.networking.k8s.io --all




#*****（可选操作） 最后注意记得删除下再重新创建一遍，否则kubectl top pod 和用k9s监控pod指标会有问题
kubectl delete apiservice v1beta1.metrics.k8s.io

kubectl apply -f 1.yaml
# cat 1.yaml 
---
apiVersion: apiregistration.k8s.io/v1beta1
kind: APIService
metadata:
  name: v1beta1.metrics.k8s.io
spec:
  service:
    name: metrics-server
    namespace: kube-system
  group: metrics.k8s.io
  version: v1beta1
  insecureSkipTLSVerify: true
  groupPriorityMinimum: 100
  versionPriority: 100


#***** 其实只需要把原本
kubectl edit apiservices.apiregistration.k8s.io v1beta1.metrics.k8s.io 

  service:
    name: prometheus-adapter
    namespace: monitoring
换成
  service:
    name: metrics-server
    namespace: kube-system
就解决问题了



# 附：清空上面部署的prometheus所有服务：
kubectl delete --ignore-not-found=true -f manifests/ -f manifests/setup
```

##### 部署注意事项

```shell
# 稍等片刻，然后查看整体状态：
kubectl -n monitoring get all

# 注意： 如果发现大部分pod都是pending状态，看下是不是node节点没有匹配的label
kubectl label node x.x.x.x kubernetes.io/os=linux
```

##### 创建Ingress(可选)

> ingress-nginx mode

```yaml
# 注意用ingress-nginx时，生成密码的文件必须是auth，密码字母+数字混合吧
#  centos7:   yum install -y httpd-tools
#  htpasswd -bc auth boge bogeit
#  kubectl create secret generic basic-auth --from-file=auth --namespace=monitoring

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/auth-realm: Authentication Required - boge
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/ingress.class: nginx
  name: prometheus-ing
  namespace: monitoring
spec:
  rules:
  - host: prometheus.boge.com
    http:
      paths:
      - backend:
          service:
            name: prometheus-k8s
            port:
              number: 9090
        pathType: ImplementationSpecific


---

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ing
  namespace: monitoring
spec:
  rules:
  - host: grafana.boge.com
    http:
      paths:
      - backend:
          service:
            name: grafana
            port:
              number: 3000
        pathType: ImplementationSpecific


---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/auth-realm: Authentication Required - boge
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/ingress.class: nginx
  name: alertmanager-ing
  namespace: monitoring
spec:
  rules:
  - host: alertmanager.boge.com
    http:
      paths:
      - backend:
          service:
            name: alertmanager-main
            port:
              number: 9093
        pathType: ImplementationSpecific


```

##### 填坑时间到

###### 坑一： kube-controller和kube-schedule的target为0/0

>在相关服务配置里面增加metrics路径白名单
>vim /etc/systemd/system/kube-scheduler.service
>vim /etc/systemd/system/kube-controller-manager.service
>
>--authorization-always-allow-paths=/metrics \
>然后就可以请求到指标数据了
>curl -k https://10.0.1.201:10257/metrics
>curl -k https://10.0.1.201:10259/metrics

```yaml
apiVersion: v1
kind: Service
metadata:
  namespace: kube-system
  name: kube-controller-manager
  labels:
    app.kubernetes.io/name: kube-controller-manager
spec:
  type: ClusterIP
  clusterIP: None
  ports:
  - name: https-metrics  # 注意这里的名称要和这里面的port名称一致 k -n monitoring get servicemonitors.monitoring.coreos.com kube-scheduler
    port: 10257  #查看服务端口 ss -tulnp|grep kube|egrep 'kube-controller|kube-scheduler'
    targetPort: 10257
    protocol: TCP
---
apiVersion: v1
kind: Service
metadata:
  namespace: kube-system
  name: kube-scheduler
  labels:
    app.kubernetes.io/name: kube-scheduler
spec:
  type: ClusterIP
  clusterIP: None
  ports:
  - name: https-metrics  # 注意这里的名称要和这里面的port名称一致 k -n monitoring get servicemonitors.monitoring.coreos.com kube-scheduler
    port: 10259  #查看服务端口 ss -tulnp|grep kube|egrep 'kube-controller|kube-scheduler'
    targetPort: 10259
    protocol: TCP

---

apiVersion: v1
kind: Endpoints
metadata:
  labels:
    app.kubernetes.io/name: kube-controller-manager
  name: kube-controller-manager
  namespace: kube-system
subsets:
- addresses:
  - ip: 10.0.1.202
  - ip: 10.0.1.203
  - ip: 10.0.1.204
  ports:
  - name: https-metrics  # 注意这里的名称要和这里面的port名称一致 k -n monitoring get servicemonitors.monitoring.coreos.com kube-controller-manager
    port: 10257  #查看服务端口 ss -tulnp|grep kube|egrep 'kube-controller|kube-scheduler'
    protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  labels:
    app.kubernetes.io/name: kube-scheduler
  name: kube-scheduler
  namespace: kube-system
subsets:
- addresses:
  - ip: 10.0.1.202
  - ip: 10.0.1.203
  - ip: 10.0.1.204
  ports:
  - name: https-metrics  # 注意这里的名称要和这里面的port名称一致 k -n monitoring get servicemonitors.monitoring.coreos.com kube-controller-manager
    port: 10259  #查看服务端口 ss -tulnp|grep kube|egrep 'kube-controller|kube-scheduler'
    protocol: TCP

```

###### 坑二： 监控ingress-nginx的指标问题修复

```yaml
# 查看prometheus日志报错如下：
#   kubectl -n monitoring logs prometheus-k8s-1 -c prometheus

cannot list resource \"pods\" in API group \"\" in the namespace \"ingress-nginx\"

# 需要修改prometheus的clusterrole
#   kubectl edit clusterrole prometheus-k8s

apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-k8s
rules:
- apiGroups:
  - ""
  resources:
  - nodes
  - services
  - endpoints
  - pods
  - nodes/proxy
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - configmaps
  - nodes/metrics
  verbs:
  - get
- nonResourceURLs:
  - /metrics
  verbs:
  - get
```



##### 数据持久化配置

###### grafana

```yaml
# 挂载独立新配置到grafana，实现sso登陆

      containers:
......
        volumeMounts:
        - mountPath: /var/lib/grafana
          name: grafana-storage


      volumes:
      - name: grafana-storage
        persistentVolumeClaim:
          claimName: grafana

---
# pvc配置
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: grafana
  namespace: monitoring
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 20Gi
  storageClassName: nfs-dynamic-class
---
```

###### prometheus

>  kubectl -n monitoring edit prometheus k8s

```yaml
spec:
......
  retention: 60d
  retentionSize: 100GB
  walCompression: true
  storage:
    volumeClaimTemplate:
      spec:
        accessModes: [ "ReadWriteOnce" ]
        storageClassName: "nfs-dynamic-class"
        resources:
          requests:
            storage: 100Gi
```





##### 第三方服务监控

早期，只有少部分服务能自暴露metrics指标出来提供prometheus采集，其他只能依靠编写exporter服务来收集数据暴露给prometheus

现在，大部分服务都已经支持自己暴露metrics指标出来了哦。

###### 监控二进制部署的etcd集群

> 注意下面的ETCD集群IP地址换成你实际的

```yaml
# 如果你是独立的二进制方式启动的 etcd 集群，同样将对应的证书保存到集群中的一个 secret 对象中去即可
# 可以先在etcd集群其中一个节点，用下面的命令手动查看下etcd暴露的metrics指标值
#  curl --cacert /etc/kubernetes/ssl/ca.pem --cert /etc/kubernetes/ssl/etcd.pem  --key /etc/kubernetes/ssl/etcd-key.pem https://10.0.1.201:2379/metrics

# 上面测试没问题，就创建这个secret
kubectl -n monitoring create secret generic etcd-certs --from-file=/etc/kubernetes/ssl/etcd.pem   --from-file=/etc/kubernetes/ssl/etcd-key.pem   --from-file=/etc/kubernetes/ssl/ca.pem

# 引用这个secrets
kubectl -n monitoring edit prometheus k8s 
spec:
...
  secrets:
  - etcd-certs
  
# 查找pod里面生成的证书位置，方便在下面的 servicemonitor里面填写
kubectl -n monitoring exec -it prometheus-k8s-0 -- sh
/prometheus $ ls /etc/prometheus/secrets/etcd-certs/
ca.pem        etcd-key.pem  etcd.pem


# cat etcd-prometheus.yaml 
apiVersion: v1
kind: Service
metadata:
  name: etcd-k8s
  namespace: monitoring
  labels:
    k8s-app: etcd
spec:
  type: ClusterIP
  clusterIP: None
  ports:
  - name: api
    port: 2379
    protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: etcd-k8s
  namespace: monitoring
  labels:
    k8s-app: etcd
subsets:
- addresses:
  - ip: 10.0.1.202
    nodeName: 10.0.1.202
  - ip: 10.0.1.203
    nodeName: 10.0.1.203
  - ip: 10.0.1.204
    nodeName: 10.0.1.204
  ports:
  - name: api
    port: 2379
    protocol: TCP
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: etcd-k8s
  namespace: monitoring
  labels:
    k8s-app: etcd-k8s
spec:
  jobLabel: k8s-app
  endpoints:
  - port: api
    interval: 30s
    scheme: https
    tlsConfig:
      caFile: /etc/prometheus/secrets/etcd-certs/ca.pem
      certFile: /etc/prometheus/secrets/etcd-certs/etcd.pem
      keyFile: /etc/prometheus/secrets/etcd-certs/etcd-key.pem
      #use insecureSkipVerify only if you cannot use a Subject Alternative Name
      insecureSkipVerify: true 
  selector:
    matchLabels:
      k8s-app: etcd
  namespaceSelector:
    matchNames:
    - monitoring
```



###### 使用exporter来实现postgres监控指标的收集

```yaml
# grafaba json模板：   https://grafana.com/grafana/dashboards/9628-postgresql-database/

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-exporter
  labels:
    app: postgres-exporter
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-exporter
  template:
    metadata:
      labels:
        app: postgres-exporter
    spec:
      containers:
      - name: postgres-exporter
        image: registry.cn-beijing.aliyuncs.com/bogeit/postgres-exporter:master
        ports:
        - containerPort: 9187
        env:
        - name: DATA_SOURCE_NAME
          value: "postgresql://boge:bogeit@xxx-postgresql.test:5432/pgdb?sslmode=disable"

---
# 通过svc地址可以查看metrics指标：  curl x.x.x.x:9187/metrics
apiVersion: v1
kind: Service
metadata:
  name: postgres-exporter
  labels:
    app: postgres-exporter
spec:
  selector:
    app: postgres-exporter
  ports:
  - name: metrics
    port: 9187
    targetPort: 9187
    protocol: TCP


---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgres-exporter
  labels:
    release: prometheus  # 确保此 release 标签与 Prometheus 配置匹配(kubectl -n monitoring get prometheus k8s  -o yaml |grep serviceMonitorSelector  默认是{}空的表示选择所有)
spec:
  selector:
    matchLabels:
      app: postgres-exporter  # 对应我们之前创建的 Service 的 label
  endpoints:
  - port: metrics  # 与 Service 的 port 名称对应（或者直接使用 9187）
    interval: 15s   # 抓取指标的间隔时间
    path: /metrics
    scheme: http
  namespaceSelector:
    matchNames:
    - test # 替换成 Postgres Exporter 部署所在的命名空间
```

###### 很全的第三方报警规则

 https://github.com/samber/awesome-prometheus-alerts



##### 监控报警配置

###### 默认报警规则调整

```yaml
修改默认的k8s层面资源监控报警
# kubectl -n monitoring edit PrometheusRule kubernetes-monitoring-rules

启用node节点内存报警
# kubectl -n monitoring edit PrometheusRule node-exporter-rules
在里面已有这个内存使用率取值规则：
    - expr: |
        max by (instance) (1 - (
          node_memory_MemAvailable_bytes{job="node-exporter"}
        /
          node_memory_MemTotal_bytes{job="node-exporter"}
        ))
      record: instance:node_memory_utilisation:ratio

我们只需要在上面使用这个规则作对比报警即可：
    - alert: HighMemoryUsage
      annotations:
        description: '{{ $labels.instance }} 上1分钟内存使用率: {{ printf "%.2f" $value }}%大于60%'
        summary: '{{ $labels.instance }} 上1分钟内存使用率: {{ printf "%.2f" $value }}%大于60%'
      expr: instance:node_memory_utilisation:ratio * 100 > 60
      for: 1m
      labels:
        severity: warning
        
        
启用node节点cpu报警
# kubectl -n monitoring edit PrometheusRule node-exporter-rules
在里面已有这个cpu使用率取值规则：
    - expr: |
        max by (instance) (1 - avg without (cpu, mode) (
          rate(node_cpu_seconds_total{job="node-exporter", mode="idle"}[5m])
        ))
      record: instance:node_cpu_utilisation:rate5m

我们只需要在上面使用这个规则作对比报警即可：
    - alert: HighCpuUsage
      annotations:
        description: '{{ $labels.instance }} 上5分钟平均CPU使用率: {{ printf "%.2f" $value }}%大于70%'
        summary: '{{ $labels.instance }} 上5分钟平均CPU使用率: {{ printf "%.2f" $value }}%大于70%'
      expr: instance:node_cpu_utilisation:rate5m * 100 > 70
      for: 5m
      labels:
        severity: warning


启用node节点磁盘使用率报警
# kubectl -n monitoring edit PrometheusRule node-exporter-rules
添加磁盘使用率取值规则：
    - expr:  max by (instance, device) ((1 - node_filesystem_avail_bytes{job="node-exporter",fstype=~"ext4|xfs"} / node_filesystem_size_bytes{job="node-exporter",fstype=~"ext4|xfs"}) * 100)
      record: node_exporter:disk:used:percent
      labels:
        desc: "节点的磁盘的使用百分比"
        unit: "%"
        job: "node-exporter"


我们只需要在上面使用这个规则作对比报警即可：
    - alert: HighDiskUsage
      annotations:
        description: '{{ $labels.instance }} 磁盘: {{ $labels.device }} 使用率: {{ printf "%.2f" $value }}% 高于80%'
        summary: '{{ $labels.instance }} 磁盘: {{ $labels.device }} 使用率: {{ printf "%.2f" $value }}% 高于80%'
      expr: node_exporter:disk:used:percent > 80
      for: 5m
      labels:
        severity: warning




    - alert: HighDiskUsage
      annotations:
        description: '{{ $labels.instance }} 磁盘: {{ $labels.device }} inode使用率: {{ printf "%.2f" $value }}% 高于80%'
        summary: '{{ $labels.instance }} 磁盘: {{ $labels.device }} inode使用率: {{ printf "%.2f" $value }}% 高于80%'
      expr: node_exporter:filesystem:used:percent > 80
      for: 5m
      labels:
        severity: warning
```

###### 报警配置文件-alertmanager.yaml

```yaml
#  kubectl -n monitoring delete secret alertmanager-main
#  kubectl -n monitoring create secret generic  alertmanager-main --from-file=alertmanager.yaml
#
# global块配置下的配置选项在本配置文件内的所有配置项下可见
global:
  # 在Alertmanager内管理的每一条告警均有两种状态: "resolved"或者"firing". 在altermanager首次发送告警通知后, 该告警会一直处于firing状态,设置resolve_timeout可以指定处于firing状态的告警间隔多长时间会被设置为resolved状态, 在设置为resolved状态的告警后,altermanager不会再发送firing的告警通知.
#  resolve_timeout: 1h
  resolve_timeout: 1h

  # 告警通知模板
templates:
- '/etc/altermanager/config/*.tmpl'

# route: 根路由,该模块用于该根路由下的节点及子路由routes的定义. 子树节点如果不对相关配置进行配置，则默认会从父路由树继承该配置选项。每一条告警都要进入route，即要求配置选项group_by的值能够匹配到每一条告警的至少一个labelkey(即通过POST请求向altermanager服务接口所发送告警的labels项所携带的<labelname>)，告警进入到route后，将会根据子路由routes节点中的配置项match_re或者match来确定能进入该子路由节点的告警(由在match_re或者match下配置的labelkey: labelvalue是否为告警labels的子集决定，是的话则会进入该子路由节点，否则不能接收进入该子路由节点).
route:
  # 例如所有labelkey:labelvalue含cluster=A及altertname=LatencyHigh labelkey的告警都会被归入单一组中
  group_by: ['job', 'altername', 'cluster', 'service','severity']
  # 若一组新的告警产生，则会等group_wait后再发送通知，该功能主要用于当告警在很短时间内接连产生时，在group_wait内合并为单一的告警后再发送
#  group_wait: 30s
  group_wait: 30s
  # 再次告警时间间隔
#  group_interval: 5m
  group_interval: 5m
  # 如果一条告警通知已成功发送，且在间隔repeat_interval后，该告警仍然未被设置为resolved，则会再次发送该告警通知
#  repeat_interval: 12h
  repeat_interval: 3h
  # 默认告警通知接收者，凡未被匹配进入各子路由节点的告警均被发送到此接收者
  receiver: 'webhook'
  # 上述route的配置会被传递给子路由节点，子路由节点进行重新配置才会被覆盖

  # 子路由树
  # 重要：调整路由顺序，info优先处理
  routes:
  # 1. 首先捕获 InfoInhibitor 告警
  - match:
      alertname: InfoInhibitor
    receiver: 'null'
    continue: false  # 阻止继续匹配
    
  # 2. 捕获所有 info 级别告警
  - match:
      severity: info
    receiver: 'null'
    continue: false  
  # 该配置选项使用正则表达式来匹配告警的labels，以确定能否进入该子路由树
  # match_re和match均用于匹配labelkey为service,labelvalue分别为指定值的告警，被匹配到的告警会将通知发送到对应的receiver
  # 3. 其他业务路由放在后面
  - match_re:
      service: ^(foo1|foo2|baz)$
    receiver: 'webhook'
    # 在带有service标签的告警同时有severity标签时，他可以有自己的子路由，同时具有severity != critical的告警则被发送给接收者team-ops-wechat,对severity == critical的告警则被发送到对应的接收者即team-ops-pager
    routes:
    - match:
        severity: critical
      receiver: 'webhook'
  # 比如关于数据库服务的告警，如果子路由没有匹配到相应的owner标签，则都默认由team-DB-pager接收
  - match:
      service: database
    receiver: 'webhook'
  # 我们也可以先根据标签service:database将数据库服务告警过滤出来，然后进一步将所有同时带labelkey为database
  - match:
      severity: critical
    receiver: 'webhook'
# 关键：完整的抑制规则
inhibit_rules:
  # 1. 当有 critical 时抑制相同资源的 warning
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'namespace', 'service']
  
  # 2. 当有 warning/critical 时抑制相同 namespace 的 info
  - source_match_re:
      severity: 'warning|critical'
    target_match:
      severity: 'info'
    equal: ['namespace']
  
  # 3. 专门针对 InfoInhibitor 的抑制
  - source_match_re:
      severity: 'warning|critical'
    target_match:
      alertname: InfoInhibitor
    equal: ['namespace']
  #
# 收件人配置
receivers:
- name: 'webhook'
  webhook_configs:
  - url: 'http://10.0.1.203:7777'
    send_resolved: true
- name: 'null'
  # 确保是真正的空接收器
  webhook_configs: [] 
```

###### 报警配置生效

```yaml
# 通过这里可以获取需要创建的报警配置secret名称
# kubectl -n monitoring edit statefulsets.apps alertmanager-main
...
      volumes:
      - name: config-volume
        secret:
          defaultMode: 420
          secretName: alertmanager-main  # 新版本这里为 alertmanager-main-generated，无需理会，照样按下面创建alertmanager.yaml即可
...

# 注意事先在配置文件 alertmanager.yaml 里面编辑好收件人等信息 ，再执行下面的命令(配置更新就会自动加载)
kubectl -n monitoring delete secrets alertmanager-main
kubectl -n monitoring create secret generic  alertmanager-main --from-file=alertmanager.yaml --from-file=mail-template.tmpl

```

###### 启动报警发送服务

```yaml
# 启动 prometheus alarm agent
./prometheus -port 7777 -url "http://10.0.1.202:9999/send" -token "xxxxxx" -dataSourceType "PrometheusTest" -region "hb" -ip "1.6.7.8" -webhookType "feishuv2card" -webhookID "xx-xx-xx-xx-xx-xx"

# 启动报警中心服务端(可选)
./server
```





#### 传统主机上

##### docker容器化运行prometheus

> docker容器化运行prometheus，来监控传统主机性能指标，并通过自己开发的webhook服务端转发报警消息到钉钉、飞书或企业微信。

###### 部署 node-exporter

```yaml
## docker-compose.yml
version: '2.20'

services:
  node-exporter:
    image: registry.cn-beijing.aliyuncs.com/bogeit/node-exporter:v1.9.1
    container_name: node-exporter
    restart: always
    ports:
      - "9100:9100"
    expose:
      - "9100"
    networks:
      node-exporter:
        aliases:
          - node-exporter

networks:
  node-exporter:
    driver: bridge

## 部署命令
docker-compose -f ./prometheus/node-exporter/docker-compose.yml up -d
docker-compose -f ./prometheus/node-exporter/docker-compose.yml ps
docker-compose -f ./prometheus/node-exporter/docker-compose.yml down -v
```



###### 准备prometheus-server配置

```yaml
# 先准备好配置文件
## conf/alertmanager.yml
global:
  resolve_timeout: 5m #处理超时时间，默认为5min

route:
  group_by: ['alertname'] # 报警分组依据
  group_wait: 10s # 最初即第一次等待多久时间发送一组警报的通知
  group_interval: 10s # 在发送新警报前的等待时间
  repeat_interval: 1m # 发送重复警报的周期 对于email配置中，此项不可以设置过低，否则将会由于邮件发送太多频繁，被smtp服务器拒绝
  receiver: 'live-monitoring' # 发送警报的接收者的名称，以下receivers name的名称

receivers:
  - name: 'live-monitoring'
    webhook_configs:
    - url: 'http://10.0.1.203:7777'
      send_resolved: true

## conf/prometheus.yml
global:
  scrape_interval:     15s 
  evaluation_interval: 15s 

alerting:
  alertmanagers:
  - static_configs:
    - targets: ['alertmanager:9093']


rule_files:
  - "rules/*rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
    - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    scrape_interval: 8s
    static_configs:
      - targets:
         - "10.0.0.202:9100"
         - "10.0.0.203:9100"
         - "10.0.0.204:9100"


## rules/node-exporter-alert-rules.yml
groups:
  - name: node-exporter-alert
    rules:
    - alert: node-exporter-down
      expr: node_exporter:up == 0 
      for: 1m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} 宕机了"  
        description: "instance: {{ $labels.instance }} \n- job: {{ $labels.job }} 关机了， 时间已经1分钟了。" 
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"
    
    - alert: node-exporter-cpu-high 
      expr:  node_exporter:cpu:total:percent > 50
      for: 3m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} cpu 使用率高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"
        
    - alert: node-exporter-cpu-iowait-high 
      expr:  node_exporter:cpu:iowait:percent >= 12
      for: 3m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} cpu iowait 使用率高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"
        
    - alert: node-exporter-load-load1-high 
      expr:  (node_exporter:load:load1) > (node_exporter:cpu:count) * 1.2
      for: 3m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} load1 使用率高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-memory-high
      expr:  node_exporter:memory:used:percent > 85
      for: 3m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} memory 使用率高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-disk-high
      expr:  node_exporter:disk:used:percent > 88
      for: 10m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} disk 使用率高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-disk-read:count-high
      expr:  node_exporter:disk:read:count:rate > 3000
      for: 2m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} iops read 使用率高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-disk-write-count-high
      expr:  node_exporter:disk:write:count:rate > 3000
      for: 2m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} iops write 使用率高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"
        
    - alert: node-exporter-disk-read-mb-high
      expr:  node_exporter:disk:read:mb:rate > 60 
      for: 2m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} 读取字节数 高于 {{ $value }}"  
        description: ""    
        instance: "{{ $labels.instance }}"
        value: "{{ $value }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-disk-write-mb-high
      expr:  node_exporter:disk:write:mb:rate > 60
      for: 2m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} 写入字节数 高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-filefd-allocated-percent-high 
      expr:  node_exporter:filefd_allocated:percent > 80
      for: 10m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} 打开文件描述符 高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-network-netin-error-rate-high
      expr:  node_exporter:network:netin:error:rate > 4
      for: 1m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} 包进入的错误速率 高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"
        
    - alert: node-exporter-network-netin-packet-rate-high
      expr:  node_exporter:network:netin:packet:rate > 35000
      for: 1m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} 包进入速率 高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-network-netout-packet-rate-high
      expr:  node_exporter:network:netout:packet:rate > 35000
      for: 1m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} 包流出速率 高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-network-tcp-total-count-high
      expr:  node_exporter:network:tcp:total:count > 40000
      for: 1m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} tcp连接数量 高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-process-zoom-total-count-high 
      expr:  node_exporter:process:zoom:total:count > 10
      for: 10m
      labels: 
        severity: info
      annotations: 
        summary: "bogeit-instance: {{ $labels.instance }} 僵死进程数量 高于 {{ $value }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"

    - alert: node-exporter-time-offset-high
      expr:  node_exporter:time:offset > 0.03
      for: 2m
      labels: 
        severity: info
      annotations:
        summary: "bogeit-instance: {{ $labels.instance }} {{ $labels.desc }}  {{ $value }} {{ $labels.unit }}"  
        description: ""    
        value: "{{ $value }}"
        instance: "{{ $labels.instance }}"
        grafana: "http://xxxxxxxx.com/d/node-exporter/node-exporter?orgId=1&var-instance={{ $labels.instance }} "
        console: "https://ecs.console.aliyun.com/#/server/{{ $labels.instanceid }}/detail?regionId=cn-beijing"
        cloudmonitor: "https://cloudmonitor.console.aliyun.com/#/hostDetail/chart/instanceId={{ $labels.instanceid }}&system=&region=cn-beijing&aliyunhost=true"
        id: "{{ $labels.instanceid }}"
        type: "aliyun_meta_ecs_info"




## rules/node-exporter-record-rules.yml
groups:
  - name: node-exporter-record
    rules:
    - expr: up{job=~"node-exporter"}
      record: node_exporter:up
      labels:
        desc: "节点是否在线, 在线1,不在线0"
        unit: " "
        job: "node-exporter"

    - expr: time() - node_boot_time_seconds{}
      record: node_exporter:node_uptime
      labels:
        desc: "节点的运行时间"
        unit: "s"
        job: "node-exporter"

    - expr: (1 - avg by (environment,instance) (irate(node_cpu_seconds_total{job="node-exporter",mode="idle"}[5m])))  * 100 
      record: node_exporter:cpu:total:percent
      labels:
        desc: "节点的cpu总消耗百分比"
        unit: "%"
        job: "node-exporter"

    - expr: (avg by (environment,instance) (irate(node_cpu_seconds_total{job="node-exporter",mode="idle"}[5m])))  * 100
      record: node_exporter:cpu:idle:percent
      labels:
        desc: "节点的cpu idle百分比"
        unit: "%"
        job: "node-exporter"

    - expr: (avg by (environment,instance) (irate(node_cpu_seconds_total{job="node-exporter",mode="iowait"}[5m])))  * 100
      record: node_exporter:cpu:iowait:percent
      labels:
        desc: "节点的cpu iowait百分比"
        unit: "%"
        job: "node-exporter"

    - expr: (avg by (environment,instance) (irate(node_cpu_seconds_total{job="node-exporter",mode="system"}[5m])))  * 100
      record: node_exporter:cpu:system:percent
      labels:
        desc: "节点的cpu system百分比"
        unit: "%"
        job: "node-exporter"

    - expr: (avg by (environment,instance) (irate(node_cpu_seconds_total{job="node-exporter",mode="user"}[5m])))  * 100
      record: node_exporter:cpu:user:percent
      labels:
        desc: "节点的cpu user百分比"
        unit: "%"
        job: "node-exporter"

    - expr: (avg by (environment,instance) (irate(node_cpu_seconds_total{job="node-exporter",mode=~"softirq|nice|irq|steal"}[5m])))  * 100
      record: node_exporter:cpu:other:percent
      labels:
        desc: "节点的cpu 其他的百分比"
        unit: "%"
        job: "node-exporter"

    - expr: node_memory_MemTotal_bytes{job="node-exporter"}
      record: node_exporter:memory:total
      labels:
        desc: "节点的内存总量"
        unit: byte
        job: "node-exporter"

    - expr: node_memory_MemFree_bytes{job="node-exporter"}
      record: node_exporter:memory:free
      labels:
        desc: "节点的剩余内存量"
        unit: byte
        job: "node-exporter"

    - expr: node_memory_MemTotal_bytes{job="node-exporter"} - node_memory_MemFree_bytes{job="node-exporter"}
      record: node_exporter:memory:used
      labels:
        desc: "节点的已使用内存量"
        unit: byte
        job: "node-exporter"

    - expr: node_memory_MemTotal_bytes{job="node-exporter"} - node_memory_MemAvailable_bytes{job="node-exporter"}
      record: node_exporter:memory:actualused
      labels:
        desc: "节点用户实际使用的内存量"
        unit: byte
        job: "node-exporter"

    - expr: (1-(node_memory_MemAvailable_bytes{job="node-exporter"} / (node_memory_MemTotal_bytes{job="node-exporter"})))* 100
      record: node_exporter:memory:used:percent
      labels:
        desc: "节点的内存使用百分比"
        unit: "%"
        job: "node-exporter"

    - expr: ((node_memory_MemAvailable_bytes{job="node-exporter"} / (node_memory_MemTotal_bytes{job="node-exporter"})))* 100
      record: node_exporter:memory:free:percent
      labels:
        desc: "节点的内存剩余百分比"
        unit: "%"
        job: "node-exporter"

    - expr: sum by (instance) (node_load1{job="node-exporter"})
      record: node_exporter:load:load1
      labels:
        desc: "系统1分钟负载"
        unit: " "
        job: "node-exporter"

    - expr: sum by (instance) (node_load5{job="node-exporter"})
      record: node_exporter:load:load5
      labels:
        desc: "系统5分钟负载"
        unit: " "
        job: "node-exporter"

    - expr: sum by (instance) (node_load15{job="node-exporter"})
      record: node_exporter:load:load15
      labels:
        desc: "系统15分钟负载"
        unit: " "
        job: "node-exporter"

    - expr: node_filesystem_size_bytes{job="node-exporter" ,fstype=~"ext4|xfs"}
      record: node_exporter:disk:usage:total
      labels:
        desc: "节点的磁盘总量"
        unit: byte
        job: "node-exporter"

    - expr: node_filesystem_avail_bytes{job="node-exporter",fstype=~"ext4|xfs"}
      record: node_exporter:disk:usage:free
      labels:
        desc: "节点的磁盘剩余空间"
        unit: byte
        job: "node-exporter"

    - expr: node_filesystem_size_bytes{job="node-exporter",fstype=~"ext4|xfs"} - node_filesystem_avail_bytes{job="node-exporter",fstype=~"ext4|xfs"}
      record: node_exporter:disk:usage:used
      labels:
        desc: "节点的磁盘使用的空间"
        unit: byte
        job: "node-exporter"

    - expr:  (1 - node_filesystem_avail_bytes{job="node-exporter",fstype=~"ext4|xfs"} / node_filesystem_size_bytes{job="node-exporter",fstype=~"ext4|xfs"}) * 100
      record: node_exporter:disk:used:percent
      labels:
        desc: "节点的磁盘的使用百分比"
        unit: "%"
        job: "node-exporter"

    - expr: irate(node_disk_reads_completed_total{job="node-exporter"}[1m])
      record: node_exporter:disk:read:count:rate
      labels:
        desc: "节点的磁盘读取速率"
        unit: "次/秒"
        job: "node-exporter"

    - expr: irate(node_disk_writes_completed_total{job="node-exporter"}[1m])
      record: node_exporter:disk:write:count:rate
      labels:
        desc: "节点的磁盘写入速率"
        unit: "次/秒"
        job: "node-exporter"

    - expr: (irate(node_disk_written_bytes_total{job="node-exporter"}[1m]))/1024/1024
      record: node_exporter:disk:read:mb:rate
      labels:
        desc: "节点的设备读取MB速率"
        unit: "MB/s"
        job: "node-exporter"

    - expr: (irate(node_disk_read_bytes_total{job="node-exporter"}[1m]))/1024/1024
      record: node_exporter:disk:write:mb:rate
      labels:
        desc: "节点的设备写入MB速率"
        unit: "MB/s"
        job: "node-exporter"

    - expr:   (1 -node_filesystem_files_free{job="node-exporter",fstype=~"ext4|xfs"} / node_filesystem_files{job="node-exporter",fstype=~"ext4|xfs"}) * 100
      record: node_exporter:filesystem:used:percent
      labels:
        desc: "节点的inode的剩余可用的百分比"
        unit: "%"
        job: "node-exporter"

    - expr: node_filefd_allocated{job="node-exporter"}
      record: node_exporter:filefd_allocated:count
      labels:
        desc: "节点的文件描述符打开个数"
        unit: "%"
        job: "node-exporter"

    - expr: node_filefd_allocated{job="node-exporter"}/node_filefd_maximum{job="node-exporter"} * 100
      record: node_exporter:filefd_allocated:percent
      labels:
        desc: "节点的文件描述符打开百分比"
        unit: "%"
        job: "node-exporter"

    - expr: avg by (environment,instance,device) (irate(node_network_receive_bytes_total{device=~"eth0|eth1|ens33|ens37"}[1m]))
      record: node_exporter:network:netin:bit:rate
      labels:
        desc: "节点网卡eth0每秒接收的比特数"
        unit: "bit/s"
        job: "node-exporter"

    - expr: avg by (environment,instance,device) (irate(node_network_transmit_bytes_total{device=~"eth0|eth1|ens33|ens37"}[1m]))
      record: node_exporter:network:netout:bit:rate
      labels:
        desc: "节点网卡eth0每秒发送的比特数"
        unit: "bit/s"
        job: "node-exporter"

    - expr: avg by (environment,instance,device) (irate(node_network_receive_packets_total{device=~"eth0|eth1|ens33|ens37"}[1m]))
      record: node_exporter:network:netin:packet:rate
      labels:
        desc: "节点网卡每秒接收的数据包个数"
        unit: "个/秒"
        job: "node-exporter"

    - expr: avg by (environment,instance,device) (irate(node_network_transmit_packets_total{device=~"eth0|eth1|ens33|ens37"}[1m]))
      record: node_exporter:network:netout:packet:rate
      labels:
        desc: "节点网卡发送的数据包个数"
        unit: "个/秒"
        job: "node-exporter"

    - expr: avg by (environment,instance,device) (irate(node_network_receive_errs_total{device=~"eth0|eth1|ens33|ens37"}[1m]))
      record: node_exporter:network:netin:error:rate
      labels:
        desc: "节点设备驱动器检测到的接收错误包的数量"
        unit: "个/秒"
        job: "node-exporter"

    - expr: avg by (environment,instance,device) (irate(node_network_transmit_errs_total{device=~"eth0|eth1|ens33|ens37"}[1m]))
      record: node_exporter:network:netout:error:rate
      labels:
        desc: "节点设备驱动器检测到的发送错误包的数量"
        unit: "个/秒"
        job: "node-exporter"

    - expr: node_tcp_connection_states{job="node-exporter", state="established"}
      record: node_exporter:network:tcp:established:count
      labels:
        desc: "节点当前established的个数"
        unit: "个"
        job: "node-exporter"

    - expr: node_tcp_connection_states{job="node-exporter", state="time_wait"}
      record: node_exporter:network:tcp:timewait:count
      labels:
        desc: "节点timewait的连接数"
        unit: "个"
        job: "node-exporter"

    - expr: sum by (environment,instance) (node_tcp_connection_states{job="node-exporter"})
      record: node_exporter:network:tcp:total:count
      labels:
        desc: "节点tcp连接总数"
        unit: "个"
        job: "node-exporter"

    - expr: node_processes_state{state="Z"}
      record: node_exporter:process:zoom:total:count
      labels:
        desc: "节点当前状态为zoom的个数"
        unit: "个"
        job: "node-exporter"

    - expr: abs(node_timex_offset_seconds{job="node-exporter"})
      record: node_exporter:time:offset
      labels:
        desc: "节点的时间偏差"
        unit: "s"
        job: "node-exporter"

    - expr: count by (instance) ( count by (instance,cpu) (node_cpu_seconds_total{ mode='system'}) )
      record: node_exporter:cpu:count

```



###### 部署prometheus-server和grafana

```yaml
## docker-compose.yml
version: '2.20'

services:
  prometheus:
    image: registry.cn-beijing.aliyuncs.com/bogeit/prometheus:v3.5.0
    container_name: prometheus
    restart: always
    volumes:
      - /etc/localtime:/etc/localtime
      - /mnt/prometheus/data/:/prometheus/
      - ./prometheus/conf/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus/rules/:/etc/prometheus/rules/
    ports:
      - "9090:9090"
    expose:
      - "9090"
    networks:
      monitor:
        aliases:
          - prometheus

  alertmanager:
    image: registry.cn-beijing.aliyuncs.com/bogeit/alertmanager:v0.28.1
    container_name: alertmanager
    restart: always
    volumes:
      - ./prometheus/conf/alertmanager.yml:/etc/alertmanager/alertmanager.yml
    expose:
      - "9093"
    networks:
      monitor:
        aliases:
          - alertmanager
  # download linux dashboard:  https://grafana.com/dashboards （search ID：8919）
  grafana:
    image: registry.cn-beijing.aliyuncs.com/bogeit/grafana:12.1.0
    container_name: grafana
    restart: always
    environment:
      - GF_SECURITY_ADMIN_USER=boge
      - GF_SECURITY_ADMIN_PASSWORD=bogeit
    volumes:
      - /etc/localtime:/etc/localtime
      - /mnt/grafana/data/:/var/lib/grafana/
#      - /mnt/grafana/conf/:/etc/grafana/
    ports:
      - "13000:3000"
    expose:
      - "3000"
    networks:
      monitor:
        aliases:
          - grafana

networks:
  monitor:
    driver: bridge



## 部署命令
### 目录打开下权限，否则服务有可能运行不正常
chmod -R 777 /mnt/prometheus
chmod -R 777 /mnt/grafana

docker-compose -f ./prometheus/prometheus-server/docker-compose.yml up -d
docker-compose -f ./prometheus/prometheus-server/docker-compose.yml ps
docker-compose -f ./prometheus/prometheus-server/docker-compose.yml down -v
```



###### 准备grafana模板

```json
# grafana模板 - 12633_rev1_linux_dashboard.json

{
  "__inputs": [
    {
      "name": "DS_PROMETHEUS",
      "label": "Prometheus",
      "description": "",
      "type": "datasource",
      "pluginId": "prometheus",
      "pluginName": "Prometheus"
    }
  ],
  "__requires": [
    {
      "type": "panel",
      "id": "bargauge",
      "name": "Bar gauge",
      "version": ""
    },
    {
      "type": "grafana",
      "id": "grafana",
      "name": "Grafana",
      "version": "7.0.6"
    },
    {
      "type": "panel",
      "id": "graph",
      "name": "Graph",
      "version": ""
    },
    {
      "type": "datasource",
      "id": "prometheus",
      "name": "Prometheus",
      "version": "1.0.0"
    },
    {
      "type": "panel",
      "id": "singlestat",
      "name": "Singlestat",
      "version": ""
    },
    {
      "type": "panel",
      "id": "table-old",
      "name": "Table (old)",
      "version": ""
    }
  ],
  "annotations": {
    "list": [
      {
        "$$hashKey": "object:5598",
        "builtIn": 1,
        "datasource": "-- Grafana --",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "description": "添加了个分区节点数查看。添加了个人使用的标签。如需修改，请大家修改原版：1 Node Exporter for Prometheus Dashboard CN v20200628 by StarsL.cn，https://grafana.com/grafana/dashboards/8919",
  "editable": true,
  "gnetId": 12633,
  "graphTooltip": 0,
  "id": null,
  "iteration": 1594630293088,
  "links": [],
  "panels": [
    {
      "cacheTimeout": null,
      "colorBackground": false,
      "colorPostfix": false,
      "colorPrefix": false,
      "colorValue": true,
      "colors": [
        "rgba(245, 54, 54, 0.9)",
        "rgba(237, 129, 40, 0.89)",
        "rgba(50, 172, 45, 0.97)"
      ],
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 0,
      "description": "",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "format": "s",
      "gauge": {
        "maxValue": 100,
        "minValue": 0,
        "show": false,
        "threshcisLabels": false,
        "threshcisMarkers": true
      },
      "gridPos": {
        "h": 3,
        "w": 2,
        "x": 0,
        "y": 0
      },
      "hideTimeOverride": true,
      "id": 15,
      "interval": null,
      "links": [],
      "mappingType": 1,
      "mappingTypes": [
        {
          "name": "value to text",
          "value": 1
        },
        {
          "name": "range to text",
          "value": 2
        }
      ],
      "maxDataPoints": 100,
      "nullPointMode": "null",
      "nullText": null,
      "pluginVersion": "6.4.2",
      "postfix": "",
      "postfixFontSize": "50%",
      "prefix": "",
      "prefixFontSize": "50%",
      "rangeMaps": [
        {
          "from": "null",
          "text": "N/A",
          "to": "null"
        }
      ],
      "sparkline": {
        "fillColor": "rgba(31, 118, 189, 0.18)",
        "full": false,
        "lineColor": "rgb(31, 120, 193)",
        "show": false
      },
      "tableColumn": "",
      "targets": [
        {
          "expr": "avg(time() - node_boot_time_seconds{instance=~\"$node\"})",
          "format": "time_series",
          "hide": false,
          "instant": true,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "",
          "refId": "A",
          "step": 40
        }
      ],
      "threshciss": "1,2",
      "thresholds": "1,3",
      "title": "运行时间",
      "type": "singlestat",
      "valueFontSize": "70%",
      "valueMaps": [
        {
          "op": "=",
          "text": "N/A",
          "value": "null"
        }
      ],
      "valueName": "current"
    },
    {
      "cacheTimeout": null,
      "colorBackground": false,
      "colorPostfix": false,
      "colorValue": true,
      "colors": [
        "rgba(245, 54, 54, 0.9)",
        "rgba(237, 129, 40, 0.89)",
        "rgba(50, 172, 45, 0.97)"
      ],
      "datasource": "${DS_PROMETHEUS}",
      "description": "",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "format": "short",
      "gauge": {
        "maxValue": 100,
        "minValue": 0,
        "show": false,
        "thresholdLabels": false,
        "thresholdMarkers": true
      },
      "gridPos": {
        "h": 3,
        "w": 2,
        "x": 2,
        "y": 0
      },
      "id": 14,
      "interval": null,
      "links": [],
      "mappingType": 1,
      "mappingTypes": [
        {
          "name": "value to text",
          "value": 1
        },
        {
          "name": "range to text",
          "value": 2
        }
      ],
      "maxDataPoints": 100,
      "maxPerRow": 6,
      "nullPointMode": "null",
      "nullText": null,
      "postfix": "",
      "postfixFontSize": "50%",
      "prefix": "",
      "prefixFontSize": "50%",
      "rangeMaps": [
        {
          "from": "null",
          "text": "N/A",
          "to": "null"
        }
      ],
      "sparkline": {
        "fillColor": "rgba(31, 118, 189, 0.18)",
        "full": false,
        "lineColor": "rgb(31, 120, 193)",
        "show": false
      },
      "tableColumn": "",
      "targets": [
        {
          "expr": "count(node_cpu_seconds_total{instance=~\"$node\", mode='system'})",
          "format": "time_series",
          "instant": true,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "",
          "refId": "A",
          "step": 20
        }
      ],
      "thresholds": "1,2",
      "title": "CPU 核数",
      "type": "singlestat",
      "valueFontSize": "80%",
      "valueMaps": [
        {
          "op": "=",
          "text": "N/A",
          "value": "null"
        }
      ],
      "valueName": "current"
    },
    {
      "datasource": "${DS_PROMETHEUS}",
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "thresholds"
          },
          "custom": {},
          "decimals": 1,
          "displayName": "",
          "mappings": [
            {
              "from": "",
              "id": 1,
              "operator": "",
              "text": "N/A",
              "to": "",
              "type": 1,
              "value": "0"
            }
          ],
          "max": 100,
          "min": 0.1,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green",
                "value": null
              },
              {
                "color": "#EAB839",
                "value": 70
              },
              {
                "color": "red",
                "value": 90
              }
            ]
          },
          "unit": "percent"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 6,
        "w": 3,
        "x": 4,
        "y": 0
      },
      "id": 177,
      "options": {
        "displayMode": "lcd",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": [
            "last"
          ],
          "fields": "",
          "values": false
        },
        "showUnfilled": true
      },
      "pluginVersion": "7.0.6",
      "targets": [
        {
          "expr": "100 - (avg(irate(node_cpu_seconds_total{instance=~\"$node\",mode=\"idle\"}[5m])) * 100)",
          "instant": true,
          "interval": "",
          "legendFormat": "总CPU使用率",
          "refId": "A"
        },
        {
          "expr": "avg(irate(node_cpu_seconds_total{instance=~\"$node\",mode=\"iowait\"}[5m])) * 100",
          "hide": true,
          "instant": true,
          "interval": "",
          "legendFormat": "IOwait使用率",
          "refId": "C"
        },
        {
          "expr": "(1 - (node_memory_MemAvailable_bytes{instance=~\"$node\"} / (node_memory_MemTotal_bytes{instance=~\"$node\"})))* 100",
          "instant": true,
          "interval": "",
          "legendFormat": "内存使用率",
          "refId": "B"
        },
        {
          "expr": "(node_filesystem_size_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint=\"$maxmount\"}-node_filesystem_free_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint=\"$maxmount\"})*100 /(node_filesystem_avail_bytes {instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint=\"$maxmount\"}+(node_filesystem_size_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint=\"$maxmount\"}-node_filesystem_free_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint=\"$maxmount\"}))",
          "hide": true,
          "instant": true,
          "interval": "",
          "legendFormat": "最大分区({{mountpoint}})使用率",
          "refId": "D"
        },
        {
          "expr": "(1 - ((node_memory_SwapFree_bytes{instance=~\"$node\"} + 1)/ (node_memory_SwapTotal_bytes{instance=~\"$node\"} + 1))) * 100",
          "instant": true,
          "legendFormat": "交换分区使用率",
          "refId": "F"
        }
      ],
      "timeFrom": null,
      "timeShift": null,
      "title": "",
      "type": "bargauge"
    },
    {
      "columns": [],
      "datasource": "${DS_PROMETHEUS}",
      "description": "本看板中的：磁盘总量、使用量、可用量、使用率保持和df命令的Size、Used、Avail、Use% 列的值一致，并且Use%的值会四舍五入保留一位小数，会更加准确。\n\n注：df中Use%算法为：(size - free) * 100 / (avail + (size - free))，结果是整除则为该值，非整除则为该值+1，结果的单位是%。\n参考df命令源码：",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fontSize": "100%",
      "gridPos": {
        "h": 6,
        "w": 9,
        "x": 7,
        "y": 0
      },
      "id": 181,
      "links": [
        {
          "targetBlank": true,
          "title": "https://github.com/coreutils/coreutils/blob/master/src/df.c",
          "url": "https://github.com/coreutils/coreutils/blob/master/src/df.c"
        }
      ],
      "pageSize": null,
      "scroll": true,
      "showHeader": true,
      "sort": {
        "col": 6,
        "desc": false
      },
      "styles": [
        {
          "$$hashKey": "object:818",
          "alias": "分区",
          "align": "auto",
          "colorMode": null,
          "colors": [
            "rgba(50, 172, 45, 0.97)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(245, 54, 54, 0.9)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 2,
          "mappingType": 1,
          "pattern": "mountpoint",
          "thresholds": [
            ""
          ],
          "type": "string",
          "unit": "bytes"
        },
        {
          "$$hashKey": "object:819",
          "alias": "可用空间",
          "align": "auto",
          "colorMode": "value",
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 1,
          "mappingType": 1,
          "pattern": "Value #A",
          "thresholds": [
            "10000000000",
            "20000000000"
          ],
          "type": "number",
          "unit": "bytes"
        },
        {
          "$$hashKey": "object:820",
          "alias": "使用率",
          "align": "auto",
          "colorMode": "cell",
          "colors": [
            "rgba(50, 172, 45, 0.97)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(245, 54, 54, 0.9)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 1,
          "mappingType": 1,
          "pattern": "Value #B",
          "thresholds": [
            "70",
            "85"
          ],
          "type": "number",
          "unit": "percent"
        },
        {
          "$$hashKey": "object:821",
          "alias": "总空间",
          "align": "auto",
          "colorMode": null,
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 0,
          "link": false,
          "mappingType": 1,
          "pattern": "Value #C",
          "thresholds": [],
          "type": "number",
          "unit": "bytes"
        },
        {
          "$$hashKey": "object:822",
          "alias": "文件系统",
          "align": "auto",
          "colorMode": null,
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 2,
          "link": false,
          "mappingType": 1,
          "pattern": "fstype",
          "thresholds": [],
          "type": "string",
          "unit": "short"
        },
        {
          "$$hashKey": "object:823",
          "alias": "设备名",
          "align": "auto",
          "colorMode": null,
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 2,
          "link": false,
          "mappingType": 1,
          "pattern": "device",
          "preserveFormat": false,
          "sanitize": false,
          "thresholds": [],
          "type": "string",
          "unit": "short"
        },
        {
          "$$hashKey": "object:824",
          "alias": "",
          "align": "auto",
          "colorMode": null,
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "decimals": 2,
          "pattern": "/.*/",
          "preserveFormat": true,
          "sanitize": false,
          "thresholds": [],
          "type": "hidden",
          "unit": "short"
        }
      ],
      "targets": [
        {
          "expr": "node_filesystem_size_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}-0",
          "format": "table",
          "hide": false,
          "instant": true,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "总量",
          "refId": "C"
        },
        {
          "expr": "node_filesystem_avail_bytes {instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}-0",
          "format": "table",
          "hide": false,
          "instant": true,
          "interval": "10s",
          "intervalFactor": 1,
          "legendFormat": "",
          "refId": "A"
        },
        {
          "expr": "(node_filesystem_size_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}-node_filesystem_free_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}) *100/(node_filesystem_avail_bytes {instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}+(node_filesystem_size_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}-node_filesystem_free_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}))",
          "format": "table",
          "hide": false,
          "instant": true,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "",
          "refId": "B"
        }
      ],
      "title": "【$show_hostname】：各分区可用空间(EXT.*/XFS)",
      "transform": "table",
      "type": "table-old"
    },
    {
      "aliasColors": {
        "cn-shenzhen.i-wz9cq1dcb6zwc39ehw59_cni0_in": "light-red",
        "cn-shenzhen.i-wz9cq1dcb6zwc39ehw59_cni0_in下载": "green",
        "cn-shenzhen.i-wz9cq1dcb6zwc39ehw59_cni0_out上传": "yellow",
        "cn-shenzhen.i-wz9cq1dcb6zwc39ehw59_eth0_in下载": "purple",
        "cn-shenzhen.i-wz9cq1dcb6zwc39ehw59_eth0_out": "purple",
        "cn-shenzhen.i-wz9cq1dcb6zwc39ehw59_eth0_out上传": "blue"
      },
      "bars": true,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "editable": true,
      "error": false,
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 0,
      "grid": {},
      "gridPos": {
        "h": 6,
        "w": 8,
        "x": 16,
        "y": 0
      },
      "hiddenSeries": false,
      "id": 183,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": false,
        "show": false,
        "sort": "current",
        "sortDesc": true,
        "total": true,
        "values": true
      },
      "lines": false,
      "linewidth": 2,
      "links": [],
      "nullPointMode": "null as zero",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 1,
      "points": false,
      "renderer": "flot",
      "repeat": null,
      "seriesOverrides": [
        {
          "alias": "/.*_out上传$/",
          "transform": "negative-Y"
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "increase(node_network_receive_bytes_total{instance=~\"$node\",device=~\"$device\"}[60m])",
          "interval": "60m",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_in下载",
          "metric": "",
          "refId": "A",
          "step": 600,
          "target": ""
        },
        {
          "expr": "increase(node_network_transmit_bytes_total{instance=~\"$node\",device=~\"$device\"}[60m])",
          "hide": false,
          "interval": "60m",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_out上传",
          "refId": "B",
          "step": 600
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "每小时流量$device",
      "tooltip": {
        "msResolution": false,
        "shared": true,
        "sort": 0,
        "value_type": "cumulative"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "bytes",
          "label": "上传（-）/下载（+）",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": false
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "cacheTimeout": null,
      "colorBackground": false,
      "colorValue": true,
      "colors": [
        "rgba(245, 54, 54, 0.9)",
        "rgba(237, 129, 40, 0.89)",
        "rgba(50, 172, 45, 0.97)"
      ],
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 0,
      "description": "",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "format": "bytes",
      "gauge": {
        "maxValue": 100,
        "minValue": 0,
        "show": false,
        "thresholdLabels": false,
        "thresholdMarkers": true
      },
      "gridPos": {
        "h": 3,
        "w": 2,
        "x": 0,
        "y": 3
      },
      "id": 75,
      "interval": null,
      "links": [],
      "mappingType": 1,
      "mappingTypes": [
        {
          "name": "value to text",
          "value": 1
        },
        {
          "name": "range to text",
          "value": 2
        }
      ],
      "maxDataPoints": 100,
      "maxPerRow": 6,
      "nullPointMode": "null",
      "nullText": null,
      "postfix": "",
      "postfixFontSize": "70%",
      "prefix": "",
      "prefixFontSize": "50%",
      "rangeMaps": [
        {
          "from": "null",
          "text": "N/A",
          "to": "null"
        }
      ],
      "sparkline": {
        "fillColor": "rgba(31, 118, 189, 0.18)",
        "full": false,
        "lineColor": "rgb(31, 120, 193)",
        "show": false
      },
      "tableColumn": "",
      "targets": [
        {
          "expr": "sum(node_memory_MemTotal_bytes{instance=~\"$node\"})",
          "format": "time_series",
          "instant": true,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{instance}}",
          "refId": "A",
          "step": 20
        }
      ],
      "thresholds": "2,3",
      "title": "总内存",
      "type": "singlestat",
      "valueFontSize": "80%",
      "valueMaps": [
        {
          "op": "=",
          "text": "N/A",
          "value": "null"
        }
      ],
      "valueName": "current"
    },
    {
      "cacheTimeout": null,
      "colorBackground": false,
      "colorValue": true,
      "colors": [
        "rgba(50, 172, 45, 0.97)",
        "rgba(237, 129, 40, 0.89)",
        "#d44a3a"
      ],
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 2,
      "description": "",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "format": "percent",
      "gauge": {
        "maxValue": 100,
        "minValue": 0,
        "show": false,
        "thresholdLabels": false,
        "thresholdMarkers": true
      },
      "gridPos": {
        "h": 3,
        "w": 2,
        "x": 2,
        "y": 3
      },
      "id": 20,
      "interval": null,
      "links": [],
      "mappingType": 1,
      "mappingTypes": [
        {
          "name": "value to text",
          "value": 1
        },
        {
          "name": "range to text",
          "value": 2
        }
      ],
      "maxDataPoints": 100,
      "nullPointMode": "connected",
      "nullText": null,
      "pluginVersion": "6.4.2",
      "postfix": "",
      "postfixFontSize": "50%",
      "prefix": "",
      "prefixFontSize": "50%",
      "rangeMaps": [
        {
          "from": "null",
          "text": "N/A",
          "to": "null"
        }
      ],
      "sparkline": {
        "fillColor": "rgba(31, 118, 189, 0.18)",
        "full": true,
        "lineColor": "#3274D9",
        "show": true,
        "ymax": null,
        "ymin": null
      },
      "tableColumn": "",
      "targets": [
        {
          "expr": "avg(irate(node_cpu_seconds_total{instance=~\"$node\",mode=\"iowait\"}[5m])) * 100",
          "format": "time_series",
          "hide": false,
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "",
          "refId": "A",
          "step": 20
        }
      ],
      "thresholds": "20,50",
      "timeFrom": null,
      "timeShift": null,
      "title": "CPU iowait",
      "type": "singlestat",
      "valueFontSize": "80%",
      "valueMaps": [
        {
          "op": "=",
          "text": "N/A",
          "value": "null"
        }
      ],
      "valueName": "avg"
    },
    {
      "aliasColors": {
        "192.168.200.241:9100_Total": "dark-red",
        "Idle - Waiting for something to happen": "#052B51",
        "guest": "#9AC48A",
        "idle": "#052B51",
        "iowait": "#EAB839",
        "irq": "#BF1B00",
        "nice": "#C15C17",
        "sdb_每秒I/O操作%": "#d683ce",
        "softirq": "#E24D42",
        "steal": "#FCE2DE",
        "system": "#508642",
        "user": "#5195CE",
        "磁盘花费在I/O操作占比": "#ba43a9"
      },
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 2,
      "description": "",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 8,
        "w": 8,
        "x": 0,
        "y": 6
      },
      "hiddenSeries": false,
      "id": 7,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": true,
        "rightSide": false,
        "show": true,
        "sideWidth": null,
        "sort": "current",
        "sortDesc": true,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "links": [],
      "maxPerRow": 6,
      "nullPointMode": "null",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "repeat": null,
      "seriesOverrides": [
        {
          "$$hashKey": "object:263",
          "alias": "/.*总使用率/",
          "color": "#C4162A",
          "fill": 0
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "avg(irate(node_cpu_seconds_total{instance=~\"$node\",mode=\"system\"}[5m])) by (instance) *100",
          "format": "time_series",
          "hide": false,
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "系统使用率",
          "refId": "A",
          "step": 20
        },
        {
          "expr": "avg(irate(node_cpu_seconds_total{instance=~\"$node\",mode=\"user\"}[5m])) by (instance) *100",
          "format": "time_series",
          "hide": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "用户使用率",
          "refId": "B",
          "step": 240
        },
        {
          "expr": "avg(irate(node_cpu_seconds_total{instance=~\"$node\",mode=\"iowait\"}[5m])) by (instance) *100",
          "format": "time_series",
          "hide": false,
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "磁盘IO使用率",
          "refId": "D",
          "step": 240
        },
        {
          "expr": "(1 - avg(irate(node_cpu_seconds_total{instance=~\"$node\",mode=\"idle\"}[5m])) by (instance))*100",
          "format": "time_series",
          "hide": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "总使用率",
          "refId": "F",
          "step": 240
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "CPU使用率",
      "tooltip": {
        "shared": true,
        "sort": 2,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "$$hashKey": "object:278",
          "decimals": 0,
          "format": "percent",
          "label": "",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "$$hashKey": "object:279",
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": false
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {
        "192.168.200.241:9100_总内存": "dark-red",
        "使用率": "yellow",
        "内存_Avaliable": "#6ED0E0",
        "内存_Cached": "#EF843C",
        "内存_Free": "#629E51",
        "内存_Total": "#6d1f62",
        "内存_Used": "#eab839",
        "可用": "#9ac48a",
        "总内存": "#bf1b00"
      },
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 2,
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 8,
        "w": 8,
        "x": 8,
        "y": 6
      },
      "height": "300",
      "hiddenSeries": false,
      "id": 156,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": true,
        "rightSide": false,
        "show": true,
        "sort": "current",
        "sortDesc": true,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "alias": "总内存",
          "color": "#C4162A",
          "fill": 0
        },
        {
          "alias": "使用率",
          "color": "rgb(0, 209, 255)",
          "lines": false,
          "pointradius": 1,
          "points": true,
          "yaxis": 2
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "node_memory_MemTotal_bytes{instance=~\"$node\"}",
          "format": "time_series",
          "hide": false,
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "总内存",
          "refId": "A",
          "step": 4
        },
        {
          "expr": "node_memory_MemTotal_bytes{instance=~\"$node\"} - node_memory_MemAvailable_bytes{instance=~\"$node\"}",
          "format": "time_series",
          "hide": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "已用",
          "refId": "B",
          "step": 4
        },
        {
          "expr": "node_memory_MemAvailable_bytes{instance=~\"$node\"}",
          "format": "time_series",
          "hide": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "可用",
          "refId": "F",
          "step": 4
        },
        {
          "expr": "node_memory_Buffers_bytes{instance=~\"$node\"}",
          "format": "time_series",
          "hide": true,
          "intervalFactor": 1,
          "legendFormat": "内存_Buffers",
          "refId": "D",
          "step": 4
        },
        {
          "expr": "node_memory_MemFree_bytes{instance=~\"$node\"}",
          "format": "time_series",
          "hide": true,
          "intervalFactor": 1,
          "legendFormat": "内存_Free",
          "refId": "C",
          "step": 4
        },
        {
          "expr": "node_memory_Cached_bytes{instance=~\"$node\"}",
          "format": "time_series",
          "hide": true,
          "intervalFactor": 1,
          "legendFormat": "内存_Cached",
          "refId": "E",
          "step": 4
        },
        {
          "expr": "node_memory_MemTotal_bytes{instance=~\"$node\"} - (node_memory_Cached_bytes{instance=~\"$node\"} - node_memory_Buffers_bytes{instance=~\"$node\"} - node_memory_MemFree_bytes{instance=~\"$node\"})",
          "format": "time_series",
          "hide": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{instance}}_已用(total-cache-buf-free)",
          "refId": "G"
        },
        {
          "expr": "(1 - (node_memory_MemAvailable_bytes{instance=~\"$node\"} / (node_memory_MemTotal_bytes{instance=~\"$node\"})))* 100",
          "format": "time_series",
          "hide": false,
          "interval": "30m",
          "intervalFactor": 10,
          "legendFormat": "使用率",
          "refId": "H"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "内存信息",
      "tooltip": {
        "shared": true,
        "sort": 2,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "bytes",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": "0",
          "show": true
        },
        {
          "format": "percent",
          "label": "内存使用率",
          "logBase": 1,
          "max": "100",
          "min": "0",
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {
        "192.168.10.227:9100_em1_in下载": "super-light-green",
        "192.168.10.227:9100_em1_out上传": "dark-blue"
      },
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 2,
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 8,
        "w": 8,
        "x": 16,
        "y": 6
      },
      "height": "300",
      "hiddenSeries": false,
      "id": 157,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": true,
        "rightSide": false,
        "show": true,
        "sort": "current",
        "sortDesc": true,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 2,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "alias": "/.*_out上传$/",
          "transform": "negative-Y"
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "irate(node_network_receive_bytes_total{instance=~'$node',device=~\"$device\"}[5m])*8",
          "format": "time_series",
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_in下载",
          "refId": "A",
          "step": 4
        },
        {
          "expr": "irate(node_network_transmit_bytes_total{instance=~'$node',device=~\"$device\"}[5m])*8",
          "format": "time_series",
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_out上传",
          "refId": "B",
          "step": 4
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "每秒网络带宽使用$device",
      "tooltip": {
        "shared": true,
        "sort": 2,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "bps",
          "label": "上传（-）/下载（+）",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": false
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {
        "15分钟": "#6ED0E0",
        "1分钟": "#BF1B00",
        "5分钟": "#CCA300"
      },
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 2,
      "editable": true,
      "error": false,
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 1,
      "grid": {},
      "gridPos": {
        "h": 8,
        "w": 8,
        "x": 0,
        "y": 14
      },
      "height": "300",
      "hiddenSeries": false,
      "id": 13,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": true,
        "rightSide": false,
        "show": true,
        "sort": "current",
        "sortDesc": true,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "links": [],
      "maxPerRow": 6,
      "nullPointMode": "null as zero",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "repeat": null,
      "seriesOverrides": [
        {
          "alias": "/.*总核数/",
          "color": "#C4162A"
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "node_load1{instance=~\"$node\"}",
          "format": "time_series",
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "1分钟负载",
          "metric": "",
          "refId": "A",
          "step": 20,
          "target": ""
        },
        {
          "expr": "node_load5{instance=~\"$node\"}",
          "format": "time_series",
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "5分钟负载",
          "refId": "B",
          "step": 20
        },
        {
          "expr": "node_load15{instance=~\"$node\"}",
          "format": "time_series",
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "15分钟负载",
          "refId": "C",
          "step": 20
        },
        {
          "expr": " sum(count(node_cpu_seconds_total{instance=~\"$node\", mode='system'}) by (cpu,instance)) by(instance)",
          "format": "time_series",
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "CPU总核数",
          "refId": "D",
          "step": 20
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "系统平均负载",
      "tooltip": {
        "msResolution": false,
        "shared": true,
        "sort": 2,
        "value_type": "cumulative"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {
        "vda_write": "#6ED0E0"
      },
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 2,
      "description": "Read bytes 每个磁盘分区每秒读取的比特数\nWritten bytes 每个磁盘分区每秒写入的比特数",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 1,
      "gridPos": {
        "h": 8,
        "w": 8,
        "x": 8,
        "y": 14
      },
      "height": "300",
      "hiddenSeries": false,
      "id": 168,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": true,
        "show": true,
        "sort": "current",
        "sortDesc": true,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "alias": "/.*_读取$/",
          "transform": "negative-Y"
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "irate(node_disk_read_bytes_total{instance=~\"$node\"}[5m])",
          "format": "time_series",
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_读取",
          "refId": "A",
          "step": 10
        },
        {
          "expr": "irate(node_disk_written_bytes_total{instance=~\"$node\"}[5m])",
          "format": "time_series",
          "hide": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_写入",
          "refId": "B",
          "step": 10
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "每秒磁盘读写容量",
      "tooltip": {
        "shared": true,
        "sort": 2,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "decimals": null,
          "format": "Bps",
          "label": "读取（-）/写入（+）",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": false
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {},
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 1,
      "description": "",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 0,
      "fillGradient": 0,
      "gridPos": {
        "h": 8,
        "w": 8,
        "x": 16,
        "y": 14
      },
      "hiddenSeries": false,
      "id": 174,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": true,
        "rightSide": false,
        "show": true,
        "sideWidth": null,
        "sort": "current",
        "sortDesc": true,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "alias": "/Inodes.*/",
          "yaxis": 2
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "(node_filesystem_size_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}-node_filesystem_free_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}) *100/(node_filesystem_avail_bytes {instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}+(node_filesystem_size_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}-node_filesystem_free_bytes{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}))",
          "format": "time_series",
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{mountpoint}}",
          "refId": "A"
        },
        {
          "expr": "node_filesystem_files_free{instance=~'$node',fstype=~\"ext.?|xfs\"} / node_filesystem_files{instance=~'$node',fstype=~\"ext.?|xfs\"}",
          "hide": true,
          "interval": "",
          "legendFormat": "Inodes：{{instance}}：{{mountpoint}}",
          "refId": "B"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "磁盘使用率",
      "tooltip": {
        "shared": true,
        "sort": 2,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "decimals": null,
          "format": "percent",
          "label": "",
          "logBase": 1,
          "max": "100",
          "min": "0",
          "show": true
        },
        {
          "decimals": 2,
          "format": "percentunit",
          "label": null,
          "logBase": 1,
          "max": "1",
          "min": null,
          "show": false
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {
        "vda_write": "#6ED0E0"
      },
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 2,
      "description": "Reads completed: 每个磁盘分区每秒读完成次数\n\nWrites completed: 每个磁盘分区每秒写完成次数\n\nIO now 每个磁盘分区每秒正在处理的输入/输出请求数",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 0,
      "fillGradient": 0,
      "gridPos": {
        "h": 9,
        "w": 8,
        "x": 0,
        "y": 22
      },
      "height": "300",
      "hiddenSeries": false,
      "id": 161,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": true,
        "show": true,
        "sort": "current",
        "sortDesc": true,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "alias": "/.*_读取$/",
          "transform": "negative-Y"
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "irate(node_disk_reads_completed_total{instance=~\"$node\"}[5m])",
          "format": "time_series",
          "hide": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_读取",
          "refId": "A",
          "step": 10
        },
        {
          "expr": "irate(node_disk_writes_completed_total{instance=~\"$node\"}[5m])",
          "format": "time_series",
          "hide": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_写入",
          "refId": "B",
          "step": 10
        },
        {
          "expr": "node_disk_io_now{instance=~\"$node\"}",
          "format": "time_series",
          "hide": true,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}",
          "refId": "C"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "磁盘读写速率（IOPS）",
      "tooltip": {
        "shared": true,
        "sort": 2,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "decimals": null,
          "format": "iops",
          "label": "读取（-）/写入（+）I/O ops/sec",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {
        "Idle - Waiting for something to happen": "#052B51",
        "guest": "#9AC48A",
        "idle": "#052B51",
        "iowait": "#EAB839",
        "irq": "#BF1B00",
        "nice": "#C15C17",
        "sdb_每秒I/O操作%": "#d683ce",
        "softirq": "#E24D42",
        "steal": "#FCE2DE",
        "system": "#508642",
        "user": "#5195CE",
        "磁盘花费在I/O操作占比": "#ba43a9"
      },
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "decimals": null,
      "description": "每一秒钟的自然时间内，花费在I/O上的耗时。（wall-clock time）\n\nnode_disk_io_time_seconds_total：\n磁盘花费在输入/输出操作上的秒数。该值为累加值。（Milliseconds Spent Doing I/Os）\n\nirate(node_disk_io_time_seconds_total[1m])：\n计算每秒的速率：(last值-last前一个值)/时间戳差值，即：1秒钟内磁盘花费在I/O操作的时间占比。",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 0,
      "gridPos": {
        "h": 9,
        "w": 8,
        "x": 8,
        "y": 22
      },
      "hiddenSeries": false,
      "id": 175,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": false,
        "rightSide": false,
        "show": true,
        "sideWidth": null,
        "sort": null,
        "sortDesc": null,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "maxPerRow": 6,
      "nullPointMode": "null",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "irate(node_disk_io_time_seconds_total{instance=~\"$node\"}[5m])",
          "format": "time_series",
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_每秒I/O操作%",
          "refId": "C"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "每1秒内I/O操作耗时占比",
      "tooltip": {
        "shared": true,
        "sort": 2,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "decimals": null,
          "format": "percentunit",
          "label": "",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": false
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {
        "vda": "#6ED0E0"
      },
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 2,
      "description": "Read time seconds 每个磁盘分区读操作花费的秒数\n\nWrite time seconds 每个磁盘分区写操作花费的秒数\n\nIO time seconds 每个磁盘分区输入/输出操作花费的秒数\n\nIO time weighted seconds每个磁盘分区输入/输出操作花费的加权秒数",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 1,
      "fillGradient": 1,
      "gridPos": {
        "h": 9,
        "w": 8,
        "x": 16,
        "y": 22
      },
      "height": "300",
      "hiddenSeries": false,
      "id": 160,
      "legend": {
        "alignAsTable": true,
        "avg": true,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": true,
        "show": true,
        "sort": "current",
        "sortDesc": true,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "links": [],
      "nullPointMode": "null as zero",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "alias": "/,*_读取$/",
          "transform": "negative-Y"
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "irate(node_disk_read_time_seconds_total{instance=~\"$node\"}[5m]) / irate(node_disk_reads_completed_total{instance=~\"$node\"}[5m])",
          "format": "time_series",
          "hide": false,
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_读取",
          "refId": "B"
        },
        {
          "expr": "irate(node_disk_write_time_seconds_total{instance=~\"$node\"}[5m]) / irate(node_disk_writes_completed_total{instance=~\"$node\"}[5m])",
          "format": "time_series",
          "hide": false,
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_写入",
          "refId": "C"
        },
        {
          "expr": "irate(node_disk_io_time_seconds_total{instance=~\"$node\"}[5m])",
          "format": "time_series",
          "hide": true,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}",
          "refId": "A",
          "step": 10
        },
        {
          "expr": "irate(node_disk_io_time_weighted_seconds_total{instance=~\"$node\"}[5m])",
          "format": "time_series",
          "hide": true,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "{{device}}_加权",
          "refId": "D"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "每次IO读写的耗时（参考：小于100ms）(beta)",
      "tooltip": {
        "shared": true,
        "sort": 2,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "s",
          "label": "读取（-）/写入（+）",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": false
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {
        "192.168.200.241:9100_TCP_alloc": "semi-dark-blue",
        "TCP": "#6ED0E0",
        "TCP_alloc": "blue"
      },
      "bars": false,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "decimals": 2,
      "description": "Sockets_used - 已使用的所有协议套接字总量\n\nCurrEstab - 当前状态为 ESTABLISHED 或 CLOSE-WAIT 的 TCP 连接数\n\nTCP_alloc - 已分配（已建立、已申请到sk_buff）的TCP套接字数量\n\nTCP_tw - 等待关闭的TCP连接数\n\nUDP_inuse - 正在使用的 UDP 套接字数量\n\nRetransSegs - TCP 重传报文数\n\nOutSegs - TCP 发送的报文数\n\nInSegs - TCP 接收的报文数",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 0,
      "fillGradient": 0,
      "gridPos": {
        "h": 8,
        "w": 16,
        "x": 0,
        "y": 31
      },
      "height": "300",
      "hiddenSeries": false,
      "id": 158,
      "interval": "",
      "legend": {
        "alignAsTable": true,
        "avg": false,
        "current": true,
        "hideEmpty": true,
        "hideZero": true,
        "max": true,
        "min": false,
        "rightSide": true,
        "show": true,
        "sideWidth": null,
        "sort": "current",
        "sortDesc": true,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 1,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pointradius": 5,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "alias": "/.*Sockets_used/",
          "color": "#E02F44",
          "lines": false,
          "pointradius": 1,
          "points": true,
          "yaxis": 2
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "node_netstat_Tcp_CurrEstab{instance=~'$node'}",
          "format": "time_series",
          "hide": false,
          "instant": false,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "CurrEstab",
          "refId": "A",
          "step": 20
        },
        {
          "expr": "node_sockstat_TCP_tw{instance=~'$node'}",
          "format": "time_series",
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "TCP_tw",
          "refId": "D"
        },
        {
          "expr": "node_sockstat_sockets_used{instance=~'$node'}",
          "hide": false,
          "interval": "30m",
          "intervalFactor": 1,
          "legendFormat": "Sockets_used",
          "refId": "B"
        },
        {
          "expr": "node_sockstat_UDP_inuse{instance=~'$node'}",
          "interval": "",
          "legendFormat": "UDP_inuse",
          "refId": "C"
        },
        {
          "expr": "node_sockstat_TCP_alloc{instance=~'$node'}",
          "interval": "",
          "legendFormat": "TCP_alloc",
          "refId": "E"
        },
        {
          "expr": "irate(node_netstat_Tcp_PassiveOpens{instance=~'$node'}[5m])",
          "hide": true,
          "interval": "",
          "legendFormat": "{{instance}}_Tcp_PassiveOpens",
          "refId": "G"
        },
        {
          "expr": "irate(node_netstat_Tcp_ActiveOpens{instance=~'$node'}[5m])",
          "hide": true,
          "interval": "",
          "legendFormat": "{{instance}}_Tcp_ActiveOpens",
          "refId": "F"
        },
        {
          "expr": "irate(node_netstat_Tcp_InSegs{instance=~'$node'}[5m])",
          "interval": "",
          "legendFormat": "Tcp_InSegs",
          "refId": "H"
        },
        {
          "expr": "irate(node_netstat_Tcp_OutSegs{instance=~'$node'}[5m])",
          "interval": "",
          "legendFormat": "Tcp_OutSegs",
          "refId": "I"
        },
        {
          "expr": "irate(node_netstat_Tcp_RetransSegs{instance=~'$node'}[5m])",
          "hide": false,
          "interval": "",
          "legendFormat": "Tcp_RetransSegs",
          "refId": "J"
        },
        {
          "expr": "irate(node_netstat_TcpExt_ListenDrops{instance=~'$node'}[5m])",
          "hide": true,
          "interval": "",
          "legendFormat": "",
          "refId": "K"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "网络Socket连接信息",
      "tooltip": {
        "shared": true,
        "sort": 2,
        "value_type": "individual"
      },
      "transformations": [],
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "label": null,
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": "已使用的所有协议套接字总量",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "aliasColors": {
        "filefd_192.168.200.241:9100": "super-light-green",
        "switches_192.168.200.241:9100": "semi-dark-red",
        "使用的文件描述符_10.118.72.128:9100": "red",
        "每秒上下文切换次数_10.118.71.245:9100": "yellow",
        "每秒上下文切换次数_10.118.72.128:9100": "yellow"
      },
      "bars": false,
      "cacheTimeout": null,
      "dashLength": 10,
      "dashes": false,
      "datasource": "${DS_PROMETHEUS}",
      "description": "",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fill": 0,
      "fillGradient": 1,
      "gridPos": {
        "h": 8,
        "w": 8,
        "x": 16,
        "y": 31
      },
      "hiddenSeries": false,
      "hideTimeOverride": false,
      "id": 16,
      "legend": {
        "alignAsTable": false,
        "avg": false,
        "current": true,
        "max": false,
        "min": false,
        "rightSide": false,
        "show": true,
        "total": false,
        "values": true
      },
      "lines": true,
      "linewidth": 2,
      "links": [],
      "nullPointMode": "null",
      "options": {
        "dataLinks": []
      },
      "percentage": false,
      "pluginVersion": "6.4.2",
      "pointradius": 1,
      "points": false,
      "renderer": "flot",
      "seriesOverrides": [
        {
          "alias": "/每秒上下文切换次数.*/",
          "color": "#FADE2A",
          "lines": false,
          "pointradius": 1,
          "points": true,
          "yaxis": 2
        },
        {
          "alias": "/使用的文件描述符.*/",
          "color": "#F2495C"
        }
      ],
      "spaceLength": 10,
      "stack": false,
      "steppedLine": false,
      "targets": [
        {
          "expr": "node_filefd_allocated{instance=~\"$node\"}",
          "format": "time_series",
          "instant": false,
          "interval": "",
          "intervalFactor": 5,
          "legendFormat": "使用的文件描述符",
          "refId": "B"
        },
        {
          "expr": "irate(node_context_switches_total{instance=~\"$node\"}[5m])",
          "interval": "",
          "intervalFactor": 5,
          "legendFormat": "每秒上下文切换次数",
          "refId": "A"
        },
        {
          "expr": "  (node_filefd_allocated{instance=~\"$node\"}/node_filefd_maximum{instance=~\"$node\"}) *100",
          "format": "time_series",
          "hide": true,
          "instant": false,
          "interval": "",
          "intervalFactor": 5,
          "legendFormat": "使用的文件描述符占比_{{instance}}",
          "refId": "C"
        }
      ],
      "thresholds": [],
      "timeFrom": null,
      "timeRegions": [],
      "timeShift": null,
      "title": "打开的文件描述符(左 )/每秒上下文切换次数(右)",
      "tooltip": {
        "shared": true,
        "sort": 2,
        "value_type": "individual"
      },
      "type": "graph",
      "xaxis": {
        "buckets": null,
        "mode": "time",
        "name": null,
        "show": true,
        "values": []
      },
      "yaxes": [
        {
          "format": "short",
          "label": "使用的文件描述符",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        },
        {
          "format": "short",
          "label": "context_switches",
          "logBase": 1,
          "max": null,
          "min": null,
          "show": true
        }
      ],
      "yaxis": {
        "align": false,
        "alignLevel": null
      }
    },
    {
      "columns": [],
      "datasource": "${DS_PROMETHEUS}",
      "description": "",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "fontSize": "100%",
      "gridPos": {
        "h": 6,
        "w": 16,
        "x": 0,
        "y": 39
      },
      "id": 184,
      "links": [],
      "pageSize": null,
      "scroll": true,
      "showHeader": true,
      "sort": {
        "col": 6,
        "desc": false
      },
      "styles": [
        {
          "$$hashKey": "object:818",
          "alias": "分区",
          "align": "auto",
          "colorMode": null,
          "colors": [
            "rgba(50, 172, 45, 0.97)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(245, 54, 54, 0.9)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 2,
          "mappingType": 1,
          "pattern": "mountpoint",
          "thresholds": [
            ""
          ],
          "type": "string",
          "unit": "bytes"
        },
        {
          "$$hashKey": "object:819",
          "alias": "可用数",
          "align": "auto",
          "colorMode": "value",
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": null,
          "mappingType": 1,
          "pattern": "Value #A",
          "thresholds": [
            "1000000",
            "10000000"
          ],
          "type": "number",
          "unit": "none"
        },
        {
          "$$hashKey": "object:820",
          "alias": "使用率",
          "align": "auto",
          "colorMode": "cell",
          "colors": [
            "rgba(50, 172, 45, 0.97)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(245, 54, 54, 0.9)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 1,
          "mappingType": 1,
          "pattern": "Value #B",
          "thresholds": [
            "70",
            "85"
          ],
          "type": "number",
          "unit": "percent"
        },
        {
          "$$hashKey": "object:821",
          "alias": "节点数",
          "align": "auto",
          "colorMode": null,
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 0,
          "link": false,
          "mappingType": 1,
          "pattern": "Value #C",
          "thresholds": [],
          "type": "number",
          "unit": "none"
        },
        {
          "$$hashKey": "object:822",
          "alias": "文件系统",
          "align": "auto",
          "colorMode": null,
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 2,
          "link": false,
          "mappingType": 1,
          "pattern": "fstype",
          "thresholds": [],
          "type": "string",
          "unit": "short"
        },
        {
          "$$hashKey": "object:823",
          "alias": "设备名",
          "align": "auto",
          "colorMode": null,
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "dateFormat": "YYYY-MM-DD HH:mm:ss",
          "decimals": 2,
          "link": false,
          "mappingType": 1,
          "pattern": "device",
          "preserveFormat": false,
          "sanitize": false,
          "thresholds": [],
          "type": "string",
          "unit": "short"
        },
        {
          "$$hashKey": "object:824",
          "alias": "",
          "align": "auto",
          "colorMode": null,
          "colors": [
            "rgba(245, 54, 54, 0.9)",
            "rgba(237, 129, 40, 0.89)",
            "rgba(50, 172, 45, 0.97)"
          ],
          "decimals": 2,
          "pattern": "/.*/",
          "preserveFormat": true,
          "sanitize": false,
          "thresholds": [],
          "type": "hidden",
          "unit": "short"
        }
      ],
      "targets": [
        {
          "expr": "node_filesystem_files{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}-0",
          "format": "table",
          "hide": false,
          "instant": true,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "",
          "refId": "C"
        },
        {
          "expr": "node_filesystem_files_free{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}-0",
          "format": "table",
          "hide": false,
          "instant": true,
          "interval": "10s",
          "intervalFactor": 1,
          "legendFormat": "",
          "refId": "A"
        },
        {
          "expr": "(node_filesystem_files{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}-node_filesystem_files_free{instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}) *100/node_filesystem_files {instance=~'$node',fstype=~\"ext.*|xfs\",mountpoint !~\".*pod.*\"}",
          "format": "table",
          "hide": false,
          "instant": true,
          "interval": "",
          "intervalFactor": 1,
          "legendFormat": "",
          "refId": "B"
        }
      ],
      "title": "【$show_hostname】：各分区可用节点数(EXT.*/XFS)",
      "transform": "table",
      "type": "table-old"
    },
    {
      "cacheTimeout": null,
      "colorBackground": false,
      "colorPostfix": false,
      "colorValue": true,
      "colors": [
        "rgba(245, 54, 54, 0.9)",
        "rgba(237, 129, 40, 0.89)",
        "rgba(50, 172, 45, 0.97)"
      ],
      "datasource": "${DS_PROMETHEUS}",
      "decimals": null,
      "description": "",
      "fieldConfig": {
        "defaults": {
          "custom": {}
        },
        "overrides": []
      },
      "format": "locale",
      "gauge": {
        "maxValue": 100,
        "minValue": 0,
        "show": false,
        "thresholdLabels": false,
        "thresholdMarkers": true
      },
      "gridPos": {
        "h": 2,
        "w": 8,
        "x": 16,
        "y": 39
      },
      "id": 178,
      "interval": null,
      "links": [],
      "mappingType": 1,
      "mappingTypes": [
        {
          "name": "value to text",
          "value": 1
        },
        {
          "name": "range to text",
          "value": 2
        }
      ],
      "maxDataPoints": 100,
      "maxPerRow": 6,
      "nullPointMode": "null",
      "nullText": null,
      "postfix": "",
      "postfixFontSize": "50%",
      "prefix": "",
      "prefixFontSize": "50%",
      "rangeMaps": [
        {
          "from": "null",
          "text": "N/A",
          "to": "null"
        }
      ],
      "sparkline": {
        "fillColor": "rgba(31, 118, 189, 0.18)",
        "full": false,
        "lineColor": "rgb(31, 120, 193)",
        "show": false
      },
      "tableColumn": "",
      "targets": [
        {
          "expr": "avg(node_filefd_maximum{instance=~\"$node\"})",
          "format": "time_series",
          "instant": true,
          "intervalFactor": 1,
          "legendFormat": "",
          "refId": "A",
          "step": 20
        }
      ],
      "thresholds": "1024,10000",
      "title": "总文件描述符",
      "type": "singlestat",
      "valueFontSize": "70%",
      "valueMaps": [
        {
          "op": "=",
          "text": "N/A",
          "value": "null"
        }
      ],
      "valueName": "current"
    }
  ],
  "refresh": false,
  "schemaVersion": 25,
  "style": "dark",
  "tags": [
    "Prometheus",
    "node_exporter",
    "StarsL.cn"
  ],
  "templating": {
    "list": [
      {
        "allValue": null,
        "current": {},
        "datasource": "${DS_PROMETHEUS}",
        "definition": "label_values(node_uname_info, project)",
        "hide": 0,
        "includeAll": true,
        "label": "项目",
        "multi": true,
        "name": "project",
        "options": [],
        "query": "label_values(node_uname_info, project)",
        "refresh": 1,
        "regex": "",
        "skipUrlSync": false,
        "sort": 1,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      },
      {
        "allValue": null,
        "current": {},
        "datasource": "${DS_PROMETHEUS}",
        "definition": "label_values(node_uname_info{project=~\"$project\"}, job)",
        "hide": 0,
        "includeAll": false,
        "label": "IP",
        "multi": false,
        "name": "job",
        "options": [],
        "query": "label_values(node_uname_info{project=~\"$project\"}, job)",
        "refresh": 1,
        "regex": "",
        "skipUrlSync": false,
        "sort": 3,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      },
      {
        "allFormat": "glob",
        "allValue": null,
        "current": {},
        "datasource": "${DS_PROMETHEUS}",
        "definition": "label_values(node_uname_info{job=~\"$job\",nodename=~\"$hostname\"},instance)",
        "hide": 0,
        "includeAll": false,
        "label": "采集器",
        "multi": false,
        "multiFormat": "regex values",
        "name": "node",
        "options": [],
        "query": "label_values(node_uname_info{job=~\"$job\",nodename=~\"$hostname\"},instance)",
        "refresh": 1,
        "regex": "",
        "skipUrlSync": false,
        "sort": 5,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      },
      {
        "allValue": null,
        "current": {},
        "datasource": "${DS_PROMETHEUS}",
        "definition": "label_values(node_uname_info{job=~\"$job\"}, nodename)",
        "hide": 0,
        "includeAll": false,
        "label": "主机名",
        "multi": false,
        "name": "hostname",
        "options": [],
        "query": "label_values(node_uname_info{job=~\"$job\"}, nodename)",
        "refresh": 1,
        "regex": "",
        "skipUrlSync": false,
        "sort": 5,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      },
      {
        "allFormat": "glob",
        "allValue": null,
        "current": {},
        "datasource": "${DS_PROMETHEUS}",
        "definition": "label_values(node_network_info{instance=~'$node',device!~'tap.*|veth.*|br.*|docker.*|virbr.*|lo.*|cni.*'},device)",
        "hide": 0,
        "includeAll": false,
        "label": "网卡",
        "multi": false,
        "multiFormat": "regex values",
        "name": "device",
        "options": [],
        "query": "label_values(node_network_info{instance=~'$node',device!~'tap.*|veth.*|br.*|docker.*|virbr.*|lo.*|cni.*'},device)",
        "refresh": 1,
        "regex": "",
        "skipUrlSync": false,
        "sort": 1,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      },
      {
        "allValue": null,
        "current": {},
        "datasource": "${DS_PROMETHEUS}",
        "definition": "query_result(topk(1,sort_desc (max(node_filesystem_size_bytes{instance=~'$node',fstype=~\"ext.?|xfs\",mountpoint!~\".*pods.*\"}) by (mountpoint))))",
        "hide": 2,
        "includeAll": false,
        "label": "最大挂载目录",
        "multi": false,
        "name": "maxmount",
        "options": [],
        "query": "query_result(topk(1,sort_desc (max(node_filesystem_size_bytes{instance=~'$node',fstype=~\"ext.?|xfs\",mountpoint!~\".*pods.*\"}) by (mountpoint))))",
        "refresh": 2,
        "regex": "/.*\\\"(.*)\\\".*/",
        "skipUrlSync": false,
        "sort": 5,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      },
      {
        "allValue": null,
        "current": {},
        "datasource": "${DS_PROMETHEUS}",
        "definition": "label_values(node_uname_info{job=~\"$job\",instance=~\"$node\"}, nodename)",
        "hide": 2,
        "includeAll": false,
        "label": "展示使用的主机名",
        "multi": false,
        "name": "show_hostname",
        "options": [],
        "query": "label_values(node_uname_info{job=~\"$job\",instance=~\"$node\"}, nodename)",
        "refresh": 1,
        "regex": "",
        "skipUrlSync": false,
        "sort": 5,
        "tagValuesQuery": "",
        "tags": [],
        "tagsQuery": "",
        "type": "query",
        "useTags": false
      }
    ]
  },
  "time": {
    "from": "now-24h",
    "to": "now"
  },
  "timepicker": {
    "hidden": false,
    "now": true,
    "refresh_intervals": [
      "15s",
      "30s",
      "1m",
      "5m",
      "15m",
      "30m"
    ],
    "time_options": [
      "5m",
      "15m",
      "1h",
      "6h",
      "12h",
      "24h",
      "2d",
      "7d",
      "30d"
    ]
  },
  "timezone": "browser",
  "title": "Linux主机详情",
  "uid": "9CWBzd1f0bik001",
  "version": 3
}
```

#### VictoriaMetrics

> 维多利亚指标

可以作为`prometheus`的本地存储代替方案，性能好，可水平扩容，这里就不展开来讲，作为本期`prometheus`监控的探索作业交给大家去了解了，因为这个在后面的夜莺监控里面会讲到。
