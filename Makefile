.PHONY: server gulp prod dev mongo msh

RS=rsync -Pav -e "ssh -i /home/eugeneai/.ssh/id_ed25519-gtherm" --delete-after
server:
	julia --project=v1.11 storage.jl

gulp:
	gulp

prod:
	gulp build:dist

dev:
	gulp build:dev

sync:
	# ssh root -i ~/.ssh/id_ed25519-gtherm
	$(RS) /mnt/data/gtherm/site/html\&css/ eugeneai@root:/srv/http/gtherm.ru/

mongo:
	mongod --dbpath ./storage

# mongo shell connect to geotherm database
# Collections are
# 1. db.users
# 2. db.projects
# 3. db.models
# 4. db.figures
msh:
	mongosh mongodb://localhost/geotherm
