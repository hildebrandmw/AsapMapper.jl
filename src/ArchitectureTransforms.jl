#=
A collection of transforms that will run on a created architecture. 
This will probably be used to set metadata fields for various components to
include runtime variations such as different max frequencies, maybe voltage
characteristics etc.
=#
function set_asap3_frequencies(arch)
    # Read the frequencies JSON file
    filepath = joinpath(PKGDIR, "frequencies", "frequencies.json.gz")
    println(filepath, "r")
    f = GZip.open(filepath)
    jsn = JSON.parse(f)
    close(f)
    # For now, just grab the first entry from the json dict
    frequency_dict = first(values(jsn))
    # The frequency dictionary should contain keys that are strings of the form
    # "(a,b)" and floating point values. 
    #
    # I'll call "parse" on the tuple strings to make tuples which can then be
    # turned into addresses.
    
    # Make an array to collect all the frequencies seen. This will be useful for
    # later processing when assigning a metric to task and processor.
    frequency_vector = Float64[]
    for (addr_tuple_string,freq) in frequency_dict
        # Get an address from the tuple string
        local addr_tuple
        try
            addr_tuple = eval(parse(addr_tuple_string))
        catch
            continue
        end
        if !(typeof(addr_tuple) <: Tuple)
            continue
        end
        # Add offset (1,1) to adjust for 0 based indexing
        addr = Address(addr_tuple) + Address(1,2)
        # Use this to index into the architecture
        if haskey(arch.children, addr)
            c = arch.children[addr]
            # Check to see if this component has a child named "processor"
            if haskey(c.children, "processor")
                c.children["processor"].metadata["max_frequency"] = freq
                push!(frequency_vector, freq)
            else
                println(addr, " does not have a processor.")
            end
        else
            println(addr, " not present in architecture.")
        end
    end
    arch.metadata["frequencies"] = frequency_vector
    return
end
