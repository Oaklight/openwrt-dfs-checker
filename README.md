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

## 设置开机自动运行脚本

通过Cron任务设置脚本在路由器重启时自动运行。

### 配置步骤

1. **编辑Cron任务**
   

```sh
   crontab -e
   ```

2. **添加任务**
   在Cron文件中添加：
   

```sh
   @reboot /root/dfscheck.sh 0 128 149 1 > /root/dfs-check/dfscheck.log 2>&1 &
   ```

3. **创建日志目录**
   

```sh
   mkdir -p /root/dfs-check/
   chmod 755 /root/dfs-check/
   ```

4. **设置日志轮转**
   创建配置文件 `/etc/logrotate.d/dfs-check` ：
   

```sh
   /root/dfs-check/dfscheck.log {
       missingok
       rotate 3
       size 1M
       create 644 root root
       postrotate
           /bin/kill -HUP $(cat /var/run/syslogd.pid 2>/dev/null) 2>/dev/null || true
       endscript
   }
   ```

5. **测试自动运行**
   重启路由器：
   

```sh
   reboot
   ```

   检查日志：
   

```sh
   cat /root/dfs-check/dfscheck.log
   ```

通过上述配置，脚本将在路由器重启后自动运行，并记录日志以供管理。
