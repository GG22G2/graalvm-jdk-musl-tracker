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

- 基础镜像固定为
  `container-registry.oracle.com/graalvm/native-image:25i4-25.0.4.1.1-ol10-20260922`
  —— Oracle GraalVM（企业版）arm64，**JDK 25.0.4 + glibc（Oracle Linux 10）**。
- 构建定义在 `Dockerfile.arm`，装 jq + git + Maven 3.9.16（阿里云源）。
- 在原生 arm64 runner（`ubuntu-24.04-arm`）上构建，不用 QEMU 模拟。
- 推送目标：阿里云 ACR
  `crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck`，
  tag 固定 `graalvm-oracle-jdk25-arm-musl-maven`，每次构建覆盖更新。

### 为什么是 glibc 而不是 musl（tag 名里的 musl 是历史遗留）

tag 名带 `musl`，但镜像实际是 **glibc** 的。原因：Oracle 的 `*-muslib-*` 系列
tag 至今全部只有 amd64，musl + arm64 在 Oracle 那边不存在；arm64 只出现在它的
glibc 系列。而更关键的是，**musl 镜像在云效上根本跑不起来**：

云效会往构建环境注入自己的工具链（`__flow_externals/node16/bin/node` 等），
那些二进制是 glibc 编译的，需要 `ld-linux-aarch64.so.1`。musl 镜像里只有
`ld-musl-aarch64.so.1`，于是云效直接报：

```
/root/workspace/__flow_externals/node16/bin/node: cannot execute: required file not found
```

（`required file not found` 是 musl 下动态链接器缺失的经典误导性报错 —— 文件明明
在那儿，是解释器找不到。）

而 Alpaquita 的 musl 仓库里**没有 `gcompat` / `libc6-compat`**，加不了兼容层，
所以只能换 glibc。已实测验证：同一个官方 glibc node16 arm64 二进制，
在 glibc 镜像里输出 `node v16.20.2` / `npm 8.19.4`，在旧的 musl 镜像里失败。

### 给云效（Yunxiao）流水线用

云效对自定义镜像有三条硬性要求（见
[官方文档](https://help.aliyun.com/zh/yunxiao/user-guide/custom-build-environment)）：
**必须包含 bash 和 jq，默认用户必须是 root**，并且它会用 `/bin/bash` 作为
entrypoint 起容器。本镜像已按此处理：

- 基础镜像自带 bash（`/usr/bin/bash`），jq 由 `microdnf` 装上
  （OL10 baseos 仓库里有 jq）。
- 另加 `/etc/profile.d/00-graalvm-path.sh` 幂等兜底，防止 login shell 下
  PATH 被覆盖导致 `mvn` / `java` 丢失（Oracle Linux 的 `/etc/profile` 本身是
  追加式的，不像 Alpaquita 那样直接赋值覆盖，但兜底无害）。
- Dockerfile 构建期会断言：bash/jq/java/native-image/mvn/git 齐全、uid=0、
  **存在 `ld-linux-aarch64.so.1`**，并且**实编一个 glibc C 程序并运行**，
  确认动态链接真的可用 —— 缺任何一项直接构建失败，不把问题留到云效上。

```bash
docker pull crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck:graalvm-oracle-jdk25-arm-musl-maven
docker run --rm --platform linux/arm64 -v "$PWD":/workspace \
  crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck:graalvm-oracle-jdk25-arm-musl-maven mvn -B package
```
