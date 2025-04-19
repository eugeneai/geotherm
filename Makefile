.PHONY: server gulp prod dev mongo msh

JULIA=/usr/bin/julia --project=v1.11

RS=rsync -Pav -e "ssh -i /home/eugeneai/.ssh/id_ed25519-gtherm" --delete-after
server:
	$(JULIA) storage.jl

project:
	$(JULIA)

julia: project

pluto:
	# host=0.0.0.0, port=1234
	$(JULIA) plutenb.jl

gulp:
	gulp

prod:
	gulp build:dist

dev:
	gulp build:dev

sync:
	# ssh root -i ~/.ssh/id_ed25519-gtherm
	$(RS) /mnt/data/gtherm/site/html\&css/ eugeneai@root:/srv/http/gtherm.ru/
