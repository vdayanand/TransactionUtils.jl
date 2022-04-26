module DotEnv

# modified version of https://github.com/vmari/DotEnv.jl/blob/master/src/DotEnv.jl
function parse(src::String)
    return open(src, "r") do f
        parse(f)
    end
end

function parse(src::IO)
    res = Dict{String,String}()
    for line in eachline(src)
        m = match(r"^\s*([\w.-]+)\s*=\s*(.*)?\s*$", line)
        if m !== nothing
            key = m.captures[1]
            value = string(m.captures[2])
            if (length(value) > 0 && value[1] === '"' && value[end] === '"')
                value = replace(value, r"\\n"m => "\n")
            end
            value = replace(value, r"(^['\u0022]|['\u0022]$)" => "")
            value = strip(value)
            push!(res, Pair(key, value) )
        end
    end
    res
end
function Base.print(io::IO, content::Dict{String, String})
    for(k, v) in content
        write(io, "$(k)=$(v)\n")
    end
end
end
