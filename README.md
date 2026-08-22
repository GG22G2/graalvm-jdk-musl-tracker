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
