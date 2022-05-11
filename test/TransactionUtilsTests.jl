module TransactionUtilsTests
using ReTest
using TransactionUtils: Transaction, copy, remove, JSONFile, patch, TOMLFile, convert, rollback, EnvFile, DotEnv
using JSON
using TOML

@testset "Copy test" begin
    mktempdir() do src
        mktempdir() do dest
            srcfile = joinpath(src, "ds")
            destfile = joinpath(dest, "ds")
            touch(srcfile)
            Transaction("copy-test-successfull") do u
                copy(u, srcfile, destfile)
            end
            @test isfile(destfile)
            rm(destfile, force = true)
            Transaction("copy-test-falied") do u
                copy(u, srcfile, destfile)
                ## failed since modifying backed up resource within a Transaction is not allowed, triggers rollback
                copy(u, srcfile, destfile)
            end
            @test !isfile(destfile)
            src_dir = joinpath(src, "srcdir")
            testfile = joinpath(src_dir, "A")
            mkpath(src_dir)
            touch(testfile)
            dest_dir = joinpath(dest, "destdir")
            Transaction("copy-directory-successfull") do u
                copy(u, src_dir, dest_dir)
            end
            @test isdir(dest_dir)
            @test isfile(joinpath(dest_dir, "A"))
            rm(dest_dir, force=true, recursive=true)
            Transaction("copy-directory-successfull") do u
                copy(u, src_dir, dest_dir)
                ## failed since modifying backed up resource within a Transaction is not allowed, triggers rollback
                copy(u, src_dir, dest_dir)
            end
            @test !isdir(dest_dir)

            ## lets try dest non empty
            mkpath(dest_dir)
            touch(joinpath(dest_dir, "B"))
            Transaction("copy-directory-failed:-destination-non-empty") do u
                copy(u, src_dir, dest_dir)
                copy(u, src_dir, dest_dir)
            end
            @test isdir(dest_dir)
            @test isfile(joinpath(dest_dir, "B"))
            Transaction("copy-directory-success:-destination-non-empty") do u
                copy(u, src_dir, dest_dir)
            end
            @test isdir(dest_dir)
            @test isfile(joinpath(dest_dir, "A"))
        end
    end
end


@testset "Remove test" begin
    mktempdir() do src
        mktempdir() do dest
            destfile = joinpath(dest, "ds")
            touch(destfile)
            Transaction("remove-test-successfull") do u
                remove(u, destfile)
            end
            @test !isfile(destfile)
            touch(destfile)
            Transaction("remove-test-successfull") do u
                remove(u, destfile)
                remove(u, destfile)
            end
            @test isfile(destfile)
        end
    end
end

@testset "patch test" begin
    mktempdir() do src
        mktempdir() do dest
            destfile = joinpath(dest, "ds")
            open(destfile, "w") do f
                JSON.print(f, Dict("test" => "hello"))
            end
            @info JSON.parsefile(destfile)
            Transaction("patch-json-successfull") do u
                patch(u, destfile, Val{JSONFile}()) do res
                    res["test"] = "hellow2"
                    res
                end
            end
            @test JSON.parsefile(destfile)["test"] == "hellow2"
            Transaction("patch-json-failed") do u
                patch(u, destfile, Val{JSONFile}()) do res
                    res["test"] = "hellow3"
                    res
                end
                ## fails
                patch(u, destfile, Val{JSONFile}()) do res
                    res["test"] = "hellow3"
                    res
                end
            end
            @test JSON.parsefile(destfile)["test"] == "hellow2"
        end
    end
end

@testset "convert test" begin
    mktempdir() do src
        mktempdir() do dest
            destfile = joinpath(dest, "ds")
            open(destfile, "w") do f
                JSON.print(f, Dict("test" => "hello"))
            end
            Transaction("patch-json-successfull") do u
                convert(u, destfile, Val{JSONFile}(), Val{TOMLFile}())
            end
            @test TOML.parsefile(destfile)["test"] == "hello"
            rm(destfile, force = true)
            open(destfile, "w") do f
                JSON.print(f, Dict("test" => "hello"))
            end
            Transaction("patch-json-failed") do u
                convert(u, destfile, Val{JSONFile}(), Val{TOMLFile}())
                convert(u, destfile, Val{JSONFile}(), Val{TOMLFile}())
            end
            @test JSON.parsefile(destfile)["test"] == "hello"
        end
    end
end

@testset "rollback test" begin
    mktempdir() do src
        mktempdir() do dest
            destfile = joinpath(dest, "ds")
            open(destfile, "w") do f
                JSON.print(f, Dict("test" => "hello"))
            end
            t = Transaction("convert-json-successfull") do u
                convert(u, destfile, Val{JSONFile}(), Val{TOMLFile}())
                return u
            end
            @test TOML.parsefile(destfile)["test"] == "hello"
            rollback(t)
            @test JSON.parsefile(destfile)["test"] == "hello"
            @test isnothing(rollback(t))
        end
    end
end

@testset "env patch test" begin
    mktempdir() do src
        mktempdir() do dest
            destfile = joinpath(dest, "ds")
            open(destfile, "w") do f
                DotEnv.print(f, Dict("test" => "hello"))
            end
            t  = Transaction("patch-test-envfile") do u
                patch(u, destfile, Val{EnvFile}()) do res
                    res["test"] = "hellow3"
                    res
                end
            end
            @test DotEnv.parse(destfile)["test"] == "hellow3"
            rollback(t)
            @test DotEnv.parse(destfile)["test"] == "hello"
        end
    end
end

end
