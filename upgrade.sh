#!/usr/bin/env bash

# Copyright (c) 2016, rockyluke
#
# Permission  to use,  copy, modify,  and/or  distribute this  software for  any
# purpose  with  or without  fee  is hereby  granted,  provided  that the  above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS"  AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO  THIS SOFTWARE INCLUDING  ALL IMPLIED WARRANTIES  OF MERCHANTABILITY
# AND FITNESS.  IN NO EVENT SHALL  THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR  CONSEQUENTIAL DAMAGES OR  ANY DAMAGES WHATSOEVER  RESULTING FROM
# LOSS OF USE, DATA OR PROFITS,  WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER  TORTIOUS ACTION,  ARISING  OUT OF  OR  IN CONNECTION  WITH  THE USE  OR
# PERFORMANCE OF THIS SOFTWARE.

# http://www.redmine.org/projects/redmine/wiki/RedmineUpgrade

if [ ${#} -lt 1 ]
then
    cat <<EOF
${0}: missing version
Usage: ${0} [VERSION].

eg: ${0} 3.0.3
    ${0} latest to get the latest version
EOF
exit 0
fi

if [ ! -x "$(command -v mysqldump)" ]
then
    echo -e "\\033[31mPlease install mysqldump (see README.md)\\033[39m"
    exit 1
fi

if [ ! -x "$(command -v wget)" ]
then
    echo -e "\\033[31mPlease install wget (see README.md)\\033[39m"
    exit 1
fi

if [ "${1}" == "latest" ]
then
    VERSION=$(curl -s http://www.redmine.org/releases/ | awk -F "\"" '{print $8}' | grep .zip$ | sed -r 's/.*-([0-9].[0-9].[0-9])\..*/\1/g' | tail -1)
else
    VERSION=${1}
fi

# main variables
DATE=$(date +%Y%m%d-%Hh%M)
# default values
REDMINE_PATH='/srv/redmine'
REDMINE_USER='www-data'
REDMINE_GROUP='www-data'
REDMINE_DB='redmine'
RAILS_ENV='production'

if [ -f /etc/redmine.upgrade ]
then
    . /etc/redmine.upgrade
fi

echo -ne "\\033[39m-- check folders in ${REDMINE_PATH}"
# redmine folders
if [ ! -d ${REDMINE_PATH} ]
then
    mkdir -p ${REDMINE_PATH}
else
    cd ${REDMINE_PATH} || exit 1
    # backup folder
    echo -n ' (backup, '
    if [ ! -d ${REDMINE_PATH}/backup ]
    then
	mkdir -p ${REDMINE_PATH}/backup
    fi
    # shared folders (read README.md)
    echo -n 'shared, '
    if [ ! -d ${REDMINE_PATH}/shared ]
    then
	mkdir -p ${REDMINE_PATH}/shared
    else
	# files folder
	echo -n 'files, '
	if [ ! -d ${REDMINE_PATH}/shared/files ]
	then
	    mkdir -p ${REDMINE_PATH}/shared/files
	    chown -R ${REDMINE_USER}:${REDMINE_GROUP} ${REDMINE_PATH}/shared/files
	fi
	# plugins folder
	echo -n 'plugins, '
	if [ ! -d ${REDMINE_PATH}/shared/plugins ]
	then
	    mkdir -p ${REDMINE_PATH}/shared/plugins
	fi
	# themes folder
	echo -n 'themes)'
	if [ ! -d ${REDMINE_PATH}/shared/themes ]
	then
	    mkdir -p ${REDMINE_PATH}/shared/themes
	fi
    fi
fi
echo -e "\\033[32m OK"

# backup
echo -ne "\\033[39m-- backup database in ${REDMINE_PATH}/backup/database-${DATE}.sql"
mysqldump ${REDMINE_DB} > "${REDMINE_PATH}/backup/database-${DATE}.sql"
if [ ${?} -ne 0 ]
then
    echo -e "\\033[31m KO: error with mysqldump"
    exit 1
else
    echo -e "\\033[32m OK"
fi

# download
echo -ne "\\033[39m-- download redmine version ${VERSION} (redmine-${VERSION}.tar.gz) in /usr/src"
wget -q -O "/usr/src/redmine-${VERSION}.tar.gz http://www.redmine.org/releases/redmine-${VERSION}.tar.gz"
if [ ${?} -ne 0 ]
then
    echo -e "\\033[31m KO: error with wget"
    exit 1
else
    echo -e "\\033[32m OK"
fi

# extract
echo -ne "\\033[39m-- extract redmine version ${VERSION} (redmine-${VERSION}.tar.gz) from /usr/src in ${REDMINE_PATH}"
tar -C ${REDMINE_PATH} -xzf "/usr/src/redmine-${VERSION}.tar.gz"
if [ $? -ne 0 ]
then
    echo -e "\\033[31m KO: error with tar"
    exit 1
else
    echo -e "\\033[32m OK"
fi

# chown / chmod
echo -ne "\\033[39m-- chown & chmod in ${REDMINE_PATH}"
find "${REDMINE_PATH}/redmine-${VERSION}" -type d -exec chmod 755 {} \;
find "${REDMINE_PATH}/redmine-${VERSION}" -type f -exec chmod 644 {} \;
echo -n " (redmine-${VERSION}, "
chown -R root:root "${REDMINE_PATH}/redmine-${VERSION}"
echo -n 'files, '
chown -R "${REDMINE_USER}:${REDMINE_GROUP}" "${REDMINE_PATH}/shared/files"
echo -n 'log, '
chown -R "${REDMINE_USER}:${REDMINE_GROUP}" "${REDMINE_PATH}/redmine-${VERSION}/log"
echo -n 'tmp, '
chown -R "${REDMINE_USER}:${REDMINE_GROUP}" "${REDMINE_PATH}/redmine-${VERSION}/tmp"
echo -n 'plugin_assets)'
chown -R "${REDMINE_USER}:${REDMINE_GROUP}" "${REDMINE_PATH}/redmine-${VERSION}/public/plugin_assets"
echo -e "\\033[32m OK"

# symlink current
echo -ne "\\033[39m-- create current symlink in ${REDMINE_PATH} (redmine-${VERSION})"
cd ${REDMINE_PATH} || exit 1
if [ -h ${REDMINE_PATH}/current ]
then
    rm ${REDMINE_PATH}/current
    ln -s "redmine-${VERSION}" current
elif [ -d ${REDMINE_PATH}/current ] || [ -f ${REDMINE_PATH}/current ]
then
    echo -e "\\033[31m KO: current is a folder or file"
    exit 1
else
    ln -s "redmine-${VERSION}" current
fi
cd "${REDMINE_PATH}/current" || exit 1
echo -e "\\033[32m OK"

# symlink configuration
echo -ne "\\033[39m-- create configuration symlink in ${REDMINE_PATH}/config (redmine-${VERSION})"
ln -s /etc/redmine/configuration.yml ${REDMINE_PATH}/current/config/configuration.yml
ln -s /etc/redmine/database.yml      ${REDMINE_PATH}/current/config/database.yml
echo -e "\\033[32m OK"

# symlink files
echo -ne "\\033[39m-- create files symlink in ${REDMINE_PATH}/current (redmine-${VERSION})"
cd ${REDMINE_PATH}/current || exit 1
if [ -d ${REDMINE_PATH}/current/files ]
then
    rm -rf ${REDMINE_PATH}/current/files
fi
ln -s ../shared/files ${REDMINE_PATH}/current/files
if [ ${?} -ne 0 ]
then
    echo -e "\\033[31m KO: error with tar"
    exit 1
else
    echo -e "\\033[32m OK"
fi

# symlink themes
echo -ne "\\033[39m-- create themes symlink in ${REDMINE_PATH}/current/public/themes (redmine-${VERSION})"
###
### TODO
###
echo -e "\\033[32m OK"

# symlink plugins
echo -ne "\\033[39m-- create plugins symlink in ${REDMINE_PATH}/current/plugins (redmine-${VERSION})"
###
### TODO
###
echo -e "\\033[32m OK"

# bundle install
echo -ne "\\033[39m-- bundle install in ${REDMINE_PATH}/current (redmine-${VERSION})"
cd ${REDMINE_PATH}/current || exit 1
env RAILS_ENV=${RAILS_ENV} bundle install --no-color --without development test > /dev/null
if [ $? -ne 0 ]
then
    echo -e "\\033[31m KO"
    exit 1
else
    echo -e "\\033[32m OK"
fi

# rake generate_secret_token
echo -ne "\\033[39m-- rake generate_secret_token in ${REDMINE_PATH}/current (redmine-${VERSION})"
cd ${REDMINE_PATH}/current || exit 1
env RAILS_ENV=${RAILS_ENV} bundle exec rake generate_secret_token
if [ $? -ne 0 ]
then
    echo -e "\\033[31m KO"
    exit 1
else
    echo -e "\\033[32m OK"
fi

# rake db:migrate
echo -ne "\\033[39m-- rake db:migrate in ${REDMINE_PATH}/current (redmine-${VERSION})"
cd ${REDMINE_PATH}/current || exit 1
env RAILS_ENV=${RAILS_ENV} bundle exec rake db:migrate
if [ $? -ne 0 ]
then
    echo -e "\\033[31m KO"
    exit 1
else
    echo -e "\\033[32m OK"
fi

# rake redmine:plugins:migrate
echo -ne "\\033[39m-- rake redmine:plugins:migrate in ${REDMINE_PATH}/current (redmine-${VERSION})"
cd ${REDMINE_PATH}/current || exit 1
env RAILS_ENV=${RAILS_ENV} bundle exec rake redmine:plugins:migrate
if [ $? -ne 0 ]
then
    echo -e "\\033[31m KO"
    exit 1
else
    echo -e "\\033[32m OK"
fi

# rake tmp:cache:clear
echo -ne "\\033[39m-- rake tmp:cache:clear tmp:sessions:clear in ${REDMINE_PATH}/current (redmine-${VERSION})"
cd ${REDMINE_PATH}/current || exit 1
env RAILS_ENV=${RAILS_ENV} bundle exec rake tmp:cache:clear tmp:sessions:clear
if [ $? -ne 0 ]
then
    echo -e "\\033[31m KO"
    exit 1
else
    echo -e "\\033[32m OK"
fi

# reset color and print final message
echo -ne "\\033[39m"
cat <<EOF

################################################################################
#
#	Redmine upgrade to version ${VERSION} finished \o/
#
#	Now you need to reload your http daemon.
#
#	service apache2 reload or service nginx reload
#
#
################################################################################
EOF
# EOF
