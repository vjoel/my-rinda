# benchmark that does a lot of write and take ops, but all tuples are small and
# the tuplespace is small.

$LOAD_PATH.unshift "lib"

require 'rinda/rinda'

rd, wr = IO.pipe

server = fork do
  rd.close
  require 'rinda/tuplespace'
  ts = Rinda::TupleSpace.new
  DRb.start_service(nil, ts)
  wr.puts DRb.uri
  DRb.thread.join
end

wr.close
uri = rd.gets.chomp

t0 = Process.times.to_a.inject{|s,x|s+x}

c1 = fork do
  DRb.start_service
  ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(uri))
  
  n = 1000
  
  n.times do |i|
    ts.write([i])
    ts.take([nil])
  end
end

Process.wait c1

t1 = Process.times.to_a.inject{|s,x|s+x}

printf "time = %.2f\n", t1 - t0

Process.kill "TERM", server
