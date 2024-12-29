# OpenWrt DFS Checker

[English version](README_en.md)

## 介绍

本代码来源于Reddit的回答：[DFS雷达导致5GHz频段断联且不会恢复](https://www.reddit.com/r/openwrt/comments/rs9pit/dfs_radar_causes_5ghz_to_drop_and_it_doesnt_come/)。感谢 `u/_daphreak_` 和 `u/try_harder_later` 的初步贡献。

代码经过交互性优化，使用了DeepSeek-R1-Lite，并记录了修改历史。DeepSeek-R1-Lite的表现令人满意。

## 脚本说明

`dfscheck.sh` 用于在OpenWrt路由器上监控无线接口状态，特别是DFS通道的雷达检测事件。当雷达信号禁用无线接口时，脚本会自动切换至备用通道，并尝试在指定时间后恢复主通道。

### 功能概述

1. **通道切换**：在主通道因DFS检测被禁用时自动切换至备用通道，保持网络连接。
2. **自动恢复**：切换到备用通道后，脚本会在默认30分钟后尝试恢复主通道。
3. **监控与日志**：实时监控无线状态并记录日志，便于调试。

### 使用方法

1. **上传脚本**：将 `dfscheck.sh` 上传至 `/root/` 目录。
2. **赋予权限**：运行 `chmod +x /root/dfscheck.sh`。
3. **运行脚本**：以root权限运行并指定参数。

#### 示例命令

假设配置如下：
* 设备编号：0（对应 `radio0`）
* 主通道：128
* 备用通道：149
* AP索引：1（对应 `ap1`，你需要为这个检查器添加另外隐藏的WiFi端点，用于DFS检测）

运行命令：

```sh
/root/dfscheck.sh 0 128 149 1
```

### 参数说明

* `device`：无线设备编号（如0表示 `radio0`）。
* `channel`：主DFS通道。
* `fallback_channel`：备用通道。
* `ap_index`：AP接口索引，默认值为1，如果不存在，则回落至0。

### 注意事项

* **权限**：需以root权限运行。
* **网络中断**：切换通道可能导致设备短暂断开连接。
* **日志**：日志记录可通过 `logread` 查看。
* **法律合规**：请确保通道配置符合当地无线频段管理法规。因违规导致的后果由用户自行承担。

## 设置脚本为开机服务

为了确保脚本在路由器启动时自动运行，可以通过创建服务的方式来实现。

### 为什么使用服务而不是Cron？

最初尝试了使用Cron来设置脚本开机自启，但由于未知原因，Cron无法正确解析 `@reboot` 指令，导致脚本无法自动运行。使用服务的方式可以避免Cron的解析问题，提供更可靠的解决方案。

### 设置步骤：

1. **使用仓库中的服务脚本**

   仓库中已包含服务脚本 [ `dfscheck` ](./dfscheck) 。将该文件复制到 `/etc/init.d/` 目录：

   

```sh
   cp ./dfscheck /etc/init.d/dfscheck
   ```

2. **赋予脚本可执行权限**

   运行以下命令，确保服务脚本可执行：

   

```sh
   chmod +x /etc/init.d/dfscheck
   ```

3. **启用服务**

   运行以下命令，确保服务在开机时自动启动：

   

```sh
   /etc/init.d/dfscheck enable
   ```

4. **启动服务（无需重启设备）**

   如果需要立即启动服务，可以运行以下命令：

   

```sh
   /etc/init.d/dfscheck start
   ```

5. **检查服务状态**

   运行以下命令，检查服务是否正常运行：

   

```sh
   /etc/init.d/dfscheck status
   ```

6. **重启设备（可选）**

   如果需要通过重启验证服务是否生效，可以运行以下命令：

   

```sh
   reboot
   ```

通过上述配置，脚本将在路由器重启后自动运行，并记录日志以供管理。
