# ILA ADC 调试使用指南

## 概述

ILA (Integrated Logic Analyzer) 是 Xilinx FPGA 内置的在线逻辑分析仪。本指南教你如何使用 ILA 抓取 ADC 引脚的工作状态，验证 XADC 是否正常采样。

### 被监控的信号

| 信号名 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|
| `device_mode` | 2 | 25MHz | 当前工作模式 (00=信号发生器, 01=示波器, 10=李萨如, 11=万花筒) |
| `mux_sel` | 1 | 100MHz | 74HC4053 通道选择 (0=CH1, 1=CH2) |
| `ch1_vld_raw` | 1 | 100MHz | CH1 XADC 原始有效脉冲 (来自 DRDY) |
| `ch2_vld_raw` | 1 | 100MHz | CH2 XADC 原始有效脉冲 (来自 DRDY) |
| `drp_drdy` | 1 | 100MHz | **XADC DRP data-ready** — 监控 DRDY 是否异常/卡高 |
| `drp_den` | 1 | 100MHz | **XADC DRP enable** — DEN 脉冲发送到 XADC |
| `settling` | 1 | 100MHz | **4053 建立等待** — 1=等待模拟开关稳定 |
| `den_pending` | 1 | 100MHz | **DEN 挂起** — 1=等待发出下一个 DEN |
| `startup_done` | 1 | 100MHz | **XADC 校准完成** — 1=启动后校准完毕 |
| `trigger_fired` | 1 | 25MHz | 示波器触发已触发 |
| `sample_wr_addr` | 10 | 25MHz | 波形 RAM 写地址 |
| `adc_ch1_raw` | 12 | 100MHz | CH1 12位原始 XADC 数据 |
| `adc_ch2_raw` | 12 | 100MHz | CH2 12位原始 XADC 数据 |
| `adc_ch1_8b` | 8 | 25MHz | CH1 8位示波器数据 |
| `adc_ch2_8b` | 8 | 25MHz | CH2 8位示波器数据 |
| `clk_25m_ref` | 1 | 25MHz | 25MHz 参考时钟 (用于确认时钟存在) |

---

## 第一步：生成 ILA IP 核

ILA 需要在综合前作为 IP 核创建。打开 Vivado 项目后，在 Tcl Console 中运行：

```tcl
# 1. 确认你在正确的项目中
current_project

# 2. 执行 ILA 创建脚本
cd [get_property DIRECTORY [current_project]]
source create_ila_adc.tcl
```

这会创建一个名为 `ila_adc` 的 ILA IP 核：
- **采样时钟**: 100MHz (sys_clk)
- **探针宽度**: 64 位 (单个探针)
- **采样深度**: 2048 (约 20.48µs 的捕捉窗口)
- **高级触发**: 启用 (支持触发序列器)

> ⚠️ **注意**: ILA 使用的 IP 版本是 `ila v6.2`。如果你使用的是较旧版本的 Vivado (如 2017.x)，需要将 `create_ila_adc.tcl` 中的 `-version 6.2` 改为 `-version 6.1` 或更早版本。

---

## 第二步：确认文件已添加到工程

确保以下文件已经添加到 Vivado 项目中：

| 文件 | 类型 | 路径 |
|---|---|---|
| `ila_adc_debug.v` | Design Source | `pocketscope_sim.srcs/sources_1/new/` |
| `ila_adc.xdc` | Constraints | `pocketscope_sim.srcs/constrs_1/new/` |

同时确认 `top.v` 中已经包含了 ILA 的实例化（已自动添加）。

### 检查 top.v 是否正确

打开 `top.v`，搜索 `u_ila_adc`，确认存在以下代码：

```verilog
ila_adc_debug u_ila_adc (
    .clk   (sys_clk),
    .probe (ila_probe)
);
```

---

## 第三步：综合 → 实现 → 生成比特流

按顺序执行：

```
1. Run Synthesis     (综合)
2. Run Implementation (实现)  
3. Generate Bitstream (生成比特流)
```

这些步骤在 Vivado GUI 左侧的 "Flow Navigator" 中依次点击即可。

> 💡 **提示**: 如果在综合时提示找不到 `ila_adc` 模块，说明 ILA IP 尚未生成，请回到第一步执行 `create_ila_adc.tcl`。

---

## 第四步：编程 FPGA 并打开 ILA

### 4.1 连接硬件

