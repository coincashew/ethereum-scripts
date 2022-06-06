#!/bin/bash
##########################################
# User Configuration - Change as desired
##########################################
NETWORK=ropsten                     # network i.e. ropsten | mainnet | kiln
SECRETS_PATH=/secrets               # location of jwtsecret file
SUGGESTED_FEE_RECIPIENT=""          # ETH address to recieve TXN fees
SSH_PORT=22                         # port used by SSH

EL_NAME=besu                        # name of systemd service
EL_DATABASE_PATH=/var/lib/besu      # location of execution layer database
EL_MAXPEERS=10                      # number of peers - lower to save bandwidth, increase for better connectivity
EL_P2PPORT=30303                    # p2p traffic port
EL_service_account_name=besu        # EL service account name

CL_NAME=lodestar-consensus                    # name of systemd service
CL_DATABASE_PATH=/var/lib/lodestar/consensus  # location of consensus layer database
CL_MAXPEERS=50                                # number of peers - lower to save bandwidth, increase for better connectivity
CL_P2PPORT=9000                               # p2p traffic port
CL_service_account_name=lsconsensus           # ConsensusLayer service account name
CL_QUICKSYNC_BEACONNODE_URL=""                # Quick Sync your Beacon Node with Infura.io or a trusted node | 1. Create an Infura eth2/beacon project. 2) Replace the <project-id> and <project-secret> and <network> | example: CL_QUICKSYNC_BEACONNODE_URL="https://<project-id>:<project-secret>@eth2-beacon-<network>.infura.io"

VC_NAME=lodestar-validator                    # name of systemd service
VC_DATABASE_PATH=/var/lib/lodestar/validators # location of validator client database
VC_service_account_name=lsvalidator           # Validator service account name
VC_GRAFFITI=coincashew_bestar                 # When validator makes a block, add an optional, graffiti message
VC_IMPORT_KEYSTORES_PATH=/tmp/keystore        # When importing validator keys, copy your keystore files here

CC_CHECK_FOR_SCRIPT_UPDATES=Y        # Check if there is an updated version of this script to download
CHECK_INTERNET_SPEED=Y               # Check if internet connection has sufficient up/download speeds
USE_GRAFANA_METRICS=Y                # For dashboard reporting, installs Grafana, prometheus and ethereum metrics exporter
USE_CHRONY=Y                         # A must for staking nodes, Chrony is a time synchornization app
INSTALL_QUICK=N                      # Quickly installs base Ethereum node with defaults, no validator

######################################
# Do NOT modify code below           #
######################################

# Automated ETH Node Install Script
# :: Besu EL & Lodestar CL ::
# by coincashew.eth [ https://coincashew.com ]
#
# Tools for Ethereum Nodes and Staking for the Home Node Operator
#
# Install quickly and conveniently with this command (from your Ubuntu Linux machine):
# curl -sSL https://raw.githubusercontent.com/coincashew/ethereum-scripts/main/eth-node-besu-lodestar.sh | bash
#
#  [✓] Tested working on Ubuntu 20.04.4 LTS
#  [✓] Tested working on Ubuntu 21.10
#  [✗] Tested as NOT working with Ubuntu 22.04 due to nodejs issues
#
# Improvements, issues, pull-requests and feedback greatly welcome at:
# https://github.com/coincashew/ethereum-scripts/
#
# donations: coincashew.eth
# gitcoin grant: https://gitcoin.co/grants/1653/ethereum-staking-guides-by-coincashew-with-poap
#
# Thanks for your support, home stakers and all.
#

CC_VERSION=0.7.9
CC_BRANCH="main"
CC_REPO="https://github.com/coincashew/ethereum-scripts"
CC_REPO_RAW="https://raw.githubusercontent.com/coincashew/ethereum-scripts"
CC_URL_RAW="${CC_REPO_RAW}/${CC_BRANCH}"


UPDATE_NODE=N
DELETE_NODE=N
CONFIG_FIREWALL=N

usage() {
  cat <<EOF >&2

Automatically installs the most diverse Ethereum node :: Merge Ready
version $CC_VERSION by coincashew.eth
=====================================================================
bestar :: most diverse client :: ${EL_NAME} EL and ${CL_NAME} CL
=====================================================================

USAGE:
	$(basename "$0") [-u] [-w] [-n <ropsten|mainnet|kiln> ] [-d] [-c] [-g] [-x] [-s] [-o] [-a] [-k] [-v] [-i] [-t] [-q] [-z] [-r]

FLAGS:
	-u          Upgrade node to the latest EL and CL versions
	-n          Connect to specified network (Default: ropsten)
	-w          Configures firewall and fail2ban
	-d          Uninstall the node
	-g          Gets node status
	-x          Stops node
	-s          Starts node
	-c          Shows node commands
	-o          Describes overview of Ethereum node and validator
	-a          Show about and credits
	-k          Show info about generating validator key(s)
	-v          Install validator client
	-i          Import validator key(s)
	-t          Perform internet speed test
	-q          Quickly installs a basic Ethereum node. No validator.
	-z          Show advanced options help - voluntary exit
	-r          Show reporting setup instructions - Grafana Dashboards
EOF
  exit 1
}

get_sudo(){
	if [[ $EUID != 0 ]]; then
	sudo -p "Install script requires admin/sudo password to continue, please enter: " date 2>/dev/null 1>&2
        if [ ! $? = 0 ]; then
            echo "Invalid password. Install aborted."
            exit 1
        fi
fi
}

get_options(){
	while getopts :ovtauiwdkrgzqxscn: opt; do
		case ${opt} in
			o     ) show_overview ;;
			v     ) install_validator; exit 0 ;;
			i     ) import_validatorkeys; exit 0 ;;
			u     ) UPDATE_NODE='Y' ;;
			w     ) CONFIG_FIREWALL='Y' ;;
			d     ) DELETE_NODE='Y' ;;
			q     ) INSTALL_QUICK='Y' ;;
			n     ) NETWORK=${OPTARG} ;;
			g     ) get_status ;;
			x     ) stop_node ;;
			s     ) start_node ;;
			c     ) show_commands ;;
			a     ) show_about ;;
			k     ) generate_validatorkeys ;;
			t     ) check_internetspeed; exit 0;;
			z     ) show_advanced ;;
			r	  ) show_reporting ;;
			\? | *    ) usage ;;
		esac
	done
	shift $((OPTIND -1))
}

get_answer() {
  printf "%s (yes/no): " "$*" >&2; read -r answer
  while :
  do
    case $answer in
    [Yy]*)
      return 0;;
    [Nn]*)
      return 1;;
    *) printf "%s" "Please enter 'yes' or 'no' to continue: " >&2; read -r answer
    esac
  done
}

set_os() {
    #!/bin/bash
    # Check for FreeBSD in the uname output
    # If it's not FreeBSD, then we move on!
    if [ "$(uname -s)" = 'FreeBSD' ]; then
        OS='freebsd'
    # Check for a redhat-release file and see if we can
    # tell which Red Hat variant it is
    elif [ -f "/etc/redhat-release" ]; then
        RHV=$(egrep -o 'Fedora|CentOS|Red\ Hat|Red.Hat' /etc/redhat-release)
        case $RHV in
        Fedora)  OS='fedora';;
        CentOS)  OS='centos';;
        Red\ Hat)  OS='redhat';;
        Red.Hat)  OS='redhat';;
        esac
    # Check for debian_version
    elif [ -f "/etc/debian_version" ]; then
        OS='debian'
    # Check for arch-release
    elif [ -f "/etc/arch-release" ]; then
        OS='arch'
    # Check for SuSE-release
    elif [ -f "/etc/SuSE-release" ]; then
        OS='suse'
    fi
}

