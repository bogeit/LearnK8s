FROM alpine:3.18

MAINTAINER Boge <github.com/bogeit>

ENV TZ "Asia/Shanghai"

RUN sed -ri 's+dl-cdn.alpinelinux.org+mirrors.aliyun.com+g' /etc/apk/repositories \
 && apk add --no-cache curl tzdata ca-certificates \
 && cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
 && apk upgrade \
 && rm -rf /var/cache/apk/*

COPY mycli /usr/local/bin/
RUN chmod +x /usr/local/bin/mycli

ENTRYPOINT ["mycli"]
CMD ["-h"]

# docker build -t harbor.boge.com/product/alertmanaer-webhook:1.0 .