1. 用 USB 线连接 EGO1 开发板到电脑
2. 打开 **Hardware Manager** (Flow Navigator → Program and Debug → Open Hardware Manager)
3. 点击 **Open target** → **Auto Connect**

### 4.2 编程 FPGA

1. 在 Hardware 窗口中，右键点击 `xc7a35t_0` → **Program Device**
2. 选择刚生成的 `.bit` 文件 (通常在 `pocketscope_sim.runs/impl_1/top.bit`)
3. 点击 **Program**

编程成功后，Vivado 会自动检测到 ILA 调试核，弹出 ILA Dashboard。

---

## 第五步：使用 ILA 抓取波形

### 5.1 ILA 窗口布局

编程成功后，Vivado 会显示 ILA 窗口，包含以下几个区域：

```
┌─────────────────────────────────────────────────┐
│  Trigger Setup  (触发设置)                       │
│  ┌─────────────────────────────────────────────┐ │
│  │ Trigger Mode: BASIC / ADVANCED              │ │
│  │ Probe[63:0] = XXXX_XXXX_...                 │ │
│  │ Compare Value:  _____                       │ │
│  │ Operator: ==  / !=  / <  / >  / ...        │ │
│  │ Position: 512  (触发点在窗口中的位置)         │ │
│  └─────────────────────────────────────────────┘ │
│                                                   │
│  Waveform Viewer (波形显示区)                      │
│  ┌─────────────────────────────────────────────┐ │
│  │  probe[63:0]  ▁▂▃▄▅▆▇█▇▆▅▄▃▂▁               │ │
│  │  ...展开后可见各信号分组...                    │ │
│  └─────────────────────────────────────────────┘ │
│                                                   │
│  Status: Idle / Waiting for Trigger / Captured    │
└─────────────────────────────────────────────────┘
```

### 5.2 基本触发设置

ILA 的核心操作流程：**设置触发条件 → 等待触发 → 查看波形**

#### 触发条件示例 1：捕捉任意 XADC 数据

- 触发信号: 不设条件
- 操作符: `>=`  
- 比较值: `0`
- 说明：只要有数据就触发（等同于自动触发）

#### 触发条件示例 2：捕捉 CH1 有效数据

`ch1_vld_raw` 在探针的 bit 60 位置。设置：
- 在 Trigger Setup 中找到对应位
- 操作符: `==`
- 比较值: `1` (上升沿触发，即从 0 变 1 时捕获)

#### 触发条件示例 3：捕捉 mux_sel 切换

`mux_sel` 在探针的 bit 61 位置。设置：
- 操作符: `== R` (R = rising edge)
- 捕获时机：每次 4053 切换通道时

#### 触发条件示例 4：捕捉 DRDY 异常（诊断用）

`drp_drdy` 在探针的 bit 58 位置。设置：
- 操作符: `==`
- 比较值: `1`
- 目的：查看 DRDY 是否卡高（一直为 1）或正常脉冲

### 5.3 运行捕捉

1. **点击 ▶ (Run Trigger)** 按钮
2. ILA 状态变为 "Waiting for Trigger"
3. 当触发条件满足时，状态变为 "Captured"
4. 波形自动显示

### 5.4 查看波形

捕捉完成后，你可以：

- **放大/缩小**: 鼠标滚轮
- **平移**: 按住鼠标左键拖动
- **测量**: 在波形上右键 → 添加 Marker
- **数值查看**: 将鼠标悬停在波形上的任意位置，会显示该时刻的数值

### 5.5 重命名信号组（强烈推荐！）

默认情况下，ILA 显示的是一个 64 位的 `probe0` 总线。为了方便查看，你可以在 ILA 窗口中将其拆分为有意义的信号组：

1. 在 Waveform 窗口中，右键点击 `probe0[63:0]`
2. 选择 **New Group** 或 **Rename**
3. 根据以下位映射添加信号组：

```
信号分组参考 (probe[63:0]):

[63:62]  →  mode[1:0]              (工作模式)
[61]     →  mux_sel                (通道选择)
[60]     →  ch1_vld_raw            (CH1有效-XADC)
[59]     →  ch2_vld_raw            (CH2有效-XADC)
[58]     →  drp_drdy               (DRP数据就绪) ⚠️ 关键诊断信号
[57]     →  drp_den                (DRP使能脉冲)
[56]     →  settling               (4053建立等待)
[55]     →  den_pending            (DEN挂起标志)
[54]     →  startup_done           (XADC校准完成)
[53]     →  trig_fired             (触发已发送)
[52:43]  →  wr_addr[9:0]           (写地址)
[42:31]  →  ch1_raw[11:0]          (CH1原始12位)
[30:19]  →  ch2_raw[11:0]          (CH2原始12位)
[18:11]  →  ch1_8b[7:0]            (CH1 8位数据)
[10:3]   →  ch2_8b[7:0]            (CH2 8位数据)
[2]      →  clk_25m_ref            (25MHz参考)
```

