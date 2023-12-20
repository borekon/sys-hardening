#!/bin/bash
#
# Execute this script as sudo
# Note that this some steps requires human actions

# install lynins
# https://github.com/CISOfy/lynis.git

# Check if we have the correct system in this case Ubuntu 22.04 Jammy

DISTRIBUTION_ID="Ubuntu"
DISTRIBUTION_CODENAME="jammy"
DISTRIBUTION_RELEASE=22.04

_dist_id=$(lsb_release -is)
_dist_codename=$(lsb_release -cs)
_dist_release=$(lsb_release -rs)

if [ "$_dist_id" = $DISTRIBUTION_ID ] && 
   [ "$_dist_codename" = $DISTRIBUTION_CODENAME ] &&
   [ $_dist_release = $DISTRIBUTION_RELEASE ]; then
	echo "$_dist_id $_dist_release ($_dist_codename) [OK]" 
else
	echo "This script has been made to run against $_dist_id $_dist_release ($_dist_codename) distro" 
	if [ "$_dist_id" = $DISTRIBUTION_ID ]; then
	       echo "Still an $_dist_id system, so maybe some parts of this script could be valid"
       	       echo "We do not recomend to run it, unless you know what are you doing and reviewng carefuly the whole content and steps."	       
	fi
	echo "Exiting now"
	exit 1
fi

# CONFIGURATION SECTION

SSH_PORT=22122
SSH_FOLDER=/etc/ssh/
SSH_CONFIG_FILE=sshd_config
MODPROBE_CONFIG_FILE=/etc/modprobe.d/blacklist.conf
LOGING_CONFIG_FILE=/etc/login.defs
ISSUE_FILE=/etc/issue
ISSUE_FILE_NET=/etc/issue.net
ISSUE_FILE_PROFILE=/etc/profile
MODPROBE_PROTOCOL_CONF=/etc/modprobe.d/CIS.conf
LIMITS_CONF=/etc/security/limits.conf
SYSCTL_CONF=/etc/sysctl.conf
USB_STORAGE_CONF=/etc/modprobe.d/usb_storage.conf
GRUB_CONFIG_FILE=/etc/grub.d/10_linux

# do the update/upgrade for the system
apt update
apt upgrade -y


# Disabling all ports but ssh on custom port
if [ ! -f /usr/bin/$_tool ]; then
        apt install -y ufw
fi
ufw allow $SSH_PORT/tcp
ufw enable

# sshd configuration
mv ${SSH_FOLDER}${SSH_CONFIG_FILE} ${SSH_FOLDER}${SSH_CONFIG_FILE}_back
cp ${SSH_CONFIG_FILE}_hardened ${SSH_FOLDER}${SSH_CONFIG_FILE}
echo "Port $SSH_PORT" >> ${SSH_FOLDER}${SSH_CONFIG_FILE}
echo "sshd service listen port changed to ${SSH_PORT}"
echo "use port option to connect since now: ssh -p ${SSH_PORT} $(whoami)@$(hostname -I)"
read -p "press ENTER key to continue..." smthng
wall "New ssh port ${SSH_PORT}"
systemctl restart sshd

# file permissions
chmod 400 /boot/grub/grub.cfg
chmod 700 /etc/cron.monthly/
chmod 700 /etc/cron.daily/
chmod 700 /etc/cron.d
chmod 700 /etc/cron.hourly/
chmod 700 /etc/cron.weekly/
chmod 600 /etc/ssh/sshd_config
chmod 600 /etc/crontab

# Disable useless protocols
echo "install dccp /bin/true"     >> $MODPROBE_PROTOCOL_CONF
echo "install sctp /bin/true"     >> $MODPROBE_PROTOCOL_CONF
echo "install rds  /bin/true"     >> $MODPROBE_PROTOCOL_CONF
echo "install tipc /bin/true"     >> $MODPROBE_PROTOCOL_CONF
echo "install freevxfs /bin/true" >> $MODPROBE_PROTOCOL_CONF
echo "install hfs /bin/true"      >> $MODPROBE_PROTOCOL_CONF
echo "install cramfs /bin/true"   >> $MODPROBE_PROTOCOL_CONF
echo "install jffs2 /bin/true"    >> $MODPROBE_PROTOCOL_CONF
echo "install hfsplus /bin/true"  >> $MODPROBE_PROTOCOL_CONF
echo "install udf /bin/true"      >> $MODPROBE_PROTOCOL_CONF

## core dumps
echo "* hard core 0" >> $LIMITS_CONF
echo "* soft core 0" >> $LIMITS_CONF

echo "fs.suid_dumpable=0" 	       >> $SYSCTL_CONF
echo "kernel.core_pattern=|/bin/false" >> $SYSCTL_CONF
sysctl -p $SYSCTL_CONF

