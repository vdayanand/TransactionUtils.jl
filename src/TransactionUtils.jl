module TransactionUtils

using Random
using SHA
using JSON
using TOML

abstract type Resource  end
export Transaction, copy, remove, convert, patch, JSONFile, TOMLFile

function pprint_exception(e)
    eio = IOBuffer()
    Base.showerror(eio, e, catch_backtrace())
    @error String(take!(eio))
end

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

function Transaction(id::String)
    arr = string.(split(id, "-"))
    name == arr[1]
    id == arr[2]
    root = get(ENV, "TRANSACTION_CONFIG_DIR", joinpath(homedir(), ".transaction"))
    Transaction(name, id, x->x, JSON.parsefile(joinpath(root, string(name, "-", id), "transaction.json")))
end

function Transaction(proc::Function, name::String; auto_rollback = true, verbose = false)
    u = Transaction(replace(name, r"\s"=>"-"), randstring(6), proc, Dict("backups"=>Dict{String, Any}()))
    dir = configdir(u)
    if !isdir(dir)
        mkpath(joinpath(dir, "resource"))
    end
    try
        @info "Running Transaction ... $(name)"
        proc(u)
        @info "Completed Transaction ... $(name)"
    catch ex
        auto_rollback && rollback(u)
        if verbose
            pprint_exception(ex)
        else
             @warn "Failed ... $(name) due to $(ex)"
        end
    end
end

function resource_hash(resource::File)
    return bytes2hex(open(sha256, resource.path))
end

function configdir(u::Transaction)
    root = get(ENV, "TRANSACTION_CONFIG_DIR", joinpath(homedir(), ".transaction"))
    joinpath(root, string(u.name, "-", u.id))
end

function resourcedir(u::Transaction)
    joinpath(configdir(u), "resource")
end

function resource_backed(u::Transaction, key::String)
    haskey(u.config["backups"], key)
end

function add!(u::Transaction, key::String, hashconfig::Dict)
    u.config["backups"][key] = hashconfig
    @debug "Persisting backup structure for rollback $(key)" hashconfig
    upgrade_file = joinpath(configdir(u), "transaction.json")
    open(upgrade_file*".tmp", "w") do f
        JSON.print(f, u.config)
    end
    mv(upgrade_file*".tmp", upgrade_file, force = true)
end

function remove!(u::Transaction, key::String)
    delete!(u.config["backups"], key)
    upgrade_file = joinpath(configdir(u), "transaction.json")
    open(upgrade_file*".tmp", "w") do f
        JSON.print(f, u.config)
    end
    mv(upgrade_file*".tmp", upgrade_file, force = true)
end

function backup!(u::Transaction, resource::File)
    if resource_backed(u, resource.path)
        error("Backing up resource $(resource.path) within same transaction not allowed")
    end
    if islink(resource.path)
        error("Links not supported")
    end
    @debug "backing up $(resource.path)"
    hash = if isfile(resource.path) || isdir(resource.path)
        resource_hash(resource)
    else
        nothing
    end
    @debug "Generated debug hash" hash
    if !isnothing(hash)
        backfile = joinpath(resourcedir(u), hash)
        @debug "Taking backup of $(resource.path) to $(backfile)"
        atomic_copy(resource.path, backfile, force = true)
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
        if (isfile(backfile) || isdir(backfile)) && resource_hash(File(backfile)) == hash
            mv(backfile, key, force=true)
        else
            error("Resource missing unable rollback")
        end
    else
        rm(key, force = true, recursive=true)
    end
    remove!(u, key)
end

function rollback(u::Transaction)
    for (k, v) in u.config["backups"]
        @info "Key v $(k) $(v)"
        rollback(u, RESOURCE_TYPE_MAP[v["type"]], k, v)
    end
end

function copy(u::Transaction, src::String, dest::String)
    backup!(u, File(dest))
    if !isfile(src) && !isdir(src))
        error("Resource $(src) not found")
    end

    atomic_copy(src, dest, force = true)
end

function remove(u::Transaction, dest::String)
    backup!(u, File(dest))
    rm(dest, force = true, recursive = true)
end

function convert(u::Transaction, dest::String, src_type::Val{JSONFile}, dest_type::Val{TOMLFile})
    backup!(u, File(dest))
    res = JSON.parsefile(dest)
    open(dest*".tmp", "w") do f
        TOML.print(f, res)
    end
    mv(dest*".tmp", dest, force = true)
end

function convert(u::Transaction,  dest::String, src_type::Val{TOMLFile}, dest_type::Val{JSONFile})
    backup!(u, File(dest))
    res = TOML.parsefile(dest)
    open(dest*".tmp", "w") do f
        JSON.print(f, res)
    end
    mv(dest*".tmp", dest, force = true)
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

function patch(callback::Function, u::Transaction, src::String, src_type::Val{JSONFile})
    backup!(u, File(src))
    res = JSON.parsefile(src)
    new_res = callback(res)
    open(src*".tmp", "w") do f
        JSON.print(f, new_res)
    end
    mv(src*".tmp", src, force = true)
end


end # module
