#!/bin/bash
#
# Dyname.net interactive setup for *NIX-based systems

# Functions
initialize() {
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

    # Location of files
    DYNAME_HOME="$HOME/.dyname"
    UPDATERFILE="$DYNAME_HOME/updater.sh"
    HOSTNAMEFILE="$DYNAME_HOME/hostname"
    SECRETFILE="$DYNAME_HOME/secret"
    MODEFILE="$DYNAME_HOME/operatingmode"
    CLIENTPORTFILE="$DYNAME_HOME/clientport"

    # Fetch a saved secret, or generate a random one
    if [[ -f $SECRETFILE ]]; then
        SECRET=$(cat $SECRETFILE)
    else
        SECRET=$(LC_CTYPE=C tr -dc A-Za-z0-9 < /dev/urandom | fold -w ${1:-32} | head -n 1)
        echo $SECRET > $SECRETFILE
    fi

}

first_run() {
    echo -e "**********\n\nThanks for running Dyname setup!\nLet's walk you through setting things up.\n"
}

save_settings() {
    echo $INPUT_HOSTNAME > $HOSTNAMEFILE
    echo $SECRET > $SECRETFILE
    echo $OPERATING_MODE > $MODEFILE
    echo $CLIENT_PORT > $CLIENTPORTFILE
}

load_settings() {
    INPUT_HOSTNAME=$(cat $HOSTNAMEFILE)
    SECRET=$(cat $SECRETFILE)
    OPERATING_MODE=$(cat $MODEFILE)
    CLIENT_PORT=$(cat $CLIENTPORTFILE)
}

query_hostname() {
    echo "First, we'll need the hostname you're interested in."

    # We have a guess for the hostname
    if [[ $HOSTNAME_GUESS != "" ]]; then
        echo "If our guess below is correct, just press ENTER."
        echo -n "Hostname [$HOSTNAME_GUESS]: "
        read INPUT_HOSTNAME
        if [[ $INPUT_HOSTNAME == "" ]]; then
            INPUT_HOSTNAME=$HOSTNAME_GUESS
        fi
        AVAILABILITYCHECK=$($DLCMD $DLARG $API/is_available?hostname=$INPUT_HOSTNAME&secret=$SECRET)
        while [[ $AVAILABILITYCHECK != *"true"* ]]; do
            echo "Sorry, that hostname is invalid or already taken. Please try something else, and make sure you use a valid suffix (.dyname.net or .dnm.li)"
            echo -n "Hostname: "
            read INPUT_HOSTNAME
            AVAILABILITYCHECK=$($DLCMD $DLARG $API/is_available?hostname=$INPUT_HOSTNAME&secret=$SECRET)
        done
    else
        # No guess
        echo "Please give a hostname with a valid suffix (either .dyname.net or .dnm.li)"
        while [[ $INPUT_HOSTNAME == "" ]] || [[ $AVAILABILITYCHECK != *"true"* ]]; do
            echo -n "Hostname: "
            read INPUT_HOSTNAME
            
            AVAILABILITYCHECK=$($DLCMD $DLARG $API/is_available?hostname=$INPUT_HOSTNAME&secret=$SECRET)
            if [[ $AVAILABILITYCHECK != *"true"* ]]; then
                echo "Sorry, that hostname is invalid or already taken. Please try something else, and make sure you use a valid suffix (.dyname.net or .dnm.li)"
            fi
        done
    fi
}