#Message disclaimer
NOTICE_HEADER="################ NOTICE ################"
MESSAGE_DISCLAIMER="WARNING: Unauthorized access to this system is forbidden and will being prosecuted by law. By accessing this system, you agree that your actions prosecuted by law. By accessing this system, you agree that your actions"
printf "$NOTICE_HEADER\n$MESSAGE_DISCLAIMER" > $ISSUE_FILE
cat $ISSUE_FILE > $ISSUE_FILE_NET
printf "\necho \"$NOTICE_HEADER\"\necho \"$MESSAGE_DISCLAIMER\"" >> $ISSUE_FILE_PROFILE

#Change UMASK
if grep --quiet "UMASK.*022" /etc/login.defs; then
	sed -i 's/022/027/g' /etc/login.defs
fi

if ! grep --quiet "umask 027" $ISSUE_FILE_PROFILE; then
	echo "umask 027" >> $ISSUE_FILE_PROFILE
fi

if ! grep --quiet "umask 027" /etc/bash.bashrc; then
	echo "umask 027" >> /etc/bash.bashrc
fi

# Removing compilers
for _compiler in gcc cc clang g++ gcc; do
	if [ -f /usr/bin/$_compiler ]; then
		apt purge -y $_compiler
	fi
done

# Uninstall tools
for _tool in wget nmap telnet curl netcat-openbsd; do
	if [ -f /usr/bin/$_tool ]; then
		apt purge -y $_tool
	fi
done

sudo apt autoremove -y

# Disable media
chmod 000 /media

# Disable USB Storge
echo -e "install usb-storage /bin/true" > $USB_STORAGE_CONF

for _i in /sys/bus/usb/devices/usb*/authorized; do 
	echo 0 > $_i;
done

for _i in /sys/bus/usb/devices/usb*/authorized_default; do 
	echo 0 > $_i;
done

# Set disable IPv6
cat /etc/*rele* | grep Ubuntu | grep 22.04 && sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="ipv6.disable=1"/g' /etc/default/grub

# Set grub password
if ! grep --quiet "unrestricted" /etc/grub.d/*; then 
	sed -i 's/CLASS="--class gnu-linux --class gnu --class os"/CLASS="--class gnu-linux --class gnu --class os --unrestricted"/g' $GRUB_CONFIG_FILE
fi

echo "Going to configure grub password"
read -p "Enter grub user name: " GRUB_USR_NAME
echo "Going to set the hashed grub password"
echo "You'll need to copy paste later"

grub-mkpasswd-pbkdf2

read -p "Enter grub hash password, copy and paste: " GRUB_PASSWORD

echo 'cat <<EOF' >> $GRUB_CONFIG_FILE
echo "set superusers=\""${GRUB_USR_NAME}"\"" >> $GRUB_CONFIG_FILE
echo "password_pbkdf2 ${GRUB_USR_NAME} ${GRUB_PASSWORD}" >> $GRUB_CONFIG_FILE
echo 'EOF' >> $GRUB_CONFIG_FILE

update-grub

# deal with passwords policy 
echo "SHA_CRYPT_MIN_ROUNDS 10000" >> $LOGING_CONFIG_FILE 
echo "SHA_CRYPT_MAX_ROUNDS 15000" >> $LOGING_CONFIG_FILE

# TODO: This is not working as expected
# TODO: recheck this section
apt install -y libpam-pwquality
sed -i 's/PASS_MAX_DAYS/#PASS_MAX_DAYS/g' /etc/login.defs 
sed -i 's/PASS_MIN_DAYS/#PASS_MIN_DAYS/g' /etc/login.defs 
printf "PASS_MAX_DAYS 2 \nPASS_MIN_DAYS 1" >> /etc/login.defs
echo 'TMOUT=900' >> /etc/profile

cp -f ./common-auth /etc/pam.d/common-auth
chown root:root /etc/pam.d/common-auth
chmod 644 /etc/pam.d/common-auth

cp -f ./common-password /etc/pam.d/common-password
chown root:root /etc/pam.d/common-password
chmod 644 /etc/pam.d/common-password

# install and setting tools
apt install -y rkhunter aide auditd debsums acct ntp sysstat apt-show-versions
aideinit
rkhunter -c
cp /etc/pam.d/common-password /root/

# sysstat config
sed -i 's/ENABLED="false"/ENABLED="true"/g' /etc/default/sysstat
systemctl enable sysstat
systemctl start sysstat

# process accounting config
touch /var/log/pacct
accton /var/log/pacct

# Audit 
auditctl -w /etc/passwd -p rwxa
auditctl -w /etc/security -p rwxa
auditctl -a always,exit -S chmod
auditctl -l >> /etc/audit/rules.d/additional.rules 

