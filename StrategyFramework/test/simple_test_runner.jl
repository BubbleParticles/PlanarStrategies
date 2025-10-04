# Simple test runner that tests individual utility functions without full module loading
using Test

# Add the src directory to the load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

# Test individual utility files
println("Testing math utilities...")
include("test_math_utils_standalone.jl")

println("Testing async utilities...")
include("test_async_utils_standalone.jl")

println("Testing parameter management...")
include("test_parameters_simple.jl")

println("Testing integration scenarios...")
include("integration_tests.jl")

println("All tests completed!")