---

## 第六步：诊断 ADC 工作状态

### 6.1 快速健康检查清单

捕捉一帧波形后，按以下顺序检查：

| 检查项 | 怎么看 | 正常状态 | 异常意味着 |
|---|---|---|---|
| **25MHz 时钟** | 看 `clk_25m_ref` 是否翻转 | 有规律的 0→1→0→1 跳变 | 如果始终为 0 或 1：25MHz 时钟未生成，检查 `clk_div_25m` |
| **XADC 校准完成** | 看 `startup_done` 是否为 1 | 启动 ~5ms 后变为 1 | 如果始终为 0：XADC 校准卡住，检查 DCLK |
| **DRP 握手** | 同时看 `drp_den`、`drp_drdy` | DEN 脉冲后 ~520ns 出现 DRDY 脉冲 | **如果 drp_drdy 始终为 1（卡高）：XADC 异常，检查配置和复位** |
| **settling 状态** | 看 `settling` 脉冲宽度 | 每次 DRDY 后持续 10 个 DCLK 周期 (100ns) | 如果 settling 不出现或过长：4053 状态机异常 |
| **mux_sel 翻转** | 看 `mux_sel` 是否有跳变 | 每个 DRDY 后翻转一次 | 如果一直不变：XADC 4053 状态机可能卡住了 |
| **CH1/CH2 valid** | 看 `ch1_vld_raw` 和 `ch2_vld_raw` | 与 DRDY 同时出现脉冲 | 如果没有脉冲：XADC DRP 接口可能不工作 |
| **CH1 raw 数据变化** | 看 `ch1_raw[11:0]` | 数值在 ~0x200-0x600 附近变化（接扩展板时） | 如果全是 0x000：VAUXP[2] 无输入或 DRDY 卡高导致读到空数据 |

### 6.1.1 🔑 DRDY 诊断（最重要！）

如果 ADC 数据全为零，**首先检查 `drp_drdy` 信号**：

- **正常**: `drp_drdy` 是一个窄脉冲（1个 DCLK 周期），每次 XADC 转换完成后出现。在 ILA 中应该看到稀疏的正脉冲。
- **DRDY 卡高（最常见故障）**: `drp_drdy` 始终为 1。这意味着 XADC 没有正常复位或配置错误。此时 FSM 会误认为每次都是转换完成，快速循环读取 `drp_do=0x0000`，导致 ADC 数据全为 0。
  - **解决方法**: 检查 XADC `RESET` 信号（当前由 `~rst_n` 驱动），确保复位持续时间足够（>1μs）。检查 INIT_40/41/48 配置值。
- **DRDY 始终为 0**: XADC 从未完成转换。检查 DCLK 是否运行、INIT_40 是否正确使能 sequencer 模式。

### 6.2 典型异常及排查

#### ❌ 问题 1：完全没有 valid 脉冲

```
现象：ch1_vld_raw, ch2_vld_raw 始终为 0
原因：XADC 没有开始采样
排查：
  1. 先看 startup_done (bit 54)，如果为 0 说明 XADC 校准未完成
  2. 检查 XADC 供电和 VAUXP[2]/VAUXN[2] 连接
  3. 检查 xadc_reader.v 中 INIT_40 配置 (应为 16'h1032)
  4. 确认 startup_done 信号已拉高（等待 ~5ms）
```

#### ❌ 问题 2：ADC数据全为零但 valid 脉冲正常（⚠️ 最常见！）

```
现象：ch1_vld_raw/ch2_vld_raw 脉冲正常，但 ch1_raw/ch2_raw 全是 0x000
原因：DRDY 卡高 → FSM 误判 → 快速循环读 drp_do=0x0000
排查（用新 ILA probe）：
  1. 看 drp_drdy (bit 58)：如果始终为 1 → 确认 DRDY 卡高
  2. 看 drp_den (bit 57) 和 settling (bit 56)：确认 DEN→settle→DEN 循环
     - 正常：DEN脉冲 → 等 ~52 cycles → DRDY脉冲 → settling=1(10 cycles) → 重复
     - 异常 (DRDY卡高)：DEN脉冲 → 下1拍 DRDY=1 → settling=1(10 cycles) → 重复
  3. 如果 DRDY 卡高：检查 XADC RESET (~rst_n) 是否正常
  4. 确认 XADC INIT_40 bit4 (CHSEL)=1 启用通道序列器
```

