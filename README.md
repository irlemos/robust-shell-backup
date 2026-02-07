🌐 Available in: [English](README.md) | [Português BR](README.pt-br.md)

# Robust Shell Backup

A comprehensive and reliable backup system, written in Bash, designed to automate the backup of multiple websites (files and databases) to an AWS S3 bucket.

This project was created to solve the need for an automated, robust, and low-impact backup solution for web servers hosting multiple sites. Many existing solutions are complex, expensive, or consume valuable resources like disk space, which is a critical factor in shared hosting environments or smaller cloud servers.

## Table of Contents

-   [The Project: Vision and Purpose](#the-project-vision-and-purpose)
-   [Key Features](#key-features)
-   [Requirements](#requirements)
-   [Step-by-Step Installation and Configuration Guide](#step-by-step-installation-and-configuration-guide)
    -   [Step 0: Configure AWS Credentials](#step-0-configure-aws-credentials)
    -   [Step 1: Clone the Repository and Set Permissions](#step-1-clone-the-repository-and-set-permissions)
    -   [Step 2: Configure Email Sending (SSMTP)](#step-2-configure-email-sending-ssmtp)
    -   [Step 3: Customize the Configuration File](#step-3-customize-the-configuration-file)
    -   [Step 4: Schedule Automation with Cron](#step-4-schedule-automation-with-cron)
-   [Restoration Assistant](#restoration-assistant)
-   [File Breakdown](#file-breakdown)
-   [Manual Usage and Testing](#manual-usage-and-testing)
-   [How to Contribute](#how-to-contribute)
-   [About the Author](#about-the-author)
-   [License](#license)

---

## The Project: Vision and Purpose

This project was born out of the need for an automated, robust, and low-impact backup solution for web servers hosting multiple sites.

**Robust Shell Backup** is designed to be:

-   **Reliable:** It uses techniques like a two-pass `rsync` to ensure files are copied consistently, even if they are being modified during the process.
-   **Efficient:** It sends compressed backups directly to AWS S3 via *streaming*, eliminating the need to store bulky temporary files on the server's local disk.
-   **Customizable:** Through a centralized and easy-to-understand configuration file, the system can be adapted to various hosting scenarios, managing multiple sites, databases, and specific exclusion rules.
-   **Extensible:** Although currently focused on MySQL databases, the script's architecture is designed to be modular.

Its purpose is to provide system administrators and developers with a "set it and forget it" tool that offers peace of mind, knowing their critical website data is secure, consistent, and stored off-site.

---

## Key Features

-   **Consistent Snapshots**: Creates a local snapshot of files using a two-pass `rsync`, minimizing inconsistencies from files that change during the backup.
-   **Direct Streaming to S3**: Compresses and sends backups via a stream (`|`) to AWS, saving disk space and speeding up the process.
-   **Centralized Management**: Configure all sites, databases, and exclusions in a single `.conf` file.
-   **MySQL Database Backup**: Performs dumps and compression of MySQL databases.
-   **Restoration Assistant**: Includes an interactive script to restore files and databases from S3, with automatic `wp-config.php` updates for WordPress sites.
-   **Automated Cleanup**: Removes old backups from S3 based on a configurable retention period.
-   **Idempotent Execution**: Checks if the day's backup already exists and skips execution to avoid redundant work.
-   **Atomic Operations per Site**: If a backup step fails, partial files for that day are removed from S3 to maintain integrity.
-   **Email Error Alerts**: Sends detailed notifications in case of failure, using `ssmtp` to ensure delivery through an external SMTP.
-   **Detailed Logging**: Each execution is recorded in a timestamped log file for easy auditing.

---

## Requirements

For the script to work correctly, your server must have the following tools installed:

-   `aws-cli`: The AWS Command Line Interface.
-   `rsync`: A utility for file synchronization.
-   `mysqldump` & `mysql`: Tools for database operations.
-   `ssmtp`: A simple mail client to relay emails via an external SMTP.
-   `sed`: Used for updating configuration files during restoration.

---

## Step-by-Step Installation and Configuration Guide

### Step 0: Configure AWS Credentials

First and foremost, the script needs permission to access your S3 bucket. The most secure way to do this is to configure AWS credentials for the user that will run the script.

```sh
aws configure
```
Follow the prompts to enter your `AWS Access Key ID`, `AWS Secret Access Key`, `Default region name`, and `Default output format`.

### Step 1: Clone the Repository and Set Permissions

First, get the files and make the scripts executable.

```sh
# Clone this repository to your server
git clone https://github.com/irlemos/robust-shell-backup.git

# Navigate to the project directory
cd robust-shell-backup

# Grant execution permission to the scripts
chmod +x backup_sites.sh restore_site.sh
```

### Step 2: Configure Email Sending (SSMTP)

For error alerts to work, you need to configure `ssmtp` to use an external mail server (like Gmail, SendGrid, etc.).

Edit the `/etc/ssmtp/ssmtp.conf` configuration file with your email provider's information.

### Step 3: Customize the Configuration File

This is the heart of the system. Open the `backup_sites.conf` file and adjust all the variables for your environment.

### Step 4: Schedule Automation with Cron

Finally, schedule the script to run automatically.

1.  Open the `cron` editor for the user that should run the backup:
    ```sh
    crontab -e
    ```

2.  Add the following line to the end of the file to run the backup every day at 3 AM:
    ```crontab
    0 3 * * * cd /full/path/to/robust-shell-backup/ && ./backup_sites.sh >/dev/null 2>&1
    ```
    **Remember to replace `/full/path/to/robust-shell-backup/` with the actual path where you cloned the project.**

---

## Restoration Assistant

This project includes a `restore_site.sh` to help you recover data easily and interactively.

**How to use:**
```sh
./restore_site.sh
```

**What it does:**
1.  **Site Selection**: Lists configured sites and lets you choose one.
2.  **Date Selection**: Fetches available backups from S3 and presents a date list.
3.  **File Restoration**: Downloads and extracts files to a specific local directory you provide.
4.  **Database Restoration**: Prompts for credentials of an **existing** database, validates the connection, downloads the dump, and imports it.
5.  **WordPress Auto-Config**: If `wp-config.php` is found in the restored files, the script automatically updates `DB_NAME`, `DB_USER`, and `DB_PASSWORD` to match the credentials provided during the restore process.

---

## File Breakdown

### The Configuration File: `backup_sites.conf`

This file centralizes all the script's settings.

| Variable             | Description                                                                       | Example                           |
| :------------------- | :-------------------------------------------------------------------------------- | :-------------------------------- |
| `LOG_DIR`            | The directory where log files will be stored.                                     | `"$SCRIPT_DIR/log"`               |
| `LOG_RETENTION_DAYS` | How many days log files should be kept.                                           | `30`                              |
| `BACKUP_DIR`         | Temporary folder for creating local snapshots with `rsync`.                       | `"/home/user/backups_temp"`       |
| `AWS_S3_BUCKET`      | **Only** the name of your S3 bucket. Do not include `s3://` or subfolders.          | `"my-backup-bucket"`              |
| `AWS_S3_PREFIX`      | The subfolder (prefix) within the bucket where backups will be stored. Can be left empty. | `"server-1-backups"`              |
| `RETENTION_DAYS`     | How many days backups should be kept in S3.                                       | `7`                               |
| `EMAIL_ALERTS_ENABLED`| Enables (`true`) or disables (`false`) sending error emails.                      | `true`                            |
| `EMAIL_TO`           | The recipient's email address for alerts.                                         | `"admin@mydomain.com"`            |
| `EMAIL_FROM`         | The email address that will appear as the sender.                                 | `"backup-bot@mydomain.com"`       |
| `EMAIL_SUBJECT`      | The subject of the alert email. Can include commands like `date`.                 | `"ALERT: Backup Error - $(date)"` |

**Configuration Arrays:**

-   **`SITES`**: An associative array that defines each site.
    -   **Key**: The site's name, which will also be used as the folder name in S3.
    -   **Value**: A space-separated string with parameters: `/path/to/files database_name database_user 'database_password'`.
    -   *If a site has no database, omit the last three pieces of information.*
    ```bash
    SITES["mysite.com"]="/var/www/mysite my_db_prod my_db_user 'strongPassword'"
    SITES["othersite.com"]="/var/www/mysite/othersite other_db_prod other_db_user 'strongPassword'"
    SITES["blog.mysite.com"]="/var/www/blog" # No database
    ```

-   **`EXCLUDE_SITES`**: An associative array to exclude subfolders from the file backup.
    -   **Key**: The site name (must match a key in `SITES`).
    -   **Value**: A space-separated string of folder names to be excluded.
    ```bash
    # Excludes the cache folder and temporary uploads
    EXCLUDE_SITES["mysite.com"]="/wp-content/cache /tmp/uploads /othersite"
    EXCLUDE_SITES["othersite.com"]="/wp-content/cache"
    ```

### The Main Script: `backup_sites.sh`

The script follows a logical and robust flow for each configured site:

1.  **Loading and Validation**: The script loads `backup_sites.conf` and validates that critical variables have been set.
2.  **Main Loop**: It iterates over each site defined in the `SITES` array.
3.  **Check for Existing Backup**: Before starting, it checks S3 to see if a complete backup (files and, if applicable, database) for the current date already exists. If so, it skips to the next site.
4.  **`rsync` Snapshot Creation**:
    -   Creates a temporary directory for the site's snapshot.
    -   Runs `rsync` a first time to copy the bulk of the data.
    -   Runs `rsync` a second time. This pass is very fast and syncs only the files that changed during the first pass, ensuring a highly consistent state.
5.  **File Backup**: The script uses `tar` to compress the contents of the snapshot directory (which is now static) and pipes the output directly (`|`) to the `aws s3 cp` command, which uploads the stream to S3.
6.  **Database Backup**: If a database is configured, `mysqldump` exports the database, `gzip` compresses it, and the result is streamed (`|`) to S3.
7.  **Failure Handling and Cleanup**:
    -   A `site_backup_failed` flag tracks the success of each step.
    -   If any command (`rsync`, `tar`, `mysqldump`, `aws`) fails, the flag is set.
    -   The local snapshot is always removed to free up space.
    -   If the failure flag is set, the script sends an email alert and actively removes any partial files that may have been uploaded to S3 for that site on that day.
8.  **Old Backup Cleanup**: If the day's backup was successful, the script calls a function that lists and removes backups from S3 older than `RETENTION_DAYS`.

---

## Manual Usage and Testing

To test your configuration or run a backup outside of the scheduled time, you can call the script directly.

-   **To run and see real-time output:**
    ```sh
    # Navigate to the project directory
    cd /full/path/to/robust-shell-backup/
    
    # Execute the script
    ./backup_sites.sh
    ```
    This will print all logs to your terminal.

-   **To simulate the cron job (silent execution):**
    ```sh
    cd /full/path/to/robust-shell-backup/ && ./backup_sites.sh >/dev/null 2>&1
    ```
    After running, check the results in the `log/` folder and in your S3 bucket.

---

## How to Contribute

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1.  Fork the Project
2.  Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the Branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request

---

## About the Author

Developed by [Rodrigo Lemos](https://linkedin.com/in/irlemos)

**Extensive experience in software development, integrations, and complex solutions**  
With vast experience in multiple programming languages, platforms, and scalable projects.

---

## License

Distributed under the MIT License. See `LICENSE` for more information.
