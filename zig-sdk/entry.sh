#!/bin/bash

# Modify UID_MIN and UID_MAX to include the desired UID
sed -i 's/^UID_MIN.*/UID_MIN 500/' /etc/login.defs
sed -i 's/^UID_MAX.*/UID_MAX 60000/' /etc/login.defs

# create a user with the same USID
useradd -u $USID -o -m builder
# also add the user to the same GUSID
usermod -a -G $GUSID builder

# and execute the args passed to the entrypoint
# as the builder user
su builder -c "$*"
