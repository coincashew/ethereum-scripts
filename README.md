# Automated ETH Node Install Script
# :: Besu EL & Lodestar CL ::
by coincashew.eth [ https://coincashew.com ]

## Tools for Ethereum Nodes and Staking for the Home Node Operator

## Install quickly and conveniently with this command (from your Ubuntu Linux machine):

```
curl -sSL https://raw.githubusercontent.com/coincashew/ethereum-scripts/main/eth-node-besu-lodestar.sh | bash
```

```
 [✓] Tested working on Ubuntu 20.04.4 LTS
 [✓] Tested working on Ubuntu 21.10
 [✗] Tested as NOT working with Ubuntu 22.04 due to nodejs issues
```

## Objectives
* Strengthen the Most Diverse Client -- Lodestar CL and Besu EL 
* Simple to use for the home solo staker
* Fully automated installation
* Easy to use with Ubuntu Linux
* Simple to read, understand and modify
* No docker requirements
* Interruptible and self-recoverable
* Self-updating to the latest version
* Built-in tests for common node issues, such as lack of disk space, internet speed, or ram

Improvements, issues, pull-requests and feedback greatly welcome at:
[github.com](https://github.com/coincashew/ethereum-scripts/)

### Donations: coincashew.eth

### Gitcoin Grant: https://gitcoin.co/grants/1653/ethereum-staking-guides-by-coincashew-with-poap

Thanks for your support, home stakers and all.

After installing your node, you'll want to maintain and operate it.
Download and access the script as follows.

```
curl -sS -o eth-node-install-besu-lodestar.sh https://raw.githubusercontent.com/coincashew/ethereum-scripts/main/eth-node-install-besu-lodestar.sh
chmod 755 eth-node-install-besu-lodestar.sh
./eth-node-install-besu-lodestar.sh
```

### Pro tips:
* Always test first on Testnets !!! Then you can graduate to mainnet.
* Don't attest too late. Use time synchronization, such as Chrony.
* Take [security](https://www.coincashew.com/coins/overview-eth/guide-or-how-to-setup-a-validator-on-eth2-mainnet/part-i-installation/guide-or-security-best-practices-for-a-eth2-validator-beaconchain-node) seriously. Use the firewall option -w
* Keep validator keys offline! And have fun !!!

Before continuing, please learn the syntax of this script. To view the usage options, use ./eth-node-install-besu-lodestar.sh -h
Sample help output below:

```
Automatically installs the most diverse Ethereum node :: Merge Ready
by coincashew.eth
=====================================================================
bestar :: most diverse client :: besu EL and lodestar-consensus CL
=====================================================================

USAGE:
	eth-node-besu-lodestar.sh [-u] [-w] [-n <ropsten|mainnet|kiln> ] [-d] [-c] [-g] [-x] [-s] [-o] [-a] [-k] [-v] [-i] [-t] [-q] [-z] [-r]

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
```