check_for_script_updates(){
	PARENT="$(dirname $0)"
	SCRIPTNAME="$(basename $0)"
	if [[ ${CC_CHECK_FOR_SCRIPT_UPDATES} == 'Y' ]] && curl -s -f -m 60 -o "${PARENT}"/${SCRIPTNAME}.tmp ${CC_URL_RAW}/${SCRIPTNAME} 2>/dev/null; then
	  TEMP_CMD=$(awk '/^# Do NOT modify/,0' "${PARENT}"/${SCRIPTNAME})
	  TEMP2_CMD=$(awk '/^# Do NOT modify/,0' "${PARENT}"/${SCRIPTNAME}.tmp)
	  if [[ "$(echo ${TEMP_CMD} | sha256sum)" != "$(echo ${TEMP2_CMD} | sha256sum)" ]]; then
		if (whiptail --title "Update Available" --yesno "A new version of ${SCRIPTNAME} script is available, do you want to download the latest version?" 8 80); then
		  cp "${PARENT}"/${SCRIPTNAME} "${PARENT}/${SCRIPTNAME}_bkp$(date +%s)"
		  STATIC_CMD=$(awk '/#!/{x=1}/^# Do NOT modify/{exit} x' "${PARENT}"/${SCRIPTNAME})
		  printf '%s\n%s\n' "$STATIC_CMD" "$TEMP2_CMD" > "${PARENT}"/${SCRIPTNAME}.tmp
		  {
			mv -f "${PARENT}"/${SCRIPTNAME}.tmp "${PARENT}"/${SCRIPTNAME} && \
			chmod 755 "${PARENT}"/${SCRIPTNAME} && \
			echo -e "\nUpdate applied successfully, please run ${SCRIPTNAME} again!\n" && \
			exit 0;
		  } || {
			echo -e "Update failed!\n\nPlease manually download latest version of ${SCRIPTNAME} script from GitHub" && \
			exit 1;
		  }
		fi
	  fi
	fi
}

install_linux() {
    # TODO: support more distros
    set_os
        case $OS in
            debian )  install_debian ;;
            * )       err "OS $OS unsupported." ;;
        esac
}

install_debian() {
	is_validnetwork
	check_diskspace
	check_totalmemory
    if [[ $CHECK_INTERNET_SPEED == "Y" ]]; then check_internetspeed; fi
	update_OS
	configure_network_config_files
	if [[ $USE_CHRONY == "Y" ]]; then install_chrony; fi
	if [[ $USE_GRAFANA_METRICS == "Y" ]]; then
		install_ethereum_metrics_exporter
		install_monitoring_prometheus_grafana
	fi
	install_EL
	install_CL
	if [[ ${installtype} == "execution_consensus_validator_node" ]]; then
		install_validator
	fi
}

get_status() {
	systemctl status besu lodestar-consensus lodestar-validator
	exit
}

show_commands() {
	if [ -f $VC_DATABASE_PATH ]; then isValidatorInstalled=1; fi

	say_info "Run the following command to get status:"
	echo "service ${EL_NAME} status"
	echo "service ${CL_NAME} status"
	if [ $isValidatorInstalled ]; then echo "service ${VC_NAME} status"; fi

	say_info "Run the following command to stop services:"
	echo "sudo service ${EL_NAME} stop"
	echo "sudo service ${CL_NAME} stop"
	if [ $isValidatorInstalled ]; then echo "service ${VC_NAME} stop"; fi

	say_info "Run the following command to start:"
	echo "sudo service ${EL_NAME} start"
	echo "sudo service ${CL_NAME} start"
	if [ $isValidatorInstalled ]; then echo "sudo service ${VC_NAME} start"; fi

	say_info "Run the following command to monitor logs:"
	echo "journalctl -fu ${EL_NAME}"
	echo "journalctl -fu ${CL_NAME}"
	if [ $isValidatorInstalled ]; then echo "journalctl -fu ${VC_NAME}"; fi
	exit
}


show_overview() {
  cat <<EOF >&2

Here's an overview of the steps required to run an Ethereum node and/or to stake on the Ethereum network as a validator.

To run an Ethereum node, post-Merge, means to:
* Install an Ethereum execution client, ${EL_NAME}, and let it synchronize
* Install an Ethereum beacon node, ${CL_NAME}, and let it synchronize
* If you only want to run an Ethereum node, you can stop here. Congrats.

If you wish to earn staking rewards as a validator on the Ethereum network, you will:
* Aggregate 32 ETH for each of your validator(s)
* Generate your validator key(s)
* Install an Ethereum validator client, ${VC_NAME}
* Import your validator key(s)
* Deposit 32 ETH to fund each of your validator(s)
* Wait for your validator(s) to become active (can take a few hours/days)

PRO TIPS:
* Your staking node setup can easily handle 1, dozens or 1000's of validators.
* Mind the bandwidth data usage. A validator node can use 1TB or more per month. Unlimited data plan recommended.
* Learn to connect to your own node with MetaMask. Thanks & goodbye Infura.
* Monitor stats and visual data from your node with Grafana and Ethereum Metrics Exporter

* Thanks for helping keep Ethereum decentralized, intrepid solo home ETHstaker!!

Cheers, coincashew.eth
EOF
  exit 0

}

show_about() {
  cat <<EOF >&2
Thanks to the ethstaker community, the extraordinary ETH guide creators, and you, the intrepid solo home ETHstaker for supporting ETH.

If you have any question or would like extra support, reach out to the ethstaker community on

* Reddit: reddit.com/r/ethstaker
* coincashew: $CC_REPO
EOF

  exit 0
}

show_advanced() {
  cat <<EOF >&2
USAGE:  These commands are performed manually via your command line.

		* "voluntary exit" - this means you no longer want to stake your 32 ETH and want to retire your validator

							#Stop validator first
							sudo systemctl stop lodestar-validator

							#Perform a voluntary exit, follow the prompts and confirm your choices
							cd /usr/local/bin/ls
							./lodestar account validator voluntary-exit --rootDir /var/lib/lodestar/validators --network <NETWORK>

							#Restart validator, if you did not exit all your validator(s).
							sudo systemctl start lodestar-validator
EOF

  exit 0
}

show_reporting() {
	cat <<EOF >&2
	Reporting with Grafana and Metrics: In order to load the Grafana dashboards and view Ethereum-Metrics-Exporter data, complete the following:
	1) Open with your browser http://localhost:3000 or http://<ipaddress>:3000 If this is remote node, open with a ssh tunnel. If this is a node on your local LAN, you can open port 3000 with "sudo ufw allow 3000/tcp"
	2) Click the Gear Icon on the left menu for "Configuration" > select "Data Sources" > click "Add data source"
	3) Select Prometheus
	4) Enter "http://localhost:9090" for the URL field
	5) Click "Save & Test"
	6) Click the + icon on the left menu, then select "Import".
	7) Get the ethereum metrics exporter dashboard from https://grafana.com/grafana/dashboards/16277 . Either enter the dashboard ID or copy/paste the json.
	8) Click "Load"
	9) For data source, choose the "Prometheus" data source
	10) Click "Import"
