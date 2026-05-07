# dskill 实现原理

**作者：** 阿布 (Abu) & OCAD  
**基于：** Pill by Jon Pry (GPL v2)

---

## 1. 概述

dskill 是一个 Cadence SKILL 语言的反编译与解密工具，支持两种操作模式：

- **ILE 解密** (`dskill -ile`)：解密 Virtuoso 加密的 `.ile` 文件为可读 `.il` 源码
- **CXT 反编译** (`dskill -cxt`)：将 SKILL context 二进制文件 (`.cxt/.cdn`) 反编译为 SKILL 源码

---

## 2. ILE 解密原理

Cadence 的 `.ile` 文件使用 XOR 流密码加密：

```
加密算法: cipher[i] = plain[i] ^ key[ki] ^ state[i-1]
          state[i] = cipher[i] (反馈)
          ki = (ki - 1) mod key_len
```

解密是同一个操作：用相同的 key 和反馈机制对密文再次 XOR 即可还原明文。前 65 字节为文件头（跳过不解密）。

Key 为 128 字节的固定密钥数组，存储在 `dskill_ile.cpp` 中。

---

## 3. CXT 反编译原理

### 3.1 Context 文件格式

SKILL context (`.cxt`) 是 Virtuoso SKILL 解释器内部状态的二进制快照，类似于 Unix core dump。其目的是加速大 SKILL 文件的加载。

**文件头结构：**
```
Offset  Size   Field
0x10    8      ulong (magic)
0x18    4      uint (flags)
0x20    4      version
0x30    2      header_size
0x40    8      orig_arytab (原始数组表地址)
0x48    4      nns
0x60    4      narrays (数组数量)
0x70    4      nstrings (字符串数量)
0x78    8      orig_strtab (原始字符串表地址)
0x88    4      nuts
0x90    4      nblocks (块数量)
```

**内存块 (Block) 结构：**
文件头后跟随 nblocks 个内存块。每个块包含：
- `cell_size`: 2 bytes — 单元大小
- `cell_type`: 2 bytes — 类型 (1=FUN, 2=LIST, 3=FIXNUM, 5=SYMBOL, 8=FLONUM, 9=STRING)
- `block_size`: 2 bytes — 块大小
- `orig_addr`: 原始虚拟地址

块被映射到独立页（通过 valloc 分配 4096 字节页），使用原始地址的页号作为索引。

### 3.2 函数字节码解码

每个函数包含：
- **函数名** — 第一个指令，符号类型
- **参数列表** — 接下来的 m_args 个指令
- **函数体** — m_len - m_args 条字节码指令

**字节码指令格式（64位）：**
```
[63:16] u48 — 数据/偏移
[15:8]  u8  — 子类型
[7:0]   code — 操作码
```

操作码分为两类：
- **偶数 code** (bit 0 = 0): 加载字面量，从 `pgmap` 解析对象
- **奇数 code** (bit 0 = 1): 执行操作

**指令类型及处理逻辑：**

| Type | 含义 | 处理方式 |
|------|------|---------|
| 0x01 (1c) | 内联整数 | 直接取值 |
| 0x02 | ICall | 间接调用（@optional） |
| 0x03 (1d) | PCall/相对加载 | 计算偏移读取字面量 |
| 0x06 | 立即数 | 移位解码 48 位立即数 |
| 0x07 | Control flow | 控制流指令 (if/then/while/for 等) |
| 0x09 | One arg + literal | 单参数加字面量操作 |
| 0x0a | NCall | 原生调用 |
| 0x0d | Let/Prog | let/prog 环境 |
| 0x0f | Call | 函数调用 |
| 0x10 | PCall pred | 比较谓词 (equalsp, lt, gt 等) |
| 0x11 | AssignOp | 赋值操作 |
| 0x12 | RefKLocalVar | 引用局部变量 |
| 0x1a | LoadNil/LoadT | 加载 nil 或 t |
| 0x1f | LoadFunc | 加载函数引用 |

### 3.3 AST 构建与变换

字节码指令执行后，操作数被压入/弹出栈，最终生成表达式列表。表达式列表被组织为 SList 树（Lisp 风格的 S 表达式）。

**SList 结构：**
```cpp
class SList {
    string m_atom;           // 原子值 (符号名)
    vector<SList*> m_list;   // 子表达式列表
    bool m_forceparen;       // 强制加括号
    bool m_noparen;          // 不加括号
    // ...
};
```

输出的 S 表达式格式为：
- **命名函数**: `(procedure name(args) body...)`
- **匿名函数 (lambda)**: `(lambda (args) body...)`

**AST 变换 (Transform)：**
对原始表达式树进行后处理以生成可读的 SKILL 代码：

| 变换 | 功能 |
|------|------|
| `rename` | 重命名操作符 (e.g., setq→=, quote→') |
| `rpn` | 中缀表达式转 RPN |
| `forfactor` | for 循环重构 |
| `foreachfactor` | foreach 循环重构 |
| `condfix` | cond 表达式修复 |
| `setsgq/putpropq` | setSGq/putpropq 转 ~>/-> 语法 |
| `arrayfix` | 数组索引修复 |
| `staticfactor` | 静态列表展开 |
| `rot_back` | setvar 旋转 |
| `postfactor` | 后置操作符处理 |

### 3.4 容错机制

由于 context 文件可能包含工具未完整支持的字节码模式，dskill 实现了多层容错：

1. **指令数量限制** (50,000/函数)：防止死循环
2. **超时保护** (30s/函数)：alarm 信号超时跳过
3. **进程隔离** (fork)：每个函数在独立子进程中处理，堆破坏不影响其他函数
4. **信号捕获**：SIGSEGV/SIGABRT/SIGALRM 被捕获，跳过问题函数
5. **边界检查**：字节码偏移越界时返回 nil 占位
6. **空栈处理**：栈下溢时用 nil 占位而非崩溃

---

## 4. 关键修复（相对于 Pill 原始代码）

原始 Pill 工具在解析新版 SKILL context 文件时存在多个问题：

| 问题 | 修复 |
|------|------|
| `SList::print()` 空指针段错误 | `stack->find()` 前添加 `!stack\|\|` 守卫 |
| `rot_back()` 空指针段错误 | `parents->find()` 前添加 `!parents\|\|` 守卫 |
| assert 在未知字节码时崩溃 | 替换为 WARNING + nil 占位符 |
| 多函数间堆破坏 | fork() 进程隔离 |
| 函数名解析失败 (全为 nil) | 按序号命名 func_N.il |
| lambda 匿名函数识别 | nil→lambda 转换，输出 lambda 格式 |
| 死循环 (printins 递归) | 指令计数上限 + alarm 超时 |

---

## 5. 平台兼容性

### 当前二进制
- 操作系统: RHEL 8+ / Rocky 8+ / Ubuntu 20.04+
- GLIBC: >= 2.33
- libstdc++: >= GLIBCXX_3.4.29

### RHEL 7 部署
RHEL 7 的 GLIBC 版本为 2.17，无法直接运行预编译二进制。
需要在 RHEL 7 上使用 devtoolset 从源码编译：

```bash
# 安装 devtoolset-11 (提供 GCC 11 + C++17)
yum install devtoolset-11
scl enable devtoolset-11 bash

# 编译
cd /path/to/dskill
bash build.sh
```
