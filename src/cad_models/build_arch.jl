function build_arch(name::String,A)
    num_fifos = 2

    f = open(name * ".json")
    s = JSON.parse(f)

    arch = TopLevel{A,2}(s["name"])
    row = s["dimensions"]["row"]
    col = s["dimensions"]["column"]
    processor_add = s["processor_tile"]["add"]
    processor_remove = s["processor_tile"]["remove"]
    one_port = s["memory"]["1_port"]
    two_port = s["memory"]["2_port"]
    num_links = s["configurations"]["num_links"]
    input_handler = s["input_handler"]
    output_handler = s["output_handler"]
    special_mem_connection = s["configurations"]["special_mem_connection"]


    # memories connected in a non-asap way are dealt with below
    offset = Array{Tuple{Int64,Int64},1}()
    if(special_mem_connection)
      tmp = s["configurations"]["offsets"]
      for off in tmp
        push!(offset, stringtotuple(off))
      end
    end

    close(f)

    # preallocate arrays to store Tuple addresses
    in_addr = Array{Tuple{Int64,Int64},1}()
    out_addr = Array{Tuple{Int64,Int64},1}()
    proc = Array{Tuple{Int64,Int64},1}()

    # push the tuples into their respective arrays
    for handler in input_handler
      push!(in_addr,stringtotuple(handler))
    end
    for handler in output_handler
      push!(out_addr,stringtotuple(handler))
    end

    # get all the processors
    # add/remove processors to and from the processor array
    for r in 0:row-1, c in 0:col-1
      match = false
      for rem in processor_remove
        if(rem == "($r,$c)")
          match = true
        end
      end
      match && continue
      push!(proc,(r,c))
    end
    for p in processor_add
      push!(proc,stringtotuple(p))
    end

    one_port_mem = Array{Tuple{Int64,Int64},1}()
    two_port_mem = Array{Tuple{Int64,Int64},1}()
    memory_1port = Array{AsapMapper.MemoryLocation{2},1}()
    memory_2port = Array{AsapMapper.MemoryLocation{2},1}()
    extra_two_port_mem = Array{Tuple{Int64,Int64},1}()

    # get all mems
    count = 1
    for mem in one_port
      addr = stringtotuple(mem)
      push!(one_port_mem,addr)
      if(special_mem_connection)
        push!(memory_1port, MemoryLocation(addr,[offset[count]]))
        count += 1
      else
        push!(memory_1port, MemoryLocation(addr,[(-1,0)]))
      end
    end
    for mem in two_port
      addr = stringtotuple(mem)
      push!(two_port_mem,addr)
      if(special_mem_connection)
        second_address = other_address(addr,offset,count)
        push!(memory_2port, MemoryLocation(addr,second_address,[offset[count],offset[count+1]]))
        push!(extra_two_port_mem,second_address)
        count += 2
      else
        push!(memory_2port, MemoryLocation(addr,[(-1,0),(-1,1)]))
      end
    end
    mem_neighbor_addrs = vcat(mem_neighbor(memory_2port),mem_neighbor(memory_1port))

    ####################
    # Normal Processor #
    ####################
    # Get a processor tile and instantiate it.
    processor = build_processor_tile(num_links)
    for p in proc
      overlap = false
      one_match = false
      two_match = false
      ex_two_match = false
      for mem_neighbor_addr in mem_neighbor_addrs
        if(mem_neighbor_addr == CartesianIndex(p[1],p[2]))
          overlap = true
        end
      end
      for mem in one_port_mem
        if(mem == (p[1],p[2]))
          one_match = true
        end
      end
      for mem in two_port_mem
        if(mem == (p[1],p[2]))
          two_match = true
        end
      end
      for mem in extra_two_port_mem
        if(mem == (p[1],p[2]))
          ex_two_match = true
        end
      end
      (overlap || one_match || two_match || ex_two_match) && continue
      add_child(arch, processor, CartesianIndex(p[1],p[2]))
    end

    ####################
    # Memory Processor #
    ####################
    # Instantiate a memory processor at every address neighboring a memory.
    memory_processor = build_processor_tile(num_links, include_memory = true)
    for mem_neighbor_addr in mem_neighbor_addrs
      add_child(arch, memory_processor, mem_neighbor_addr)
    end

    #################
    # 2 Port Memory #
    #################
    memory_twoport = build_memory(2)
    for mem in two_port_mem
          add_child(arch, memory_twoport, CartesianIndex(mem[1],mem[2]))
    end

    #################
    # 1 Port Memory #
    #################
    memory_oneport = build_memory(2)
    for mem in one_port_mem
          add_child(arch, memory_oneport, CartesianIndex(mem[1],mem[2]))
    end

    #################
    # Input Handler #
    #################
    input_handler = build_input_handler(1)
    for handler in in_addr
      add_child(arch, input_handler, CartesianIndex(handler[1],handler[2]))
    end

    ##################
    # Output Handler #
    ##################
    output_handler = build_output_handler(1)
    for handler in out_addr
      add_child(arch, output_handler, CartesianIndex(handler[1],handler[2]))
    end

    connect_processors(arch, num_links)
    connect_io(arch, num_links)
    if (special_mem_connection)
      if(one_port_mem != nothing)
        connect_memories_cluster(arch, memory_1port)
      end
      if(two_port_mem != nothing)
        connect_memories_cluster(arch, memory_2port)
      end
    else
      connect_memories(arch)
    end

    return arch
end

function stringtotuple(string)

  row,column = split(string,",")
  row = parse(Int64,split(row,"(")[2])
  column = parse(Int64,split(column,")")[1])

  return (row,column)
end

function other_address(addr, offset, count)
  if(offset[count][1] != offset[count+1][1])
    second_addr = (addr[1]+offset[count+1][1],addr[2])
  elseif(offset[count][2] != offset[count+1][2])
    second_addr =  (addr[1],addr[2]+offset[count+1][2])
  end
  return second_addr
end
