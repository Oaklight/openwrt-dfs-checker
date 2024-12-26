# OpenWrt DFS Checker

[English version](README_en.md)

## 介绍

本代码最初来源于Reddit上的一个回答：[DFS雷达导致5GHz频段断联且不会恢复](https://www.reddit.com/r/openwrt/comments/rs9pit/dfs_radar_causes_5ghz_to_drop_and_it_doesnt_come/)。在此特别感谢 `u/_daphreak_` 和 `u/try_harder_later` 的初步尝试和贡献。

我对代码进行了交互性修改，使用了DeepSeek-R1-Lite，git历史记录了整个修改过程。DeepSeek-R1-Lite的表现让我非常满意。

## 脚本说明

这个脚本名为 `dfscheck.sh` ，专门用于在OpenWrt路由器上监控无线接口状态，特别是针对动态频率选择（DFS）通道的雷达检测事件。当检测到雷达信号导致无线接口关闭时，脚本会自动切换到备用通道，并在一段时间后尝试恢复到原来的通道。

### 功能概述

1. **通道切换**：脚本允许用户指定主通道和备用通道。如果主通道由于DFS雷达检测而被禁用，脚本会自动切换到备用通道，以保持网络连接。

2. **自动恢复**：在切换到备用通道一段时间（默认30分钟）后，脚本会尝试切换回主通道，并等待一段时间以进行初始的DFS扫描。

3. **监控与日志**：脚本持续监控无线接口的状态，并在日志中记录状态变化和操作，便于用户跟踪和调试。

### 使用方法

1. **安装脚本**：将 `dfscheck.sh` 上传到OpenWrt路由器的 `/root/` 目录下。

2. **赋予执行权限**：使用命令 `chmod +x /root/dfscheck.sh` 赋予脚本执行权限。

3. **运行脚本**：以root权限运行脚本，并提供必要的参数。

#### 示例

假设你有以下配置：

* 设备编号：0（对应你的5GHz信号设备 `radio0`）
* 主通道：149
* 备用通道：1
* AP索引：1

你可以使用以下命令运行脚本：

```sh
/root/dfscheck.sh 0 149 1 1
```

### 参数说明

* `device`：无线设备的编号，例如0对应 `radio0`（5GHz设备）。
* `channel`：要使用的主DFS通道。
* `fallback_channel`：当主通道被禁用时要切换到的备用通道。
* `ap_index`：AP接口的索引，默认为1。

### 注意事项

* **权限要求**：脚本需要以root权限运行，以修改无线配置并重新加载无线设置。
* **网络影响**：修改无线通道可能会影响当前连接的设备，导致它们需要重新连接到新的通道。
* **日志记录**：脚本会记录重要操作到系统日志，可以使用 `logread` 命令查看相关日志。
* **法律合规**：请确保你的通道配置符合所在国家或地区关于无线电频段管理的法律法规。本脚本不承担任何因违规使用而引发的问题或法律责任。

### 示例配置

以下是一个完整的示例配置，假设你要监控并管理 `radio0` 上的DFS通道：

```sh
/root/dfscheck.sh 0 149 1 1
```

这个命令会在 `radio0` 上监控通道149，如果由于DFS雷达检测导致通道149被禁用，脚本会自动切换到通道1，并在30分钟后尝试切换回通道149。

通过使用这个脚本，你可以更好地管理DFS通道的使用，减少因雷达检测导致的网络中断时间，从而提高网络的稳定性和可靠性。

---

## 设置Cron Job以在重启时运行脚本

为了确保脚本在每次路由器重启时自动运行，可以将其添加到cron任务中。以下是具体步骤：

### 1. 编辑Cron任务

使用以下命令编辑cron任务：

```sh
crontab -e
```

### 2. 添加Cron Job

在cron配置文件中添加以下行：

```sh
@reboot /usr/bin/nohup /root/dfscheck.sh 0 149 1 1 > /var/log/dfs-check/dfscheck.log 2>&1 &
```

#### 参数说明：

* `@reboot`：表示在每次系统重启时运行该任务。
* `/usr/bin/nohup`：确保脚本在后台运行，即使终端关闭也不会中断。
* `> /var/log/dfs-check/dfscheck.log 2>&1`：将脚本的输出和错误日志保存到 `/var/log/dfs-check/dfscheck.log`。
* `&`：将脚本放到后台运行。

### 3. 创建日志目录

确保日志目录存在并具有适当的权限：

```sh
mkdir -p /var/log/dfs-check/
chmod 755 /var/log/dfs-check/
```

### 4. 设置日志轮转

为了管理日志文件的大小和历史，可以使用 `logrotate` 进行日志轮转。以下是配置步骤：

1. 创建logrotate配置文件：

   

```sh
   touch /etc/logrotate.d/dfs-check
   ```

2. 编辑 `/etc/logrotate.d/dfs-check` 文件，添加以下内容：

   

```sh
   /var/log/dfs-check/dfscheck.log {
       missingok
       rotate 3
       size 1M
       create 644 root root
       postrotate
           /bin/kill -HUP $(cat /var/run/syslogd.pid 2>/dev/null) 2>/dev/null || true
       endscript
   }
   ```

#### 参数说明：

* `missingok`：如果日志文件不存在，忽略错误。
* `rotate 3`：保留3个旧的日志文件。
* `size 1M`：当日志文件达到1MB时进行轮转。
* `create 644 root root`：创建新的日志文件并设置权限。
* `postrotate`：在轮转后重新加载syslog服务（可选）。

### 5. 测试Cron Job

重启路由器并检查脚本是否正常运行：

```sh
reboot
```

查看日志文件以确认脚本已启动：

```sh
cat /var/log/dfs-check/dfscheck.log
```

---

通过以上步骤，你可以确保 `dfscheck.sh` 脚本在每次路由器重启时自动运行，并通过日志轮转管理日志文件。这将进一步提高脚本的可用性和可维护性。