EOF

	exit 0
}

generate_validatorkeys() {
	cat <<EOF >&2
Two options to generate your validator keys.

* Wagyu Key Gen GUI: https://github.com/stake-house/wagyu-key-gen
* staking-deposit-cli: https://github.com/ethereum/staking-deposit-cli

Best practice is to generate your keys on an air-gapped offline machine (never connected to the internet).
For testnet purposes, it's less critical.

Afterwards, copy your keystore directory to this Ethereum staking node at location:
$VC_IMPORT_KEYSTORES_PATH

This directory should contain one keystore-m.json file per validator. i.e. 3 validator = 3 keystore-m.json files
Remember to fund your validators with 32ETH each using the $NETWORK launchpad website.

EOF

	exit 0
}

run_wizard(){
	ensure sudo apt-get install -y whiptail
	ask_welcome
	ask_network
	ask_installation
	ask_grafana
	ask_feerecipient
	ask_graffiti
	ask_quicksync
}

ask_welcome() {
	if ! (whiptail --title "CoinCashew.eth Automated ETH Node Installer" --yesno "This script will help you install and run an Ethereum node.\n\nWould you like to continue?" 10 70); then exit; fi
}

ask_network() {
	NETWORK=$(whiptail --notags --title "Pick your Network" --menu \
	"What network do you want to run on?" 13 70 4 \
	"ropsten" "Ropsten Testnet" \
	"kiln" "Kiln Testnet" \
	"mainnet" "Ethereum Mainnet" 3>&1 1>&2 2>&3)
	if [[ $? -eq 1 ]]; then exit; fi
	say_info  "You picked $NETWORK network"

}

ask_installation() {
	installtype=$(whiptail --notags --title "Pick your Installation" --menu \
	"What type of node do you want to run?" 13 80 6 \
	"execution_consensus_node" "Ethereum node - Besu Execution Layer and Lodestar Consensus Layer" \
	"execution_consensus_validator_node" "Ethereum staking node - Besu EL, Lodestar CL and Lodestar Validator" 3>&1 1>&2 2>&3)
	if [[ $? -eq 1 ]]; then exit; fi
	say_info  "You picked $installtype installation"
}

ask_grafana() {
	if (whiptail --title "Dashboard Metrics and Reporting" --yesno "Would you like to install reporting software to view your node's stats / performance? \n\nComponents used include Prometheus, Grafana dashboards and Ethereum Metrics Exporter" 13 80); then USE_GRAFANA_METRICS=Y; fi
}

ask_feerecipient() {
	if [[ ${installtype} == "execution_consensus_validator_node" ]]; then
		while :
		do
			SUGGESTED_FEE_RECIPIENT=$(whiptail --title "Set Validator Rewards Address" --inputbox "Specify your ETH address to receive validator rewards: (right click for paste)\n\n* Do not use your ENS. " 14 70 "$SUGGESTED_FEE_RECIPIENT" 3>&1 1>&2 2>&3)
			if [[ $? -eq 1 ]]; then exit; fi
			if [[ ${SUGGESTED_FEE_RECIPIENT} =~ ^0x[a-fA-F0-9]{40}$ ]]; then
				say_info "Your validator(s) rewards address is:" $SUGGESTED_FEE_RECIPIENT
				break
			else
				whiptail --msgbox "$SUGGESTED_FEE_RECIPIENT is not a valid ETH address. Please enter again." 10 60
			fi
		done
	fi
}

ask_quicksync() {
	if [[ $NETWORK == "mainnet" ]]; then
		if [[ ! $CL_QUICKSYNC_BEACONNODE_URL ]]; then
			if (whiptail --title "Select Option" --yesno "Do you want to Quick Sync your Beacon Node with Infura or another trusted node?" 10 60 3>&1 1>&2 2>&3); then
				CL_QUICKSYNC_BEACONNODE_URL=$(whiptail --title "Configure quick sync" --inputbox "Address for your Infura or trusted consensus layer node? (right click for paste).\n\nInfura example: https://<project-id>:<project-secret>@eth2-beacon-<network>.infura.io" 16 80 3>&1 1>&2 2>&3)
				say_info "Quick sync URL is: $CL_QUICKSYNC_BEACONNODE_URL"
			fi
		fi
	fi
}

ask_graffiti() {
	if [[ ${installtype} == "execution_consensus_validator_node" ]]; then
		VC_GRAFFITI=$(whiptail --title "Set Graffiti" --inputbox "Specify your graffiti to be included in blocks: (32 characters max)" 10 50 "$VC_GRAFFITI" 3>&1 1>&2 2>&3)
		VC_GRAFFITI=${VC_GRAFFITI:0:31}
		say_info "Graffiti is:" "${VC_GRAFFITI}"
	fi
}


is_validnetwork(){
	validnetworks=("ropsten" "mainnet" "kiln" )
	if [[ ! "${validnetworks[@]}" =~ "${NETWORK}" ]]; then
		say_err "${NETWORK} is not a valid network. Valid: $validnetworks"
		exit 1
	fi
}

start_node() {
	pre_installcheck
	say_info "Starting node ..."
	ignore sudo service ${EL_NAME} start
	ignore sudo service ${CL_NAME} start
	say_info "Node started."
	exit
}

stop_node() {
	pre_installcheck
	say_info "Stopping node ..."
	ignore sudo service ${EL_NAME} stop
	ignore sudo service ${CL_NAME} stop
	say_info "Node stopped."
	exit
}

check_diskspace() {
	say_info "Checking for adequate free disk space..."
	FREE=`df -k --output=avail "$PWD" | tail -n1`
	if [[ $FREE -lt 314572800 ]]; then  # 300G = 300*1024*1024k
		if $(whiptail --title "Internet Speed" --yesno "Warning! Less than 300G free disk space.\n\nRecommendations:\n\nmainnet: 2TB\n\ntestnets: 300GB+\n\nWould you like to continue?" 15 80 3>&1 1>&2 2>&3); then
			say_info "Continuing installation with $FREE disk space."
			say_info "Tip: Recommend 1TB or 2TB+ SSD."
		else
			say_info "Tip: Recommend 1TB or 2TB+ SSD."
			say "Good choice. Increase diskspace and try again."
			exit
		fi
	fi
}

check_totalmemory() {
	say_info "Checking for adequate memory..."
	TOTAL_MEM=`free --total --giga| awk 'END{print $2}'`
	if [[ $TOTAL_MEM -lt 12 ]]; then
		if $(whiptail --title "Internet Speed" --yesno "Warning! $TOTAL_MEM GB RAM detected. Less than 12GB total memory.\n\n Would you like to continue?" 15 80 3>&1 1>&2 2>&3); then
			say_info "Continuing installation with $TOTAL_MEM GB RAM."
			say_info "Tip: Recommend 16GB+ of RAM."
		else
			say_info "Tip: Recommend 16GB+ of RAM."
			say "Good choice. Increase RAM and try again."
			exit
		fi
	fi
}

