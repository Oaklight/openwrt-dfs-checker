# OpenWrt DFS Checker

[中文版](README.md)

## Introduction

This code was originally based on a Reddit post: [DFS Radar Causes 5GHz to Drop and Doesn't Come Back](https://www.reddit.com/r/openwrt/comments/rs9pit/dfs_radar_causes_5ghz_to_drop_and_it_doesnt_come/). I would like to express my gratitude to `u/_daphreak_` and `u/try_harder_later` for their initial efforts and contributions.

I have interactively modified this code using DeepSeek-R1-Lite, and the git history reflects the changes made during the process. I am highly satisfied with the capabilities of DeepSeek-R1-Lite.

## Script Description

The script `dfscheck.sh` is designed to monitor the status of wireless interfaces on OpenWrt routers, specifically handling Dynamic Frequency Selection (DFS) channels and radar detection events. When a radar signal causes the wireless interface to shut down, the script automatically switches to a fallback channel to maintain network connectivity and attempts to switch back to the original channel after a specified period.

### Functional Overview

1. **Channel Switching**: Automatically switches to a fallback channel when the primary DFS channel is disabled due to radar detection, ensuring network connectivity.
2. **Automatic Recovery**: After switching to the fallback channel, the script attempts to revert to the primary channel after a default period of 30 minutes.
3. **Monitoring and Logging**: Continuously monitors the wireless interface status and logs significant events for debugging purposes.

### Usage

1. **Upload the Script**: Place `dfscheck.sh` in the `/root/` directory.
2. **Grant Execution Permissions**: Run `chmod +x /root/dfscheck.sh`.
3. **Run the Script**: Execute the script with root privileges and provide the necessary parameters.

#### Example Command

Assuming the following configuration:
* Device Number: 0 (corresponds to `radio0`)
* Primary Channel: 128
* Fallback Channel: 149
* AP Index: 1 (corresponds to `ap1`, yes, you should have maybe another hidden SSID for this checker to run)

Run the command:

```sh
/root/dfscheck.sh 0 128 149 1
```

### Parameter Explanation

* `device`: Wireless device number (e.g., 0 for `radio0`).
* `channel`: Primary DFS channel.
* `fallback_channel`: Fallback channel.
* `ap_index`: AP interface index, default is 1, if not provided it falls back to 0.

### Notes

* **Privilege Requirements**: The script must be run with root privileges.
* **Network Disruption**: Channel switching may cause temporary network disconnection.
* **Logging**: Logs can be viewed using `logread`.
* **Legal Compliance**: Ensure channel configuration complies with local wireless spectrum regulations. Users are responsible for any consequences arising from non-compliance.

## Setting Up the Script as a Service

To ensure the script runs automatically at startup, create a service in OpenWrt.

### Why Use a Service Instead of Cron?

The cron method was attempted but resulted in parsing errors, preventing the script from running automatically. Using a service ensures the script starts at boot without relying on cron, providing a more reliable solution.

### Steps:

1. **Use the Service Script from the Repository**

   The repository includes the service script [ `dfscheck` ](./dfscheck). Copy this file to the `/etc/init.d/` directory:

   

```sh
   cp ./dfscheck /etc/init.d/dfscheck
   ```

2. **Make the Script Executable**

   Run the following command to ensure the service script is executable:

   

```sh
   chmod +x /etc/init.d/dfscheck
   ```

3. **Enable the Service**

   Run the following command to ensure the service starts automatically at boot:

   

```sh
   /etc/init.d/dfscheck enable
   ```

4. **Start the Service (Without Rebooting)**

   To start the service immediately without rebooting the device, run:

   

```sh
   /etc/init.d/dfscheck start
   ```

5. **Check the Service Status**

   To verify that the service is running, use the following command:

   

```sh
   /etc/init.d/dfscheck status
   ```

6. **Reboot the Device (Optional)**

   If you want to verify that the service starts automatically after a reboot, run:

   

```sh
   reboot
   ```

By following these steps, the script will automatically run upon router reboot, with logs maintained for management and debugging.
