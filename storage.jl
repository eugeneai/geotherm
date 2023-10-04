import Mongoc
import SHA
import UUIDs

mutable struct Config
    salt::String
    systemUUID::Any
    client::Any
    dbName::String
    db::Any
end

@enum ResultLevel begin
    OK = 0
    INFO = 1
    ERROR = 2
    FATAL = 3
    DEBUG = 4
end

struct Result
    value::Any
    level::ResultLevel
    description::String
end

config::Config = Config("salt9078563412",
                        UUIDs.UUID("7a2b81c9-f1fa-41de-880d-9635f4741511"),
                        0,
                        "geotherm",
                        0)

function connectDb()
    mongoClient = Mongoc.Client("mongodb://localhost:27017")
    try
        println("Check connection:",Mongoc.ping(mongoClient))
    catch
        print("\nERROR: Cannot connect mongo database!\n")
        exit()
    end
    config.client = mongoClient
    return mongoClient
end

function addUser(alias::String, name::String, org::String,
                 password::String, email::String) :: Result
    client = config.client
    session = client
    db = session[config.dbName]
    coll = db["users"]
    user = Mongoc.BSON()
    user["alias"] = alias
    prev = Mongoc.find_one(coll, user)
    if isnothing(prev)
        user["name"] = name
        user["org"] = org
        user["password"] = SHA.sha256(config.salt * password) |> bytes2hex
        user["email"] = email
        user["emailChecked"] = false
        uuid = UUIDs.uuid5(config.systemUUID, "geotherm-user")
        user["uuid"] = string(uuid)
        push!(coll, user)
        return Result(uuid,OK,"user added")
    else
        println(prev["uuid"])
        return Result(
            prev["uuid"] |> UUIDs.UUID ,
            ERROR, "user exists")
    end
end


function test()
    mongoClient = connectDb()
    println("CFG:", config.client, "\n")
    println(addUser("eugeneai","Evgeny Cherkashin", "ISDCT SB RAS", "passW0rd", "eugeneai@irnok.net"))
end

test()
