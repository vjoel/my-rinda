$LOAD_PATH.unshift "lib"

require 'rinda/rinda'
require 'rinda/attempt'

rd, wr = IO.pipe

server = fork do
  rd.close
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  ts.extend Rinda::TupleSpace::Attempt
  
  ts.write [:leader_pid, 0]
  
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
  
  sleep rand(0.1 .. 0.2)
  
  tuple, entry =
    ts.attempt [:leader_pid, 0], [:leader_pid, $$], [:leader_pid, nil]

    # Essentially, the attempt call does the following atomically:
    #
    # if take_nonblock [:leader_pid, 0] is not nil
    #   write [:leader_pid, $$]
    # else
    #   read [:leader_pid, nil] # blocking!
    # end
  
  if entry
    $stderr.puts "pid=#$$ is the leader: #{tuple.inspect}"
  else
    $stderr.puts " "*20 + "pid=#$$ is following #{tuple.inspect}"
  end
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