check_internetspeed() {
	say_info "Checking internet connection speed..."
	sudo apt-get update -y -qq && sudo apt-get install speedtest-cli jq -y -qq
	r="$(speedtest-cli --json)"
	down=$(echo $r | jq -r '.download' | awk '{print int ($1/1000000)}')
	up=$(echo $r | jq -r '.upload' | awk '{print int ($1/1000000)}')
	t="Checked speed against $(echo $r | jq -r '.server.sponsor') > $(echo $r | jq -r '.server.host')"
	if [[ $up -lt 5 || $down -lt 5 ]]; then
		if $(whiptail --title "Internet Speed" --yesno "Warning! Internet connection may too be slow.\n\n Would you like to continue?" 15 80 3>&1 1>&2 2>&3); then
			say_info "Tip: Recommend 5Mbit/s+ internet connection with 1TB+ per month data plan."
			say "Good choice. Upgrade internet connection and try again."
			exit
		fi
	fi
	say_info $t
	say "Internet connection speed check complete! Upload: $up Mbit/s Download: $down Mbit/s"
	say_info "Tip: Recommend 10Mbit/s+ internet connection with 1TB+ per month data plan."
}

check_for_existing_installation(){
	systemctl is-active --quiet ${CL_NAME}
	local _retval=$?
	if [ $_retval == 0 ]; then
		say_err "Warning! ${CL_NAME} service is already running!"
		say_err "Remove existing node or use a different machine"
		exit
	fi

	systemctl is-active --quiet ${EL_NAME}
	local _retval=$?
	if [ $_retval == 0 ]; then
		say_err "Warning! ${EL_NAME} service is already running!"
	say_err "Remove existing node or use a different machine"
		exit
	fi
	return 0
}

cleanup_previous_EL_install(){
	if [ -d besu/ ]; then
		say_info "Found previous besu/ ... cleaning up ..."
		sudo rm -rf besu/
	fi
	if [ -d /usr/local/bin/besu/ ]; then
		say_info "Found previous /usr/local/bin/besu ... cleaning up ..."
		sudo rm -rf /usr/local/bin/besu
	fi
	if [ -d $EL_DATABASE_PATH ]; then
		say_info "Found previous DATA files at $EL_DATABASE_PATH ... "
		say_info "Deleting previous database at $EL_DATABASE_PATH"
		sudo rm -rf $EL_DATABASE_PATH
	fi
	if [ -f $SECRETS_PATH/jwtsecret ]; then
		say_info "Found $SECRETS_PATH/jwtsecret ... cleaning up ..."
		sudo rm $SECRETS_PATH/jwtsecret
	fi
}

cleanup_previous_CL_install(){
	if [ -d /tmp/git/lodestar ]; then
		say_info "Found previous lodestar/ ... cleaning up ..."
		sudo rm -rf $/tmp/git/lodestar
	fi
	if [ -d /usr/local/bin/ls ]; then
		say_info "Found previous /usr/local/bin/ls ... cleaning up ..."
	sudo rm -rf /usr/local/bin/ls
	fi
	if [ -d $CL_DATABASE_PATH ]; then
		say_info "Found previous DATA files at $CL_DATABASE_PATH ... "
		say_info "Deleting previous database at $CL_DATABASE_PATH"
		sudo rm -rf $CL_DATABASE_PATH
	fi
}

cleanup_previous_VC_install(){
	if [ -d $VC_DATABASE_PATH ]; then
		say_info "Found previous validator files at $VC_DATABASE_PATH ... "
		say_info "Deleting previous database at $VC_DATABASE_PATH"
		sudo rm -rf $VC_DATABASE_PATH
	fi
}

delete_node(){
	if (whiptail --title "Uninstall" --yesno "Are you sure you want to uninstall this node?" 13 70); then
		ignore sudo systemctl stop grafana-server prometheus prometheus-node-exporter
		ignore sudo systemctl stop ethereum-metrics-exporter ${EL_NAME} ${CL_NAME} ${VC_NAME}

		ignore sudo systemctl disable grafana-server prometheus prometheus-node-exporter
		ignore sudo systemctl disable ethereum-metrics-exporter
		ignore sudo systemctl disable ${EL_NAME} ${CL_NAME} ${VC_NAME}

		cleanup_previous_CL_install
		cleanup_previous_EL_install
		cleanup_previous_VC_install

		ignore sudo apt-get remove chrony speedtest-cli -y -qq
		ignore sudo apt-get remove -y prometheus prometheus-node-exporter grafana fail2ban -qq

		sudo ufw delete allow $EL_P2PPORT/tcp
		sudo ufw delete allow $CL_P2PPORT/tcp
		sudo ufw delete allow $CL_P2PPORT/udp

		sudo rm -rf /tmp/git/merge-testnets
		sudo rm -rf /tmp/git/ethereum-metrics-exporter
		sudo rm /usr/local/bin/ethereum-metrics-exporter

		sudo rm /etc/systemd/system/ethereum-metrics-exporter.service
		sudo rm /etc/systemd/system/${EL_NAME}.service
		sudo rm /etc/systemd/system/${CL_NAME}.service
		sudo rm /etc/systemd/system/${VC_NAME}.service
		sudo rm /etc/prometheus/prometheus.yml
		sudo systemctl daemon-reload

		say "Uninstalled node complete."
		exit
	else
		say "Skipping, not deleting node."
		exit
	fi
}

update_node(){
	pre_installcheck
	say_info "Starting to update node..."
	update_EL_binaries
	if [ $? == "0" ]; then
		ensure sudo systemctl stop ${EL_NAME}
		ensure sudo rm -rf /usr/local/bin/besu
		ensure sudo mv besu /usr/local/bin
		ensure sudo systemctl restart ${EL_NAME}
	fi

	ignore sudo rm -rf /tmp/git/lodestar
	update_CL_binaries
	if [ $? == "0" ]; then
		ensure sudo systemctl stop ${CL_NAME}
		ensure sudo rm -rf /usr/local/bin/ls
		ensure sudo mkdir -p /usr/local/bin/ls
		ensure sudo install -m 0755 -o root -g root -t /usr/local/bin/ls /tmp/git/lodestar/lodestar
		ensure sudo mv /tmp/git/lodestar/node_modules /usr/local/bin/ls
		ensure sudo mv /tmp/git/lodestar/packages /usr/local/bin/ls
		ensure sudo systemctl restart ${CL_NAME}
	fi
	say_info "Update node finished."

	systemctl is-active --quiet ${CL_NAME}
	local _retval=$?
	if [ ! $_retval == 0 ]; then
		say_err "${CL_NAME} is not running, please start manually or investigate logs"
		say_err "journalctl -fu ${CL_NAME}"
	fi

	systemctl is-active --quiet ${EL_NAME}
	local _retval=$?
	if [ ! $_retval == 0 ]; then
		say_err "${EL_NAME} is not running, please start manually or investigate logs"
		say_err "journalctl -fu ${EL_NAME}"
	fi

	say "Automatically restarted node."
	exit
}

update_EL_binaries(){
	say "Downloading ${EL_NAME} binaries..."
	GIT_DATA="$(curl -s https://api.github.com/repos/hyperledger/besu/releases/latest)"
	GIT_TAR_URL="$(echo $GIT_DATA | jq -r '.body' | grep '.tar.gz')"
	EL_GIT_VERSION="$(echo $GIT_DATA | jq -r '.tag_name')"
	if [[ -f $EL_DATABASE_PATH/tag_name ]]; then
		say_info "Current ${EL_NAME} version $(sudo cat $EL_DATABASE_PATH/tag_name)"
	fi
	if [[ ! -f $EL_DATABASE_PATH/tag_name || ("$(sudo cat $EL_DATABASE_PATH/tag_name )" != "$EL_GIT_VERSION") ]]; then

		say "Installing ${EL_NAME} $EL_GIT_VERSION ..."
		ensure wget $GIT_TAR_URL -O besu.tar.gz
		ensure tar -xf besu.tar.gz
		ensure rm besu.tar.gz
		ensure mv besu*/ besu #rename folder

		sudo echo $EL_GIT_VERSION | sudo tee $EL_DATABASE_PATH/tag_name
		sudo chown -R $EL_service_account_name:$EL_service_account_name $EL_DATABASE_PATH
		return 0
	else
		say_info "EL already on latest version $EL_GIT_VERSION."
		return -1
	fi
}

