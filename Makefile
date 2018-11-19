
build:
	@cd script && ./build.sh

down:
	@cd script && ./network_setup.sh -t down

# setup network by version
upold:
	@cd script && ./network_setup.sh -t up -v 0.18.0
upnew:
	@cd script && ./network_setup.sh -t up -v 0.23.1

# add new node to network by version
addold:
	@cd script && ./network_setup.sh -t add -v 0.18.0
addnew:
	@cd script && ./network_setup.sh -t add -v 0.23.1

# restore or delete bad node
start:
	@cd script && ./node_flex.sh -t start
del:
	@cd script && ./node_flex.sh -t del

# upgrade from 0.18.0 to 0.23.1
upgrade:
	@cd script && ./upgrade_all.sh

# start or stop node monitor api interface
upmon:
	@cd monitor && make up
downmon:
	@cd monitor && make down 

clean:
	@echo "every thing is clean up, no worry"
