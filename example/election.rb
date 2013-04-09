$LOAD_PATH.unshift "lib"

$use_establish = ARGV.delete("--use-establish")

require 'rinda/rinda'
require 'rinda/attempt'
require 'rinda/establish' if $use_establish

rd, wr = IO.pipe

server = fork do
  rd.close
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  ts.extend Rinda::TupleSpace::Attempt
  ts.extend Rinda::TupleSpace::Establish if $use_establish
  
  ts.write [:leader_pid, 0] unless $use_establish
  
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
  ts.extend Rinda::TupleSpaceProxy::Establish if $use_establish
  
  sleep rand(0.1 .. 0.2)
  
  if $use_establish
    # alternate implementation using a primitive that expects non-eistence of
    # tuple.
    entry = ts.establish [:leader_pid, nil], [:leader_pid, $$]
    tuple = ts.read [:leader_pid, nil]
  else
    tuple, entry =
      ts.attempt [:leader_pid, 0], [:leader_pid, $$], [:leader_pid, nil]

      # Essentially, the attempt call does the following atomically:
      #
      # if take_nonblock [:leader_pid, 0] is not nil
      #   write [:leader_pid, $$]
      # else
      #   read [:leader_pid, nil] # blocking!
      # end
  end
  
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