update_CL_binaries(){
	say "Building ${CL_NAME} binaries..."
	GIT_DATA="$(curl -s https://api.github.com/repos/chainsafe/lodestar/releases/latest)"
	CL_GIT_VERSION="$(echo $GIT_DATA | jq -r '.tag_name')"
	if [[ -f $CL_DATABASE_PATH/tag_name ]]; then
		say_info "Current ${CL_NAME} version $(sudo cat $CL_DATABASE_PATH/tag_name)"
	fi
	if [[ ! -f $CL_DATABASE_PATH/tag_name || ("$(sudo cat $CL_DATABASE_PATH/tag_name )" != "$CL_GIT_VERSION") ]]; then
		say "Installing ${CL_NAME} $CL_GIT_VERSION ..."
		if [[ -d /tmp/git/lodestar ]]; then sudo rm -rf /tmp/git/lodestar; fi
		ensure mkdir -p /tmp/git && cd /tmp/git
		ensure git clone https://github.com/chainsafe/lodestar.git
		ensure cd lodestar
		ensure yarn install --ignore-optional
		ensure yarn run build

		say "Verifying ${CL_NAME} was installed properly by displaying the help menu."
		ensure ./lodestar --help

		sudo echo $CL_GIT_VERSION | sudo tee $CL_DATABASE_PATH/tag_name
		sudo chown -R $CL_service_account_name:$CL_service_account_name $CL_DATABASE_PATH
		return 0
	else
		say_info "CL already on latest version $CL_GIT_VERSION."
		return -1
	fi
}

pre_installcheck(){
	if [[ ! -f $EL_DATABASE_PATH/tag_name ]]; then
		say_err "Execution Layer not yet installed."
		say "Run this first: sudo ./$(basename "$0")"
		exit 1
	fi
}

configure_firewall(){
	say "Configuring ufw firewall..."

	# By default, deny all incoming and outgoing traffic
	sudo ufw default deny incoming
	sudo ufw default allow outgoing

	# Allow SSH access
	sudo ufw allow $SSH_PORT

	# Allow execution client port
	sudo ufw allow $EL_P2PPORT/tcp

	# Allow consensus client port
	sudo ufw allow $CL_P2PPORT/tcp
	sudo ufw allow $CL_P2PPORT/udp

	# Enable UFW
	sudo ufw enable

	# Show status
	sudo ufw status numbered
	say "Success, ufw firewall enabled"

	sudo apt-get install fail2ban -y -qq
	ensure cat > jail.local << EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF
	sudo mv jail.local /etc/fail2ban/jail.local
	sudo systemctl restart fail2ban
	say "Success, fail2ban enabled"
	exit
}

update_OS(){
	say "Installing OS updates..."
	ignore sudo apt-get update && sudo apt-get upgrade -y
	ignore sudo apt-get install git ufw curl wget -y
}

install_chrony(){
	say "Installing chrony time synchronization service..."
	ignore sudo apt-get install chrony -y
}

configure_network_config_files(){
	EL_ADDITIONAL_PARAMETERS=""
	CL_ADDITIONAL_PARAMETERS=""
	VC_ADDITIONAL_PARAMETERS=""

	if [ $NETWORK == 'ropsten' ]; then
		if [[ ! -d /tmp/git/merge-testnets ]]; then
			say "Downloading $NETWORK configuration files..."
			ensure sudo apt-get install -y git
			ensure mkdir -p /tmp/git && cd /tmp/git
			ignore git clone https://github.com/eth-clients/merge-testnets.git

			say "Copying $NETWORK configuration files..."
			if [[ ! -d $CL_DATABASE_PATH ]]; then sudo mkdir -p $CL_DATABASE_PATH; fi
			ensure sudo cp /tmp/git/merge-testnets/ropsten-beacon-chain/config.yaml $CL_DATABASE_PATH
			ensure sudo cp /tmp/git/merge-testnets/ropsten-beacon-chain/boot_enr.txt $CL_DATABASE_PATH
			ensure sudo cp /tmp/git/merge-testnets/ropsten-beacon-chain/genesis.ssz $CL_DATABASE_PATH
		fi

		CL_ADDITIONAL_PARAMETERS="--paramsFile="$CL_DATABASE_PATH/config.yaml" \
	--genesisStateFile="$CL_DATABASE_PATH/genesis.ssz" \
	--bootnodesFile="$CL_DATABASE_PATH/boot_enr.txt" \
	--network.discv5.bootEnrs="enr:-Iq4QMCTfIMXnow27baRUb35Q8iiFHSIDBJh6hQM5Axohhf4b6Kr_cOCu0htQ5WvVqKvFgY28893DHAg8gnBAXsAVqmGAX53x8JggmlkgnY0gmlwhLKAlv6Jc2VjcDI1NmsxoQK6S-Cii_KmfFdUJL2TANL3ksaKUnNXvTCv1tLwXs0QgIN1ZHCCIyk" \
	--terminal-total-difficulty-override=50000000000000000"

		EL_ADDITIONAL_PARAMETERS="override-genesis-config=[\"terminalTotalDifficulty=50000000000000000\"]"
		VC_ADDITIONAL_PARAMETERS="--terminal-total-difficulty-override 50000000000000000"
	fi

	if [ $CL_QUICKSYNC_BEACONNODE_URL ]; then
		say "Quick Sync for beacon node enabled..."
		CL_ADDITIONAL_PARAMETERS="${CL_ADDITIONAL_PARAMETERS} --weakSubjectivitySyncLatest --weakSubjectivityServerUrl ${CL_QUICKSYNC_BEACONNODE_URL}"
	fi

	if [[ $installtype == "execution_consensus_validator_node" ]]; then
		EL_ADDITIONAL_PARAMETERS="${EL_ADDITIONAL_PARAMETERS}\nminer-enabled=true\nminer-coinbase=\"${SUGGESTED_FEE_RECIPIENT}\""
		CL_ADDITIONAL_PARAMETERS="${CL_ADDITIONAL_PARAMETERS} --chain.defaultFeeRecipient ${SUGGESTED_FEE_RECIPIENT}"
		VC_ADDITIONAL_PARAMETERS="${VC_ADDITIONAL_PARAMETERS} --defaultFeeRecipient ${SUGGESTED_FEE_RECIPIENT}"
	fi
}

