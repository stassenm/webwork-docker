#!/bin/bash
set -eo pipefail

function wait_for_db {
	echo "Waiting for database to become available..."
	while ! timeout 1 bash -c "(cat < /dev/null > /dev/tcp/$WEBWORK_DB_HOST/$WEBWORK_DB_PORT) >/dev/null 2>&1"
	do
		echo "waiting..."
		sleep 0.5;
	done
}

# Build extra locales if requested.
if [ "$ADD_LOCALES" != "0" ]; then
	echo "Rebuilding locales - adding: $ADD_LOCALES"
	cp -a /etc/locale.gen /etc/locale.gen.orig
	/bin/echo -e "en_US ISO-8859-1\nen_US.UTF-8 UTF-8\n$ADD_LOCALES" > /etc/locale.gen.tmp
	/usr/bin/tr "," "\n" < /etc/locale.gen.tmp > /etc/locale.gen
	rm /etc/locale.gen.orig
	/usr/sbin/locale-gen
fi

# Set system timezone if not the default UTC
if [ "$SYSTEM_TIMEZONE" != "UTC" ]; then
	echo "Setting system timezone to $SYSTEM_TIMEZONE"
	rm /etc/localtime
	rm /etc/timezone
	echo "$SYSTEM_TIMEZONE" > /etc/timezone
	dpkg-reconfigure -f noninteractive tzdata
fi

# Modify default papersize based on environment variable PAPERSIZE
echo "Setting libpaper1 papersize to $PAPERSIZE"
echo "libpaper1 libpaper/defaultpaper select $PAPERSIZE\nlibpaper1:amd64 libpaper/defaultpaper select $PAPERSIZE\ndebconf debconf/frontend select Noninteractive" > /tmp/preseed.txt
debconf-set-selections /tmp/preseed.txt
dpkg-reconfigure -f noninteractive libpaper1

# Install some extra packages
if [ "$ADD_APT_PACKAGES" != "0" ]; then
	apt-get update
	apt-get install -y --no-install-recommends --no-install-suggests $ADD_APT_PACKAGES
fi

# generate conf files if not exist
for i in site.conf localOverrides.conf; do
	if [ ! -f $WEBWORK_ROOT/conf/$i ]; then
		echo "Creating a new $WEBWORK_ROOT/conf/$i"
		cp $WEBWORK_ROOT/conf/$i.dist $WEBWORK_ROOT/conf/$i
		if [ $i == 'site.conf' ]; then
			sed -i -e 's/webwork_url       = '\''\/webwork2'\''/webwork_url       = $ENV{"WEBWORK_URL"}/' \
				-e 's/server_root_url   = '\'''\''/server_root_url   = $ENV{"WEBWORK_ROOT_URL"}/' \
				-e 's/^\$database_driver="MariaDB"/$database_driver = $ENV{"WEBWORK_DB_DRIVER"}/' \
				-e 's/^\$database_host="localhost"/$database_host = $ENV{"WEBWORK_DB_HOST"}/' \
				-e 's/^\$database_port="3306"/$database_port = $ENV{"WEBWORK_DB_PORT"}/' \
				-e 's/^\$database_name="webwork"/$database_name = $ENV{"WEBWORK_DB_NAME"}/' \
				-e 's/^\$database_username ="webworkWrite"/$database_username =$ENV{"WEBWORK_DB_USER"}/' \
				-e 's/^\$database_password ='\''passwordRW'\''/$database_password =$ENV{"WEBWORK_DB_PASSWORD"}/' \
				-e 's/mail{smtpServer} = '\'''\''/mail{smtpServer} = $ENV{"WEBWORK_SMTP_SERVER"}/' \
				-e 's/siteDefaults{timezone} = "America\/New_York"/siteDefaults{timezone} = $ENV{"WEBWORK_TIMEZONE"}/' \
				-e 's/^# $server_userID     = '\''www-data/$server_userID     = '\''www-data/'  \
				-e 's/^# $server_groupID    = '\''www-data/$server_groupID    = '\''www-data/' $WEBWORK_ROOT/conf/site.conf

			echo "$WEBWORK_ROOT/conf/$i has been modified."
		fi

		if [ $i == 'localOverrides.conf' ]; then
			sed -i -e 's/#$pg{specialPGEnvironmentVars}{Rserve} = {host => "r"};/$pg{specialPGEnvironmentVars}{Rserve} = {host => "r"};/' \
				-e 's/#$problemLibrary{showLibraryLocalStats} = 0;/$problemLibrary{showLibraryLocalStats} = 0;/' $WEBWORK_ROOT/conf/localOverrides.conf
							echo "$WEBWORK_ROOT/conf/$i has been modified."
		fi
	fi
done