query_email() {
    echo -e "\nGreat! Next, we'll need your e-mail address.\nThis is for being able to reset your secret, and communication regarding the service. We won't abuse it. Promise."
    echo -n "E-mail address: "
    read INPUT_EMAIL
    INPUT_EMAIL=${INPUT_EMAIL//@/%}
}

create_dynatunnel() {
    if [[ ! -x `which ssh` ]]; then
        echo "Sorry, DynaTunnel requires ssh installed and in the PATH."
        exit 1
    fi

    # Prepare the tunnel, get SSH key and make connection
    TUNNEL_OUTPUT=$($DLCMD $DLARG https://tunnel.dyname.net/v1/tunnel?hostname=$INPUT_HOSTNAME)
    SERVER_PORT=$(echo $TUNNEL_OUTPUT | cut -d';' -f1)
    SSH_KEY_FILE="$HOME/.dyname/dynatunnel.pem"
    echo $TUNNEL_OUTPUT| cut -d';' -f2 | tr '%%' '\n' > $SSH_KEY_FILE
    chmod 600 $SSH_KEY_FILE
    ssh -i $SSH_KEY_FILE -R $SERVER_PORT:localhost:$CLIENT_PORT dyname@tunnel.dyname.net $INPUT_HOSTNAME $CLIENT_PORT
    if [[ $? -ne 0 ]]; then
        echo "Creating a tunnel failed."
    fi
    rm $SSH_KEY_FILE

    exit 0
}

query_mode() {
    echo -e "\nDyname has two operating modes:\n\n1) Traditional Dynamic DNS, where the hostname is pointed to your IP address."
    echo -e "2) DynaTunnel, which exposes a HTTP server on your local machine to your hostname, even if you are behind NAT or a firewall."
    echo -en "\nChoose operating mode [1]: "
    read OPERATING_MODE
}

map_ip() {
    UPDATER_URL="$API_PROTOCOL://$INPUT_EMAIL:$SECRET@$API_HOSTNAME/nic/update?hostname=$INPUT_HOSTNAME&myip=$FORCE_IP"

    if [[ "$DLCMD" == "wget" ]]; then
        UPDATE_CMD="$DLCMD $DLARG --auth-no-challenge --http-user=$INPUT_EMAIL --http-password=$SECRET \"$UPDATER_URL\" > /dev/null"
    else
        UPDATE_CMD="$DLCMD $DLARG \"$UPDATER_URL\" > /dev/null"
    fi

    eval $UPDATE_CMD
}

set_updater() {
    echo -e "#!/bin/bash\n# Dyname Updater\n$UPDATE_CMD\n" > $UPDATERFILE
    chmod 755 $UPDATERFILE
    CRONCONTENT=$(crontab -l 2>/dev/null)
    echo -e "$CRONCONTENT\n#-- Begin Dyname updater\n@reboot $UPDATERFILE\n*/5 * * * * $UPDATERFILE\n#-- End Dyname updater" | crontab
}

query_updater() {
    echo -e "To keep your hostname pointing to your IP address, I'd like to add the following lines to your crontab:"
    echo "#-- Begin Dyname updater"
    echo "@reboot $UPDATERFILE"
    echo "*/5 * * * * $UPDATERFILE"
    echo "#-- End Dyname updater"
    echo -en "\nI can do that automatically. Is that OK? y/n [y] "

    read CONFIRMATION
    if [[ $CONFIRMATION != "y" && $CONFIRMATION != "" ]]; then
        echo "Your crontab remains untouched. You will need to run this script again to update your IP address."
        exit 1
    else
        set_updater
    fi
}

query_clientport() {
    if [[ "$CLIENT_PORT" == "" ]]; then
        DEF_PORT=3000
    else
        DEF_PORT=$CLIENT_PORT
    fi
    echo -e "Which local port would you like to expose via $INPUT_HOSTNAME?"
    echo -n "Local port [$DEF_PORT]: "
    read INPUT_PORT
    if [[ "$INPUT_PORT" == "" ]]; then
        CLIENT_PORT=$DEF_PORT
    else
        CLIENT_PORT=$INPUT_PORT
    fi
}

# Main flow:
# 1. See if we have saved hostname, secret and operatingmode - if so, ask if we should do what we did last time (according to mode)
# 2. If not, continue
# 3. Ask for hostname, e-mail and operating mode
# 4. Save settings
# 5. Continue with operating mode

initialize

if [[ -f $HOSTNAMEFILE && -f $SECRETFILE && -f $MODEFILE ]]; then
    load_settings

    # We have saved settings
    if [[ "$UNATTENDED" == "" ]]; then
        echo -n "Would you like to repeat your last action "
        if [[ "$OPERATING_MODE" == "1" ]]; then
            echo -n "(update $INPUT_HOSTNAME with your current IP)? y/n [y] "
        elif [[ "$(cat $MODEFILE)" == "2" ]]; then
            echo -n "(point $INPUT_HOSTNAME to your local port $CLIENT_PORT)? y/n [y] "
        fi
        read CONTINUE_WITH_SAVED
    else
        CONTINUE_WITH_SAVED="y"
    fi
    if [[ "$CONTINUE_WITH_SAVED" == "" || "$CONTINUE_WITH_SAVED" == "y" || "$CONTINUE_WITH_SAVED" == "Y" ]]; then
        

        if [[ "$OPERATING_MODE" == "1" ]]; then
            map_ip
            echo "IP updated."
        else
            FORCE_IP="34.250.152.193"
            map_ip
            create_dynatunnel
        fi
        exit 0

    fi
fi

first_run
query_hostname
query_email
query_mode

if [[ "$OPERATING_MODE" == "1" || "$OPERATING_MODE" == "" ]]; then
    OPERATING_MODE=1
    map_ip
    echo -e "Great! $INPUT_HOSTNAME now points to your IP address.\n"
    save_settings
    query_updater
else
    FORCE_IP="34.250.152.193"
    map_ip
    query_clientport
    save_settings
    create_dynatunnel
fi

exit 0
