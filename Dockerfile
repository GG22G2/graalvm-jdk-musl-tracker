# 自动跟踪 ghcr.io/graalvm/native-image-community 的 *-muslib-ol10 系列
# 官方每次发布新日期 tag，check-upstream 工作流会自动触发本仓库构建，
# 用与官方相同的 tag 名推送到 ghcr.io/gg22g2/graalvm-jdk-musl-maven。
ARG BASE_IMAGE=ghcr.io/graalvm/native-image-community:25i2-25.0.4-muslib-ol10-20260728
ARG MAVEN_VERSION=3.9.16
FROM ${BASE_IMAGE}

# ARG 在 FROM 之后会失效，必须在当前阶段重新声明，RUN 里才能用到它的值
ARG MAVEN_VERSION

RUN microdnf --nodocs --setopt=install_weak_deps=0 install -y git-core pigz \
 && microdnf clean all \
 && curl -fL --connect-timeout 10 --retry 2 --retry-delay 3 --max-time 180 \
      -o /tmp/apache-maven.tgz \
      "https://mirrors.aliyun.com/apache/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
 && mkdir -p /opt /workspace \
 && tar -xzf /tmp/apache-maven.tgz -C /opt \
 && ln -sfn /opt/apache-maven-${MAVEN_VERSION} /opt/maven \
 && rm -f /tmp/apache-maven.tgz /opt/apache-maven-${MAVEN_VERSION}/bin/*.cmd \
 && rm -rf "$JAVA_HOME"/jmods "$JAVA_HOME"/lib/src.zip "$JAVA_HOME"/man \
 && rm -rf /var/cache/dnf /var/cache/yum /root/.cache /tmp/* /var/tmp/*

COPY maven-settings.xml /opt/maven/conf/settings.xml

ENV MAVEN_HOME=/opt/maven \
    PATH=/opt/maven/bin:/usr/local/musl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /workspace
ENTRYPOINT []
CMD ["/bin/bash"]