# Create the admin course if it does not exist.
# Check first if the admin courses directory exists then check that the admin_user table exists.
#
# The check for the database tables for the admin course is neccessary for the
# following situation. In rebuilding a docker box one might clear out the docker
# containers, images and volumes including mariaDB, BUT leave the contents of the
# courses directory in place.  It now holds the shell of the courses
# including the admin course directory. This means that once you rebuild the box
# you can't access the admin course (because the admin_user table is missing)
# and you need to run bin/upgrade_admin_db.pl from inside the container.  This
# check ensures that if the admin_user table is missing the whole admin course
# is rebuilt even if the admin directory is in place.
echo "check admin course and admin tables"
wait_for_db
ADMIN_TABLE_EXISTS=`mysql -u $WEBWORK_DB_USER  -p$WEBWORK_DB_PASSWORD -B -N -h $WEBWORK_DB_HOST -e "select count(*) from information_schema.tables where table_schema='webwork' and table_name = 'admin_user';"`
if [ ! -d "$APP_ROOT/courses/admin" ]; then
	newgrp www-data
	umask 2
	cd $APP_ROOT/courses
	wait_for_db
	$WEBWORK_ROOT/bin/addcourse admin --db-layout=sql_single --users=$WEBWORK_ROOT/courses.dist/adminClasslist.lst --professors=admin
	chown www-data:www-data -R $APP_ROOT/courses
	echo "Admin course is created."
	echo "user: admin password: admin added to course admin and tables upgraded"
elif [ $ADMIN_TABLE_EXISTS == 0 ]; then
	echo "admin course db tables need updating"
	$WEBWORK_ROOT/bin/upgrade_admin_db.pl
	$WEBWORK_ROOT/bin/wwsh admin $WEBWORK_ROOT/bin/addadmin
	echo "admin course tables created with one user: admin   whose password is admin"
else
	echo "using pre-existing admin course and admin tables"
fi

# Create modelCourses if it doesn't exist.
if [ ! -d "$APP_ROOT/courses/modelCourse" ]; then
	echo "create modelCourse subdirectory"
	rm -rf $APP_ROOT/courses/modelCourse
	cd $WEBWORK_ROOT/courses.dist
	cp -R modelCourse $APP_ROOT/courses/
fi

# Create the htdocs/tmp directory if it does not exist
if [ ! -d "$WEBWORK_ROOT/htdocs/tmp" ]; then
	echo "Creating htdocs/tmp directory"
	mkdir $WEBWORK_ROOT/htdocs/tmp
	chown www-data:www-data -R $WEBWORK_ROOT/htdocs/tmp
	echo "htdocs/tmp directory created"
fi

# Copy defaultClasslist.lst and adminClasslist.lst into $APP_ROOT/courses if
# either file does not exist.
if [ ! -f "$APP_ROOT/courses/defaultClasslist.lst"  ]; then
	echo "defaultClasslist.lst is being created"
	cd $WEBWORK_ROOT/courses.dist
	cp *.lst $APP_ROOT/courses/
fi
if [ ! -f "$APP_ROOT/courses/adminClasslist.lst"  ]; then
	echo "adminClasslist.lst is being created"
	cd $WEBWORK_ROOT/courses.dist
	cp *.lst $APP_ROOT/courses/
fi

# Update the OPL tables, if requested
if [ -f "$APP_ROOT/libraries/Restore_or_build_OPL_tables" ]; then
	if [ -f "$APP_ROOT/libraries/webwork-open-problem-library/TABLE-DUMP/OPL-tables.sql" ]; then
		echo "Restoring OPL tables from the TABLE-DUMP/OPL-tables.sql file"
		wait_for_db
		$WEBWORK_ROOT/bin/restore-OPL-tables.pl
		$WEBWORK_ROOT/bin/load-OPL-global-statistics.pl
		#$WEBWORK_ROOT/bin/update-OPL-statistics.pl
		if [ ! -f "$WEBWORK_ROOT/htdocs/DATA/tagging-taxonomy.json" ]; then
			echo "You are missing some of the JSON files, including"
			echo "tagging-taxonomy.json, from $WEBWORK_ROOT/htdocs/DATA/"
			echo "Some of the library functions will not work properly"
		fi
	else
		echo "Could not find the OPL-tables.sql file in "
		echo "$APP_ROOT/libraries/webwork-open-problem-library/TABLE-DUMP/"
		echo "OPL tables not restored"
	fi
	rm $APP_ROOT/libraries/Restore_or_build_OPL_tables
fi

# Fix possible permission issues
echo "Fixing ownership and permissions (just in case it is needed)"
cd $WEBWORK_ROOT

# Minimal chown/chmod code for the critical directories.
chown -R www-data:www-data logs tmp DATA
chmod -R ug+w logs tmp DATA
chown  www-data:www-data htdocs/tmp
chmod ug+w htdocs/tmp

# Even if the admin and courses directories already existed, their permissions
# might not be correct.
chown www-data:www-data  $APP_ROOT/courses
chown www-data:www-data  $APP_ROOT/courses/admin
chown www-data:www-data  $APP_ROOT/courses/admin/*

echo "End fixing ownership and permissions"

# Start the Minion job queue.
echo "Starting Minion job queue"
sudo -E -u www-data bin/webwork2 minion worker -m production &

# The code below allows you to use
#    docker container exec -it webwork2_app_1 hypnotoad -s bin/webwork2
# to restart the webwork2 Mojolicious app in the container in a "nice" way.

trap "exit 0" SIGWINCH

while true
do
	exec "$@" &
	wait $!
done
