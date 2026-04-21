# IP2Proxy → MMDB Universal Converter

将 [IP2Proxy](https://www.ip2location.com/database/ip2proxy) CSV 数据库转换为 MaxMind MMDB 格式的工具。

支持版本：**PX8 / PX9 / PX10 / PX11 / PX12**（LITE 与商业版均可）

---

## ✨ 功能特点

- 🔍 **自动识别版本** — 从文件名中自动识别 PX 版本，无需手动指定
- 🗂 **完整字段映射** — 保留所有字段（proxy_type、country、isp、threat、fraud_score 等）
- 🌐 **IPv4 / IPv6 双栈** — 自动判断地址版本，统一写入 IPv6 树
- ⚡ **性能优化** — GMP/Pari 加速大整数运算，批量日志降低 IO 开销
- 🛡 **健壮容错** — 跳过格式异常行并汇报，不中断整体转换

---

## 📋 字段对照表

| 字段名         | 类型        |  PX8  |  PX9  | PX10  | PX11  | PX12  |
| -------------- | ----------- | :---: | :---: | :---: | :---: | :---: |
| `is_proxy`     | uint32      |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `proxy_type`   | utf8_string |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `country_code` | utf8_string |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `country_name` | utf8_string |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `region_name`  | utf8_string |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `city_name`    | utf8_string |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `isp`          | utf8_string |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `domain`       | utf8_string |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `usage_type`   | utf8_string |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `asn`          | utf8_string |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `last_seen`    | uint32      |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `threat`       | utf8_string |   ✅   |   ✅   |   ✅   |   ✅   |   ✅   |
| `provider`     | utf8_string |   ❌   |   ✅   |   ✅   |   ✅   |   ✅   |
| `fraud_score`  | uint32      |   ❌   |   ❌   |   ✅   |   ✅   |   ✅   |
| `residential`  | utf8_string |   ❌   |   ❌   |   ❌   |   ✅   |   ✅   |
| `as_name`      | utf8_string |   ❌   |   ❌   |   ❌   |   ❌   |   ✅   |

> **proxy_type 枚举值：** VPN / TOR / DCH / PUB / WEB / SES / RES / CPN / FBT / UNK

---

## 🖥 环境要求

### Perl 5.16+

```bash
perl --version
```

### CPAN 依赖

```bash
cpanm Text::CSV \
       Math::BigInt \
       Math::BigInt::GMP \
       Net::Works \
       MaxMind::DB::Writer
```

> 若 `Math::BigInt::GMP` 安装失败（需要 libgmp-dev），可改用纯 Perl 后端，速度略慢：
> ```bash
> cpanm Math::BigInt::FastCalc
> ```

### Ubuntu / Debian 系统依赖

```bash
sudo apt-get install libgmp-dev
```

### macOS (Homebrew)

```bash
brew install gmp
```

---

## 🚀 使用方法

### 基础用法（自动识别版本）

```bash
perl ip2proxy_to_mmdb.pl --input IP2PROXY-LITE-PX11.CSV
# 输出: IP2PROXY-LITE-PX11.mmdb
```

### 指定版本与输出路径

```bash
perl ip2proxy_to_mmdb.pl \
  --input  IP2PROXY-LITE-PX10.CSV \
  --version PX10 \
  --output  /data/proxy_px10.mmdb
```

### 省略 country_name（减小文件体积）

```bash
perl ip2proxy_to_mmdb.pl --input IP2PROXY-LITE-PX11.CSV --no-country
```

### 全部选项

```
--input  <file>     输入 CSV 文件（默认：自动检测当前目录）
--output <file>     输出 MMDB 文件（默认：<input_basename>.mmdb）
--version <PXn>     强制指定版本：PX8 PX9 PX10 PX11 PX12
--no-country        省略 country_name 字段
--help              显示帮助
```

---

## 🔍 验证输出

使用 [mmdblookup](https://github.com/maxmind/libmaxminddb) 验证：

```bash
mmdblookup --file IP2PROXY-LITE-PX11.mmdb --ip 1.2.3.4
```

或在 Python 中验证：

```python
import maxminddb

with maxminddb.open_database('IP2PROXY-LITE-PX11.mmdb') as db:
    result = db.get('1.2.3.4')
    print(result)
    # {'is_proxy': 1, 'proxy_type': 'VPN', 'country_code': 'US', ...}
```

---

## ⚙️ 自定义列顺序

如果你的 CSV 列顺序与默认不同，运行时脚本会**打印实际列顺序**供核对：

```
📋 CSV 列顺序确认:
   [00] ip_from
   [01] ip_to
   [02] proxy_type
   [03] country_code
   ...
```

若列序不符，直接修改脚本中 `%SCHEMAS` 哈希里对应版本的 `col_index`（第一个数字）即可。

---

## 📊 性能参考

| 环境                  | 记录数    | 耗时  |
| --------------------- | --------- | ----- |
| Linux, Perl 5.36, GMP | 1,000,000 | ~90s  |
| macOS M2, Perl 5.38   | 1,000,000 | ~75s  |
| Windows WSL2          | 1,000,000 | ~120s |

---

## 📁 项目结构

```
.
├── ip2proxy_to_mmdb.pl     # 主转换脚本
├── README.md               # 本文件
└── IP2PROXY-LITE-PX11.CSV  # 你的源数据（需自行下载）
```

---

## 📜 许可证

[MIT License](./LICENSE) © 2026 QingXian（清仙）

本项目基于 MIT 协议开源，允许自由使用、修改与分发，但须保留原始版权声明。

---

## 🙏 致谢

- [IP2Location](https://www.ip2location.com/) — 数据提供方
- [MaxMind::DB::Writer](https://metacpan.org/pod/MaxMind::DB::Writer) — MMDB 写入库
- [Net::Works](https://metacpan.org/pod/Net::Works) — IP 地址与子网处理