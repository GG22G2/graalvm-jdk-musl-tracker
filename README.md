# GraalVM 镜像构建

本仓库跟踪上游发布，重新构建并推送 GraalVM `native-image` 镜像，共 4 个：社区版，以及
Oracle GraalVM 的 3 个（amd64 musl、arm64 glibc、arm64 musl）。

其中 amd64 的两个跟随上游自动更新，两个 arm64 的为手动构建。产出的都是可直接作为 CI
构建环境使用的镜像。

| 流水线 | 产物 | JDK | libc | 架构 | 更新 |
|---|---|---|---|---|---|
| `build.yml` | `ghcr.io/gg22g2/graalvm-jdk-musl-maven` | 25 | musl | amd64 | 上游更新后自动 |
| `build-oracle.yml` | `ghcr.io/gg22g2/graalvm-jdk-musl-maven-oracle`<br>`ACR/gg22g2/ck:graalvm-oracle-jdk25-musl-maven` | 25 | musl | amd64 | 上游更新后自动 |
| `build-arm.yml` | `ACR/gg22g2/ck:graalvm-oracle-jdk25-arm-musl-maven` | 25 | glibc | arm64 | 手动 |
| `build-arm-muslib-ol10.yml` | `ACR/gg22g2/ck:graalvm-oracle-jdk25-arm-muslib-ol10-maven` | 25 | musl | arm64 | 手动 |

`ACR` = `crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com`

镜像内均含 Maven 3.9.16（阿里云源）与 git；两个 arm64 镜像另带一批常用命令行工具。
