$LOAD_PATH.unshift "lib"

$use_take = ARGV.delete("--use-take")

require 'rinda/rinda'
require 'rinda/attempt'
require 'rinda/take-any' if $use_take

rd, wr = IO.pipe

server = fork do
  rd.close
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  ts.extend Rinda::TupleSpace::Attempt
  ts.extend Rinda::TupleSpace::TakeAny if $use_take
  
  ts.write [:answer, :unknown]
  
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
  ts.extend Rinda::TupleSpaceProxy::TakeAny if $use_take
  
  sleep rand(0.0 .. 0.1)
  
  if $use_take
    # alternate implementation using a non-blocking take
    if ts.take_any([:answer, :unknown])
      tuple = [:solver, $$]
      entry = ts.write tuple
    else
      tuple = ts.read [:answer, nil]
      entry = nil
    end

  else
    tuple, entry =
      ts.attempt [:answer, :unknown], [:solver, $$], [:answer, nil]
  end
  
  sleep rand(0.0 .. 0.1)

  if entry
    ts.write [:answer, 42]
    $stderr.puts "pid=#$$ wrote the answer"
  else
    $stderr.puts " "*20 + "pid=#$$ got #{tuple.inspect}"
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
