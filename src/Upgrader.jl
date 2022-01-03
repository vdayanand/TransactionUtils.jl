module Upgrader

using Random
using SHA
using JSON

abstract type Resource  end

@enum FileType begin
    JSONFile
    TOMLFile
    YAMLFile
end

struct File <: Resource
    path::String
    File(path::String) = new(abspath(path))
end

struct Transaction
    name::String
    id::String
    proc::Function
    config::Dict{String, Any}
end

const RESOURCE_TYPE_MAP = Dict("file"=>File)

function atomic_copy(src::String, dest::String; force = false)
    path = mktempdir()
    cp(src, path, force = true)
    mv(path, dest; force = force)
end

function Transaction(proc::Function, name::String)
    u = Transaction(replace(name, r"\s"=>"-"), randstring(6), proc, Dict("backups"=>Dict{String, Any}()))
    dir = configdir(u)
    if !isdir(dir)
        mkpath(joinpath(dir, "resource"))
    end
    try
        proc(u)
    catch ex
        @info "failed" ex
        rollback(u)
    end
end

function resource_hash(resource::File)
    return bytes2hex(open(sha256, resource.path))
end

function configdir(u::Transaction)
    root = get(ENV, "UPGRADER_CONFIG_DIR", joinpath(homedir(), ".upgrader"))
    joinpath(root, string(u.name, "-", u.id))
end

function resourcedir(u::Transaction)
    joinpath(configdir(u), "resource")
end

function add!(u::Transaction, key::String, hashconfig::Dict)
    if haskey(u.config["backups"], key)
        error("Duplicate operation on same resource not permitted")
    end
    u.config["backups"][key] = hashconfig
    upgrade_file = joinpath(configdir(u), "upgrade.json")
    open(upgrade_file*".tmp", "w") do f
        JSON.print(f, u.config)
    end
    mv(upgrade_file*".tmp", upgrade_file, force = true)
end

function remove!(u::Transaction, key::String)
    delete!(u.config["backups"], key)
    upgrade_file = joinpath(configdir(u), "upgrade.json")
    open(upgrade_file*".tmp", "w") do f
        JSON.print(f, u.config)
    end
    mv(upgrade_file*".tmp", upgrade_file, force = true)
end

function backup!(u::Transaction, resource::File)
    hash = if isfile(resource.path)
        resource_hash(resource)
    else
        nothing
    end
    if !isnothing(hash)
        backfile = joinpath(resourcedir(u), hash)
        mv(resource.path, backfile, force = true)
        add!(u, resource.path, Dict("type"=> "file", "hash" => hash))
    else
        add!(u, resource.path, Dict("type"=> "file"))
    end
end

function rollback(u::Transaction, _::Type{File}, key::String, config::Dict)
    @info "Rolling back $(key) ..."
    hash = get(config, "hash", nothing)
    if hash != nothing
        backfile = joinpath(resourcedir(u), hash)
        if isfile(backfile) && resource_hash(File(backfile)) == hash
            mv(backfile, key, force=true)
        else
            error("Resource missing unable rollback")
        end
    else
        rm(key, force = true)
    end
    remove!(u, key)
end

function rollback(u::Transaction)
    for (k, v) in u.config["backups"]
        rollback(u, RESOURCE_TYPE_MAP[v["type"]], k, v)
    end
end

function run(u::Transaction, auto_rollback = true)
    try
        u.proc(u)
    catch ex
        @warn "upgrade" failed
        auto_rollback && rollback(u)
    end
end

function copy(u::Transaction, src::String, dest::String)
    backup!(u, File(dest))
    atomic_copy(src, dest, force = true)
end

function remove(u::Transaction, src::String, dest::String)
    backup!(u, File(dest))
    rm(src, dest, force = true, recursive = true)
end

function convert(u::Transaction, src::String, dest::String, src_type::Val{JSONFile}, dest_type::Val{TOMLFile})
    backup!(u, File(dest))
    res = JSON.parsefile(src)
    open(src*".tmp", "w") do f
        TOML.print(f, res)
    end
    mv(src*".tmp", dest, force = true)
end

function convert(u::Transaction, src::String, dest::String, src_type::Val{TOMLFile}, dest_type::Val{JSONFile})
    backup!(u, File(dest))
    res = TOML.parsefile(src)
    open(src*".tmp", "w") do f
        JSON.print(f, res)
    end
    mv(src*".tmp", dest, force = true)
end

function patch(callback::Function, u::Transaction, src::String, src_type::Val{TOMLFile})
    backup!(u, File(src))
    res = TOML.parsefile(src)
    new_res = callback(res)
    open(src*".tmp", "w") do f
        TOML.print(f, new_res)
    end
    mv(src*".tmp", src, force = true)
end

function patch(f::Function, u::Transaction, src::String, src_type::Val{JSONFile})
    backup!(u, File(src))
    res = JSON.parsefile(src)
    new_res = callback(res)
    open(src*".tmp", "w") do f
        JSON.print(f, new_res)
    end
    mv(src*".tmp", src, force = true)
end


end # module
