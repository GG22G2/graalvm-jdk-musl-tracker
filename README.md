# 自动跟踪 GraalVM 官方 muslib-ol10 镜像

本仓库自动跟踪 GraalVM 官方发布的 **`*-muslib-ol10-YYYYMMDD`** 系列镜像，共两条流水线：

- **社区版**：跟踪 [graalvm/container](https://github.com/graalvm/container) 的
  `ghcr.io/graalvm/native-image-community`
- **企业版**（Oracle GraalVM）：跟踪
  `container-registry.oracle.com/graalvm/native-image`

两条流水线共用一个 `Dockerfile`（基础镜像由 `BASE_IMAGE` 传入），构建内容相同：
官方镜像 + Maven 3.9.16（阿里云源）+ git + pigz + 瘦身。

- 官方每发布一个新日期 tag → 对应 `check-upstream*`（每天定时）自动触发 `build*` 构建
- 推送位置与 tag：
  - 社区版 → `ghcr.io/gg22g2/graalvm-jdk-musl-maven`
  - 企业版 → `ghcr.io/gg22g2/graalvm-jdk-musl-maven-oracle`（同官方 3 个 tag）
    和阿里云 ACR `crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck`
    （固定 `graalvm-oracle-jdk25-musl-maven` 一个 tag，每次构建覆盖更新）
  - tag 与官方同款：`25i2-25.0.4-muslib-ol10-20260728`（同官方日期 tag）、
    `25i2-25.0.4-muslib-ol10`（去日期短 tag）、`latest`

## 使用

```bash
# 社区版
docker pull ghcr.io/gg22g2/graalvm-jdk-musl-maven:latest
docker run --rm -v "$PWD":/workspace ghcr.io/gg22g2/graalvm-jdk-musl-maven:latest mvn -B package

# 企业版
docker pull ghcr.io/gg22g2/graalvm-jdk-musl-maven-oracle:latest
docker run --rm -v "$PWD":/workspace ghcr.io/gg22g2/graalvm-jdk-musl-maven-oracle:latest mvn -B package
```

## 工作原理

- `check-upstream.yml` / `check-upstream-oracle.yml`：每天北京时间 02:37 / 02:47
  拉取上游官方 tag 列表（ghcr / Oracle container-registry），与
  `built-tag.txt` / `built-tag-oracle.txt`（最近一次成功构建的官方 tag）对比，
  发现新的就触发对应 build。
- `build.yml` / `build-oracle.yml`：用官方新 tag 作基础镜像构建，验证 5 个工具
  版本，推送 3 个 tag，成功后把新 tag 写回对应的 built-tag 文件。
- 构建失败不会写 built-tag 文件，下一次 check 会自动重试。

## arm64 镜像（手动触发）

`build-arm.yml` 是独立的一条**手动**流水线，与上面两条定时跟踪互不影响（不读写
built-tag 文件，不会被 check-upstream 触发）：

- 基础镜像固定为 `ghcr.io/bell-sw/liberica-native-image-kit-container:jdk-25-nik-25.0.4-musl`
  —— BellSoft Liberica NIK，JDK 25.0.4 + musl + arm64。
- 构建定义在 `Dockerfile.arm`，同样装 Maven 3.9.16（阿里云源）+ git。
- 在原生 arm64 runner（`ubuntu-24.04-arm`）上构建，不用 QEMU 模拟。
- 推送目标：阿里云 ACR
  `crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck`，
  tag 固定 `graalvm-oracle-jdk25-arm-musl-maven`，每次构建覆盖更新。

为什么不用 Oracle GraalVM：Oracle 的 `*-muslib-*` 系列 tag 至今全部只有 amd64，
musl + arm64 的组合在 Oracle 那边不存在（arm64 只出现在 glibc 系列）。要换回
Oracle，得接受 glibc，或者改用 GraalVM 社区版。

### 给云效（Yunxiao）流水线用

云效对自定义镜像有三条硬性要求（见
[官方文档](https://help.aliyun.com/zh/yunxiao/user-guide/custom-build-environment)）：
**必须包含 bash 和 jq，默认用户必须是 root**，并且它会用 `/bin/bash` 作为
entrypoint 起容器。本镜像已按此处理：

- 基镜像 Alpaquita 只有 ash/sh，**没有 bash 和 jq**，所以 Dockerfile 显式
  `apk add bash jq`（bash 在 core 仓库，jq 在 universe 仓库）。
  缺 bash 时云效会直接报
  `exec: "/bin/bash": stat /bin/bash: no such file or directory`。
- 基镜像的 `/etc/profile` 第 1 行是
  `export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"`，会**整个覆盖
  PATH**。云效用 bash 起容器，login shell 读到它之后 `mvn`、`java` 就都从 PATH
  里消失了。镜像里加了 `/etc/profile.d/00-graalvm-path.sh` 兜底
  （`/etc/profile` 末尾会 source `profile.d/*.sh`）。
- Dockerfile 构建期会断言 bash/jq/java/native-image/mvn/git 齐全、uid=0，
  并用 `bash -lc` 复现云效的 login shell，缺任何一项直接构建失败。

```bash
docker pull crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck:graalvm-oracle-jdk25-arm-musl-maven
docker run --rm --platform linux/arm64 -v "$PWD":/workspace \
  crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck:graalvm-oracle-jdk25-arm-musl-maven mvn -B package
```
