
build:
	@cd script && ./build.sh

up:
	@cd script && ./network_setup.sh -t up
down:
	@cd script && ./network_setup.sh -t down
add:
	@cd script && ./network_setup.sh -t add

start:
	@cd script && ./node_flex.sh -t start
del:
	@cd script && ./node_flex.sh -t del

monup:
	@cd monitor && make up
mondown:
	@cd monitor && make down 

clean:
	@echo "every thing is clean up, no worry"
