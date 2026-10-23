
---

# arm64 的 `*-muslib-ol10` 等价镜像（`build-arm-muslib-ol10.yml`）

上面 `build-arm.yml` 那个 arm 镜像是 **glibc** 口径的，native-image 只能编 glibc
产物。这一条流水线做的是另一件事：**在 arm64 上复刻 Oracle amd64 的
`*-muslib-ol10`** —— 镜像本身是 glibc 用户空间（依赖 glibc 的程序能跑），
但 `native-image` 默认走 musl，能编出完全静态的 aarch64 可执行文件。

- 构建定义：`Dockerfile.arm-muslib-ol10`
- 手动触发：`build-arm-muslib-ol10.yml`，在原生 `ubuntu-24.04-arm` runner 上构建
- 推送目标：阿里云 ACR
  `crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck`，
  tag 固定 `graalvm-oracle-jdk25-arm-muslib-ol10-maven`，每次构建覆盖更新
- 基础镜像：`oraclelinux:10-slim`（arm64，glibc 2.39），与 amd64 的 ol10 基线对齐

```bash
docker pull crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck:graalvm-oracle-jdk25-arm-muslib-ol10-maven
docker run --rm --platform linux/arm64 -v "$PWD":/workspace \
  crpi-xm8affxmcnbpks63.cn-shanghai.personal.cr.aliyuncs.com/gg22g2/ck:graalvm-oracle-jdk25-arm-muslib-ol10-maven \
  native-image --libc=musl --static -cp . MyApp
```

## 为什么不能直接拿 Oracle 的 muslib-ol10，以及真正的缺口在哪

Oracle 的 `*-muslib-ol10` 系列至今**只有 amd64**，arm64 只出现在它的 glibc 系列
（ol8/ol9/ol10）。所以 arm64 版必须自己做。

但缺口不是"缺一个 musl 编译器"。`--libc=musl` 需要的是**按 musl 编好的 JDK 静态库**
（`lib/static/<os>-<arch>/musl/{libjava,libnio,libnet,libzip,...}.a`，`--static` 全静态
链接要用）。实测（2026-10-23）四处都只有 glibc 那一份：

| 来源 | `lib/static/linux-aarch64/` 下有什么 |
|---|---|
| GraalVM Community aarch64 发行包 | 只有 `glibc` |
| Oracle GraalVM aarch64 发行包 | 只有 `glibc` |
| Oracle 自己的 aarch64 RPM（yum.oracle.com graalvm/community/aarch64） | 78 项，全在 `glibc` 下 |
| amd64 发行包（对照） | `glibc` 和 `musl` 两份齐全 |

所以只装 musl 工具链的话，`native-image --libc=musl` 会在 `[1/8]` 直接报：

```
Error: Building images on LINUX_AARCH64 (target libc: musl) is not supported on your platform.
Build on a different platform or try upgrading to a newer GraalVM release
Missing libraries: java, nio, net
(search path: <JAVA_HOME>/lib/static/linux-aarch64/musl)
```

**解决办法**：用 BellSoft Liberica NIK 的 aarch64-musl 发行包里那套静态 JDK 库
（42 个 `.a`）补进 Oracle GraalVM 的 `lib/static/linux-aarch64/musl/`。
NIK 是同一份 GraalVM 代码库的商业发行版，官方就出 aarch64+musl 组合，而 Oracle 不出。

## 另外两个 aarch64 特有的坑（都已实测踩过并绕开）

### 1. GraalVM 25 的 driver 在 aarch64 上硬找 `x86_64-linux-musl-gcc`

`HostedMuslLibC.getTargetCompiler()` 里 musl 交叉编译的编译器名是硬编码的：

```java
return isCrossCompiling() ? "x86_64-linux-musl-gcc" : "gcc";
```

（历史上该处曾按目标架构返回 `x86_64-linux-musl-gcc` / `aarch64-linux-musl-gcc`
两种名字，后来被简化成只认前者。）于是 aarch64 上会报：

