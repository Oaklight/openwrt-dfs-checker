# OpenWrt DFS Checker

[中文版](README.md)

## Introduction

This code was originally based on a Reddit post: [DFS Radar Causes 5GHz to Drop and Doesn't Come Back](https://www.reddit.com/r/openwrt/comments/rs9pit/dfs_radar_causes_5ghz_to_drop_and_it_doesnt_come/). I would like to express my gratitude to `u/_daphreak_` and `u/try_harder_later` for their initial efforts and contributions.

I have interactively modified this code using **DeepSeek-V3** together with **DeepSeek-R1-Lite**, and the git history reflects the changes made during the process. I am highly satisfied with the capabilities of both **DeepSeek-V3** and **DeepSeek-R1-Lite**, which have significantly streamlined the development and optimization of this script.

## Script Description

The script `dfscheck.sh` is designed to monitor the status of wireless interfaces on OpenWrt routers, specifically handling Dynamic Frequency Selection (DFS) channels and radar detection events. When a radar signal causes the wireless interface to shut down, the script automatically switches to a fallback channel to maintain network connectivity and attempts to switch back to the original channel after a specified period.

### Functional Overview

1. **Channel Switching**: Automatically switches to a fallback channel when the primary DFS channel is disabled due to radar detection, ensuring network connectivity.
2. **Automatic Recovery**: After switching to the fallback channel, the script attempts to revert to the primary channel after a default period of 30 minutes.
3. **Monitoring and Logging**: Continuously monitors the wireless interface status and logs significant events for debugging purposes.
4. **5G Radio and Interface Detection**: Automatically identifies the 5G radio and its interfaces, eliminating the need for manual configuration.
5. **Configurable Backoff Strategy**: Supports `fixed`,    `linear`, and `exponential` backoff strategies for retries after connectivity failures. The default backoff strategy is `fixed`.

### Usage

1. **Upload the Script**: Place `dfscheck.sh` in the `/root/` directory.
2. **Grant Execution Permissions**: Run `chmod +x /root/dfscheck.sh`.
3. **Run the Script**: Execute the script with root privileges and provide the necessary parameters.

#### Example Command

Assuming the following configuration:
* Primary Channel: 108
* Fallback Channel: 149
* Backoff Type: fixed (default)

Run the command:

```sh
/root/dfscheck.sh 108 149 fixed
```

### Parameter Explanation

* `channel`: Primary DFS channel (e.g., 108).
* `fallback_channel`: Fallback channel (e.g., 149).
* `backoff_type`: (Optional) Type of backoff strategy (`fixed`,    `linear`, or `exp`). Default is `fixed`.

### Notes

* **Privilege Requirements**: The script must be run with root privileges.
* **Network Disruption**: Channel switching may cause temporary network disconnection.
* **Logging**: Logs can be viewed using `logread`. Note that the "connection is okay" message is printed to the console and not logged, to prevent log clogs.
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

### Default Values in the Service File

The service file now includes default values for the primary channel ( `108` ), fallback channel ( `149` ), and backoff type ( `fixed` ). These values can be customized by modifying the service file or passing arguments when starting the script manually.

---

### Key Updates:

1. **Default Backoff Strategy**: The default backoff strategy is now `fixed`, which uses a constant backoff time of 15 seconds.
2. **Console Output for "Connection is Okay"**: The "connection is okay" message is now printed to the console instead of being logged.
3. **DeepSeek Tools**: The script was interactively modified using **DeepSeek-V3** together with **DeepSeek-R1-Lite**, which significantly improved the development process and script functionality.
4. **Simplified CLI**: The script now requires only three arguments (`channel`, `fallback_channel`, and `backoff_type`), as it automatically identifies the 5G radio and its interfaces.
5. **Default Values**: The service file includes default values for the primary channel, fallback channel, and backoff type.
6. **Improved Documentation**: The README now reflects the latest changes, including the new CLI interface, service file updates, and the use of **DeepSeek-V3** and **DeepSeek-R1-Lite**.

This update ensures the documentation is aligned with the latest script and service file changes, making it easier for users to understand and use the tool.
