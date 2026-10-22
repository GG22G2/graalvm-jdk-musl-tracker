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
  `container-registry.oracle.com/graalvm/native-image:25i4-25.0.4.1.1-ol8-20260922`
  —— Oracle GraalVM（企业版）arm64，**JDK 25.0.4 + glibc 2.28（Oracle Linux 8）**。
- 构建定义在 `Dockerfile.arm`，装 jq + git + Maven 3.9.16（阿里云源），
  以及云效步骤脚本要用的一批命令行工具（见下）。
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

### 为什么用 ol8 而不是 ol10（glibc 版本决定产物能跑在哪台机器上）

目标部署机是**银河麒麟 V10 SP1**（基于 Ubuntu 20.04，glibc **2.31**）。
glibc 是**向后兼容、不向前兼容**的：在 glibc 2.39 上编译的二进制，拿到 2.31
的机器上会因为找不到符号而直接报

```
version `GLIBC_2.34' not found
```

Oracle GraalVM 的 arm64 提供三个 Oracle Linux 变体（**三个都有 arm64**，只有
glibc 版本不同）：

| 变体 | glibc | 对麒麟 2.31 |
|---|---|---|
| `ol8` | **2.28** | **安全** ← 当前使用 |
| `ol9` | 2.34 | 有风险（2.34 > 2.31） |
| `ol10` | 2.39 | 会失败 |

因此基础镜像固定用 `ol8`。构建期有两道断言把这个约束卡死：

- `Dockerfile.arm`：构建机 glibc 必须 ≤ 2.31，否则构建失败（防止以后误换回 ol9/ol10）
- `build-arm.yml`：**真编一个 native-image 产物**，用 `readelf --version-info` 读出它
  引用的最高 GLIBC 符号版本，超过 2.31 就让构建失败，不推镜像

实测结果：产物最高只引用 **GLIBC_2.17**，远低于目标机的 2.31，余量充足。

如果目标机的 glibc 不是 2.31（比如换了系统版本），改 `build-arm.yml` 里的
`TARGET_GLIBC` 和 `BASE_IMAGE` 两个值即可。

### 给云效（Yunxiao）流水线用

云效对自定义镜像有三条硬性要求（见
[官方文档](https://help.aliyun.com/zh/yunxiao/user-guide/custom-build-environment)）：
**必须包含 bash 和 jq，默认用户必须是 root**，并且它会用 `/bin/bash` 作为
entrypoint 起容器。本镜像已按此处理：

- 基础镜像自带 bash（`/usr/bin/bash`），jq 由 `microdnf` 装上
  （OL8 的 jq / git / wget 在 appstream 仓库，该仓库默认启用）。
- 另加 `/etc/profile.d/00-graalvm-path.sh` 幂等兜底，防止 login shell 下
  PATH 被覆盖导致 `mvn` / `java` 丢失（Oracle Linux 的 `/etc/profile` 本身是
  追加式的，不像 Alpaquita 那样直接赋值覆盖，但兜底无害）。
- Dockerfile 构建期会断言：bash/jq/java/native-image/mvn/git/readelf 及下面那批
  命令行工具齐全、`find` 能真正跑起来、uid=0、**存在 `ld-linux-aarch64.so.1`**，
  并且**实编一个 glibc C 程序并运行**，确认动态链接真的可用 —— 缺任何一项直接
  构建失败，不把问题留到云效上。

### 为什么要额外装一批命令行工具（findutils 等）

云效的步骤脚本（`step-user-*.sh`）是它自己生成的，里面直接调用 `find` 这类命令，
而 **ol8 的 slim 基础镜像里没有 findutils**：实测 base layer 的 `/usr/bin` 只有
208 项，`find`、`xargs`、`ps`、`ssh`、`unzip` 都不在（ol10 的基础层里则有
`find` / `xargs`）。所以从 ol10 换到 ol8 之后，云效流水线在 Maven 构建成功之后
直接倒在下一步：

```
scripts/step-user-3.sh: line 5: find: command not found
[ERROR] run user script failed, exit code: 127
```

因此 `Dockerfile.arm` 里显式装了这批工具：`findutils gawk sed grep diffutils patch
tar gzip pigz xz bzip2 zip unzip file which less hostname procps-ng openssh-clients
rsync ca-certificates tzdata binutils`，构建期逐条断言，缺任何一条都不推镜像。

```bash
docker pull crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck:graalvm-oracle-jdk25-arm-musl-maven
docker run --rm --platform linux/arm64 -v "$PWD":/workspace \
  crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck:graalvm-oracle-jdk25-arm-musl-maven mvn -B package
```