```
Error: Default native-compiler executable 'x86_64-linux-musl-gcc' not found via environment variable PATH
```

`x86_64` 这个名字在这里纯粹被当成"PATH 上的一个可执行文件名"，所以建个
`x86_64-linux-musl-gcc` 指向真正的 aarch64 musl gcc 即可。

### 2. musl.cc 的工具链默认 PIE，会和 native-image 固定的 `-z text` 冲突

musl.cc 的 aarch64 native 工具链是 `--enable-default-pie --enable-static-pie` 编的，
默认产出 PIE。对纯 C 小程序没问题，但 native-image 的真实产物会在**链接期**炸：

```
/usr/local/musl/bin/ld: read-only segment has dynamic relocations
collect2: error: ld returned 1 exit status
```

触发条件是产物里出现需要重定位的只读段 —— 实测带 `java.net.InetAddress`
（会用 `getaddrinfo`）的应用**必现**，而最简单的 `System.out.println` Hello
反而不触发，所以只用 Hello 做冒烟测试会漏掉这个问题。

原因在 native-image 自己的链接代码 `CCLinkerInvocation.BinutilsCCLinkerInvocation`：
它固定加 `-z text`（注释写着"否则镜像在 SELinux 上跑不起来"），即禁止只读段重定位；
而 PIE 链接会往只读段塞重定位，两者直接冲突。实测三种走法：

| 走法 | 结果 |
|---|---|
| `--static` 默认（PIE） | 链接失败 `read-only segment has dynamic relocations` |
| 加 `-Wl,-z,notext`（允许重定位） | 链接过了，但一运行就 `Segmentation fault` |
| 加 `-no-pie` | 成功，产物是真正的 `statically linked`（非 PIE） |

Oracle 官方 amd64 的 muslib-ol10 用自家 musl 工具链（gcc 10.2.1）不踩这个坑，
所以它不需要任何额外参数。这里用**包装脚本**在编译/链接时补上 `-no-pie`，
让 `native-image --libc=musl --static` 不带任何额外参数也能正常出产物。

### 3. PATH 顺序：musl 放在系统目录之后

Oracle 的 amd64 muslib-ol10 把 `/usr/local/musl/bin` 放在 PATH 最前。aarch64 上
这样做有副作用：musl 工具链的 bin 里有名为 `ld` 和 `gcc` 的可执行文件，放最前会把
**所有**编译（包括 glibc 程序的常规编译）劫持到 musl 的 ld，于是 glibc 程序一编就报：

```
/usr/local/musl/bin/ld: /usr/libexec/gcc/aarch64-redhat-linux/14/liblto_plugin.so:
  error loading plugin: Dynamic loading not supported
```

这和"镜像里 glibc 程序能正常跑/正常编译"的目标冲突。所以这里把
`/usr/local/musl/bin` 放到系统目录之后，裸 `gcc`/`ld`/`cc` 是 glibc 的；
native-image 编 musl 时由它自己按 `TOOLCHAIN_DIR` 和上面那个硬编码名找 musl 编译器，
不依赖 PATH 顺序。两种顺序都实测能产出可运行的 musl 静态二进制，这里选了不牺牲 glibc 的那种。

## 构建期断言

`Dockerfile.arm-muslib-ol10` 把上面所有约束都卡在构建期，任何一条不过就直接失败：

1. 必需命令齐全 —— 分两组：云效硬性要求 + `step-user-*.sh` 会直接调用的那批
   （`bash` `jq` `gzip` `gunzip` `find` `xargs` `ps` `ssh` `scp` `unzip` 等，
   漏任何一个云效流水线都会中途 exit 127），以及 native-image 工具链自用
   （`cc` `gcc` `ld` `make` `readelf` `objdump` `nm` `ar` `strip`）。
   其中 `gzip`/`find`/`xargs`/`jq` 不只查存在，还会真跑一遍；
   并在 `bash -lc`（login shell，复现云效启动方式）下再查一次 `mvn`/`java`/`jq`/`gzip`
