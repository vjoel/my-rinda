$LOAD_PATH.unshift "lib"

require 'rinda/rinda'
require 'rinda/establish'

rd, wr = IO.pipe

server = fork do
  rd.close
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  ts.extend Rinda::TupleSpace::Establish
  
  DRb.start_service(nil, ts)
  wr.puts DRb.uri
  DRb.thread.join
end

wr.close
uri = rd.gets.chomp

def client(svr_uri)
  DRb.start_service
  ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(svr_uri))
  ts.extend Rinda::TupleSpaceProxy::Establish
  
  sleep rand(0.1 .. 0.2)
  
  entry = ts.establish [:tagmap, :mytag, nil], [:tagmap, :mytag, $$]
  if entry
    puts "pid=#$$ won"
  end
end

n = 10

n.times do
  fork do
    client(uri)
  end
end

n.times do
  Process.wait
end

DRb.start_service
ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(uri))
tags = ts.read_all [:tagmap, :mytag, nil]
puts "tagmap = #{tags.inspect}"

Process.kill "TERM", server
