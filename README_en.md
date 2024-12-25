# OpenWrt DFS Checker

[中文版本](README.md)

## Introduction

This code was originally based on a Reddit post: [DFS Radar Causes 5GHz to Drop and Doesn't Come Back](https://www.reddit.com/r/openwrt/comments/rs9pit/dfs_radar_causes_5ghz_to_drop_and_it_doesnt_come/). I would like to express my gratitude to `u/_daphreak_` and `u/try_harder_later` for their initial efforts and contributions.

I have interactively modified this code using DeepSeek-R1-Lite, and the git history reflects the changes made during the process. I am highly satisfied with the capabilities of DeepSeek-R1-Lite.

## Script Description

The script `dfscheck.sh` is designed to monitor the status of wireless interfaces on OpenWrt routers, specifically handling Dynamic Frequency Selection (DFS) channels and radar detection events. When a radar signal causes the wireless interface to shut down, the script automatically switches to a fallback channel to maintain network connectivity and attempts to switch back to the original channel after a specified period.

### Functional Overview

1. **Channel Switching**: The script allows users to specify primary and fallback channels. If the primary channel is disabled due to DFS radar detection, it switches to the fallback channel to keep the network operational.

2. **Automatic Recovery**: After switching to the fallback channel for a set period (default is 30 minutes), the script attempts to switch back to the primary channel and waits for a period to perform an initial DFS scan.

3. **Monitoring and Logging**: The script continuously monitors the wireless interface's status and logs significant actions and status changes, aiding users in tracking and debugging issues.

## Usage

1. **Install the Script**: Upload `dfscheck.sh` to the `/root/` directory on your OpenWrt router.

2. **Make the Script Executable**: Use the command `chmod +x /root/dfscheck.sh` to grant execution permissions.

3. **Run the Script**: Execute the script with root privileges and provide the necessary parameters.

### Example

Assuming you have the following configuration:

* Device Number: 0 (corresponds to the 5GHz signal device `radio0`)
* Primary Channel: 149
* Fallback Channel: 1
* AP Index: 1

You can run the script with the following command:

```sh
/root/dfscheck.sh 0 149 1 1
```

### Parameters Explanation

* `device`: The wireless device number, e.g., 0 for `radio0` (5GHz device).
* `channel`: The primary DFS channel to be used.
* `fallback_channel`: The secondary channel to be used if the primary channel is disabled due to DFS detection.
* `ap_index`: The index of the AP interface (default is 1).

### Notes

* **Privilege Requirements**: The script requires root privileges to modify wireless configurations and reload wireless settings.
* **Network Impact**: Changing wireless channels may disrupt currently connected devices, forcing them to reconnect to the new channel.
* **Logging**: The script logs significant operations to the system log, which can be viewed using the `logread` command.
* **Legal Compliance**: Ensure your channel configuration complies with the laws and regulations governing wireless spectrum management in your country or region. The script is not responsible for any issues arising from non-compliance.

### Example Configuration

Below is a complete example configuration, assuming you want to monitor and manage DFS channels on `radio0` :

```sh
/root/dfscheck.sh 0 149 1 1
```

This command will monitor channel 149 on `radio0` . If channel 149 is disabled due to DFS radar detection, the script will automatically switch to channel 1 and attempt to switch back to channel 149 after 30 minutes.

By using this script, you can better manage DFS channel usage, minimize network downtime caused by radar detections, and enhance overall network stability and reliability.
