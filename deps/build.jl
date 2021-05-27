cd(@__DIR__)
println("building...")
println(@__DIR__)
cd("../dats/pbesol/v1.2/")
run(`tar -xf els.tar`)
run(`tar -xf binary.tar`)
cd(@__DIR__)


