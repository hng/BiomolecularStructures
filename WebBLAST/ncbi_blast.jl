
using HttpCommon
using Requests
using LightXML
using FastaIO

# BLAST API base url
base_url = "http://blast.ncbi.nlm.nih.gov/Blast.cgi"

# generic web api call
function call_api(;args...)
    query_string = ""
    for (k, v) in args
        if typeof(v) == ASCIIString
            v = encodeURI(v)
        end
        k = uppercase(string(k))
        if query_string != ""
            query_string = "$(query_string)&$(k)=$(v)"
        else
            query_string = "?$(k)=$(v)"
        end
    end
    
    query_string = "$(base_url)$(query_string)"

    return get(query_string)

end

function read_sequence(args) 
  if length(args["fasta"]) == 2

    try
      fasta = FastaReader(args["fasta"][1])
      name = ""
      seq = ""
      try
        for i in range(1,int(args["fasta"][2]))
          name, seq = readentry(fasta)
        end
        
      catch 
        error("Error parsing arguments. Check 'em!")
      end
      return seq
    catch GZError
      error("File not found")
    end

  end

  if args["sequence"] != ""
    return args["sequence"]
  end

end

function ncbi_blast_search_info(rid)

  searching = false

  while true
    sleep(5)
    response = call_api(cmd="Get", format_object="SearchInfo", rid=rid).data
    # check status codes
    if ismatch(r"Status=WAITING", response)
      
      if searching
        print(".")
      else 
        print("Searching...")
        searching = true
      end
      continue
    end

    if ismatch(r"Status=FAILED", response)
      println("Search $( rid ) failed; please report to blast-help\@ncbi.nlm.nih.gov.\n")
      return false
    end

    if ismatch(r"Status=UNKNOWN", response)
      println("Search $( rid ) expired.\n")
      return false
    end

    if ismatch(r"Status=READY", response)
      return true
    end


    println("Something went wrong...\n")
    return false
  end
end

function ncbi_blast_get_results(rid)
  content = call_api(cmd="Get", rid=rid, format_type="XML").data
  xml_doc = parse_string(content)

  xroot = root(xml_doc)
  c_nodes = child_nodes(xroot)
  hits = 0

  for c in child_nodes(xroot)
    if is_elementnode(c)
       e1 = XMLElement(c)
       if name(e1) == "BlastOutput_iterations"
          e2 = find_element(e1, "Iteration")
          e3 = find_element(e2, "Iteration_hits")

          hits = get_elements_by_tagname(e3, "Hit")

       end
    end
  end
  
  if hits != 0
      for hit in hits
        
        hitdict = attributes_dict(hit)
        println(hitdict)

        hit_id = find_element(hit, "Hit_id")
        hit_id_content = first(collect(child_nodes(hit_id))) 
        
        #this_hit = Hit("hit_id_content")
        println(hit_id_content)
     end
  end
end

# returns the RID of the query
function ncbi_blast_put(query, database="nr", program="blastp", hitlist_size=500)
  response = call_api(cmd="Put", QUERY=query, DATABASE=database, program=program, HITLIST_SZE=hitlist_size)

  m = match(r"RID = (.*)\n", response.data)
  rtoe = match(r"RTOE = (.*)\n", response.data)

  return (m.captures[1],rtoe.captures[1])
end
