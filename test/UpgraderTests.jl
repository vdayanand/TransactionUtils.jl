module UpgraderTests
using ReTest
using Upgrader: Transaction, copy

@testset "Copy test" begin
    mktempdir() do temp
        mktempdir() do temp2
            testfile = joinpath(temp, "ds")
            testfiledest = joinpath(temp2, "ds")
            touch(testfile)
            Transaction("copy test successfull") do u
                copy(u, testfile, testfiledest)
            end
            @test isfile(testfiledest)
            rm(testfiledest, force = true)
            Transaction("copy test faled") do u
                copy(u, testfile, testfiledest)
                ## failed copy, triggers rollback
                copy(u, testfile*"DS", testfiledest)
            end
            @test !isfile(testfiledest)
        end
    end
end

end
