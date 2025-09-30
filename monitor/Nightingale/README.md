### 夜莺(以下简称N9E)介绍PPT

https://c9xudyniiq.feishu.cn/slides/O6xJsUzZclzeUrdMb9DcynVtnSf

#### 文档

https://flashcat.cloud/docs/content/flashcat-monitor/nightingale-v8/prologue/introduction/


#### 下载中心

https://flashcat.cloud/download/

#### GITHUB

https://github.com/ccfos/nightingale



#### N9E常用的两类生产场景

公司生产已经有了Prometheus监控系统，可使用N9E来作为报警规则处理及发送使用

![n9e-01](../pics/n9e-01.png)

完全使用N9E来部署监控系统，同时也可接入像Prometheus这样的数据源使用

![n9e-02](../pics/n9e-02.png)


### 全量部署夜莺N9E监控系统

#### docker部署mysql和redis

```shell
docker run -d --name mysql-test \
           -p3306:3306 \
           -e MYSQL_ROOT_PASSWORD=bogeit \
           -v /mnt/mysql-data:/var/lib/mysql \
           registry.cn-beijing.aliyuncs.com/bogeit/mysql:5.7.44-oraclelinux7 \
           --character-set-server=utf8mb4 \
           --collation-server=utf8mb4_unicode_ci \
           --max_allowed_packet=20M \
           --lower_case_table_names=1 \
           --max_connections=5000 \
           --sql_mode=STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION


docker run --name myredis \
           --net host --privileged \
           -d registry.cn-beijing.aliyuncs.com/bogeit/redis:6.2.16-alpine3.20 \
           /bin/sh -c "echo 2000 > /proc/sys/net/core/somaxconn && \
           echo 1 > /proc/sys/vm/overcommit_memory && \
           mount -o remount rw /sys && \
           echo never > /sys/kernel/mm/transparent_hugepage/enabled && \
           redis-server --requirepass bogeit"
```