install_ethereum_metrics_exporter(){
	if [[ -f /usr/local/bin/ethereum-metrics-exporter ]]; then
		say_info "ethereum-metrics-exporter already installed."
		return 0
	fi

	say "Installing ethereum metrics exporter by samcm ..."

	ensure sudo apt-get install -y git wget gcc

	ensure wget https://go.dev/dl/go1.18.linux-amd64.tar.gz
	ensure sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.18.linux-amd64.tar.gz && rm go1.18.linux-amd64.tar.gz
	echo "export PATH=$PATH:/usr/local/go/bin" >> .profile
	source .profile

	ensure mkdir -p /tmp/git && cd /tmp/git
	ignore git clone https://github.com/samcm/ethereum-metrics-exporter
	cd ethereum-metrics-exporter
	go build -o ethereum-metrics-exporter .
	ensure sudo install -m 0755 -o root -g root -t /usr/local/bin ethereum-metrics-exporter

	id -u ethereum-metrics-exporter >/dev/null 2>&1
	if [ "$?" == "0" ]; then
	  say_info "ethereum-metrics-exporter user already exists... skipping."
	else
	  say "Creating ethereum-metrics-exporter service user..."
	  ignore sudo useradd -r -s /bin/false ethereum-metrics-exporter
	fi

	say "Creating ethereum-metrics-exporter systemd service..."

	ensure cat > ethereum-metrics-exporter.service << EOF
[Unit]
Description=ethereum-metrics-exporter service
Wants           = network-online.target
After           = network-online.target


[Service]
ExecStart=/usr/local/bin/ethereum-metrics-exporter --metrics-port 9191 --consensus-url=http://localhost:9596 --execution-url=http://localhost:8545

# Process management
####################

Type=simple
Restart=on-failure
RestartSec=3
TimeoutStopSec=300
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

	ensure sudo mv ethereum-metrics-exporter.service /etc/systemd/system/ethereum-metrics-exporter.service
	ensure sudo chmod 644 /etc/systemd/system/ethereum-metrics-exporter.service
	ensure sudo systemctl enable ethereum-metrics-exporter

	say "Starting ethereum-metrics-exporter-consensus..."
	ensure sudo systemctl restart ethereum-metrics-exporter
	systemctl is-active --quiet ethereum-metrics-exporter
	local _retval=$?
	if [ $_retval != 0 ]; then
		say_err "Warning! ethereum-metrics-exporter service is not running!"
		journalctl -u ethereum-metrics-exporter -b --no-pager
	fi
}

install_monitoring_prometheus_grafana(){

	if [[ -f /etc/prometheus/prometheus.yml && -f /etc/apt/sources.list.d/grafana.list ]]; then
		say_info "prometheus and grafana already installed."
		return 0
	fi

	say "Installing prometheus and grafana monitoring ..."
	ensure sudo apt-get install -y prometheus prometheus-node-exporter gnupg -qq
	ensure wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
	ensure echo "deb https://packages.grafana.com/oss/deb stable main" > grafana.list
	ensure sudo mv grafana.list /etc/apt/sources.list.d/grafana.list
	ensure sudo apt-get update && sudo apt-get install -y grafana
	ensure sudo systemctl enable grafana-server.service prometheus.service prometheus-node-exporter.service

	cat > prometheus.yml << EOF
global:
  scrape_interval:     15s # By default, scrape targets every 15 seconds.

scrape_configs:
   - job_name: 'node_exporter'
     static_configs:
       - targets: ['localhost:9100']
   - job_name: 'EthereumMetricsExporter'
     static_configs:
       - targets: ['localhost:9191']
   - job_name: Lodestar
     metrics_path: /metrics
     static_configs:
       - targets: ["localhost:8008"]
EOF

	ensure sudo mv prometheus.yml /etc/prometheus/prometheus.yml
	ensure sudo chmod 644 /etc/prometheus/prometheus.yml
	ensure sudo systemctl restart grafana-server.service prometheus.service prometheus-node-exporter.service
}
import_validatorkeys() {
	pre_installcheck

	if [[ ! -d $VC_DATABASE_PATH ]]; then
		say_err "Install validator first.  Use: ./$(basename "$0") -v"
		exit 1
	fi

	say "Starting to import validator key(s)..."

	if [[ ! -d  $VC_IMPORT_KEYSTORES_PATH ]]; then sudo mkdir -p $VC_IMPORT_KEYSTORES_PATH; fi

	VC_IMPORT_KEYSTORES_PATH=$(whiptail --title "Import keys" --inputbox "Where are your validator keys? (right click for paste).\n\nBy default, you can copy them into $VC_IMPORT_KEYSTORES_PATH\n\nMake a new window or new terminal and copy your keys over before proceeding." 16 80 $VC_IMPORT_KEYSTORES_PATH 3>&1 1>&2 2>&3)
	say_info "Importing keystores from: $VC_IMPORT_KEYSTORES_PATH"

	count=$(ls $VC_IMPORT_KEYSTORES_PATH/keystore*json | wc -l)
	if [[ $count -ge 1 ]]; then
		say "Found $count keystore files"
		rm $VC_IMPORT_KEYSTORES_PATH/deposit_data* #remove any deposit_data files
	else
		say_err "No keystore files found"
		say_err "Please copy keystore files to directory: $VC_IMPORT_KEYSTORES_PATH"
		say_err "Then try keystore import again"
		say_err "Usage: $(basename $0) -i"
		exit 1
	fi

	whiptail --title "Importing keys" --msgbox "Before importing, you should understand...\n\n* NEW VALIDATORS: Only import your validator keys on a single staking machine. Don't import your keys with multiple validator clients.\n\n* EXISTING VALIDATORS: If migrating from a previous installation, best practice is to STOP and DELETE your validator key(s) on your previous validator node. Then, WAIT 2 EPOCHS and ensure your validator(s) have MISSED ATTESTATIONS (check beaconcha.in) block explorer) for those 2 recent epochs. Finally, it's safe to import.\n\n* In order to import keys, I will be prompted to enter my keystore password twice.\n\n* Already imported keys will be skipped.\n\n* lodestar-validator client automatically detects new imported keys. No need to restart validator\n\n" 26 80
	if (whiptail --title "Confirmation" --yesno "I UNDERSTAND AND WANT TO PROCEED WITH IMPORTING VALIDATOR KEYS?" 12 60); then
		cd /usr/local/bin/ls
		sudo /usr/local/bin/ls/lodestar account validator import --network ${NETWORK} --directory ${VC_IMPORT_KEYSTORES_PATH} --rootDir "$VC_DATABASE_PATH"
		say "For confirmation, here's the validator keys on this machine:"
		sudo /usr/local/bin/ls/lodestar account validator list --network ${NETWORK} --rootDir "$VC_DATABASE_PATH"
		say "Import Validator key(s) complete"
		sudo chown -R $VC_service_account_name:$VC_service_account_name $VC_DATABASE_PATH
	else
			say_info "Skipped importing validator keys."
	fi
}

