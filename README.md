# enhance-ols-config-persistence
A robust script to apply overrides to OpenLiteSpeed's config and persist them on Enhance panel.

**Use this script at your own risk**
**Test in a development environment first.**

### How does it work?
- Uses both real-time file monitoring (inotify) and a fallback cron job to monitor 2 files, the OLS config, and a custom overrides.txt file.
- Delays are 10 secs for the real-time monitoring, 3 mins for the cron job, and then a graceful OLS reload.
- Adds your current overrides in OLS config at both the start and the end to ensure it overrides first-wins and last-wins directives (I'm not really sure how the parser reads the config file, so I went this way; you can adjust it).
- Automatic backups to your OLS config before applying changes.
- log file.
- Retention for both logs and backups.
- Adds a service to ensure the persistence works flawlessly after reboots.

### Installation
Run:
`sudo bash -c 'cd /root && rm -f ols-config-persistence-install.sh && curl -o ols-config-persistence-install.sh -fL https://cdn.jsdelivr.net/gh/abdeenoz/enhance-ols-config-persistence@main/ols-config-persistence-install.sh && bash ols-config-persistence-install.sh'`

After completing installation, add your custom overrides:
`nano /root/ols_custom_config.txt`
Save, you are done!

### Uninstallation
`bash /root/ols-config-persistence-install.sh uninstall`
