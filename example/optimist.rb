$LOAD_PATH.unshift "lib"

require 'rinda/rinda'
require 'rinda/attempt'

rd, wr = IO.pipe

server = fork do
  rd.close
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  ts.extend Rinda::TupleSpace::Attempt
  
  ts.write [:count, 0]
  
  DRb.start_service(nil, ts)
  wr.puts DRb.uri
  DRb.thread.join
end

wr.close
uri = rd.gets.chomp

def client(svr_uri)
  DRb.start_service
  ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(svr_uri))
  ts.extend Rinda::TupleSpaceProxy::Attempt
  
  tuple = ts.read [:count, nil]
  loop do
    count = tuple[1]
    tuple, entry =
      ts.attempt [:count, count], [:count, count+1], [:count, nil]
    break if entry
    $stderr.puts " "*20 + "pid=#$$ is retrying on #{tuple.inspect}"
  end
  
  $stderr.puts "pid=#$$ incremented #{tuple.inspect}"
end

n = 10

n.times do
  c1 = fork do
    client(uri)
  end
end

n.times do
  Process.wait
end

Process.kill "TERM", server
