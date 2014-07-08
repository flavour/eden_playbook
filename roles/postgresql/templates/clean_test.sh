#!/bin/bash
set -e
if [[ -z "$1" ]]; then
    echo >&2 "Instance needs to be specified: prod or test or demo"
    exit 1
elif [[ ! -d "/home/$1" ]]; then
    echo >&2 "$1 is not a valid instance!"
    exit 1
fi
INSTANCE=$1
if [[ "$1" = "prod" ]]; then
    echo "You selected: Production"
    echo -n "Are you absolutely sure? (yes/n):"
    read confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"; exit
    fi
    DATABASE="sahana"
else
    DATABASE="sahana-$INSTANCE"
fi
echo >&2 "Cleaning instance: $INSTANCE"
/etc/init.d/uwsgi-$INSTANCE stop
cd /home/$INSTANCE/applications/eden
rm -rf databases/*
rm -f errors/*
rm -f sessions/*
rm -rf uploads/*
echo >&2 "Dropping database: $DATABASE"
set +e
pkill -f "postgres: sahana $DATABASE"
sudo -H -u postgres dropdb $DATABASE
set -e
echo >&2 "Creating database: $DATABASE"
su -c - postgres "createdb -O sahana -E UTF8 -l en_US.UTF-8 $DATABASE -T template0"
if [[ "$1" = "test" ]]; then
    echo >&2 "Refreshing database from Production: $DATABASE"
    su -c - postgres "pg_dump -c sahana > /tmp/sahana.sql"
    su -c - postgres "psql -f /tmp/sahana.sql $DATABASE"
    cp -pr /home/prod/applications/eden/databases/* /home/$INSTANCE/applications/eden/databases/
    cd /home/$INSTANCE/applications/eden/databases
    for i in *.table; do mv "$i" "${i/PROD_TABLE_STRING/TEST_TABLE_STRING}"; done
else
    echo >&2 "Migrating/Populating database: $DATABASE"
    #su -c - postgres "createlang plpgsql -d $DATABASE"
    su -c - postgres "psql -q -d $DATABASE -f /usr/share/postgresql/9.3/extension/{{ postgis_version.stdout }}"
    su -c - postgres "psql -q -d $DATABASE -c 'grant all on geometry_columns to sahana;'"
    su -c - postgres "psql -q -d $DATABASE -c 'grant all on spatial_ref_sys to sahana;'"
    echo >&2 "Starting DB actions with eden"
    cd /home/$INSTANCE/applications/eden
    sed -i 's/settings.base.migrate = False/settings.base.migrate = True/g' models/000_config.py
    sed -i "s/settings.base.prepopulate = 0/#settings.base.prepopulate = 0/g" models/000_config.py
    rm -rf compiled
    cd /home/$INSTANCE
    sudo -H -u web2py python web2py.py -S eden -M -R applications/eden/static/scripts/tools/noop.py
    cd /home/$INSTANCE/applications/eden
    sed -i 's/settings.base.migrate = True/settings.base.migrate = False/g' models/000_config.py
    sed -i "s/#settings.base.prepopulate = 0/settings.base.prepopulate = 0/g" models/000_config.py
fi
echo >&2 "Compiling..."
cd /home/$INSTANCE
python web2py.py -S eden -M -R applications/eden/static/scripts/tools/compile.py
/etc/init.d/uwsgi-$INSTANCE start
if [[ "$1" = "test" ]]; then
   echo >&2 "pass"
else
   cd /home/$INSTANCE
   #sudo -H -u web2py python web2py.py -S eden -M -R /home/data/import.py
fi