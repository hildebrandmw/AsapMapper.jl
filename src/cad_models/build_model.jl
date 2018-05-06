function build_model(name::String, A)

  num_fifos = 2

  f = open(name * ".json")
  s = JSON.parse(f)

  arch = TopLevel{A,2}(s["name"])
  row = s["dimensions"]["row"]
  col = s["dimensions"]["column"]
  lev = s["dimensions"]["level"]
  proc_add = s["processor_tile"]["add"]
  proc_remove = s["processor_tile"]["remove"]
  mem_proc_add = s["memory_processor_tile"]["add"]
  mem_proc_remove = s["memory_processor_tile"]["remove"]
  one_port = s["memory"]["1_port"]
  two_port = s["memory"]["2_port"]
  num_links = s["configurations"]["num_links"]
  in_handler = s["input_handler"]
  out_handler = s["output_handler"]

  close(f)

  processor = build_processor_tile(num_links)
  if lev > 0
    for r in 0:row-1, c in 0:col-1, l in 0:lev-1
      (in("($r,$c,$l)",proc_remove) || in("($r,$c,$l)",one_port)
       || in("($r,$c,$l)",two_port) || in("($r,$c,$l)",mem_proc_add)
       || in("($r,$c,$l)",mem_proc_remove)) && continue
      add_child(arch, processor, CartesianIndex(r,c,l))
    end
    for proc in proc_add
      r, c, l = stringtoindex3(proc)
      add_child(arch, processor, CartesianIndex(r,c,l))
    end
  elseif lev == 0
    for r in 0:row-1, c in 0:col-1
      (in("($r,$c)",proc_remove) || in("($r,$c)",one_port)
       || in("($r,$c)",two_port) || in("($r,$c)",mem_proc_add)
       || in("($r,$c)",mem_proc_remove)) && continue
      add_child(arch, processor, CartesianIndex(r,c))
    end
    for proc in proc_add
      r, c = stringtoindex2(proc)
      add_child(arch, processor, CartesianIndex(r,c))
    end
  end

  memory_processor = build_processor_tile(num_links, include_memory = true)
  if lev > 0
    for proc in mem_proc_add
      r, c, l = stringtoindex3(proc)
      add_child(arch, memory_processor, CartesianIndex(r,c,l))
    end
  elseif lev == 0
    for proc in mem_proc_add
      r, c = stringtoindex2(proc)
      add_child(arch, memory_processor, CartesianIndex(r,c))
    end
  end

  memory_2port = build_memory(2)
  if lev > 0
    for mem in two_port
      r, c, l = stringtoindex3(mem)
      add_child(arch, memory_2port, CartesianIndex(r,c,l))
    end
  elseif lev == 0
    for mem in two_port
      r, c = stringtoindex2(mem)
      add_child(arch, memory_2port, CartesianIndex(r,c))
    end
  end

  memory_1port = build_memory(2)
  if lev > 0
    for mem in one_port
      r, c, l = stringtoindex3(mem)
      add_child(arch, memory_1port, CartesianIndex(r,c,l))
    end
  elseif lev == 0
    for mem in one_port
      r, c = stringtoindex2(mem)
      add_child(arch, memory_1port, CartesianIndex(r,c))
    end
  end

  input_handler = build_input_handler(1)
  if lev > 0
    for handler in in_handler
      r,c,l = stringtoindex3(handler)
      add_child(arch, input_handler, CartesianIndex(r,c,l))
    end
  elseif lev == 0
    for handler in in_handler
      r,c = stringtoindex2(handler)
      add_child(arch, input_handler, CartesianIndex(r,c))
    end
  end

  output_handler = build_output_handler(1)
  if lev > 0
    for handler in out_handler
      r,c,l = stringtoindex3(handler)
      add_child(arch, output_handler, CartesianIndex(r,c,l))
    end
  elseif lev == 0
    for handler in out_handler
      r,c = stringtoindex2(handler)
      add_child(arch, output_handler, CartesianIndex(r,c))
    end
  end

  connect_processors(arch, num_links)
  connect_io(arch, num_links)
  connect_memories(arch)
  return arch
end

function stringtoindex2(string)

  row,column = split(string,",")
  row = parse(Int64,split(row,"(")[2])
  column = parse(Int64,split(column,")")[1])

  return row, column
end

function stringtoindex3(string)

  row,column,level = split(string,",")
  row = parse(Int64,split(row,"(")[2])
  column = parse(Int64,column)
  level = parse(Int64,split(column,")")[1])

  return row, column, level
end
