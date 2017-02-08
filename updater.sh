#!/bin/bash
#
# Dyname.net updater for *NIX-based systems

# Our API location
API_PROTOCOL="https"
API_HOSTNAME="api.dyname.net"
API_VERSION="v1"
API="$API_PROTOCOL://$API_HOSTNAME/$API_VERSION"

# We'll need either curl or wget to rock.
# The former is generally available on OS X, latter on Linux
if [[ -x `which curl` ]]; then
    DLCMD="curl"
    DLARG="-s"
elif [[ -x `which wget` ]]; then
    DLCMD="wget"
    DLARG="-qO-"
else
    echo "Sorry, this script requires either curl or wget installed and in PATH."
    exit 1
fi

# Make sure our config directory exists
mkdir -p $HOME/.dyname/

# Query our API for the external IP of this box
IP=$($DLCMD $DLARG $API/ip)

# And make an educated guess about the hostname we're about to register
HOSTNAME_GUESS=$($DLCMD $DLARG $API/get_last_availabilitycheck)

# Fetch a saved secret, or generate a random one
if [[ -f $HOME/.dyname/secret ]]; then
    SECRET=$(cat $HOME/.dyname/secret)
else
    SECRET=$(LC_CTYPE=C tr -dc A-Za-z0-9 < /dev/urandom | fold -w ${1:-32} | head -n 1)
    echo $SECRET > $HOME/.dyname/secret
fi

# Location of an updater script, should the user choose to want one
UPDATERFILE="$HOME/.dyname/updater.sh"

echo -e "**********\n\nThanks for running the Dyname Updater!\nLet me walk you through setting things up.\n"
echo "First, I'll need the hostname you're interested in."

# We have a guess for the hostname
if [[ $HOSTNAME_GUESS != "" ]]; then
    echo "If my guess below is correct, just press ENTER."
    echo -n "Hostname [$HOSTNAME_GUESS]: "
    read INPUT_HOSTNAME
    if [[ $INPUT_HOSTNAME == "" ]]; then
        INPUT_HOSTNAME=$HOSTNAME_GUESS
    fi
    AVAILABILITYCHECK=$($DLCMD $DLARG $API/is_available?hostname=$INPUT_HOSTNAME)
    while [[ $AVAILABILITYCHECK != *"true"* ]]; do
        echo "Sorry, that hostname is invalid or already taken. Please try something else, and make sure you use a valid suffix (.dyname.net or .dnm.li)"
        echo -n "Hostname: "
        read INPUT_HOSTNAME
        AVAILABILITYCHECK=$($DLCMD $DLARG $API/is_available?hostname=$INPUT_HOSTNAME)
    done
else
    # No guess
    echo "Please give a hostname with a valid suffix (either .dyname.net or .dnm.li)"
    while [[ $INPUT_HOSTNAME == "" ]] || [[ $AVAILABILITYCHECK != *"true"* ]]; do
        echo -n "Hostname: "
        read INPUT_HOSTNAME
        
        AVAILABILITYCHECK=$($DLCMD $DLARG $API/is_available?hostname=$INPUT_HOSTNAME)
        if [[ $AVAILABILITYCHECK != *"true"* ]]; then
            echo "Sorry, that hostname is invalid or already taken. Please try something else, and make sure you use a valid suffix (.dyname.net or .dnm.li)"
        fi
    done
fi

echo -e "\nGreat! Next, I'll need your e-mail address.\nThis is for being able to reset your secret, and communication regarding the service. I won't abuse it. Promise."
echo -n "E-mail address: "
read INPUT_EMAIL
INPUT_EMAIL=${INPUT_EMAIL//@/%}


UPDATER_URL="$API_PROTOCOL://$INPUT_EMAIL:$SECRET@$API_HOSTNAME/nic/update?hostname=$INPUT_HOSTNAME"

if [[ "$DLCMD" == "wget" ]]; then
    UPDATE_CMD="$DLCMD $DLARG --auth-no-challenge --http-user=$INPUT_EMAIL --http-password=$SECRET \"$UPDATER_URL\" > /dev/null"
else
    UPDATE_CMD="$DLCMD $DLARG \"$UPDATER_URL\" > /dev/null"
fi

eval $UPDATE_CMD

echo -e "\nThanks! You're all set: $INPUT_HOSTNAME now points to $IP.\nI've stored a script to update your IP in $UPDATERFILE\n"
echo -e "To keep your hostname pointing to your IP address, I'd like to store a script in $UPDATERFILE, and add the following lines to your crontab:"
echo "#-- Begin Dyname updater"
echo "@reboot $UPDATERFILE"
echo "*/5 * * * * $UPDATERFILE"
echo "#-- End Dyname updater"
echo -en "\nIs that OK? y/n [y] "

read CONFIRMATION
if [[ $CONFIRMATION != "y" && $CONFIRMATION != "" ]]; then
    echo "Your crontab remains untouched. You will need to run this script again to update your IP address."
    exit 1
else
    echo -e "#!/bin/bash\n# Dyname Updater\n$UPDATE_CMD\n" > $UPDATERFILE
    chmod 755 $UPDATERFILE
    CRONCONTENT=$(crontab -l 2>/dev/null)
    echo -e "$CRONCONTENT\n#-- Begin Dyname updater\n@reboot $UPDATERFILE\n*/5 * * * * $UPDATERFILE\n#-- End Dyname updater" | crontab
fi
