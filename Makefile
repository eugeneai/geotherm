.PHONY: server gulp prod dev mongo msh

server:
	julia storage.jl

gulp:
	gulp

prod:
	gulp build:dist

dev:
	gulp build:dev

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
