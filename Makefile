.PHONY: server gulp prod dev mongo msh

JULIA=/usr/bin/julia

RS=rsync -Pav -e "ssh -i /home/eugeneai/.ssh/id_ed25519-gtherm" --delete-after
server:
	$(JULIA) --project=v1.11 storage.jl

project:
	$(JULIA) --project=v1.11

gulp:
	gulp

prod:
	gulp build:dist

dev:
	gulp build:dev

sync:
	# ssh root -i ~/.ssh/id_ed25519-gtherm
	$(RS) /mnt/data/gtherm/site/html\&css/ eugeneai@root:/srv/http/gtherm.ru/
