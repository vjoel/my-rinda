$LOAD_PATH.unshift "lib"

require 'rinda/rinda'
require 'rinda/replace-all'

rd, wr = IO.pipe

server = fork do
  rd.close
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  ts.extend Rinda::TupleSpace::ReplaceAll
  DRb.start_service(nil, ts)
  wr.puts DRb.uri
  DRb.thread.join
end

wr.close
uri = rd.gets.chomp

c1 = fork do
  DRb.start_service
  ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(uri))
  ts.extend Rinda::TupleSpaceProxy::ReplaceAll
  
  # This seems to solve the problem noted on p.176 of The dRuby Book, without
  # adding a global lock (other than the #synchronize).
  
  def ts.[](key)
    tuples = read_all [key, nil]
    t = tuples.first # assume no duplicates
    t && t[1]
  end
  
  def ts.[]=(key, value)
    replace_all [key, nil], [key, value]
  end

  p ts.read_all [nil, nil]
  puts [ts["pres"], ts["veep"]].join("-")

  ts["pres"] = "Bush"
  ts["veep"] = "Cheney"
  
  p ts.read_all [nil, nil]
  puts [ts["pres"], ts["veep"]].join("-")
  
  ts["pres"] = "Obama"
  ts["veep"] = "Biden"
  
  p ts.read_all [nil, nil]
  puts [ts["pres"], ts["veep"]].join("-")
end

Process.wait c1

Process.kill "TERM", server