#### ❌ 问题 3：adc_ch1_raw 和 adc_ch2_raw 数据完全相同

```
现象：两个通道的 12 位数据一模一样
原因：4053 模拟开关没有切换，或 mux_sel 不工作
排查：
  1. 看 mux_sel 信号是否翻转
  2. 如果不翻转 → 检查 xadc_reader 状态机
  3. 用万用表量 H17 引脚 (mux_sel) 电压是否在 0V/3.3V 间切换
```

#### ❌ 问题 4：DRDY 脉冲正常但数据仍为零

```
现象：drp_drdy 正常脉冲，ch1_vld_raw 正常，但 ch1_raw = 0x000
原因：VAUXP[2] 模拟输入为 0V（扩展板未连接或输入开路）
排查：
  1. 确认 EGO1_Oscilloscope_Gen 扩展板已连接到 J5
  2. 用万用表量 J5 pin 9 (VAUXP2) 对地电压
     - 接扩展板且无输入：应约 0.55V (MCP6002 偏置)
     - 不接扩展板：可能浮空或拉到 0V
  3. 在 BNC 输入端接入已知信号（如 1kHz 方波）测试
```

---

## 快捷键和技巧

### Vivado ILA 快捷键

| 操作 | 快捷键 / 方法 |
|---|---|
| 单次捕捉 | 点击 ▶ (Run Trigger) |
| 立即触发 (不等待) | 点击 ⏩ (Immediate Trigger) |
| 停止 | 点击 ⏹ (Stop) |
| 导出波形数据 | File → Export → ILA Data |
| 保存 ILA 配置 | 点击 💾 Save Trigger Setup |
| 添加光标测量 | 右键波形 → Add Marker |

### 调试技巧

1. **先不用触发条件**：初次使用时，点击 ⏩ (Immediate Trigger) 直接抓一帧，先看看所有信号的状态
2. **用 mux_sel 做触发**：mux_sel 每 ~620ns 翻转一次，用它做触发可以稳定捕获每个完整的采样周期
3. **扩大深度**：如果需要更长的观察窗口，修改 `create_ila_adc.tcl` 中的 `C_DATA_DEPTH` 参数，但注意会消耗更多 BRAM
4. **配合外部信号**：在 ILA 窗口中加入 `sys_clk` 周期计数，方便精确测量时间间隔

### 估算采样窗口

```
采样窗口 = 深度 / 采样率
         = 2048 / 100MHz
         = 20.48 µs

XADC 每个采样周期 = ~620ns
20.48µs 可以捕获 ≈ 33 次 XADC 转换
```

如果要看到更完整的波形（如整个 CDC 流程），可以将深度调大：
- `C_DATA_DEPTH = 4096` → 40.96µs, ~66 次转换
- `C_DATA_DEPTH = 8192` → 81.92µs, ~132 次转换
- `C_DATA_DEPTH = 16384` → 163.84µs, ~264 次转换 (最大深度)

---

## 附录 A：文件清单

以下是为 ADC 调试创建/修改的所有文件：

| 文件 | 说明 |
|---|---|
| `ila_adc_debug.v` | ILA 封装模块，定义探针位映射 |
| `create_ila_adc.tcl` | Vivado TCL 脚本，自动生成 ILA IP 核 |
| `ila_adc.xdc` | ILA 约束文件 |
| `top.v` (修改) | 添加了 debug 同步器和 ILA 实例化 |

## 附录 B：如何移除 ILA

如果不再需要 ILA 调试功能：

1. 在 `top.v` 中删除 `// ILA Debug Probe` 到 `// --- ILA Core instantiation ---` 之间的所有代码
2. 在 Vivado 中移除 `ila_adc_debug.v` 文件
3. 在 Vivado 中移除 `ila_adc.xdc` 约束文件
4. 删除 ILA IP 核文件夹：`pocketscope_sim/pocketscope_sim.srcs/sources_1/ip/ila_adc/`
5. 重新综合、实现、生成比特流
