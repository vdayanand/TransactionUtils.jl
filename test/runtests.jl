using ReTest, Upgrader
include("UpgraderTests.jl")
retest(Upgrader, UpgraderTests)
