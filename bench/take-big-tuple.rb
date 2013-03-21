$LOAD_PATH.unshift "lib"

n = 10
depth = 6
width = 6

# setting 
#   n = 10
#   depth = 6
#   width = 6
#
# results in about a factor of two difference:
#
# before fix
#
#   $ ruby bench.rb
#   time = 3.020
#
# after fix
#
#   $ ruby bench.rb
#   time = 1.350

def fill d, w
  if d == 0
    return {}
  end
  h = {}
  w.times do |i|
    h[i] = fill(d - 1, w)
  end
  h
end
payload = fill(depth, width)


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
  n.times do
    ts.take([nil])
  end
end

c2 = fork do
  DRb.start_service
  ts = Rinda::TupleSpaceProxy.new(DRbObject.new_with_uri(uri))
  n.times do
    ts.write([payload])
  end
end

Process.wait c2
Process.wait c1

t1 = Process.times.to_a.inject{|s,x|s+x}

printf "time = %.2f\n", t1 - t0

Process.kill "TERM", server
