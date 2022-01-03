module TransactionUtilsTests
using ReTest
using TransactionUtils: Transaction, copy, remove, JSONFile, patch
using JSON

@testset "Copy test" begin
    mktempdir() do src
        mktempdir() do dest
            srcfile = joinpath(src, "ds")
            destfile = joinpath(dest, "ds")
            touch(srcfile)
            Transaction("copy test successfull") do u
                copy(u, srcfile, destfile)
            end
            @test isfile(destfile)
            rm(destfile, force = true)
            Transaction("copy test falied") do u
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
            Transaction("copy directory successfull") do u
                copy(u, src_dir, dest_dir)
            end
            @test isdir(dest_dir)
            @test isfile(joinpath(dest_dir, "A"))
            rm(dest_dir, force=true, recursive=true)
            Transaction("copy directory successfull") do u
                copy(u, src_dir, dest_dir)
                ## failed since modifying backed up resource within a Transaction is not allowed, triggers rollback
                copy(u, src_dir, dest_dir)
            end
            @test !isdir(dest_dir)
        end
    end
end


@testset "Remove test" begin
    mktempdir() do src
        mktempdir() do dest
            destfile = joinpath(dest, "ds")
            touch(destfile)
            Transaction("remove test successfull") do u
                remove(u, destfile)
            end
            @test !isfile(destfile)
            touch(destfile)
            Transaction("remove test successfull") do u
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
            Transaction("patch json successfull") do u
                patch(u, destfile, Val{JSONFile}()) do res
                    res["test"] = "hellow2"
                    res
                end
            end
            @test JSON.parsefile(destfile)["test"] == "hellow2"
            Transaction("patch json failed") do u
                patch(u, destfile, Val{JSONFile}()) do res
                    res["test"] = "hellow2"
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

end