2. 存在 glibc 动态链接器 `ld-linux-aarch64.so.1`（三个候选路径任一）
3. musl 工具链在位（`aarch64-linux-musl-gcc`、`x86_64-linux-musl-gcc` 包装脚本、`libz.a`、`libc.a`），
   且下载的 musl 工具链 **sha256 与预期一致**（防止镜像源内容被替换）
4. musl 静态 JDK 库在位（`libjava/libnio/libnet/libzip/libjvm`）
5. `java` 的 ELF `e_machine` 是 `b700`（AArch64），默认用户 uid=0
6. 真编一个 glibc 动态程序并运行（断言带 INTERP），真编一个 musl 全静态程序并运行
7. **真编一个 `native-image --libc=musl --static` 产物并运行** —— 用带
   `InetAddress`/`Files` 的应用，断言 `INTERP=0` 且 `NEEDED=0`，然后跑起来看输出

`build-arm-muslib-ol10.yml` 里另有一轮独立的复核，其中最硬的一条是把产物
放进 `FROM scratch` 的空镜像里跑通。

## 实测结果（47.111.136.59，Ubuntu 24.04 aarch64，真机非 QEMU）

- 镜像 `linux/arm64`，约 1.5 GB
- glibc 侧：`ldd (GNU libc) 2.39`，动态链接器在 `/lib/ld-linux-aarch64.so.1`，
  `/usr/bin/gcc` 编出的程序带 INTERP 且能跑，`jq`/`sed`/`awk`/`grep` 依赖 `libc.so.6` 正常
- 云效相关：`bash`/`jq`/`gzip`/`find`/`xargs` 等全部齐备并实跑通过，
  login shell（`/bin/bash -lc`，复现云效启动方式）下 `mvn`/`java`/`native-image` 都在
- `native-image --libc=musl --static -cp . App`（App 用 `InetAddress` + `Files`）：
  约 3 分 20 秒，产出 `ELF 64-bit LSB executable, ARM aarch64, statically linked`，
  `INTERP=0 NEEDED=0`，运行输出正确
- 同一产物放进 `FROM scratch` 容器里运行成功
- **CI 产物已在 ACR 上复验**：从 `crpi-xm8affxmcnbpks63.../gg22g2/ck:graalvm-oracle-jdk25-arm-muslib-ol10-maven`
  拉取后重跑上述全部检查，均通过

## 关于 musl 工具链的下载源

`MUSL_URL` 默认指向 **GitHub 镜像 `musl-cc/musl.cc`**，而不是 `musl.cc` 本身 ——
实测 GitHub Actions runner 连不上 musl.cc（`Failed to connect to musl.cc port 443`），
但能正常访问 GitHub。

该镜像的 `aarch64-linux-musl-native.tgz` 已与 musl.cc 官方原版做过 **sha256 逐字节比对，
完全一致**（`daf336ca...8ad2a069`，85323901 字节）。Dockerfile 里用 `MUSL_SHA256`
在构建期再校验一次，所以换成别的源只要内容一致就能用，内容不一致会直接构建失败。

## 已知边界

- 上面那个 `x86_64-linux-musl-gcc` 硬编码名是 GraalVM 25 的行为。以后 GraalVM 若
  按目标架构返回正确名字，这个包装脚本会变成"名字没被用到"的死代码，不影响功能；
  若反而改成别的名字，构建期断言 3 会立刻失败，不会静默出错。
- musl.cc 的 aarch64 工具链是 gcc 11.2.1。Oracle 官方 amd64 用的是自家
  musl-toolchain（gcc 10.2.1），两者都是 gcc 10/11 量级，行为差异只在上面那个 PIE 默认值上。
- 本镜像的 glibc 是 2.39（ol10）。如果产物要拿到更低 glibc 的目标机上跑，
  那是"运行时 glibc 版本"的问题，与 musl 静态产物无关（静态产物完全不依赖 glibc）；
  但镜像里那些 glibc 工具本身仍受此约束。