install_EL() {
	need_cmd apt-get
	need_cmd sleep
	need_cmd systemctl
	need_cmd openssl

	if [[ -f $EL_DATABASE_PATH/tag_name ]]; then
		say_info "${EL_NAME} already installed."
		return 0
	fi

	say "Starting to install ${EL_NAME} ..."

	id -u $EL_service_account_name >/dev/null 2>&1
	if [ "$?" == "0" ]; then
	  say_info "$EL_service_account_name user already exists... skipping."
	else
	  say "Creating $EL_service_account_name service user..."
	  ignore sudo useradd -r -s /bin/false $EL_service_account_name
	fi

	say "Setting up besu data directory..."
	ensure sudo mkdir -p $EL_DATABASE_PATH
	ensure sudo chown $EL_service_account_name:$EL_service_account_name $EL_DATABASE_PATH

	say "Updating repos ..."
	ignore sudo apt-get update -qq

	say "Installing wget curl jq ..."
	ensure sudo apt-get install -y wget curl jq -qq

	say "Installing openjdk-11-jre ... may take a few minutes."
	ensure sudo apt-get install -y openjdk-11-jre

	say "Creating jwtsecret..."
	ensure sudo mkdir -p $SECRETS_PATH
	ensure openssl rand -hex 32 | tr -d "\n" | sudo tee $SECRETS_PATH/jwtsecret
	ensure sudo cp $SECRETS_PATH/jwtsecret $EL_DATABASE_PATH
	ensure sudo chown $EL_service_account_name:$EL_service_account_name $EL_DATABASE_PATH/jwtsecret
	echo ""
	say "Creating besu TOML config file..."
	ensure cat > config.toml << EOF
# Besu TOML config file
data-path="${EL_DATABASE_PATH}"
data-storage-format="BONSAI"
sync-mode="X_SNAP"

network="$NETWORK"
host-allowlist=["*"]

p2p-port=${EL_P2PPORT}
p2p-enabled=true
max-peers=${EL_MAXPEERS}

rpc-http-enabled=true
rpc-http-host="0.0.0.0"
rpc-http-port=8545
rpc-http-cors-origins=["*"]
rpc-http-api=["ADMIN","ETH","NET","DEBUG","TXPOOL","WEB3"]

rpc-ws-enabled=true
rpc-ws-host="0.0.0.0"
rpc-ws-port=8546

metrics-enabled=true
metrics-host="0.0.0.0"
metrics-port=6060

engine-jwt-enabled=true
engine-jwt-secret="$EL_DATABASE_PATH/jwtsecret"
engine-host-allowlist=["*"]
engine-rpc-port=8551
EOF

# Add network-specific EL parameters
echo -e ${EL_ADDITIONAL_PARAMETERS} >> config.toml
ensure sudo mv config.toml ${EL_DATABASE_PATH}/config.toml
ensure sudo chown $EL_service_account_name:$EL_service_account_name ${EL_DATABASE_PATH}/config.toml

	say "Creating systemd service..."

	ensure cat > ${EL_NAME}.service << EOF
[Unit]
Description     = Besu Execution Layer Client service
Wants           = network-online.target ${CL_NAME}.service
After           = network-online.target ${CL_NAME}.service

[Service]
ExecStart=/usr/local/bin/besu/bin/besu \
	--config-file=${EL_DATABASE_PATH}/config.toml

Environment="JAVA_OPTS=-Xmx4g"

# Process management
####################

Type=simple
Restart=on-failure
RestartSec=3
TimeoutStopSec=300
KillSignal=SIGINT

# Run as $EL_service_account_name:$EL_service_account_name
User=$EL_service_account_name
Group=$EL_service_account_name

[Install]
WantedBy=${CL_NAME}.service
EOF
	ensure sudo mv ${EL_NAME}.service /etc/systemd/system/${EL_NAME}.service
	ensure sudo chmod 644 /etc/systemd/system/${EL_NAME}.service
	ensure sudo systemctl enable ${EL_NAME}

	update_EL_binaries

	say "Installing ${EL_NAME} binaries version $EL_GIT_VERSION..."
	if [[ -d /usr/local/bin/besu ]]; then rm -rf /usr/local/bin/besu; fi
	ensure sudo mv besu /usr/local/bin

	say "Starting ${EL_NAME}..."
	ensure sudo systemctl restart ${EL_NAME}
	systemctl is-active --quiet ${EL_NAME}
	local _retval=$?
	if [ $_retval != 0 ]; then
		say_err "Warning! ${EL_NAME} service is not running!"
		journalctl -u ${EL_NAME} -b --no-pager
	fi
}


install_CL() {
	need_cmd apt-get
	need_cmd sleep
	need_cmd systemctl

	if [[ -f $CL_DATABASE_PATH/tag_name ]]; then
		say_info "${CL_NAME} already installed."
		return 0
	fi

	say "Starting to install ${CL_NAME} ..."

	id -u $CL_service_account_name >/dev/null 2>&1
	if [ "$?" == "0" ]; then
		say_info "$CL_service_account_name user already exists... skipping."
	else
		say "Creating $CL_service_account_name service user..."
		ignore sudo useradd -r -s /bin/false $CL_service_account_name
	fi

	say "Setting up ${CL_NAME} consensus data directory..."
	ensure sudo mkdir -p $CL_DATABASE_PATH
	ensure sudo chown $CL_service_account_name:$CL_service_account_name $CL_DATABASE_PATH
	ensure sudo chmod 700 $CL_DATABASE_PATH

	say "Copying jwtsecret..."
	ensure sudo cp /secrets/jwtsecret $CL_DATABASE_PATH/jwtsecret
	ensure sudo chown -R $CL_service_account_name:$CL_service_account_name $CL_DATABASE_PATH

	say "Updating repos ..."
	ignore sudo apt-get update -qq

	say "Installing gcc g++ make git curl ..."
	ensure sudo apt-get install -y gcc g++ make git curl jq -qq

	say "Installing yarn"
	ensure curl -m 60 -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
	ensure echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
	ignore sudo apt update -qq
	ensure sudo apt install yarn -y

	say "Installing nodejs"
	ensure curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
	ensure sudo apt-get install -y nodejs

	say "Creating systemd service..."

	ensure cat > ${CL_NAME}.service << EOF
[Unit]
Description=Lodestar Consensus Layer Client service
Wants           = network-online.target
After           = network-online.target

[Service]
WorkingDirectory=/usr/local/bin/ls
ExecStart=/usr/local/bin/ls/lodestar beacon \
  ${CL_ADDITIONAL_PARAMETERS} \
  --network $NETWORK \
  --rootDir "$CL_DATABASE_PATH" \
  --execution.urls "http://127.0.0.1:8551" \
  --jwt-secret "$CL_DATABASE_PATH/jwtsecret" \
  --network.connectToDiscv5Bootnodes \
  --network.discv5.enabled true \
  --api.rest.enabled true \
  --api.rest.host 0.0.0.0 \
  --api.rest.api "*" \
  --api.rest.port 9596 \
  --metrics.enabled \
  --metrics.serverPort 8008 \
  --network.targetPeers $CL_MAXPEERS

# Process management
####################

Type=simple
Restart=on-failure
RestartSec=3
TimeoutStopSec=300
KillSignal=SIGINT

# Run as $CL_service_account_name:$CL_service_account_name
User=$CL_service_account_name
Group=$CL_service_account_name

[Install]
WantedBy=multi-user.target
RequiredBy	= ${VC_NAME}.service ${EL_NAME}.service
EOF
	ensure sudo mv ${CL_NAME}.service /etc/systemd/system/${CL_NAME}.service
	ensure sudo chmod 644 /etc/systemd/system/${CL_NAME}.service
	ensure sudo systemctl enable ${CL_NAME}

	update_CL_binaries

	say "Installing ${CL_NAME} $CL_GIT_VERSION binaries..."
	need_cmd install
	if [[ -d /usr/local/bin/ls ]]; then sudo rm -rf /usr/local/bin/ls; fi
	sudo mkdir -p /usr/local/bin/ls
	ensure sudo install -m 0755 -o root -g root -t /usr/local/bin/ls /tmp/git/lodestar/lodestar
	ensure sudo mv /tmp/git/lodestar/node_modules /usr/local/bin/ls
	ensure sudo mv /tmp/git/lodestar/packages /usr/local/bin/ls

	say "Starting ${CL_NAME}..."
	ensure sudo systemctl restart ${CL_NAME}
	systemctl is-active --quiet ${CL_NAME}
	local _retval=$?
	if [ $_retval != 0 ]; then
		say_err "Warning! ${CL_NAME} service is not running!"
		journalctl -u ${CL_NAME} -b --no-pager
	fi
}

install_validator() {
	pre_installcheck

	if [[ ! ${installtype} ]]; then ask_network; fi

	if [[ -d $VC_DATABASE_PATH ]]; then
		say_info "${VC_NAME} already installed."
		return 0
	fi

	say "Starting to install $VC_NAME ..."

	id -u $VC_service_account_name >/dev/null 2>&1
	if [ "$?" == "0" ]; then
		say_info "$VC_service_account_name user already exists... skipping."
	else
		say "Creating $VC_service_account_name service user..."
		ignore sudo useradd -r -s /bin/false $VC_service_account_name
	fi

	say "Setting up $VC_NAME validator data directory..."
	ensure sudo mkdir -p $VC_DATABASE_PATH
	ensure sudo chown $VC_service_account_name:$VC_service_account_name $VC_DATABASE_PATH
	ensure sudo chmod 700 $VC_DATABASE_PATH

	configure_network_config_files

	say "Creating systemd service..."

	ensure cat > ${VC_NAME}.service << EOF
[Unit]
Description=Lodestar Validator Client service
BindsTo		= ${CL_NAME}.service
After		= ${CL_NAME}.service

[Service]
WorkingDirectory=/usr/local/bin/ls
ExecStart=/usr/local/bin/ls/lodestar validator \
  ${VC_ADDITIONAL_PARAMETERS} \
  --network "$NETWORK" \
  --rootDir "$VC_DATABASE_PATH" \
  --graffiti "$VC_GRAFFITI"

# Process management
####################

Type=simple
Restart=on-failure
RestartSec=3
TimeoutStopSec=300
KillSignal=SIGINT

# Run as $VC_service_account_name:$VC_service_account_name
User=$VC_service_account_name
Group=$VC_service_account_name

[Install]
WantedBy=${CL_NAME}.service
EOF
	ensure sudo mv ${VC_NAME}.service /etc/systemd/system/${VC_NAME}.service
	ensure sudo chmod 644 /etc/systemd/system/${VC_NAME}.service
	ensure sudo systemctl enable ${VC_NAME}

	say "Starting ${VC_NAME}..."
	ensure sudo systemctl restart ${VC_NAME}
	systemctl is-active --quiet ${VC_NAME}
	local _retval=$?
	if [ $_retval != 0 ]; then
		say_err "Warning! ${VC_NAME} service is not running!"
		journalctl -u ${VC_NAME} -b --no-pager
	fi
	import_validatorkeys
}

install() {
	unamestr=`uname`
	if [ "$unamestr" = 'Linux' ]; then
		install_linux "$@"
	else
		err "OS $unamestr unsupported."
	fi

	if [ -d $VC_DATABASE_PATH ]; then isValidatorInstalled=1; fi

	say_info "${EL_NAME} is now running on port $EL_P2PPORT"
	say_info "${CL_NAME} is now running on port $CL_P2PPORT"
	say_info "Ensure port forwarding is setup on your router!"
	echo ""
	say_info "Run the following command to get status:"
	echo "service ${EL_NAME} status"
	echo "service ${CL_NAME} status"

	say_info "Run the following command to stop services:"
	echo "sudo service ${EL_NAME} stop"
	echo "sudo service ${CL_NAME} stop"
	say_info "Note: As ${EL_NAME} depends on ${CL_NAME}, stopping ${CL_NAME} automatically stops ${EL_NAME}"

	say_info "Run the following command to start:"
	echo "sudo service ${EL_NAME} start"
	echo "sudo service ${CL_NAME} start"
	say_info "Note: As ${EL_NAME} depends on ${CL_NAME}, starting ${CL_NAME} automatically starts ${EL_NAME}"

	say_info "Run the following command to monitor logs:"
	echo "journalctl -fu ${EL_NAME}"
	echo "journalctl -fu ${CL_NAME}"

	say "\nCongrats and thanks for running a ${EL_NAME} ${EL_GIT_VERSION} and ${CL_NAME} ${CL_GIT_VERSION} on ${NETWORK} network!"
	say "Next steps:"
	say_info "Secure your node - Configure firewall and fail2ban. Use: ./$(basename "$0") -w"
	say_info "Learn more about Ethereum Staking. Use: ./$(basename "$0") -o"
	say_info "Learn more about your node with Grafana Dashboarding. Use: ./$(basename "$0") -r"
	say_info "Explore the help menu. Use: ./$(basename "$0") -h"
	say "Automated install complete !!!"
}

# Copyright 2016 The Rust Project Developers. See the COPYRIGHT
# file at the top-level directory of this distribution and at
# http://rust-lang.org/COPYRIGHT.
#
# Licensed under the Apache License, Version 2.0 <LICENSE-APACHE or
# http://www.apache.org/licenses/LICENSE-2.0> or the MIT license
# <LICENSE-MIT or http://opensource.org/licenses/MIT>, at your
# option. This file may not be copied, modified, or distributed
# except according to those terms.

say() {
	echo -e "${COL_LIGHT_GREEN}coincashew-automated-mdc-install:${COL_NC} ${TICK} $@"
}

say_info() {
	echo -e "${COL_LIGHT_BLUE}coincashew-automated-mdc-install:${COL_NC} ${INFO} $@"
}
say_err() {
	echo -e "${COL_LIGHT_RED}coincashew-automated-mdc-install:${COL_NC} ${CROSS} $@" >&2
}

err() {
	say "$@" >&2
	exit 1
}

need_cmd() {
	if ! command -v "$1" > /dev/null 2>&1
	then err "need '$1' (command not found)"
	fi
}

need_ok() {
	if [ $? != 0 ]; then err "$1"; fi
}

assert_nz() {
	if [ -z "$1" ]; then err "assert_nz $2"; fi
}

# Run a command that should never fail. If the command fails execution
# will immediately terminate with an error showing the failing
# command.
ensure() {
	"$@"
	need_ok "$CROSS command failed: $*"
}

# This is just for indicating that commands' results are being
# intentionally ignored. Usually, because it's being executed
# as part of error handling.
ignore() {
	run "$@"
}

# Runs a command and prints it to stderr if it fails.
run() {
	"$@"
	local _retval=$?
	if [ $_retval != 0 ]; then
		say_err "command failed: $*"
	fi
	return $_retval
}

set_colors() {
	COL_NC='\e[0m' # No Color
	COL_LIGHT_GREEN='\e[1;32m'
	COL_LIGHT_RED='\e[1;31m'
	COL_LIGHT_BLUE='\e[1;34m'
	TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
	CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
	INFO="[i]"
}

set_colors
say "Running Automated ::bestar:: ETH Node Install Script"
get_sudo
check_for_script_updates
get_options "$@"
if [[ $DELETE_NODE == "Y" ]]; then delete_node; fi
if [[ $UPDATE_NODE == "Y" ]]; then update_node; fi
if [[ $CONFIG_FIREWALL == "Y" ]]; then configure_firewall; fi
if [[ $INSTALL_QUICK == "N" ]]; then run_wizard; fi
install "$@"
